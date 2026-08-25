# M1 Readiness Review — 2026-08-26

## Outcome

M1 is **not checkpoint-ready**.

The implementation now forms the intended in-process vertical slice from authentication through word-timed lyric presentation, and every unblocked offline/Linux validation passes. An Android ARM64 release APK now provides the required mobile build evidence, but the review does not promote a build or fixture/widget evidence into a runtime or real-user claim. No mobile runtime is available for TD-004, and this checkout has not completed an authorized real-account flow across the whole slice.

This document is a readiness review, not the M1 checkpoint.

## Validation baseline

Passed on the current Linux host:

- `cargo fmt --all -- --check`;
- `cargo test --workspace --all-targets`: 149 offline tests passed (`19 + 2 + 29 + 75 + 24`), while four explicitly gated live tests remained ignored;
- `cargo clippy --workspace --all-targets -- -D warnings`;
- `dart analyze --fatal-infos`;
- `flutter test`: 103 tests;
- Linux release application build;
- packaged Linux typed-FFI integration: 1 test;
- packaged GStreamer local-file and loopback-HTTP MP3 integration: 2 tests, including a positive playback-position event;
- disposable non-account Linux secure-storage write/read/delete integration: 1 test with cleanup.

Android ARM64 release built after an ASCII Flutter SDK alias exposed and the project narrowly addressed two additional blockers: `flutter_secure_storage` 11.0.0's upstream-recorded compile-SDK 37 incompatibility, and generated Cargokit's unconditional rustup assumption. The 23.2 MB APK contains Flutter/Dart and the stripped Android-24 AArch64 Rust bridge; all Rust LOAD segments are 16 KB aligned, v2 signature verification and `zipalign -P 16` pass. The certificate remains Android Debug under TD-002. Because this session could not install packages system-wide, the exact signature-verified matching `rust-src` package was temporarily mounted at its normal sysroot path; an ordinary repeat on this host requires installing it. No Android device or running emulator was available, so no mobile FFI, storage, or audio runtime claim follows.

## Roadmap acceptance matrix

| Acceptance criterion | Status | Current evidence | Evidence still required |
| --- | --- | --- | --- |
| Sign in, restart, and regain the appropriate credential state | Implemented; not demonstrated end to end | Cross-validated protocol, offline lifecycle/rejection tests, and live Linux vault round trip | Authorized QR success, persisted credential, process restart, and upstream restore acceptance with a real account |
| Browse playlists, open one, play a track, and manage the queue | Implemented; not demonstrated against a real account | Provider/Bridge fixtures, 103 Flutter tests, positional queue tests, and real Linux playback adapter integration | One authorized account path through real library/detail/media responses and playable QQ source |
| Synchronized lyrics and basic word-level experience | Partially live-proven; full chain unverified | Anonymous live QQ request/decrypt/QRC parse, offline Provider/Bridge mapping, real position stream, and narrow/wide lyric widgets | Authenticated current-track lyric load and playback-synchronized observation in the real account flow |
| Flutter and Rust stay in one process behind a thin typed boundary | Build-pass on Linux and Android ARM64; runtime-pass on Linux | Linux release/debug and packaged typed-FFI calls; Android APK contains the AArch64 Rust bridge; source dependency review | Android runtime FFI smoke still required |
| QQ protocol/mapping has offline regression coverage and live tests stay separate | Pass | 149 offline Rust tests; four live tests explicitly gated and ignored by default | Future protocol changes must retain this separation |
| Linux desktop and at least one mobile target build | Pass | Linux release/integrations and inspected Android ARM64 release APK | Recheck both at checkpoint; runtime is a separate criterion |
| No runtime third-party QQ API server or unapproved Provider expansion | Pass | Source/dependency/scope scan; only QQ Music Provider is implemented | Recheck at checkpoint |

## Architecture self-review

- Flutter owns widgets, navigation, adaptive layout, controller state, current playback position presentation, active-line selection, and word-progress paint.
- Rust owns credential rules, QQ protocol, Domain identities/models, Provider mapping, media/lyrics resolution, queue mutation semantics, QRC processing, and bounded external operations.
- Bridge APIs remain coarse, typed, cancellable, and provider-neutral. No raw QQ response, identity grammar, credential field, vkey, source URI diagnostic, or QRC document is made into presentation state.
- `QQMusicProvider` remains UI-free. Handwritten Dart contains no musicu method name, QQ request field, QRC decrypt/parser, or opaque-ID parser.
- Queue mutation remains Rust Domain behavior; Dart only composes queue snapshots with foreground playback and lyric presentation.
- No localhost service, hosted third-party QQ API runtime, additional Provider, plugin runtime, download system, comment/MV/social expansion, or speculative framework was introduced.
- A static scan found no new untracked source TODO/FIXME and no tracked APK, target/build output, credential, cookie, token, QIMEI, or user-data artifact. The tracked `credential.rs` source filename is code, not credential material.

The only documentation drift found was the `ARCHITECTURE.md` current-module summary omitting the completed lyric Domain/Provider/Bridge/UI path; this review corrected it.

## Scope review

The implementation stays inside the M1 vertical slice. It adds no search, comments, MV, downloads, background playback, shuffle/repeat/reorder, queue persistence, extra Provider, or marketplace. The lyric UI is an adaptive view over the existing controller rather than a second playback owner or timer.

## Technical-debt review

- **TD-001 — Open, mobile-build trigger handled:** Linux x64 and Linux-host Android ARM64 have narrow system-Cargo paths. The underlying generated Cargokit rustup assumption remains debt, but it no longer blocks the required ARM64 build.
- **TD-002 — Open, not triggered for distribution:** Android release remains debug-signed and no produced artifact may be distributed.
- **TD-003 — Resolved:** restore requires upstream verification; real-account acceptance remains a validation gap, not a reason to weaken the rule.
- **TD-004 — In Progress:** Linux vault runtime passes. No mobile runtime exists on this host, so the M1 mobile instance is unresolved.
- **TD-005 — Open, trigger not observed:** the 1,000-favorite bound remains explicit; no evidence justifies changing it.

No new technical debt or Human Decision was created by the build task. The Android result confirms rather than resolves TD-002 and leaves TD-004 unchanged.

## Exact remaining M1 work

1. Install the matching distribution `rust-src` package when an ordinary local Android rebuild is needed; the signature-verified ephemeral proof must not be mistaken for a permanent host dependency installation.
2. Run the existing disposable non-account secure-storage test plus bounded audio and FFI smokes on an available Android runtime. An APK alone does not satisfy runtime evidence.
3. With explicit account authorization, perform a secret-safe smoke from QR sign-in through persistence/restart verification, playlists, detail, media playback/queue, and synchronized word-timed lyrics. Do not retain raw responses, credentials, source URLs, identifiers, or lyric content.
4. Rerun the checkpoint baseline, accurately retain or close debt, write the M1 checkpoint, then read M2. Do not start M2 merely because the implementation exists.
