# ADR 0003 — Platform secure storage with Rust-owned credential semantics

- **Status:** Accepted
- **Date:** 2026-08-25

## Context

M1 requires a QQ Music session to survive process restart. The credential includes account identity, music keys, and refresh material, so ordinary files, preferences, and UI state are not acceptable persistence boundaries. Rust already owns credential validation and restore policy, while Flutter owns platform application integration.

The first persistence slice needs to support the generated Android, iOS, Linux, macOS, and Windows shells without introducing a localhost service or a second business layer.

## Decision

Use `flutter_secure_storage` 11 as a narrow platform-keystore adapter. Rust serializes and validates one versioned credential document. A dedicated Bridge call exports that document as short-lived opaque bytes only after authentication. Dart Base64-encodes those bytes solely because the plugin stores strings, writes one namespaced key, and zeroes the mutable bridge buffer after the asynchronous write finishes.

Credential field names and semantics do not enter the controller or UI. Storage success and failure are reduced to coarse presentation state. Android automatic backup is disabled, Apple targets declare Keychain access, Apple synchronization is disabled, and Apple items use `first_unlock_this_device` accessibility.

The plugin is allowed to provide platform encryption and key-store integration; it does not decide whether a credential is structurally valid, expired, accepted by QQ Music, refreshable, or authenticated. Startup import and server verification are a separate next slice.

## Alternatives

- Plain JSON, Flutter preferences, or a project-owned encrypted file.
- A Rust-only `keyring` integration.
- A localhost credential service.
- Persisting individual credential fields through generated Dart models.

## Why

The selected package is maintained, BSD-3-Clause licensed, declares every generated native target, and linked successfully in the current Linux release build. Its platform implementations use native secure-storage facilities and keep key custody outside project-owned files.

Rust `keyring` 4 now has broad desktop and Android support, but its Android store requires explicit JNI/Android-context initialization. This checkout has no verified way to connect that lifecycle safely through the Flutter engine yet. Adopting it now would make Android integration, rather than credential restore, the architecture experiment.

## Consequences

- Secret bytes cross FFI for one dedicated storage operation, remain in process memory briefly, and must never be logged, cached, or exposed to ordinary presentation types. Dart can zero the mutable byte buffer, but the plugin's required immutable Base64 `String` remains eligible for garbage collection rather than deterministic zeroization.
- Rust remains the only authority that can serialize or accept a persisted credential.
- Corrupt plugin values and platform failures are surfaced rather than silently treated as signed-out state.
- The current Linux build and smoke test prove linking and plugin registration, not a real keyring write/read/delete cycle.
- Each target still needs disposable runtime storage verification before its authenticated build can be called release-ready; this is tracked as TD-004.
