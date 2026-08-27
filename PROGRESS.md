---
execution:
  mode: CONTINUOUS_AUTONOMOUS
  state: ACTIVE
  global_stop: false
  acceptance_milestone: M1
  active_workstream: HOME_FOCUSED_UI_REVIEW
  current_task: null
  next_action: MAINTAINER_HOME_VISUAL_ACCEPTANCE
---

# Current State

- New QQ Music capabilities and visual redesign remain frozen after the maintainer-authorized complexity-paydown pass.
- M2 through M6 are checkpointed. M7 is not checkpointed and is paused after bounded Home, Library, and persistent-player presentation work.
- The authenticated presentation now uses one typed local-route stack instead of unrelated nullable route fields and a long Back priority chain. Retained destination/detail widgets, controllers, playback, Queue, lyrics, and focus behavior remain covered by existing regressions.
- The composition root keeps explicit constructor injection while forwarding three immutable responsibility groups after authentication: Library/Catalog, Discovery/Search, and Playback.
- The four Search types share one identical failure taxonomy/retry policy while retaining feature-specific results, pagination, Bridge DTO validation, and UI state.
- Repeated catalog Queue test setup is shared without deleting any distinct regression scenario.
- Governance is current-state oriented, and the complete Rust, Dart/Flutter, Linux build, and required Linux integration gates pass. See `docs/development/complexity-paydown-review.md`.
- HD-006 authorized one Home-only visual pass. The real-data Home now removes duplicate navigation actions, establishes a restrained page/section hierarchy, uses a denser artwork recommendation shelf, and presents personal playlists as compact metadata rows. Desktop and compact running screenshots received two bounded `agy` reviews; no other page or product capability changed.

# Active Work

- Home is `HOME_READY_FOR_HUMAN_VISUAL_REVIEW`; no further Home iteration is selected without maintainer evidence.
- Keep Library, Discover, Search, catalog, Queue, Now Playing, authentication, and global M7 work paused. A next UI page requires explicit maintainer acceptance/authority.
- Authenticated screenshots remain temporary local files and are not committed because they contain current catalog and personal-library presentation.

# Blockers

- M1 still needs one user-operated, secret-safe observation of corrected authenticated QQ playback → Queue navigation → synchronized lyrics → word timing. This blocks only the M1 end-to-end acceptance claim.
- Physical Android and Apple/Windows runtime evidence require those actual environments.
- Production identity, signing, external distribution, and release-time native-video notices remain blocked by HD-001 and the linked debt items.

# Next Candidates

1. Record maintainer acceptance or bounded Home corrections from the supplied desktop/compact screenshots.
2. Record the M1 playback/Queue/lyrics observation when the maintainer supplies only coarse outcomes; do not access stored credentials autonomously.
3. Resume another page only after explicit product authority; otherwise keep the UI freeze.

# Pending Human Decisions

- **HD-001:** final product/display name, platform identifiers, signing custody, and distribution ownership.

# Important Risks / Evidence Gaps

- Offline and Widget tests prove implemented rules and retained presentation behavior, not current authenticated QQ CDN playback or broad catalog compatibility.
- Linux local media, packaged Bridge, and development builds do not prove physical-device audio focus, hardware video decode, or unavailable operating systems.
- The Home pass has real authenticated desktop/compact screenshots and external visual critique, but it is not product-complete until the maintainer accepts the result. It does not validate or resume the rest of M7.
- Historical research/checkpoint documents contain useful protocol and evidence boundaries. They are retained unless a file is proven to duplicate Git and current governance without unique reasoning.
