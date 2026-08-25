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

# In Progress

- Define cancellable QR login-session orchestration so replacement or disposal cannot surface late results.

# Next Candidates

1. Define cancellation/timeout behavior so a superseded QR session cannot deliver a late success.
2. Exchange the confirmed callback for a credential only after the request and error mapping have independent evidence.
3. Expose an initial login session state through the provider and bridge without adding secret persistence.
4. Select and validate the minimum secure credential-storage boundary before implementing restore persistence.

# Blockers

None.

# Pending Human Decisions

None.

# Risks

- QQ Music endpoints and authentication behavior are external and unstable; protocol work needs evidence and sanitized fixtures.
- Credential handling can create account and privacy risk; temporary storage must be explicit debt and must not be mistaken for release readiness.
- A local credential timestamp cannot prove server validity; transport failures must not be mapped to signed-out or rejected state.
- A generated bridge can grow into a second business layer unless its public surface stays coarse and typed.
- Cargokit 2.13.0 assumes rustup; Linux currently uses a direct system-Cargo build tracked as TD-001, and non-Linux bridge builds remain unverified.
