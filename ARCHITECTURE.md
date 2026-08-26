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

- `apps/flutter` contains adaptive Material 3 authentication, complete user-playlist collection, paged playlist-detail, foreground playback/queue, and synchronized-lyric surfaces; short-lived Dart controllers/gateway adapters; one shared serialized platform-vault boundary; a plugin-independent foreground-audio port/controller plus its selected plugin adapter; and Dart integration/widget tests.
- `crates/music-domain` contains provider-independent provider/playlist/track identities, playlist and track summaries, bounded playlist-track pages, a redacted short-lived resolved-media source, deterministic positional playback queue, and synchronized line/word lyric timing. Provider-owned identity values remain opaque outside their implementation.
- `crates/provider-api` contains the UI-free provider descriptor/capabilities plus provider-neutral QR authentication, owned/complete user-playlist, paged playlist-detail, standard-media-resolution, and synchronized-lyrics contracts.
- `crates/qqmusic-client` owns the raw QQ Music client boundary. It contains redacted credential/restore models, versioned secure-storage serialization, a Rustls-backed bounded HTTP implementation, cross-validated WeChat QR flows, credential verification, owned/favorite playlist fetching, ordinary/liked-songs detail-page fetching, media dispatch/vkey resolution, bounded cloud-QRC decryption/parsing, and cancellable lifecycle coordinators.
- `crates/provider-qqmusic` retains credential state; maps raw authentication, playlist, track, media, and lyric protocol values into provider/domain contracts; aggregates bounded owned/favorite pages; routes ordinary versus built-in liked detail pages; and truthfully advertises `Authentication`, `UserLibrary`, `MediaResolution`, and `Lyrics`.
- `bridges/flutter` adapts core/provider status, authentication, credential persistence, complete user-playlist loading, one playlist-track page, one standard-media resolution, synchronized lyrics, and one Dart-owned positional playback queue into presentation-safe generated types. Secret-bearing credential and media handoffs stay narrow and short-lived rather than becoming presentation models.

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

The current bridge is generated by `flutter_rust_bridge` 2.13.0. Linux x64 builds its bridge crate directly with system Cargo because the generated Cargokit backend requires rustup. On Linux hosts without rustup, Android uses a second localized system-Cargo Gradle task for one explicitly requested ARM64 or x64 target: the matching distribution `rust-src` builds `std`, NDK API 24 supplies the linker, and the resulting library is merged into the plugin AAR before native-library packaging. ARM64 additionally links the NDK compiler-runtime archive and fails if an unresolved `__aarch64_*` symbol survives. The application maps Flutter's explicit target platform into Gradle ABI filters so transitive JNI libraries cannot advertise an incomplete ABI. ARM64 release artifact inspection plus translated AVD startup and native x64 emulator FFI have passed; physical ARM64, other hosts, and other ABI sets retain unvalidated paths. These exceptions are tracked as TD-001.

## Provider architecture

Providers expose data plus explicit capabilities such as authentication, catalog, user library, lyrics, and media resolution. A provider can implement only a subset. The first implementation is QQ Music; capability interfaces must remain small enough to reflect proven behavior.

Provider code never returns Flutter widgets or presentation-specific models.

The first user-library operation loads authenticated account-owned playlists via `QQMusicClient` `PlaylistBaseRead/GetPlaylistByUin`. QQ-specific, diagnostics-redacted protocol summaries preserve both playlist and directory identifiers. `QQMusicProvider` maps them into provider-independent `PlaylistSummary` values whose `PlaylistId` contains a stable provider ID and an opaque provider-owned value; generic domain and Flutter code cannot parse QQ identity rules. The narrow `OwnedPlaylistsProvider` remains available for the created-only collection.

`QQMusicClient` also implements one bounded page of `PlaylistFavRead/CgiGetPlaylistFavInfo`. It requires the credential's encrypted UIN, constrains page size to 100, and returns typed pagination plus protocol summaries without performing hidden loops. `QQMusicProvider` implements the complete `UserPlaylistsProvider` contract by loading owned rows first, following at most ten favorite pages, advancing offsets by raw page length, rejecting empty continuing pages, and deduplicating by QQ playlist ID. Owned identities remain `owned:<tid>:<dirId>` and favorite identities become `favorite:<id>` inside provider-owned opaque values. Every network await rechecks the exact credential; only explicit rejection for the current credential signs out. The hard safety limit is TD-005.

