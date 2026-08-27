---
execution:
  mode: CONTINUOUS_AUTONOMOUS
  state: ACTIVE
  global_stop: false
  acceptance_milestone: M1
  active_workstream: FIRST_RELEASE_CORE_CAPABILITY_COMPLETION
  current_task: TYPED_PERSISTENT_SETTINGS_FOUNDATION
  next_action: IMPLEMENT
---

# Current State

- Visual UI redesign is frozen while the maintainer-authorized first-release core-capability pass is active.
- M2 through M6 are checkpointed. M7 is not checkpointed and is paused after bounded Home, Library, and persistent-player presentation work.
- The authenticated presentation now uses one typed local-route stack instead of unrelated nullable route fields and a long Back priority chain. Retained destination/detail widgets, controllers, playback, Queue, lyrics, and focus behavior remain covered by existing regressions.
- The composition root keeps explicit constructor injection while forwarding three immutable responsibility groups after authentication: Library/Catalog, Discovery/Search, and Playback.
- The four Search types share one identical failure taxonomy/retry policy while retaining feature-specific results, pagination, Bridge DTO validation, and UI state.
- Repeated catalog Queue test setup is shared without deleting any distinct regression scenario.
- Governance is current-state oriented, and the complete Rust, Dart/Flutter, Linux build, and required Linux integration gates pass. See `docs/development/complexity-paydown-review.md`.
- The repository-wide capability matrix is current in `docs/development/first-release-capability-audit.md`. Existing read/catalog/playback foundations are strong, while account summary, truthful Home data, library mutations, audio quality, Settings, and target-runtime evidence remain explicitly classified.

# Active Work

- Implement the selected typed persistent Settings foundation with only the already-existing system/light/dark theme preference, versioned storage, safe defaults, and read/write/reset tests.
- Keep Home, Library, Discover, Search, catalog, Queue, Now Playing, authentication, and global M7 visual work paused. Capability work may add only the smallest verification control when genuinely required.
- Do not automate stored-account access or real-account mutation acceptance.

# Blockers

- M1 still needs one user-operated, secret-safe observation of corrected authenticated QQ playback → Queue navigation → synchronized lyrics → word timing. This blocks only the M1 end-to-end acceptance claim.
- Physical Android and Apple/Windows runtime evidence require those actual environments.
- Production identity, signing, external distribution, and release-time native-video notices remain blocked by HD-001 and the linked debt items.

# Next Candidates

1. Complete the typed persistent Settings foundation, then update the capability matrix and rerank.
2. Perform bounded signed-in account-summary discovery using sanitized evidence; do not retain personal responses.
3. Cross-validate audio-quality request, returned-quality, entitlement, and fallback semantics before implementation.
4. Research one smallest reversible personal-library mutation without autonomously changing the maintainer's account.
5. Discover truthful Home recommendation semantics without substituting unrelated existing data.

# Pending Human Decisions

- **HD-001:** final product/display name, platform identifiers, signing custody, and distribution ownership.

# Important Risks / Evidence Gaps

- Offline and Widget tests prove implemented rules and retained presentation behavior, not current authenticated QQ CDN playback or broad catalog compatibility.
- Linux local media, packaged Bridge, and development builds do not prove physical-device audio focus, hardware video decode, or unavailable operating systems.
- The previous directed Home remains a paused presentation snapshot, not accepted product completion. Public recommendations are not Daily Recommendations, personal playlists are not a Treasure Playlist Library, and the missing Home data capabilities are tracked without fabricated substitutions.
- Historical research/checkpoint documents contain useful protocol and evidence boundaries. They are retained unless a file is proven to duplicate Git and current governance without unique reasoning.
