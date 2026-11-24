# Production playback stack convergence (HD-037)

Baseline `b9dbb1de85c96fad95f9206b17cb5a4bcfaca835`. Existing UI/artwork
and QQ research changes in the checkout are separate from this task.
HD-037 supersedes the experiment-retention and selection requirements of
HD-033. The original experiment and device evidence remain historical records.

## Before and after

| Component | Before | After | Disposition |
| --- | --- | --- | --- |
| Music engine | Default MediaKit with Audioplayers reachable via flags and alternate app composition | One engine-lifetime MediaKit Player; alternate callers supply a host or engine | KEEP_REQUIRED / RETIRE_LEGACY |
| System owner | Requested/effective A/B/C/D selection, optional alternate AudioService edges | One static edge per platform over the existing Queue controller | RETIRE_LEGACY |
| Android native | Conditional receiver, service, registry and Activity engine setup for AudioService or Media3 | Media3 receiver and local media-playback service; FlutterActivity; AudioService excluded from Android runtime registration | REPLACE_WITH_UPSTREAM |
| Windows native | Flutter Media Session and separate AudioService SMTC plugin | Flutter Media Session only | REPLACE_WITH_UPSTREAM |
| Linux native | Direct Dart DBus MPRIS, Audioplayers plugin and its GStreamer packaging | Direct Dart DBus MPRIS, MediaKit/libmpv, dormant upstream GIO plugin registered by Flutter | PLATFORM_GATE_REQUIRED |
| iOS native | MediaKit and AudioService | Same fixed iOS edge with the existing focus owner | PLATFORM_GATE_REQUIRED |
| MV and Rust Queue | Independent finite video Player; positional Rust Queue | Same owners with the same source, Queue and Roam contracts | KEEP_REQUIRED |

Removed the Audioplayers class, plugin seams, dependencies, generated
registrations and rollback-only tests. Shared engine and decoder contracts
now execute against MediaKit. Removed the playback stack selector, Gradle and
Dart define readers, legacy Android declarations, conditional Activity engine,
old channel/icon configuration and the unused AudioService MPRIS volume
forwarder. The Linux package no longer requires Audioplayers' GStreamer
modules or scanner. Other ELF dependency, graphics, MIME, secure-storage and
WebView exclusion checks remain in force.

Kept the source generation, serialized native dispatch, bounded recovery,
acknowledged focus lease and engine retirement, retained EOF replay, coarse
failures, and independent MV session. The Flutter system edge rejects queued
seeks after the playback generation changes and joins pending activation
before teardown. The protected app owner still decides all Queue operations.

## Released source and platform ownership

