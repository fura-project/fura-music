#!/usr/bin/env python3
"""Fail closed on missing unprivileged WebKit/bubblewrap prerequisites.

This is an environment preflight, never proof of AppImage startup. Output is
fixed categories and numeric kernel policy only, not raw process/tool output.
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path


POLICIES = {
    "USERNS_CLONE": "/proc/sys/kernel/unprivileged_userns_clone",
    "MAX_USER_NAMESPACES": "/proc/sys/user/max_user_namespaces",
    "APPARMOR_USERNS_RESTRICT": "/proc/sys/kernel/apparmor_restrict_unprivileged_userns",
    "APPARMOR_UNCONFINED_RESTRICT": "/proc/sys/kernel/apparmor_restrict_unprivileged_unconfined",
}


def diagnostics() -> None:
    for label, name in POLICIES.items():
        try:
            value = Path(name).read_text().strip()
        except OSError:
            value = "UNAVAILABLE"
        print(f"{label}={value if value.isdecimal() else 'UNAVAILABLE'}")
    for label in ("uid_map", "gid_map"):
        try:
            rows = [tuple(map(int, row.split())) for row in Path("/proc/self", label).read_text().splitlines()]
            valid = all(len(row) == 3 for row in rows)
        except (OSError, ValueError):
            rows, valid = [], False
        print(f"{label.upper()}_ROWS={len(rows) if valid else 'UNAVAILABLE'}")
    try:
        status = Path("/proc/self/status").read_text()
    except OSError:
        status = ""
    for label in ("Seccomp", "NoNewPrivs", "CapEff", "CapBnd"):
        match = re.search(rf"^{label}:\s*([0-9a-f]+)$", status, re.MULTILINE)
        print(f"{label.upper()}={match[1] if match else 'UNAVAILABLE'}")


def failure_category(stderr: bytes) -> str:
    if b"uid map" in stderr:
        return "USER_NAMESPACE_UID_MAP_DENIED"
    if b"gid map" in stderr:
        return "USER_NAMESPACE_GID_MAP_DENIED"
    return "USER_OR_MOUNT_NAMESPACE_UNAVAILABLE"


def main() -> int:
    if os.geteuid() == 0:
        print("SANDBOX_PREFLIGHT_INVALID: MUST_RUN_AS_ORDINARY_USER")
        return 1
    if os.environ.get("WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS"):
        print("SANDBOX_PREFLIGHT_INVALID: SANDBOX_BYPASS_ENVIRONMENT")
        return 1
    diagnostics()
    try:
        result = subprocess.run(
            ["bwrap", "--unshare-user", "--unshare-pid", "--ro-bind", "/", "/",
             "--proc", "/proc", "--dev", "/dev", "/bin/true"],
            capture_output=True, timeout=15, check=False,
        )
    except subprocess.TimeoutExpired:
        print("ENVIRONMENT_BLOCKED: NAMESPACE_PROBE_TIMEOUT")
        return 78
    except OSError:
        print("ENVIRONMENT_BLOCKED: BUBBLEWRAP_UNAVAILABLE")
        return 78
    if result.returncode:
        print("ENVIRONMENT_BLOCKED: " + failure_category(result.stderr))
        return 78
    print("SANDBOX_NAMESPACE_PREFLIGHT_PASS: APPIMAGE_LAUNCH_NOT_YET_TESTED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
