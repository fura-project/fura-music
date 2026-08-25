# flutterustmusic

`flutterustmusic` is a modern, open-source, cross-platform, QQ Music-first client built with Flutter and an in-process Rust core.

The repository is at the beginning of its first vertical slice: sign in, restore credentials, browse the user's playlists, open a playlist, play tracks, manage the queue, and follow word-level lyrics.

## Status

The project is in active bootstrap. Product boundaries and architectural decisions are recorded in [PROJECT.md](PROJECT.md), [ARCHITECTURE.md](ARCHITECTURE.md), and [ROADMAP.md](ROADMAP.md). Current execution state lives in [PROGRESS.md](PROGRESS.md).

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
```

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
