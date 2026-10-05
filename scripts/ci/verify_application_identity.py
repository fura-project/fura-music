#!/usr/bin/env python3
"""Verify Fura's canonical public identity across first-party platform files."""

from __future__ import annotations

import sys
from pathlib import Path


APP_ID = "com.fura.flutterustmusic"
TEST_APP_ID = f"{APP_ID}.RunnerTests"
REPO_ROOT = Path(__file__).resolve().parents[2]


def require_contains(relative: str, needle: str, count: int | None = None) -> None:
    text = (REPO_ROOT / relative).read_text(encoding="utf-8")
    actual = text.count(needle)
    if actual == 0 or count is not None and actual != count:
        raise AssertionError(f"APPLICATION_IDENTITY_MISMATCH: {relative}")


def require_absent(relative: str) -> None:
    if (REPO_ROOT / relative).exists():
        raise AssertionError(f"OBSOLETE_APPLICATION_ID_PATH_FOUND: {relative}")


def main() -> int:
    personal_marker = bytes.fromhex("617869616f626f").decode("ascii")
    require_contains(
        "apps/flutter/android/app/build.gradle.kts", f'namespace = "{APP_ID}"'
    )
    require_contains(
        "apps/flutter/android/app/build.gradle.kts", f'applicationId = "{APP_ID}"'
    )
    for filename in ("FuraApplication.kt", "MainActivity.kt"):
        require_contains(
            f"apps/flutter/android/app/src/main/kotlin/com/fura/flutterustmusic/{filename}",
            f"package {APP_ID}",
        )
    require_absent(
        "apps/flutter/android/app/src/main/kotlin/"
        f"dev/{personal_marker}/flutterustmusic"
    )
    require_contains(
        "bridges/flutter/src/android_platform_verifier.rs",
        "Java_com_fura_flutterustmusic_"
        "FuraApplication_initializeRustlsPlatformVerifier",
    )

    require_contains(
        "apps/flutter/ios/Runner.xcodeproj/project.pbxproj",
        f"PRODUCT_BUNDLE_IDENTIFIER = {APP_ID};",
        count=3,
    )
    require_contains(
        "apps/flutter/ios/Runner.xcodeproj/project.pbxproj",
        f"PRODUCT_BUNDLE_IDENTIFIER = {TEST_APP_ID};",
        count=3,
    )
    require_contains(
        "apps/flutter/macos/Runner/Configs/AppInfo.xcconfig",
        f"PRODUCT_BUNDLE_IDENTIFIER = {APP_ID}",
        count=1,
    )
    require_contains(
        "apps/flutter/macos/Runner.xcodeproj/project.pbxproj",
        f"PRODUCT_BUNDLE_IDENTIFIER = {TEST_APP_ID};",
        count=3,
    )

    require_contains(
        "apps/flutter/linux/CMakeLists.txt", f'set(APPLICATION_ID "{APP_ID}")'
    )
    desktop = "packaging/linux/assets/com.fura.flutterustmusic.desktop"
    require_contains(desktop, "Name=fura music")
    require_contains(desktop, "Exec=flutterustmusic")
    require_contains(desktop, f"Icon={APP_ID}")
    require_contains(desktop, f"StartupWMClass={APP_ID}")
    require_contains("packaging/linux/lib.sh", f"app_id={APP_ID}")

    require_contains(
        "apps/flutter/windows/runner/Runner.rc",
        'VALUE "CompanyName", "Fura Project"',
    )
    require_contains(
        "apps/flutter/windows/runner/Runner.rc",
        'VALUE "LegalCopyright", '
        '"Copyright (C) 2026 Fura contributors."',
    )
    require_contains("LICENSE", "Copyright (c) 2026 Fura contributors")
    print("application identity verification passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from None
