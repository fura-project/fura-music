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
- Added the first adaptive owned-playlist screen with separate loading, content, empty, transient retry, credential rejection, storage-cleanup failure, account replacement, and core failure states. Its heading truthfully says “Playlists you created”; it does not claim favorite playlists or playlist details.
- Routed both fresh QR login and verified startup restore into the library, while a rejected library credential returns to sign-in and deletes only the serialized shared vault entry.
- Shared one serialized credential-vault queue across authentication and library gateways so an old rejection delete cannot overtake a new login write; a cross-wrapper concurrency regression locks this behavior.
- Revalidated the logical slice with 44 Flutter tests, Rust workspace tests (4 + 2 + 11 + 54 + 10), strict Clippy, a Linux release build, the packaged in-process Bridge smoke, and the Linux Secret Service round-trip.
- Cross-validated `PlaylistFavRead/CgiGetPlaylistFavInfo` across two current musicu implementations, with a third legacy implementation corroborating favorite-playlist identity semantics.
- Added a bounded one-page favorite-playlist client operation with encrypted-UIN precondition, `1..=100` size validation, typed pagination, flexible evidence-backed field aliases, redacted diagnostics, and 4 synthetic fixture tests.
- Added a complete `UserPlaylistsProvider` contract and QQ implementation that loads owned rows plus at most ten favorite pages, advances by raw page length, rejects non-advancing continuation, deduplicates by QQ playlist ID, preserves source-specific opaque IDs, and checks account replacement after every await.
- Added Provider regressions for two-page aggregation, cross-source deduplication, missing encrypted UIN before transport, empty/overlong pagination, favorite-stage rejection versus transient failure, and account replacement during a favorite request.

# In Progress

- Switch the existing cancellable Bridge library handle from the created-only contract to the complete user-playlist contract, then update presentation copy and regressions.

# Next Candidates

1. Expose the combined collection through the existing cancellable Bridge lifecycle and preserve exact cancellation/error mapping.
2. Rename the Flutter collection from created-only copy to the complete playlist library without making rows interactive prematurely.
3. Implement the first playlist-detail protocol slice, including the special built-in liked-songs directory path, before making playlist rows interactive.

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
- A local credential timestamp cannot prove server validity; transport failures must not be mapped to signed-out or rejected state.
- A generated bridge can grow into a second business layer unless its public surface stays coarse and typed.
- The current UI intentionally shows created playlists only; its Bridge handle and presentation copy must switch to the now-complete Provider contract before it can claim the complete library.
- The Provider rejects a favorite collection that still has more data after 1,000 rows rather than looping without bound or silently truncating it (TD-005).
- Cargokit 2.13.0 assumes rustup; Linux currently uses a direct system-Cargo build tracked as TD-001, and non-Linux bridge builds remain unverified.
