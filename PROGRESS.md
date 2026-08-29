---
execution:
  mode: CONTINUOUS_AUTONOMOUS
  state: ACTIVE
  global_stop: false
  acceptance_milestone: M1
  active_workstream: M7_PAGE_BY_PAGE_UI
  current_task: NOW_PLAYING_ARTWORK_COLOR_VISUAL_ACCEPTANCE
  next_action: MAINTAINER_REVIEW_NOW_PLAYING
---

# Current State

- The first-release Core-capability workstream checkpointed on 2026-08-28. Its audit has no required executable `MISSING` item; every remaining gap is exactly evidence-, environment-, or human-decision-blocked. See `docs/development/first-release-core-capability-checkpoint.md`.
- M2 through M6 are checkpointed. HD-012 redirects the active M7 visual-review surface to Expanded Now Playing; the implemented Home and Liked Songs candidates remain intact and unaccepted.
- M1 still lacks the maintainer-operated real QQ playback → Queue → synchronized/word-timed lyric observation. The checkpoint does not close or bypass it.
- Expanded Now Playing now derives a page-local official Material 3 color scheme from the current artwork in light and dark modes, preserves the existing player/Queue/lyrics/Comments/MV ownership, and uses separate wide and compact compositions. Long translations and romanization explicitly wrap without a line cap; targeted narrow/text-scale coverage and synthetic light/dark page renders pass. This is implementation evidence, not maintainer visual acceptance or proof that unmatched upstream translation timestamps are available.

# Current Capability Boundary

- Later UI can reuse typed Account, Home recommendation, Library read/mutation, Search, Discover, foreground playback/Queue/mode, Lyrics, Comments, MV, and Settings foundations without raw QQ responses or fabricated semantics.
- Popular Programs and background/system playback require human product decisions. Playlist rename and Artist mutation remain protocol-evidence-blocked. Physical Android and Apple/Windows runtime claims remain environment-blocked.
- Remote-write foundations have independent protocol evidence and strict offline lifecycle coverage, but this repository did not mutate the maintainer's account. Confirmation, refresh, and maintainer-operated live acceptance remain later UI/evidence work.
- Personalized recommendation availability and quality are not authenticated-account verified. One personalized Track set may be reused transparently, but it cannot be relabeled as two distinct recommendation products.

# Current Scheduling

- There is no remaining safe agent-only Core capability task supported by the audit. Do not invent another endpoint, Provider, framework, or refactor to keep producing commits.
- Expanded Now Playing is the active unaccepted candidate under HD-012. Artwork-derived color remains inside the page and safely falls back to the normal app scheme when a cover is absent or cannot be decoded. The supplied frame is reference-only; supported playback, Queue, Comments, MV, synchronized lyrics, and word timing remain reachable.
- Home and Liked Songs remain implemented and unaccepted. Home still needs a maintainer authenticated rerun for Daily/personalized recommendation availability; Liked Songs retains its typed built-in-liked semantic, dense desktop rows, compact Track rows, and persistent player.
- The current candidate intentionally omits unsupported download, batch-edit, audiobook, and video-library controls. Synthetic review content does not enter production and no account data was accessed.
- No other page may begin before maintainer visual acceptance or another explicit Human redirect. Automated checks and the bounded Material 3 review cannot supply that acceptance.
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
- Home, Liked Songs, and Expanded Now Playing remain unaccepted. Expanded Now Playing is the current visual-review candidate; synthetic light/dark renders and widget tests do not prove Human visual acceptance or live catalog artwork/translation coverage.
- Historical research/checkpoint documents remain evidence snapshots. Current scheduling is governed by `AGENTS.md`, `ROADMAP.md`, and this file.
