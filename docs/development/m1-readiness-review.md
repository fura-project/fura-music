# M1 Readiness Review — 2026-08-26

## Outcome

M1 is **not checkpoint-ready**.

The implementation now forms the intended in-process vertical slice from authentication through word-timed lyric presentation, and every unblocked offline/platform validation passes. Android ARM64 release provides the required mobile build evidence, while Android 16 x64 now provides bounded FFI, vault, and local-audio runtime evidence. The review does not promote those smokes or fixture/widget evidence into a real-user claim: this checkout has not completed an authorized real-account flow across the whole slice.

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

Android ARM64 release first built after an ASCII Flutter SDK alias exposed and the project narrowly addressed two blockers: `flutter_secure_storage` 11.0.0's upstream-recorded compile-SDK 37 incompatibility, and generated Cargokit's unconditional rustup assumption. After matching system `rust-src` 1.97.1-1 was installed, a clean repeat compiled `core`, `std`, and compiler builtins directly from `/usr/lib/rustlib/src/rust/library` without a temporary mount or alternate sysroot.

That clean artifact audit also found and reproduced two latent defects before accepting the repeat. Transitive `jni` libraries made the nominal ARM64 APK advertise incomplete x64/ARMv7 ABIs, so Android selected x64 and crashed while loading the AArch64 Flutter engine. Separately, the Rust library retained `__aarch64_cas4_acq_rel`, which failed dynamic loading after the ABI metadata was corrected. Gradle now filters every explicit Flutter target to its matching ABI; the ARM64 linker includes NDK compiler-rt and the build rejects any surviving `__aarch64_*` symbol.

The corrected 23.0 MB APK contains only the complete ARM64 Flutter/Dart/JNI/Rust library set. Its stripped Rust bridge targets Android 24 AArch64 with NDK r28c, has no unresolved compiler-runtime symbol, retains four 16 KB-aligned LOAD segments, and passes v2 signature verification plus `zipalign -P 16`. The certificate remains Android Debug under TD-002. Installed on the existing Android 16 AVD's ARM64 translation path, Android selected `arm64-v8a`, all native layers loaded, and the real signed-out surface rendered. A native x64 debug rebuild likewise contained only x64 libraries and rendered the entrypoint. Translation is runtime evidence for the packaged ARM64 code, not a physical-device claim.

The existing Android 16 x64 AVD then supplied real runtime evidence. After correcting a debug JNI merge-order bug exposed by an APK missing its Rust library, the installed test APK contained a stripped Android-24 x64 bridge with 16 KB-aligned LOAD segments. Packaged FFI passed 1/1, disposable non-account vault write/read/delete/absence passed 1/1, and local MP3 lifecycle passed 1/1. The Linux-only loopback HTTP audio test was skipped rather than enabling Android cleartext.

The actual application entrypoint also launched to the signed-out QQ Music surface at 1080 x 2400, initialized the Rust core, presented the expected sign-in action without visible clipping/overflow, and produced no Flutter/native fatal error. The first launch performed an empty legacy-algorithm migration after the secure-storage compatibility change; a force-stop and second launch did not repeat it. The smoke did not start QR authentication or touch credentials, account data, or remote media, and the test installation was removed. These results do not prove a physical device, QQ CDN playback, audio focus/interruption, or authenticated product flow.

## Roadmap acceptance matrix

| Acceptance criterion | Status | Current evidence | Evidence still required |
| --- | --- | --- | --- |
| Sign in, restart, and regain the appropriate credential state | Implemented; not demonstrated end to end | Cross-validated protocol, offline lifecycle/rejection tests, and live Linux vault round trip | Authorized QR success, persisted credential, process restart, and upstream restore acceptance with a real account |
| Browse playlists, open one, play a track, and manage the queue | Implemented; not demonstrated against a real account | Provider/Bridge fixtures, 103 Flutter tests, positional queue tests, and real Linux playback adapter integration | One authorized account path through real library/detail/media responses and playable QQ source |
| Synchronized lyrics and basic word-level experience | Partially live-proven; full chain unverified | Anonymous live QQ request/decrypt/QRC parse, offline Provider/Bridge mapping, real position stream, and narrow/wide lyric widgets | Authenticated current-track lyric load and playback-synchronized observation in the real account flow |
| Flutter and Rust stay in one process behind a thin typed boundary | Pass on Linux and Android x64; ARM64 package/load/start pass under AVD translation | Linux and Android packaged typed-FFI calls; native x64 and translated ARM64 signed-out startup; both APK paths contain the requested Rust bridge; source dependency review | Physical-device coverage remains a release-quality follow-up, not an M1 build blocker |
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

- **TD-001 — Open, current target triggers handled:** Linux x64 and Linux-host Android ARM64/x64 have narrow system-Cargo paths. The underlying generated Cargokit rustup assumption remains debt but does not block current M1 targets.
- **TD-002 — Open, not triggered for distribution:** Android release remains debug-signed and no produced artifact may be distributed.
- **TD-003 — Resolved:** restore requires upstream verification; real-account acceptance remains a validation gap, not a reason to weaken the rule.
- **TD-004 — In Progress globally; Android M1 instance resolved:** Linux and Android x64 vault runtimes pass. Apple and Windows remain unverified for their future distribution paths.
- **TD-005 — Open, trigger not observed:** the 1,000-favorite bound remains explicit; no evidence justifies changing it.

No new technical debt or Human Decision was created. The Android result confirms rather than resolves TD-002 and resolves the M1 mobile instance, not every platform instance, of TD-004.

## Exact remaining M1 work

1. With explicit account authorization, perform a secret-safe smoke from QR sign-in through persistence/restart verification, playlists, detail, media playback/queue, and synchronized word-timed lyrics. Do not retain raw responses, credentials, source URLs, identifiers, or lyric content.
2. Rerun the checkpoint baseline, accurately retain or close debt, write the M1 checkpoint, then read M2. Do not start M2 merely because the implementation exists.
