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

- `apps/flutter` contains the Material 3 application shell, presentation-safe bootstrap page, and Dart integration/widget tests.
- `crates/music-domain` contains provider-independent identity types. It currently defines only `ProviderId`.
- `crates/provider-api` contains the UI-free provider descriptor, capabilities, baseline provider trait, and provider-neutral QR authentication challenge/progress/error contracts.
- `crates/qqmusic-client` owns the raw QQ Music client boundary. It currently contains the redacted credential/restore model, a small asynchronous HTTP contract with a Rustls-backed native implementation, cross-validated WeChat QR bootstrap/poll/exchange requests, and a cancellable generation-based login coordinator.
- `crates/provider-qqmusic` owns the QQ Music login coordinator, maps raw QR protocol states into provider contracts, and retains a successful credential inside Rust. It currently declares only the implemented authentication capability.
- `bridges/flutter` adapts core/provider status and authentication into presentation-safe generated types.

The current concrete bootstrap flow is:

```text
Flutter main
  -> RustLib.init
  -> bridge bootstrap_status
  -> QqMusicProvider descriptor
  -> typed BootstrapStatus
  -> Flutter bootstrap page
```

The raw authentication flow now reaches a validated credential inside the core, but is not yet a Provider/bridge capability:

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
  -> authenticated boolean only

Rust opaque session
  -> QQMusicProvider QR session
  -> WechatQrLoginCoordinator
  -> Credential retained inside QQMusicProvider
```

The opaque handle exposes no fields and carries generation-specific cancellation authority, so cancelling an old Dart object cannot cancel its replacement. Concurrent `advance` calls fail explicitly instead of creating a hidden polling queue. Credential persistence does not exist yet; the current in-memory state is tracked as TD-003.

## Flutter / Rust boundary

Place logic in Rust when it would remain useful if Flutter were replaced by another UI toolkit. Keep logic in Dart when it exists primarily to present or interact with the current UI.

The bridge must not synchronize hover, focus, animation progress, navigation rail state, or dialog visibility. It may expose coarse application operations, opaque operation handles, and serializable domain results. Opaque handles must not expose raw provider session identifiers or secret material.

The current bridge is generated by `flutter_rust_bridge` 2.13.0. Linux builds its bridge crate directly with system Cargo because the generated Cargokit backend requires rustup; this localized exception is tracked as TD-001. Other platform build paths remain generated and are not yet validated.

## Provider architecture

Providers expose data plus explicit capabilities such as authentication, catalog, user library, lyrics, and media resolution. A provider can implement only a subset. The first implementation is QQ Music; capability interfaces must remain small enough to reflect proven behavior.

Provider code never returns Flutter widgets or presentation-specific models.

## Playback and storage

The detailed playback and storage architectures do not exist yet and are intentionally not specified. They will be documented when the first vertical slice introduces real implementations. Credential material must not be logged or committed, and release-bound storage must use a platform-appropriate secure mechanism.

## Forbidden dependencies

- Flutter presentation importing or reimplementing QQ Music protocol behavior.
- Rust core managing purely visual interaction state.
- Project domain types depending on provider response packages or Flutter types.
- A localhost Node, Python, or Rust API server as the normal application path.
- Provider-owned application UI.