The Bridge exposes the complete Provider operation through a single-use `QqMusicUserPlaylistLoadHandle`. `run`, exact `cancel`, and `isActive` are the only operations; cancellation drops the losing Provider/network future, including an in-progress favorite page, and concurrent runs fail explicitly. Generated Dart receives provider ID, opaque playlist ID, title, optional artwork/count, and a coarse failure enum. Credential, QQ dual IDs, pagination, and merging rules remain outside Flutter.

Flutter routes both newly authenticated and server-verified restored sessions into an adaptive “Your playlists” page containing the combined Provider result. Its controller owns loading/retry/empty/error presentation, cancels replaced operations, and suppresses late results after restart or disposal. Desktop uses a bounded artwork grid; narrow layouts use a touch-sized list. Structural or safety-limit failures show no partial list. Rows open local playlist-detail presentation without parsing source-specific opaque IDs.

The protocol client has separate bounded operations for ordinary playlist pages (`disstid`) and the built-in liked-songs directory (`dirid: 201` plus encrypted UIN). Both return QQ-specific track, artist, and album summaries with typed pagination and failures. `QQMusicProvider` alone parses playlist opaque identities, selects the request route, and maps the result into a provider-neutral `PlaylistTracksPage`. Track IDs remain provider-scoped opaque values containing the QQ fields needed by media and lyrics; generic Domain and presentation code cannot interpret them. The minimum file boundary retains only the optional `file.media_mid` now proven necessary for vkey filenames. File-quality sizes, payment/action payloads, and other raw fields remain excluded.

The page boundary is intentional: playlist detail does not hide an unbounded full-list loop. The Provider rejects a continuing empty page and rechecks the exact authenticated credential after the network await. The Bridge exposes one single-use `QqMusicPlaylistTrackPageLoadHandle` with exact cancel/run/isActive lifecycle. Its input carries provider/opaque playlist identity and pagination; its output carries provider-neutral display fields, opaque track identity, pagination, and coarse failures. It never parses QQ identity or exposes protocol models.

Flutter opens a selected playlist locally from the library surface and creates a short-lived paged controller. It requests pages of at most 100 rows, advances offsets by the raw response length, rejects mismatched or non-advancing pages, and deduplicates only exact provider/opaque track identities at page boundaries. Initial failure replaces the page; retryable append failure preserves existing rows and has a separate retry state. Restart/back/dispose cancels the current handle and suppresses late generations, while explicit rejection still follows shared serialized-vault cleanup. Desktop and narrow layouts render track display data, load-more progress, and a truthful terminal state. Track rows are Material keyboard/touch actions that pass the existing opaque track model unchanged into the playback coordinator.

The lyric protocol client now has one bounded `PlayLyricInfo/GetPlayLyricInfo` operation using the verified `songMid`, requested song type, QRC, translation, romanization, and encrypted representation flags. It validates global/named codes and representation flags, caps the HTTP body at 2 MiB, ciphertext at 1 MiB per track, decompressed text at 2 MiB, lines at 10,000, and timed segments at 100,000. Cloud QRC decryption uses the QQ-compatible DES D-E-D behavior adapted with its MIT notice plus bounded zlib/UTF-8 decoding. A real XML reader extracts and entity-decodes `LyricContent`; hand-written bounded scanners parse QRC absolute-millisecond line/segment pairs and auxiliary LRC timestamps. Live raw, encrypted, and plaintext bodies never enter diagnostics or retained fixtures; offline tests use independently generated, project-authored non-lyrical ciphertext.

