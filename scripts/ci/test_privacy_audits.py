#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import contextlib
import hashlib
import io
import json
import os
import plistlib
import shutil
import shlex
import sys
import struct
import subprocess
import tempfile
import unittest
import zipfile
from contextlib import nullcontext
from pathlib import Path, PureWindowsPath
from unittest.mock import patch


SCRIPT_DIRECTORY = Path(__file__).resolve().parent


def load_module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIRECTORY / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {filename}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


source_audit = load_module("source_audit", "audit_privacy_hygiene.py")
artifact_audit = load_module("artifact_audit", "audit_artifact_privacy.py")
package_config = load_module(
    "prepare_flutter_package_config", "prepare_flutter_package_config.py"
)
privacy_build = load_module("privacy_build", "build_flutter_with_privacy.py")
mac_strip = load_module("mac_strip", "strip_macos_debug.py")
native_sections = load_module("native_sections", "native_artifact_sections.py")


def elf_fixture(content: bytes) -> bytes:
    names = b"\0.rodata\0.shstrtab\0"
    header = bytearray(64)
    header[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<Q", header, 40, 64)
    struct.pack_into("<HHH", header, 58, 64, 3, 2)
    zero = bytes(64)
    rodata = struct.pack("<IIQQQQIIQQ", 1, 1, 2, 0, 256, len(content), 0, 0, 1, 0)
    strings = struct.pack("<IIQQQQIIQQ", 9, 3, 0, 0, 256 + len(content), len(names), 0, 0, 1, 0)
    return bytes(header) + zero + rodata + strings + content + names


def indirect_macho_fixture(target: int = 8) -> bytes:
    names = b"\0_alias\0_target\0_other\0"
    header = struct.pack("<IIIIIIII", 0xfeedfacf, 0x1000007, 3, 6, 1, 24, 0, 0)
    command = struct.pack("<IIIIII", 2, 24, 56, 1, 72, len(names))
    symbol = struct.pack("<IBBHQ", 1, 0xb, 0, 0, target)
    return header + command + symbol + names


def runtime_macho_fixture(content: bytes, target: int = 8) -> bytes:
    names = b"\0_alias\0_target\0_other\0"
    header = struct.pack("<IIIIIIII", 0xfeedfacf, 0x1000007, 3, 6, 2, 176, 0, 0)
    segment = bytearray(152)
    struct.pack_into("<II", segment, 0, 0x19, 152)
    struct.pack_into("<I", segment, 64, 1)
    segment[72:88] = b"__cstring".ljust(16, b"\0")
    segment[88:104] = b"__TEXT".ljust(16, b"\0")
    struct.pack_into("<QI", segment, 112, len(content), 224 + len(names))
    command = struct.pack("<IIIIII", 2, 24, 208, 1, 224, len(names))
    symbol = struct.pack("<IBBHQ", 1, 0xb, 0, 0, target)
    return header + segment + command + symbol + names + content


def debug_macho_fixture(*, dwarf=False, stabs=False, marker=False, cpu=0x1000007) -> bytes:
    """Synthetic nlist/dyld fixture, not an executable or native strip result."""
    names = bytearray(b"\0")
    symbols = []
    def symbol(name, kind, section=0, description=0, value=0):
        index = len(names)
        names.extend(name + b"\0")
        symbols.append(struct.pack("<IBBHQ", index, kind, section, description, value))
    if marker:
        symbol(b"radr://5614542", 0x3c, value=0x05614542)
    if stabs:
        symbol(b"/synthetic-private-builder/source.o", 0x66)
    local_count = len(symbols)
    symbol(b"_entry", 0xf, section=1, value=0x1000)
    symbol(b"_puts", 0x1, description=0x100)
    text = b"synthetic-code!!"
    debug = b"/synthetic-private-builder/source.cc\0" if dwarf else b""
    command_bytes = 152 + (152 if dwarf else 0) + 24 + 80 + 48
    text_offset = 32 + command_bytes
    symbol_offset = text_offset + len(text) + len(debug)
    string_offset = symbol_offset + 16 * len(symbols)
    indirect_offset = string_offset + len(names)
    bind_offset = indirect_offset + 4
    def segment(segname, sectname, offset, size):
        result = bytearray(152)
        struct.pack_into("<II", result, 0, 0x19, 152)
        result[8:24] = segname.ljust(16, b"\0")
        struct.pack_into("<I", result, 64, 1)
        result[72:88] = sectname.ljust(16, b"\0")
        result[88:104] = segname.ljust(16, b"\0")
        struct.pack_into("<QI", result, 112, size, offset)
        return result
    commands = segment(b"__TEXT", b"__text", text_offset, len(text))
    if dwarf:
        commands += segment(b"__DWARF", b"__debug_info", text_offset + len(text), len(debug))
    commands += struct.pack("<IIIIII", 2, 24, symbol_offset, len(symbols), string_offset, len(names))
    dysymtab = [0xb, 80, 0, local_count, local_count, 1, local_count + 1, 1,
                0, 0, 0, 0, 0, 0, indirect_offset, 1, 0, 0, 0, 0]
    commands += struct.pack("<20I", *dysymtab)
    commands += struct.pack("<12I", 0x80000022, 48, 0, 0, bind_offset, 4, 0, 0, 0, 0, 0, 0)
    header = struct.pack("<8I", 0xfeedfacf, cpu, 0, 6, 4 + int(dwarf), command_bytes, 4, 0)
    return header + commands + text + debug + b"".join(symbols) + names + struct.pack("<I", local_count + 1) + b"bind"


def universal_macho_fixture(*slices: bytes) -> bytes:
    result = bytearray(8 + 20 * len(slices))
    struct.pack_into(">II", result, 0, 0xcafebabe, len(slices))
    for index, data in enumerate(slices):
        offset = len(result)
        cpu, subtype = struct.unpack_from("<II", data, 4)
        struct.pack_into(">IIIII", result, 8 + 20 * index, cpu, subtype, offset, len(data), 0)
        result.extend(data)
    return bytes(result)


def add_bundle_metadata_fixture(app: Path, framework: Path | None = None) -> None:
    runner = app / "Contents/MacOS/runner"
    runner.parent.mkdir(parents=True, exist_ok=True)
    runner.write_bytes(debug_macho_fixture(marker=True))
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "runner"}))
    if framework is not None:
        resources = framework / "Versions/A/Resources"
        resources.mkdir(parents=True, exist_ok=True)
        (resources / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": framework.stem}))
        (framework / "Resources").symlink_to("Versions/A/Resources")
        if not (framework / framework.stem).is_symlink():
            (framework / framework.stem).symlink_to("Versions/A/" + framework.stem)


def fake_native_metadata(args) -> bytes:
    if "lipo" in args:
        return b" ".join(state.architecture.lower().encode()
                         for state in mac_strip.debug_states(Path(args[-1]).read_bytes()))
    return b"Signature=adhoc" if args[0] == "codesign" else b"stable-native-metadata"


class PrivacyAuditTests(unittest.TestCase):
    def test_apple_strip_compatibility_marker_is_not_source_debug_metadata(self) -> None:
        # Apple's cctools strip synthesizes this exact N_OPT record when an
        # indirect table needs a nonzero first external-symbol index.
        data = debug_macho_fixture(marker=True)
        self.assertFalse(mac_strip.has_debug(data))
        self.assertTrue(mac_strip.has_debug(debug_macho_fixture(marker=True, stabs=True)))
        self.assertTrue(mac_strip.has_debug(debug_macho_fixture(marker=True, dwarf=True)))

    def test_macos_debug_classification_is_per_slice_and_never_treats_all_stabs_as_safe(self) -> None:
        cases = ((False, False, "DEBUG_METADATA_CLEARED"),
                 (True, False, "DEBUG_DWARF_SECTION_REMAINS"),
                 (False, True, "DEBUG_STABS_REMAINS"),
                 (True, True, "DEBUG_BOTH_REMAIN"))
        for dwarf, stabs, category in cases:
            with self.subTest(category=category):
                thin = debug_macho_fixture(dwarf=dwarf, stabs=stabs, marker=True)
                state, = mac_strip.debug_states(thin)
                self.assertEqual((state.architecture, state.dwarf, state.stabs, state.category),
                                 ("X86_64", dwarf, stabs, category))
                fat = universal_macho_fixture(debug_macho_fixture(marker=True, cpu=0x100000c), thin)
                first, second = mac_strip.debug_states(fat)
                self.assertEqual(first.architecture, "ARM64")
                self.assertEqual(first.category, "DEBUG_METADATA_CLEARED")
                self.assertEqual(second.category, category)
                self.assertEqual(mac_strip.has_debug(fat), dwarf or stabs)

    def test_unsupported_macho_encoding_is_not_silently_treated_as_clear(self) -> None:
        for magic in (b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbf"):
            with self.assertRaisesRegex(ValueError, "MACHO_FORMAT_OR_SLICES_INVALID"):
                mac_strip.has_debug(magic + bytes(28))

    def test_apple_marker_requires_exact_record_name_and_indirect_context(self) -> None:
        original = debug_macho_fixture(marker=True)
        _, ranges = native_sections.sections(original)
        table = next(s for s in ranges if s.name == "symbol-table")
        variants = []
        for field_offset in (4, 5, 6, 8):
            changed = bytearray(original)
            changed[table.offset + field_offset] ^= 1 if field_offset != 4 else 2
            variants.append(changed)
        for value in (b"radr://5614543\0", b"radr://5614542x"):
            variants.append(original.replace(b"radr://5614542\0", value))
        pos = original.index(struct.pack("<II", 0xb, 80))
        changed = bytearray(original)
        struct.pack_into("<I", changed, pos + 60, 0)
        variants.append(changed)
        changed = bytearray(original)
        struct.pack_into("<I", changed, pos + 12, 1000)
        variants.append(changed)
        changed = bytearray(original)
        struct.pack_into("<I", changed, table.offset, len(original))
        variants.append(changed)
        changed = bytearray(original)
        changed[table.offset:table.offset + 16], changed[table.offset + 16:table.offset + 32] = (
            changed[table.offset + 16:table.offset + 32], changed[table.offset:table.offset + 16])
        variants.append(changed)
        for index, data in enumerate(variants):
            with self.subTest(variant=index):
                self.assertTrue(mac_strip.has_debug(bytes(data)))
        # Recognition is not a privacy exemption, even for an exact marker.
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "probe"
            binary.write_bytes(original + b"/synthetic-private-builder/secret.cc\0")
            self.assertTrue(artifact_audit.scan_file(binary, artifact_audit.forbidden_patterns([
                "/synthetic-private-builder"])))

    def test_debug_removal_preserves_runtime_meaning_including_renumbered_indirect_targets(self) -> None:
        before = debug_macho_fixture(dwarf=True, stabs=True, marker=True)
        after = debug_macho_fixture(marker=True)
        self.assertTrue(mac_strip.has_debug(before))
        self.assertFalse(mac_strip.has_debug(after))
        for fingerprint in (lambda data: native_sections.loadable_fingerprint(data, native_sections.sections(data)[1]),
                            native_sections.macho_linkedit_fingerprint, native_sections.macho_indirect_fingerprint):
            self.assertEqual(fingerprint(before), fingerprint(after))
            self.assertEqual(fingerprint(universal_macho_fixture(before, before)),
                             fingerprint(universal_macho_fixture(after, after)))
        states = [dict(mac_strip.snapshot(data), exports=b"exports", architectures=b"x64", links=b"links")
                  for data in (before, after)]
        self.assertEqual(mac_strip.contract_failures(*states), [])

    def test_indirect_table_corruption_is_not_hidden_by_unchanged_external_symbols(self) -> None:
        data = debug_macho_fixture(marker=True)
        pos = data.index(struct.pack("<II", 0xb, 80))
        offset = struct.unpack_from("<I", data, pos + 56)[0]
        changed = bytearray(data)
        struct.pack_into("<I", changed, offset, 1)  # another valid external target
        self.assertEqual(native_sections.macho_linkedit_fingerprint(data),
                         native_sections.macho_linkedit_fingerprint(bytes(changed)))
        self.assertNotEqual(native_sections.macho_indirect_fingerprint(data),
                            native_sections.macho_indirect_fingerprint(bytes(changed)))
        for target in (0, 1000, 0x80000001):
            struct.pack_into("<I", changed, offset, target)
            with self.assertRaises(ValueError):
                native_sections.macho_indirect_fingerprint(bytes(changed))

    def test_chained_fixup_and_export_trie_byte_changes_remain_rejected(self) -> None:
        for kind in (0x80000033, 0x80000034):
            header = struct.pack("<8I", 0xfeedfacf, 0x1000007, 0, 6, 1, 16, 4, 0)
            data = header + struct.pack("<4I", kind, 16, 48, 4) + b"safe"
            self.assertNotEqual(native_sections.macho_linkedit_fingerprint(data),
                                native_sections.macho_linkedit_fingerprint(data[:-1] + b"x"))

    def test_macos_diagnostics_only_emit_fixed_states_and_ordinal_architectures(self) -> None:
        data = universal_macho_fixture(debug_macho_fixture(dwarf=True, stabs=True),
                                       debug_macho_fixture(marker=True, cpu=0x100000c))
        with contextlib.redirect_stdout(io.StringIO()) as output:
            mac_strip.report_debug(7, "AFTER", data)
        self.assertIn("binary_index=7 architecture=X86_64 dwarf=1 stabs=1 state=DEBUG_BOTH_REMAIN", output.getvalue())
        self.assertIn("architecture=ARM64 dwarf=0 stabs=0 state=DEBUG_METADATA_CLEARED", output.getvalue())
        for private in ("source.o", "private-builder", "radr://", "_entry", "_puts"):
            self.assertNotIn(private, output.getvalue())

    def test_macos_transaction_rolls_back_strip_sign_verify_and_install_failures(self) -> None:
        failures = ("strip", "debug-remains", "runtime", "inner-sign", "verify", "final-path-verify", "post-sign-runtime", "install", "install-interrupt")
        for failure in failures:
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                app = Path(directory) / "private-review-name.app"
                framework = app / "Contents/Frameworks/Probe.framework"
                binary = framework / "Versions/A/Probe"
                binary.parent.mkdir(parents=True)
                original = debug_macho_fixture(stabs=True)
                cleared = debug_macho_fixture(marker=True)
                binary.write_bytes(original)
                (framework / "Versions/Current").symlink_to("A")
                (framework / "Probe").symlink_to("Versions/Current/Probe")
                seal = app / "Contents/_CodeSignature/CodeResources"
                seal.parent.mkdir(parents=True)
                seal.write_bytes(b"original-resource-seal")
                add_bundle_metadata_fixture(app, framework)
                calls = []
                def fake_command(args):
                    calls.append(args)
                    if "strip" in args:
                        if failure == "strip":
                            raise RuntimeError("SIMULATED_STRIP_FAILURE")
                        result = original if failure == "debug-remains" else cleared
                        if failure == "runtime":
                            result = result.replace(b"synthetic-code!!", b"corrupted-code!!")
                        Path(args[-1]).write_bytes(result)
                    if "--force" in args:
                        if failure == "inner-sign":
                            raise RuntimeError("SIMULATED_SIGN_FAILURE")
                        staged = next(p for p in Path(args[-1]).parents if p.suffix == ".app") if Path(args[-1]).suffix != ".app" else Path(args[-1])
                        (staged / "Contents/_CodeSignature/CodeResources").write_bytes(b"new-resource-seal")
                        if failure == "post-sign-runtime":
                            target = staged / binary.relative_to(app)
                            target.write_bytes(cleared.replace(b"synthetic-code!!", b"corrupted-code!!"))
                    if "--verify" in args and (failure == "verify" or (failure == "final-path-verify" and Path(args[-1]) == app)):
                        raise RuntimeError("SIMULATED_VERIFY_FAILURE")
                    return fake_native_metadata(args)
                replace = os.replace
                def fake_replace(source, destination):
                    if failure.startswith("install") and Path(source).name == app.name and "backup" not in Path(source).parts and Path(destination) == app:
                        if failure == "install-interrupt":
                            raise KeyboardInterrupt()
                        raise OSError("private-error-that-must-not-be-printed")
                    return replace(source, destination)
                with (patch.object(mac_strip.sys, "platform", "darwin"),
                      patch.object(mac_strip, "command", fake_command),
                      patch.object(mac_strip.os, "replace", fake_replace),
                      contextlib.redirect_stdout(io.StringIO()) as output):
                    with self.assertRaises(KeyboardInterrupt if failure == "install-interrupt" else RuntimeError):
                        mac_strip.prepare(app)
                self.assertEqual(binary.read_bytes(), original)
                self.assertEqual(seal.read_bytes(), b"original-resource-seal")
                self.assertEqual(os.readlink(framework / "Probe"), "Versions/Current/Probe")
                self.assertEqual(os.readlink(framework / "Versions/Current"), "A")
                self.assertFalse(list(Path(directory).glob(".fura-macos-debug-*")))
                self.assertNotIn("private-review-name", output.getvalue())
                self.assertNotIn("private-error", output.getvalue())

    def test_macos_failed_rollback_retains_original_in_private_backup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "probe.app"
            app.mkdir()
            binary = app / "probe"
            binary.write_bytes(debug_macho_fixture(marker=True))
            original = binary.read_bytes()
            replace = os.replace
            def fail_install_and_restore(source, destination):
                if Path(destination) == app:
                    raise OSError("private-error")
                return replace(source, destination)
            with (patch.object(mac_strip.sys, "platform", "darwin"),
                  patch.object(mac_strip, "command", return_value=b""),
                  patch.object(mac_strip.os, "replace", fail_install_and_restore),
                  contextlib.redirect_stdout(io.StringIO())):
                with self.assertRaisesRegex(RuntimeError, "PRIVATE_BACKUP_RETAINED"):
                    mac_strip.prepare(app)
            backup, = Path(directory).glob(".fura-macos-debug-*/backup/probe.app")
            self.assertEqual((backup / "probe").read_bytes(), original)
            self.assertEqual(backup.parent.parent.stat().st_mode & 0o777, 0o700)
            replace(backup, app)

    def test_adhoc_signature_check_does_not_match_an_executable_path_substring(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "probe.app"
            app.mkdir()
            binary = app / "probe"
            original = debug_macho_fixture(stabs=True)
            binary.write_bytes(original)
            with (patch.object(mac_strip.sys, "platform", "darwin"),
                  patch.object(mac_strip, "command", side_effect=lambda args: fake_native_metadata(args) if "lipo" in args else b"Executable=/private/Signature=adhoc\nAuthority=Developer ID\n") as command,
                  contextlib.redirect_stdout(io.StringIO())):
                with self.assertRaisesRegex(ValueError, "non-ad-hoc"):
                    mac_strip.prepare(app)
            self.assertEqual(binary.read_bytes(), original)
            self.assertFalse(any("strip" in call.args[0] or "--force" in call.args[0] for call in command.call_args_list))

    def test_universal_non_host_developer_signature_is_rejected_before_strip(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "probe.app"
            app.mkdir()
            binary = app / "probe"
            original = universal_macho_fixture(debug_macho_fixture(stabs=True),
                                                debug_macho_fixture(stabs=True, cpu=0x100000c))
            binary.write_bytes(original)
            calls = []
            def command(args):
                calls.append(args)
                if args[0] == "codesign" and "--architecture" in args and "arm64" in args:
                    return b"Authority=Developer ID\n"
                return fake_native_metadata(args)
            with (patch.object(mac_strip.sys, "platform", "darwin"),
                  patch.object(mac_strip, "command", command),
                  contextlib.redirect_stdout(io.StringIO())):
                with self.assertRaisesRegex(ValueError, "non-ad-hoc"):
                    mac_strip.prepare(app)
            self.assertEqual(binary.read_bytes(), original)
            self.assertTrue(any("arm64" in args for args in calls))
            self.assertFalse(any("strip" in args or "--force" in args for args in calls))

    def test_signing_bundle_executable_cannot_escape_checked_bundle(self) -> None:
        invalid = (plistlib.dumps({"CFBundleExecutable": "../outside"}),
                   b'<?xml version="1.0"?><plist><dict><key>CFBundleExecutable</key><string>incomplete')
        for index, metadata in enumerate(invalid):
            with self.subTest(case=index), tempfile.TemporaryDirectory() as directory:
                app = Path(directory) / "probe.app"
                add_bundle_metadata_fixture(app)
                candidate = app / "debug"
                original = debug_macho_fixture(stabs=True)
                candidate.write_bytes(original)
                (app / "Contents/Info.plist").write_bytes(metadata)
                with (patch.object(mac_strip.sys, "platform", "darwin"),
                      patch.object(mac_strip, "command", side_effect=fake_native_metadata) as command,
                      contextlib.redirect_stdout(io.StringIO())):
                    with self.assertRaisesRegex(ValueError, "MACHO_BUNDLE_METADATA_INVALID"):
                        mac_strip.prepare(app)
                self.assertEqual(candidate.read_bytes(), original)
                self.assertEqual((app / "Contents/Info.plist").read_bytes(), metadata)
                self.assertFalse(any("strip" in call.args[0] or "--force" in call.args[0] for call in command.call_args_list))

    def test_marker_only_binary_is_not_stripped_or_resigned_but_app_is_verified(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "probe.app"
            app.mkdir()
            binary = app / "probe"
            original = universal_macho_fixture(debug_macho_fixture(marker=True),
                                                debug_macho_fixture(marker=True, cpu=0x100000c))
            binary.write_bytes(original)
            with (patch.object(mac_strip.sys, "platform", "darwin"),
                  patch.object(mac_strip, "command", return_value=b"") as command,
                  contextlib.redirect_stdout(io.StringIO())):
                mac_strip.prepare(app)
            self.assertEqual(binary.read_bytes(), original)
            self.assertEqual(len(command.call_args_list), 2)
            for call in command.call_args_list:
                self.assertEqual(call.args[0][:-1], ["codesign", "--verify", "--deep", "--strict"])
            self.assertEqual(command.call_args.args[0][-1], str(app))

    def test_framework_external_and_broken_symlinks_are_rejected_before_tools_run(self) -> None:
        for kind in ("external", "broken"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                app = Path(directory) / "probe.app"
                app.mkdir()
                (app / "probe").write_bytes(debug_macho_fixture(stabs=True))
                external = Path(directory) / "outside"
                external.mkdir()
                (app / "Versions").symlink_to(external if kind == "external" else "absent")
                with (patch.object(mac_strip.sys, "platform", "darwin"),
                      patch.object(mac_strip, "command") as command):
                    with self.assertRaises(ValueError):
                        mac_strip.prepare(app)
                command.assert_not_called()
                self.assertTrue((app / "Versions").is_symlink())

    @unittest.skipUnless(sys.platform == "darwin", "NATIVE_MACOS_CI_NOT_RUN")
    def test_native_macos_debug_strip_sign_load_and_zip_privacy(self) -> None:
        # Real Apple clang/strip/codesign/ditto, no simulated native success.
        import ctypes
        self.assertIsNotNone(shutil.which("xcrun"), "native Xcode tools are required, not a skipped pass")
        with tempfile.TemporaryDirectory(prefix="fura native debug fixture ") as directory:
            root = Path(directory)
            app = root / "Probe.app"
            runner = app / "Contents/MacOS/probe"
            runner.parent.mkdir(parents=True)
            framework = app / "Contents/Frameworks/Probe.framework"
            library = framework / "Versions/A/Probe"
            library.parent.mkdir(parents=True)
            resources = library.parent / "Resources"
            resources.mkdir()
            (framework / "Versions/Current").symlink_to("A")
            (framework / "Probe").symlink_to("Versions/Current/Probe")
            (framework / "Resources").symlink_to("Versions/Current/Resources")
            for plist, executable, kind in ((app / "Contents/Info.plist", "probe", "APPL"),
                                             (resources / "Info.plist", "Probe", "FMWK")):
                plist.write_bytes(plistlib.dumps({"CFBundleExecutable": executable,
                    "CFBundleIdentifier": "com.fura.privacyfixture." + executable,
                    "CFBundleName": executable, "CFBundlePackageType": kind, "CFBundleVersion": "1"}))
            source = root / "probe.c"
            source.write_text("#include <unistd.h>\nint fura_probe(void) { return getpid() > 0 ? 7 : 9; }\nint main(void) { return fura_probe() == 7 ? 0 : 1; }\n")
            for output, extra in ((runner, []), (library, ["-dynamiclib", "-Wl,-install_name,@rpath/Probe.framework/Versions/A/Probe"])):
                mac_strip.command(["xcrun", "clang", "-g", "-O0", "-arch", "x86_64", "-arch", "arm64",
                                   *extra, str(source), "-o", str(output)])
            for seal in (framework, app):
                mac_strip.command(["codesign", "--force", "--sign", "-", str(seal)])
            before = [mac_strip.native_snapshot(path) for path in (runner, library)]
            self.assertTrue(any(state["debug"] for state in before), "native fixture did not exercise source debug stripping")
            mac_strip.prepare(app)
            after = [mac_strip.native_snapshot(path) for path in (runner, library)]
            for old, new in zip(before, after, strict=True):
                self.assertEqual(mac_strip.contract_failures(old, new), [])
                self.assertFalse(new["debug"])
            self.assertEqual(os.readlink(framework / "Probe"), "Versions/Current/Probe")
            mac_strip.command(["codesign", "--verify", "--deep", "--strict", str(app)])
            mac_strip.command([str(runner)])
            try:
                loaded = ctypes.CDLL(str(library))
                self.assertEqual(loaded.fura_probe(), 7)
            except (OSError, AttributeError):
                raise AssertionError("NATIVE_MACOS_FIXTURE_LOAD_FAILED") from None
            patterns = artifact_audit.forbidden_patterns([str(root)])
            for path in app.rglob("*"):
                if path.is_file():
                    self.assertFalse(bool(artifact_audit.scan_file(path, patterns)), "native fixture .app privacy rejected")
            archive = root / "probe.zip"
            mac_strip.command(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)])
            self.assertFalse(bool(artifact_audit.scan_file(archive, patterns)), "native fixture ZIP privacy rejected")

    def test_macos_invalid_slice_extent_is_classified_as_format_not_dyld(self) -> None:
        data = struct.pack(">II", 0xcafebabe, 1) + struct.pack(">IIIII", 0x1000007, 3, 4096, 32, 0)
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "malformed"
            binary.write_bytes(data)
            with self.assertRaisesRegex(RuntimeError, "MACHO_FORMAT_OR_SLICES_INVALID"):
                mac_strip.native_snapshot(binary)

    def test_windows_native_build_script_fingerprint_must_record_selected_compiler_and_maps(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = {}
            with patch.object(privacy_build.shutil, "which", return_value="clang-cl"):
                privacy_build.windows_aws_lc_environment(env, Path("/source"), Path("/builder"))
            with self.assertRaisesRegex(RuntimeError, "NOT_APPLIED"):
                privacy_build.verify_windows_aws_lc_flags(root, env)
            record = root / "x86_64-pc-windows-msvc/release/.fingerprint/aws-lc-sys-hash/run-build-script-build-script-main.json"
            record.parent.mkdir(parents=True)
            values = [{"RerunIfEnvChanged": {"var": key, "val": value}} for key, value in env.items()]
            for local in ([], values):
                record.write_text(json.dumps({"local": local}))
                if not local:
                    with self.assertRaisesRegex(RuntimeError, "NOT_APPLIED"):
                        privacy_build.verify_windows_aws_lc_flags(root, env)
                else:
                    with contextlib.redirect_stdout(io.StringIO()) as output:
                        privacy_build.verify_windows_aws_lc_flags(root, env)
                    self.assertNotIn("/builder", output.getvalue())

    def test_windows_native_maps_are_scoped_to_aws_lc_and_preserve_caller_flags(self) -> None:
        environment = {"CC": "unchanged-default-compiler", "CFLAGS": "/DKEEP=1"}
        with patch.object(privacy_build.shutil, "which", return_value="clang-cl"):
            privacy_build.native_build_environment(environment, "windows", Path("/source with spaces"), Path("/builder"))
        self.assertEqual(environment["CC"], "unchanged-default-compiler")
        self.assertEqual(environment["CFLAGS"], "/DKEEP=1")
        flags = shlex.split(environment["AWS_LC_SYS_HOST_CFLAGS_x86_64_pc_windows_msvc"])
        self.assertIn("/DKEEP=1", flags)
        self.assertIn("/clang:-ffile-prefix-map=/source with spaces=/fura-source", flags)
        self.assertEqual(environment["AWS_LC_SYS_CMAKE_BUILDER"], "0")
        with patch.object(privacy_build.shutil, "which", return_value=None):
            with self.assertRaisesRegex(SystemExit, "CLANG_CL_REQUIRED"):
                privacy_build.native_build_environment({}, "windows", Path("/source"), Path("/builder"))

    @unittest.skipUnless(shutil.which("clang-cl") and shutil.which("lld-link"), "requires clang-cl/lld-link")
    def test_native_c_file_macro_in_real_pe_requires_native_not_rust_maps(self) -> None:
        # Actual MSVC-target PE generation on the local host; NOT a native
        # Windows Fura build. No CRT/SDK or upstream crypto replacement.
        with tempfile.TemporaryDirectory(prefix="fura native PE ") as directory:
            root = Path(directory)
            home = root / "synthetic builder"
            home.mkdir()
            source = home / "dependency.c"
            source.write_text('#define WIDE_(x) L##x\n#define WIDE(x) WIDE_(x)\n'
                              '__declspec(dllexport) const char *build_file(void) { return __FILE__; }\n'
                              '__declspec(dllexport) const unsigned short *wide_file(void) { return WIDE(__FILE__); }')
            obj, dll = root / "dependency.obj", root / "dependency.dll"
            env = dict(os.environ, CARGO_ENCODED_RUSTFLAGS=privacy_build.encoded_rust_flags("", root, home))
            configured = {}
            privacy_build.windows_aws_lc_environment(configured, root, home)
            maps = shlex.split(configured["AWS_LC_SYS_HOST_CFLAGS_x86_64_pc_windows_msvc"])
            for flags, rejected in (([], True), (maps, False)):
                subprocess.run(["clang-cl", "--target=x86_64-pc-windows-msvc", "/nologo", "/c",
                                *flags, "/Fo" + str(obj), "--", str(source)],
                               env=env, check=True, capture_output=True)
                subprocess.run(["lld-link", "/dll", "/noentry", "/nodefaultlib", "/out:" + str(dll), str(obj)],
                               check=True, capture_output=True)
                data = dll.read_bytes()
                self.assertEqual(native_sections.sections(data)[0], "PE")
                diagnostics = []
                findings = artifact_audit.scan_file(dll, artifact_audit.forbidden_patterns([str(home), str(root)]), diagnostics)
                self.assertEqual(bool(findings), rejected)
                if rejected:
                    self.assertEqual({d["section"] for d in diagnostics}, {".rdata"})
                    self.assertTrue({"utf-8", "utf-16le"}.issubset({d["pattern_encoding"] for d in diagnostics}))
                    self.assertEqual({d["origin_hint"] for d in diagnostics}, {"NATIVE_C_SOURCE_PATH"})
                if not rejected:
                    self.assertTrue(b"/fura-build" in data.replace(b"\\", b"/"), "native source map was not emitted")

    @unittest.skipUnless(shutil.which("cargo") and shutil.which("rustc"), "requires installed Cargo/rustc")
    def test_real_cargo_preserves_encoded_flags_in_target_fingerprint_and_cdylib(self) -> None:
        with tempfile.TemporaryDirectory(prefix="fura cargo privacy ") as directory:
            root = Path(directory)
            source = root / "source"
            home = root / "synthetic builder"
            dependency = home / ".cargo/registry/src/synthetic-dependency"
            for path in (source, dependency):
                path.mkdir(parents=True)
            (dependency / "Cargo.toml").write_text('[package]\nname="synthetic-dependency"\nversion="0.0.0"\n[lib]\npath="lib.rs"\n')
            (dependency / "lib.rs").write_text("pub fn source() -> &'static str { file!() }")
            (source / "Cargo.toml").write_text('[package]\nname="privacy-probe"\nversion="0.0.0"\n[lib]\npath="lib.rs"\ncrate-type=["cdylib"]\n[dependencies]\nsynthetic-dependency={path="' + dependency.as_posix() + '"}\n[workspace]\n')
            (source / "lib.rs").write_text('#[unsafe(no_mangle)] pub fn source() -> &\'static str { synthetic_dependency::source() }')
            host = next(line.split(": ", 1)[1] for line in subprocess.check_output(["rustc", "-vV"], text=True).splitlines() if line.startswith("host: "))
            flags = privacy_build.encoded_rust_flags("", source, home,
                                                    "windows" if sys.platform == "win32" else "linux")
            env = dict(os.environ, CARGO_ENCODED_RUSTFLAGS=flags)
            subprocess.run(["cargo", "build", "--offline", "--release", "--target", host,
                            "--target-dir", str(root / "target")], cwd=source, env=env,
                           check=True, capture_output=True)
            fingerprint = next((root / "target" / host).rglob("lib-privacy_probe.json"))
            self.assertEqual(json.loads(fingerprint.read_text())["rustflags"], flags.split("\x1f"))
            library = next(p for p in fingerprint.parents[2].glob("*privacy_probe*") if p.suffix in (".so", ".dylib", ".dll"))
            self.assertTrue(b"/fura-build" in library.read_bytes(), "mapped Rust source name was not emitted")
            self.assertFalse(artifact_audit.scan_file(library, artifact_audit.forbidden_patterns([str(home), str(source)])))

    def test_stabs_removal_and_string_relocation_preserve_runtime_fingerprint(self) -> None:
        runtime_names = b"\0_alias\0_target\0_other\0"
        debug_name = b"synthetic-debug-object.o\0"
        names = runtime_names + debug_name
        header = struct.pack("<IIIIIIII", 0xfeedfacf, 0x1000007, 3, 6, 1, 24, 0, 0)
        command = struct.pack("<IIIIII", 2, 24, 56, 2, 88, len(names))
        alias = struct.pack("<IBBHQ", 1, 0xb, 0, 0, 8)
        debug = struct.pack("<IBBHQ", len(runtime_names), 0x66, 0, 1, 123)
        before = header + command + debug + alias + names
        after = indirect_macho_fixture()
        self.assertTrue(mac_strip.has_debug(before))
        self.assertFalse(mac_strip.has_debug(after))
        self.assertEqual(native_sections.macho_linkedit_fingerprint(before),
                         native_sections.macho_linkedit_fingerprint(after))
        # No broad exclusion of the symbol table: aliases, runtime flags and
        # CPU identities still change the fingerprint.
        for change in ("weak-definition", "alias-target"):
            changed = bytearray(alias)
            if change == "weak-definition":
                changed[6] = 0x80  # N_WEAK_DEF, runtime meaning
            else:
                struct.pack_into("<Q", changed, 8, 16)  # different alias target
            altered = header + command + debug + changed + names
            self.assertNotEqual(native_sections.macho_linkedit_fingerprint(before),
                                native_sections.macho_linkedit_fingerprint(altered))

    def test_macos_contract_diagnostics_classify_every_invariant_without_values(self) -> None:
        before = dict(shape=("thin64", 1), loadable="hash1", linkedit="hash2", indirect="hash3",
                      exports=b"private symbol", architectures=b"arm64", links=b"private path", debug=True)
        after = dict(before, debug=False)
        self.assertEqual(mac_strip.contract_failures(before, after), [])
        categories = {"shape": "MACHO_FORMAT_OR_SLICES_CHANGED", "loadable": "LOADABLE_SECTIONS_CHANGED",
                      "linkedit": "LINKEDIT_OR_DYLD_CHANGED", "indirect": "LINKEDIT_OR_DYLD_CHANGED",
                      "exports": "EXPORTED_SYMBOLS_CHANGED",
                      "architectures": "CPU_ARCHITECTURES_CHANGED", "links": "DYLIB_DEPENDENCY_OR_INSTALL_NAME_CHANGED"}
        for field, category in categories.items():
            with self.subTest(field=field):
                self.assertEqual(mac_strip.contract_failures(before, dict(after, **{field: "changed-private-value"})), [category])
        self.assertEqual(mac_strip.contract_failures(before, before), ["DEBUG_METADATA_REMAINS"])
        self.assertEqual(len(mac_strip.contract_failures(before, dict.fromkeys(before, "changed"))), 7)

    def test_cargo_fingerprint_checks_actual_target_flags_and_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = "--remap-path-prefix=C:/Users/Builder=/fura-build\x1f-C\x1flink-arg=/PDBALTPATH:%_PDB%"
            with self.assertRaisesRegex(RuntimeError, "EVIDENCE_MISSING"):
                privacy_build.verify_windows_cargo_flags(root, expected)
            fingerprint = root / "plugins/rust/cargokit_build/x86_64-pc-windows-msvc/release/.fingerprint/rust_lib_flutterustmusic-hash/lib-rust_lib_flutterustmusic.json"
            fingerprint.parent.mkdir(parents=True)
            for value in ("invalid-json", '{}', '[]', 'null', '{"rustflags": []}'):
                fingerprint.write_text(value)
                with self.assertRaises(RuntimeError):
                    privacy_build.verify_windows_cargo_flags(root, expected)
            fingerprint.write_text(json.dumps({"rustflags": expected.split("\x1f")}))
            with contextlib.redirect_stdout(io.StringIO()) as output:
                privacy_build.verify_windows_cargo_flags(root, expected)
            self.assertIn("PRIVATE_RUST_FLAGS_VERIFIED", output.getvalue())
            self.assertNotIn("C:/Users", output.getvalue())

    def test_path_origin_diagnostics_are_fixed_hints_not_audit_exemptions(self) -> None:
        patterns = artifact_audit.forbidden_patterns(["C:/Users/Builder"])
        for data, hint in ((b"C:/Users/Builder/.cargo/registry/src/hash/dependency/src/lib.rs", "RUST_REGISTRY_SOURCE"),
                           (b"RSDS" + bytes(20) + b"C:/Users/Builder/output.pdb\0", "PE_CODEVIEW_PDB")):
            start = data.index(b"C:/Users")
            self.assertEqual(artifact_audit.path_origin_hint(data, start, start + len(b"C:/Users/Builder"), "PE"), hint)
            self.assertTrue(artifact_audit.scan_payload(data, patterns, "rust.dll"))

    def test_windows_remapping_covers_cargo_slash_spellings(self) -> None:
        class WindowsRoot(PureWindowsPath):
            def resolve(self):
                return self

        flags = privacy_build.encoded_rust_flags(
            "", WindowsRoot("D:/a/fura/fura"), WindowsRoot("C:/Users/CI Builder"),
            "windows").split("\x1f")
        for root, replacement in (("C:/Users/CI Builder", "/fura-build"),
                                  ("D:/a/fura/fura", "/fura-source")):
            for spelling in (root, root.replace("/", "\\")):
                self.assertIn(f"--remap-path-prefix={spelling}={replacement}", flags)

    @unittest.skipUnless(shutil.which("rustc"), "requires installed rustc")
    def test_actual_rustc_textual_remap_requires_both_separator_spellings(self) -> None:
        # Linux compiler evidence for Rust's textual remapper, NOT MSVC proof.
        # The source filename itself deliberately uses Windows-style spelling.
        if sys.platform == "win32":
            self.skipTest("synthetic colon filename is a Unix-only fixture")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "C:/Users/CI Builder/registry/source.rs"
            source.parent.mkdir(parents=True)
            source.write_text("#[unsafe(no_mangle)] pub fn source() -> &'static str { file!() }")
            output = root / "source.ll"
            for prefixes, contains_private in ((["C:\\Users\\CI Builder"], True),
                                               (["C:\\Users\\CI Builder", "C:/Users/CI Builder"], False)):
                subprocess.run(["rustc", "--crate-type=lib", "--emit=llvm-ir",
                                *[f"--remap-path-prefix={p}=/fura-build" for p in prefixes],
                                "C:/Users/CI Builder/registry/source.rs", "-o", str(output)],
                               cwd=root, check=True, capture_output=True)
                self.assertEqual(b"C:/Users/CI Builder" in output.read_bytes(), contains_private)

    def test_macos_upstream_classification_rejects_altered_runtime_linkedit(self) -> None:
        text = b"public upstream /Users/runner/config\0"
        data = runtime_macho_fixture(text)
        _, ranges = native_sections.sections(data)
        record = {"payload": "Contents/Frameworks/Mpv.framework/Versions/A/Mpv",
                  "format": "Mach-O", "root": "/Users/runner",
                  "loadable_sha256": native_sections.loadable_fingerprint(data, ranges),
                  "linkedit_sha256": native_sections.macho_linkedit_fingerprint(data),
                  "strings": [{"section": "__TEXT,__cstring", "length": len(text) - 1,
                               "sha256": hashlib.sha256(text[:-1]).hexdigest()}]}
        patterns = artifact_audit.forbidden_patterns([record["root"]])
        with patch.object(artifact_audit, "UPSTREAM_PAYLOADS", [record]):
            self.assertFalse(artifact_audit.scan_payload(data, patterns, record["payload"]))
            for altered in (runtime_macho_fixture(text, 16),
                            runtime_macho_fixture(text, 1000),
                            data + b"/Users/runner/private"):
                self.assertTrue(artifact_audit.scan_payload(altered, patterns, record["payload"]))

    def test_macho_dyld_binding_bytecode_is_part_of_runtime_contract(self) -> None:
        header = struct.pack("<IIIIIIII", 0xfeedfacf, 0x1000007, 3, 6, 1, 48, 0, 0)
        command = struct.pack("<IIIIIIIIIIII", 0x80000022, 48,
                              0, 0, 80, 4, 0, 0, 0, 0, 0, 0)
        before = header + command + b"bind"
        self.assertNotEqual(native_sections.macho_linkedit_fingerprint(before),
                            native_sections.macho_linkedit_fingerprint(before[:-1] + b"x"))

    def test_macho_indirect_export_target_is_part_of_runtime_contract(self) -> None:
        valid = indirect_macho_fixture()
        altered = indirect_macho_fixture(16)
        self.assertNotEqual(native_sections.macho_linkedit_fingerprint(valid),
                            native_sections.macho_linkedit_fingerprint(altered))
        with self.assertRaisesRegex(ValueError, "indirect export"):
            native_sections.macho_linkedit_fingerprint(indirect_macho_fixture(1000))
        self.assertNotEqual(native_sections.macho_linkedit_fingerprint(valid),
                            native_sections.macho_linkedit_fingerprint(valid.replace(b"_alias", b"_other")))
        for data in (b"", b"\x7fELF", b"\xca\xfe\xba\xbe\xff\xff\xff\xff"):
            self.assertFalse(native_sections.sections(data)[1])

    def test_macos_preflight_rejects_real_signature_before_any_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "development.app"
            app.mkdir()
            binary = app / "Runner"
            original = debug_macho_fixture(stabs=True)
            binary.write_bytes(original)
            calls = []
            def fake_command(args):
                calls.append(args)
                return fake_native_metadata(args) if "lipo" in args else b"Authority=Developer ID Application"
            with (patch.object(mac_strip.sys, "platform", "darwin"),
                  patch.object(mac_strip, "command", fake_command)):
                with self.assertRaisesRegex(ValueError, "non-ad-hoc"):
                    mac_strip.prepare(app)
            self.assertEqual(binary.read_bytes(), original)
            self.assertFalse(any("strip" in args or "--force" in args for args in calls))

    def test_macos_debug_strip_preserves_contract_and_repairs_inner_seal_first(self) -> None:
        for break_runtime in (False, True):
            with self.subTest(break_runtime=break_runtime), tempfile.TemporaryDirectory() as directory:
                app = Path(directory) / "development.app"
                binary = app / "Contents" / "Frameworks" / "Plugin.framework" / "Versions" / "A" / "Plugin"
                binary.parent.mkdir(parents=True)
                original = debug_macho_fixture(stabs=True)
                cleared = debug_macho_fixture(marker=True)
                binary.write_bytes(original)
                add_bundle_metadata_fixture(app, app / "Contents/Frameworks/Plugin.framework")
                calls = []
                def fake_command(args):
                    calls.append(args)
                    if "strip" in args:
                        result = cleared.replace(b"synthetic-code!!", b"corrupted-code!!") if break_runtime else cleared
                        Path(args[-1]).write_bytes(result)
                    return fake_native_metadata(args)
                with (patch.object(mac_strip.sys, "platform", "darwin"),
                      patch.object(mac_strip, "command", fake_command),
                      contextlib.redirect_stdout(io.StringIO())):
                    if break_runtime:
                        with self.assertRaisesRegex(RuntimeError, "runtime contract"):
                            mac_strip.prepare(app)
                    else:
                        mac_strip.prepare(app)
                seals = [args[-1] for args in calls if "--force" in args]
                if break_runtime:
                    self.assertFalse(seals)
                    self.assertEqual(binary.read_bytes(), original)
                else:
                    self.assertEqual(Path(seals[-1]).name, app.name)
                    self.assertEqual([Path(p).suffix for p in seals], ["", ".framework", ".app"])
                    self.assertEqual(binary.read_bytes(), cleared)
                    self.assertTrue(any("--verify" in args and "--strict" in args for args in calls))

    def test_windows_roots_case_and_separator_variants(self) -> None:
        patterns = artifact_audit.forbidden_patterns(["D:/a/Fura/Fura", "C:\\Users\\Builder"])
        for value in (b"d:/A/fura/FURA/plugin.cpp", b"D:\\A\\FURA\\FURA\\plugin.cpp",
                      b"d:/A\\fura/FURA\\plugin.cpp", b"c:\\Users/Builder\\source.rs",
                      b"c:/users/builder/.cargo/source.rs", b"C:\\USERS\\BUILDER\\.cargo\\source.rs"):
            self.assertTrue(artifact_audit.scan_bytes(value, patterns))
            self.assertTrue(artifact_audit.scan_payload(value.decode().encode("utf-16le"), patterns, "plugin.dll"))
            self.assertTrue(artifact_audit.scan_payload(value.decode().encode("utf-16be"), patterns, "plugin.dll"))
            self.assertNotIn(value.decode().rsplit("source.rs", 1)[0],
                             artifact_audit.safe_display(value.decode(), patterns))
        unicode_patterns = artifact_audit.forbidden_patterns(["D:/Users/Åccount/音乐"])
        for codec in ("utf-8", "utf-16le", "utf-16be"):
            value = "d:\\users/åccount\\音乐/source.cpp".encode(codec)
            self.assertTrue(artifact_audit.scan_payload(value, unicode_patterns, "plugin.dll"))

    def test_unknown_third_party_and_first_party_paths_are_not_exempt(self) -> None:
        patterns = artifact_audit.forbidden_patterns(["/build/private", "/home/runner"])
        for payload in ("libmpv.so", "plugin.dll", "Contents/MacOS/flutterustmusic",
                        "Contents/Frameworks/rust_lib_flutterustmusic.framework/Versions/A/rust_lib_flutterustmusic",
                        "lib/arm64-v8a/libmpv.so"):
            for text in (b"/build/private/src/main.rs", b"/home/runner/not-proven/config"):
                self.assertTrue(artifact_audit.scan_payload(elf_fixture(text + b"\0"), patterns, payload))

    def test_upstream_classification_requires_payload_section_and_full_digest(self) -> None:
        text = b"public build --prefix=/home/runner/upstream\0"
        data = elf_fixture(text)
        record = {"payload": "lib/arm64-v8a/libmpv.so", "format": "ELF",
                  "upstream_sha256": hashlib.sha256(data).hexdigest(), "root": "/home/runner",
                  "strings": [{"section": ".rodata", "length": len(text) - 1,
                               "sha256": hashlib.sha256(text[:-1]).hexdigest()}]}
        patterns = artifact_audit.forbidden_patterns(["/home/runner"])
        with patch.object(artifact_audit, "UPSTREAM_PAYLOADS", [record]):
            self.assertFalse(artifact_audit.scan_payload(data, patterns, record["payload"]))
            self.assertTrue(artifact_audit.scan_payload(data, patterns, "first-party.so"))
            self.assertTrue(artifact_audit.scan_payload(data + b"/home/runner/private", patterns, record["payload"]))
            self.assertTrue(artifact_audit.scan_payload(data.replace(b'upstream', b'personal'), patterns, record["payload"]))
            self.assertTrue(artifact_audit.scan_payload(data, artifact_audit.forbidden_patterns([
                "/home/runner/upstream"]), record["payload"]))
            record["strings"][0]["section"] = ".debug_str"
            self.assertTrue(artifact_audit.scan_payload(data, patterns, record["payload"]))

    def test_personal_markers_are_never_classified_even_with_provenance(self) -> None:
        text = artifact_audit.OLD_APPLICATION_ID.encode() + b" /home/runner/public\0"
        data = elf_fixture(text)
        record = {"payload": "lib/arm64-v8a/libmpv.so", "format": "ELF",
                  "upstream_sha256": hashlib.sha256(data).hexdigest(), "root": "/home/runner",
                  "strings": [{"section": ".rodata", "length": len(text) - 1,
                               "sha256": hashlib.sha256(text[:-1]).hexdigest()}]}
        with patch.object(artifact_audit, "UPSTREAM_PAYLOADS", [record]):
            findings = artifact_audit.scan_payload(data, artifact_audit.forbidden_patterns([
                "/home/runner"]), record["payload"])
            self.assertIn("PERSONAL_APP_ID_FOUND", findings)
            self.assertIn("PERSONAL_MARKER_FOUND", findings)

    def test_recursive_archive_and_metadata_remain_fail_closed(self) -> None:
        nested = io.BytesIO()
        with zipfile.ZipFile(nested, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("lib/arm64-v8a/libmpv.so", b"/private/build/first-party")
        outer = io.BytesIO()
        with zipfile.ZipFile(outer, "w") as archive:
            archive.writestr("nested.apk", nested.getvalue())
            archive.comment = b"/private/build/container-secret"
        findings = artifact_audit.scan_archive_or_payload(outer.getvalue(),
            artifact_audit.forbidden_patterns(["/private/build"]), "artifact.zip")
        self.assertIn(("ABSOLUTE_BUILD_PATH_FOUND_1", "artifact.zip!nested.apk!lib/arm64-v8a/libmpv.so"), findings)
        self.assertIn(("ABSOLUTE_BUILD_PATH_FOUND_1", "artifact.zip"), findings)

    def test_cli_never_echoes_sensitive_bytes_or_sensitive_entry_names(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "artifact.zip"
            with zipfile.ZipFile(artifact, "w") as archive:
                archive.writestr("/private/build/entry", b"/private/build/secret-value")
            stderr = io.StringIO()
            with (patch.object(sys, "argv", ["audit", str(artifact), "--diagnose", "--forbidden-root", "/private/build"]),
                  contextlib.redirect_stderr(stderr)):
                self.assertEqual(artifact_audit.main(), 1)
            self.assertNotIn("/private/build", stderr.getvalue())
            self.assertNotIn("secret-value", stderr.getvalue())

    def test_corrupt_zip_is_fatal_without_echoing_exception_entry_name(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "artifact.zip"
            with zipfile.ZipFile(artifact, "w") as archive:
                archive.writestr("/private/build/entry", b"synthetic-payload")
            artifact.write_bytes(artifact.read_bytes().replace(b"synthetic-payload", b"corrupted-payload"))
            stderr = io.StringIO()
            with (patch.object(sys, "argv", ["audit", str(artifact)]),
                  contextlib.redirect_stderr(stderr)):
                self.assertEqual(artifact_audit.main(), 1)
            self.assertEqual(stderr.getvalue().strip(), "ARTIFACT_READ_OR_PARSE_FAILED")

    def test_rust_linker_path_mapping_keeps_repeated_codegen_flags(self) -> None:
        flags = privacy_build.encoded_rust_flags("-C\x1fdebuginfo=0\x1f-C\x1fopt-level=3",
            Path("/source"), Path("/builder"), "windows").split("\x1f")
        self.assertEqual(flags.count("-C"), 3)
        self.assertIn("link-arg=/PDBALTPATH:%_PDB%", flags)

    def test_native_settings_apply_to_private_build_only_and_preserve_flags(self) -> None:
        env = {"FLUTTER_XCODE_OTHER_CFLAGS": "$(inherited) -DFURA_TEST=1"}
        privacy_build.native_build_environment(env, "macos", Path("/source with spaces"), Path("/builder"))
        self.assertIn('-DFURA_TEST=1', env["FLUTTER_XCODE_OTHER_CFLAGS"])
        self.assertIn('"-ffile-prefix-map=/source with spaces=/fura-source"', env["FLUTTER_XCODE_OTHER_CFLAGS"])
        self.assertEqual(env["FLUTTER_XCODE_COPY_PHASE_STRIP"], "YES")
        self.assertEqual(env["FLUTTER_XCODE_STRIP_STYLE"], "non-global")
        self.assertFalse(mac_strip.has_debug(elf_fixture(b"hello")))
        with self.assertRaisesRegex(RuntimeError, "native macOS"):
            with patch.object(mac_strip.sys, "platform", "linux"):
                mac_strip.prepare(Path("test.app"))

    def test_source_content_reports_classes_without_echoing_values(self) -> None:
        marker = source_audit.PERSONAL_MARKER
        findings = source_audit.content_findings(
            f"dev.{marker}.flutterustmusic /home/{marker}/repo".encode()
        )
        self.assertEqual(
            findings,
            {
                "ABSOLUTE_MAINTAINER_HOME_FOUND",
                "PERSONAL_APP_ID_FOUND",
                "PERSONAL_MARKER_FOUND",
            },
        )

    def test_sensitive_filename_policy_allows_only_explicit_env_templates(self) -> None:
        self.assertEqual(
            source_audit.sensitive_filename_class("android/key.properties"),
            "SENSITIVE_FILENAME",
        )
        self.assertEqual(
            source_audit.sensitive_filename_class("config/.env.production"),
            "SENSITIVE_FILENAME",
        )
        self.assertIsNone(
            source_audit.sensitive_filename_class("config/.env.example")
        )

    def test_artifact_scans_archive_entries_and_build_roots(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive_path = root / "artifact.apk"
            forbidden_root = root / "workspace"
            forbidden_root.mkdir()
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(
                    "classes.dex",
                    f"{artifact_audit.OLD_APPLICATION_ID} {forbidden_root}".encode(),
                )
            findings = artifact_audit.scan_file(
                archive_path,
                artifact_audit.forbidden_patterns([str(forbidden_root)]),
            )
            labels = {label for label, _ in findings}
            self.assertIn("PERSONAL_APP_ID_FOUND", labels)
            self.assertIn("PERSONAL_MARKER_FOUND", labels)
            self.assertIn("ABSOLUTE_BUILD_PATH_FOUND_1", labels)

    def test_generated_plugin_registry_gets_a_stable_package_uri(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            config_path = root / "package_config.json"
            config_path.write_text(
                json.dumps(
                    {
                        "configVersion": 2,
                        "packages": [
                            {
                                "name": "flutterustmusic",
                                "rootUri": "../",
                                "packageUri": "lib/",
                                "languageVersion": "3.13",
                            },
                            {
                                "name": package_config.SYNTHETIC_PACKAGE_NAME,
                                "rootUri": "obsolete/",
                                "packageUri": "lib/",
                                "languageVersion": "3.0",
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )

            package_config.prepare_package_config(config_path)

            document = json.loads(config_path.read_text(encoding="utf-8"))
            generated_entries = [
                entry
                for entry in document["packages"]
                if entry["name"] == package_config.SYNTHETIC_PACKAGE_NAME
            ]
            self.assertEqual(
                generated_entries,
                [
                    {
                        "name": package_config.SYNTHETIC_PACKAGE_NAME,
                        "rootUri": "flutter_build/",
                        "packageUri": "",
                        "languageVersion": "3.13",
                    }
                ],
            )

    def test_rust_path_remapping_preserves_encoded_flags_and_spaces(self) -> None:
        flags = privacy_build.encoded_rust_flags(
            "-C\x1fdebuginfo=0",
            Path("/workspace with spaces/fura"),
            Path("/home/tester"),
        ).split("\x1f")
        self.assertEqual(flags[0:2], ["-C", "debuginfo=0"])
        self.assertIn(
            "--remap-path-prefix=/workspace with spaces/fura=/fura-source",
            flags,
        )
        self.assertIn("--remap-path-prefix=/home/tester=/fura-build", flags)

    def test_private_uri_scope_restores_pub_config_on_success_and_failure(self) -> None:
        with tempfile.TemporaryDirectory(prefix="private uri with spaces ") as directory:
            path = Path(directory) / "package_config.json"
            original = json.dumps(
                {
                    "configVersion": 2,
                    "packages": [{
                        "name": "flutterustmusic",
                        "rootUri": "../",
                        "packageUri": "lib/",
                        "languageVersion": "3.13",
                    }],
                }
            ).encode()
            for fail in (False, True):
                path.write_bytes(original)
                expectation = self.assertRaises(RuntimeError) if fail else nullcontext()
                with expectation:
                    with package_config.private_package_config(path):
                        self.assertIn(
                            package_config.SYNTHETIC_PACKAGE_NAME, path.read_text()
                        )
                        if fail:
                            raise RuntimeError("synthetic compiler failure")
                self.assertEqual(path.read_bytes(), original)

            package_config.prepare_package_config(path)
            with package_config.private_package_config(path):
                pass
            self.assertNotIn(package_config.SYNTHETIC_PACKAGE_NAME, path.read_text())

    def test_wrapper_separates_kernel_keys_without_changing_runtime_defines(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "package_config.json"
            original = json.dumps(
                {"packages": [{"name": "flutterustmusic", "languageVersion": "3.13"}]}
            ).encode()
            for target in sorted(privacy_build.SUPPORTED_TARGETS):
                with self.subTest(target=target):
                    path.write_bytes(original)
                    commands = []

                    def fake_run(command, environment):
                        commands.append(command)
                        if "--no-pub" in command:
                            self.assertIn(
                                package_config.SYNTHETIC_PACKAGE_NAME, path.read_text()
                            )
                            raise RuntimeError("synthetic build failure")

                    with (
                        patch.object(privacy_build, "PACKAGE_CONFIG", path),
                        patch.object(privacy_build, "run", fake_run),
                        patch.object(privacy_build.shutil, "which", return_value="flutter"),
                        patch.object(sys, "argv", [
                            "wrapper", target, "--debug",
                            "--dart-define=FURA_AUDIO_ENGINE=audioplayers",
                        ]),
                    ):
                        with self.assertRaises(RuntimeError):
                            privacy_build.main()
                    self.assertEqual(path.read_bytes(), original)
                    self.assertEqual(len(commands), 2)
                    for command in commands:
                        self.assertEqual(command[2], target)
                        self.assertIn(privacy_build.PRIVATE_REGISTRANT_DEFINE, command)
                        self.assertIn(
                            "--dart-define=FURA_AUDIO_ENGINE=audioplayers", command
                        )

if __name__ == "__main__":
    unittest.main()
