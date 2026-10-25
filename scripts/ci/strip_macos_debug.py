#!/usr/bin/env python3
"""Strip only debug metadata in a development .app, then repair ad-hoc seals.

Never accepts a production signing identity. No exported symbols, architecture
slices, framework symlinks, install names, or loadable sections may change.
"""

from __future__ import annotations

import argparse
import struct
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


def container_shape(data: bytes) -> tuple[str, int]:
    if data[:4] == b"\xca\xfe\xba\xbe":
        count = struct.unpack_from(">I", data, 4)[0]
        if 0 < count <= 16:
            occupied = []
            for index in range(count):
                _, _, offset, extent, _ = struct.unpack_from(">IIIII", data, 8 + index * 20)
                if (offset < 8 + count * 20 or extent < 32 or offset + extent > len(data)
                        or data[offset:offset + 4] != b"\xcf\xfa\xed\xfe"
                        or any(a < offset + extent and offset < b for a, b in occupied)):
                    raise ValueError("MACHO_FORMAT_OR_SLICES_INVALID")
                occupied.append((offset, offset + extent))
            return "universal64", count
    elif data[:4] == b"\xcf\xfa\xed\xfe":
        return "thin64", 1
    raise ValueError("MACHO_FORMAT_OR_SLICES_INVALID")


def snapshot(data: bytes) -> dict:
    fmt, ranges = sections(data)
    if fmt != "Mach-O":
        raise ValueError("MACHO_FORMAT_OR_SLICES_INVALID")
    state = {
        "shape": container_shape(data),
        "loadable": loadable_fingerprint(data, ranges),
        "debug": has_debug(data),
    }
    try:
        state["linkedit"] = macho_linkedit_fingerprint(data)
    except (ValueError, IndexError, struct.error):
        raise ValueError("LINKEDIT_OR_DYLD_INVALID") from None
    return state


def contract_failures(before: dict, after: dict) -> list[str]:
    # Compare independently: one failure must not hide the other invariants.
    fields = {
        "shape": "MACHO_FORMAT_OR_SLICES_CHANGED",
        "loadable": "LOADABLE_SECTIONS_CHANGED",
        "linkedit": "LINKEDIT_OR_DYLD_CHANGED",
        "exports": "EXPORTED_SYMBOLS_CHANGED",
        "architectures": "CPU_ARCHITECTURES_CHANGED",
        "links": "DYLIB_DEPENDENCY_OR_INSTALL_NAME_CHANGED",
    }
    failures = [category for field, category in fields.items() if before[field] != after[field]]
    if after["debug"]:
        failures.append("DEBUG_METADATA_REMAINS")
    return failures


def native_snapshot(path: Path) -> dict:
    try:
        state = snapshot(path.read_bytes())
    except ValueError as error:
        category = ("LINKEDIT_OR_DYLD_INVALID" if str(error) == "LINKEDIT_OR_DYLD_INVALID"
                    else "MACHO_FORMAT_OR_SLICES_INVALID")
        raise RuntimeError(category) from None
    except (IndexError, struct.error):
        raise RuntimeError("MACHO_FORMAT_OR_SLICES_INVALID") from None
    state["exports"] = command(["xcrun", "nm", "-gjU", str(path)])
    state["architectures"] = command(["xcrun", "lipo", "-archs", str(path)])
    state["links"] = command(["xcrun", "otool", "-L", str(path)])
    return state


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
    for index, path in enumerate(candidates, 1):
        # Record progress without publishing build roots or symbol names.
        print(f"MACHO_STRIP_BEGIN: binary_index={index}", flush=True)
        before = native_snapshot(path)
        command(["xcrun", "strip", "-S", str(path)])
        failures = contract_failures(before, native_snapshot(path))
        if failures:
            raise RuntimeError("debug strip changed runtime contract; refuse packaging: "
                               + ",".join(failures))
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
    except OSError:
        raise SystemExit("MACHO_ARTIFACT_READ_OR_WRITE_FAILED") from None
