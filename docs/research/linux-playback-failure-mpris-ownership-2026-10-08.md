# Linux native failure semantics and direct MPRIS ownership

Date: 2026-10-08. Human-directed Core reliability correction.
Starting HEAD, tracked and live origin/main:
`aea2cf1a8edc879917fc2b48b07255fc5e2671fa`. Initial worktree clean.
All candidate changes remain uncommitted. No UI, Provider, Rust Queue, SDK,
dependency version or Git publication change is part of this task.

## A. Evidence and failure boundary

Human reported real retained EOF seek and intentional stop/replacement logs:
native error observation -> session failure/focus release -> the same native
operation succeeds -> replay caller is replaced. A deterministic before-fix
test reproduced the false-fatal ordering; it is preserved separately from PASS.
This proves a Fura classification defect, not the origin of the original mpv
message. Original source-bearing error text was neither collected nor printed.

### Exact pinned implementation

The installed hosted `media_kit` **1.2.6** archive and locked
`media_kit_libs_video` **1.0.7** were inspected, not floating upstream behavior.
Files below are relative to the pinned package's `lib/`:

| Source | Evidence |
| --- | --- |
| `src/models/player_stream.dart:99` | Error stream is documented as error messages, not terminal player state. |
| `src/player/native/player/real.dart:2069–2118` | `MPV_EVENT_LOG_MESSAGE` at error level, filtered file/ffmpeg-tcp/vd/ad/cplayer/stream prefixes, becomes `errorController.add(text)`. There is no source generation, terminal class or command correlation. |
| `real.dart:2613–2640` | Async command reply acknowledgement and log emission are separate from error-stream dispatch; a negative native reply is logged, not necessarily thrown as a Dart Future exception. Command success is not proof that every preceding log is terminal or non-terminal. |
| `real.dart:2128`, `2255`, `2700–2703` | Public `onLoadHooks`/`onUnloadHooks` permit a project-owned source-lifetime observation without private FFI or arbitrary message parsing. |
| `real.dart:1950` | EOF/completed observation uses eof-reached with keep-open; retained seek/play need no reopen. |