Checked on 2026-11-24. [flutter_media_session 3.2.1](https://pub.dev/packages/flutter_media_session/versions/3.2.1)
is the stable resolved pin. The exact [pub archive](https://pub.dev/api/archives/flutter_media_session-3.2.1.tar.gz)
has SHA-256 `12c3fae81577077d51b568236bad89d40e7cbec8616b08a48bcbe9796633e333`,
matching the generated lockfile. [Tag v3.2.1](https://github.com/wyrindev/flutter-media-session/tree/v3.2.1)
peels to `00eed667323de53db72f0ca65c5739e153c2a37f`. The archive declares
Dart `>=3.3.0 <4.0.0`, Flutter `>=3.3.0` and MIT. Linux adds one
GIO-linked shared object. The app uses the released platform interface for
projection and one action stream. The native Android activation uses a
regular service start/bind, removing the 3.0.5 foreground-start priming.
Media notification permission is declared. The projection uses direct
platform activation to avoid requiring an opt-in permission dialog as
a prerequisite for a media session.

[MediaKit 1.2.6](https://pub.dev/packages/media_kit/versions/1.2.6) remains
pinned with `media_kit_video` 2.0.1 and `media_kit_libs_video` 1.0.7.
The video native package covers both music and video; the formal native
redistribution notice gate TD-006 still applies. The new Flutter plugin's
MIT notice is carried by the Flutter/Dart dependency-notice mechanism.

| Platform | Session lifecycle | Focus/interruption | Runtime boundary |
| --- | --- | --- | --- |
| Android | 3.2.1 Media3 service; direct app projection | Fura `audio_session` lease; disable upstream focus before activation; one Media3 noisy-device pause channel | ARM64 build and merged manifest are distinct from phone/task removal, lock screen, headset and focus behavior |
| Linux | One Fura MPRIS name; upstream plugin has no active bus owner | Desktop audio routing; Linux lease has no mobile native focus operation | Release first frame plus isolated real bus and synthetic native playback |
| Windows | 3.2.1 SMTC | System audio routing | Native build and SMTC/AUMID acceptance require Windows |
| macOS | 3.2.1 Now Playing/Remote Command Center | System audio routing; no iOS-only AVAudioSession configuration | Native build, artwork and command acceptance require macOS |
| iOS | Fixed AudioService exception | Existing `audio_session` sole lease | Apple native/device regression plus an upstream projection-only option required |

The Android service still owns becoming-noisy delivery with its focus option
off. Fura therefore uses the Dart noisy stream for the other environments
only. Android's conditional build copy became an unconditional exclusion of
AudioService's plugin registration. The shared iOS package still enters the
Android dependency graph and macOS generated registration. In its Darwin
source, registration sets up channels, while MPRemoteCommandCenter activation
requires a playing state from the Dart handler. Only iOS initializes that
handler. Full exclusion on Android/macOS follows removal of the shared pin.

On Windows, the published SMTC updater ignores omitted text fields. Fura
sends blank text when those fields are cleared. Omitted artwork and duration
have no equivalent clear operation in the released updater. macOS removes
omitted artwork but writes duration only when positive. Native acceptance
must verify track replacement and Queue clearing with previously published
artwork and duration. Native mode events carry toggle/cycle intent without
the requested explicit mode. Absolute seek is projected through the current
generation. Relative seek is covered by Fura's retained Linux edge.

On iOS, the archive's `MediaSessionManager.swift` calls
`configureAudioSession()` in `activate()`, sets the category to playback
and calls `setActive(true)`. Playing updates can call it again. The Android
interruption switch does not disable those calls. The minimal upstream exit
is an explicit projection-only option covering activation, playing updates,
and interruption/route delivery, followed by an iOS device gate.

## Linux takeover experiment

Built the archive's unmodified `linux/mpris_player.cc` against host GIO in
a disposable C++ driver. The driver published synthetic metadata with a
current Track path and one Playing position sample on `dbus-run-session`.
An external `busctl` client read Position at two times, sent an old Track
path to SetPosition and wrote Volume. The upstream service delivered
`seekTo` with a position for the stale Track, returned the same 1,000,000 µs
sample while playing, returned Volume 1.0, then exited on GLib's assertion
that a failed property setter must set a GError. The archive sends position
under `args`/`positionMs` but has no Track path field at the Dart boundary.

| Contract | 3.2.1 evidence |
| --- | --- |
| Name, root/player interfaces, application fields | Real bus registration; identity and DesktopEntry settable via native API |
| Metadata, artwork, duration, Track path | Source maps metadata and synthesizes a Track path; does not round-trip Fura's positional authority for seeks |
| Playback/position, paused freeze, Seeked | Playback state stored; Position is a static sample while playing; Seeked is declared without a matching emission on accepted seek |
| Relative and absolute seek | Both dispatch a target time; relative uses a static origin; absolute accepts a stale Track path |
| Delayed-dispatch invalidation | Public event lacks Track identity, so Dart cannot restore the original request semantics |
| Shuffle, LoopStatus | Projection exists; setters discard the requested value and emit toggle/cycle action |
| Volume | Getter fixed at 1.0; real write terminated the probe |
| Available actions | Native capability fields exist; methods are dispatched without enforcing all sampled capabilities |
| Exit and replacement consistency | Source unregisters on deactivate. Volume failure exits unexpectedly. Full native candidate parity is blocked |

Retain the project edge. It now publishes the installed desktop entry. The
upstream correction should validate the incoming Track path before
SetPosition dispatch, carry that path to the receiver for queued-command
revalidation, project position from a monotonic anchor, emit Seeked on
settled seeks, and propagate requested mode and volume values with typed D-Bus
errors. No upstream modifications were published.

## Verification and remaining acceptance

| Gate | Local evidence |
| --- | --- |
| Dart and Flutter | Format check for `lib test integration_test`, `dart analyze`, and `flutter test --no-pub` all passed. Full Flutter unit/widget suite: 1,149 passed, including the final Windows SMTC text-clearing regression. |
| Rust Queue and Bridge | Rust 1.97.1 workspace format check and strict Clippy on `music-domain` and `rust_lib_flutterustmusic` passed. Targeted `test --locked --all-targets`: 208 passed, 4 ignored. No Rust APIs or generated bridge changes. |
| Python, packaging helpers and workflow | `test_privacy_audits.py`: 49 passed with the Apple-only fixture skipped. Privacy hygiene and identity passed. AppRun, AppImage tool, bundle normalization, shell syntax and actionlint checks passed. |
| Android ARM64 | Debug and privacy-wrapper Release APK builds passed. Actual APK manifests each declare one Media3 receiver and the local mediaPlayback service. Build-owned registrant includes Flutter Media Session and excludes AudioService. Release ABI, native entries, Rustls JNI symbol and artifact privacy passed. Release APK: 47,039,205 bytes. |
| Linux Release | Privacy-wrapper build, installed identity, artifact privacy and first frame passed. Isolated session bus and PlayerCtl confirmed one MPRIS owner, Stopped, Volume round-trip and name removal at process exit. |
| Linux native music | `system_playback_service_test.dart`: 1 pass. `linux_playback_reliability_test.dart`: 2 passed with real MediaKit and D-Bus. `playback_engine_test.dart`: 5 passed including MP3, M4A and FLAC over loopback, 100 replacements and 100 retained EOF replays. 101 total EOF events, zero additional HTTP requests on replay and no native error category. |
| Linux native MV | `music_video_engine_test.dart`: 1 pass with a real native texture and local MP4. |
| Linux native packages | Local Ubuntu 24.04 DEB, Fedora 43 RPM and Arch packages from the same Manjaro Release bundle passed checksum, privacy and ordinary-user launch with X11, first frame, media engine and MPRIS. Arch also passed reinstall/remove and retained the user config marker. |
| Linux AppImage | Built from the same bundle on Ubuntu. The compressed artifact is 117,283,320 bytes. Ubuntu and Fedora each passed checksum, privacy, ordinary-user X11/first-frame/media-engine/MPRIS smoke and audit of all 275 extracted ELF payloads. AppDir: 379,348,519 bytes. |

The Linux Release bundle had 11 ELF payloads and 48,165,958 bytes before
normalization. Earlier checkout output with Audioplayers had 74,285,749
bytes, from an uncontrolled build, so these figures cannot quantify the
dependency retirement. `readelf` tied GStreamer directly to the previous
Audioplayers plugin. `ldd` checked libmpv in the three distro builders and
found no GStreamer or missing dependency. No final bundle ELF requires
GStreamer, WebKitGTK or JavaScriptCoreGTK. AppRun still retains its GTK
hooks, MIME cache and libmpv/secure-storage closure. TD-006 still governs
the formal redistribution inventory.

The final Linux Debug soak sampled RSS 453/476/481/358/362 MiB and threads
107/96/71/70/71 at 0/10/20/50/100 source replacements. It kept one music
Player. Those whole-process Debug samples establish bounded synthetic
exercise and observable resource behavior, with no cross-build savings claim.
The local native packages were built before the final Windows-only SMTC text
clearing change. Hosted platform builds, x64 Android and FUSE mount testing
were not run during this local task.

### Negative evidence and recovery

- The first Linux packaged identity check found missing MPRIS `DesktopEntry`.
  The direct edge now publishes the application desktop-file stem, covered by
  the real session bus integration test and the install verifier.
- A shared Flutter Linux ephemeral cache retained the Release GTK engine
  when a Debug integration binary was rebuilt. The loader could not start the
  Debug isolate. The stale ignored engine file matched the Release artifact.
  Moving just that generated file aside and running the native files serially
  restored the matching mode. The earlier multi-file launch failure remains
  in the record.
- The first native FLAC assertion timed out while waiting for progress from
  a single-block test sample. EOF was observed. A verified multi-block
  silent fixture exercises progress with the original assertion.
- The first Android APK inspection found that `apkanalyzer` represents the
  same mediaPlayback flag as hexadecimal `0x2`. The checker now handles both
  real representations and rejects extra type bits and the connected-device
  permission.
- The local AppImage builder finished creating the artifact before its
  command deadline during post-build verification. The exact file was
  checksummed and verified separately in clean rooms. Synthetic forbidden
  roots such as `/home` and `/root` also matched ordinary upstream bytes.
  The clean-room rerun used the actual workspace and builder-home roots and
  the CI workspace/home spellings with the same unchanged auditor.

### Scope and platform exit conditions

The production composition constructs one music Player and one active system
edge per supported OS. Linux and desktop builds do not request mobile audio
focus. Android and iOS have one app-owned focus lease. Foreground operation
survives edge initialization failure using the same controller and engine.
No flag, package dependency or generated registration for Audioplayers
remains. `audio_service_win` is absent. The residual `audio_service` package
has an iOS production consumer. Flutter still emits its macOS registration
and Android input registration through the shared package. Neither activates
an alternate session in the respective composition. The Android compiler
uses the filtered registration. Historical references remain for provenance.

The migration changes no Provider routing, authentication, Library, MV
production or Rust domain implementation. Same-session command routing,
collection continuation and Roam still run through the existing Queue
controller. Other UI/artwork and QQ research changes were already present
in the checkout. No commit, push or upstream publication occurred.

Android platform acceptance needs an authorized ARM64 device for notification,
lock screen, headset/noisy, audio-focus loss, task removal, Activity recreation
and one native session during playback and source replacement. No ADB device
was connected and the installed Waydroid session was stopped. Windows needs
native build and SMTC timeline, metadata clearing and command acceptance.
macOS needs native build and Remote Command Center metadata and command
validation. iOS needs build and physical audio-session regression on the
retained edge. The upstream iOS
and Linux replacement conditions are recorded above.
