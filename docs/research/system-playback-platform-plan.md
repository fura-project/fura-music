# Cross-Platform System Playback Plan

> **HD-033 update (2026-09-23):** the no-define test request is now D
> (`media_kit + flutter_media_session`), while A remains the explicit rollback
> baseline. Android/Windows/macOS resolve D directly; Linux resolves it to
> MediaKit plus project-owned MPRIS; iOS resolves it to MediaKit plus
> AudioService because exact-pinned 3.0.5 would compete for AVAudioSession.
> This is a test-default change, not Human runtime acceptance or authority to
> remove the retained stack. See
> [the playback-stack bake-off](playback-stack-bakeoff.md).

## Scope and invariant

HD-014 authorizes operating-system music controls on Android, iOS, macOS, Linux, and Windows. One root `AppPlaybackHost` owns the existing Flutter playback controller, selected audio engine and Rust positional Queue handle for the application lifetime. The selected system edge is `FuraMediaSessionAdapter`, retained `AudioServiceSystemMediaEdge`/`ProjectSystemAudioHandler`, or direct Linux `FuraMprisSystemMediaEdge`. None creates a second player, duplicates Queue state, exposes credentials or publishes expiring media URLs.

Common system state is limited to provider-neutral current Track metadata, artwork, duration, position, playing/processing state, previous/next availability, and shuffle/repeat projection. System commands delegate to the existing controller. Product pages may add and remove listeners, but cannot attach, detach, replace, or dispose the playback owner. Only application shutdown closes the host and clears terminal platform state.

## Platform matrix

| Target | Native surface | Implemented wiring | Current evidence | Remaining acceptance |
| --- | --- | --- | --- | --- |
| Android | MediaSession, foreground media notification, lock screen, headset/media buttons | Default D uses `FuraMediaSessionAdapter` / Media3; AudioService declarations and A/B path remain rollback; shared app-lifetime Queue owner and `audio_session` focus | Selector and single-edge unit regressions; Android packaging and Waydroid lifecycle evidence in the dated audits, not physical acceptance | [Physical runtime matrix](android-system-playback-runtime-checklist.md): notification and lock-screen controls, headset buttons, audio focus/interruption, route loss, Activity navigation and background/task lifecycle |
| iOS | Control Center, lock screen, remote commands, background audio | Official Darwin `audio_service` implementation, `UIBackgroundModes=audio`, music audio session | Generated plugin/Info.plist inspection only | macOS-host build plus physical/simulator remote commands, interruptions, route loss and background continuity |
| macOS | Now Playing/remote commands and media keys | Default D uses `flutter_media_session`; official Darwin `audio_service` remains A/B rollback; `audio_session` focus retained | Selection, adapter tests and generated plugin inspection; no new macOS build in this Linux audit | macOS-host build and runtime command/metadata verification |
| Linux | MPRIS over the desktop session bus | Direct `FuraMprisSystemMediaEdge` -> existing Queue/controller -> `ProjectMprisPlayer` -> `dbus`; no AudioService protocol adapter | 2026-10-08 real Rust Queue/native mpv/session-bus gate: metadata, advancing position, all advertised transport/seek/mode/volume commands, disposal and same-name restart, no account access | Human KDE/GNOME presentation/physical playback acceptance is not inferred from protocol or synthetic native gates |
| Windows | System Media Transport Controls | Default D uses `flutter_media_session`; explicit `audio_service_win` platform pin supports A/B rollback | Selection and single-edge tests; generated Dart/native registration and locked package source inspected; no new Windows build in this Linux audit | Native Windows build/runtime; default-D repeat/shuffle callback semantics and rollback TD-008 timeline/seek limitation |

## Shared behavior

- Play, pause, stop, previous, next, supported Queue-item selection, seek, shuffle, and repeat enter through the one selected app-lifetime system adapter and are permitted only when its existing controller permits them. Removing a page listener cannot disable those commands.
- Current metadata never contains a resolved playback URI, vkey, Cookie, credential, or raw QQ response. Artwork accepts only HTTP(S) URIs already present in the provider-neutral Track summary.
- `AudioSessionConfiguration.music()` establishes the one application audio
  session. Immediately before playback, the engine explicitly activates that
  session; pause, stop, completion, failure and disposal release it. The
  Android `audioplayers` context uses `AndroidAudioFocus.none`, so the plugin
  cannot race a second `AudioFocusRequest` against `audio_session`. Non-duck
  interruptions and output-route loss pause the current owner. No automatic
  resume policy is invented.
