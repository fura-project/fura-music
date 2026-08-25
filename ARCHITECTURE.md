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

- `apps/flutter` contains adaptive Material 3 authentication, complete user-playlist collection, paged playlist-detail surfaces, short-lived Dart controllers/gateway adapters, one shared serialized platform-vault boundary, and Dart integration/widget tests.
- `crates/music-domain` contains provider-independent provider/playlist/track identities, playlist and track summaries, bounded playlist-track pages, and a redacted short-lived resolved-media source. Provider-owned identity values remain opaque outside their implementation.
- `crates/provider-api` contains the UI-free provider descriptor/capabilities plus provider-neutral QR authentication, owned/complete user-playlist, paged playlist-detail, and standard-media-resolution contracts.
- `crates/qqmusic-client` owns the raw QQ Music client boundary. It contains redacted credential/restore models, versioned secure-storage serialization, a Rustls-backed bounded HTTP implementation, cross-validated WeChat QR flows, credential verification, owned/favorite playlist fetching, ordinary/liked-songs detail-page fetching, and cancellable lifecycle coordinators.
- `crates/provider-qqmusic` retains credential state, maps raw authentication/playlist/track/media protocol values into provider/domain contracts, aggregates bounded owned/favorite pages, routes ordinary versus built-in liked detail pages, resolves the evidenced standard MP3 source, and truthfully advertises `Authentication`, `UserLibrary`, and `MediaResolution`.
- `bridges/flutter` adapts core/provider status, authentication, credential persistence, complete user-playlist loading, and one playlist-track page into presentation-safe generated types. Its secret-bearing operation remains a dedicated short-lived persistence handoff, not a presentation model.

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

The controller sees only stored/unavailable status. It cannot inspect credential fields. The mutable bridge buffer is zeroed after the asynchronous write. Secure write alone does not satisfy credential restore.

Startup now performs the reverse narrow handoff before constructing the login controller:

```text
native platform secure storage
  -> Dart vault read and Base64 decode
  -> dedicated Bridge import of optional opaque bytes
  -> Rust version/invariant validation and local expiry plan
  -> signed out | verification required | locally expired | typed failure
  -> exact verification attempt ID
  -> QQMusicProvider -> QQMusicClient user-info verification
  -> authenticated | rejected | retryable/typed failure
```

The loaded Dart byte buffer is zeroed after the synchronous Rust import. Rust retains verification and locally expired candidates in distinct internal states, and neither makes `has_authenticated_credential` true. The Provider promotes a candidate only when QQ Music returns zero global and named-result codes. Independently observed rejection codes clear in-memory state; transport, service, other upstream, and malformed-response failures retain the candidate for explicit retry. Malformed, unsupported, and platform-access failures remain distinct and are never auto-deleted. The Dart platform edge deletes secure storage only after an explicit rejection and reports cleanup failure separately. Authentication and library gateways share one serialized vault queue, so an old rejection cleanup cannot remove a newer QR credential.

Restore-verification attempt IDs are process-local cancellation authority, not QQ Music identifiers. The Provider checks both the exact attempt and candidate before and after network work. Starting a new QR login clears that authority, so a late verification cannot overwrite the replacement session. Dart additionally uses controller generations to suppress late presentation updates after retry, QR replacement, cancellation, or disposal.

QR creation has a separate opaque start-attempt number reserved by the Bridge adapter before network work begins. Cancel/restart/dispose can cancel that exact pending creation; comparison against the current start attempt prevents a late old controller from cancelling its replacement. After a challenge returns, the Dart controller discards that start operation and uses the Rust-owned session handle. Dart owns presentation stages, one-second network-reconnect delay, adaptive layout, animation, and late-result visibility guards. Rust remains the authority for protocol deadlines, failure counts, session generations, and credential state.

## Flutter / Rust boundary

Place logic in Rust when it would remain useful if Flutter were replaced by another UI toolkit. Keep logic in Dart when it exists primarily to present or interact with the current UI.

The bridge must not synchronize hover, focus, animation progress, navigation rail state, or dialog visibility. It may expose coarse application operations, opaque operation handles, and serializable domain results. Opaque handles must not expose raw provider session identifiers or secret material.

The current bridge is generated by `flutter_rust_bridge` 2.13.0. Linux builds its bridge crate directly with system Cargo because the generated Cargokit backend requires rustup; this localized exception is tracked as TD-001. Other platform build paths remain generated and are not yet validated.

## Provider architecture

Providers expose data plus explicit capabilities such as authentication, catalog, user library, lyrics, and media resolution. A provider can implement only a subset. The first implementation is QQ Music; capability interfaces must remain small enough to reflect proven behavior.

Provider code never returns Flutter widgets or presentation-specific models.

The first user-library operation loads authenticated account-owned playlists via `QQMusicClient` `PlaylistBaseRead/GetPlaylistByUin`. QQ-specific, diagnostics-redacted protocol summaries preserve both playlist and directory identifiers. `QQMusicProvider` maps them into provider-independent `PlaylistSummary` values whose `PlaylistId` contains a stable provider ID and an opaque provider-owned value; generic domain and Flutter code cannot parse QQ identity rules. The narrow `OwnedPlaylistsProvider` remains available for the created-only collection.

