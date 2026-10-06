# Core / Backend Development

Use this guide for QQ Music and NetEase protocol, Provider and Domain behavior, authentication and credential semantics, media resolution, Queue rules, lyric parsing/timing, remote mutation semantics, recommendation capability, Settings business models, reusable non-visual logic, Rust platform-neutral behavior, and typed Bridge contracts. A small Flutter adapter needed to expose a capability remains Core work; visual design does not.

The shared execution-mode, task-authority, evidence-exhaustion, security, Git, and reporting rules in [`AGENTS.md`](../../AGENTS.md) always apply. The only current modes are `HUMAN_DIRECTED` and `AUTONOMOUS_DEVELOPMENT`; mode is persisted in `PROGRESS.md` and only Human may switch it.

## Ownership and authority

```text
Human defines product boundary, task scope and execution mode.
Evidence plus architecture define correctness.
The Agent designs the bounded implementation.
```

Inside an authorized capability, implementation details such as Rust models, Provider contracts, Domain representation, Bridge DTOs, cancellation, stale-result rules, error semantics, tests, and internal factoring normally do not require Human approval. This does not authorize a new product category, Provider, stored-account automation, real-account mutation, speculative framework, or visual redesign.

Keep raw QQ/NetEase models and protocol behavior inside their respective clients; keep Provider identity opaque outside the owning Provider; keep reusable business behavior in Rust; keep the Bridge typed, coarse, cancellable, provider-neutral, and free of product business rules.

## Execution-mode interpretation

### CORE + HUMAN_DIRECTED

Human chooses the current Core WHAT: task, scope, objective, acceptance boundary and exclusions. The Agent determines HOW and exhausts applicable inspection, reproduction, research, implementation, diagnostics, tests, authorized runtime/CI checks, failure/lifecycle/concurrency/memory investigation and diff/blocker review. Do not select another Core task after completing it. This is not passive, lower effort, regression-only or limited to the commands Human enumerated.

### CORE + AUTONOMOUS_DEVELOPMENT

Human authorizes the Core direction. The Agent may select successive finite evidence-backed Core WHATs only inside that direction, using the provenance requirements in `AGENTS.md`. Each selected task must be executed just as exhaustively as a Human-directed task. Do not invent capabilities, Providers, framework work or adjacent cleanup merely to continue.

### Shared execution and evidence

The Agent executes the authorized Core task exhaustively with identical reasoning depth, engineering rigor, testing, evidence standards, failure investigation, security and acceptance honesty in both modes, for implementation, regression, research or validation:

```text
inspect -> reproduce/research -> implement -> test/runtime verify
-> investigate failures -> review diff -> record evidence/blockers
```

Acceptance gates do not select or switch mode. In either mode, a Human/live/device gate blocks its dependent claim, not independent authorized machine work. `AUTONOMOUS_DEVELOPMENT` additionally permits the next task within the already-authorized direction; `HUMAN_DIRECTED` does not. Negative-evidence exhaustion and machine-actionable remainder reporting are mandatory in both.

### Regression scope and independent evidence

Assume existing Core behavior is the baseline. Investigate only reproduced bugs, compatibility failures, Human-reported incorrect behavior, failing regressions, and evidence-backed correctness defects.

Start with targeted reproduction and evidence. Fix the smallest proven cause and verify that exact behavior. Do not expand capability coverage, redesign APIs, perform speculative architecture work, or clean up nearby code while fixing the regression. A live/account/device gate blocks its dependent acceptance only: exhaust independent authorized machine work and negative-evidence investigation before reporting the exact remaining blocker. A passing rerun does not erase an observed failure, and `COMPLETE` requires the reported task's actual acceptance boundary.

## Evidence and correctness

Prefer evidence in this order:

1. bounded real QQ Music behavior where safe;
2. current independent active implementations;
3. repository fixtures and existing integration evidence;
4. older wrappers or historical evidence as secondary sources.

Cross-validate conflicting protocol behavior. Automated tests, protocol evidence, integration, or platform evidence may verify a bounded Core claim, but an offline fixture does not prove a live service or real-account path.

## Live evidence and remote writes

- Live tests are bounded, redacted, ignored by default where appropriate, secret-safe, and failure-budget limited.
- Never automate stored credentials or persist returned personal content.
- Do not autonomously mutate the maintainer's account. Remote-write foundations may be verified offline without performing a persistent write.
- Once a remote write may have been sent, preserve unknown-outcome semantics; cancellation or transport failure cannot become a definitive remote failure.

## Refactoring and Mixed work

Refactor only for proven duplication, correctness, blocked testability/changeability, a boundary violation, repeated lifecycle mechanics, triggered debt, or measured maintenance friction. File size, aesthetics, and hypothetical future Providers are not evidence.

If UI work exposes a genuine missing capability, define and verify one bounded Core subtask, then return to the approved UI task. Do not fabricate production data, delete the approved section, or let the Core subtask choose a new composition.

## Validation

Run affected package tests and checks. The normal full Core gate, when the task's risk or checkpoint requires it, is:

```bash
cargo fmt --all -- --check
cargo test --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
```

Bridge changes also require the code-generation and orphan-file checks in `AGENTS.md`, followed by affected Dart/Flutter validation from the UI guide. Targeted regression work does not require unrelated full-suite ceremony unless its changed boundary could regress what that suite proves.
