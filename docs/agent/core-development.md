# Core / Backend Development

Use this guide for QQ Music protocol, Provider and Domain behavior, authentication and credential semantics, media resolution, Queue rules, lyric parsing/timing, remote mutation semantics, recommendation capability, Settings business models, reusable non-visual logic, Rust platform-neutral behavior, and typed Bridge contracts. A small Flutter adapter needed to expose a capability remains Core work; visual design does not.

The shared authority, execution-mode, security, Git, and reporting rules in [`AGENTS.md`](../../AGENTS.md) always apply.

## Ownership and authority

```text
Human defines product boundary and execution mode.
Evidence plus architecture define correctness.
The Agent designs the bounded implementation.
```

Inside an authorized capability, implementation details such as Rust models, Provider contracts, Domain representation, Bridge DTOs, cancellation, stale-result rules, error semantics, tests, and internal factoring normally do not require Human approval. This does not authorize a new product category, Provider, stored-account automation, real-account mutation, speculative framework, or visual redesign.

Keep raw QQ models and protocol behavior inside `QQMusicClient`; keep Provider identity opaque outside `QQMusicProvider`; keep reusable business behavior in Rust; keep the Bridge typed, coarse, cancellable, provider-neutral, and free of product business rules.

## Execution-mode interpretation

### CORE + AUTONOMOUS_DEVELOPMENT

Core may use the evidence-driven loop that supports forward development:

```text
implement -> test/evidence -> fix -> verify -> next finite authorized task
```

The next task still needs current product authority and concrete evidence. Do not manufacture capability work to continue.

### CORE + HUMAN_GATED_REGRESSION

Assume existing Core behavior is the baseline. Investigate only reproduced bugs, compatibility failures, Human-reported incorrect behavior, failing regressions, and evidence-backed correctness defects.

Start with targeted reproduction and evidence. Fix the smallest proven cause and verify that exact behavior. Do not expand capability coverage, redesign APIs, perform speculative architecture work, or clean up nearby code while fixing the regression. Completion of the bounded regression is a valid `COMPLETE` gate.

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
