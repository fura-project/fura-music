# Repository Agent Guide

This repository separates **execution mode**, **work domain** and **acceptance gate**. Execution mode answers only who chooses the next unit of work: Human or Agent. Work domain identifies the changing layer; acceptance gate identifies what prevents acceptance. The latest Human authorization defines the task or direction, its scope and acceptance boundary. Execution mode never sets execution intensity or authorizes unrelated work.

## Task startup

For an ordinary task, read:

1. this file;
2. the applicable domain guide;
3. the current `PROGRESS.md`;
4. the relevant implementation;
5. task-specific product, architecture, Human Decision, design, protocol, or historical evidence only when that boundary is involved;
6. recent relevant Git history.

Inspect `git status` before editing. The local working tree and local history are the first source of truth; preserve all unrecognized work. Historical checkpoint, research, debt, decision, architecture, and design documents remain available evidence, but they are not mandatory reading when unrelated to the task.

## Work domain

Classify every task as one work domain:

- **CORE:** QQ Music protocol, Provider/Domain behavior, authentication and credential semantics, media resolution, Queue rules, lyric parsing/timing, remote mutation semantics, recommendation capability, Settings business models, reusable non-visual logic, Rust platform-neutral behavior, and typed Bridge contracts. Read [`docs/agent/core-development.md`](docs/agent/core-development.md).
- **UI:** Flutter page composition, visual hierarchy, layout, adaptive behavior, Material 3 presentation, visual states, interaction, accessibility, and implementation of an approved design source. Read [`docs/agent/ui-development.md`](docs/agent/ui-development.md).
- **MIXED:** split the work into a genuine Core subtask and an approved UI subtask; each follows its domain guide. Neither side may silently redesign the other.

For a new or materially changed UI interaction component, follow the `agy` component preflight and rendered-review workflow in the UI guide. It supplements machine verification and never replaces Human visual authority or Core correctness evidence.

## Execution modes and task authority

The only current execution modes are `HUMAN_DIRECTED` and `AUTONOMOUS_DEVELOPMENT`. Their sole difference is who selects the next WHAT; single-task execution quality is identical.

### HUMAN_DIRECTED

Human chooses WHAT. Agent determines HOW and executes that WHAT exhaustively. Agent does not choose a different WHAT afterward.

Human defines the task, scope, objective, acceptance boundary, explicit exclusions and necessary product/architecture constraints. The Agent independently completes all applicable machine-actionable work inside that scope. This mode is not passive, lower effort, conservative, regression-only, limited to enumerated shell commands, or permission to stop at the first Human/device gate. After the Human-defined task is exhausted, do not select another product task.

### AUTONOMOUS_DEVELOPMENT

Human authorizes the DIRECTION. Agent chooses successive WHATs inside that authorized direction. Each selected WHAT is executed exhaustively.

After completing a finite task, the Agent may select the next finite evidence-backed task within the authorized direction. Each selection needs its own scope, acceptance boundary and concrete provenance: an accepted Roadmap objective or Human Decision, reproduced defect, failing regression, measured compatibility/performance issue, documented architecture gap, triggered technical debt, or missing acceptance evidence for an already-authorized capability. Do not invent a new Provider, product capability, recommendation semantic, speculative framework, unnecessary architecture rewrite, unrelated cleanup or work merely to continue working. A Roadmap entry or historical authorization is not a blanket grant to work on every adjacent feature.

The autonomous loop is: inspect -> select one finite evidence-backed task -> define acceptance -> implement -> test/runtime verify -> inspect diff -> investigate negative evidence -> record result/debt -> select the next authorized task. A blocked claim does not prevent independent authorized work, but it does not widen the direction.

### Identical execution requirements

Execution mode never changes reasoning depth, engineering rigor, testing requirements, evidence standards, failure investigation depth, security requirements or acceptance honesty. Neither Human-directed nor autonomous work is a lower-effort path. The Agent determines implementation HOW and exhausts the bounded, authorized machine-actionable work in both modes. The negative-evidence exhaustion and machine-actionable remainder rules below apply identically to both modes.

Within that scope, take responsibility for inspection, reproduction, task-specific evidence research, implementation, secret-safe diagnostics, regression tests, automated checks, available authorized runtimes (including Waydroid/emulator evidence where applicable), generated-code and applicable CI verification, lifecycle/concurrency/memory/performance and failure-path investigation, diff review, and blocker/debt documentation. This is not limited to the shell commands the Human happened to enumerate. Neither mode authorizes unsafe live traffic, real-account operations, new runtimes, remote writes or other actions outside the task's existing authority.

