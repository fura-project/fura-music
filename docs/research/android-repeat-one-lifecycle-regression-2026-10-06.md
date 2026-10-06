# Android retained-source replay lifecycle regression — 2026-10-06

Status: **DEVICE_REQUIRED**. This checkpoint does not accept physical Android
playback stability, background/lock, network transition, Bluetooth or mobile
memory. The previous physical-device failure is not superseded by Linux tests.

## Baseline and scope

- HEAD and local `origin/main`: `9098912210289d7bdb504f26d4a0c50dad0767f2`.
- Initial `git status --short --branch`: clean, `main...origin/main`.
- `git log -1`: `9098912 fix(playback): reuse completed sources and harden provider caches`.
- `adb devices -l` was executed twice: no devices listed. No physical API/ABI,
  installed APK, account, Track or OEM lifecycle evidence was collected.
- No emulator installed, no phone data cleared, no system configuration changed.
- Provider refresh, KuGou media, persistent byte caching, Library and UI changes
  are out of scope. No commit/push/reset/restore/clean performed.

## Read-only completion path audit

The actual path remains:

```text
music-domain PlaybackQueue.complete_current
  → PlaybackCompletionAction::ReplayCurrent
  → synchronous typed Bridge PlaybackQueueHandle.complete_current
  → RustPlaybackQueueGateway mapping
  → QueuePlaybackController._completeCurrent
  → TrackPlaybackController.replayCurrent
  → ForegroundPlaybackController.replayCurrent
  → retained ForegroundAudioSession.seekToMs(0)
  → retained session.play()
```

That branch returns before `playTrack`; it does not call `beginResolution`,
`loadRemote` or `Player.open`. Next/wrap still use the Rust-selected new Track.
There is no Dart repeat-mode decision, second Queue or `PlaylistMode.single`.

The pinned local media_kit 1.2.6 implementation under
`lib/src/player/native/player/real.dart` has these relevant semantics:

- `eof-reached` publishes playing=false then completed=true.
- `seek` submits the native absolute seek, then sets state.completed=false and
  emits completed=false. A successful explicit seek therefore prevents `play`
  from taking its completed-playlist `playlist-pos=0` compatibility branch.
- Fura's session suppresses duplicate completed=true and trailing playing=false
  while its last state is completed. `play()` re-arms the session's playing state.
- Position is not used to synthesize completion. Detached source events and late
  replay results are generation/identity checked by the foreground controller.
- Focus is retained at clean EOF; terminal Queue completion releases it. Errors,
  pause/stop/disposal release focus through the existing audio_session owner.

This is pinned source inspection plus tests, not a claim about every Android
plugin/native scheduler ordering. No state-machine or focus-policy rewrite was
justified or made.

## Targeted automated evidence

- Existing 100-completion Queue regression retained: one resolution, one load,
  100 zero seeks, 101 plays including initial play, zero stops before cleanup.
  Its first 100 play cycles are initial play + 99 replays.
- MediaKit fake 100 EOF replay: one open, zero source stop/disposal/rebuilds,
  100 seeks, 101 plays and one focus activation before terminal release.
- Duplicate EOF plus trailing paused events: exactly 100 completions across
  100 cycles, with playing restored after each seek/play.
- Replay seek/play failure: engineError, failed-session cleanup, no new
  resolution/open or silent `playTrack` fallback.
- Late replay seek/play after replacement: old session cannot overwrite or play
  the replacement Track; old focus is released. The Bridge completion itself is
  synchronous, not an asynchronous result that can be delayed over a network.
- Failed typed completion result: release retained focus, no replay or storm.
- Never-completing open, pause, replay seek and replay play: coarse bounded
  failure, operation tail not permanently poisoned, next explicit load can use
  one retirement-before-factory rebuild. Hung retirement starts no replacement;
  a second stalled generation cannot consume another rebuild.
- Diagnostic regression captures stdout and rejects synthetic native-error,
  host/path/query/credential-like marker leakage.

The deterministic stall tests inject 20 ms deadlines; production retains 15 s
open and 5 s control deadlines. Native retirement still has the SDK limitation
recorded in TD-016: delayed final handle destruction is not instantaneous
zero-handle-overlap proof.

## Linux supplemental evidence and fixture correction

The first real Linux run reached 100 EOF replays with zero extra fixture HTTP
requests, but diagnostics exposed focus release before EOF. A further run
recorded 101 coarse decode errors. Direct-session EOF tests had not asserted
the absence of native errors, so they could not prove an error-free controller
lifecycle even though their cache/position assertions passed.

Independently decoding the old embedded silent MP3 with local FFmpeg reported
`Header missing` and invalid packet data. FFmpeg's exit code was zero despite
those diagnostics; it is not cited as successful decoding. A fresh 0.5 s silent
8 kHz mono MP3 was generated using libmp3lame/16 kbps with no Xing header in pipe
output. It is test-only synthetic data. Independent decode with `-v error
-xerror` then completed with no diagnostics and exit 0. The real EOF integration
now counts only coarse native error categories and asserts that count is zero,
in addition to the existing cache/progress assertions. It never prints upstream
error text. No decoder error is filtered or ignored in production.

