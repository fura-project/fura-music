# Linux startup and playback dependency ownership — 2026-10-07

## Scope and baseline

Human-directed Core task: ordinary Linux Debug startup, Settings backend
construction robustness, then playback dependency ownership. Starting HEAD and
tracked `origin/main`: `bd1a6d73db7fce874bf78c7191a2d79b448b3980`; worktree clean.
No playback/focus/Queue, Provider, authentication, UI, dependency-version or
toolchain change is authorized by this audit.

Local toolchain: Flutter 3.47.1, framework `6655482ec0`, engine revision
`5d53178869`, Dart 3.13.1; Linux x64 with an existing desktop display. Runtime
checks use disposable XDG config/data/cache directories and a private D-Bus
session, not maintainer settings or stored accounts.

## A. Dart registration failure

### Generated registration is present

The resolved packages remain `shared_preferences` 2.5.5 and
`shared_preferences_linux` 2.4.1. The latter is an endorsed Dart-only Linux
implementation: `.flutter-plugins-dependencies` records `native_build: false`
and `path_provider_linux` as its dependency. The generated Dart registrant
imports it and calls `SharedPreferencesLinux.registerWith()`, which calls
`SharedPreferencesAsyncLinux.registerWith()` and sets the Async platform
instance. Its absence from the C++ registrant is correct.

The checked local SDK sources explain the normal root-isolate path:

- `packages/flutter_tools/lib/src/compile.dart` adds the generated registrant
  as `--source` and injects `flutter.dart_plugin_registrant` using its package
  URI when mapped, otherwise its file URI.
- `packages/flutter/lib/src/dart_plugin_registrant.dart` holds the injected
  environment value.
- `engine/src/flutter/runtime/dart_plugin_registrant.cc` looks up that library
  and invokes `_PluginRegistrant.register()` before the main entrypoint in
  `dart_isolate.cc`.
- `packages/flutter_tools/lib/src/bundle.dart` keys the resident kernel by
  caller dart-defines/frontend options, **not this generated URI mapping**.
  Desktop kernel compilation also initializes from a previous build-system
  dill (`build_system/targets/common.dart`).

No SDK, runner or generated registrant was patched. No root-isolate
`DartPluginRegistrant.ensureInitialized()` was added.

### Controlled before/after evidence

The existing privacy helper persistently added a synthetic package mapping to
ordinary `.dart_tool/package_config.json`, changing the generated registrant
from `file:` to `package:fura_generated_plugin_registry/...`. Ordinary and
private Debug compilation could consequently reuse a kernel under different
registration URI assumptions. This is a build-lifecycle/cache ownership
defect, not a missing C++ SharedPreferences plugin.

| Controlled run | Result |
| --- | --- |
| Ordinary config, ordinary cached Debug startup | First frame reached |
| Existing helper mapping added, same ordinary incremental namespace, `flutter run --debug --no-pub` | Exact `SharedPreferencesAsyncPlatform instance must be set` exception before Rust init |
| Same mapped config and generated files, independent caller-define namespace | Registration works; Rust/audio/MPRIS/first frame reached |
| Fixed private Debug wrapper and resulting bundle | First frame reached; private mapping absent from ordinary config afterward |
| Subsequent ordinary `flutter run -d linux --debug` (verbose logging only) | Rust init, audio engine, system edge, `run_app`, first frame succeed; no Settings-unavailable fallback |
| After native Settings/audio/MV integrations and private Release, exact ordinary `flutter run -d linux --debug` without extra compile options | All required phases and first frame succeed; no registration/unavailable error; exited normally through Flutter `q` |

VM library inventory confirms the generated library changes between file and
package URIs in these trials. The debugger's lazy constant-field inspection
does not expose the value of the registrant define; it is not claimed as an
independent measurement of that value. The failing transition and successful
separate-namespace control, together with the actual SDK cache/registration
code, establish the actionable failure mechanism without guessing a package
version incompatibility.

The wrapper now scopes the private package mapping to compilation and restores
the pub config on success/failure, also removing its own stale mapping from
older runs. `FURA_PATH_PRIVATE_REGISTRANT=1` isolates private incremental
kernels using Flutter's supported dart-define cache key. It is compile-only;
it does not alter `FURA_AUDIO_ENGINE`, `FURA_SYSTEM_MEDIA` or default D policy.
The helper is not a persistent development setup command. This does not wipe
caches or settings, change SDK versions, or hex-patch compiled artifacts.

### Independent Settings robustness defect

Before the fix, `AppSettingsStore()` eagerly constructed
`SharedPreferencesAsync`, so its exact missing-registration StateError escaped
before `load()` could return `storageUnavailable`. A new unit regression
reproduced that exception before production changes.

