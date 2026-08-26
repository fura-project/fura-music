# flutterustmusic

`flutterustmusic` is a modern, open-source, cross-platform, QQ Music-first client built with Flutter and an in-process Rust core.

The first in-process vertical slice implements sign-in, credential restore, user playlists and details, foreground playback and queue controls, and synchronized word-level lyrics. M3 now also includes direct QQ Music Track, Artist, Album, and Playlist search, Album and Artist browsing, canonical Album metadata with credited-Artist navigation, Artist discography navigation, public recommended-playlist discovery, grouped current QQ Music rankings, authenticated Radar Track recommendations, regional new-Album releases, typed new-song channels, authenticated favorite Albums, playlist Track-to-Album/Artist navigation, and current-Track Album/Artist navigation from the shared now-playing surface. One user-operated real-account playback/queue/lyric observation remains before the M1 end-to-end acceptance claim; it does not block the active M3 QQ Music core-product workstream.

## Status

The project has a working M1 implementation with offline regression coverage and bounded Linux/Android runtime evidence. M2 reliability and daily-use quality is checkpointed; bounded M3 Track/Artist/Album/Playlist Search, Album Tracks/details/credited-Artist routing, Artist Tracks/Albums, recommended-playlist, current-ranking, authenticated Radar/favorite-Album, regional new-Album, typed new-song, playlist Track-to-Album/Artist, and global current-Track catalog-navigation slices are implemented. This is not a release-readiness, recommendation-quality, or live catalog claim, and real QQ Music playback remains subject to the user-operated observation above. Product boundaries and architectural decisions are recorded in [PROJECT.md](PROJECT.md), [ARCHITECTURE.md](ARCHITECTURE.md), and [ROADMAP.md](ROADMAP.md). Current execution state lives in [PROGRESS.md](PROGRESS.md).

No release is available yet.

## Repository layout

The layout is created progressively. Only modules with a current responsibility should exist.

- `apps/flutter/` — Flutter presentation and short-lived UI state
- `crates/` — reusable Rust domain and provider implementation
- `bridges/flutter/` — the thin typed Flutter/Rust boundary
- `docs/decisions/` — accepted architecture decision records

## Development

The currently verified local toolchain is Flutter 3.47.1 / Dart 3.13.1 and Rust 1.97.1. From the repository root:

```bash
cargo test --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
```

For Flutter checks and the real Linux bridge path:

```bash
cd apps/flutter
dart analyze
flutter test
flutter build linux
flutter test integration_test/simple_test.dart -d linux
flutter test integration_test/secure_storage_test.dart -d linux
flutter test integration_test/playback_engine_test.dart -d linux
```

The Linux build also needs the native `libsecret-1` development package for platform secure storage. Package names vary by distribution (`libsecret` on Arch-based systems and `libsecret-1-dev` on Debian-based systems).

Playback uses the endorsed Linux `audioplayers` implementation and therefore also needs GStreamer 1.0 core, app, and audio development modules plus runtime plugins for the formats being played. The local M1 integration currently proves MP3 decode on the recorded development environment; installing headers alone does not prove runtime codec availability on another distribution.
The secure-storage integration uses a randomized, non-account test key, never calls `deleteAll`, and verifies cleanup in `finally`; it intentionally performs a live write/read/delete cycle in the current user's platform keyring.

On a Linux host that uses distribution `rustc`/`cargo` instead of rustup, Android builds require the matching `rust-src` package and an explicit target. The validated targets are `android-arm64` for a release APK and `android-x64` for the current emulator:

```bash
flutter build apk --release --target-platform android-arm64
flutter test integration_test/simple_test.dart -d <android-device>
flutter test integration_test/secure_storage_test.dart -d <android-device>
flutter test integration_test/playback_engine_test.dart -d <android-device>
```

The current Flutter 3.47.1 wrapper resolves an ASCII SDK symlink back to its non-ASCII physical path, so invoking `/home/axiaobo/flutter-sdk/bin/flutter` is not sufficient on this recorded host. Use the logical root with the cached Dart VM and `flutter_tools.snapshot` directly:

```bash
flutter_logical_root=/home/axiaobo/flutter-sdk
env FLUTTER_ROOT="$flutter_logical_root" \
  "$flutter_logical_root/bin/cache/dart-sdk/bin/dart" \
  "$flutter_logical_root/bin/cache/flutter_tools.snapshot" \
  build apk --debug --target-platform android-x64
```

Replace the final build arguments with `build apk --release --target-platform android-arm64` for the validated ARM64 release package. This is a local invocation workaround, not a repository or Flutter SDK patch.

The application keeps Gradle's ABI filter aligned with Flutter's explicit `target-platform`; otherwise transitive JNI libraries can make a single-target APK advertise ABIs that do not contain Flutter or Rust. The system-Cargo ARM64 path also links the NDK compiler runtime and rejects unresolved `__aarch64_*` symbols before packaging. Do not disable either guard when reproducing these builds.

The playback integration runs the local-file lifecycle on Android; its loopback-HTTP case remains Linux-only so tests do not weaken Android cleartext policy. The recorded non-ASCII Flutter SDK path needs the local logical-root invocation documented in `MEMORY.md`; that environment issue is not patched into the repository or SDK.

`dart analyze` is deliberate for the current local non-ASCII checkout-path issue recorded in `MEMORY.md`.

When the public Rust bridge API changes, install and run the pinned generator:

```bash
cargo install --locked flutter_rust_bridge_codegen --version 2.13.0
cd apps/flutter
flutter_rust_bridge_codegen generate
```

Generated Dart bridge files are committed so application builds do not require the generator. See [AGENTS.md](AGENTS.md) for the repository workflow and validation boundaries.

## License

MIT. See [LICENSE](LICENSE).
