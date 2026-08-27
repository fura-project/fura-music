---
execution:
  mode: CONTINUOUS_AUTONOMOUS
  state: ACTIVE
  global_stop: false
  acceptance_milestone: M1
  active_workstream: EVIDENCE_GATED_PRODUCT_REVIEW
  current_task: null
  next_action: MAINTAINER_REVIEW
---

# Current State

- The first-release Core-capability workstream checkpointed on 2026-08-28. Its audit has no required executable `MISSING` item; every remaining gap is exactly evidence-, environment-, or human-decision-blocked. See `docs/development/first-release-core-capability-checkpoint.md`.
- M2 through M6 are checkpointed. M7 is authorized but not checkpointed; its bounded Home/Library/persistent-player work remains paused pending maintainer visual acceptance of the current Home and separate page-level visual direction.
- M1 still lacks the maintainer-operated real QQ playback → Queue → synchronized/word-timed lyric observation. The checkpoint does not close or bypass it.
- Current full gates pass: 372 offline Rust tests with 6 live tests default-ignored, strict Clippy, Dart format/analyze, 385 Flutter tests, Linux x64 Release packaging, and all five required Linux integration targets.

# Current Capability Boundary

- Later UI can reuse typed Account, Home recommendation, Library read/mutation, Search, Discover, foreground playback/Queue/mode, Lyrics, Comments, MV, and Settings foundations without raw QQ responses or fabricated semantics.
- Popular Programs and background/system playback require human product decisions. Playlist rename and Artist mutation remain protocol-evidence-blocked. Physical Android and Apple/Windows runtime claims remain environment-blocked.
- Remote-write foundations have independent protocol evidence and strict offline lifecycle coverage, but this repository did not mutate the maintainer's account. Confirmation, refresh, and maintainer-operated live acceptance remain later UI/evidence work.
- Personalized recommendation availability and quality are not authenticated-account verified. One personalized Track set may be reused transparently, but it cannot be relabeled as two distinct recommendation products.

# Current Scheduling

- There is no remaining safe agent-only Core capability task supported by the audit. Do not invent another endpoint, Provider, framework, or refactor to keep producing commits.
- The next product action is maintainer review of the current authenticated Home snapshot. UI code must not resume automatically from this Core checkpoint.
- If Home is accepted or redirected, subsequent UI work proceeds one page at a time under separate human visual direction while preserving retained state, accessibility, and the existing Flutter/Rust/music boundaries.
- Do not automate stored-account access, real-account mutation acceptance, or secret-bearing screenshots/fixtures.

# Blockers

- **M1 evidence:** maintainer-operated ordinary QQ Track playback → Queue navigation → synchronized lyrics → word timing.
- **Protocol evidence:** playlist rename and Artist follow/unfollow need independent current request/success evidence before Client work.
- **Product authority:** Popular Programs and background/system playback remain undecided.
- **Target environments:** physical Android and Apple/Windows secure-storage/media behavior cannot be established on this host.
- **Release:** production identity, signing, external distribution, and native-video notices remain blocked by HD-001 and TD-002/TD-006.

# Pending Human Decisions

- **HD-001:** final product/display name, platform identifiers, signing custody, and distribution ownership.
- Popular Programs' product boundary and background/system playback remain explicitly `HUMAN_DECISION_REQUIRED` in the first-release audit; they are not promoted to numbered decisions until the maintainer chooses to address them.

# Important Evidence Limits

- Offline and Widget tests prove implemented rules and retained presentation behavior, not current authenticated QQ CDN playback, personalized recommendation quality, or broad live catalog compatibility.
- Linux local media, packaged Bridge, and development builds do not prove physical-device audio focus, hardware video decode, unavailable operating systems, or release readiness.
- The current Home is a paused presentation snapshot, not accepted product completion. Automated layout tests cannot supply its required visual review.
- Historical research/checkpoint documents remain evidence snapshots. Current scheduling is governed by `AGENTS.md`, `ROADMAP.md`, and this file.