With the corrected fixture, the full Linux playback-engine integration passed
all six cases, including MP3/M4A/FLAC decoding, 100 source replacements, and
100 EOF replays with zero extra HTTP requests and an empty native-error count.
EOF trace showed focus=retained; release occurred during terminal cleanup.
The final EOF-only rerun passed with explicit 101 completion events (initial EOF
and 100 replay EOFs), one native open, 100 seeks, 101 plays, zero stalls/rebuilds,
zero extra HTTP requests and an empty native-error count. No Provider resolution
is involved in that direct synthetic-source test; the separate Queue regression
proves its one initial resolution. Neither count is physical Android evidence.

Linux Debug process samples (not Android or mpv-only heap):

| Replacements | RSS MiB | Threads |
| --- | ---: | ---: |
| 0 | 469 | 55 |
| 10 | 520 | 59 |
| 20 | 612 | 56 |
| 50 | 612 | 55 |
| 100 | 629 | 55 |

These short mixed-runtime samples cannot establish mobile memory acceptance or
long-term leak absence. No Android PSS/native-heap observation was possible.

Local checks:

- Baseline six targeted controller/engine/system-edge test files: 78 passed.
- Added regressions in the same targeted set: 87 passed.
- Final whole `flutter test test/playback` rerun: 248 passed after the final
  diagnostic/trace changes, exit 0.
- Final Queue/Track/MediaKit subset: 56 passed; final Queue diagnostic trace
  test file: 34 passed; no repeated resolve trace and no synthetic Track/URL
  leakage across 100 replay actions.
- `dart analyze`: no issues. Changed Dart files format-clean.
- Privacy-hygiene/application-identity checks and `git diff --check`: passed.
- FFmpeg strict decode of corrected fixture: exit 0, no diagnostics.
- No Rust or Bridge production file changed; no FRB regeneration, workspace
  Rust rerun, new Android build, GitHub Actions run or real-service test claimed.

Logs are local test evidence under `/tmp/fura-android-playback-targeted-final.log`,
`/tmp/fura-playback-suite-regression.log`,
`/tmp/fura-playback-suite-final.log`,
`/tmp/fura-linux-playback-fixture-final.log` and
`/tmp/fura-linux-eof-counter-final.log`, not committed artifacts.

## Diagnostics and physical next gate

New trace events contain locally constructed categories/counters only:
`playback_completed`, `queue_completion_action`, `replay_current` seek/play,
`media_operation` generation/cycle/phase/elapsed/outcome, `engine_stall`,
`engine_rebuild`, `audio_focus`, `native_player_failure`. No Track/title,
source URL, signed query, cookie/token or raw native error enters them.

These events use Flutter stdout so they can be collected without a VM-service
connection. Flutter documents that [debugPrint emits console output even in
release](https://api.flutter.dev/flutter/rendering/debugPrint.html), whereas
[dart:developer log](https://api.dart.dev/dart-developer/log.html) is a DevTools
log event. No per-position logger, telemetry service or diagnosis framework was
introduced. Android release logcat delivery itself remains device-unverified.
The existing media-resolution trace also emits to stdout; its source host/scheme
was removed so only safe Provider/category/format/quality/TTL remains. Resolution
counts come from `media_playback phase=resolve outcome=started`, and completed
native opens from `media_operation phase=open outcome=success`; CDN range
requests are not counted as Provider resolution.

Once an authorized physical phone is available, use the existing app identity
`com.fura.flutterustmusic`, retain app data, and collect only the coarse
`FURA_DIAGNOSTIC` trace. Record first-source resolution/open separately from
CDN byte-range requests. The requested matrix remains entirely unexecuted:

| Physical scenario | Result |
| --- | --- |
| Ordinary Track, Repeat One ≥30 full EOFs | DEVICE_REQUIRED |
| MP3/M4A, long Track, entitled High/Lossless | DEVICE_REQUIRED |
| Background across ≥2 EOFs, return to foreground | DEVICE_REQUIRED |
| Lock/unlock across EOF and system controls | DEVICE_REQUIRED |
| Safe audio-focus interruption and resume | DEVICE_REQUIRED |
| Wi-Fi/cellular and brief offline/restore | DEVICE_REQUIRED |
| Fully cached short-source offline replay | DEVICE_REQUIRED |
| Android RSS/PSS/native heap and post-switch trend | DEVICE_REQUIRED |
| Bluetooth connect/disconnect/reconnect | HUMAN_REVIEW_REQUIRED |

The 64 MiB forward/64 MiB backward packet limits are unchanged. They are not a
total RSS guarantee and their mobile cost is not measured. No mobile/desktop
budget split was guessed without physical evidence.

## Resolution cache second review

QQ/NetEase hold one Provider-wide cache mutex across network awaits. Different
Tracks/qualities (including ready cache hits) can wait: **HEAD_OF_LINE_BLOCKING**.
This does not participate in retained-source EOF replay. Current `playTrack`
cancels the prior operation; the Bridge's `tokio::select!` drops its Provider
resolution future and releases the cache guard. Thus rapid switching is not
inherently forced to wait for the old HTTP timeout. No physical rapid-switch
latency was reproduced and no Provider code was changed. TD-017 records a future
short critical section/per-key single-flight remedy only if measured latency
or an authorized parallel-consumer requirement triggers the debt.
