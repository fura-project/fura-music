---
execution:
  mode: CONTINUOUS_AUTONOMOUS
  state: ACTIVE
  global_stop: false
  acceptance_milestone: M1
  active_workstream: FIRST_RELEASE_CORE_CAPABILITY_COMPLETION
  current_task: PLAYLIST_CONTAINER_MUTATION_DISCOVERY
  next_action: DISCOVER
---

# Current State

- Visual UI redesign is frozen while the maintainer-authorized first-release core-capability pass is active.
- M2 through M6 are checkpointed. M7 is not checkpointed and is paused after bounded Home, Library, and persistent-player presentation work.
- The authenticated presentation now uses one typed local-route stack instead of unrelated nullable route fields and a long Back priority chain. Retained destination/detail widgets, controllers, playback, Queue, lyrics, and focus behavior remain covered by existing regressions.
- The composition root keeps explicit constructor injection while forwarding three immutable responsibility groups after authentication: Library/Catalog, Discovery/Search, and Playback.
- The four Search types share one identical failure taxonomy/retry policy while retaining feature-specific results, pagination, Bridge DTO validation, and UI state.
- Repeated catalog Queue test setup is shared without deleting any distinct regression scenario.
- Governance is current-state oriented, and the complete Rust, Dart/Flutter, Linux build, and required Linux integration gates pass. See `docs/development/complexity-paydown-review.md`.
- The repository-wide capability matrix is current in `docs/development/first-release-capability-audit.md`. Existing read/catalog/playback foundations are strong, while truthful Home data, library mutations, and target-runtime evidence remain explicitly classified.

# Active Work

- The typed Settings foundation now persists only the existing system/light/dark and Standard/High playback-quality preferences in a versioned noncritical local document. Defaults, version-1 migration, malformed/future documents, storage failures, read/write/reset, startup Theme/media wiring, and a disposable Linux native round trip are verified; no Settings page was added.
- The signed-in account-summary foundation now maps only a bounded display name and optional avatar through Domain, Provider, a cancellable Bridge, and a Dart gateway. It remains presentation-deferred and is not claimed as maintainer-account live evidence.
- Standard/High MP3 preference now flows from the versioned local Settings document through a typed cancellable Bridge into Rust-owned negotiation. High retries Standard only after an unavailable item, and the returned source reports actual quality; FLAC, encrypted media, and VIP inference remain out of scope.
- Liked/not-liked Track is now a bounded typed remote-mutation foundation from Client through Dart gateway. It uses current independently evidenced playlist-write semantics, rejects invalid identity before transport, and never turns network/response/cancellation/replacement uncertainty into a false confirmed result. No real account was changed.
- One Track add/remove operation now accepts only a structurally validated owned playlist target through Client, Provider, cancellable Bridge, and Dart gateway. Favorite, public catalog, foreign, and malformed targets fail before transport; unknown outcomes remain unconfirmed. No real account was changed.
- Discover the smallest safe playlist-container mutation from current independent evidence; do not bundle create, rename, and destructive delete or execute the maintainer's account.
- Keep Home, Library, Discover, Search, catalog, Queue, Now Playing, authentication, and global M7 visual work paused. Capability work may add only the smallest verification control when genuinely required.
- Do not automate stored-account access or real-account mutation acceptance.

# Blockers

- M1 still needs one user-operated, secret-safe observation of corrected authenticated QQ playback → Queue navigation → synchronized lyrics → word timing. This blocks only the M1 end-to-end acceptance claim.
- Physical Android and Apple/Windows runtime evidence require those actual environments.
- Production identity, signing, external distribution, and release-time native-video notices remain blocked by HD-001 and the linked debt items.

# Next Candidates

1. Discover one bounded playlist-container mutation without autonomously changing the maintainer's account.
2. Discover truthful Home recommendation semantics without substituting unrelated existing data.

# Pending Human Decisions

- **HD-001:** final product/display name, platform identifiers, signing custody, and distribution ownership.

# Important Risks / Evidence Gaps

- Offline and Widget tests prove implemented rules and retained presentation behavior, not current authenticated QQ CDN playback or broad catalog compatibility.
- Linux local media, packaged Bridge, and development builds do not prove physical-device audio focus, hardware video decode, or unavailable operating systems.
- The previous directed Home remains a paused presentation snapshot, not accepted product completion. Public recommendations are not Daily Recommendations, personal playlists are not a Treasure Playlist Library, and the missing Home data capabilities are tracked without fabricated substitutions.
- Historical research/checkpoint documents contain useful protocol and evidence boundaries. They are retained unless a file is proven to duplicate Git and current governance without unique reasoning.
- Signed-in account-summary mapping is supported by two current independent implementations and synthetic offline coverage; this checkout has not retained or observed the maintainer's live account profile response.
- The credential-free media gate accepts both M500 and M800 request schemas, but this does not prove the maintainer account's high-quality entitlement, actual playback, or the specific reason for any unavailable result.
- Liked-Track mutation request semantics have current independent and external authenticated-roundtrip evidence, but this repository has only offline fixtures. Cancellation, malformed response, network failure, or account replacement can leave the remote outcome unknown; later UI must refresh rather than guess.
- Owned-playlist Track membership reuses that independently evidenced request with a Provider-validated owned target, but this repository still has only offline evidence and no post-write UI refresh path.
