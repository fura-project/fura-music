# Playback stack bake-off (HD-033)

- **Status:** machine implementation and build matrix complete; production
  cutover not authorized
- **Starting HEAD:** `a2a0c40532f7c55f58d86ab5ad742c9cac645d44`
- **Machine environment:** Flutter 3.47.1, Dart 3.13.1, Linux x64; no Android,
  Apple, or Windows runtime attached
- **Gate:** `HUMAN_DECISION`

## Decision boundary

HD-033 authorizes a reversible comparison of two independent choices:

1. music engine: `audioplayers` or `media_kit`;
2. system-media edge: `audio_service` or `flutter_media_session`.

It does not authorize a production migration. The build without defines remains
the existing A baseline. All old dependencies, implementations, registrations,
and tests remain present as rollback evidence. Candidate failure never starts
the other music engine and is not counted as a candidate pass.

The invariant path remains:

```text
Provider-owned media resolver
  -> TrackPlaybackController
  -> QueuePlaybackController
  -> Rust positional Queue (canonical)
  -> exactly one ForegroundAudioEngine

exactly one SystemMediaEdge
  -> commands return to the same QueuePlaybackController
```

Neither engine sees Queue semantics. Neither system edge sees source URIs,
credentials, provider protocol values, or a native player. `audio_session`
remains the intended sole focus/interruption owner.

## Exact dependency baseline

| Responsibility | Package | Version | Status |
| --- | --- | ---: | --- |
| production music engine | `audioplayers` | 6.8.1 | retained/default |
| production system edge | `audio_service` | 0.18.19 | retained/default |
| Windows baseline edge | `audio_service_win` | 0.0.3 | retained |
| common focus policy | `audio_session` | 0.2.4 | retained/sole owner |
| candidate music engine and existing MV | `media_kit` | 1.2.6 | retained/candidate |
| existing MV rendering | `media_kit_video` | 2.0.1 | retained |
| existing native MediaKit runtime | `media_kit_libs_video` | 1.0.7 | retained |
| candidate system edge | `flutter_media_session` | **3.0.5 exact** | added |

`media_kit_libs_audio` was not added. The resolved video native package already
provides this product's MediaKit runtime, and both Linux playback integration
and the Android native-library inventory prove that an extra audio package is
not needed for this experiment.

## Selector and four combinations

The internal compile-time selector is intentionally absent from Settings:

```text
FURA_AUDIO_ENGINE=audioplayers|media_kit
FURA_SYSTEM_MEDIA=audio_service|flutter_media_session
```

Unknown values fail closed to `audioplayers + audio_service`. Release builds
without either define also select that baseline. The composition root constructs
only the selected music engine. `initializeAppPlaybackHost` activates only the
selected system edge; the Flutter Media Session path never calls
`AudioService.init`, and the AudioService path never activates Flutter Media
Session.

| ID | Music engine | Requested system edge | Android meaning | Linux meaning |
| --- | --- | --- | --- | --- |
| A | audioplayers | audio_service | production baseline | audioplayers + Fura MPRIS |
| B | media_kit | audio_service | engine-only candidate | media_kit + Fura MPRIS |
| C | audioplayers | flutter_media_session | edge-only candidate | forced to audioplayers + Fura MPRIS |
| D | media_kit | flutter_media_session | combined candidate | forced to media_kit + Fura MPRIS |

Linux is intentionally exceptional: `flutter_media_session` 3.0.5 has no Linux
plugin, so the project-owned MPRIS implementation remains the only Linux system
edge. This is a deliberate platform policy, not an implicit fallback claiming
that Flutter Media Session passed.

## Music-engine ownership

### Audioplayers baseline

`AudioplayersForegroundAudioEngine` preserves its existing per-source
`AudioPlayer` lifecycle. A narrow mechanical test seam was added so the same
behavioral contract can run against both adapters; Queue and controller code
still receive only `ForegroundAudioSession`.

### MediaKit candidate