- The selected edge initializes against the already-constructed controller before credential restoration. Only the retained AudioService edge calls `AudioService.init`; neither direct Linux MPRIS nor Flutter Media Session does. Initialization failure returns a foreground-only host around that same controller with controls explicitly unavailable, never another fallback player or Queue.
- Android media-session notifications are notification-permission exempt. The
  app declares `POST_NOTIFICATIONS` plus the foreground-service permissions and
  media-playback service type, while first play does not depend on the ordinary
  notification runtime grant.

## Known target differences

- Linux exposes timestamp-projected `Position`, Track-bound `SetPosition`, relative `Seek`, shuffle, repeat and bounded volume through the existing handler. It intentionally omits MPRIS TrackList/Queue browsing because the Rust positional Queue remains authoritative. Capabilities derive from the current handler state rather than being permanently advertised.
- The Windows AudioService rollback supports metadata and basic transport only (TD-008). The default-D candidate has timeline/seek APIs but still needs native runtime acceptance, especially for repeat/shuffle callback values; API presence is not acceptance.
- Mobile background continuity keeps the root playback owner independent from Activity/page navigation through the platform media mechanism; it does not add background downloads, autoplay, Queue persistence, or restart-after-process-death restoration.
- Desktop system controls work only while the application process is alive. They are not a daemon or sidecar.

## Dependency decision

Default-D test builds pin `media_kit` 1.2.6 and `flutter_media_session` 3.0.5. `audio_session` 0.2.4 remains the common focus/interruption owner. `audio_service` 0.18.19 remains rollback and iOS fallback; explicit `audio_service_win` 0.0.3 retains Windows rollback. Linux directly uses `dbus` 0.7.15. The 2026-10-08 direct edge migration removes the direct `audio_service_platform_interface` dependency; version 0.1.3 remains transitive through retained AudioService packages. No version or generated plugin changes accompany this ownership correction. The original `audio_service_mpris` static-position/seek/Track-identity defects remain dated evidence, not a reason to reintroduce its adapter. The retained isolated DBus protocol has maintenance cost TD-009; Windows maturity remains TD-008. The [2026-10-07 inventory](linux-startup-playback-dependency-audit-2026-10-07.md) is preserved as historical evidence; the [2026-10-08 audit](linux-playback-failure-mpris-ownership-2026-10-08.md) records current owners and independent native/runtime gates.

## Android ownership and plugin-source audit (2026-09-15)

The locked implementations were inspected rather than inferred from manifest
presence alone:

- `audio_service` 0.18.19 creates the Android `MediaSessionCompat`, attaches
  the handler, enters foreground playback and acquires its wake lock when the
  published playback state changes to playing. With
  `androidStopForegroundOnPause=false`, a paused session remains resumable.
  Media-button and notification commands route back to the same
  `ProjectSystemAudioHandler`.
- `audio_session` 0.2.4 is the project owner for focus, interruption and
  becoming-noisy policy. Configuration alone did not request focus; playback
  now calls `setActive(true)` explicitly and releases the session on terminal
  transitions.
- `audioplayers` 6.8.1 plus `audioplayers_android` 5.3.0 remain the decode and
  output engine only. That Android implementation otherwise defaults to
  `AUDIOFOCUS_GAIN`, which would independently request focus. Fura now sets its
  per-player context to `AndroidAudioFocus.none` before loading a source.

This resolves an ownership conflict without adding `just_audio_background`, a
second Queue, a second player, another handler or a custom Android Service. The
root path remains exactly:

```text
AppPlaybackHost
  -> QueuePlaybackController
  -> TrackPlaybackController
  -> ForegroundPlaybackController
  -> AudioplayersForegroundAudioEngine
```

`ProjectSystemAudioHandler` permanently references that same Queue controller.
AudioService initialization and audio-session configuration now emit only
coarse structured diagnostics and have an injectable success/failure seam.
Initialization failure retains a foreground-only host around the exact same
controller, so it cannot hide the platform fault by constructing another
playback truth.

## Validation protocol

1. Run the provider-neutral handler and Linux MPRIS protocol unit regressions for state projection, command delegation, progressing position, Track-bound seek, shuffle/repeat, application shutdown clearing, and command continuity after page listeners detach.
2. Build every available target and run its isolated native media-session initialization without stored-account access. Linux additionally queries and mutates the registered service over a real disposable session bus.
3. On each real target, use a non-secret ordinary Track and record only coarse results for metadata, play/pause, previous/next, supported seek, interruption, route loss, and background lifecycle.
4. On Android, follow
   [the physical runtime checklist](android-system-playback-runtime-checklist.md)
   and retain only its secret-safe diagnostics. The current host has no attached
   Android device, so this remains `HUMAN_REVIEW`.
5. Keep every unavailable target `environment-blocked`; passing one platform never closes another.
