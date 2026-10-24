#!/usr/bin/env python3
"""Reproduce committed upstream fingerprints from independently fetched archives.

No networking and no policy generation/writing: changing a release requires a
new investigation and review, not an automatic policy update in CI.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import tarfile
import zipfile
from pathlib import Path

from audit_artifact_privacy import scan_payload, forbidden_patterns
from native_artifact_sections import loadable_fingerprint, macho_linkedit_fingerprint, sections


def verify(android_arm64: Path, android_x64: Path, macos: Path) -> None:
    policy = json.loads(Path(__file__).with_name("upstream_media_privacy.json").read_text())
    payloads = {}
    for source, path in zip(policy["sources"], (android_arm64, android_x64, macos), strict=True):
        if hashlib.sha256(path.read_bytes()).hexdigest() != source["sha256"]:
            raise ValueError("upstream archive digest mismatch")
    for abi, path in (("arm64-v8a", android_arm64), ("x86_64", android_x64)):
        with zipfile.ZipFile(path) as archive:
            name = f"lib/{abi}/libmpv.so"
            payloads[name] = archive.read(name)
    with tarfile.open(macos) as archive:
        for member in archive:
            parts = member.name.split("/")
            if (member.isfile() and len(parts) >= 4 and "/Versions/A/" in member.name
                    and parts[-4] == parts[-1] + ".framework"):
                payloads["Contents/Frameworks/" + "/".join(parts[-4:])] = archive.extractfile(member).read()
    for record in policy["payloads"]:
        data = payloads[record["payload"]]
        if hashlib.sha256(data).hexdigest() != record["upstream_sha256"]:
            raise ValueError("upstream payload digest mismatch")
        fmt, ranges = sections(data)
        if fmt != record["format"]:
            raise ValueError("upstream payload format mismatch")
        if fmt == "Mach-O" and loadable_fingerprint(data, ranges) != record["loadable_sha256"]:
            raise ValueError("upstream loadable fingerprint mismatch")
        if fmt == "Mach-O" and macho_linkedit_fingerprint(data) != record["linkedit_sha256"]:
            raise ValueError("upstream runtime linkedit mismatch")
        for string in record["strings"]:
            found = False
            for section in ranges:
                if section.name == string["section"]:
                    for value in data[section.offset:section.offset + section.size].split(b"\0"):
                        found |= len(value) == string["length"] and hashlib.sha256(value).hexdigest() == string["sha256"]
            if not found:
                raise ValueError("upstream runtime string fingerprint mismatch")
        # ELF upstream is already stripped. Mach-O debug-symbol paths remain
        # intentionally rejected until a standard strip has removed them.
        if fmt == "ELF" and scan_payload(data, forbidden_patterns([record["root"]]), record["payload"]):
            raise ValueError("upstream ELF has unclassified path occurrences")
        print(f"UPSTREAM_EVIDENCE_VERIFIED: {record['payload']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("android_arm64", type=Path)
    parser.add_argument("android_x64", type=Path)
    parser.add_argument("macos", type=Path)
    args = parser.parse_args()
    verify(args.android_arm64, args.android_x64, args.macos)
