---
execution:
  mode: CONTINUOUS_AUTONOMOUS
  state: ACTIVE
  global_stop: false
  acceptance_milestone: M1
  active_workstream: M7_PAGE_BY_PAGE_UI
  current_task: LIKED_SONGS_VISUAL_ACCEPTANCE
  next_action: HUMAN_VISUAL_REVIEW
---

# Current State

- The first-release Core-capability workstream checkpointed on 2026-08-28. Its audit has no required executable `MISSING` item; every remaining gap is exactly evidence-, environment-, or human-decision-blocked. See `docs/development/first-release-core-capability-checkpoint.md`.
- M2 through M6 are checkpointed. HD-010 leaves the unaccepted Home candidate intact but pauses its visual iteration; the Human-approved Liked Songs desktop design is now implemented as the active M7 visual-review candidate.
- M1 still lacks the maintainer-operated real QQ playback → Queue → synchronized/word-timed lyric observation. The checkpoint does not close or bypass it.
- The current Liked Songs candidate passes 372 offline Rust tests with 6 live tests default-ignored, strict Clippy, Dart format/analyze, and 393 Flutter tests. A temporary secret-free Linux integration fixture also built and rendered the 1440 × 960 and 390 × 844 candidate with real fonts; the fixture was removed after capture. Linux x64 Release packaging and the five required Linux integration targets remain last-checkpoint evidence and are rerun only after Human visual acceptance.

# Current Capability Boundary

- Later UI can reuse typed Account, Home recommendation, Library read/mutation, Search, Discover, foreground playback/Queue/mode, Lyrics, Comments, MV, and Settings foundations without raw QQ responses or fabricated semantics.
- Popular Programs and background/system playback require human product decisions. Playlist rename and Artist mutation remain protocol-evidence-blocked. Physical Android and Apple/Windows runtime claims remain environment-blocked.
- Remote-write foundations have independent protocol evidence and strict offline lifecycle coverage, but this repository did not mutate the maintainer's account. Confirmation, refresh, and maintainer-operated live acceptance remain later UI/evidence work.
- Personalized recommendation availability and quality are not authenticated-account verified. One personalized Track set may be reused transparently, but it cannot be relabeled as two distinct recommendation products.

# Current Scheduling

- There is no remaining safe agent-only Core capability task supported by the audit. Do not invent another endpoint, Provider, framework, or refactor to keep producing commits.
- The Home candidate and its truthful Daily/public/personalized slot corrections remain unaccepted and deferred; do not reinterpret the pause as visual acceptance or discard its implementation.
- Liked Songs now uses the Human-approved Stitch desktop composition over a typed provider-neutral built-in-liked semantic, the retained Library state, positional Queue, dense desktop rows, compact Track rows, and the persistent desktop/mobile player. The supplied official-client image is information-architecture reference only.
- The current candidate intentionally omits unsupported download, batch-edit, audiobook, and video-library controls. Synthetic review content does not enter production and no account data was accessed.
- No page after Liked Songs may begin before maintainer visual acceptance or another explicit Human redirect. Automated checks and the bounded Material 3 review cannot supply that acceptance.
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
- Home remains deferred and unaccepted. Liked Songs is implemented and verified as a visual-review candidate, not accepted product completion; the attached rendered output requires maintainer visual review.
- Historical research/checkpoint documents remain evidence snapshots. Current scheduling is governed by `AGENTS.md`, `ROADMAP.md`, and this file.
