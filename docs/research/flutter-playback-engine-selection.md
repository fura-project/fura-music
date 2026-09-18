# Flutter playback-engine selection

- **Status:** `audioplayers` selected; Linux MP3, low-M4A, and FLAC adapter decoding verified
- **Last checked:** 2026-09-07
- **Scope:** Foreground MP3 playback, evidence-selected C200 M4A fallback, and F000 SQ FLAC on Android, iOS, Linux, macOS, and Windows. This does not select downloads, video, or a second queue/player model.

> **HD-033 addendum (2026-09-18):** this document remains the historical
> production-baseline decision. A later reversible experiment now retains this
> Audioplayers default while making `media_kit` 1.2.6 independently selectable
> behind the same engine contract. Because Fura's existing MV stack already
> resolves `media_kit_libs_video` 1.0.7, the candidate required no
> `media_kit_libs_audio`; Linux playback integration and Android APK inventory
> passed with the existing native runtime. See
> [the bake-off](playback-stack-bakeoff.md). This does not approve cutover.

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

Linux uses an endorsed GStreamer implementation and requires the GStreamer core, app, and audio development modules. This environment reports 1.28.6 for all three. Runtime codec availability cannot be inferred from compilation; packaged loopback integrations now prove MP3, AAC-in-M4A, and FLAC decoding on this Linux host only.

The package intentionally does not own a playlist. That is acceptable for the first slice: application queue semantics should be derived after one real resolved-track flow rather than imported prematurely from an engine.

### `media_kit` 1.2.6 (evidence available at the original selection)

The [published package](https://pub.dev/packages/media_kit/versions/1.2.6) supports every target and has richer playlist, device, track, header, and codec facilities. A standalone audio app would normally add a MediaKit native-library package and call global initialization. At this checkpoint those capabilities were not required to prove one standard MP3 source. HD-033 later tested the candidate against Fura's already-resolved video native runtime; that newer evidence is recorded separately and does not retroactively change this baseline decision.

### `just_audio` 0.10.6

The [published package](https://pub.dev/packages/just_audio/versions/0.10.6) has a strong music-oriented state model and gapless playlist API. Its own plugin declaration covers Android, iOS, macOS, and web; the [Linux and Windows instructions](https://github.com/ryanheise/just_audio/blob/454a24cac1c39442009f9e18ceccceac8e53d4a8/just_audio/README.md#linux) require additional community platform implementations and native-library packages. That is a wider dependency boundary than the current one-track requirement.

Some optional `just_audio` header/cache/byte-stream paths use a localhost proxy and can require cleartext exceptions. The M1 source does not need those features, but selecting this stack would add policy surface without present user value.

## Selection

Use exactly `audioplayers` 6.8.1 behind a project-owned Dart adapter for the M1 single-track proof.

Do not expose plugin classes through controllers or Rust. Do not add `audio_service`, platform notifications, a plugin-owned playlist, or background playback during this task. Reconsider the engine only if a reproducible target failure, codec limitation, gapless requirement, or lifecycle defect supplies new evidence.

## Validation required before UI wiring

1. Build the Linux release bundle with the endorsed plugin.
2. In a packaged Linux integration, generate a disposable local audio file, then exercise load/play, pause, resume, stop, and dispose with cleanup. **Completed:** a test-only silent MP3 passed this path on 2026-08-26. On 2026-09-07 separate embedded synthetic C200-shaped M4A and F000-shaped FLAC fixtures passed load/play/progress/stop through the project adapter with `audio/mp4` and `audio/flac`; none of these fixtures ships in the application bundle.
3. Put those operations behind a minimal adapter and cover late state/completion/error events after stop, source replacement, and dispose with fakes before connecting QQ media resolution. **Completed:** the per-source adapter/controller and seven lifecycle/security regressions passed on 2026-08-26.
4. Keep authenticated QQ URLs out of logs, fixtures, and test failure descriptions. **Implemented boundary:** plugin logging is disabled before player construction because its upstream exception text includes the source; project failures contain no cause or URI. A loopback integration with a synthetic vkey passed, but a real authenticated source remains deliberately untested.
