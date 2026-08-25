# Current Milestone

M1 — First QQ Music Vertical Slice, phase 2: authentication.

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

# In Progress

- Import persisted credential bytes at startup and perform Rust-owned restore planning without mapping corruption or transport failures to authenticated/signed-out guesses.

# Next Candidates

1. Implement startup credential import and local restore planning for absent, malformed, unsupported, and locally expired documents (TD-003).
2. Implement server verification for eligible restored credentials without mapping transport failures to signed-out state.
3. Add and run a disposable Linux secure-vault read/write/delete integration that leaves no marker behind (TD-004).
4. Run a controlled real-account QR acceptance or capture a sanitized successful fixture before claiming live successful login compatibility.

# Blockers

None.

# Pending Human Decisions

None.

# Risks

- QQ Music endpoints and authentication behavior are external and unstable; protocol work needs evidence and sanitized fixtures.
- Credential handling can create account and privacy risk; temporary storage must be explicit debt and must not be mistaken for release readiness.
- A successful credential can be written to platform secure storage, but startup import and server verification are not implemented (TD-003).
- The plugin is linked and loaded on Linux, not runtime read/write/delete verified; Android, Apple, and Windows paths are still unbuilt here (TD-004).
- A successful credential exchange is cross-validated and fixture-tested but has not been exercised against a real authorized account in this checkout.
- A local credential timestamp cannot prove server validity; transport failures must not be mapped to signed-out or rejected state.
- A generated bridge can grow into a second business layer unless its public surface stays coarse and typed.
- Cargokit 2.13.0 assumes rustup; Linux currently uses a direct system-Cargo build tracked as TD-001, and non-Linux bridge builds remain unverified.