### Persistence and Human-only switching

Persist the current mode under `execution.mode` in `PROGRESS.md`. It remains effective until the Human explicitly changes it. Only the Human may switch:

- `进入人工执行模式` or `进入 Human Directed 模式` -> `HUMAN_DIRECTED`.
- `进入自我迭代模式` or `进入自主开发模式` -> `AUTONOMOUS_DEVELOPMENT`.

Do not switch automatically because a task finishes, a regression appears, `HUMAN_REVIEW` or `DEVICE_REQUIRED` appears, the domain changes, or a blocker appears. Editing governance rules is not a mode switch.

`HUMAN_GATED_REGRESSION` is retired as an execution mode. Regression is a task type, not a mode. `PROGRESS.md` records the current mode, scheduling, work domain, task and acceptance state. An optional descriptive `task_type` may identify implementation, regression, research, validation, migration or maintenance; it does not change authority or rigor and does not need to be backfilled into historical checkpoints. Historical mode labels in dated checkpoints, research and Human Decisions remain evidence, not definitions of current selectable modes.

## Authority and architecture

- `PROJECT.md` and accepted Human Decisions define the product; `ARCHITECTURE.md` and accepted ADRs define ownership; `ROADMAP.md` records authorized direction; `PROGRESS.md` records the persisted execution mode, current scheduling and acceptance state. The latest explicit Human task controls its scope and exclusions.
- Pending Human Decisions block only their recorded scope. Historical reviews are dated evidence, not current execution instructions.
- QQ Music remains first-class. Do not add a Provider, product category, or generic media-aggregation direction without Human product authority.
- Flutter owns presentation. Rust owns reusable protocol, Domain, and business behavior. QQ Music protocol must not leak into Dart, Flutter widget concepts must not leak into Rust, Providers remain UI-free, and the typed in-process Bridge stays coarse, cancellable, provider-neutral, and free of product business rules.
- Do not introduce a localhost or hosted sidecar, raw-JSON Bridge, service locator, new state-management or navigation framework, speculative plugin runtime, or generic framework merely to reduce file count.
- Visual authority never overrides security, truthful product semantics, or architecture ownership.

## Finite work and finding ownership

Normal work is:

```text
inspect -> define bounded scope and acceptance -> implement
-> test/runtime verify -> inspect diff -> investigate negative evidence
-> record result/debt -> report
```

Work needs concrete provenance: authorized Roadmap scope, accepted design, Human report, reproduced defect, failing test, documented risk, triggered debt, required target validation, or measured compatibility/accessibility/performance evidence. Nearby cleanup, hypothetical abstraction, and the desire to keep producing commits are not provenance. After three materially similar failed attempts, record the blocker and stop repeating that approach; still assess safe, bounded alternatives inside the authorized scope rather than declaring the entire investigation exhausted.

Classify findings by their owner, regardless of task type:

- **M — Machine-verifiable:** crash, parser incompatibility, incorrect state, broken Back/Queue behavior, overflow, unreachable control, failing test, protocol incompatibility, or another reproducible condition. The Agent reproduces, investigates, fixes and verifies it within the authorized task scope.
- **H — Human-judgment:** spacing, density, typography, visual strength, composition, or other quality without a reliable machine oracle. Render actual evidence, batch small findings where practical, and leave that acceptance to the Human. Continue independent authorized machine work; do not self-approve aesthetics or use this gate to redesign accepted structure.
- **D — Human decision:** new product category, capability, recommendation semantic, scope, or other authority boundary. Stop only the affected scope and report the exact decision required.

Regression is a task type, not an execution mode. Preserve the working baseline and fix the reported/reproduced failures inside its specific scope. Do not expand it into unrelated features, architecture redesign or cleanup. Implementation, research and validation tasks follow their own authorized objectives with the same rigor.

## Acceptance gates and stopping

Execution mode is independent of acceptance gate. An acceptance gate states what prevents a particular claim from being accepted, not who chooses work or how hard the Agent works. `HUMAN_REVIEW`, `DEVICE_REQUIRED` and `HUMAN_DECISION` block only the dependent claim or action. Missing physical-device evidence cannot be replaced by emulator success; missing visual authority cannot be invented. Neither prevents bounded independent machine work already authorized within the task. Continue such work using available authorized runtimes and checks in both modes.

`Execution mode: HUMAN_DIRECTED` with `Gate: HUMAN_REVIEW` means Human selected the current task, its machine work must still be exhausted, and a particular acceptance needs Human evidence. `Execution mode: AUTONOMOUS_DEVELOPMENT` with `Gate: HUMAN_REVIEW` means a claim awaits Human evidence while other independent tasks inside the authorized direction may continue. A gate never selects or switches mode.

