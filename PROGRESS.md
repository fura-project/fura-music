# Current Milestone

M1 — First QQ Music Vertical Slice, phase 3: user library.

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

# In Progress

- Cross-validate ordinary playlist-detail and built-in liked-songs request shapes before making library rows interactive.

# Next Candidates

1. Cross-validate ordinary playlist-detail and built-in `dirId: 201` liked-songs requests across current implementations.
2. Add bounded detail/track protocol models and sanitized fixture regressions without leaking raw QQ responses into Domain.
3. Map playlist detail through Provider and a cancellable Bridge operation, then make rows interactive with truthful loading/error states.

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
- A local credential timestamp cannot prove server validity; transport failures must not be mapped to signed-out or rejected state.
- A generated bridge can grow into a second business layer unless its public surface stays coarse and typed.
- The Provider rejects a favorite collection that still has more data after 1,000 rows rather than looping without bound or silently truncating it (TD-005).
- Cargokit 2.13.0 assumes rustup; Linux currently uses a direct system-Cargo build tracked as TD-001, and non-Linux bridge builds remain unverified.
