#!/usr/bin/env python3
"""Build a Flutter artifact without embedding maintainer build paths."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

from prepare_flutter_package_config import private_package_config


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FLUTTER_PROJECT = REPOSITORY_ROOT / "apps" / "flutter"
PACKAGE_CONFIG = FLUTTER_PROJECT / ".dart_tool" / "package_config.json"
SUPPORTED_TARGETS = {"apk", "ios", "linux", "macos", "windows"}
PRIVATE_REGISTRANT_DEFINE = "--dart-define=FURA_PATH_PRIVATE_REGISTRANT=1"


def encoded_rust_flags(
    existing: str,
    source_root: Path,
    user_home: Path,
) -> str:
    flags = [flag for flag in existing.split("\x1f") if flag]
    flags.extend(
        [
            f"--remap-path-prefix={source_root.resolve()}=/fura-source",
            f"--remap-path-prefix={user_home.resolve()}=/fura-build",
        ]
    )
    return "\x1f".join(dict.fromkeys(flags))


def run(command: list[str], environment: dict[str, str]) -> None:
    subprocess.run(command, cwd=FLUTTER_PROJECT, env=environment, check=True)


def main() -> int:
    build_arguments = sys.argv[1:]
    if not build_arguments or build_arguments[0] not in SUPPORTED_TARGETS:
        targets = ", ".join(sorted(SUPPORTED_TARGETS))
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} <{targets}> [build options]")
    forbidden_options = {"--config-only", "--no-config-only", "--pub", "--no-pub"}
    supplied_forbidden = forbidden_options.intersection(build_arguments)
    if supplied_forbidden:
        raise SystemExit(
            "build lifecycle options are owned by the privacy wrapper: "
            + ", ".join(sorted(supplied_forbidden))
        )

    flutter = shutil.which("flutter")
    if flutter is None:
        raise SystemExit("flutter executable is unavailable")
    environment = os.environ.copy()
    environment["CARGO_ENCODED_RUSTFLAGS"] = encoded_rust_flags(
        environment.get("CARGO_ENCODED_RUSTFLAGS", ""),
        REPOSITORY_ROOT,
        Path.home(),
    )

    # Generated package: vs file: registrant URIs must not share an incremental
    # kernel. Flutter keys its kernel by dart-defines, not by this URI mapping.
    # This compile-only namespace does not select a runtime playback stack.
    base_command = [flutter, "build", *build_arguments, PRIVATE_REGISTRANT_DEFINE]
    run([*base_command, "--config-only"], environment)
    with private_package_config(PACKAGE_CONFIG):
        run([*base_command, "--no-pub"], environment)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
