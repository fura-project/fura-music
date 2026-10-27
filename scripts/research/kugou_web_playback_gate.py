#!/usr/bin/env python3
"""Maintainer-operated, disconnected KuGou Web candidate. No browser automation."""

from __future__ import annotations

import argparse
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import warnings


def hidden(prompt: str) -> str:
    # Never allow getpass's echoing fallback when terminal control is unavailable.
    with warnings.catch_warnings():
        warnings.simplefilter("error", getpass.GetPassWarning)
        return getpass.getpass(prompt)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--human-authorized-once", action="store_true")
    parser.add_argument("--probe-range", action="store_true")
    args = parser.parse_args()
    if not args.human_authorized_once:
        print("KUGOU_GATE result=NOT_RUN reason=EXPLICIT_HUMAN_AUTHORIZATION_REQUIRED")
        return 0
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        print("KUGOU_GATE result=NOT_RUN reason=INTERACTIVE_HUMAN_REQUIRED")
        return 1
    print("Targets: https://wwwapi.kugou.com/play/songinfo; no other auth API.")
    print("Budget: one GET; no retry/redirect/fallback; no automatic account read.")
    print("Optional media budget: " + ("one 4096-byte Range on your pre-approved exact KuGou host." if args.probe_range else "zero."))
    print("Use only your disposable isolated official-Web session; never your daily browser profile.")
    print("Account confirmation is Human-owned, not a server account-summary verification.")
    print("Stop on CAPTCHA/SSA/429/access denial/device/signature challenge; do not rerun around it.")
    consent = input("To authorize this exact budget, type AUTHORIZE ONE KUGOU WEB REQUEST: ")
    if consent != "AUTHORIZE ONE KUGOU WEB REQUEST":
        print("KUGOU_GATE result=NOT_RUN reason=CONSENT_NOT_GIVEN")
        return 0
    repo = Path(__file__).resolve().parents[2]
    # Compile before collecting secrets; no credential enters Cargo's argv/env.
    build = subprocess.run(
        ["cargo", "build", "--offline", "--locked", "-p", "provider-kugou", "--example", "kugou_web_playback_gate"],
        cwd=repo, capture_output=True, check=False,
    )
    if build.returncode:
        print("KUGOU_GATE result=NOT_RUN reason=OFFLINE_BUILD_FAILED")
        return 1
    metadata = subprocess.run(
        ["cargo", "metadata", "--offline", "--locked", "--format-version", "1", "--no-deps"],
        cwd=repo, capture_output=True, check=False,
    )
    if metadata.returncode:
        print("KUGOU_GATE result=NOT_RUN reason=OFFLINE_METADATA_FAILED")
        return 1
    target = Path(json.loads(metadata.stdout)["target_directory"])
    executable = target / "debug/examples" / ("kugou_web_playback_gate.exe" if os.name == "nt" else "kugou_web_playback_gate")
    confirmed = input("Have YOU confirmed the intended account and full Standard playback permission in the isolated website? Type YES: ") == "YES"
    if not confirmed:
        print("KUGOU_GATE result=NOT_RUN reason=ACCOUNT_NOT_CONFIRMED")
        return 0
    payload = bytearray(json.dumps({
        "authorization": "I_AUTHORIZE_ONE_KUGOU_WEB_REQUEST",
        "account_confirmed_by_human": True,
        "official_origin": "https://www.kugou.com/",
        "cookie_header": hidden("Minimal KugooID/t Cookie header (hidden): "),
        "captured_songinfo_url": hidden("Fresh official-page signed songinfo URL (hidden): "),
        "track_opaque": hidden("Exact existing KuGou v1 Track context (hidden): "),
        "approved_media_host": hidden("Independently observed, explicitly approved exact media host (hidden): "),
        "probe_range": args.probe_range,
    }).encode())
    try:
        result = subprocess.run([str(executable), "--human-authorized-once"], input=payload,
                                capture_output=True, cwd=repo, check=False, timeout=50)
    finally:
        payload[:] = b"\0" * len(payload)
    lines = result.stdout.decode("ascii", errors="replace").splitlines()
    if len(lines) != 1 or not re.fullmatch(r"KUGOU_GATE result=(PASS|BLOCKED|NOT_RUN) [A-Za-z0-9_= ]+", lines[0]):
        print("KUGOU_GATE result=BLOCKED reason=UNEXPECTED_TOOL_OUTPUT")
        return 1
    print(lines[0])
    return result.returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("KUGOU_GATE result=NOT_RUN reason=HUMAN_CANCELLED")
        raise SystemExit(1) from None
    except (OSError, ValueError, KeyError, getpass.GetPassWarning, subprocess.TimeoutExpired):
        print("KUGOU_GATE result=BLOCKED reason=LOCAL_TOOL_FAILURE")
        raise SystemExit(1) from None
