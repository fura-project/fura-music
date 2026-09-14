# Android system playback runtime checklist

Date: 2026-09-15

Decision: HD-030

Gate: `HUMAN_REVIEW`

## Purpose and current boundary

This checklist validates the two independent Android runtime branches left
after the machine-side repair:

1. `ANDROID_SYSTEM_PLAYBACK`: notification, MediaSession, lock-screen,
   headset/media-button, audio-focus and background lifecycle behavior.
2. `NETEASE_ANDROID_MEDIA_PLAYBACK`: one ordinary entitled NetEase Track
   resolves to a safe HTTPS CDN source, reaches the existing audio engine and
   advances playback position.

No physical Android device is connected to the current development host, so
none of the checks below is recorded as passed by the Agent. A successful APK
build or desktop integration test is not a substitute for this matrix. Queue
restoration after Android kills the application process is not implemented and
is explicitly outside the pass criteria.

## Build and install

Build the supported single-ABI artifacts from `apps/flutter`:

```text
flutter build apk --debug --target-platform android-arm64
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Use the Debug APK for the diagnostic run. Do not enable global cleartext
traffic or replace the audio engine while testing.

## Secret-safe diagnostics

Clear old logs before each scenario and retain only Fura's structured,
redacted events:

```text
adb logcat -c
adb logcat -v threadtime | rg 'FURA_DIAGNOSTIC'
```

Permitted fields are lifecycle phase, coarse outcome/failure, Provider name,
safe scheme, exact validated media host, format, quality and TTL. Do not record
or share a full media URL, path, query, Track ID, Cookie, credential, account
identifier or platform exception message.

Expected initialization sequence:

```text
audio_service init started -> success
audio_session configure started -> success
playback_host selected audio_service
```

`playback_host selected foreground_only` means system integration did not
initialize. In-app playback may still work, but the system-playback branch has
failed and the immediately preceding coarse initialization phase is the owning
failure boundary.

## System playback matrix

Start one ordinary, non-secret Track in Fura and confirm its position advances.
Then record each row independently.

| Scenario | Action | Pass condition |
| --- | --- | --- |
| Notification publication | Begin playback, open the notification shade | One media notification shows the same title/artist/artwork and playing state; no duplicate Fura session appears |
| Pause and resume | Use notification Pause, then Play | The same `QueuePlaybackController` pauses and resumes; position and in-app controls agree |
| Previous and next | Use notification controls | The existing positional Queue moves exactly once in the requested direction |
| Seek | Scrub from a supported system surface | In-app and system positions converge without a second player or stale progress |
| Lock screen | Lock the device during playback | Metadata and controls remain available and operate the same session |
| App navigation | Move among Library, Search and Settings | Playback and system commands survive page disposal and navigation |
| Background | Press Home while playing, then return | Audio continues through the media foreground service; state remains synchronized |
| Task removal | Swipe the Activity from recents while playing | Behavior follows the retained `audio_service` task policy without a crash or orphan duplicate session |
| Paused background resume | Pause, background/lock, then use system Play | Resume succeeds without `ForegroundServiceStartNotAllowedException` |
| Headset/media keys | Use Play/Pause/Next/Previous hardware or Bluetooth controls | Each command is received once and delegates to the existing Queue owner |
| Becoming noisy | Disconnect the active wired/Bluetooth output | Playback pauses and does not invent automatic resume |
| Interruption/focus loss | Trigger a call/navigation focus loss | Non-duck loss pauses safely; returning focus does not invent resume policy |

Commands can supplement physical buttons where the device image supports them:

```text
adb shell cmd media_session dispatch play
adb shell cmd media_session dispatch pause
adb shell cmd media_session dispatch next
adb shell cmd media_session dispatch previous
adb shell input keyevent KEYCODE_MEDIA_PLAY_PAUSE
```

The system branch passes only when state publication and reverse commands both
work through the same root-owned playback session. Metadata-only display is not
sufficient.

## NetEase Android media matrix

1. Complete the existing official-Web login and confirm the intended account.
2. Select one ordinary standard-quality Track that the account is entitled to
   play; do not use a trial-only, region-blocked or VIP-only item as the only
   sample.
3. Observe this coarse sequence:

```text
media_playback phase=resolve outcome=started provider=netease
media_playback phase=resolve outcome=success provider=netease scheme=https host=mNNN.music.126.net format=... quality=standard ttl=...
playback_engine phase=prepare outcome=success
playback_engine phase=play outcome=success
```

4. Confirm position advances beyond zero, pause/resume works, and selecting a
   second Track does not reuse the first short-lived source.
5. Repeat once after backgrounding the Activity.

The validated NetEase CDN form is one label matching `m` plus 1–4 ASCII digits
under `.music.126.net`, over HTTPS and without user-info, explicit port or
fragment. Any other host, an HTTP source after Rust normalization, or a full URL
in diagnostics is a failure.

If playback still fails, classify it without exposing source material:

- resolution failure: Provider/business/entitlement path;
- engine prepare failure: Android transport/container/decoder path;
- play failure after prepare: focus or platform player transition;
- position remains zero after play success: runtime engine/output path;
- system metadata absent while audio plays: `audio_service` publication path.

## Acceptance record

Record device model, Android API, Fura commit, Debug APK checksum, and a
pass/fail value for every row. Screenshots may show public metadata but must not
show account credentials or diagnostic URLs. HD-030 can close only after the
Human supplies this physical-device evidence for both branches.
