#!/usr/bin/env python3
"""Give Flutter's generated Dart plugin registrant a stable package URI."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from contextlib import contextmanager
from pathlib import Path


SYNTHETIC_PACKAGE_NAME = "fura_generated_plugin_registry"


def write_package_config(path: Path, contents: bytes) -> None:
    original_mode = path.stat().st_mode
    with tempfile.NamedTemporaryFile(
        "wb", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as temporary_file:
        temporary_file.write(contents)
        temporary_path = Path(temporary_file.name)
    os.chmod(temporary_path, original_mode)
    os.replace(temporary_path, path)


@contextmanager
def private_package_config(path: Path):
    """Scope the generated URI mapping to a private artifact compilation.

    Flutter's incremental kernel key does not include this generated URI. Never
    leave the mapping in the ordinary pub config after a build (including a
    failed build). Remove a stale mapping left by older wrapper versions too.
    """
    original = path.read_bytes()
    document = json.loads(original)
    packages = document["packages"]
    if any(entry.get("name") == SYNTHETIC_PACKAGE_NAME for entry in packages):
        document["packages"] = [
            entry for entry in packages if entry.get("name") != SYNTHETIC_PACKAGE_NAME
        ]
        original = (json.dumps(document, ensure_ascii=False) + "\n").encode("utf-8")
    try:
        prepare_package_config(path)
        yield
    finally:
        write_package_config(path, original)


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

    write_package_config(
        path,
        (json.dumps(document, ensure_ascii=False, separators=(",", ":")) + "\n").encode(
            "utf-8"
        ),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("package_config", type=Path)
    args = parser.parse_args()
    prepare_package_config(args.package_config)
    print("prepared Flutter package config for path-private compilation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
