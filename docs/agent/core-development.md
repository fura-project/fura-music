# Core / Backend Development Mode

Use this mode for QQ Music protocol, Provider and Domain behavior, authentication and credential semantics, media resolution, Queue rules, lyric parsing/timing, remote mutation semantics, recommendation capability, Settings persistence/business models, reusable non-visual logic, Rust platform-neutral behavior, and typed Bridge contracts. A small Flutter adapter needed to expose a capability remains Core work; visual design does not.

The shared rules in [`AGENTS.md`](../../AGENTS.md) always apply.

## Authority model

```text
Human defines product boundary and required capability.
Evidence plus architecture define correctness.
Codex designs the implementation.
```

Inside an already authorized capability area, Codex may autonomously determine protocol implementation, Rust model structure, Provider contract shape, Domain representation, Bridge DTOs, cancellation and stale-result rules, error semantics, test structure, internal factoring, and the next finite evidenced Core task. Ordinary implementation choices do not require Human approval.

Core authority does not permit a new product category, Provider, stored-account automation, real-account mutation, speculative framework, or visual redesign.

## Evidence and correctness

Prefer evidence in this order:

1. bounded real QQ Music behavior where safe;
2. current independent active implementations;
3. repository fixtures and existing integration evidence;
4. older wrappers or historical evidence as secondary sources.

Do not trust one third-party wrapper blindly. Cross-validate conflicting protocol behavior, keep raw QQ models inside `QQMusicClient`, and preserve Provider-owned identity as opaque outside `QQMusicProvider`.

For Core work, automated correctness evidence is a valid completion mechanism:

```text
implemented -> the bounded code path exists
verified    -> tests, protocol, integration, or platform evidence supports the claim
```

Visual acceptance is not required for a protocol or Domain claim. Conversely, an offline fixture does not prove a live service or real-account path.

## Live evidence and remote writes

- Live tests must be bounded, redacted, ignored by default where appropriate, secret-safe, and failure-budget limited.
- Never automate stored credentials or persist returned personal content.
- Do not autonomously mutate the maintainer's account. Remote-write foundations may be implemented and verified offline without performing a real persistent write.
- Once a remote write may have been sent, preserve unknown-outcome semantics; cancellation or transport failure cannot be relabeled as a definitive remote failure.

## Refactoring

Refactor only from proven duplication, a correctness problem, blocked testability/changeability, a boundary violation, repeated lifecycle mechanics, triggered debt, or measured maintenance friction. File size, aesthetics, and hypothetical future Providers are not sufficient evidence.

## Mixed work

If a UI implementation exposes a genuine missing capability, define a bounded Core subtask, implement and verify it here, then return to the approved UI design. Do not fabricate production data, delete the approved section, or let the Core subtask choose a new composition.

## Validation and continuation

Run the affected package tests plus the relevant workspace checks. The normal full Core gate is:

```bash
cargo fmt --all -- --check
cargo test --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
```

Bridge changes also require the code-generation and orphan-file check in `AGENTS.md`, followed by affected Dart/Flutter validation from the UI guide.

After a Core task:

```text
test -> self-review -> inspect diff -> commit -> rank remaining authorized Core gaps
```

Task completion is not a stop condition. Codex may select the next finite Core task when current product scope and evidence already authorize it; it must not invent a capability to continue producing work.
