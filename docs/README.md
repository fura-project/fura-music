# Documentation Map

Use this page to find the current owner of a decision, design contract or
verification result. Before adding a document, search the canonical owner and
extend it when the subject already exists. Git is the implementation diary;
these documents should preserve durable contracts and review boundaries.

## Root project records

- [`README.md`](../README.md) — project entry point, setup and user-facing
  repository orientation.
- [`ARCHITECTURE.md`](../ARCHITECTURE.md) — stable application layers,
  ownership boundaries and cross-platform structure.
- [`ROADMAP.md`](../ROADMAP.md) — authorized direction and future Human gates;
  not a completed-work changelog.
- [`PROGRESS.md`](../PROGRESS.md) — concise current checkpoints and validation
  state. Prefer one consolidated entry per coherent workstream.
- [`HUMAN_DECISIONS.md`](../HUMAN_DECISIONS.md) — decisions that require Human
  authority or record an approved irreversible choice.
- [`TECH_DEBT.md`](../TECH_DEBT.md) — explicit debt with status, impact,
  solution direction and trigger condition.

## Agent guidance

- [`agent/core-development.md`](agent/core-development.md) — Rust, Provider,
  Domain, Bridge and authenticated-data rules.
- [`agent/ui-development.md`](agent/ui-development.md) — Flutter Shell,
  Material 3, adaptive layout and Human visual-review rules.

Repository-level `AGENTS.md` remains authoritative for execution mode, commit,
push and final-report requirements.

## Architecture decisions

- [`decisions/0001-in-process-flutter-rust-architecture.md`](decisions/0001-in-process-flutter-rust-architecture.md)
  — the in-process Flutter/Rust boundary.
- [`decisions/0002-capability-driven-providers.md`](decisions/0002-capability-driven-providers.md)
  — provider capabilities and truthful unsupported states.
- [`decisions/0003-platform-secure-credential-storage.md`](decisions/0003-platform-secure-credential-storage.md)
  — platform credential persistence ownership.

Add an ADR only for a durable architectural choice with meaningful alternatives
and consequences. Ordinary UI geometry and endpoint observations belong
elsewhere.

## Design contracts

- [`design/home.md`](design/home.md) — Home hierarchy, recommendation surfaces
  and its top Search entry.
- [`design/discover.md`](design/discover.md) — Discover sections and density.
- [`design/search.md`](design/search.md) — Search types, shared Track results and
  provider-backed suggestions.
- [`design/collection-details.md`](design/collection-details.md) — shared
  collection collapse, Track rows and current-Track locator.
- [`design/liked-songs.md`](design/liked-songs.md) — account Liked composition.
- [`design/recent-plays.md`](design/recent-plays.md) — cloud-history detail and
  collapse behavior.
- [`design/now-playing.md`](design/now-playing.md) — persistent and Expanded Now
  Playing, controls, lyrics, Queue and Comments.
- [`design/settings-shell.md`](design/settings-shell.md) — Settings hierarchy and
  Shell transition behavior.

Design documents state durable interaction and responsive rules. Screenshot
paths under `/tmp` are review artifacts and do not belong in these files.

## Development checkpoints

The `development/` directory records milestone audits, build matrices and
implementation plans. Start with the newest relevant checkpoint rather than
reading every historical file:

- `m1-readiness-review.md` through `m7-ui-discovery.md` — milestone reviews and
  discovery checkpoints.
- `post-m5-roadmap-review.md` and `post-m6-roadmap-review.md` — bounded roadmap
  reassessments.
- `first-release-capability-audit.md` and
  `first-release-core-capability-checkpoint.md` — release-scope evidence.
- `built-in-provider-ui-integration.md` — provider/UI integration boundaries.
- `cross-platform-test-packages.md` — platform validation packaging.
- `localization.md` — localization generation and review rules.
- `platform-native-authorization-plan.md` — native authorization planning.
- `complexity-paydown-review.md` — evidence-backed refactoring candidates.

Do not copy completed checkpoint detail into the Roadmap. Link it from the
current concise Progress entry when it remains useful.

## Research and evidence

The `research/` directory owns protocol observations, endpoint evidence,
platform diagnostics and design discovery. Common families are:

- `qqmusic-*-evidence.md` and `qqmusic-*-discovery.md` — QQ Music protocol and
  capability evidence.
- `netease-*.md` — NetEase authentication, protocol, Web login and media
  evidence.
- `kugou-protocol-evidence.md` — KuGou source provenance, implementation-family
  deduplication, TME hypothesis, capability matrix and bounded live evidence.
- `android-*.md` and `system-playback-*.md` — Android/native playback diagnosis
  and Human runtime matrices.
- `m3-*`, `m4-*` and `m5-*` — historical product discovery that informed the
  canonical design files.

Research may record bounded observations and rejected alternatives. It must not
upgrade synthetic, anonymous or local evidence into authenticated production
capability.

## Adding or updating documentation

1. Search this map, the root records and document headings for the topic.
2. Update the canonical design, architecture, decision or evidence owner.
3. Put only the current concise checkpoint in `PROGRESS.md`.
4. Put only future authorized direction and Human gates in `ROADMAP.md`.
5. Add `HUMAN_DECISIONS.md` or `TECH_DEBT.md` entries only when their stated
   thresholds are genuinely met.
6. Link instead of duplicating long rationale, validation logs or protocol
   evidence.
7. Keep machine verification separate from physical-device, real-account and
   Human visual acceptance.

When no existing owner fits, create the narrowest document in the appropriate
directory and add it to this map in the same change.
