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

For each finite task, define its goal, provenance, scope, acceptance criteria, expected modules, required tests, known risks, and explicit non-goals. Implement only the smallest coherent unit, test it, inspect the diff, review architecture/scope/debt, update persistent state, and commit the logical unit. Then select the next highest-value unblocked roadmap task.

After three materially similar failed attempts, stop repeating the approach. Record a blocker and the attempted evidence, then continue independent work.

## Continuous execution state machine

The repository remains in continuous autonomous execution while `PROGRESS.md` records `global_stop: false`.

```text
task_complete != stop
commit_complete != stop
review_complete != stop
checkpoint != stop
milestone_complete != stop
report_generated != stop
tests_green != stop

global_stop == false
    => SELECT_NEXT_TASK
```

Every finite task must exit through `TEST -> SELF_REVIEW -> UPDATE_STATE_IF_NEEDED -> CHECK_GLOBAL_STOP -> SELECT_NEXT_TASK`. `TASK_COMPLETE -> SUMMARY -> EXIT` is not a project lifecycle. Only `GLOBAL_STOP` can end autonomous project execution.

`GLOBAL_STOP` is valid only when the Roadmap contains no legitimate next objective; every remaining legitimate task is blocked by pending Human Decisions; continued work has no safe alternative to credential disclosure, account damage, data loss, or a security vulnerability; unresolved legal or platform risk makes work unsafe; the implemented architecture fundamentally conflicts with the product definition; or core build/test infrastructure remains globally blocked after three materially distinct, evidence-backed approaches. A forced session end is `SESSION_INTERRUPTED`, not project completion: preserve the active task, evidence, remaining work, and `next_action` while leaving project execution active for the next session.

`NO_LEGITIMATE_WORK` is also distinct from `GLOBAL_STOP`. Before recording it, recheck the Roadmap, live risks and blockers, user-reported or reproduced bugs, necessary test and platform evidence, triggered debt, demonstrated adaptive/accessibility failures, stale misleading documentation, and measured performance issues. Do not invent work merely to keep producing commits.

## Task provenance and global ranking

A task needs concrete provenance: a Roadmap acceptance criterion, user-reported or reproduced problem, failing test, documented risk, triggered debt, required platform validation, reproducible accessibility/adaptive failure, or measured compatibility/performance problem. A nearby cleanup, speculative edge case, aesthetic preference, or hypothetical abstraction is not sufficient.

After each task, rank candidates across the whole project instead of continuing with the nearest file. After roughly three presentation-only focus, semantics, live-region, minor adaptive-layout, or affordance tasks, explicitly rerank playback reliability, Provider correctness, platform evidence, risks, blockers, and triggered debt before selecting another presentation task.

Pending Human Decisions block only their explicitly recorded scope. Historical reviews under `docs/development/` preserve dated evidence and do not override current autonomous execution. Product authority comes from `PROJECT.md` and accepted Human Decisions; architecture authority from `ARCHITECTURE.md` and accepted ADRs; execution semantics from this file; authorized direction from `ROADMAP.md`; and live scheduling state from `PROGRESS.md`.

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