`MediaKitForegroundAudioEngine` owns exactly one engine-lifetime `Player`.
Each source replacement calls `open(Media(...), play: false)` on that same
Player. Per-source sessions own only subscriptions and focus activation; their
disposal never disposes the Player. Only terminal engine disposal releases it.
The adapter exposes no MediaKit playlist operation, so Rust remains the only
Queue truth. Open failure is a coarse engine failure and never instantiates an
Audioplayers fallback.

The current source contract contains no HTTP-header semantics. The candidate
therefore adds no guessed `Referer`, `User-Agent`, or Cookie. Plugin errors may
contain the source; they are reduced to source-free Fura failures and are not
logged.

The existing MV path still creates an independent, disposable MediaKit Player
per MV session. Its existing product arbitration is unchanged: opening an MV
pauses music, closing it does not invent automatic music resume, and replacing
the Queue Track disposes the MV session. A new regression drives the candidate
music adapter and proves that disposing the MV session does not dispose the
music Player; only terminal Queue/playback-host disposal does.

## System-media ownership

`SystemMediaEdge` is a lifecycle boundary only. Both implementations project
the same provider-neutral Queue/controller state and return commands to the
same `QueuePlaybackController`.

- `AudioServiceSystemMediaEdge` is a minimal wrapper over the retained
  `ProjectSystemAudioHandler`, AudioService initialization, and custom Linux
  MPRIS registration.
- `FuraMediaSessionAdapter` publishes metadata, status, position, duration,
  available actions, repeat, and shuffle. Play/pause/stop/seek/next/previous/
  repeat/shuffle callbacks are serialized and delegated to the existing Queue
  owner. It does not use the package sample's player adapter.
- Candidate synchronization is serialized separately from commands so rapid
  Queue changes cannot publish older metadata/state after newer state.
- Initialization failure yields foreground-only playback around the exact same
  controller. It does not initialize AudioService or construct another player,
  and therefore is reported as system controls unavailable rather than a
  candidate success.

The merged Android manifest contains both retained native declarations:

- `com.ryanheise.audioservice.AudioService` and its media-button receiver;
- `dev.wyrin.flutter_media_session.FlutterMediaSessionService` and the Media3
  media-button receiver.

Manifest retention is required for build-time rollback and does not mean both
sessions are activated. Unit tests prove one selected initialization path;
physical Android inspection must still prove that only one service/session and
one notification are live at runtime.

## Focus and platform source audit

The exact resolved package source under Pub cache was inspected; README claims
alone were not used.

### MediaKit 1.2.6

The resolved Dart/Kotlin/Swift source for `media_kit`, `media_kit_video`, and
`media_kit_libs_video` contains the Player/open/state interfaces used here and
no package-level audio-focus, interruption, or AVAudioSession policy surface.
That source audit supports leaving focus with `audio_session`; it is not a
claim about every opaque native-library implementation on every OS. The shared
engine contract additionally proves that denied `audio_session` activation
prevents candidate playback.

### Flutter Media Session 3.0.5 — Android

The package uses a Media3 `MediaSessionService` plus a forwarding player. It
maps metadata, playback/timeline state, available commands, seek, repeat, and
shuffle to Media3; owns the candidate notification/service and launch intent;
and receives media buttons. Its optional interruption handling is disabled by
calling `setAutoHandleInterruptions(false)` before activation, leaving
`audio_session` as the intended focus owner.

Two Android behaviors remain runtime risks:

- the package still observes becoming-noisy while playing, while Fura also
  pauses through `audio_session`; duplicate pause delivery must be observed;
- `onTaskRemoved` stops the service when it is not playing or has no media
  item, so paused-task-swipe and notification retention require physical proof.

Fura does not enable the package's optional background keepalive.

### Apple

The package implements `MPNowPlayingInfoCenter` and
`MPRemoteCommandCenter` metadata, timeline, play/pause/stop, next/previous,
seek, repeat, and shuffle. Existing Fura Apple AudioService registration and
the iOS `audio` background mode remain untouched.