The [mpv manual](https://mpv.io/manual/stable/) defines `on_unload` as the
point where the file is closing and cannot resume, before end-file. Loading
failure also follows this lifecycle. This is stronger evidence of lost retained
source than log severity. Local host executable is mpv **v0.41.0**; pkg-config
reports libmpv client API **2.5.0**, not a media_kit package version.

### Implemented rule

- Raw SDK error **data** remains subscribed and produces a redacted
  `native_error_event ... classification=uncorrelated_log`. Never print its
  text, source, credential or Track identity; do not claim its observing source
  generation identifies the originating native log.
- An unexpected native unload of the owned source emits a typed generation.
  The session terminates once with `ForegroundAudioFailure.playback`, bounded
  existing focus cleanup and truthful controller error state. A source-failure
  latch covers unload before a session subscriber/next control exists.
- Explicit stop/open/disposal declares the retiring generation before native
  dispatch. Expected unload is lifecycle cleanup, not another fatal event.
  An old/disposed session cannot emit failure or control the new source.
- Stream-channel exceptions and explicit operation exceptions/timeouts still
  fail; no blanket EOF/replay exemption, missing-error allowlist, text matcher,
  automatic reopen or Provider re-resolution is introduced.
- SDK `open` acknowledges playlist commands before its asynchronous load hook.
  Wait for the public load-hook ownership acknowledgement under the existing
  open deadline. Then capture source generation **inside** that serialized
  operation, not after the outer await. A newly added concurrent-open test
  independently failed before this last fix: the old caller could bind to the
  new source and play it. The fix prevents old play/stop/focus ownership.

This does not certify that every SDK log is harmless. An uncorrelated message
alone lacks sufficient proof to retire the source; actual unload, channel or
operation failure remains authoritative. Future native errors retain their
category and lifecycle investigation requirement.

### Tests and separate native runtime gates

Deterministic regressions cover successful seek plus error message, intentional
stop/replacement, real source failure during an otherwise successful seek,
explicit seek/play failure, late older-generation failure, disposed events,
duplicate fatal events with never-acknowledged focus release, and concurrent
serialized source acquisition. Both shared engine contracts remain exercised.

**Before any MPRIS migration**, real GTK/mpv + Rust Queue + local generated MP3:

| Gate | resolve | open | seek | play | stop | native log events | fatal | focus activate/release | rebuild |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| 33 retained EOF replays | 1 | 1 | 33 | 34 | 0 | 0 | 0 | 1 / 0 | 0 |
| Subsequent replacement, pause/resume, Next, stop, native unexpected unload and corrupt local media | 4 | 4 | 34 | 38 | 2 | 1 | 2 | 5 / 5 | 0 |

Cached replay emitted no additional HTTP requests. Native `stop` injected
outside project intentional-stop bookkeeping and corrupt local media both
entered engine error: genuine failure was not hidden. Real good-source seek
did not reproduce the original Human log text; do not invent its exact cause.

Existing real native suites also passed local/remote MP3, M4A, FLAC, one Player
across 100 source replacements and 100 cached EOF replays. The latter observed
101 completions, zero extra HTTP requests, one active music Player and no
native error categories. These runs are local synthetic playback, not account
access, a production network source or physical-device acceptance.

## B. Direct Fura MPRIS

Before:
`QueuePlaybackController -> ProjectSystemAudioHandler -> AudioServicePlatform`
messages/callbacks -> `ProjectLinuxMprisAudioService -> ProjectMprisPlayer -> DBus`.

After:
`QueuePlaybackController <-> FuraMprisSystemMediaEdge <-> ProjectMprisPlayer -> DBus`.

The existing pure DBus object is moved to `linux_mpris_player.dart`; it is not
replaced with a new MPRIS library. Keep service ID/name convention, process
suffix, `/org/mpris/MediaPlayer2`, metadata/opaque Track path rules, timestamped
position projection, bounded seeks, shuffle/repeat and introspection. No
TrackList, Queue browsing, second audio engine or extra Flutter engine.

| Existing domain/controller | MPRIS projection/command |
| --- | --- |
| Current provider-neutral Track summary/index | Metadata, artwork, duration and current opaque Track path |
| Stage, position sample and timestamp | Playing/Paused/Stopped, advancing/clamped Position |
| Current command availability | CanPlay/CanPause/CanSeek/CanGoNext/CanGoPrevious |
| Queue order/repeat, playback volume | Shuffle, LoopStatus, bounded finite Volume |
| Play/Pause/Stop/Next/Previous | Same controller's playCurrent/pause/stop/advance/rewind |
| Relative Seek/current-Track SetPosition | Same playback seekToMs; stale Track path is rejected |

One `FuraMprisAppPlaybackHost` activates exactly this edge on Linux, never
`AudioService.init`. `audio_session` still owns focus/interruption policy.
Initialization failure returns the **same** foreground controller with controls
unavailable; no alternate edge/player. Page listener detach does not deactivate
the app-lifetime owner. Commands are serialized; closing revokes queued
commands/projection rights rather than waiting for arbitrary network settlement
of already-delegated controller work. Host disposal revokes that controller's
generation. Concurrent activation/close, name/connect failure, unregister
failure and late commands have deterministic tests and owned cleanup.
Final review reproduced a second caller returning early while host DBus
cleanup was still pending. The Linux host now returns one cached disposal
Future to every caller; `concurrent-host-disposal-before.log` preserves the
before-fix failure, and the final regression verifies that both callers await
actual cleanup. Other platforms' hosts are not rewritten.
Another before-fix interleaving queued a valid SetPosition behind a pending
Pause, then changed Track through the existing UI/controller. The old seek
incorrectly reached the new source (`queued-mpris-seek-before.log`: `[1000]`
instead of no seek). Relative/absolute seek events now capture the existing
MPRIS Track path at receipt and require that same path again at dispatch.
This adds no wire field, Track parser, Queue or second command owner. Global
volume/repeat/order commands intentionally retain app/Queue scope.

Real session bus + real Rust Queue + native audio verified service/identity,
metadata, advancing position, Pause/Play, Next/Previous, relative Seek,
SetPosition/stale Track rejection, Shuffle, Track/Playlist/None repeat, Volume
in both directions, Stop, service removal and same-name restart. Counters:
`resolve=3 open=3 seek=2 play=4 stop=3 focusActivate=4 focusRelease=4`.
An initializer trap proves that no Linux AudioService initialization ran.

Only direct `audio_service_platform_interface` ownership is retired. Pub get
changes its lock entry from direct to transitive, keeping **0.1.3** and its
checksum. `audio_service`, `audio_service_win`, `audioplayers`, `audio_session`
and `dbus` remain pinned. No generated plugin registrant changes were found.

## Validation and negative evidence ledger

Temporary logs: `/tmp/fura-linux-playback-20261008-g7bFO5/`; not committed
artifacts, may be removed by system temporary-file policy.

- `before-native-log.log`: reproduced original false-fatal policy.
- `concurrent-source-ownership.log`: new concurrent acquisition regression FAIL;
  in-operation generation capture fixes it; affected regression suite PASS.
- `native-rust-runtime-corrected.log`: independent native gate before MPRIS.
- `direct-mpris-runtime-fixture-corrected.log`: real direct bus/native gate PASS.
- `core-regression-clock-corrected.log`: **145** affected tests PASS. A prior
  exact relative-seek assertion used a playing wall-clock position and was
  wrong by elapsed milliseconds; pausing before that exact assertion supplies
  a deterministic origin. Not resolved by increasing timeout or retrying.
- `core-regression-final-146.log`: **146** final affected tests PASS, including
  concurrent host disposal and old-source stop isolation. Both engines' shared
  contract/focus, Queue/controller and MV ownership regressions are covered.
- `core-regression-final-147.log`: **147** tests PASS after the final queued
  Track-target fix; the preceding 146-test gate is preserved, not claimed to
  have covered an interleaving discovered afterward.
- `app-composition-regression.log`: **131** application/selector tests PASS;
  no UI implementation change or visual acceptance is inferred.
- New test fixture initially threw on lyric load, despite the host legitimately
  asking its lyric gateway. Return typed unavailable; no accounts contacted.
- Initial retained-runtime test expected EOF minus one replays although the
  initial play is separate. Correct oracle is seek=EOF, play=EOF+1. Failed
  trials remain recorded, not labelled native playback failures.
- Six real engine integration cases passed in a multi-file invocation. Starting
  the second executable lost Flutter debug discovery; direct launch of that
  exact built executable started a VM service without an application crash.
  `bus-launch-isolated-diagnostic.log` passes the isolated real-bus invocation.
  SDK source narrows the failure: `flutter_tools/src/desktop_device.dart:46`
  keeps one final DesktopLogReader; `:363` closes its controller when the first
  process exits. `src/test/flutter_platform.dart:486` reuses that device for
  successive integration executables. The second discovery subscribes to an
  already-closed stream. This is an out-of-scope SDK multi-executable runner
  lifecycle defect, not proof that Fura crashed. Use separate invocations for
  actual gates, not an SDK patch/upgrade or a fabricated combined PASS.
- GTK startup reports ATK socket/cursor-theme warnings before playback in
  standalone and fixture programs. They concern desktop accessibility/theme
  resources, outside this frozen-UI/Core task; native audio/bus evidence is
  recorded independently, not a claim that those toolkit warnings are fixed.
- Ordinary `flutter run` reports that the integration-test capture plugin was
  not detected: it is not the instrumented test launcher. Explicit harness
  assertions/counters and its final test result were captured; the same final
  harness also passed under instrumented `flutter test -d linux`.

### Final executed results

- `ordinary-linux-debug-final.log`: ordinary Debug GTK run, both tests PASS.
- `linux-debug-final-instrumented.log`: final Debug native/Rust Queue + bus
  harness PASS after the last ownership/host fixes and stronger Next oracle
  (current Track **and actual playing**, not merely early Queue selection).
- `linux-debug-final-track-ownership.log`: Debug harness PASS again after the
  queued Track ownership correction, including real DBus seeks and stale-path
  rejection. Earlier tests remain separate observations.
- `ordinary-linux-release-final.log`: same final harness in ordinary Release
  GTK/mpv runtime, both tests PASS, native property confirms **mpv v0.41.0**.
- `linux-release-final-track-ownership.log`: both Release harness cases PASS
  again after dispatch-time seek Track ownership was added; run exited normally
  after explicit quit. No earlier binary is claimed to contain this final fix.
- Both final modes have retained counters `1/1/33/34/0`, zero fatal/rebuild,
  no extra cached HTTP read. Following genuine failure injection and all
  transitions, both final gates observed `resolve=5 open=5 seek=34 play=39
  stop=3 nativeErrorEvent=1 fatalError=2 focusActivate=6 focusRelease=6
  rebuild=0`. The additional opens are intentional separate Tracks/invalid
  source, not repeat-one reopen. Async decoding can fail before or after the
  first attempted play; the earlier pre-MPRIS row remains its own observation.
- Both modes' direct MPRIS gate has `resolve=3 open=3 seek=2 play=4 stop=3
  focusActivate=4 focusRelease=4`, service release/restart PASS.
- `linux-production-release-final-track-build.log`: final **ordinary production
  main.dart** Linux Release build PASS after all production fixes. Its app is
  not launched against stored accounts. A fixture Release run is not relabelled
  as production-account acceptance.
- `flutter pub get`, dependency graph, all platform generated-registrant diff
  review, final `dart analyze` (no issues), affected 12-file format check,
  source privacy audit and `git diff --check`: PASS. No package versions change.

Changed scope: production engine, direct MPRIS edge/player/host; direct pubspec
entry and lock ownership; affected MediaKit/shared contract/MPRIS/host/MV tests;
native replay wrapper's interface delegation only; Linux runtime fixtures;
ARCHITECTURE/PROGRESS/TECH_DEBT, research index/current ownership notes and this
audit. Old `linux_mpris_audio_service.dart` and its test are replaced by the
preserved pure player files, not a parallel adapter. No Rust/generated FFI,
Android production, Settings/widget or Provider production code changes.

## C. Remaining boundaries

TD-018 remains open: exact-pinned audio_session 0.2.4 `setActive` awaits native
request/abandon calls without cancellation, settlement reset or safe ownership
transfer. Existing bounded caller/lease tests still apply. Linux focus calls
return true on this platform; Linux success cannot resolve a historical Android
~5.5s play / ~40s release cause or a never-acknowledged platform call. Fresh
traces during recurrence, an upstream acknowledgement/cancellation contract,
and physical OEM/Bluetooth/cellular/phone-focus evidence remain prerequisites.

No new Provider/UI scope, real stored account, physical device, new remote CI,
package install or Human desktop-shell presentation acceptance was tested here.
Settings Human review is independent of this Core task. No commit/push/reset/
restore/clean/rebase/force-push operation is authorized or performed.

Machine-actionable work remaining: NONE within this local Core correction and
its authorized deterministic/native/session-bus validation. Human review of
the candidate/original ordinary-media scenario, and TD-018's specific fresh
trace/upstream/physical prerequisites, are not represented as completed.
Execution mode: HUMAN_DIRECTED. Work domain: CORE. Gate: HUMAN_REVIEW (this
Core candidate, not the unrelated pending Settings visual review).
