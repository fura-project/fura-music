#!/usr/bin/env python3
"""Verify the single enabled Android MEDIA_BUTTON receiver contract."""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET


ANDROID = "{http://schemas.android.com/apk/res/android}"
MEDIA_BUTTON = "android.intent.action.MEDIA_BUTTON"
AUDIO_SERVICE = "com.ryanheise.audioservice.AudioService"
AUDIO_SERVICE_RECEIVER = "com.ryanheise.audioservice.MediaButtonReceiver"
FLUTTER_MEDIA_SESSION_SERVICE = (
    "dev.wyrin.flutter_media_session.FlutterMediaSessionService"
)
FLUTTER_MEDIA_SESSION_RECEIVER = "androidx.media3.session.MediaButtonReceiver"
CONNECTED_DEVICE_PERMISSION = "android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest_xml")
    args = parser.parse_args()

    root = ET.parse(args.manifest_xml).getroot()
    application = root.find("application")
    if application is None:
        raise SystemExit("Android manifest has no application element")

    declared: list[tuple[str, bool]] = []
    for receiver in application.findall("receiver"):
        actions = {
            action.get(f"{ANDROID}name")
            for intent_filter in receiver.findall("intent-filter")
            for action in intent_filter.findall("action")
        }
        if MEDIA_BUTTON not in actions:
            continue
        name = receiver.get(f"{ANDROID}name")
        if not name:
            raise SystemExit("MEDIA_BUTTON receiver has no android:name")
        enabled = receiver.get(f"{ANDROID}enabled", "true") != "false"
        declared.append((name, enabled))

    expected = [(FLUTTER_MEDIA_SESSION_RECEIVER, True)]
    if declared != expected:
        print(f"declared MEDIA_BUTTON receivers: {declared}", file=sys.stderr)
        print(f"expected exactly: {expected}", file=sys.stderr)
        return 1

    services = application.findall("service")
    playback_services = [
        service for service in services
        if service.get(f"{ANDROID}name") == FLUTTER_MEDIA_SESSION_SERVICE
    ]
    if (
        len(playback_services) != 1
        or any(service.get(f"{ANDROID}name") == AUDIO_SERVICE for service in services)
        or any(
            receiver.get(f"{ANDROID}name") == AUDIO_SERVICE_RECEIVER
            for receiver in application.findall("receiver")
        )
    ):
        print("expected one enabled local playback service and no AudioService registrations", file=sys.stderr)
        return 1

    service = playback_services[0]
    # Merged source XML is symbolic; apkanalyzer prints the mediaPlayback bit
    # from binary XML as 0x2. Additional bits must still fail the gate.
    if (
        service.get(f"{ANDROID}enabled", "true") != "true"
        or service.get(f"{ANDROID}foregroundServiceType") not in ("mediaPlayback", "0x2")
        or any(
            permission.get(f"{ANDROID}name") == CONNECTED_DEVICE_PERMISSION
            for permission in root.findall("uses-permission")
        )
    ):
        print("expected a local mediaPlayback service without connected-device access", file=sys.stderr)
        return 1

    print(f"declared MEDIA_BUTTON receivers: {declared}")
    print(f"enabled MEDIA_BUTTON receiver: {FLUTTER_MEDIA_SESSION_RECEIVER}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
