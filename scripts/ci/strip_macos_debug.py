#!/usr/bin/env python3
"""Strip only debug metadata in a development .app, then repair ad-hoc seals.

Never accepts a production signing identity. No exported symbols, architecture
slices, framework symlinks, install names, or loadable sections may change.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from native_artifact_sections import loadable_fingerprint, macho_linkedit_fingerprint, sections


def command(arguments: list[str]) -> bytes:
    # Diagnostics may contain source paths. Do not echo tool output on failure.
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f"{Path(arguments[0]).name} failed (exit {result.returncode})")
    return result.stdout + result.stderr


def has_debug(data: bytes) -> bool:
    fmt, ranges = sections(data)
    if fmt != "Mach-O":
        return False
    if any(s.name.startswith("__DWARF,") and s.size for s in ranges):
        return True
    # nlist_64.n_type & N_STAB. N_OSO strings belong to debugger provenance,
    # not the dynamic export table (and are removed by Apple's strip -S).
    return any(data[i + 4] & 0xe0 for s in ranges if s.name == "symbol-table"
               for i in range(s.offset, s.offset + s.size, 16))


def prepare(app: Path) -> None:
    if sys.platform != "darwin":
        raise RuntimeError("requires native macOS Xcode tools")
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("expected an existing development .app")
    files = sorted({p.resolve() for p in app.rglob("*") if p.is_file()})
    root = app.resolve()
    candidates = []
    bundles = {root}
    for path in files:
        if not path.is_relative_to(root):
            raise ValueError("framework symlink leaves application")
        data = path.read_bytes()
        if not has_debug(data):
            continue
        candidates.append(path)
        bundles.update(parent for parent in path.parents
                       if parent.is_relative_to(root) and parent.suffix in (".framework", ".app"))
    if not candidates:
        return
    # Preflight ALL affected seals before modifying ANY file. Unrelated
    # frameworks are neither stripped nor re-signed.
    for path in [*candidates, *bundles]:
        signature = command(["codesign", "-dv", str(path)])
        if b"Signature=adhoc" not in signature:
            raise ValueError("refusing non-ad-hoc signed binary")
    for path in candidates:
        data = path.read_bytes()
        before_format, before_sections = sections(data)
        before_fingerprint = loadable_fingerprint(data, before_sections)
        before_linkedit = macho_linkedit_fingerprint(data)
        exports = command(["xcrun", "nm", "-gjU", str(path)])
        architectures = command(["xcrun", "lipo", "-archs", str(path)])
        links = command(["xcrun", "otool", "-L", str(path)])
        command(["xcrun", "strip", "-S", str(path)])
        after = path.read_bytes()
        fmt, after_sections = sections(after)
        if (fmt != before_format or has_debug(after) or
                loadable_fingerprint(after, after_sections) != before_fingerprint or
                macho_linkedit_fingerprint(after) != before_linkedit or
                command(["xcrun", "nm", "-gjU", str(path)]) != exports or
                command(["xcrun", "lipo", "-archs", str(path)]) != architectures or
                command(["xcrun", "otool", "-L", str(path)]) != links):
            raise RuntimeError("debug strip changed runtime contract; refuse packaging")
        print(f"DEBUG_METADATA_STRIPPED: {path.relative_to(root)}")
    # Inner-to-outer signing, never --deep signing. Keep entitlements/flags and
    # existing development identity. The final audit runs after these seals.
    seals = bundles | {p for p in candidates if p.parent.suffix not in (".framework", ".app")}
    for bundle in sorted(seals, key=lambda p: len(p.parts), reverse=True):
        command(["codesign", "--force", "--sign", "-",
                 "--preserve-metadata=identifier,entitlements,requirements,flags,runtime",
                 str(bundle)])
    command(["codesign", "--verify", "--deep", "--strict", str(app)])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    try:
        prepare(args.app)
    except (ValueError, RuntimeError) as error:
        raise SystemExit(str(error)) from None
