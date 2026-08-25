# M1 Readiness Review — 2026-08-26

## Outcome

M1 is **not checkpoint-ready**.

The implementation now forms the intended in-process vertical slice from authentication through word-timed lyric presentation, and every unblocked offline/Linux validation passes. The review does not promote fixture/widget evidence into a real-user claim. One mobile target has not built, no mobile runtime is available for TD-004, and this checkout has not completed an authorized real-account flow across the whole slice.

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

Android did not build. Three ARM64 release attempts stopped before app or Rust compilation because Flutter 3.47.1's Gradle plugin loader reread the non-ASCII Flutter SDK path as Latin-1. A project-settings-only UTF-8 reader changed only the first read and was reverted. No APK was produced. No Android device or running emulator was available.

## Roadmap acceptance matrix

| Acceptance criterion | Status | Current evidence | Evidence still required |
| --- | --- | --- | --- |
| Sign in, restart, and regain the appropriate credential state | Implemented; not demonstrated end to end | Cross-validated protocol, offline lifecycle/rejection tests, and live Linux vault round trip | Authorized QR success, persisted credential, process restart, and upstream restore acceptance with a real account |
| Browse playlists, open one, play a track, and manage the queue | Implemented; not demonstrated against a real account | Provider/Bridge fixtures, 103 Flutter tests, positional queue tests, and real Linux playback adapter integration | One authorized account path through real library/detail/media responses and playable QQ source |
| Synchronized lyrics and basic word-level experience | Partially live-proven; full chain unverified | Anonymous live QQ request/decrypt/QRC parse, offline Provider/Bridge mapping, real position stream, and narrow/wide lyric widgets | Authenticated current-track lyric load and playback-synchronized observation in the real account flow |
| Flutter and Rust stay in one process behind a thin typed boundary | Pass on Linux | Release/debug builds plus packaged typed-FFI calls; source dependency review | Mobile build still required separately |
| QQ protocol/mapping has offline regression coverage and live tests stay separate | Pass | 149 offline Rust tests; four live tests explicitly gated and ignored by default | Future protocol changes must retain this separation |
| Linux desktop and at least one mobile target build | Blocked | Linux release and integrations pass | One actual mobile build; Android currently blocked by scheduled TD-001 |
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

- **TD-001 — Scheduled:** now blocks the required Android build. The next attempt must change the SDK-root strategy before invoking the same build again; only then should Android system-Rust/Cargokit behavior be assessed.
- **TD-002 — Open, not triggered for distribution:** Android release remains debug-signed and no produced artifact may be distributed.
- **TD-003 — Resolved:** restore requires upstream verification; real-account acceptance remains a validation gap, not a reason to weaken the rule.
- **TD-004 — In Progress:** Linux vault runtime passes. No mobile runtime exists on this host, so the M1 mobile instance is unresolved.
- **TD-005 — Open, trigger not observed:** the 1,000-favorite bound remains explicit; no evidence justifies changing it.

No new technical debt or Human Decision was created by the lyric slice.

## Exact remaining M1 work

1. Give Flutter a genuinely different ASCII SDK root and obtain a real Android build result; then address only the evidenced Cargokit/system-Rust issue, if it occurs.
2. Run the existing disposable non-account secure-storage test and a bounded audio smoke on an available Android runtime. An APK alone does not satisfy runtime evidence.
3. With explicit account authorization, perform a secret-safe smoke from QR sign-in through persistence/restart verification, playlists, detail, media playback/queue, and synchronized word-timed lyrics. Do not retain raw responses, credentials, source URLs, identifiers, or lyric content.
4. Rerun the checkpoint baseline, close or accurately retain triggered debt, write the M1 checkpoint, then read M2. Do not start M2 merely because the implementation exists.
