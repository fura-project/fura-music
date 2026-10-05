#!/usr/bin/env python3
"""Fail when first-party tracked files expose Fura maintainer identity or secrets."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path, PurePosixPath


PERSONAL_MARKER = bytes.fromhex("617869616f626f").decode("ascii")
OLD_APPLICATION_ID = f"dev.{PERSONAL_MARKER}.flutterustmusic"
TEXT_SUFFIXES = {
    "",
    ".cmake",
    ".dart",
    ".desktop",
    ".kt",
    ".kts",
    ".md",
    ".pbxproj",
    ".plist",
    ".py",
    ".rc",
    ".rs",
    ".sh",
    ".toml",
    ".txt",
    ".xcconfig",
    ".xml",
    ".yaml",
    ".yml",
}
EXCLUDED_PREFIXES = (
    "third_party/",
    "vendor/",
)
SENSITIVE_EXACT_NAMES = {
    ".env",
    "GoogleService-Info.plist",
    "google-services.json",
    "key.properties",
}
SENSITIVE_SUFFIXES = {
    ".jks",
    ".keystore",
    ".mobileprovision",
    ".p12",
    ".pem",
    ".pfx",
}
SAFE_ENV_TEMPLATE_SUFFIXES = (".example", ".sample", ".template")


def tracked_files(repo_root: Path) -> list[Path]:
    output = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=repo_root,
    )
    return [repo_root / item.decode("utf-8") for item in output.split(b"\0") if item]


def relative_path(repo_root: Path, path: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def is_third_party(relative: str) -> bool:
    return relative.startswith(EXCLUDED_PREFIXES) or any(
        part in {"third_party", "vendor"} for part in PurePosixPath(relative).parts
    )


def sensitive_filename_class(relative: str) -> str | None:
    name = PurePosixPath(relative).name
    lower_name = name.lower()
    if name in SENSITIVE_EXACT_NAMES:
        return "SENSITIVE_FILENAME"
    if lower_name.startswith(".env.") and not lower_name.endswith(
        SAFE_ENV_TEMPLATE_SUFFIXES
    ):
        return "SENSITIVE_FILENAME"
    if PurePosixPath(relative).suffix.lower() in SENSITIVE_SUFFIXES:
        return "SENSITIVE_FILENAME"
    return None


def content_findings(data: bytes) -> set[str]:
    lower = data.lower()
    findings: set[str] = set()
    if OLD_APPLICATION_ID.encode("ascii") in lower:
        findings.add("PERSONAL_APP_ID_FOUND")
    if PERSONAL_MARKER.encode("ascii") in lower:
        findings.add("PERSONAL_MARKER_FOUND")
    personal_home_patterns = (
        f"/home/{PERSONAL_MARKER}/".encode("ascii"),
        f"/users/{PERSONAL_MARKER}/".encode("ascii"),
        f"c:\\users\\{PERSONAL_MARKER}\\".encode("ascii"),
    )
    if any(pattern in lower for pattern in personal_home_patterns):
        findings.add("ABSOLUTE_MAINTAINER_HOME_FOUND")
    if re.search(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", data):
        findings.add("PRIVATE_KEY_MATERIAL_FOUND")
    return findings


def audit(repo_root: Path) -> list[tuple[str, str]]:
    findings: list[tuple[str, str]] = []
    for path in tracked_files(repo_root):
        relative = relative_path(repo_root, path)
        if is_third_party(relative):
            continue
        sensitive_class = sensitive_filename_class(relative)
        if sensitive_class is not None:
            findings.append((sensitive_class, relative))
        if path.suffix.lower() not in TEXT_SUFFIXES or not path.is_file():
            continue
        data = path.read_bytes()
        if b"\0" in data:
            continue
        findings.extend((finding, relative) for finding in content_findings(data))
    return sorted(set(findings))


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    findings = audit(repo_root)
    if findings:
        for finding, relative in findings:
            print(f"{finding}: {relative}", file=sys.stderr)
        return 1
    print("privacy hygiene audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