Before ending a task, inventory its remaining work and negative evidence. Stop only when all authorized machine-actionable work is complete and the remaining claims require Human/device/external evidence, a precise blocker prevents further safe progress, or the next action would exceed authority. A blocker in one branch does not stop independent authorized branches. A precise blocker is not a generic `DEVICE_REQUIRED` label: name the failed prerequisite, checks/alternatives actually tried, proof boundary and the exact input or authorization needed.

Do not start another page, Provider, feature, milestone, probe or refactor merely because a branch awaits acceptance. In `HUMAN_DIRECTED`, do not select another WHAT after the current task. In `AUTONOMOUS_DEVELOPMENT`, successive tasks require the already-authorized direction and concrete provenance described above; visual authority and the one-approved-page boundary still apply.

## Negative evidence exhaustion

Observed failure, timeout, unexpected latency, race, stall, native error, memory anomaly, lifecycle mismatch, CI failure or runtime inconsistency cannot be archived as resolved because a happy-path rerun passed. Before stopping, ask whether a bounded machine-actionable investigation can materially reduce uncertainty. Use deterministic failure tests, bounded reproduction, available runtime evidence, lifecycle/concurrency inspection, secret-safe diagnostics and failure-path audits where applicable.

For example, a roughly 5.5-second play timeout followed by roughly 40 seconds of focus release still requires checking which await took the time, whether cleanup is unbounded, whether deterministic reproduction is possible, and whether late cleanup can contaminate a new session. Host load is an observation, not proof of root cause. Consider generation, serialization or bounded policy only when evidence supports the change; do not speculate or silently reopen sources to hide a failure.

A negative finding may end only when it is fixed and verified, narrowed to a precise blocker, shown by concrete evidence to be outside the current scope, or shown to depend exclusively on unavailable Human/device/external evidence. Preserve failed trials and uncertainty separately from passing trials. An unconfirmed cause with executable investigation remaining is not exhaustion.

Every final report must include one of:

```text
Machine-actionable work remaining: NONE
```

```text
Machine-actionable work remaining:
- <item>: <exact blocker or authority boundary>
```

Scope this statement to the reported task; it is not a whole-project acceptance claim. Do not write `NONE` while an authorized deterministic failure test, bounded reproduction, available runtime/CI check, lifecycle/concurrency inspection, safe diagnostic or failure-path audit can still materially reduce uncertainty. If ending because fresh authority is needed, identify the exact remaining item and required Human decision.

## Security, evidence, Git, and validation

- Never commit or print credentials, cookies, tokens, musickey, QIMEI values, personal responses or account content, expiring media URLs, secret-bearing responses, build output, or unrelated generated artifacts.
- Do not automate stored-account access or mutate the maintainer's real account. Real-account acceptance is maintainer-operated and records only the minimum coarse result. Default tests remain offline; live tests are explicit, redacted, bounded, and failure-budget limited.
- Preserve claim boundaries: local tests do not prove live QQ behavior, emulator or translation does not prove physical hardware, and one target does not prove another.
- Do not reset, clean, rebase, force-push, or discard unrecognized work. Keep commits logically complete; inspect `git status`, `git diff`, and `git diff --check` before committing.
- Update persistent Markdown only for durable product, architecture, evidence, risk, debt, decision, design-source, or scheduling information. Historical evidence is not rewritten merely because current scheduling changed.
- Run checks relevant to changed layers and state what they prove. Use `dart analyze` on the current local SDK because `flutter analyze` fails under this checkout's non-ASCII path; see `MEMORY.md` when Flutter validation is relevant.
- After changing public Rust files under `bridges/flutter/src/api`, run pinned `flutter_rust_bridge_codegen` 2.13.0 from `apps/flutter`, then check for orphaned generated API files.

## Required final-report footer

Every final task report, including a report with no code changes, must include the machine-actionable remainder above and end with these three fields. Report the persisted execution mode, actual work domain and acceptance gate. Reporting them does not authorize a mode switch or expand task scope. A `COMPLETE` gate requires all acceptance required by the reported task, not merely compilation or a happy-path check.

```text
Execution mode: <HUMAN_DIRECTED | AUTONOMOUS_DEVELOPMENT>
Work domain: <CORE | UI | MIXED>
Gate: <CONTINUE | HUMAN_REVIEW | HUMAN_DECISION | DEVICE_REQUIRED | COMPLETE | BLOCKED>
```
