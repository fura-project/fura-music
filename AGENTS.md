# Repository Agent Guide

This repository separates **work domain** from **execution mode**. The domain says what part of the system is changing; the execution mode says how the Agent proceeds. They are independent.

## Task startup

For an ordinary task, read:

1. this file;
2. the applicable domain guide;
3. the current `PROGRESS.md`;
4. the relevant implementation;
5. task-specific product, architecture, Human Decision, design, protocol, or historical evidence only when that boundary is involved;
6. recent relevant Git history.

Inspect `git status` before editing. The local working tree and local history are the first source of truth; preserve all unrecognized work. Historical checkpoint, research, debt, decision, architecture, and design documents remain available evidence, but they are not mandatory reading when unrelated to the task.

## Two independent dimensions

Classify every task as one work domain:

- **CORE:** QQ Music protocol, Provider/Domain behavior, authentication and credential semantics, media resolution, Queue rules, lyric parsing/timing, remote mutation semantics, recommendation capability, Settings business models, reusable non-visual logic, Rust platform-neutral behavior, and typed Bridge contracts. Read [`docs/agent/core-development.md`](docs/agent/core-development.md).
- **UI:** Flutter page composition, visual hierarchy, layout, adaptive behavior, Material 3 presentation, visual states, interaction, accessibility, and implementation of an approved design source. Read [`docs/agent/ui-development.md`](docs/agent/ui-development.md).
- **MIXED:** split the work into a genuine Core subtask and an approved UI subtask; each follows its domain guide. Neither side may silently redesign the other.

The current execution mode is persisted in `PROGRESS.md` and is one of:

- **AUTONOMOUS_DEVELOPMENT:** forward implementation inside an already authorized product objective. The Agent may implement, test, inspect evidence, fix failures, and select the next finite evidence-backed task. It must not invent product scope, capabilities, Providers, frameworks, or work merely to continue.
- **HUMAN_GATED_REGRESSION:** preserve the working baseline and fix only reproduced or Human-reported defects. Do not search for new product work, automatically select the next feature, redesign accepted UI, speculate on refactors, reopen working architecture, or perform unrelated cleanup.

Only the Human maintainer may switch execution mode. `进入自我迭代模式` (or equivalent unambiguous wording) selects `AUTONOMOUS_DEVELOPMENT`; `进入人工回归测试模式` selects `HUMAN_GATED_REGRESSION`. Never infer a switch from the task domain or switch back automatically.

## Authority and architecture

- `PROJECT.md` and accepted Human Decisions define the product; `ARCHITECTURE.md` and accepted ADRs define ownership; `ROADMAP.md` authorizes direction; `PROGRESS.md` records current scheduling and execution mode.
- Pending Human Decisions block only their recorded scope. Historical reviews are dated evidence, not current execution instructions.
- QQ Music remains first-class. Do not add a Provider, product category, or generic media-aggregation direction without Human product authority.
- Flutter owns presentation. Rust owns reusable protocol, Domain, and business behavior. QQ Music protocol must not leak into Dart, Flutter widget concepts must not leak into Rust, Providers remain UI-free, and the typed in-process Bridge stays coarse, cancellable, provider-neutral, and free of product business rules.
- Do not introduce a localhost or hosted sidecar, raw-JSON Bridge, service locator, new state-management or navigation framework, speculative plugin runtime, or generic framework merely to reduce file count.
- Visual authority never overrides security, truthful product semantics, or architecture ownership.

## Finite work and regression classification

Normal work is:

```text
inspect -> define bounded scope and acceptance -> implement -> test
-> inspect diff -> review boundaries/debt -> commit/report
```

Work needs concrete provenance: authorized Roadmap scope, accepted design, Human report, reproduced defect, failing test, documented risk, triggered debt, required target validation, or measured compatibility/accessibility/performance evidence. Nearby cleanup, hypothetical abstraction, and the desire to keep producing commits are not provenance. After three materially similar failed attempts, record the blocker and stop repeating that approach.

In `HUMAN_GATED_REGRESSION`, classify findings only as:

- **M — Machine-verifiable:** crash, parser incompatibility, incorrect state, broken Back/Queue behavior, overflow, unreachable control, failing test, protocol incompatibility, or another reproducible condition. The Agent may reproduce, fix, and run targeted verification within the exact regression scope.
- **H — Human-judgment:** spacing, density, typography, visual strength, composition, or other quality without a reliable machine oracle. Render actual evidence, batch small findings where practical, and stop for Human review. Apply only exact Human-requested corrections before rendering again; do not self-approve aesthetics.
- **D — Human decision:** new product category, capability, recommendation semantic, scope, or other authority boundary. Stop only the affected scope and report the exact decision required.

Completing a bounded regression batch, producing canonical renders, waiting for Human visual judgment, or reaching a D finding is a valid stop in `HUMAN_GATED_REGRESSION`. Autonomous continuation applies only in `AUTONOMOUS_DEVELOPMENT`; even there, UI visual acceptance remains Human-gated. Do not create another task, milestone, probe, refactor, or document merely to avoid stopping.

## Security, evidence, Git, and validation

- Never commit or print credentials, cookies, tokens, musickey, QIMEI values, personal responses or account content, expiring media URLs, secret-bearing responses, build output, or unrelated generated artifacts.
- Do not automate stored-account access or mutate the maintainer's real account. Real-account acceptance is maintainer-operated and records only the minimum coarse result. Default tests remain offline; live tests are explicit, redacted, bounded, and failure-budget limited.
- Preserve claim boundaries: local tests do not prove live QQ behavior, emulator or translation does not prove physical hardware, and one target does not prove another.
- Do not reset, clean, rebase, force-push, or discard unrecognized work. Keep commits logically complete; inspect `git status`, `git diff`, and `git diff --check` before committing.
- Update persistent Markdown only for durable product, architecture, evidence, risk, debt, decision, design-source, or scheduling information. Historical evidence is not rewritten merely because current scheduling changed.
- Run checks relevant to changed layers and state what they prove. Use `dart analyze` on the current local SDK because `flutter analyze` fails under this checkout's non-ASCII path; see `MEMORY.md` when Flutter validation is relevant.
- After changing public Rust files under `bridges/flutter/src/api`, run pinned `flutter_rust_bridge_codegen` 2.13.0 from `apps/flutter`, then check for orphaned generated API files.

## Required final-report footer

Every final task report, including a report with no code changes, must end with exactly these three fields. They report the persisted mode and current gate; they never authorize a mode switch.

```text
Execution mode: <AUTONOMOUS_DEVELOPMENT | HUMAN_GATED_REGRESSION>
Work domain: <CORE | UI | MIXED>
Gate: <CONTINUE | HUMAN_REVIEW | HUMAN_DECISION | COMPLETE | BLOCKED>
```
