#!/usr/bin/env python3
"""Scan distributable artifacts without printing matched sensitive bytes."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import struct
import sys
import zipfile
from collections.abc import Iterable
from functools import lru_cache
from pathlib import Path

from native_artifact_sections import loadable_fingerprint, macho_linkedit_fingerprint, sections


UPSTREAM_PAYLOADS = json.loads(
    Path(__file__).with_name("upstream_media_privacy.json").read_text()
)["payloads"]


PERSONAL_MARKER = bytes.fromhex("617869616f626f").decode("ascii")
OLD_APPLICATION_ID = f"dev.{PERSONAL_MARKER}.flutterustmusic"


def iter_files(paths: Iterable[Path]) -> Iterable[Path]:
    for path in paths:
        if path.is_dir():
            yield from (candidate for candidate in path.rglob("*") if candidate.is_file())
        elif path.is_file():
            yield path
        else:
            raise FileNotFoundError(path)


def forbidden_patterns(roots: Iterable[str]) -> dict[str, bytes]:
    patterns = {
        "PERSONAL_APP_ID_FOUND": OLD_APPLICATION_ID.encode("ascii"),
        "PERSONAL_MARKER_FOUND": PERSONAL_MARKER.encode("ascii"),
    }
    for index, root in enumerate(roots):
        if not root:
            continue
        # A Windows root supplied on another host is still a Windows root.
        normalized = root if re.match(r"^[A-Za-z]:[\\/]", root) else str(Path(root).resolve())
        encoded = normalized.replace("\\", "/").rstrip("/").encode("utf-8")
        patterns[f"ABSOLUTE_BUILD_PATH_FOUND_{index + 1}"] = encoded
        patterns[f"ABSOLUTE_BUILD_PATH_WINDOWS_FOUND_{index + 1}"] = encoded.replace(
            b"/", b"\\"
        )
    return patterns


def scan_bytes(data: bytes, patterns: dict[str, bytes]) -> set[str]:
    lower = data.lower()
    return {
        label
        for label, pattern in patterns.items()
        if pattern and any(regex.search(lower) for regex in pattern_regexes(pattern))
    }


@lru_cache(maxsize=128)
def pattern_regexes(pattern: bytes) -> tuple[re.Pattern[bytes], ...]:
    text = pattern.decode("utf-8")
    # Windows accepts mixed separators too. Match complete encoded characters
    # (not individual UTF-16 bytes), retaining offsets for exact classification.
    return tuple(re.compile(b"".join(
        b"(?:" + re.escape("/".encode(codec)) + b"|" + re.escape("\\".encode(codec)) + b")"
        if char in "/\\" else b"(?:" + b"|".join(sorted({
            re.escape(value.encode(codec).lower())
            for value in (char, char.lower(), char.upper(), char.casefold())
        })) + b")"
        for char in text
    )) for codec in ("utf-8", "utf-16le", "utf-16be"))


def approved_upstream_ranges(data: bytes, payload: str) -> list[tuple[int, int]]:
    """Classify only independently reproduced public upstream runtime strings.

    Never applies to first-party payloads, debug paths, arbitrary third-party
    names or an entire section. Binary provenance AND each complete NUL string
    must match. Personal identifiers are never filtered, even in approved data.
    """
    normalized = payload.replace("\\", "/").replace("!", "/")
    fmt, ranges = sections(data)
    for record in UPSTREAM_PAYLOADS:
        canonical = record["payload"]
        if not (normalized == canonical or normalized.endswith("/" + canonical)):
            continue
        if fmt != record["format"]:
            continue
        if fmt == "ELF":
            if hashlib.sha256(data).hexdigest() != record["upstream_sha256"]:
                continue
        elif loadable_fingerprint(data, ranges) != record["loadable_sha256"]:
            continue
        if fmt == "Mach-O":
            try:
                if macho_linkedit_fingerprint(data) != record["linkedit_sha256"]:
                    continue
            except (ValueError, struct.error):
                continue  # malformed or ABI-altered upstream is not evidence
        allowed = {(s["section"], s["length"], s["sha256"]) for s in record["strings"]}
        result = []
        for section in ranges:
            if section.name not in {s[0] for s in allowed}:
                continue
            start = section.offset
            end = start + section.size
            while start < end:
                stop = data.find(b"\0", start, end)
                if stop < 0:
                    break
                string = data[start:stop]
                key = (section.name, len(string), hashlib.sha256(string).hexdigest())
                if key in allowed:
                    # Only classify the exact public upstream root occurrences,
                    # not every possible forbidden pattern inside this string.
                    for match in re.finditer(re.escape(record["root"].encode()), string):
                        result.append((start + match.start(), start + match.end()))
                start = stop + 1
        return result
    return []


def scan_payload(data: bytes, patterns: dict[str, bytes], payload: str,
                 delegated: list[tuple[int, int]] | None = None,
                 diagnostics: list[dict] | None = None) -> set[str]:
    approved = approved_upstream_ranges(data, payload)
    lower = data.lower()
    findings = set()
    for label, pattern in patterns.items():
        for regex in pattern_regexes(pattern):
            for match in regex.finditer(lower):
                if delegated and any(a <= match.start() and match.end() <= b
                                     for a, b in delegated):
                    continue  # stored member bytes are audited recursively below
                classified = label.startswith("ABSOLUTE_BUILD_PATH") and any(
                    a == match.start() and b == match.end() for a, b in approved
                )
                if diagnostics is not None:
                    fmt, ranges = sections(data)
                    section = next((s.name for s in ranges if s.offset <= match.start()
                                    and match.end() <= s.offset + s.size), "unmapped")
                    diagnostics.append({
                        "file": safe_display(payload, patterns), "category": label,
                        "format": fmt, "section": safe_display(section, patterns),
                        "offset": match.start(), "stage": "final-artifact",
                        "provenance": "PINNED_UPSTREAM_RUNTIME_STRING" if classified else "UNCLASSIFIED_REJECTED",
                    })
                if classified:
                    continue
                findings.add(label)
    return findings


def scan_archive_or_payload(data: bytes, patterns: dict[str, bytes], payload: str,
                            depth: int = 0, diagnostics: list[dict] | None = None) -> list[tuple[str, str]]:
    stream = io.BytesIO(data)
    findings = []
    delegated = []
    if zipfile.is_zipfile(stream):
        if depth >= 8:
            return [("ARCHIVE_DEPTH_EXCEEDED", payload)]
        with zipfile.ZipFile(stream) as archive:
            for item in archive.infolist():
                if item.is_dir():
                    continue
                member = archive.read(item)  # also verifies ZIP CRC
                identity = f"{payload}!{item.filename}"
                findings.extend(scan_archive_or_payload(member, patterns, identity, depth + 1, diagnostics))
                # Do not report a second copy of uncompressed member bytes as
                # a container hit. Headers, names, extras, comments, prefix and
                # trailer remain scanned, as do all compressed payload bytes.
                if item.compress_type == zipfile.ZIP_STORED:
                    name_size, extra_size = struct.unpack_from("<HH", data, item.header_offset + 26)
                    offset = item.header_offset + 30 + name_size + extra_size
                    if data[offset:offset + len(member)] == member:
                        delegated.append((offset, offset + len(member)))
    findings.extend((label, payload) for label in scan_payload(data, patterns, payload, delegated, diagnostics))
    return findings


def scan_file(path: Path, patterns: dict[str, bytes], diagnostics: list[dict] | None = None) -> list[tuple[str, str]]:
    # Resolve framework aliases so one binary has the same provenance check
    # through Versions/A and the framework-root symlink.
    return scan_archive_or_payload(path.read_bytes(), patterns, str(path.resolve()), diagnostics=diagnostics)


def safe_display(value: str, patterns: dict[str, bytes]) -> str:
    for pattern in sorted(patterns.values(), key=len, reverse=True):
        expression = "".join(r"[\\/]" if char in "/\\" else re.escape(char)
                             for char in pattern.decode("utf-8"))
        value = re.sub(expression, "<redacted>", value, flags=re.IGNORECASE)
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--forbidden-root", action="append", default=[])
    parser.add_argument("--diagnose", action="store_true",
                        help="emit categories/section offsets, never matched bytes")
    args = parser.parse_args()
    patterns = forbidden_patterns(args.forbidden_root)
    findings: list[tuple[str, str]] = []
    diagnostics = [] if args.diagnose else None
    try:
        for path in iter_files(args.paths):
            findings.extend(scan_file(path, patterns, diagnostics))
    except (OSError, ValueError, RuntimeError, struct.error, zipfile.BadZipFile):
        # ZIP/tool exceptions can contain an attacker-supplied entry name or
        # private source path. Parsing failure is fatal, not an empty audit.
        print("ARTIFACT_READ_OR_PARSE_FAILED", file=sys.stderr)
        return 1
    if diagnostics is not None:
        for diagnostic in diagnostics:
            print(json.dumps(diagnostic, ensure_ascii=True), file=sys.stderr)
    if findings:
        for finding, path in sorted(set(findings)):
            # A caller may pass an absolute artifact path. Do not echo even
            # that path's private root (or an unsafe ZIP entry name).
            print(f"{finding}: {safe_display(path, patterns)}", file=sys.stderr)
        return 1
    print("artifact privacy audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