The first lyrics Domain boundary represents one opaque `TrackId`, at least one synchronized original line, and optional timed segments within each line. Line and segment timing is unsigned milliseconds with checked start-plus-duration; source order, gaps, overlaps, zero durations, spacing segments, and segments outside the nominal line interval remain representable because current QRC evidence does not justify normalization. Optional translation and romanization attach to original lines only after Provider mapping establishes an exact start-time match. `LyricsProvider` returns this provider-neutral model or coarse authentication, availability, transport, service, structural, or replacement failures. QQ encryption, XML/QRC parsing, raw response metadata, playback position, and presentation state remain outside Domain and the Provider contract.

`QQMusicProvider` shares structural validation of `track:<id>:<primary-type>:<song-mid>:<file-media-mid-or->` across media and lyrics without exposing that identity grammar. Lyrics use the primary song type and song MID. Media uses the song MID plus optional file-media MID, while the vkey request's `songtype` is the evidence-backed constant zero rather than the unrelated playlist `songtype` field. The Provider preserves every original line and segment, attaches translation or romanization only when exactly one auxiliary row has the same start millisecond, and leaves unmatched or ambiguous rows absent instead of inventing fuzzy alignment. It rechecks the exact credential after the lyric await and clears it only for an explicit credential-rejection code.

The Bridge exposes synchronized lyrics through one single-use `QqMusicLyricLoadHandle`. Its input is the unchanged provider/opaque track identity; its output contains only provider-neutral line text, absolute millisecond line and segment timing, optional translation/romanization, or a coarse typed failure. `run`, exact `cancel`, and `isActive` own the lifecycle, and cancellation drops the losing Provider/network future. The handle and Rust result diagnostics expose only counts, timing, flags, and coarse state—not opaque identity or lyric text. Playback position and active-word selection remain Dart presentation concerns and are not part of this Bridge operation.

The Dart lyric gateway defensively validates nonempty documents, checked 32-bit millisecond timing, unambiguous success/failure shape, and nonempty optional auxiliary text before freezing the accepted lines and segments. Explicit credential rejection alone uses the same serialized vault cleanup boundary as library and playback; availability and transient failures retain the credential. A short-lived lyric controller owns loading/retry/account/error presentation state and exact operation cancellation across track replacement, clear/sign-out, and disposal. It suppresses every late generation and derives active presentation from real playback milliseconds: line and segment intervals are left-closed/right-open, gaps select nothing, overlaps select the later start, and equal starts select the later source-order entry. Segment progress is computed only inside the selected line and segment. Application composition passes the same underlying vault to authentication, library, detail, media, and lyric gateways. Since the lyric surface is not yet present to offer an account action, explicit lyric rejection or rejection-cleanup failure leaves the authenticated page through its existing sign-in reset callback; unavailable and transient failures do not.

`QueuePlaybackController` remains the single coordinator for Rust queue selection and foreground playback. It can own one lyric controller, starts lyrics only when the provider/opaque current Track identity changes, forwards current-session position updates, and clears/disposes lyrics with queue ownership. Duplicate queue positions carrying the same Track identity reuse the same lyric document; no parallel queue, timer, or playback state machine is introduced.

The now-playing surface opens this same controller in an adaptive lyric panel: widths below 600 use a tall modal bottom sheet and wider windows use a bounded dialog. The panel truthfully distinguishes idle, loading, unavailable, retryable/terminal error, account, and content states. It always preserves the Provider-mapped canonical line; timed segments replace the displayed original only when their exact concatenation is lossless, otherwise they appear as a separate timing row. The selected line and each segment's gradient progress derive only from controller position. Translation and romanization remain optional presentation text. The panel does not parse QRC, fetch data, estimate time, own playback, or duplicate account decisions.

## Playback and storage

The first playback protocol foundation now exists in `QQMusicClient`. One bounded unauthenticated CDN-dispatch operation validates HTTP(S) bases and cache/refresh TTLs; a second bounded authenticated `UrlGetVkey` operation requests only the cross-validated standard MP3 filename. With `file.media_mid`, the filename is `M500 + file-media-mid + .mp3`; without it, the independently agreed fallback is `M500 + song-mid + song-mid + .mp3`. The request always sends `songtype: [0]`. It requires one matching item, a matching returned filename, a zero item result, and a relative path that cannot replace the dispatched authority. Source URI diagnostics are redacted and validity is the smaller CDN/vkey TTL. The client preserves unknown item codes only as protocol-level unavailable outcomes and does not infer payment, region, or copyright reasons.