The store now owns one lazy factory/backend. The default factory translates
only the pinned package's known missing-registration construction error to a
typed initialization-unavailable result; other construction errors propagate.
The narrow catch is outside the existing storage-I/O catches. Known failure
uses defaults, returns `storageUnavailable` for save/reset, and emits one
source-free `settings_storage ... plugin_unregistered` diagnostic. It never
pretends to persist settings or installs another store. Schema, document key,
migration, read/write failure contract and serialized mutations are unchanged.

Factory tests prove lazy/single construction, stable unavailable outcomes,
propagation of unrelated StateError/ArgumentError, and mutation-tail recovery
after a programmer error. The actual missing-plugin constructor regression
also passes; registration failure remains visible rather than hidden.

The existing `integration_test/settings_storage_test.dart` now has opt-in
disposable `seed`, `verify`, `reset` phases. Separate Linux processes saved a
safe dark-theme synthetic document, loaded it after restart, reset it and
confirmed defaults/deletion. The existing random-key round-trip also passes
in each process. All keys are under the integration-test prefix; no real
settings document or credentials are accessed. Linux runtime environment
overrides allow the same test binary to serve each phase; Android may instead
use the equivalent dart-defines.

## B. Playback ownership audit

`PRODUCTION_DEFAULT` below denotes the current requested **test default**, not
Human acceptance of an irreversible migration. No defines requests D. Effective
Android/Windows/macOS is D; Linux is MediaKit + Fura MPRIS; iOS is MediaKit +
AudioService. Invalid defines still select the complete A rollback pair.

Evidence: actual imports, `PlaybackStackSelection`, `main`,
`initializeAppPlaybackHost`, locked package manifests/source,
`flutter pub deps`, generated Dart/native registrants, and applicable tests.

| Direct dependency (locked version) | Classification | Exact owner / reason to keep | Retirement gate |
| --- | --- | --- | --- |
| `audio_service` 0.18.19 | ROLLBACK / PLATFORM_FALLBACK / DIRECT_PROJECT_API | `AudioServiceSystemMediaEdge`, `ProjectSystemAudioHandler`; A/B rollback, iOS fallback, and the **current Linux default MPRIS handler path** | Human retirement decision plus replacement of each actual owner and affected target evidence |
| `audio_service_platform_interface` 0.1.3 | DIRECT_PROJECT_API | `ProjectLinuxMprisAudioService extends AudioServicePlatform`; direct import even though also transitive | Proven independent MPRIS edge migration plus runtime/contract proof; not implemented here |
| `audio_service_win` 0.0.3 | ROLLBACK | Explicit Windows implementation supplies generated Dart `AudioServicePlatform` and C++ registration for A/B | Human-approved rollback retirement/replacement **and native Windows build/runtime** |
| `audio_session` 0.2.4 | DIRECT_PROJECT_API / PRODUCTION_DEFAULT | Music focus, configuration, interruption and becoming-noisy ownership for both engines; not a duplicate system-media edge | Equivalent accepted focus owner on all supported paths |
| `audioplayers` 6.8.1 | ROLLBACK | Explicit A/C engines, `AudioplayersForegroundAudioEngine`, shared contract and native rollback tests | Human HD-033 engine retirement plus affected platform verification |
| `flutter_media_session` 3.0.5 | PRODUCTION_DEFAULT / DIRECT_PROJECT_API | `FuraMediaSessionAdapter` on Android/Windows/macOS; command delegation to the same Queue; no Linux plugin; iOS rejected before activation | Accepted system-edge replacement, not default selection alone |
| `media_kit` 1.2.6 | PRODUCTION_DEFAULT / MUSIC_VIDEO / DIRECT_PROJECT_API | Engine-lifetime music Player plus independent disposable MV Player; global initialization | Accepted replacements for both owners |
| `media_kit_video` 2.0.1 | MUSIC_VIDEO / DIRECT_PROJECT_API | `VideoController` and `Video` in `track_music_video_engine.dart`; generated native texture plugins | Human MV retirement/replacement and target decode/render proof |
| `media_kit_libs_video` 1.0.7 | MUSIC_VIDEO / PRODUCTION_DEFAULT | Native runtime umbrella supplies the existing MediaKit music and video payloads; no Dart import is expected | Equivalent verified music **and video** payloads on every affected target |
| `dbus` 0.7.15 | DIRECT_PROJECT_API | Project-owned Linux MPRIS; also transitive through other packages, which does not replace direct ownership | Accepted MPRIS replacement and Linux session-bus proof |

All ten dependencies: **KEEP**. None satisfies the dead-dependency removal
criteria. No versions, dependency entries or lockfile were changed; pubspec
changes are comments only. Do not add `media_kit_libs_audio` beside the existing
video runtime merely because music also uses MediaKit.

### Important transitive platform edges