On iOS, however, `activate()` unconditionally configures and activates
`AVAudioSession`, and the playing path reasserts it. The Darwin method channel
does not expose the Android interruption-policy switch. This conflicts with the
HD-033 rule that `audio_session` is the sole owner. Fura therefore rejects the
Flutter Media Session candidate before activation on iOS instead of hiding the
conflict. Deciding whether to accept a platform-specific system edge, change
the dependency, or retain AudioService on iOS requires a Human decision.

The AVAudioSession path is compiled only for iOS, so the adapter admits macOS
for a future native build/runtime check. No Apple build was available here.

### Windows

The package uses System Media Transport Controls for metadata, transport,
timeline, position, seek, repeat, and shuffle. This is a source-level candidate
advantage over the current `audio_service_win` timeline/seek limitation.
However, the 3.0.5 native side receives requested repeat/shuffle values while
its Dart action bridge does not carry those values (seek is the argument-bearing
exception). Fura can only cycle/toggle those modes from the callback, so native
runtime semantics remain unaccepted. No Windows build host was available.

## Automated evidence

### Behavioral tests

The shared music-engine contract runs against both concrete project adapters
through narrow fake plugin seams and covers:

- open, play, pause, resume, seek, volume, stop, and dispose;
- completion, position, and coarse failure mapping;
- source replacement;
- invalid-source redaction;
- backend instance count: per-source Audioplayers players versus one MediaKit
  engine Player.

Additional candidate regressions cover terminal single disposal, focus denial,
MediaKit errors, selector/default behavior, all Android combinations, Linux
MPRIS forcing, one selected system edge, candidate metadata/action projection,
command delegation to the same Queue, repeat/shuffle, and iOS rejection before
AVAudioSession activation. Existing AudioService tests remain the baseline
oracle.

### Machine commands and results

| Check | Result |
| --- | --- |
| `flutter gen-l10n` | pass |
| `dart format --output=none --set-exit-if-changed lib test integration_test` | pass |
| `dart analyze` | pass, no issues |
| `flutter test` | pass, 645 tests including the final MV-specific regression |
| Linux real-session MPRIS integration, A | pass |
| Linux real-session MPRIS integration, requested D/effective B | pass; custom Fura MPRIS retained |
| Linux real playback integration | pass: Audioplayers MP3/M4A/FLAC and two-source one-Player MediaKit candidate |
| Linux Release A | pass |
| Linux Release B | pass |
| Android ARM64 Debug A/B/C/D | all pass |
| Android ARM64 Release A/B/C/D | all pass |

The final full Flutter count is refreshed in the checkpoint report after all
documentation and tests are complete.

## Build and size results

The Android builds used `--target-platform android-arm64` and the exact two
defines for B/C/D. A used no candidate define. The copied measurement artifacts
were transient and were not added to Git.

| Android build | APK bytes | SHA-256 |
| --- | ---: | --- |
| A Debug | 172,436,757 | `a46860a78986ca270880b177d3a46a20d536f99be1a6c386114f6e388841b513` |
| B Debug | 172,436,762 | `12a889f58d931c7a5aac50d0c4c23dc3700f6d1d11820328352543518dc181e0` |
| C Debug | 172,436,757 | `a6b5ee4460f0fd73afffdcfe8417fdce3dfc1221b8fd4887b54c961172867e1d` |
| D Debug | 172,436,762 | `5e0d1ae9fea3cadb3c3aab324d7be5da26ace69f606d7949ad240041412dbee5` |
| A Release | 45,412,046 | `894c7f536ecb781bb81aa2e7f7bfc89061f80592d62a5f04abeb1c25bf3e400a` |
| B Release | 45,412,046 | `bac27582bf8a5137170e19319098a17c4c97646ed6383fcfaed5a6e36ba90ebe` |
| C Release | 45,412,046 | `631562a1033758991b8b241ef659bb2eb99b565a6b34df34391bd2ad9bdda04a` |
| D Release | 45,412,046 | `5262da9d3b62264aeec0447247e9c1061e4acc90932029cfaed270992db0dbf8` |

