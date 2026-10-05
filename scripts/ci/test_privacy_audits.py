#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


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


class PrivacyAuditTests(unittest.TestCase):
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

if __name__ == "__main__":
    unittest.main()