| Locked packages | Classification / owner |
| --- | --- |
| `audioplayers_android` 5.3.0, `audioplayers_darwin` 6.5.0, `audioplayers_linux` 4.3.0, `audioplayers_windows` 4.4.1, `audioplayers_web` 5.3.0 | TRANSITIVE_ONLY / ROLLBACK: endorsed native/web implementations of retained audioplayers |
| `audioplayers_platform_interface` 7.2.0 | TRANSITIVE_ONLY: backend contract; not an independent app dependency to retire |
| `audio_service_web` 0.1.4 | TRANSITIVE_ONLY: retained AudioService graph; not a direct dead dependency |
| `media_kit_libs_android_video` 1.3.8, `media_kit_libs_ios_video` 1.1.4, `media_kit_libs_macos_video` 1.1.4, `media_kit_libs_windows_video` 1.0.11, `media_kit_libs_linux` 1.2.1 | TRANSITIVE_ONLY / PRODUCTION_DEFAULT / MUSIC_VIDEO: native payload selected by the video umbrella |
| `wakelock_plus` 1.7.0, `wakelock_plus_platform_interface` 1.6.0, `package_info_plus` 10.2.1 / interface 4.1.0 | TRANSITIVE_ONLY: MediaKit video controller/wakelock platform support; Linux includes Dart-only registrations |
| `path_provider` 2.1.6 with Android 2.3.1, foundation 2.6.0, Linux 2.2.2, Windows 2.3.0 | TRANSITIVE_ONLY: retained playback/storage/cache clients and SharedPreferences Linux support |
| `jni` 1.0.3, `jni_flutter` 1.0.2, `objective_c` 9.5.0 | TRANSITIVE_ONLY: current path-provider platform graph/native assets, not unused direct playback pins |

AudioService 0.18.19's published manifest has Android/Darwin native plugins and
a web default package, **no Windows endorsement/dependency**. The Windows
rollback therefore needs its direct `audio_service_win` pin. That package's
Dart registrant sets `AudioServicePlatform.instance`; native registration only
installs the method channel. SMTC creation happens on `configure` /
`initializeSMTC`, not registration. Default-D activation does not call
`AudioService.init`, as the existing single-edge tests verify. Retaining both
registrants is not proof of two live sessions (nor a new Windows runtime pass).

After pub resolution, dependency graph, normalized plugin metadata and
generated Dart registrant match the initial snapshot. Tracked native
registrants and lockfile have no diff. Stale pubspec default comments,
normative platform-plan rows and TD-008's unqualified Windows-default claim
are corrected. Dated historical checkpoints/failures are retained. The
audio_service-independent MPRIS architecture is a future gate, not a migration
made in this audit.

## Validation and boundaries

Before-fix failures are preserved separately from passing trials. External
runtime logs live under a disposable `fura-linux-startup-20261007-*` evidence
directory; build products are ignored, not added to Git.

Completed validation:

- Missing-plugin Settings constructor regression: FAIL before / PASS after.
- Private-URI/shared-kernel startup reproduction: FAIL before; separate-key
  control, fixed private Debug bundle and ordinary Debug startup: PASS.
- Existing Settings integration: native round-trip plus independent
  seed/restart-read/reset processes: PASS.
- Affected Settings/controller/layout, stack selector, single-edge/iOS safety,
  MPRIS, both engine contracts, MediaKit failure paths and MV unit suites: PASS.
- Whole-app `dart analyze`: PASS; privacy helper deterministic tests and source
  privacy audit: PASS.
- Native Linux `system_playback_service_test`: PASS (default request D,
  MediaKit engine, real Fura MPRIS registration/properties/commands/disposal).
- Native Linux `music_video_engine_test`: PASS (local MP4 decode, position,
  pause, seek, resume and texture output).
- Native Linux `playback_engine_test`: PASS (Audioplayers MP3/M4A/FLAC,
  MediaKit source replacement/one-Player ownership and retained EOF replay).
- Privacy wrapper Linux Debug and Release builds: PASS; Release payload scan
  against the active workspace/HOME roots: PASS. Release app reaches first
  frame with the expected MediaKit/Fura MPRIS policy. Direct bundle observations
  are bounded to 20 seconds and then intentionally terminated by the harness;
  its exit 124 is not reported as an application crash or clean shutdown proof.
- Dependency graph, plugin metadata and Dart registrant: unchanged after pub
  resolution; native registrants and lockfile: no diff.

Windows, macOS, iOS and Android native builds/runtime are not performed in this
Linux-scoped audit. Their existing rollback/fallback decisions are unchanged;
in particular no Windows dependency retirement is claimed.

The ordinary Debug and private build startup failures are
`FIXED_AND_VERIFIED` for the exercised Linux lifecycle. SharedPreferences
registration/source-path privacy were both checked, not traded off. Desktop
Atk/cursor warnings also occur in first-frame-passing trials and are not the
reported Dart constructor failure. New remote CI has not run: no commit,
push or workflow dispatch was performed. Cross-platform native validation of
the common wrapper remains an external CI/host evidence boundary; mock command
tests across all supported targets do not replace those builds. Human retains
review of this candidate and the independent HD-033 platform runtime/rollback
retirement decisions.
