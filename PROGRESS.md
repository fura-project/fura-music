# Current Milestone

M1 — First QQ Music Vertical Slice, phase 4: playback.

# Completed Recently

- Bootstrapped the governance documents, cross-platform Flutter shell, Rust workspace, generated in-process typed bridge, QQ Music client seam, provider boundary, offline tests, and Linux release/integration path from the original license-only repository.
- Cross-validated and implemented the WeChat QR bootstrap, polling, OAuth-code exchange, bounded transport, one 180-second lifecycle, exact cancellation, stale-result suppression, and provider-neutral authentication contract. Live no-account probes proved QR waiting and invalid-code rejection only; successful real-account login remains unverified.
- Built an adaptive Material 3 login experience and Dart controller with truthful waiting, scanned, reconnecting, terminal, persistence, retry, cancellation, and narrow-layout states.
- Added Rust-owned versioned credential serialization and validation, one opaque Bridge handoff, `flutter_secure_storage` platform adapters, Android backup protection, Apple Keychain entitlements, and explicit storage-failure presentation.
- Implemented startup vault restore plus server verification using the cross-validated user-info RPC. Only explicit rejection clears the current credential and vault; transient failures retain a retryable candidate, and exact attempt IDs prevent stale promotion.
- Verified the Linux Secret Service adapter with a disposable randomized non-account write/read/delete integration and guaranteed cleanup. Other platform runtimes remain TD-004.
- Cross-validated and implemented authenticated account-owned playlists through `PlaylistBaseRead/GetPlaylistByUin`, including bounded parsing, typed failures, redacted diagnostics, and synthetic offline fixtures.
- Added provider-scoped opaque playlist identity, minimum playlist summaries, a narrow `OwnedPlaylistsProvider`, credential rechecks after awaits, and a single-use cancellable Rust-opaque Bridge load handle.
- Added an adaptive user-playlist screen with separate loading, content, empty, transient retry, credential rejection, storage-cleanup failure, account replacement, structural/safety-limit, and core failure states. Playlist rows remain non-interactive until details exist.
- Routed both fresh QR login and verified startup restore into the library, while a rejected library credential returns to sign-in and deletes only the serialized shared vault entry.
- Shared one serialized credential-vault queue across authentication and library gateways so an old rejection delete cannot overtake a new login write; a cross-wrapper concurrency regression locks this behavior.
- Revalidated the current slice with 44 Flutter tests, Rust workspace tests (4 + 2 + 16 + 58 + 10), strict Clippy, a Linux release build, the packaged in-process Bridge smoke, and the Linux Secret Service round-trip.
- Cross-validated `PlaylistFavRead/CgiGetPlaylistFavInfo` across two current musicu implementations, with a third legacy implementation corroborating favorite-playlist identity semantics.
- Added a bounded one-page favorite-playlist client operation with encrypted-UIN precondition, `1..=100` size validation, typed pagination, flexible evidence-backed field aliases, redacted diagnostics, and 4 synthetic fixture tests.
- Added a complete `UserPlaylistsProvider` contract and QQ implementation that loads owned rows plus at most ten favorite pages, advances by raw page length, rejects non-advancing continuation, deduplicates by QQ playlist ID, preserves source-specific opaque IDs, and checks account replacement after every await.
- Added Provider regressions for two-page aggregation, cross-source deduplication, missing encrypted UIN before transport, empty/overlong pagination, favorite-stage rejection versus transient failure, and account replacement during a favorite request.
- Renamed the public Bridge lifecycle from owned to user playlists, regenerated all FRB bindings with pinned 2.13.0, and confirmed no orphaned owned-load symbols remain.
- Switched the cancellable handle to the complete Provider operation and updated Dart gateways/controllers/presentation to `UserLibrary*`; “Your playlists” now accepts both owned and favorite opaque IDs without parsing them and never shows partial data after invalid pagination.
- Cross-validated ordinary playlist detail and built-in `dirId: 201` liked songs across current implementations, then confirmed the ordinary `CgiGetDiss` shape with a bounded no-account public probe on 2026-08-26.
- Added bounded `QQMusicClient` pages for ordinary and liked-songs routes, minimum QQ-specific track/artist/album summaries, three-level response-code handling, typed pagination/row failures, redacted diagnostics, and 5 synthetic fixture tests. The liked fixture locks the independently observed optional nested data code.
- Revalidated the Rust workspace after the detail protocol slice: strict Clippy and tests pass at 4 + 2 + 16 + 63 + 10; live account-dependent tests remain ignored by default.
- Added provider-scoped opaque `TrackId`, minimum provider-independent `TrackSummary`, and `PlaylistTracksPage` Domain models plus a paged `PlaylistDetailsProvider` contract. Playback rights and QQ raw fields remain outside Domain.
- Implemented QQ Provider detail routing for favorite playlists, ordinary owned playlists, and the special owned `dirId: 201` liked-songs path. Mapping preserves display metadata and future media identity behind a redacted provider opaque value, rejects foreign/malformed identities and non-advancing pages, rechecks account state after every await, and clears credentials only on explicit rejection.
- Added Provider regressions for all three routes, multi-artist/album/artwork mapping, unsafe artwork components, malformed identity, invalid page size, non-advancing pages, rejection versus transient failure, and late completion after account replacement. Strict Rust checks now pass at 6 + 2 + 20 + 63 + 10.
- Added a single-use cancellable playlist-track page Bridge handle. Inputs are provider/opaque playlist identity plus offset/size; outputs contain only provider-neutral track display fields, opaque track identity, page metadata, and coarse typed failures.
- Regenerated the FRB 2.13.0 Rust/Dart bindings, confirmed the generated API directory has no orphaned modules or old owned-load symbols, and added Bridge mapping/error/cancellation regressions. Rust now passes 6 + 2 + 20 + 63 + 13.
- Revalidated `dart analyze`, all 44 Flutter tests, a Linux release build, and the packaged Linux integration. The integration creates and cancels the new detail handle across FFI without touching QQ Music or account data.
- Added a Dart playlist-detail gateway with shared serialized-vault rejection cleanup and a first-page controller that cancels restart/dispose, suppresses late results, validates offset zero, and keeps only transient failures retryable.
- Made desktop grid and mobile list playlist rows keyboard/touch actionable, added local back navigation, and built an adaptive detail surface for track title/subtitle, multiple artists, album, artwork fallback, duration, empty/loading/error/auth states, and an explicit first-page truncation message.
- Added 6 gateway/controller regressions plus a narrow-screen navigation/widget regression. `dart analyze`, all 51 Flutter tests, and the Linux release build pass.
- Completed explicit playlist-detail pagination in Dart without hiding a full-list loop in Rust. The controller advances by raw page length, validates exact offsets and non-advancing pages, deduplicates only exact provider/opaque track identities, preserves loaded rows across retryable append failures, and keeps restart/back/dispose cancellation exact.
- Added visible load-more, retry-more, progress, and end-of-playlist states. A narrow-screen widget regression opens a playlist, requests offset 1, renders the appended track, and reaches the terminal state; controller regressions cover duplicate boundaries, invalid offsets, and retryable failures.
- Revalidated `dart analyze`, all 52 Flutter tests, Rust workspace tests (6 + 2 + 20 + 63 + 13), strict Clippy, `git diff --check`, the Linux release build, and the packaged in-process Bridge smoke. The phase-3 architecture and scope review found no Provider/UI leakage, sidecar, new dependency, untracked debt, or scope expansion; user-library implementation is complete with real-account evidence gaps retained under Risks.

