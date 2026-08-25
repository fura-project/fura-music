# Current Milestone

M1 — First QQ Music Vertical Slice, phase 3: user library.

# Completed Recently

- Confirmed the upstream repository contained only the MIT license at initial commit `f439866`.
- Established the minimum product, architecture, roadmap, decision, debt, and session-memory governance documents.
- Created Flutter targets for Android, iOS, Linux, macOS, and Windows, plus a Rust workspace with domain, provider API, QQ Music client, QQ Music provider, and bridge crates.
- Proved `Flutter -> typed bridge -> Rust -> QQMusicProvider -> typed Flutter state` with a passing Linux integration test and release build.
- Added Rust unit coverage, a Flutter widget test, strict Clippy, and offline static-analysis coverage.
- Cross-validated credential restore behavior across three active QQ Music implementations and pinned the evidence in `docs/research/qqmusic-authentication-evidence.md`.
- Added a redacted QQ Music credential model that distinguishes signed-out, server-verification-required, and locally expired restore paths with 10 focused tests.
- Cross-validated and implemented the unconfirmed WeChat QR bootstrap behind a small asynchronous HTTP contract.
- Verified the QR bootstrap against the live endpoint without scanning a code or accessing an account; the default suite remains fully offline and redacts transient session material.
- Rebuilt the Linux release bundle and reran the real Flutter/Rust integration test with the new Rustls transport dependency.
- Implemented one bounded WeChat QR long-poll with evidence-backed waiting, scanned, authorized, expired, and refused states; unknown values remain explicit protocol errors.
- Verified a fresh unscanned session returns the expected waiting state through the live endpoint without exchanging credentials.
- Added a generation-based QR login coordinator: replacement, explicit cancellation, session drop, and coordinator disposal abort in-flight create/poll futures and suppress stale results.
- Added deterministic concurrency regressions for late authorization, replacement during QR creation, disposal, terminal reuse, and failed-creation cleanup.
- Cross-validated and implemented the WeChat OAuth-code exchange using the lightweight named musicu RPC envelope, including typed global/subrequest errors and bounded POST transport.
- Retained and redacted refresh/session material, preferred `str_musicid` over placeholder numeric IDs, and kept the WeChat login type when upstream omits it.
- Integrated credential exchange into the same generation gate; a replacement aborts an in-flight exchange, while an explicit retry reuses the pending code without polling again.
- Verified the live endpoint rejects a non-account fake code as global `0` / login `1000`; no real login or successful credential response was exercised.
- Added one monotonic 180-second deadline across QR creation, polling, and credential exchange; deterministic virtual-time tests prove blocked requests are dropped at expiry.
- Bounded session transport instability to three caller-visible consecutive failures, finishing on the fourth and resetting the count after any reached protocol response.
- Added provider-neutral QR authentication contracts and mapped the QQ Music flow into the Provider layer; successful credentials remain Rust-owned and the provider now truthfully advertises only `Authentication`.
- Generated an opaque typed Bridge session exposing only challenge image data, coarse progress/failure states, `advance`, `cancel`, and active/authenticated booleans; stale cancellation authority cannot affect a replacement.
- Replaced the bootstrap placeholder with an adaptive Material 3 WeChat QR login surface: desktop uses a focused split layout, narrow screens use a scrollable single column, and authenticated copy explicitly disclaims restart restore.
- Added a Dart login controller that continuously advances waiting/scanned states, briefly backs off transport failures, pauses on protocol/upstream errors, and suppresses late start/poll results after restart or disposal.
- Added exact cancellation for QR creation before the opaque session exists; a reserved start-attempt ID prevents stale controllers from cancelling a replacement.
- Added controller and widget regressions for waiting/scanned/authenticated transitions, cancel, restart, disposal, late completion, and 390px narrow layout.
- Selected `flutter_secure_storage` 11 behind ADR 0003 after checking official platform requirements, BSD-3-Clause licensing, Rust `keyring` alternatives, and the current host's Secret Service support.
- Added Rust-owned versioned credential serialization and invariant revalidation; the Bridge exposes only short-lived opaque bytes and redacted diagnostics.
- Connected successful login to one platform-vault key, zeroed the mutable FFI buffer after writes, and kept storage failures distinct from authentication success in the UI.
- Configured Android backup protection plus iOS/macOS Keychain entitlements, and added 6 credential persistence/controller regressions without writing to the live user keyring.
- Linked the secure-storage plugin in a Linux release bundle and reran the real packaged Flutter/Rust integration smoke; runtime vault read/write/delete remains explicitly unverified as TD-004.
- Fixed terminal QR states failing to notify Flutter listeners and locked the lifecycle behavior with a regression.
- Added startup vault reads and an opaque Bridge import that always zeroes loaded mutable bytes after Rust consumes them.
- Replaced the Provider's authenticated-or-empty slot with explicit signed-out, pending-verification, locally-expired, and authenticated states; only the last satisfies `has_authenticated_credential` or can be exported.
- Classified absent, malformed, unsupported-version, invalid, locally expired, platform-unavailable, and core-unavailable restore outcomes without deleting stored data or guessing authentication.
- Added Provider, Bridge, gateway, controller, widget, and Linux integration regressions proving unverified/expired candidates remain Rust-owned and unauthenticated.
- Cross-validated the lightweight `music.UserInfo.userInfoServer/GetLoginUserInfo` credential check against four current QQ Music implementations pinned by commit.
- Added a bounded server-verification request with credential-safe diagnostics, strict response-shape parsing, and explicit rejection codes `1000`, `104400`, and `104401`; unrelated upstream codes remain service failures.
- Added exact restore-verification attempt IDs through Provider and Bridge so QR replacement, retry, cancellation, and disposal cannot promote a stale credential.
- Promoted a retained startup credential only after QQ Music returns zero global and subrequest codes; explicit rejection clears in-memory state while transport, HTTP, upstream, and response-shape failures retain the candidate.
- Started eligible startup verification automatically in Flutter, added retryable/non-retryable presentation states, and restricted platform-vault deletion to explicit server rejection.
- Added credential input hardening before stored bytes can enter an HTTP Cookie header, plus Provider, Bridge, gateway, controller, and widget regressions for success, rejection, retry, storage-cleanup failure, and late-result suppression.
- Serialized vault reads, rejection deletes, and new credential writes inside one Gateway instance so a slow old cleanup cannot delete a newly authenticated session.
- Added and ran a Linux Secret Service integration using a randomized non-account key; write/read/delete succeeded and `finally` cleanup confirmed the marker was absent without touching the production credential key or calling `deleteAll`.
- Cross-validated the authenticated `PlaylistBaseRead/GetPlaylistByUin` owned-playlist request across three active implementations pinned by commit.
- Added a bounded QQMusicClient operation with typed failure mapping, credential-safe diagnostics, and three offline fixture tests for exact request shape, optional summary fields, malformed rows, rejection, unrelated upstream failure, and missing arrays.
- Preserved `tid` and `dirId` separately because QQ Music's built-in `dirId: 201` liked-songs directory is not a generic playlist detail ID; favorited playlists remain a separate encrypted-UIN paginated RPC.
- Added provider-scoped opaque `PlaylistId` and minimum `PlaylistSummary` domain models with redacted diagnostics and honest optional artwork/track-count fields.
- Added a narrow `OwnedPlaylistsProvider` capability and mapped QQ-owned rows without leaking QQ response models; the provider now truthfully advertises `UserLibrary` alongside `Authentication`.
- Rechecked the exact authenticated credential after the library await so a late old-account response becomes `Replaced`; explicit rejection clears only the matching credential while transient/upstream failures retain it.

