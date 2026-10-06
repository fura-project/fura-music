# Android retained-source replay lifecycle regression — 2026-10-06

Initial checkpoint: **DEVICE_REQUIRED**, for physical-device acceptance only.
The historical checkpoint below is preserved. The resumed Waydroid machine
acceptance at the end of this document supersedes the earlier assumption that
all Android runtime work had to stop without a physical phone. Neither Linux
nor Waydroid evidence accepts the original physical-device failure.

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

## Resumed Waydroid machine acceptance — 2026-10-06

Starting HEAD, local `origin/main` and a fresh read-only remote query were all
`fa73c90e2a40fad08f526cbdd86d7853d8ad35f4`; the initial worktree was clean.
The candidate is `9098912 + fa73c90`, followed by the uncommitted changes
described here. No physical ADB device was present.

The existing Waydroid 1.6.3 installation was started normally, without init,
image download, reset, data removal or host configuration changes. Human
authorized its previously unauthorized ADB connection. Its runtime is Android
13/API 33, native `x86_64` (supported `x86_64,x86`), with Mesa/minigbm graphics.
The APK identity remains `com.fura.flutterustmusic`; installation uses `-r`,
not uninstall or `pm clear`. No account login or Provider playback was used.

### Real default-D startup defect found during testing

The original ordinary no-define D Debug APK reached a visible Home window, but
the integration entrypoint ran twice and media_kit's NativeReferenceHolder
reported an invalid empty pointer string. The pinned audio_service 0.18.19
source explains the extra engine: `onAttachedToActivity` unconditionally calls
`getFlutterEngine`, which constructs a cached FlutterEngine and executes the
default Dart entrypoint if absent. Disabling its manifest service/receiver does
not prevent plugin registration or this attachment behavior.

