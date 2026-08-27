# Repository Agent Guide

This repository uses continuous autonomous maintenance inside the product, architecture, Roadmap, and accepted Human Decision boundaries.

## Session startup

Before modifying code, read `PROJECT.md`, this file, `PROGRESS.md`, `MEMORY.md`, `TECH_DEBT.md`, `HUMAN_DECISIONS.md`, `ARCHITECTURE.md`, `ROADMAP.md`, and relevant files under `docs/decisions/`, `docs/development/`, and `docs/research/`. Then inspect `git status`, recent commits, and the relevant implementation. The working tree and local history are the first source of truth; never discard unrecognized work.

## Ordinary finite work

Normal work is:

```text
inspect → define a bounded task → implement → test → inspect the diff
→ review boundaries/debt → commit → rank current evidence
```

A task needs concrete provenance: an authorized Roadmap or maintenance criterion, user-reported/reproduced defect, failing test, documented risk, triggered debt, required target validation, or measured compatibility/accessibility/performance problem. Define its goal, scope, acceptance criteria, affected modules, tests, risk, and explicit non-goals. Nearby cleanup, aesthetics, hypothetical abstraction, or the desire to keep producing commits is not enough.

Ordinary tasks do not require separate selection, review, checkpoint, or ranking documents. Update persistent Markdown only when scheduling materially changes or the work creates durable product, architecture, evidence, risk, debt, or operational knowledge that Git and tests cannot communicate adequately.

After three materially similar failed attempts, record the blocker and evidence, stop repeating the approach, and continue independent work.

## Completion and continuation

- **Implemented:** the code path exists.
- **Verified:** named tests, integration, protocol, platform, or user evidence supports a bounded claim.
- **Product-complete:** the running user journey is discoverable, coherent, and usable; tests alone do not establish this.

Task, commit, review, checkpoint, milestone, report, and green-test completion are not project stop conditions. While `PROGRESS.md` records `global_stop: false`, rank current evidence and select the next legitimate task or bounded discovery. Do not create a numbered milestone, compatibility probe, refactor, or document merely to keep execution moving.

`NO_LEGITIMATE_WORK` is a valid current scheduling result only after a bounded whole-project audit finds no executable authorized product, correctness, reliability, test, platform, or triggered-debt work. It is not project completion or permission to invent scope.

`GLOBAL_STOP` is valid only when the Roadmap has no legitimate objective; every legitimate task is blocked by Human Decisions; work has no safe alternative to credential disclosure, account damage, data loss, or a security vulnerability; unresolved legal/platform risk makes continuation unsafe; implementation fundamentally conflicts with the product definition; or core build/test infrastructure remains globally blocked after three materially distinct evidence-backed approaches. A forced environment end is `SESSION_INTERRUPTED`, not project completion; preserve current state and next action.

## Authority and boundaries

- `PROJECT.md` and accepted Human Decisions define the product; `ARCHITECTURE.md` and accepted ADRs define ownership; `ROADMAP.md` authorizes direction; `PROGRESS.md` records current scheduling.
- Pending Human Decisions block only their recorded scope. Historical reviews record dated evidence and do not control current execution.
- Keep QQ Music first-class. Do not add Providers or product categories without product authority.
- Keep Flutter presentation concerns out of Rust and QQ Music protocol behavior out of Dart. Providers remain UI-free; the typed in-process Bridge stays coarse, cancellable, provider-neutral, and free of product business rules.
- Do not introduce a localhost/hosted sidecar, raw JSON boundary, service locator, new state/navigation framework, or speculative plugin/runtime abstraction.
- Refactor only from concrete duplication, blocked changeability/testability, a broken boundary, triggered debt, or measured performance—not file size or architectural aesthetics alone.

## Security and external evidence

- Never commit or print credentials, cookies, tokens, QIMEI values, personal responses, expiring media URLs, user content, build output, or unrelated generated artifacts.
- Do not automate stored-account access. Real-account acceptance remains maintainer operated and records only the minimum coarse result.
- Keep default tests offline. Live QQ tests are explicit, ignored by default, redacted, and bounded by the failure budget.
- Preserve exact claim boundaries: local tests do not prove live QQ, emulator/translation does not prove physical hardware, and one target does not prove another.

## Documentation responsibilities

- `PROJECT.md`: durable product definition and non-goals.
- `ARCHITECTURE.md`: current ownership, dependency direction, and invariants.
- `ROADMAP.md`: current/next meaningful direction and concise completed checkpoints.
- `PROGRESS.md`: current work, blockers, next candidates, decisions, and evidence gaps—not a changelog.
- `MEMORY.md`: short, durable operational knowledge likely to prevent repeated mistakes.
- `TECH_DEBT.md`: real debt with impact, trigger, status, and resolution condition.
- `HUMAN_DECISIONS.md`: product/release decisions that genuinely require or record human authority.
- `docs/development/` and `docs/research/`: milestone evidence and unusual durable investigation, not routine task ceremony.

## Validation

Run checks relevant to each changed layer. Before a maintenance or milestone checkpoint, run:

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
flutter test integration_test/music_video_engine_test.dart -d linux
```

Use `dart analyze` on the current local SDK because `flutter analyze` fails under this checkout's non-ASCII path; see `MEMORY.md`. The secure-storage integration uses one randomized non-account key and cleans it in `finally`.

After changing public Rust files under `bridges/flutter/src/api`, run pinned `flutter_rust_bridge_codegen` 2.13.0 from `apps/flutter`, then search for orphaned generated API files; the generator does not remove renamed modules automatically.
