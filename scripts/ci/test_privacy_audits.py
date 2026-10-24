#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import contextlib
import hashlib
import io
import json
import sys
import struct
import tempfile
import unittest
import zipfile
from contextlib import nullcontext
from pathlib import Path
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


class PrivacyAuditTests(unittest.TestCase):
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
            binary.write_bytes(b"original")
            calls = []
            def fake_command(args):
                calls.append(args)
                return b"Authority=Developer ID Application"
            with (patch.object(mac_strip.sys, "platform", "darwin"),
                  patch.object(mac_strip, "has_debug", return_value=True),
                  patch.object(mac_strip, "command", fake_command)):
                with self.assertRaisesRegex(ValueError, "non-ad-hoc"):
                    mac_strip.prepare(app)
            self.assertEqual(binary.read_bytes(), b"original")
            self.assertFalse(any("strip" in args or "--force" in args for args in calls))

    def test_macos_debug_strip_preserves_contract_and_repairs_inner_seal_first(self) -> None:
        for break_runtime in (False, True):
            with self.subTest(break_runtime=break_runtime), tempfile.TemporaryDirectory() as directory:
                app = Path(directory) / "development.app"
                binary = app / "Contents" / "Frameworks" / "Plugin.framework" / "Versions" / "A" / "Plugin"
                binary.parent.mkdir(parents=True)
                binary.write_bytes(b"xdebug")
                calls = []
                def fake_command(args):
                    calls.append(args)
                    if "strip" in args:
                        binary.write_bytes(b"ystripped" if break_runtime else b"xstripped")
                    if args[0] == "codesign":
                        return b"Signature=adhoc"
                    return b"unchanged-runtime-metadata"
                with (patch.object(mac_strip.sys, "platform", "darwin"),
                      patch.object(mac_strip, "has_debug", side_effect=lambda d: d == b"xdebug"),
                      patch.object(mac_strip, "sections", return_value=("Mach-O", [native_sections.Section("__TEXT,__text", 0, 1)])),
                      patch.object(mac_strip, "macho_linkedit_fingerprint", return_value="stable-aliases"),
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
                else:
                    self.assertEqual(seals[-1], str(app.resolve()))
                    self.assertIn(str(binary.resolve()), seals)
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