All four Release sizes are equal, but their hashes differ. A and C Debug are
equal in size; B and D add five bytes. This does not prove equivalent runtime
behavior.

The A and D Release ARM64 native payloads have the same largest entries:

| Native entry | Bytes |
| --- | ---: |
| `libmpv.so` | 12,369,680 |
| `libflutter.so` | 11,747,528 |
| `librust_lib_flutterustmusic.so` | 9,743,448 |
| `libapp.so` | 9,438,088 |
| `libmediakitandroidhelper.so` | 386,696 |
| `libdartjni.so` | 131,248 |
| `libdatastore_shared_counter.so` | 7,112 |

The measured candidate native delta is therefore zero. This is expected from
the retained dependency model and existing MediaKit MV native runtime, not an
argument to remove either stack.

Both Linux A and B Release bundles total 46,321,832 bytes. Their three largest
files are identical in size: `libflutter_linux_gtk.so` 17,215,480,
`librust_lib_flutterustmusic.so` 16,555,384, and `libapp.so` 10,470,280.
`libapp.so` content differs even though its length is equal.

## Evidence not available on this host

Only the Linux desktop device was attached. The following are deliberately not
claimed:

- Android A/B/C/D runtime behavior;
- one-live-MediaSession/service/notification proof from `dumpsys`;
- notification, lock-screen, Bluetooth/headset, Home/background, screen-off,
  task-switch/swipe, notification reopen, focus-loss, or becoming-noisy proof;
- 20-track, 20-pause, 20-background cycles or D's 100–200 replacement soak;
- Android RSS at initial playback, 20 replacements, or 100 replacements;
- Android thread/native-process leak observations;
- Windows, macOS, or iOS builds and runtime acceptance.

## Human runtime matrix

Use the same physical Android device and a non-secret ordinary Track for each
clearly labeled A/B/C/D build. Record only coarse data; never retain source
URLs, Cookies, credentials, or private Track identity.

For every build:

1. confirm start and advancing position, pause/resume, seek, next, previous;
2. confirm exactly one notification/session and correct metadata;
3. exercise notification, lock-screen, and headset/Bluetooth controls;
4. exercise Home, screen off, task switch, task swipe, and notification reopen;
5. exercise focus loss and unplug/becoming-noisy;
6. run 20+ Track replacements, pause/resume cycles, and background/foreground
   cycles;
7. capture coarse `dumpsys media_session`, notification, service, and
   `dumpsys meminfo` evidence.

For D, additionally run 100–200 source replacements while recording coarse RSS
at initial playback, 20 replacements, and 100 replacements, plus process/thread
stability. Attribute differences by comparing A↔B and C↔D for the engine, and
A↔C and B↔D for the system edge; do not treat “D works” as causal evidence.

## Result and recommendation

### Engine result

`media_kit` passes the available shared contract, real Linux two-source
integration, Linux build, Android builds, and independent-MV ownership
regression. This establishes a viable experiment, not better runtime behavior.
Android soak/RSS and every non-Linux runtime remain open.

### System-edge result

`flutter_media_session` passes Fura's projection, command-delegation,
single-selection, and Android/macOS/Windows source audits, and packages on
Android. It has no Linux implementation, lacks Android physical evidence, has
a Windows mode-value limitation, and conflicts with Fura's sole-focus-owner
rule on iOS.

### Recommendation

Keep A (`audioplayers + audio_service`) as the production default and rollback
baseline. Allow clearly labeled Android B/C/D Human experiments. Do not declare
a migration, remove old code, or make the selector user-facing. The iOS focus
conflict requires an explicit Human/dependency decision before any cross-
platform system-edge cutover; even after that decision, Android physical
acceptance remains mandatory.