Removing an already-attached AudioServicePlugin in `configureFlutterEngine`
was tested and rejected: attachment had already happened, and a late browser
callback produced a native NullPointerException. That removal is not retained.
The final correction gates **registration before attachment** with the existing
`BuildConfig.USE_AUDIO_SERVICE_SYSTEM_EDGE`. A build-owned generated registrant
copy preserves all other Flutter-generated registrations; the original input
is unchanged. [AGP's public generated-source API](https://developer.android.com/reference/tools/gradle-api/9.1/com/android/build/api/variant/SourceDirectories)
owns the task output. The transform fails closed unless it finds exactly one
known audio_service registration. A/B and invalid-define rollback still enable
it; C/D do not instantiate it. Both dependencies and rollback declarations are
retained. MainActivity adds only coarse registration and pause/resume markers.

The corrected D APK's compiled registrant no longer constructs
AudioServicePlugin. The real integration entrypoint runs once and the marker
reports `audioService=false`. This proves a local ownership defect and its
correction, **not the root cause of the original phone's occasional freeze**.

### Harness and evidence boundaries

`integration_test/android_replay_lifecycle_test.dart` uses the real Rust Queue,
typed Bridge, Queue/Track/Foreground controllers, media_kit native Player,
audio_session focus owner and flutter_media_session system edge. Only media
resolution/lyrics are synthetic. One app-owned loopback HTTP fixture replaces
account and Provider traffic; it is test-only and is not a shipping proxy.
Native forwarding counters count actual operations, not simulated completions.
Rust's Queue selects repeat-one and the finite terminal transition.

The fixture repeats complete silent MPEG frames under one ID3 header, not a
native playlist/loop or manufactured EOF. Independent FFmpeg `-v error -xerror`
decode passes. The short source is about 2.6 seconds; this is not a long-song,
High/Lossless or physical audio-hardware acceptance test. The integration
binding uses `fullyLive` so host-driven Activity resume renders frames during
the real-time soak; the default fade-pointer test policy initially prevented
resume completion. No production Flutter state machine was changed for that.

The normal gate asserts 101 real EOFs/100 retained-source replays, one initial
resolution/open, no repeated HTTP fetch, no native errors and no rebuild. The
observer drives actual Android Home/Activity transitions, waits for two EOFs
while backgrounded, performs 20 pause/resume cycles plus one confirmation, and
samples only this application's memory, focus and MediaSession. A separate
test injects a never-completing control Future at the native-player forwarding
seam; it proves timeout/queue release/one explicit recovery on Android, not a
reproduction of a C++ driver deadlock.

Cached-network testing closes only the fixture server for 20 EOF replays, then
restores it. Incomplete-source testing withholds only the fixture response for
three seconds, restores it and consumes a later portion. An initial 2 KiB
prefix test timed out before initial position advance: it withheld data before
the intended playback outage. The revised fixture provides enough MPEG data
for startup while keeping the source incomplete; it does not weaken native
error/position/open assertions or change mpv's production cache settings.

### Local build reproducibility

The host's Unicode SDK path caused an unrelated Gradle property decoding
failure; a command-local launcher uses the existing ASCII SDK symlink. The
normal Gradle engine download was also extremely slow. Exact Debug/Release
engine jars were fetched directly from official Flutter HTTPS storage, checked
against the GCS MD5, tested as ZIPs, and their `libflutter.so` SHA256 compared
with the installed **same** 3.47.1 SDK. A command-local Gradle init script makes
those artifacts available through a temporary Maven directory. It is not a
mirror policy, SDK/toolchain upgrade or repository/global configuration change.
Subsequent builds use the normal Gradle cache and existing privacy Rust flags.
No default-D FURA defines are injected. Current repaired APKs therefore contain
`fa73c90` plus this uncommitted Android registration correction, not pure HEAD.

Detailed logs, hashes and screenshots remain outside the repository under
`/tmp/fura-waydroid-replay-20261006-lxU1AA`. Only FURA_DIAGNOSTIC categories are
retained from logcat; no media URI, credential or account data is collected.
Screenshots show the synthetic test window. Waydroid/Mesa text-rendering noise
is not treated as Human-approved UI or physical-driver evidence.

### Completed Android playback machine results

Both the final Debug and Release integration suites passed all three cases on
the real Waydroid Android runtime. Each repeat gate observed **101 actual EOFs
and 100 replays**, rather than manufacturing completion or looping natively.

| Metric, before terminal cleanup | Debug | Release |
| --- | ---: | ---: |
| Resolution gateway calls (synthetic result, no Provider request) | 1 | 1 |
| Actual native Player opens | 1 | 1 |
| Retained-source zero seeks | 100 | 100 |
| Plays, including initial play | 101 | 101 |
| Source stops | 0 | 0 |
| Unexpected Player rebuilds | 0 | 0 |
| Native error events | 0 | 0 |
| Additional fixture HTTP requests | 0 | 0 |
| Flutter pause/resume callbacks | 22/22 | 22/24 |
| EOF replays while genuinely backgrounded | 2 | 2 |

Debug's final observer waits for each Android/Flutter lifecycle acknowledgement,
not an arbitrary rapid shell loop. Release completed twenty actual Activity
cycles plus confirmations; three additional slower cycles were used because
some Dart callbacks coalesced during rapid switching. No replay/focus policy
was changed to meet these counts. Native snapshots show one Fura MediaSession
and one active focus owner while playing. Both suites leave zero MediaSessions
and zero Fura active focus entries after controller/host/engine disposal.

The fixture-offline interval covers twenty real EOF replays (30 through 50)
without additional resolution/open/HTTP. The incomplete-source case sends only
the first 64 KiB, withholds the rest for three seconds, then restores it. Native
position advances, the response finishes, and a seek/play beyond sixty seconds
consumes the restored portion. Both builds retain open=1/play=1/nativeErrors=0
for that case; it is not evidence about cellular radio or provider/CDN recovery.

The injected never-completing seek times out at about one second, releases
focus, refuses more controls on the stalled session, then recovers through one
explicit new load. Real native position advances after that bounded rebuild.
Open/pause/seek/play never-Future, failed/hung retirement and no-second-rebuild
boundaries are additionally covered by the unchanged deterministic unit suite.

Android memory samples below are KiB, not physical-phone acceptance. Native
heap uses the coarse App Summary private-memory figure. Release experienced
host swapping, so its resident-memory decrease is not a leak-free proof.

| Build / replays | Total PSS | Total RSS | Native heap summary |
| --- | ---: | ---: | ---: |
| Debug / start | 411222 | 474968 | 35416 |
| Debug / 10 | 365820 | 433668 | 33300 |
| Debug / 30 | 376012 | 446236 | 36116 |
| Debug / 100 | 377930 | 448640 | 37736 |
| Release / start | 132991 | 243464 | 30736 |
| Release / 10 | 52684 | 107168 | 27144 |
| Release / 30 | 57285 | 84408 | 21800 |
| Release / 100 | 72516 | 91484 | 17348 |

The short synthetic source shows no obvious unbounded replay-only trend in
these samples. It cannot accept long/High/Lossless mobile memory or the existing
64 MiB forward/backward packet budgets. Those values remain unchanged.

### Negative runs retained, not relabelled PASS

- An initial Release run stopped with Waydroid's **whole container FROZEN**;
  after wakeup Android could not find the activity service. Normal session
  stop/start and full-UI launch restored the existing runtime. No init/image/
  data reset or host policy change was made. The interrupted run is not PASS.
- One Debug run **did hit a real play timeout** during parallel APK compilation:
  replay cycle 21, native cycle 45, `play` elapsed 5494 ms. Focus release then
  took about forty seconds. The test correctly failed. It is not dismissed as
  a decoder error or described as no stalls across every trial.
- At that time the host's 15 GiB swap was nearly exhausted. This task's idle
  temporary/normal Gradle daemons and Kotlin worker accounted for roughly
  4.5 GiB resident memory plus 4.9 GiB swap. Only those verified task-created
  idle JVMs were stopped; no user's unrelated process/cache or global JVM
  configuration was altered. Available memory rose from about 2.5 to 6.9 GiB.
- The **identical Debug APK** then passed the complete three-case gate without
  concurrent builds. This establishes a clean-baseline PASS, not causation:
  the contention timeout's exact native/scheduler cause and its relevance to
  the original phone remain unconfirmed. No timeout was enlarged, native error
  ignored, automatic EOF reopen/retry added, or focus state machine rewritten.

The source-lifetime replay model and cache were not changed in this task.
Machine baseline is PASS; the contention trial is a separate failed observation
and remains a stability risk for physical follow-up.

### Ordinary APK diagnostics and restart boundary

The original ordinary APK exposed native markers but not Dart startup/stack
messages in logcat: the latter used only `dart:developer.log`. Existing emitters
now use stdout-capable `debugPrint` with the same secret-free fields; main's
post-initialization stack includes actual system-controls availability. A
one-shot post-frame marker confirms framework first-frame completion without
a guessed startup sleep. Native resumed/window checks complement that marker.
There is no new diagnostics service or runtime framework.

Explicit rollback A Debug has been rebuilt and run: audioService registration
is true, requested/effective A is printed, system edge init succeeds and the
first frame appears. Ordinary no-define D Debug **and Release** each passed
three cold restarts: registration=false, requested/effective D, available
system controls and one Dart entrypoint. Release logcat actually contains
startup/selection/runtime-stack and first-frame messages without a VM-service
connection. These are startup/ownership checks, not A account/media playback
acceptance. The final installed package is ordinary D Release, not the fixture
entrypoint. The existing app data and Waydroid installation are preserved.

### Artifact provenance and checks

All artifacts below use native x86_64 and the same starting HEAD plus the
uncommitted changes described above. Harness APKs use the integration entrypoint;
ordinary APKs use `lib/main.dart`. No-define D is not implemented with a hidden
FURA define. These x64 APKs are **not ARM64 physical-phone test packages**.

| Artifact in the external evidence directory | SHA256 |
| --- | --- |
| flutterustmusic-replay-D-x64-debug.apk | ed59fd624e3fa5a9e95ecb4d182b940b7cc08b493382e9b6094b5b756c2f81a5 |
| flutterustmusic-replay-D-x64-release.apk | d3258fe5a062281bc4df40e0725434e65db04c8f8cb6ca1617b904bf7c7700e0 |
| flutterustmusic-ordinary-A-final-x64-debug.apk | cf28c3ab3c63f3bec8bbaca28328c3e891f26e84e5404db9e1f0dc788dc98074 |
| flutterustmusic-ordinary-D-final-x64-debug.apk | f15621fb095ecf925fa2f8812be2b39d631f3423a757c87a1918746c1e86d1eb |
| flutterustmusic-ordinary-D-final-x64-release.apk | 59bc5ba486d605d1cbef2064047a75a3c0755c12939bc0d739953dbf677f99e1 |

The native payload includes the Rust bridge, libmpv and media_kit Android helper;
the package identity/ABI and merged receiver/service states were checked. D's
compiled registrant has no AudioServicePlugin construction; A retains it.
The fixture entrypoint and ordinary startup checks each run exactly once.
Final ordinary builds also limit only their command-local Gradle JVM heap,
without editing project/global settings; no replay gate runs concurrently with
them. Generated Gradle problem reports were moved to the external evidence
directory rather than staged or discarded.

Offline checks include all 248 existing playback tests, three startup diagnostic
tests including the actual stdout sink, the targeted native/Queue tests, strict
fixture decode, Dart analysis/format, identity/privacy checks and diff whitespace.
No Rust/Bridge/Provider production change, FRB regeneration, real-account media
test, GitHub Actions run, commit, push, reset, restore or clean is claimed.

### Final acceptance split

| Gate | Result |
| --- | --- |
| Waydroid Android runtime baseline | PASS — Debug and Release suites, ordinary startup/restart |
| Host-contention Debug trial | FAIL — play timeout and delayed focus release; exact cause unconfirmed |
| Physical Android lifecycle gate | PENDING_HUMAN |
| Bluetooth / OEM / physical lockscreen / phone focus | PENDING_HUMAN |
| Network | PARTIAL — cached offline and incomplete synthetic transfer recovery pass; real cellular remains pending |
| Original physical-device freeze | UNVERIFIED |
| Machine-actionable baseline work remaining | NONE |

The remaining physical plan is still the original phone's normal/long/entitled
quality Tracks, ≥30 EOFs, background/lock, focus interruptions, Bluetooth and
Wi-Fi/cellular, with secret-free phase/counter evidence. The contention
observation is explicitly retained for that review; passing a quieter same-APK
run does not prove why it failed or prove the original problem fixed. No mobile
cache-budget change, per-key Provider-cache refactor or new Provider/session
feature was added.

## Autonomous focus failure-path continuation — 2026-10-06

Starting HEAD, local `origin/main`, and fresh read-only remote main were
`33d27585195eb6a10fab75e9be2ee4a9fba1fcad`; initial worktree clean. Human
authorized the existing Android playback reliability direction, not Provider,
refresh, persistent-cache, UI, Git or new-runtime work. The earlier checkpoint's
baseline exhaustion does **not** close its retained negative latency evidence.

### Selected finite tasks and before-fix reproduction

1. **Bound caller focus lifecycle without unsafe late cleanup.** Concrete
   provenance: the recorded ~5.5 s play timeout / ~40 s focus release. Inspection
   showed MediaKit's bounded `_serialize('play')` catch awaiting unbounded
   `_deactivateFocus`; pause/stop `finally`, disposal and activation had the same
   shared boundary, including the audioplayers rollback engine.
2. **Revoke a same-source acquisition result before native dispatch.** During
   the first task's diff/concurrency review, a further deterministic failing
   test showed release beginning after `activate()` returned a completed Future
   but before its play continuation/native dispatch. This was selected as a
   separate finite task, not dismissed by the first Android PASS.

Before changing production code, injected never-completing native play plus
pending release (20 ms native deadline, 150 ms test watchdog) threw the **test
watchdog TimeoutException**, not the required coarse engine exception. Separate
tests showed a new source activating while old disposal/release was pending,
and a disposed source invoking native play after late focus activation. All
three failed on the starting implementation. The later same-source test also
failed: native play count increased while release was still pending. Its failed
trace is retained in `acquire-release-race-before.log`, not overwritten by PASS.

### Ownership and bounded policy

`ForegroundAudioFocusOwner` is a small shared engine-lifetime arbiter over the
existing `ForegroundAudioFocusManager`; it does not introduce another Android
focus requester or system edge. Main constructs only one selected music engine.
Each source gets a lease, and release/close changes that lease's revision.
Both engines check its revision after activation; MediaKit checks again inside
the actual serialized native play closure. Stale play failure cannot release a
newer revision, and stale source cleanup cannot abandon another source's lease.

- Default focus caller budget: **5 s per phase**, aligned with the existing
  MediaKit control budget. It is not a service TTL or a total-control 5 s claim.
  Native control remains 5 s, open 15 s. A native play timeout followed by focus
  cleanup may consume both bounded phases (roughly 10 s plus scheduling), rather
  than wait indefinitely. Wall-clock bounds assume the Dart isolate can run.
- A deadline does **not** free the raw platform slot or cancel the Future.
  New activation is rejected while old platform work/compensation is pending.
  Concurrent same-lease activation is single-flight, not a queue of requests.
- Late activation after timeout/disposal is compensated by one release before
  the slot becomes reusable. Late acknowledged release permits a subsequent
  explicit action; it does not automatically resume/reopen/resolve.
- A release returning false or throwing leaves ownership unconfirmed and the
  engine fail-closed. Repeated cleanup does not automatically retry it. No
  native Player rebuild bypasses that reservation. This public-SDK limitation
  is TD-018, not silently reported as successful platform cancellation.
- Error/disposal cleanup observes the bounded failure without leaking an
  unhandled asynchronous exception or overriding the original typed native
  failure. Active pause/stop/release failure remains typed; disposal still
  finishes its terminal stream/player cleanup.

The change does not add native-operation deadlines to unrelated audioplayers
methods. Its shared **focus** waits are bounded; no claim is made that all its
plugin Futures are now cancellable or bounded. Rust Queue, Bridge, retained
seek/play, Player/source cache budgets and Provider resolution are unchanged.

### Pinned SDK inspection and causal boundary

Local audio_session **0.2.4** implements Android deactivate by awaiting
`AndroidAudioManager.abandonAudioFocus`; its Kotlin handler calls
`AudioManagerCompat.abandonAudioFocusRequest` synchronously then returns the
method-channel result. Its `AudioSession.instance` does platform configuration
I/O on first construction, not each subsequent lookup. There is no public
operation cancellation/settlement-reset API. The old trace locates the long
Fura wait at focus release; it cannot determine whether the native call,
method-channel delivery or scheduling caused it.

Local media_kit **1.2.6** play takes its SDK lock, awaits initialization, then
sets `pause=false`. An acknowledged retained-source seek sets completed=false,
so its completed compatibility branch should not run. In async configuration,
`_setProperty` awaits a Completer completed by `MPV_EVENT_SET_PROPERTY_REPLY`.
The historical outer play trace does not distinguish SDK lock wait from async
reply delivery. No private SDK patch, unredacted native trace or invented
native/scheduler root cause is claimed. Future in-flight native traces are
required to close that specific historical cause (TD-018).

### Validation checkpoint

Final runtime results are recorded below after candidate execution. Evidence
directory: `/tmp/fura-focus-regression-20261006-plb8R1` (outside Git). The first
four-case Debug candidate passed before the additional revision fix; its logs
are retained with `debug-first-pass-*`, but are not final-candidate acceptance.
Current final candidate adds the revoked-result race and real Android
audioplayers focus regression to the existing D replay/stall/network harness.
Only synthetic local media is used: no Provider request, credential, account
content or production localhost proxy.

### New negative evidence from validation (retained separately)

- The first revision-corrected five-case Debug run passed the D replay,
  injected seek recovery, focus-acknowledgement/revision and transfer cases, but
  **failed as a suite**: the additional audioplayers case timed out in source
  preparation after ~30 s, before any focus activation. It is retained under
  `debug-http-fixture-failed-*`. It is not a focus PASS or relabelled full PASS.
  The installed APK targetSdk=36 has no USES_CLEARTEXT_TRAFFIC flag and no
  network-security configuration. Android explicitly documents that
  [target API 28+ defaults to disallowing cleartext and MediaPlayer honors it](https://developer.android.com/guide/topics/manifest/application-element#usesCleartextTraffic).
  This establishes that mpv's loopback-HTTP fixture is unsuitable for that
  platform component; no missing focus callback can explain a failure before
  activation. Without a native exception trace, it does not establish every
  intermediate step inside that preparation timeout.
  The bounded focus oracle now supplies the same synthetic MP3 bytes from an
  app-private temporary file through the existing player test seam. It still
  invokes real Android MediaPlayer, real audio_session, actual pause/resume and
  position advancement. It does not relax manifest/TLS policy, advertise a
  production file resolver, ignore native errors or claim remote A transport
  acceptance. Only the test-owned file/directory are deleted afterward.
- The **local Debug fixture APK** artifact audit finds build-path/personal-marker
  strings in `kernel_blob.bin`. Both the earlier audit and the final candidate
  audit exit nonzero, retained in `debug-artifact-privacy.log` and
  `debug-final-artifact-privacy.log`. The **Release fixture** audit also fails:
  `libapp.so` contains exactly two personal-root source-location strings, both
  `file:` URIs for integration-test sources. Its failed audit is retained in
  `release-fixture-artifact-privacy.log`. Debug/test source-location metadata is
  not a distributable-privacy PASS. Both fixture APKs stay local, outside Git;
  no credential/account/media source data is involved. Ordinary distributable
  artifact audits are separate, never inferred from source lint or a fixture.
- The Waydroid Debug/Release screencaps contain a real fixture window/label but also
  text/GPU rendering artifacts. It proves a rendered fixture exists, not clean
  visual acceptance. No Flutter rendering/UI code is changed by this Core task;
  `vo=null` music Player has no video surface/controller. A GPU-driver/rendering
  diagnosis is outside the authorized focus/replay change. The screenshot is
  retained rather than substituted with a clean mock/reference image.
- At this continuation's runtime startup the existing container was FROZEN:
  ADB appeared offline/unresponsive despite a running session. Normal full-UI
  launch unfreezes it and Android API/ABI queries then succeed. No image/init,
  data reset or host policy edit occurred. This environment finding is not
  evidence that the historical play/focus delay was caused by container freeze.

### Final candidate Android runtime evidence

Existing Waydroid 1.6.3, Android 13 / API 33, native x86_64 is the only Android
runtime used. No physical phone is connected. No AVD/image installation, user
data reset, stored-account operation or host-network/focus policy change is
performed. Builds and runtime gates are separated; only this task's verified
idle Gradle daemon is stopped before the runtime gate, not unrelated processes.

Both **Debug and Release five-case suites PASS** on the final production
candidate. The integration entrypoint uses no FURA defines: requested/effective
D, one Dart entrypoint, audio_service plugin registration false, and the real
flutter_media_session edge available. The music Player, Android audio_session,
typed Bridge and Rust Queue are real; resolution and media are synthetic.

| Observable in normal retained-source soak | Debug | Release |
| --- | ---: | ---: |
| Actual EOF events / replay actions | 101 / 100 | 101 / 100 |
| Initial resolutions / initial opens | 1 / 1 | 1 / 1 |
| Repeat resolutions / repeat opens / repeat stops | 0 / 0 / 0 | 0 / 0 / 0 |
| Total seek / play / stop | 100 / 101 / 0 | 100 / 101 / 0 |
| Normal Player rebuild / native errors / extra fixture HTTP requests | 0 / 0 / 0 | 0 / 0 / 0 |
| Replays while actual Activity is backgrounded | 2 | 2 |
| Actual pause / resume callbacks | 22 / 22 | 22 / 22 |
| Fully cached replays while fixture server is closed | 20 | 20 |

Each suite also passes the following independently asserted failure/restore
cases; these are not folded into normal-soak counts:

- An injected never-completing native seek hits its one-second test deadline;
  the operation tail remains usable and one explicit load retires/rebuilds the
  real Player and advances position. No EOF-driven recovery or resolver retry.
- Delayed focus acknowledgement uses a test seam **after the real platform
  release**: its 250 ms caller budget returns a typed failure in 254 ms Debug /
  252 ms Release. Replacement activation is blocked until acknowledgement;
  subsequent explicit play advances. Old disposal produces zero stale release.
  A same-source release revokes a pending play result before native dispatch.
- Actual Android audioplayers/MediaPlayer plays the app-private synthetic MP3;
  pending release acknowledgement blocks resume, late acknowledgement permits
  explicit resume with position advance. Two activations and two releases;
  no alternate system edge or remote-media acceptance is implied.
- An incomplete ~166-second source initially delivers only 65,536 bytes,
  withholds the rest for three seconds, then restores it. Playback progresses
  and seek beyond 60 seconds consumes the restored tail: open=1, play=1,
  nativeErrors=0. This is not Wi-Fi/cellular or whole-device offline evidence.

`debug-final-diagnostics.log`, `debug-final-observations.log`,
`debug-local-fixture-final-gate.log`, `release-final-diagnostics.log`,
`release-final-observations.log` and `release-final-gate.log` retain the actual
results. After Release terminal cleanup, dumpsys observes zero active Fura
focus entries and zero media sessions. The checkpoint-100 snapshot races
terminal cleanup and is not used as proof of terminal focus release.

Memory samples below are KiB, not a physical-device cache-budget acceptance:

| Mode / checkpoint | Total PSS | Total RSS | Native heap PSS |
| --- | ---: | ---: | ---: |
| Debug start | 411838 | 476396 | 37208 |
| Debug 10 | 369524 | 435840 | 34780 |
| Debug 30 | 373905 | 441088 | 38276 |
| Debug 100 | 375964 | 443396 | 38528 |
| Release start | 169416 | 227552 | 33268 |
| Release 10 | 170758 | 235840 | 27988 |
| Release 30 | 173837 | 240252 | 28240 |
| Release 100 | 173993 | 240600 | 28268 |

The short silent fixture is muted. It proves native decoding, position,
retained-source lifecycle and state/focus ownership, **not audible output** or
long/high-quality/OEM memory behavior. No cache-budget change is justified by
these bounded samples.

### Ordinary startup, artifact provenance and closure checks

Ordinary **A Debug** passes one cold start with audioplayers/audio_service,
AudioServicePlugin registration true, system-edge success and first frame.
Ordinary **no-define D Release** passes three independent cold starts with
media_kit/flutter_media_session, registration false, available system controls,
one Dart startup and first frame. The ordinary D Release, not a fixture, is left
installed. These are startup/ownership checks, not authenticated or audible
remote Track acceptance.

All four artifacts use the same starting HEAD **plus this uncommitted candidate**,
native x86_64, the existing Flutter 3.47.1 / Dart 3.13.1 and pinned dependencies.
No global toolchain/JDK/host policy was changed. They are not ARM64 phone packages.

| Local artifact under `/tmp/fura-focus-regression-20261006-plb8R1` | SHA256 |
| --- | --- |
| fura-focus-D-fixture-x64-debug.apk | 9e7c13154a917d9c1f47c516a34314639d4ccac814150b6b8721fbfe9552e376 |
| fura-focus-D-fixture-x64-release.apk | 4807c719d69a157cc14fe4b2807a21c583e7684b6daa590440e63070c4891245 |
| fura-focus-A-ordinary-x64-debug.apk | a07a87c1ca207eb80c4fb41e8c7a62b6e1020272199cabe9f6e03942d4a28665 |
| fura-focus-D-ordinary-x64-release.apk | 314d3f2683c18714546f558acd193fc3d598b4673827c0a93c209ae2de2f49de |

The ordinary D Release **passes** the artifact build-path/personal-marker scan
(`ordinary-release-artifact-privacy.log`). Ordinary A Debug also retains source
paths in `kernel_blob.bin` and **fails** that scan
(`ordinary-debug-artifact-privacy.log`); it stays a local diagnostic APK. Fixture
and Debug privacy failures do not become PASS because the ordinary Release
passes. No build artifact or private runtime evidence is added to Git.

Final checks: `dart format --output=none --set-exit-if-changed` over six changed
Dart files, whole-app `dart analyze` (no issues), all **267** affected playback
and startup diagnostic tests, source privacy hygiene, application identity,
five existing privacy-audit tests and `git diff --check`. The final rerun is
`playback-tests-closure.log`, analysis `analyze-closure.log`. Failure or success
is established by exit code, not only a log grep. No Rust/Bridge contract change,
FRB regeneration, remote CI execution or service/account acceptance is claimed.

### Negative-evidence exhaustion and exact remaining boundary

| Finding | Classification | Evidence / remaining prerequisite |
| --- | --- | --- |
| Bounded native failure followed by unbounded focus cleanup | FIXED_AND_VERIFIED | Failing before-fix deterministic test; bounded typed failure after fix; shared A/D tests and real Android delayed-ack cases |
| Late activation/disposal or old release overlaps replacement | FIXED_AND_VERIFIED | Raw slot reservation, one compensating release, stale lease isolation; deterministic and Android checks |
| Acquisition result revoked before actual native play | FIXED_AND_VERIFIED | Separately failing race; revision checks before actual dispatch; no native play on revoked result |
| Exact historical ~5.5 s play / ~40 s focus-release native cause | PRECISE_BLOCKER | Old outer trace has no in-flight SDK lock/mpv-reply/AudioManager/main-thread trace; current runs do not reproduce that internal delay. Fresh in-flight native evidence is required; no host-load causal claim |
| Raw platform call never acknowledges or release returns false/error | PRECISE_BLOCKER | audio_session 0.2.4 has no public cancellation/settlement-reset acknowledgement. Caller is bounded and ownership fail-closed; safe automatic recovery needs actual settlement or a verified upstream API (TD-018) |
| Audioplayers cleartext HTTP test preparation timeout | OUT_OF_SCOPE_WITH_EVIDENCE | targetSdk 36 disallows cleartext for MediaPlayer; focus was never reached. Test-owned local MP3 restores the intended real native focus oracle; remote A transport remains unclaimed |
| Local Debug / integration-entrypoint APK source paths | OUT_OF_SCOPE_WITH_EVIDENCE | Test/source-location metadata findings remain failed local audits; ordinary distributable D Release independently passes. No fixture distribution is authorized |
| Waydroid fixture glyph/rendering artifacts | OUT_OF_SCOPE_WITH_EVIDENCE | Actual Debug/Release screencaps retained; Core focus/replay scope changes no renderer, UI or video surface |
| Existing Waydroid FROZEN / ADB unavailable | FIXED_AND_VERIFIED | Normal full-UI launch unfreezes the existing runtime; API/ABI queries and actual Android gates pass, no reset/init |
| Original physical freeze, OEM/lock/phone-call/Bluetooth/cellular, long/entitled quality/cache budget | REQUIRES_HUMAN_DEVICE_EXTERNAL_EVIDENCE | Only native x86_64 Waydroid is connected; original phone and those real lifecycle sources are unavailable |

The authorized finite fixes are machine-verified. Final diff/failure review found
no additional independent, currently executable evidence-backed task within this
direction. The next trigger is fresh native-delay evidence or physical-device
lifecycle acceptance, not Provider/auth/cache/UI work or artificial host swap
exhaustion. This does **not** declare the original phone freeze fixed.

Machine-actionable work remaining:

- Historical internal delay diagnosis: blocked by missing fresh in-flight native
  lock/reply/main-thread evidence; an outer historical duration cannot recover it.
- Never-acknowledged focus recovery: blocked by absent public platform
  cancellation/settlement acknowledgement; unsafe lease reset/retry is rejected.
- Physical lifecycle acceptance: device/OEM/audio-routing/real cellular evidence
  required; Waydroid counters cannot substitute.

Execution mode: AUTONOMOUS_DEVELOPMENT
Work domain: CORE
Gate: DEVICE_REQUIRED

Implementation-checkpoint Git state: no commit, push, reset, restore or clean.
Human subsequently authorized publication with `提交git`, under the standing
commit-and-push instruction. That authorization does not change any runtime,
physical-device or negative-evidence acceptance above.
