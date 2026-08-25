# Credential storage evidence

- **Status:** Active research for M1 authentication
- **Last checked:** 2026-08-26
- **Scope:** Selecting the minimum cross-platform persistence boundary for QQ Music credentials.

## Sources inspected

1. [`flutter_secure_storage` package documentation](https://pub.dev/packages/flutter_secure_storage), including Android backup, Apple entitlement, Linux dependency, and platform encryption notes.
2. [Official `flutter_secure_storage` repository](https://github.com/juliansteenbakker/flutter_secure_storage), including the federated platform implementations and BSD-3-Clause license.
3. [Upstream issue #1224](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1224), documenting that 11.0.0's compile-SDK 37 requirement does not build with the current default Flutter/AGP line.
4. [`keyring` 4 feature documentation](https://docs.rs/crate/keyring/latest/features) and [official repository](https://github.com/open-source-cooperative/keyring-rs), including native desktop stores and the Android feature.
5. [Official Android native keyring store](https://github.com/open-source-cooperative/android-native-keyring-store), including its JNI and `ndk-context` initialization requirements.

Only public documentation, dependency metadata, build behavior, and local system capabilities were inspected. No test credential or marker was written to the user's keyring.

## Selected package and boundary

`flutter_secure_storage` 10.3.1 is BSD-3-Clause licensed and declares Android, iOS, Linux, macOS, web, and Windows implementations. This application does not target web. Version 10's Android implementation uses its rewritten custom RSA-OAEP/AES-GCM storage path and compiles with SDK 36. The project uses no deprecated v9 cipher option and has never distributed a credential, so it does not skip a required migration state.

Version 11.0.0 was initially selected, but its Android module hard-codes compile SDK 37 while this Flutter 3.47.1 line defaults to 36 and the installed current platform is named `android-37.0`, not the `android-37` target requested by the integer Gradle DSL. The first ASCII-root Android build reproduced the same incompatibility currently recorded upstream. The project therefore pins the latest compatible v10 release instead of overriding the dependency's declared compile SDK or maintaining a fork. Pub can still resolve the independently versioned Linux 3.0.2 and Windows 4.2.2 implementations through v10's compatible constraints, retaining their current platform fixes. Reassess v11 after upstream and the supported Flutter/AGP toolchain agree on SDK 37.

The official package guidance requires Android backups to exclude its encrypted preferences because the restored encryption key is not available on another device. The application therefore disables Android backup instead of maintaining an incomplete exclusion list. Apple targets declare the documented Keychain entitlement. Linux requires `libsecret` development support.

The project configures a dedicated Android storage namespace, prevents plugin errors from silently deleting the stored value, disables Apple synchronization, and uses device-local after-first-unlock accessibility. These are storage mechanics only. Rust owns a versioned credential document and revalidates all invariants when it is later imported. The plugin accepts strings, so Dart creates a transient Base64 string that cannot be deterministically zeroized; the mutable FFI byte buffer is still zeroed after the awaited write.

## Local verification

On the 2026-08-25 Manjaro development host:

- `libsecret-1` reports 0.21.7 and `secret-tool` is installed;
- the user D-Bus session exposes `org.freedesktop.secrets` through KDE's secret-service compatibility process;
- `flutter build linux --release` links the federated plugin successfully;
- the Linux Flutter integration smoke starts the packaged app and reaches the typed Rust provider status.

On 2026-08-25 `integration_test/secure_storage_linux_test.dart` performed a live write/read/delete cycle through the configured Flutter adapter using a randomized non-account key. It never called `deleteAll`, and `finally` repeated deletion and confirmed the test key read back as absent. This verifies Linux runtime access on the current host without proving Android, iOS, macOS, or Windows behavior.

## Deferred Rust-only alternative

`keyring` 4.1.6 now includes Secret Service, Apple, Windows, and Android stores. The Android store requires Java-side initialization and a valid Android context before use. There is not yet current evidence for the correct Flutter-engine/JNI lifecycle wiring in this repository. It remains a possible future replacement if the Flutter plugin becomes unsuitable, but replacing a working boundary without such evidence would be speculative.

## Remaining evidence

1. Verify the eligible credential retained by Rust with QQ Music; local import now distinguishes absent, corrupt, unsupported, invalid, and expired values without authenticating them.
2. Add a disposable per-platform integration that writes, reads, and deletes non-account test bytes without leaving a keyring item behind.
3. Build and run Android plus the available Apple/Windows targets before claiming their secure persistence path.