`QQMusicClient` also implements one bounded page of `PlaylistFavRead/CgiGetPlaylistFavInfo`. It requires the credential's encrypted UIN, constrains page size to 100, and returns typed pagination plus protocol summaries without performing hidden loops. `QQMusicProvider` implements the complete `UserPlaylistsProvider` contract by loading owned rows first, following at most ten favorite pages, advancing offsets by raw page length, rejecting empty continuing pages, and deduplicating by QQ playlist ID. Owned identities remain `owned:<tid>:<dirId>` and favorite identities become `favorite:<id>` inside provider-owned opaque values. Every network await rechecks the exact credential; only explicit rejection for the current credential signs out. The hard safety limit is TD-005.

The Bridge exposes the complete Provider operation through a single-use `QqMusicUserPlaylistLoadHandle`. `run`, exact `cancel`, and `isActive` are the only operations; cancellation drops the losing Provider/network future, including an in-progress favorite page, and concurrent runs fail explicitly. Generated Dart receives provider ID, opaque playlist ID, title, optional artwork/count, and a coarse failure enum. Credential, QQ dual IDs, pagination, and merging rules remain outside Flutter.

Flutter routes both newly authenticated and server-verified restored sessions into an adaptive “Your playlists” page containing the combined Provider result. Its controller owns loading/retry/empty/error presentation, cancels replaced operations, and suppresses late results after restart or disposal. Desktop uses a bounded artwork grid; narrow layouts use a touch-sized list. Structural or safety-limit failures show no partial list. Rows open local playlist-detail presentation without parsing source-specific opaque IDs.

The protocol client has separate bounded operations for ordinary playlist pages (`disstid`) and the built-in liked-songs directory (`dirid: 201` plus encrypted UIN). Both return QQ-specific track, artist, and album summaries with typed pagination and failures. `QQMusicProvider` alone parses playlist opaque identities, selects the request route, and maps the result into a provider-neutral `PlaylistTracksPage`. Track IDs remain provider-scoped opaque values containing the QQ fields needed by a future media operation; generic Domain and presentation code cannot interpret them. QQ-specific file/payment/action payloads are deliberately excluded; future media resolution must introduce only fields supported by its own evidence.

The page boundary is intentional: playlist detail does not hide an unbounded full-list loop. The Provider rejects a continuing empty page and rechecks the exact authenticated credential after the network await. The Bridge exposes one single-use `QqMusicPlaylistTrackPageLoadHandle` with exact cancel/run/isActive lifecycle. Its input carries provider/opaque playlist identity and pagination; its output carries provider-neutral display fields, opaque track identity, pagination, and coarse failures. It never parses QQ identity or exposes protocol models.

Flutter opens a selected playlist locally from the library surface and creates a short-lived paged controller. It requests pages of at most 100 rows, advances offsets by the raw response length, rejects mismatched or non-advancing pages, and deduplicates only exact provider/opaque track identities at page boundaries. Initial failure replaces the page; retryable append failure preserves existing rows and has a separate retry state. Restart/back/dispose cancels the current handle and suppresses late generations, while explicit rejection still follows shared serialized-vault cleanup. Desktop and narrow layouts render track display data, load-more progress, and a truthful terminal state without playback affordances.

## Playback and storage

The first playback protocol foundation now exists in `QQMusicClient`. One bounded unauthenticated CDN-dispatch operation validates HTTP(S) bases and cache/refresh TTLs; a second bounded authenticated `UrlGetVkey` operation requests only the cross-validated standard MP3 filename. It requires one matching item, a matching returned filename, a zero item result, and a relative path that cannot replace the dispatched authority. Source URI diagnostics are redacted and validity is the smaller CDN/vkey TTL. The client preserves unknown item codes only as protocol-level unavailable outcomes and does not infer payment, region, or copyright reasons.

`music-domain` now represents an immediate provider-neutral source as its opaque `TrackId`, secret-bearing URI, `Mp3`/`Standard` labels, and positive validity in seconds. The URI remains accessible only for playback handoff and is redacted from diagnostics. `provider-api` exposes one deliberately narrow standard-media operation and typed authentication, availability, network, service, structural, core, and account-replacement failures.

`QQMusicProvider` alone parses `track:<id>:<type>:<vkey-type-or->:<song-mid>`, with the optional vkey type falling back to zero. It runs dispatch before vkey, rechecks the exact authenticated credential after both awaits, and signs out only on explicit credential rejection for that candidate. It maps no QQ filename, vkey, CDN list, or raw result code into Domain. The Bridge lifecycle, playback engine, queue, and Flutter controller do not exist yet, so Flutter still has no playback affordance.

Credential semantics and serialization remain in Rust. `flutter_secure_storage` is a platform integration edge only; it stores one opaque versioned document and cannot declare a user authenticated. Android backup is disabled, Apple synchronization is disabled, and corrupt or unavailable storage must remain distinguishable from an upstream credential rejection. Linux passed a disposable runtime write/read/delete integration on 2026-08-25; other target runtimes remain tracked by TD-004.

## Forbidden dependencies

- Flutter presentation importing or reimplementing QQ Music protocol behavior.
- Rust core managing purely visual interaction state.
- Project domain types depending on provider response packages or Flutter types.
- A localhost Node, Python, or Rust API server as the normal application path.
- Provider-owned application UI.
