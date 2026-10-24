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
    target: str = "linux",
) -> str:
    flags = [flag for flag in existing.split("\x1f") if flag]
    flags.extend(
        [
            f"--remap-path-prefix={user_home.resolve()}=/fura-build",
            f"--remap-path-prefix={source_root.resolve()}=/fura-source",
        ]
    )
    if target == "windows":
        # Rust remapping does not affect the linker's CodeView/RSDS PDB path.
        flags.extend(["-C", "link-arg=/PDBALTPATH:%_PDB%"])
    # Do not deduplicate individual tokens: repeated -C is meaningful.
    return "\x1f".join(flags)


def native_build_environment(environment: dict[str, str], target: str,
                             source: Path, home: Path) -> None:
    environment["FURA_PRIVATE_BUILD"] = "1"
    if target == "macos":
        # Flutter's supported FLUTTER_XCODE_* mechanism applies these settings
        # to Runner and source-built plugins; it does not rewrite vendored code.
        settings = {
            "COPY_PHASE_STRIP": "YES",
            "DEPLOYMENT_POSTPROCESSING": "YES",
            "STRIP_INSTALLED_PRODUCT": "YES",
            "STRIP_STYLE": "non-global",
        }
        maps = " ".join(
            f'"-ffile-prefix-map={root.resolve()}={replacement}" '
            f'"-fdebug-prefix-map={root.resolve()}={replacement}"'
            for root, replacement in ((home, "/fura-build"), (source, "/fura-source"))
        )
        settings["OTHER_CFLAGS"] = "$(inherited) " + maps
        settings["OTHER_CPLUSPLUSFLAGS"] = "$(inherited) " + maps
        for name, value in settings.items():
            key = "FLUTTER_XCODE_" + name
            if name.startswith("OTHER_") and key in environment:
                value = environment[key] + " " + maps
            environment[key] = value


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
        build_arguments[0],
    )
    native_build_environment(environment, build_arguments[0], REPOSITORY_ROOT, Path.home())

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
