# M2 Reliability and Daily-Use Quality Checkpoint — 2026-08-26

## Outcome

M2 is checkpoint-ready within its authorized reliability and daily-use scope. This closes the M2 workstream and activates bounded M3 discovery; it does not close the separate M1 real-account acceptance observation.

## Exit-criteria evidence

1. Authentication, library, detail, playback, queue, and lyric controllers expose bounded loading, empty, failure, retry, cancellation, replacement, and disposal behavior where applicable. Controller, gateway, Provider, client, and Bridge regressions cover those transitions.
2. Playback and queue behavior is covered for unavailable/resolution/engine failures, replacement, completion, seek and volume ordering, repeated activation, and stale asynchronous completion. The final M2 fix serializes rapid play/pause intent and proves queued intent cannot cross track replacement.
3. Library and detail tests prove intentional snapshot retention on transient refresh failure, privacy-clearing on credential rejection, page replacement, local back navigation, scroll restoration, and originating-row focus restoration.
4. Widget tests cover desktop shortcuts, focus traversal, modal shortcut ownership, compact bottom sheets, pointer/long-press Track actions, narrow now-playing layout, and desktop/compact detail return.
5. Widget and controller tests cover non-duplicated Track/queue semantics plus meaningful authentication, library, playback, queue, and lyric live-region changes.
6. The current checkpoint passes strict Dart analysis, all 156 Flutter tests, Rust formatting, all 152 offline Rust tests, and strict Clippy. Four live QQ/WeChat tests remain explicitly gated and ignored.
7. The current Linux release bundle builds. Existing Android ARM64/x64 artifact and signed-out runtime evidence remains recorded in `PROGRESS.md`; it is not physical-device, remote QQ media, audio-focus, Apple, or Windows evidence.
8. A bounded whole-workstream review found and fixed the repeated-activation race. No further known high-value M2 correctness or daily-use gap remains unaddressed or untracked. Future discoveries still become bounded tasks; the checkpoint is not a claim that the product has no defects.

## Architecture and scope review

- Flutter retains transport presentation and short-lived controller ordering; Rust retains QQ protocol, Provider mapping, queue semantics, and lyrics timing.
- The Bridge remains typed and thin. No sidecar, Provider expansion, navigation/state-management replacement, cache layer, background-playback system, or speculative abstraction was introduced.
- M1's corrected authenticated playback, queue, and synchronized-lyric observation remains pending and blocks only that end-to-end acceptance claim.
- HD-001 continues to block external release identity/signing only. Existing technical-debt triggers and platform evidence boundaries remain unchanged.

## Validation performed

- `dart analyze --fatal-infos`
- `flutter test`
- `flutter build linux --release`
- `cargo fmt --all -- --check`
- `cargo test --workspace --all-targets`
- `cargo clippy --workspace --all-targets -- -D warnings`

No real credential, QQ account endpoint, remote media source, or live-test gate was used for this checkpoint.
