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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest_xml")
    parser.add_argument("expected_receiver")
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

    enabled_receivers = [name for name, enabled in declared if enabled]
    if enabled_receivers != [args.expected_receiver]:
        print(f"declared MEDIA_BUTTON receivers: {declared}", file=sys.stderr)
        print(f"enabled MEDIA_BUTTON receivers: {enabled_receivers}", file=sys.stderr)
        print(f"expected exactly: {args.expected_receiver}", file=sys.stderr)
        return 1

    expected_services = {
        AUDIO_SERVICE_RECEIVER: {
            AUDIO_SERVICE: True,
            FLUTTER_MEDIA_SESSION_SERVICE: False,
        },
        FLUTTER_MEDIA_SESSION_RECEIVER: {
            AUDIO_SERVICE: False,
            FLUTTER_MEDIA_SESSION_SERVICE: True,
        },
    }
    if args.expected_receiver not in expected_services:
        raise SystemExit(f"unsupported expected receiver: {args.expected_receiver}")

    declared_services = {
        service.get(f"{ANDROID}name"): service.get(f"{ANDROID}enabled", "true")
        != "false"
        for service in application.findall("service")
    }
    expected = expected_services[args.expected_receiver]
    actual = {name: declared_services.get(name) for name in expected}
    if actual != expected:
        print(f"system-edge service states: {actual}", file=sys.stderr)
        print(f"expected service states: {expected}", file=sys.stderr)
        return 1

    print(f"declared MEDIA_BUTTON receivers: {declared}")
    print(f"enabled MEDIA_BUTTON receiver: {enabled_receivers[0]}")
    print(f"system-edge service states: {actual}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