# In Progress

- Implement the bounded `QQMusicClient` CDN-dispatch and standard MP3 `UrlGetVkey` operations selected by the media-resolution evidence note. Keep URLs/vkeys redacted and preserve raw item outcomes without inventing restriction reasons.

# Next Candidates

1. Add bounded client requests and synthetic fixtures for CDN dispatch plus standard MP3 vkey success, unauthenticated/unavailable item results, malformed paths, response limits, and redacted diagnostics.
2. Define the minimum provider-neutral media source/error model and route opaque QQ track identity only inside `QQMusicProvider`, with account-replacement and rejection regressions.
3. Expose one cancellable single-use Bridge resolution handle before selecting the Flutter playback engine and queue boundary.

# Blockers

None.

# Pending Human Decisions

None.

# Risks

- QQ Music endpoints and authentication behavior are external and unstable; protocol work needs evidence and sanitized fixtures.
- Credential handling can create account and privacy risk; real-account probes and user-derived fixtures require deliberate, secret-safe execution.
- Startup server verification is cross-validated and fixture-tested but has not accepted a real account credential in this checkout; the live-success evidence gap remains separate from TD-003's completed implementation.
- Linux runtime write/read/delete is verified with cleanup; Android, Apple, and Windows paths are still unbuilt and runtime-unverified here (TD-004).
- A successful credential exchange is cross-validated and fixture-tested but has not been exercised against a real authorized account in this checkout.
- The complete playlist collection requires `encryptUin`; credentials missing it fail before library transport instead of showing only created playlists. Real successful-login coverage has not yet proven this field on every login shape.
- Ordinary detail passed a current public no-account probe, but authenticated ordinary and liked-songs success remain cross-validated/fixture-tested rather than proven with this checkout's real account.
- Unavailable, region-filtered, or otherwise greyed QQ song rows do not yet have sanitized evidence; their long-term Domain/playback representation must not be guessed during the happy-path detail mapping.
- Current CDN dispatch returned only cleartext HTTP bases in a bounded no-account probe. Mobile playback must not globally enable cleartext traffic or silently rewrite QQ URLs before narrow platform evidence exists.
- A local credential timestamp cannot prove server validity; transport failures must not be mapped to signed-out or rejected state.
- A generated bridge can grow into a second business layer unless its public surface stays coarse and typed.
- The Provider rejects a favorite collection that still has more data after 1,000 rows rather than looping without bound or silently truncating it (TD-005).
- Cargokit 2.13.0 assumes rustup; Linux currently uses a direct system-Cargo build tracked as TD-001, and non-Linux bridge builds remain unverified.