`music-domain` now represents an immediate provider-neutral source as its opaque `TrackId`, secret-bearing URI, `Mp3`/`Standard` labels, and positive validity in seconds. The URI remains accessible only for playback handoff and is redacted from diagnostics. `provider-api` exposes one deliberately narrow standard-media operation and typed authentication, availability, network, service, structural, core, and account-replacement failures.

`QQMusicProvider` alone parses `track:<id>:<primary-type>:<song-mid>:<file-media-mid-or->`. It runs dispatch before vkey, rechecks the exact authenticated credential after both awaits, and signs out only on explicit credential rejection for that candidate. It maps no QQ filename, vkey, CDN list, or raw result code into Domain.

The Bridge exposes this operation through one single-use `QqMusicMediaResolutionHandle`. Its input carries provider and opaque track identity; its success output contains only URI, format, quality, and validity, while its failure output is coarse and typed. The handle owns exact cancel/run/isActive lifecycle, drops the losing Provider/network future, and redacts both opaque identity and source URI from Rust diagnostics. The generated Dart DTO deliberately has no generated string representation.

The Flutter playback edge pins `audioplayers` 6.8.1 behind a project-owned `ForegroundAudioEngine`/per-source session boundary. Every remote load creates a fresh plugin player, so replacing a source can detach and dispose the entire old event authority. The session exposes play, pause, bounded millisecond seek, stop, position, and disposal without exposing the plugin object. The adapter exposes only coarse load/playback/core failures, and disables the plugin's global logger before creating a player because its upstream exception string includes `player.source`. No source URI or upstream cause enters controller state or diagnostics.

`ForegroundPlaybackController` owns only short-lived single-track presentation lifecycle: loading, playing, paused, stopped, completed, or coarse error. Each session also maps the plugin's frame-driven position stream into nonnegative integer milliseconds. Seek is accepted only for the exact playing or paused session; concurrent attempts retain only the newest completion, position callbacks are ignored while it is pending, and replacement/dispose invalidates it. A new source and explicit stop reset position to zero; source replacement, stop, failure, and dispose detach the exact state, failure, and position subscriptions before terminal cleanup. Generation plus session identity suppress every late callback, and `TrackPlaybackController` forwards current-session position notifications without estimating time itself. It enables seek only when the selected Track has a positive duration and clamps the requested millisecond to that duration. Cleanup errors cannot revive or block a replacement. A packaged Linux integration proves local-file lifecycle plus loopback remote-MP3 state, positive-position events, and byte-range-backed seek through the project adapter.

`RustMediaResolutionGateway` adapts the generated media handle into a Dart-owned single-use operation. It forwards provider plus opaque track identity unchanged, validates that Bridge success contains exactly one HTTP(S) source with authority and positive validity, maps every coarse failure without collapsing unavailable into network/service failure, and uses a redacted `ResolvedPlaybackSource` string representation. Explicit credential rejection alone enters the same nested shared `SerializedCredentialVault` queue used by authentication/library cleanup.

`TrackPlaybackController` composes exactly one resolution operation with the foreground controller. It owns resolving/loading/playback/error presentation state and the selected track's existing display model, but never parses identity or retains the resolved URI. Replacement, stop, and dispose cancel the current resolution handle and advance a generation before delegating playback cleanup. A current success URI is handed directly to `ForegroundPlaybackController`; resolution failures remain separate from engine failures.

The authenticated `UserLibraryPage` owns one queue/playback/lyric coordinator so those lifecycles survive local library/detail navigation and are disposed together when the authenticated surface leaves. Application defaults construct authentication, library, detail, media, and lyric gateways over one shared serialized vault. Detail rows send their existing provider/opaque identities into queue replacement before media and lyric resolution. The compact adaptive now-playing surface renders playback and queue state and opens the synchronized lyric panel from the same owner. Account-state media failures provide an explicit sign-in reset, while an explicit lyric credential rejection uses the same reset automatically. This does not prove real authenticated QQ playback or lyric loading, cleartext-source policy, or another target runtime.

