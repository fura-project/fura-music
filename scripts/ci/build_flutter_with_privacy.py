#!/usr/bin/env python3
"""Build a Flutter artifact without embedding maintainer build paths."""

from __future__ import annotations

import json
import os
import shlex
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
    # rustc remapping is textual, NOT Windows path normalization. Cargo paths
    # can use forward slashes too. A native-backslash-only map
    # leaves file!()/panic locations embedded in the DLL's .rdata unchanged.
    # Keep source after HOME: rustc applies the last matching prefix.
    for root, replacement in ((user_home, "/fura-build"), (source_root, "/fura-source")):
        prefix = str(root.resolve())
        variants = [prefix]
        if target == "windows":
            variants.extend((prefix.replace("\\", "/"), prefix.replace("/", "\\")))
        flags.extend(f"--remap-path-prefix={value}={replacement}"
                     for value in dict.fromkeys(variants))
    if target == "windows":
        # Rust remapping does not affect the linker's CodeView/RSDS PDB path.
        flags.extend(["-C", "link-arg=/PDBALTPATH:%_PDB%"])
    # Do not deduplicate individual tokens: repeated -C is meaningful.
    return "\x1f".join(flags)


def native_build_environment(environment: dict[str, str], target: str,
                             source: Path, home: Path) -> None:
    environment["FURA_PRIVATE_BUILD"] = "1"
    if target == "windows":
        windows_aws_lc_environment(environment, source, home)
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


def windows_aws_lc_environment(environment: dict[str, str], source: Path, home: Path) -> None:
    """Map native __FILE__ in the locked AWS-LC dependency, not just Rust.

    aws-lc-sys 0.44's cc builder supports crate/target scoped CC and CFLAGS,
    but deliberately adds no prefix maps for cl-like drivers. clang-cl keeps
    the existing MSVC target/CRT ABI and accepts explicit /clang: prefix maps.
    Flutter/plugins still use MSVC; no crypto source or provider is replaced.
    """
    compiler = shutil.which("clang-cl")
    if compiler is None:
        raise SystemExit("PRIVATE_NATIVE_C_COMPILER_UNAVAILABLE: CLANG_CL_REQUIRED")
    triple = "x86_64_pc_windows_msvc"

    def effective(name: str) -> str | None:
        for key in (f"AWS_LC_SYS_{name}_{triple}", f"AWS_LC_SYS_{name}",
                    f"{name}_{triple}", name):
            if key in environment:
                return environment[key]
        return None

    original_flags = effective("HOST_CFLAGS")
    if original_flags is None:
        original_flags = effective("CFLAGS") or ""
    maps = []
    for root, replacement in ((home, "/fura-build"), (source, "/fura-source")):
        prefix = str(root.resolve())
        for value in dict.fromkeys((prefix, prefix.replace("\\", "/"), prefix.replace("/", "\\"))):
            maps.append(f"/clang:-ffile-prefix-map={value}={replacement}")
    # The native Windows packaging target equals its host. Highest-priority
    # crate/target keys avoid changing CC/CFLAGS for ring or Flutter plugins.
    environment[f"AWS_LC_SYS_HOST_CC_{triple}"] = compiler
    environment[f"AWS_LC_SYS_HOST_CFLAGS_{triple}"] = (original_flags + " " + shlex.join(maps)).strip()
    environment["AWS_LC_SYS_CMAKE_BUILDER"] = "0"
    environment["CC_SHELL_ESCAPED_FLAGS"] = "1"


def run(command: list[str], environment: dict[str, str]) -> None:
    subprocess.run(command, cwd=FLUTTER_PROJECT, env=environment, check=True)


def verify_windows_cargo_flags(build_root: Path, expected: str) -> None:
    """Read Cargo's actual target compile fingerprint, not just wrapper env.

    No paths, compiler args or fingerprint contents are printed. Host build
    scripts have separate fingerprints and do not produce the shipped DLL.
    """
    records = [p for p in build_root.rglob("lib-rust_lib_flutterustmusic.json")
               if p.parent.parent.name == ".fingerprint"
               and p.parent.parent.parent.name == "release"
               and p.parent.parent.parent.parent.name == "x86_64-pc-windows-msvc"]
    if not records:
        raise RuntimeError("PRIVATE_RUST_FLAGS_EVIDENCE_MISSING")
    try:
        # Incremental trees retain fingerprints from previous flag sets. They
        # are not the current build; require a target compile with this exact
        # flag set, while the independent final DLL/ZIP audit stays mandatory.
        verified = any(json.loads(p.read_text(encoding="utf-8"))["rustflags"] == expected.split("\x1f")
                       for p in records)
    except (OSError, ValueError, KeyError, TypeError):
        raise RuntimeError("PRIVATE_RUST_FLAGS_EVIDENCE_INVALID") from None
    if not verified:
        raise RuntimeError("PRIVATE_RUST_FLAGS_NOT_APPLIED")
    print("PRIVATE_RUST_FLAGS_VERIFIED: cargo-target-fingerprint")


def verify_windows_aws_lc_flags(build_root: Path, environment: dict[str, str]) -> None:
    required = {key: environment[key] for key in (
        "AWS_LC_SYS_HOST_CC_x86_64_pc_windows_msvc",
        "AWS_LC_SYS_HOST_CFLAGS_x86_64_pc_windows_msvc",
        "AWS_LC_SYS_CMAKE_BUILDER",
    )}
    records = [p for p in build_root.rglob("run-build-script-*.json")
               if p.parent.name.startswith("aws-lc-sys-")
               and p.parent.parent.name == ".fingerprint"
               and p.parent.parent.parent.name == "release"
               and p.parent.parent.parent.parent.name == "x86_64-pc-windows-msvc"]
    try:
        observed = []
        for path in records:
            local = json.loads(path.read_text(encoding="utf-8"))["local"]
            values = {row["RerunIfEnvChanged"]["var"]: row["RerunIfEnvChanged"]["val"]
                      for row in local if "RerunIfEnvChanged" in row}
            observed.append(all(values.get(key) == value for key, value in required.items()))
    except (OSError, ValueError, KeyError, TypeError):
        raise RuntimeError("PRIVATE_NATIVE_C_FLAGS_EVIDENCE_INVALID") from None
    if not any(observed):
        raise RuntimeError("PRIVATE_NATIVE_C_FLAGS_NOT_APPLIED")
    print("PRIVATE_NATIVE_C_FLAGS_VERIFIED: cargo-build-script-fingerprint")


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
    if build_arguments[0] == "windows":
        try:
            verify_windows_cargo_flags(FLUTTER_PROJECT / "build" / "windows",
                                      environment["CARGO_ENCODED_RUSTFLAGS"])
            verify_windows_aws_lc_flags(FLUTTER_PROJECT / "build" / "windows", environment)
        except RuntimeError as error:
            raise SystemExit(str(error)) from None
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
