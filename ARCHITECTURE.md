# Architecture

This document describes the architecture currently accepted for implementation. Module-specific details must only be added after the corresponding code exists.

## System shape

```text
Flutter presentation
        |
        | typed in-process bridge
        v
Rust application/core API
        |
        +--> music domain
        +--> provider API and registry
        +--> QQMusicProvider
                  |
                  v
            QQMusicClient
                  |
                  v
              QQ Music
```

There is no runtime HTTP sidecar between Flutter and the Rust core.

## Dependency direction

- Presentation depends on generated or explicit bridge types, never raw QQ Music response models.
- The bridge adapts calls and data ownership. It does not contain product business rules.
- Provider implementations depend on provider interfaces and project domain models.
- `QQMusicProvider` maps raw protocol results from `QQMusicClient` into stable project domain models.
- `QQMusicClient` owns transport, request construction, cookies, session details, signing/QIMEI when required, and raw protocol models. It does not know Flutter.

## Current modules

- `apps/flutter` contains the Material 3 adaptive login surface, its short-lived Dart controller/gateway adapter, a narrow platform secure-storage adapter, and Dart integration/widget tests.
- `crates/music-domain` contains provider-independent identity types. It currently defines only `ProviderId`.
- `crates/provider-api` contains the UI-free provider descriptor, capabilities, baseline provider trait, and provider-neutral QR authentication challenge/progress/error contracts.
- `crates/qqmusic-client` owns the raw QQ Music client boundary. It currently contains the redacted credential/restore model, versioned secure-storage serialization, a small asynchronous HTTP contract with a Rustls-backed native implementation, cross-validated WeChat QR bootstrap/poll/exchange requests, and a cancellable generation-based login coordinator.
- `crates/provider-qqmusic` owns the QQ Music login coordinator, maps raw QR protocol states into provider contracts, retains a successful credential inside Rust, and exports only its versioned opaque persistence document. It currently declares only the implemented authentication capability.
- `bridges/flutter` adapts core/provider status and authentication into presentation-safe generated types. Its one secret-bearing operation is a dedicated short-lived persistence handoff, not a presentation model.

The current concrete bootstrap flow is:

```text
Flutter main
  -> RustLib.init
  -> bridge bootstrap_status
  -> QqMusicProvider descriptor
  -> typed BootstrapStatus
  -> Flutter bootstrap page
```

The raw authentication flow reaches a validated credential inside the core:

```text
QQMusicClient
  -> WeChat QR connect page
  -> bounded UUID parsing
  -> QR image fetch and signature validation
  -> transient unconfirmed QR session
  -> one bounded long-poll
  -> protocol state or internal redacted authorization code
  -> named musicu Login RPC
  -> validated redacted Credential
```

Request/response diagnostics omit query values, headers, bodies, QR identifiers, image bytes, authorization codes, credential keys, and refresh material. The one-shot client remains independent of UI state. A separate login coordinator owns attempt generations: starting again supersedes the old generation, cancellation/disposal drops in-flight create/poll/exchange futures, and a credential is accepted only while its generation is current. Authorization codes never need to leave that coordinator. One monotonic 180-second deadline spans QR creation, polling, and exchange; it drops blocked requests. Three consecutive transport failures are caller-retryable, the fourth finishes the session, and any reached protocol response resets the count. The coordinator does not hide polling or retry loops. Default protocol tests use synthetic sanitized responses; live tests are separate, ignored, and explicitly environment-gated.

The typed authentication boundary is:

```text
Flutter
  -> start WeChat QR login
  -> Rust-opaque session handle + image bytes/media type
  -> explicit advance/cancel calls
  -> Provider-neutral progress or failure enum
  -> coarse authentication and persistence state

Rust opaque session
  -> QQMusicProvider QR session
  -> WechatQrLoginCoordinator
  -> Credential retained inside QQMusicProvider
```

The opaque handle exposes no fields and carries generation-specific cancellation authority, so cancelling an old Dart object cannot cancel its replacement. Concurrent `advance` calls fail explicitly instead of creating a hidden polling queue.

After successful authentication, credential persistence follows a separate narrow path:

```text
QQMusicProvider credential
  -> Rust versioned serialization and invariant checks
  -> dedicated Bridge export of short-lived opaque bytes
  -> Dart platform-vault adapter (Base64 transport envelope only)
  -> flutter_secure_storage
  -> native platform secure storage
```

The controller sees only stored/unavailable status. It cannot inspect credential fields. The mutable bridge buffer is zeroed after the asynchronous write. Secure write alone does not satisfy credential restore; TD-003 remains in progress until QQ Music accepts a startup candidate.

Startup now performs the reverse narrow handoff before constructing the login controller:

```text
native platform secure storage
  -> Dart vault read and Base64 decode
  -> dedicated Bridge import of optional opaque bytes
  -> Rust version/invariant validation and local expiry plan
  -> signed out | verification required | locally expired | typed failure
```

The loaded Dart byte buffer is zeroed after the synchronous Rust import. Rust retains verification and locally expired candidates in distinct internal states, and neither makes `has_authenticated_credential` true. Malformed, unsupported, and platform-access failures remain distinct and are never auto-deleted. Server verification is the remaining TD-003 step.

QR creation has a separate opaque start-attempt number reserved by the Bridge adapter before network work begins. Cancel/restart/dispose can cancel that exact pending creation; comparison against the current start attempt prevents a late old controller from cancelling its replacement. After a challenge returns, the Dart controller discards that start operation and uses the Rust-owned session handle. Dart owns presentation stages, one-second network-reconnect delay, adaptive layout, animation, and late-result visibility guards. Rust remains the authority for protocol deadlines, failure counts, session generations, and credential state.

## Flutter / Rust boundary

Place logic in Rust when it would remain useful if Flutter were replaced by another UI toolkit. Keep logic in Dart when it exists primarily to present or interact with the current UI.

The bridge must not synchronize hover, focus, animation progress, navigation rail state, or dialog visibility. It may expose coarse application operations, opaque operation handles, and serializable domain results. Opaque handles must not expose raw provider session identifiers or secret material.

The current bridge is generated by `flutter_rust_bridge` 2.13.0. Linux builds its bridge crate directly with system Cargo because the generated Cargokit backend requires rustup; this localized exception is tracked as TD-001. Other platform build paths remain generated and are not yet validated.

## Provider architecture

Providers expose data plus explicit capabilities such as authentication, catalog, user library, lyrics, and media resolution. A provider can implement only a subset. The first implementation is QQ Music; capability interfaces must remain small enough to reflect proven behavior.

Provider code never returns Flutter widgets or presentation-specific models.

## Playback and storage

The detailed playback and general storage architectures do not exist yet and are intentionally not specified. They will be documented when the first vertical slice introduces real implementations.

Credential semantics and serialization remain in Rust. `flutter_secure_storage` is a platform integration edge only; it stores one opaque versioned document and cannot declare a user authenticated. Android backup is disabled, Apple synchronization is disabled, and corrupt or unavailable storage must remain distinguishable from an upstream credential rejection. See ADR 0003 and TD-004 for the current verification boundary.

## Forbidden dependencies

- Flutter presentation importing or reimplementing QQ Music protocol behavior.
- Rust core managing purely visual interaction state.
- Project domain types depending on provider response packages or Flutter types.
- A localhost Node, Python, or Rust API server as the normal application path.
- Provider-owned application UI.