The reusable queue foundation is `music-domain::PlaybackQueue`. It owns ordered `TrackSummary` entries and exactly one current position whenever non-empty. Complete replacement validates before mutation; select/advance/rewind are bounded; completion advances once and leaves the terminal item selected at the end. Removal is position-specific, retains the same current track when an earlier entry shifts indices, and selects the successor or final predecessor when removing current. Duplicate `TrackId` values are deliberately retained because repeated queue entries can express user intent. The model has no Provider fetching, media URI, plugin state, presentation state, repeat, shuffle, persistence, or automatic pagination.

The Bridge exposes each queue as a Dart-owned Rust-opaque `PlaybackQueueHandle`, not a global service. Synchronous replace/push/select/advance/rewind/complete/remove/clear commands lock only this small in-process Domain object and return an immutable provider-neutral snapshot plus `currentChanged`; the latter distinguishes a positional current replacement from an unrelated removal. Track DTO conversion validates Domain identity/display invariants before mutation, and invalid track/position or poisoned-core failures are coarse and typed. Snapshots preserve duplicates and expose no media source. The generated boundary has passed a packaged Linux FFI mutation smoke.

`RustPlaybackQueueGateway` is the only Dart adapter for generated queue DTOs. It validates exactly one snapshot or typed failure, all track display/identity invariants, the non-empty/current relationship, and `hasPrevious`/`hasNext` consistency. It keeps list data immutable and redacts diagnostics. Native handle creation is lazy so signed-out presentation and FFI-free widget tests do not touch Rust before application initialization.

`QueuePlaybackController` retains the last valid snapshot when a Bridge command fails and delegates every list mutation back to Rust. It starts a new `TrackPlaybackController` operation only when `currentChanged` is true; current removal therefore plays the Domain-selected successor/predecessor, while unrelated removal does not restart audio. One completion notification calls Rust completion once, advances and plays the returned current item, or leaves the terminal completed item selected. The authenticated library page owns this queue/playback composition across local list/detail navigation and disposes both at sign-out. Activating a detail row explicitly replaces the queue with the detail controller's rows loaded at that moment and selects the exact row position. Later page loads do not mutate that playback queue until another row activation.

The adaptive now-playing surface consumes the queue controller and exposes bounded previous/next, single-track play/pause/retry/stop, account reset, lyrics, a queue affordance, and exact elapsed/duration progress when Track duration is known. Slider movement owns only a temporary visual preview and commits one bounded native seek when released; unknown duration renders no invented progress. Hardware media keys plus `Ctrl+Space`, `Ctrl+Left`, and `Ctrl+Right` call the same controller actions across local library/detail navigation. At widths below 520 the surface separates track information from transport controls; lyrics and queue open as mobile bottom sheets below 600 and constrained dialogs on wider layouts. Positional queue entries preserve duplicates, mark current, select on tap, and remove individually; clear is explicit. Every action calls the queue/controller boundary, so presentation never splices or reorders its own list. Shuffle, repeat, drag reorder, persistence, automatic Provider fetching, and background playback remain absent.

Credential semantics and serialization remain in Rust. `flutter_secure_storage` is a platform integration edge only; it stores one opaque versioned document and cannot declare a user authenticated. Android backup is disabled, Apple synchronization is disabled, and corrupt or unavailable storage must remain distinguishable from an upstream credential rejection. Linux passed a disposable runtime write/read/delete integration on 2026-08-25 and Android 16 x64 passed the same bounded test on 2026-08-26; other target runtimes remain tracked by TD-004.

## Forbidden dependencies

- Flutter presentation importing or reimplementing QQ Music protocol behavior.
- Rust core managing purely visual interaction state.
- Project domain types depending on provider response packages or Flutter types.
- A localhost Node, Python, or Rust API server as the normal application path.
- Provider-owned application UI.
