# Cross-Platform System Playback Plan

## Scope and invariant

HD-014 authorizes operating-system music controls on Android, iOS, macOS, Linux, and Windows. One root `AppPlaybackHost` owns the existing Flutter playback controller, selected audio engine and Rust positional Queue handle for the application lifetime. Its `ProjectSystemAudioHandler` is the permanent service-facing adapter over that owner; it does not create a second player, duplicate Queue state, expose credentials or publish expiring QQ media URLs.

Common system state is limited to provider-neutral current Track metadata, artwork, duration, position, playing/processing state, previous/next availability, and shuffle/repeat projection. System commands delegate to the existing controller. Product pages may add and remove listeners, but cannot attach, detach, replace, or dispose the playback owner. Only application shutdown closes the host and clears terminal platform state.

## Platform matrix

| Target | Native surface | Implemented wiring | Current evidence | Remaining acceptance |
| --- | --- | --- | --- | --- |
| Android | MediaSession, foreground media notification, lock screen, headset/media buttons | `AudioServiceActivity`, media foreground service/receiver, wake lock and Android 14 media-service permissions; app-lifetime handler/controller owner; music audio session | Handler delegation/lifetime unit regressions; ARM64 Release packaging; Linux real-session integration of the same handler contract | Physical operation of notification and lock-screen controls, headset buttons, audio focus/interruption, route loss, Activity navigation and background/task lifecycle |
| iOS | Control Center, lock screen, remote commands, background audio | Official Darwin `audio_service` implementation, `UIBackgroundModes=audio`, music audio session | Generated plugin/Info.plist inspection only | macOS-host build plus physical/simulator remote commands, interruptions, route loss and background continuity |
| macOS | Now Playing/remote commands and media keys | Official Darwin `audio_service` and `audio_session` registration | Generated plugin inspection only | macOS-host build and runtime command/metadata verification |
| Linux | MPRIS over the desktop session bus | Project-owned `AudioServicePlatform` edge using `dbus`; the shared handler remains the only command/state adapter | Linux Release build; unit protocol regressions; real session-bus integration verifies registration, properties and shuffle/repeat round trips without account access | KDE/GNOME shell metadata/transport, advancing progress, absolute/relative seek, shuffle/repeat and shutdown/stale-state observation |
| Windows | System Media Transport Controls | `audio_service_win` platform implementation | Generated Windows registration and source-level capability audit only | Native Windows build/runtime; metadata and basic transport; TD-008 timeline/seek limitation |

## Shared behavior

- Play, pause, stop, previous, next, Queue-item selection, seek, shuffle, and repeat enter through one app-lifetime `ProjectSystemAudioHandler` and are permitted only when its existing controller permits them. Removing a page listener cannot disable those commands.
- Current metadata never contains a resolved playback URI, vkey, Cookie, credential, or raw QQ response. Artwork accepts only HTTP(S) URIs already present in the provider-neutral Track summary.
- `AudioSessionConfiguration.music()` establishes a music session. Non-duck interruptions and output-route loss pause the current owner. No automatic resume policy is invented.
- `AudioService.init` receives the already-constructed handler/controller before credential restoration. Failure to initialize an unavailable platform session is non-fatal and returns a foreground-only host around that same controller; it does not create a second fallback player or Queue.
- Android media-session notifications are notification-permission exempt. The app declares only the foreground-service permissions and service type required for media playback, so first play does not cause an unrelated notification permission prompt.

## Known target differences

- Linux exposes timestamp-projected `Position`, Track-bound `SetPosition`, relative `Seek`, shuffle, repeat and bounded volume through the existing handler. It intentionally omits MPRIS TrackList/Queue browsing because the Rust positional Queue remains authoritative. Capabilities derive from the current handler state rather than being permanently advertised.
- Windows currently supports metadata and basic transport only. Timeline, progress scrubbing, Queue exposure, and system seek are TD-008.
- Mobile background continuity keeps the root playback owner independent from Activity/page navigation through the platform media mechanism; it does not add background downloads, autoplay, Queue persistence, or restart-after-process-death restoration.
- Desktop system controls work only while the application process is alive. They are not a daemon or sidecar.

## Dependency decision

The integration pins `audio_service` 0.18.19 and `audio_session` 0.2.4 for the common media-session/audio-focus contract, `audio_service_win` 0.0.3 for Windows, and the already transitive MIT-licensed `audio_service_platform_interface` 0.1.3 plus `dbus` 0.7.15 directly for Linux. A maintainer runtime report proved `audio_service_mpris` 0.2.1 unsuitable for the accepted surface: it retained a static position sample and did not implement the advertised seek/shuffle/repeat behavior. The newer prerelease was source-audited but still lacked the required complete position/seek/Track identity behavior, so upgrading would not resolve the defect. The replacement remains one isolated Linux protocol edge over the same shared handler, not another playback owner; its maintenance cost is TD-009. Windows maturity remains isolated in TD-008.

## Validation protocol

1. Run the provider-neutral handler and Linux MPRIS protocol unit regressions for state projection, command delegation, progressing position, Track-bound seek, shuffle/repeat, application shutdown clearing, and command continuity after page listeners detach.
2. Build every available target and run its isolated native media-session initialization without stored-account access. Linux additionally queries and mutates the registered service over a real disposable session bus.
3. On each real target, use a non-secret ordinary Track and record only coarse results for metadata, play/pause, previous/next, supported seek, interruption, route loss, and background lifecycle.
4. Keep every unavailable target `environment-blocked`; passing one platform never closes another.
