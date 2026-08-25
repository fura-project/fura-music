# Current Milestone

M1 — First QQ Music Vertical Slice, phase 2: authentication.

# Completed Recently

- Confirmed the upstream repository contained only the MIT license at initial commit `f439866`.
- Established the minimum product, architecture, roadmap, decision, debt, and session-memory governance documents.
- Created Flutter targets for Android, iOS, Linux, macOS, and Windows, plus a Rust workspace with domain, provider API, QQ Music client, QQ Music provider, and bridge crates.
- Proved `Flutter -> typed bridge -> Rust -> QQMusicProvider -> typed Flutter state` with a passing Linux integration test and release build.
- Added 6 Rust unit tests, a Flutter widget test, strict Clippy, and offline static-analysis coverage.
- Cross-validated credential restore behavior across three active QQ Music implementations and pinned the evidence in `docs/research/qqmusic-authentication-evidence.md`.
- Added a redacted QQ Music credential model that distinguishes signed-out, server-verification-required, and locally expired restore paths with 10 focused tests.

# In Progress

- Select and model the first verified QQ Music authentication request without using a real account.

# Next Candidates

1. Compare the WeChat and QQ QR bootstrap requests and select the smallest channel with reproducible evidence.
2. Introduce the smallest asynchronous transport contract required by that one verified request.
3. Add sanitized response fixtures for QR creation and precise error mapping.
4. Expose an initial login session state through the provider and bridge without adding secret persistence.

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
