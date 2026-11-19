#!/usr/bin/env python3
"""Check Flutter's generated federated plugin selection after pub get."""

import json
from pathlib import Path


def main():
    app = Path(__file__).resolve().parents[2] / "apps/flutter"
    plugin_graph = json.loads(
        (app / ".flutter-plugins-dependencies").read_text(encoding="utf-8")
    )["plugins"]
    expected = {
        "linux": ("fura_webview_all_linux", False),
        "android": ("webview_all_android", True),
        "ios": ("webview_all_wkwebview", True),
        "macos": ("webview_all_wkwebview", True),
        "windows": ("webview_all_windows", True),
    }
    for platform, selection in expected.items():
        actual = [
            (plugin["name"], plugin.get("native_build"))
            for plugin in plugin_graph[platform]
            if "webview" in plugin["name"].lower()
        ]
        if actual != [selection]:
            raise SystemExit(f"Unexpected WebView implementation for {platform}: {actual}")

    for name in ("generated_plugins.cmake", "generated_plugin_registrant.cc"):
        generated = (app / "linux/flutter" / name).read_text(encoding="utf-8")
        if "webview" in generated.lower():
            raise SystemExit(f"WebView unexpectedly present in Linux native {name}")
    print("Linux Dart-only WebView registration and existing platform implementations verified")


if __name__ == "__main__":
    main()