# In Progress

- Expose one coarse authenticated owned-library load through the typed Bridge without moving protocol or presentation rules into the Bridge.

# Next Candidates

1. Expose a coarse authenticated library load through the Bridge before building the first real library screen.
2. Build the first adaptive owned-playlist screen with loading, retry, rejection, and empty states.
3. Run a controlled real-account QR acceptance or capture a sanitized successful fixture before claiming live successful login compatibility.

# Blockers

None.

# Pending Human Decisions

None.

# Risks

- QQ Music endpoints and authentication behavior are external and unstable; protocol work needs evidence and sanitized fixtures.
- Credential handling can create account and privacy risk; temporary storage must be explicit debt and must not be mistaken for release readiness.
- Startup server verification is cross-validated and fixture-tested but has not accepted a real account credential in this checkout; the live-success evidence gap remains separate from TD-003's completed implementation.
- Linux runtime write/read/delete is verified with cleanup; Android, Apple, and Windows paths are still unbuilt and runtime-unverified here (TD-004).
- A successful credential exchange is cross-validated and fixture-tested but has not been exercised against a real authorized account in this checkout.
- A local credential timestamp cannot prove server validity; transport failures must not be mapped to signed-out or rejected state.
- A generated bridge can grow into a second business layer unless its public surface stays coarse and typed.
- `GetPlaylistByUin` covers owned playlists only; presenting it as the complete library would omit favorited playlists and is explicitly out of the first protocol task.
- Cargokit 2.13.0 assumes rustup; Linux currently uses a direct system-Cargo build tracked as TD-001, and non-Linux bridge builds remain unverified.
