#!/usr/bin/env python3
"""Scan distributable artifacts without printing matched sensitive bytes."""

from __future__ import annotations

import argparse
import sys
import zipfile
from collections.abc import Iterable
from pathlib import Path


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
        encoded = str(Path(root).resolve()).encode("utf-8")
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
        if pattern and pattern.lower() in lower
    }


def scan_file(path: Path, patterns: dict[str, bytes]) -> list[tuple[str, str]]:
    findings = [
        (label, str(path)) for label in scan_bytes(path.read_bytes(), patterns)
    ]
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            for item in archive.infolist():
                if item.is_dir():
                    continue
                data = archive.read(item)
                findings.extend(
                    (label, f"{path}!{item.filename}")
                    for label in scan_bytes(data, patterns)
                )
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--forbidden-root", action="append", default=[])
    args = parser.parse_args()
    patterns = forbidden_patterns(args.forbidden_root)
    findings: list[tuple[str, str]] = []
    for path in iter_files(args.paths):
        findings.extend(scan_file(path, patterns))
    if findings:
        for finding, path in sorted(set(findings)):
            print(f"{finding}: {path}", file=sys.stderr)
        return 1
    print("artifact privacy audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
