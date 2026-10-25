#!/usr/bin/env python3
"""Strip only debug metadata in a development .app, then repair ad-hoc seals.

Never accepts a production signing identity. No exported symbols, architecture
slices, framework symlinks, install names, or loadable sections may change.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from xml.parsers.expat import ExpatError

from native_artifact_sections import (
    loadable_fingerprint, macho_indirect_fingerprint, macho_linkedit_fingerprint,
    macho_slices, sections,
)


def command(arguments: list[str]) -> bytes:
    # Diagnostics may contain source paths. Do not echo tool output on failure.
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f"{Path(arguments[0]).name} failed (exit {result.returncode})")
    return result.stdout + result.stderr


@dataclass(frozen=True)
class DebugState:
    architecture: str
    dwarf: bool
    stabs: bool

    @property
    def category(self) -> str:
        if self.dwarf and self.stabs:
            return "DEBUG_BOTH_REMAIN"
        if self.dwarf:
            return "DEBUG_DWARF_SECTION_REMAINS"
        return "DEBUG_STABS_REMAINS" if self.stabs else "DEBUG_METADATA_CLEARED"


def debug_states(data: bytes) -> list[DebugState]:
    if data[:4] not in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"):
        if data[:4] in (b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf",
                        b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"):
            raise ValueError("MACHO_FORMAT_OR_SLICES_INVALID")
        return []
    result = []
    for payload in macho_slices(data):
        _, ranges = sections(payload)
        cpu = struct.unpack_from("<I", payload, 4)[0]
        architecture = {0x1000007: "X86_64", 0x100000c: "ARM64"}.get(cpu, "OTHER_64")
        dwarf = any(s.name.startswith("__DWARF,") and s.size for s in ranges)
        table = next((s for s in ranges if s.name == "symbol-table"), None)
        strings = next((s for s in ranges if s.name == "symbol-strings"), None)
        marker_context = False
        pos = 32
        for _ in range(struct.unpack_from("<I", payload, 16)[0]):
            command, size = struct.unpack_from("<II", payload, pos)
            if command == 0xb and size == 80:
                first_local, local_count = struct.unpack_from("<II", payload, pos + 8)
                indirect_offset, indirect_count = struct.unpack_from("<II", payload, pos + 56)
                marker_context = (table is not None and first_local == 0
                                  and 0 < local_count <= table.size // 16 and indirect_count > 0
                                  and indirect_offset + indirect_count * 4 <= len(payload))
            pos += size
        stabs = False
        if table is not None and strings is not None:
            names = payload[strings.offset:strings.offset + strings.size]
            for pos in range(table.offset, table.offset + table.size, 16):
                name, kind, section, description, value = struct.unpack_from("<IBBHQ", payload, pos)
                if not kind & 0xe0:
                    continue
                # Apple cctools inserts this exact N_OPT at local index zero
                # for dyld radar 5614542, including after strip -S. It is not
                # source debugging information. No other N_OPT/STABS is exempt.
                marker = (marker_context and pos == table.offset
                          and (kind, section, description, value) == (0x3c, 0, 0, 0x05614542)
                          and names[name:name + 15] == b"radr://5614542\0")
                stabs |= not marker
        result.append(DebugState(architecture, bool(dwarf), stabs))
    return result


def has_debug(data: bytes) -> bool:
    return any(state.dwarf or state.stabs for state in debug_states(data))


def report_debug(index: int, phase: str, data: bytes) -> None:
    for state in debug_states(data):
        print(f"MACHO_DEBUG_{phase}: binary_index={index} architecture={state.architecture} "
              f"dwarf={int(state.dwarf)} stabs={int(state.stabs)} state={state.category}", flush=True)


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
        state["indirect"] = macho_indirect_fingerprint(data)
    except (ValueError, IndexError, struct.error):
        raise ValueError("LINKEDIT_OR_DYLD_INVALID") from None
    return state


def contract_failures(before: dict, after: dict) -> list[str]:
    # Compare independently: one failure must not hide the other invariants.
    fields = {
        "shape": "MACHO_FORMAT_OR_SLICES_CHANGED",
        "loadable": "LOADABLE_SECTIONS_CHANGED",
        "linkedit": "LINKEDIT_OR_DYLD_CHANGED",
        "indirect": "LINKEDIT_OR_DYLD_CHANGED",
        "exports": "EXPORTED_SYMBOLS_CHANGED",
        "architectures": "CPU_ARCHITECTURES_CHANGED",
        "links": "DYLIB_DEPENDENCY_OR_INSTALL_NAME_CHANGED",
    }
    failures = list(dict.fromkeys(category for field, category in fields.items()
                                  if before[field] != after[field]))
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


def require_adhoc_seal(path: Path) -> None:
    executable = path
    if path.is_dir():
        is_app = path.suffix == ".app"
        plists = [path / "Contents/Info.plist"] if is_app else [
            path / "Resources/Info.plist", path / "Info.plist"]
        try:
            names = {plistlib.loads(p.read_bytes())["CFBundleExecutable"] for p in plists if p.is_file()}
            name, = names
            if not isinstance(name, str) or not name or name in (".", "..") or Path(name).name != name:
                raise ValueError()
            executable = (path / "Contents/MacOS" if is_app else path) / name
            if not executable.is_file() or not executable.resolve().is_relative_to(path.resolve()):
                raise ValueError()
        except (OSError, ValueError, TypeError, KeyError, ExpatError, plistlib.InvalidFileException):
            raise ValueError("MACHO_BUNDLE_METADATA_INVALID") from None
    slices = macho_slices(executable.read_bytes())
    # codesign display defaults to the host architecture, whereas signing
    # changes ALL slices. Inspect each actual architecture before any mutation.
    architectures = command(["xcrun", "lipo", "-archs", str(executable)]).split()
    if (len(architectures) != len(slices) or len(set(architectures)) != len(slices)
            or any(re.fullmatch(rb"[a-zA-Z0-9_]+", arch) is None for arch in architectures)):
        raise RuntimeError("MACHO_ARCHITECTURE_METADATA_INVALID")
    for architecture in architectures:
        signature = command(["codesign", "-dv", "--architecture", architecture.decode("ascii"), str(path)])
        if b"Signature=adhoc" not in signature.splitlines():
            raise ValueError("refusing non-ad-hoc signed binary")


def prepare_copy(app: Path) -> None:
    root = app.resolve()
    entries = list(app.rglob("*"))
    for entry in entries:
        if entry.is_symlink():
            try:
                target = entry.resolve(strict=True)
            except (OSError, RuntimeError):
                raise ValueError("FRAMEWORK_SYMLINK_INVALID") from None
            if not target.is_relative_to(root):
                raise ValueError("framework symlink leaves application")
    files = sorted({p.resolve() for p in entries if p.is_file()})
    candidates = []
    bundles = {root}
    binary_index = 0
    for path in files:
        if not path.is_relative_to(root):
            raise ValueError("framework symlink leaves application")
        data = path.read_bytes()
        if not debug_states(data):
            continue
        binary_index += 1
        # Validate indirect targets even when only Apple's marker is present.
        try:
            macho_indirect_fingerprint(data)
        except (ValueError, IndexError, struct.error):
            raise RuntimeError("LINKEDIT_OR_DYLD_INVALID") from None
        report_debug(binary_index, "BEFORE", data)
        if not has_debug(data):
            continue
        candidates.append((binary_index, path))
        bundles.update(parent for parent in path.parents
                       if parent.is_relative_to(root) and parent.suffix in (".framework", ".app"))
    if not candidates:
        command(["codesign", "--verify", "--deep", "--strict", str(app)])
        return
    # Preflight ALL affected seals before modifying ANY file. Unrelated
    # frameworks are neither stripped nor re-signed.
    for path in [*(path for _, path in candidates), *bundles]:
        require_adhoc_seal(path)
    before_states = {}
    for index, path in candidates:
        # Record progress without publishing build roots or symbol names.
        print(f"MACHO_STRIP_BEGIN: binary_index={index}", flush=True)
        before = native_snapshot(path)
        before_states[path] = before
        command(["xcrun", "strip", "-S", str(path)])
        report_debug(index, "AFTER", path.read_bytes())
        failures = contract_failures(before, native_snapshot(path))
        if failures:
            raise RuntimeError("debug strip changed runtime contract; refuse packaging: "
                               + ",".join(failures))
        print(f"MACHO_RUNTIME_CONTRACT_PASS: binary_index={index} phase=STRIP")
        print(f"DEBUG_METADATA_STRIPPED: binary_index={index}")
    # Inner-to-outer signing, never --deep signing. Keep entitlements/flags and
    # existing development identity. The final audit runs after these seals.
    seals = bundles | {p for _, p in candidates if p.parent.suffix not in (".framework", ".app")}
    for bundle in sorted(seals, key=lambda p: (len(p.parts), str(p)), reverse=True):
        command(["codesign", "--force", "--sign", "-",
                 "--preserve-metadata=identifier,entitlements,requirements,flags,runtime",
                 str(bundle)])
    command(["codesign", "--verify", "--deep", "--strict", str(app)])
    for index, path in candidates:
        failures = contract_failures(before_states[path], native_snapshot(path))
        if failures:
            raise RuntimeError("signing changed runtime contract; refuse packaging: " + ",".join(failures))
        print(f"MACHO_RUNTIME_CONTRACT_PASS: binary_index={index} phase=SIGN")


def prepare(app: Path) -> None:
    if sys.platform != "darwin":
        raise RuntimeError("requires native macOS Xcode tools")
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("expected an existing development .app")
    root = app.resolve()
    workspace = Path(tempfile.mkdtemp(prefix=".fura-macos-debug-", dir=root.parent))
    backup = workspace / "backup" / root.name
    preserve_backup = False
    committed = False
    try:
        staged = workspace / root.name
        shutil.copytree(root, staged, symlinks=True)
        prepare_copy(staged)
        backup.parent.mkdir()
        try:
            os.replace(root, backup)
            os.replace(staged, root)
            command(["codesign", "--verify", "--deep", "--strict", str(root)])
        except BaseException as error:
            try:
                if backup.exists():
                    if root.exists():
                        os.replace(root, staged)
                    os.replace(backup, root)
            except BaseException:
                preserve_backup = True
                raise RuntimeError("MACHO_APP_ROLLBACK_FAILED: PRIVATE_BACKUP_RETAINED") from None
            if isinstance(error, OSError):
                raise RuntimeError("MACHO_APP_INSTALL_FAILED: ORIGINAL_RESTORED") from None
            raise
        committed = True
    finally:
        # Also retain the original if interruption occurs between renames.
        # A hard process kill cannot run rollback, but never deletes the backup.
        if not preserve_backup and (committed or not backup.exists()):
            shutil.rmtree(workspace)


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
