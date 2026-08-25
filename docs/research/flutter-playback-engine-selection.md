# Flutter playback-engine selection

- **Status:** `audioplayers` selected for the bounded M1 single-track proof
- **Last checked:** 2026-08-26
- **Scope:** Foreground standard-MP3 playback on Android, iOS, Linux, macOS, and Windows. This does not select background playback, lock-screen integration, downloads, video, or a queue model.

## Required boundary

The first engine slice needs only:

- a remote URL source and a deterministic local test source;
- load/play, pause, stop, completion/state observation, and terminal disposal;
- one Flutter-owned adapter so controllers and tests do not depend directly on a plugin;
- support for all five native product targets without a localhost application sidecar;
- a permissive dependency license and an actively maintained upstream.

HTTP cleartext policy is intentionally not part of engine selection. The current QQ Music dispatch can return HTTP sources, but the application must not globally weaken a target's transport security before narrow host/platform evidence exists.

## Current upstream evidence

### `audioplayers` 6.8.1

The [published package](https://pub.dev/packages/audioplayers/versions/6.8.1) declares endorsed Android, iOS, Linux, macOS, web, and Windows implementations from one top-level dependency and requires Flutter 3.44 or newer. The checkout currently uses Flutter 3.47.1.

At upstream commit [`cd475c7`](https://github.com/bluefireteam/audioplayers/tree/cd475c760b2e730c4306c1f102f3ac6f4313109e), the [feature-parity table](https://github.com/bluefireteam/audioplayers/blob/cd475c760b2e730c4306c1f102f3ac6f4313109e/feature_parity_table.md) marks local files, local assets, external URL files/streams, resume/pause/stop, release, seek, and duration/position/state/completion events as supported across all six targets. Its [lifecycle guide](https://github.com/bluefireteam/audioplayers/blob/cd475c760b2e730c4306c1f102f3ac6f4313109e/getting_started.md) distinguishes pause, stop, release, and terminal dispose. The repository and published package use the MIT license.

Linux uses an endorsed GStreamer implementation and requires the GStreamer core, app, and audio development modules. This environment reports 1.28.6 for all three. Runtime codec availability still needs an actual local MP3/WAV probe and cannot be inferred from compilation.

The package intentionally does not own a playlist. That is acceptable for the first slice: application queue semantics should be derived after one real resolved-track flow rather than imported prematurely from an engine.

### `media_kit` 1.2.6

The [published package](https://pub.dev/packages/media_kit/versions/1.2.6) supports every target and has richer playlist, device, track, header, and codec facilities. Audio apps must also add `media_kit_libs_audio`, which expands into target-specific native-library packages, and call global initialization. Those capabilities and that native stack are not required to prove one standard MP3 source. The package remains a fallback candidate if measured codec or gapless requirements exceed the selected engine.

### `just_audio` 0.10.6

The [published package](https://pub.dev/packages/just_audio/versions/0.10.6) has a strong music-oriented state model and gapless playlist API. Its own plugin declaration covers Android, iOS, macOS, and web; the [Linux and Windows instructions](https://github.com/ryanheise/just_audio/blob/454a24cac1c39442009f9e18ceccceac8e53d4a8/just_audio/README.md#linux) require additional community platform implementations and native-library packages. That is a wider dependency boundary than the current one-track requirement.

Some optional `just_audio` header/cache/byte-stream paths use a localhost proxy and can require cleartext exceptions. The M1 source does not need those features, but selecting this stack would add policy surface without present user value.

## Selection

Use exactly `audioplayers` 6.8.1 behind a project-owned Dart adapter for the M1 single-track proof.

Do not expose plugin classes through controllers or Rust. Do not add `audio_service`, platform notifications, a plugin-owned playlist, or background playback during this task. Reconsider the engine only if a reproducible target failure, codec limitation, gapless requirement, or lifecycle defect supplies new evidence.

## Validation required before UI wiring

1. Build the Linux release bundle with the endorsed plugin.
2. In a packaged Linux integration, generate a disposable local audio file, then exercise load/play, pause, resume, stop, and dispose with cleanup. **Completed:** a test-only silent MP3 passed this path on 2026-08-26 and was deleted in `finally`.
3. Put those operations behind a minimal adapter and cover late state/completion/error events after stop, source replacement, and dispose with fakes before connecting QQ media resolution.
4. Keep authenticated QQ URLs out of logs, fixtures, and test failure descriptions.
