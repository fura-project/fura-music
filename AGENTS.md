# Repository Agent Guide

This repository uses continuous autonomous maintenance inside the accepted product, architecture, Roadmap, and Human Decision boundaries. Core and UI work use different authority models; this file contains the shared rules and routes each task to its mode-specific guide.

## Session startup

Before modifying the repository, read `PROJECT.md`, this file, `PROGRESS.md`, `MEMORY.md`, `TECH_DEBT.md`, `HUMAN_DECISIONS.md`, `ARCHITECTURE.md`, `ROADMAP.md`, and relevant files under `docs/decisions/`, `docs/development/`, `docs/research/`, and `docs/design/`. Then inspect `git status`, recent commits, and the relevant implementation. The working tree and local history are the first source of truth; never discard unrecognized work.

## Select a work mode

Before implementation:

1. classify the task as **Core**, **UI**, or **Mixed**;
2. read the corresponding mode guide;
3. apply this file's shared constraints;
4. execute with that mode's authority model.

- **Core / Backend:** QQ Music protocol, Provider and Domain behavior, authentication and credential semantics, media resolution, Queue rules, lyric parsing/timing, remote mutation semantics, recommendation capability, Settings persistence/business models, reusable non-visual logic, Rust platform-neutral behavior, and typed Bridge contracts. Read [`docs/agent/core-development.md`](docs/agent/core-development.md).
- **UI / Product:** Flutter page composition, visual hierarchy, layout, adaptive behavior, Material 3 presentation, spacing, typography, surfaces, visual states, desktop/mobile translation, and implementation of an approved design source. Read [`docs/agent/ui-development.md`](docs/agent/ui-development.md).
- **Mixed:** split the task explicitly. Complete and verify a genuine Core subtask under Core rules, then return to the approved UI task under UI rules. A UI task may not silently redesign Core, and a Core task may not silently redesign the product UI.

## Shared authority and boundaries

- `PROJECT.md` and accepted Human Decisions define the product; `ARCHITECTURE.md` and accepted ADRs define ownership; `ROADMAP.md` authorizes direction; `PROGRESS.md` records current scheduling.
- Pending Human Decisions block only their recorded scope. Historical reviews are dated evidence, not current execution instructions.
- QQ Music remains first-class. Do not add a Provider, product category, or generic media-aggregation direction without Human product authority.
- Flutter owns presentation. Rust owns reusable protocol, Domain, and business behavior. QQ Music protocol must not leak into Dart, Flutter widget concepts must not leak into Rust, Providers remain UI-free, and the typed in-process Bridge stays coarse, cancellable, provider-neutral, and free of product business rules.
- Do not introduce a localhost or hosted sidecar, raw-JSON Bridge, service locator, new state-management or navigation framework, speculative plugin runtime, or generic framework merely to reduce file count.
- Preserve accepted Human Decisions. Resolve apparent rule conflicts using the authority and work-mode rules above; visual authority never overrides security, truthful product semantics, or architecture ownership.

## Ordinary finite work

Normal work is:

```text
inspect -> define a bounded task -> implement -> test -> inspect the diff
-> review boundaries/debt -> commit -> rank current evidence
```

A task needs concrete provenance: authorized Roadmap scope, an accepted design source, a user-reported or reproduced defect, a failing test, documented risk, triggered debt, required target validation, or measured compatibility/accessibility/performance evidence. Define the goal, scope, acceptance criteria, affected modules, tests, risk, and explicit non-goals. Nearby cleanup, hypothetical abstraction, or the desire to keep producing commits is not enough.

Ordinary tasks do not require separate selection, review, checkpoint, or ranking documents. Update persistent Markdown only for durable product, architecture, design-source, evidence, risk, debt, decision, or scheduling information that Git and tests cannot communicate adequately.

After three materially similar failed attempts, record the blocker and evidence, stop repeating the approach, and continue independent work.

## Completion and continuation

- **Implemented:** the code path exists.
- **Verified:** named automated, protocol, integration, platform, or user evidence supports a bounded claim.
- **Product-complete:** the running user journey is discoverable, coherent, and usable. For visual work, use the stricter UI acceptance model.

Task, commit, review, checkpoint, milestone, report, and green-test completion are not project stop conditions. While `PROGRESS.md` records `global_stop: false`, rank current evidence and select the next legitimate task or bounded discovery within the active authority. Do not create a milestone, probe, refactor, or document merely to keep execution moving.

`NO_LEGITIMATE_WORK` is valid only after a bounded whole-project audit finds no executable authorized product, correctness, reliability, test, platform, or triggered-debt work. It is not project completion or permission to invent scope.

`GLOBAL_STOP` is valid only when the Roadmap has no legitimate objective; every legitimate task is blocked by Human Decisions; work has no safe alternative to credential disclosure, account damage, data loss, or a security vulnerability; unresolved legal/platform risk makes continuation unsafe; implementation fundamentally conflicts with the product definition; or core build/test infrastructure remains globally blocked after three materially distinct evidence-backed approaches. A forced environment end is `SESSION_INTERRUPTED`, not project completion; preserve current state and next action.

## Security and external evidence

- Never commit or print credentials, cookies, tokens, musickey, QIMEI values, personal responses or account content, expiring media URLs, secret-bearing responses, build output, or unrelated generated artifacts.
- Do not automate stored-account access. Real-account acceptance remains maintainer operated and records only the minimum coarse result.
- Keep default tests offline. Live QQ tests are explicit, ignored by default, redacted, bounded, and failure-budget limited. Do not autonomously mutate the maintainer's real account.
- Preserve claim boundaries: local tests do not prove live QQ behavior, emulator or translation does not prove physical hardware, and one target does not prove another.

## Git and documentation discipline

- Preserve unrecognized work. Do not reset, clean, rebase, force-push, or discard user changes.
- Keep commits small and logically complete. Before committing, inspect `git status`, `git diff`, and `git diff --check`; exclude secrets, build outputs, and unrelated changes.
- `PROJECT.md` records durable product definition; `ARCHITECTURE.md` current ownership and invariants; `ROADMAP.md` meaningful direction and checkpoints; `PROGRESS.md` live scheduling and evidence gaps; `MEMORY.md` short operational knowledge; `TECH_DEBT.md` real debt and triggers; `HUMAN_DECISIONS.md` genuine Human authority; `docs/design/` durable design-source identities and constraints.
- `docs/development/` and `docs/research/` hold milestone evidence and unusual durable investigation, not routine task ceremony.

## General validation

Run checks relevant to every changed layer and state exactly what they prove. Use `dart analyze` on the current local SDK because `flutter analyze` fails under this checkout's non-ASCII path; see `MEMORY.md`. A repository maintenance or milestone checkpoint runs the full applicable command sets in both mode guides. The secure-storage and Settings integrations each use one independent randomized non-account key and clean it in `finally`.

After changing public Rust files under `bridges/flutter/src/api`, run pinned `flutter_rust_bridge_codegen` 2.13.0 from `apps/flutter`, then search for orphaned generated API files; the generator does not remove renamed modules automatically.
