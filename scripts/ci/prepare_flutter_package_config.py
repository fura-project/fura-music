#!/usr/bin/env python3
"""Give Flutter's generated Dart plugin registrant a stable package URI."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path


SYNTHETIC_PACKAGE_NAME = "fura_generated_plugin_registry"


def prepare_package_config(path: Path) -> None:
    document = json.loads(path.read_text(encoding="utf-8"))
    packages = document.get("packages")
    if not isinstance(packages, list):
        raise ValueError("Flutter package config has no package list")

    project_entry = next(
        (entry for entry in packages if entry.get("name") == "flutterustmusic"),
        None,
    )
    if project_entry is None:
        raise ValueError("Flutter package config has no application package")
    language_version = project_entry.get("languageVersion")
    if not isinstance(language_version, str):
        raise ValueError("Flutter application package has no language version")

    document["packages"] = [
        entry for entry in packages if entry.get("name") != SYNTHETIC_PACKAGE_NAME
    ]
    document["packages"].append(
        {
            "name": SYNTHETIC_PACKAGE_NAME,
            "rootUri": "flutter_build/",
            "packageUri": "",
            "languageVersion": language_version,
        }
    )

    original_mode = path.stat().st_mode
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        delete=False,
    ) as temporary_file:
        json.dump(document, temporary_file, ensure_ascii=False, separators=(",", ":"))
        temporary_file.write("\n")
        temporary_path = Path(temporary_file.name)
    os.chmod(temporary_path, original_mode)
    os.replace(temporary_path, path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("package_config", type=Path)
    args = parser.parse_args()
    prepare_package_config(args.package_config)
    print("prepared Flutter package config for path-private compilation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
