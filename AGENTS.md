# Repository Agent Guide

This repository uses continuous autonomous maintenance within the boundaries in `PROJECT.md`, `ARCHITECTURE.md`, `ROADMAP.md`, and accepted decisions.

## Session startup

Before modifying code, read:

1. `PROJECT.md`
2. `AGENTS.md`
3. `PROGRESS.md`
4. `MEMORY.md`
5. `TECH_DEBT.md`
6. `HUMAN_DECISIONS.md`
7. `ARCHITECTURE.md`
8. `ROADMAP.md`

Then inspect `git status`, recent commits, and the relevant implementation. Do not ask a human to repeat repository state already recorded here.

## Task loop

For each finite task, define its goal, scope, acceptance criteria, expected modules, tests, and risks. Implement only the smallest coherent unit, test it, inspect the diff, review architecture/scope/debt, update persistent state, and commit the logical unit. Then select the next highest-value unblocked roadmap task.

After three materially similar failed attempts, stop repeating the approach. Record a blocker and the attempted evidence, then continue independent work.

## Priority

Current milestone user value comes first, followed by blockers, bugs, correctness, reliability, necessary test gaps, triggered debt, stale documentation, and measured performance. Refactoring without one of those drivers is not a task.

## Required boundaries

- Keep QQ Music first-class and do not add providers or product categories without roadmap authority.
- Keep Flutter presentation concerns out of Rust and QQ Music protocol behavior out of Dart.
- Keep providers UI-free and return project domain models.
- Keep live QQ Music tests separate from the offline default suite.
- Do not commit secrets, credentials, cookies, raw personal responses, build output, or unrelated generated artifacts.
- Do not describe skeletons, placeholders, or infrastructure as completed user-facing features.

## Validation

Run the checks relevant to each changed layer:

```bash
cargo fmt --all -- --check
cargo test --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings

cd apps/flutter
dart format --output=none --set-exit-if-changed lib test integration_test
dart analyze
flutter test
flutter build linux
flutter test integration_test/simple_test.dart -d linux
flutter test integration_test/secure_storage_test.dart -d linux
flutter test integration_test/playback_engine_test.dart -d linux
```

On the current local SDK, use `dart analyze` because the `flutter analyze` LSP process fails under this checkout's non-ASCII path; see `MEMORY.md`. Report exactly what each test proves: local unit tests do not prove live QQ Music behavior or every platform build, while the Linux integration test does prove the packaged in-process bridge call on this host.

After changing public Rust files under `bridges/flutter/src/api`, run the pinned `flutter_rust_bridge_codegen` 2.13.0 generator from `apps/flutter`, then search for orphaned generated API files. The generator does not remove files for renamed modules automatically.
