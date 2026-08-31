# Cross-platform development test packages

The `Cross-platform development packages` GitHub Actions workflow builds short-lived artifacts for maintainer-operated runtime testing. It is manual-only: open **Actions**, select the workflow, choose the branch or commit, and select **Run workflow**. Artifacts are attached to that workflow run for seven days.

These artifacts are not releases. They retain the current generated application identity and have not completed production signing, notarization, store packaging, or the native-video distribution-notice review tracked by HD-001, TD-002, and TD-006. Do not redistribute or publish them.

## Artifacts and truthful test boundary

| Artifact | Intended use | Important boundary |
| --- | --- | --- |
| `flutterustmusic-android-arm64-development.apk` | Physical ARM64 Android phone or tablet | Built in Release mode but signed with the repository's development/debug key. It is not a production APK. |
| `flutterustmusic-android-x64-debug.apk` | x64 Android Emulator | Debug-only emulator package; it does not prove ARM64 physical-device behavior. |
| `flutterustmusic-linux-x64-development.tar.gz` | x64 Linux desktop | Extract the complete `bundle/` directory and run `bundle/flutterustmusic`. The target still needs compatible GTK, libsecret, GStreamer, and desktop-session libraries. |
| `flutterustmusic-windows-x64-development.zip` | x64 Windows 10 or 11 | Extract the whole directory before launching `flutterustmusic.exe`; individual DLLs must remain beside the executable. It is not MSIX-signed or Store-packaged. |
| `flutterustmusic-macos-development.zip` | macOS architecture(s) listed in `MACOS_ARCHITECTURES.txt` | The `.app` is neither Developer ID signed nor notarized. It is a compile/test artifact, not a distributable macOS release. |
| `flutterustmusic-ios-simulator-development.zip` | Xcode iOS Simulator architecture(s) listed in `IOS_SIMULATOR_ARCHITECTURES.txt` | Debug-mode Simulator package. Flutter does not support mobile Release mode on a simulator. It cannot be installed on a physical iPhone or iPad and does not prove physical-device background audio, lock-screen controls, or Keychain behavior. |

There is no Web artifact because the product's Rust core, secure-storage, native audio/video, and operating-system media integrations are native-target capabilities; Web is not a supported product target.

## What CI proves

Before packaging begins, one Ubuntu job runs the locked Rust workspace format, test, and strict Clippy gates plus Dart formatting, `dart analyze`, and all Flutter tests. Platform jobs then prove that the named source revision compiles into the named package. The Android job additionally verifies that the ARM64 Release APK declares Internet access and contains the expected ARM64 Rust bridge library. Linux additionally runs the isolated system-media initialization integration under a temporary D-Bus/X11 session.

A green workflow does not prove real-account QQ Music behavior, physical Android or Apple behavior, Windows SMTC usability, Linux desktop-shell integration, codecs on another machine, signing, notarization, store acceptance, or release readiness. Those observations remain per-target maintainer tests.

Each artifact includes `FLUTTER_VERSION.txt`, `RUST_VERSION.txt`, and this boundary note so the toolchain and claim do not become detached from the binary.
