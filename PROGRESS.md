---
execution:
  mode: CONTINUOUS_AUTONOMOUS
  state: ACTIVE
  global_stop: false
  acceptance_milestone: M1
  active_workstream: FIRST_RELEASE_CORE_CAPABILITY_COMPLETION
  current_task: null
  next_action: SELECT_NEXT_TASK
---

# Current State

- Visual UI redesign is frozen while the maintainer-authorized first-release core-capability pass is active.
- M2 through M6 are checkpointed. M7 is not checkpointed and is paused after bounded Home, Library, and persistent-player presentation work.
- The authenticated presentation now uses one typed local-route stack instead of unrelated nullable route fields and a long Back priority chain. Retained destination/detail widgets, controllers, playback, Queue, lyrics, and focus behavior remain covered by existing regressions.
- The composition root keeps explicit constructor injection while forwarding three immutable responsibility groups after authentication: Library/Catalog, Discovery/Search, and Playback.
- The four Search types share one identical failure taxonomy/retry policy while retaining feature-specific results, pagination, Bridge DTO validation, and UI state.
- Repeated catalog Queue test setup is shared without deleting any distinct regression scenario.
- Governance is current-state oriented. The current full gates pass: 372 offline Rust tests with 6 live tests default-ignored, strict Clippy, Dart format/analyze, 385 Flutter tests, Linux x64 Release packaging, and all five required Linux integration targets. See `docs/development/complexity-paydown-review.md` for the earlier consolidation review.
- The repository-wide capability matrix is current in `docs/development/first-release-capability-audit.md`. Existing read/catalog/playback foundations are strong, while truthful Home data, library mutations, and target-runtime evidence remain explicitly classified.

# Active Work

- The typed Settings foundation now persists only the existing system/light/dark and Standard/High playback-quality preferences in a versioned noncritical local document. Defaults, version-1 migration, malformed/future documents, storage failures, read/write/reset, startup Theme/media wiring, and a disposable Linux native round trip are verified; no Settings page was added.
- The signed-in account-summary foundation now maps only a bounded display name and optional avatar through Domain, Provider, a cancellable Bridge, and a Dart gateway. It remains presentation-deferred and is not claimed as maintainer-account live evidence.
- Standard/High MP3 preference now flows from the versioned local Settings document through a typed cancellable Bridge into Rust-owned negotiation. High retries Standard only after an unavailable item, and the returned source reports actual quality; FLAC, encrypted media, and VIP inference remain out of scope.
- Liked/not-liked Track is now a bounded typed remote-mutation foundation from Client through Dart gateway. It uses current independently evidenced playlist-write semantics, rejects invalid identity before transport, and never turns network/response/cancellation/replacement uncertainty into a false confirmed result. No real account was changed.
- One Track add/remove operation now accepts only a structurally validated owned playlist target through Client, Provider, cancellable Bridge, and Dart gateway. Favorite, public catalog, foreign, and malformed targets fail before transport; unknown outcomes remain unconfirmed. No real account was changed.
- Bounded owned-playlist creation now runs through Client, Provider, cancellable Bridge, generated binding, and Dart gateway. It accepts the independently observed nonzero `result.tid` or `result.id` forms, also requires `dirId` and the server-returned name, rejects invalid names before transport, and preserves unknown-outcome semantics. No real account was changed.
- TD-007 was resolved before the third remote write: Rust now shares only single-use run/cancel state, Dart shares only explicit-rejection vault cleanup, and every operation keeps typed results plus Provider-owned identity rules.
- Favorite/not-favorite Album is now a bounded typed foundation from Client through Dart gateway. It accepts only a QQ Album opaque identity carrying a nonzero numeric ID, sends the independently evidenced numeric-ID form exactly once, requires an empty failed-ID list for success, and never retries with the alternate MID form after an unknown outcome. Offline Client, Provider, cancellable Bridge, generated binding, Dart-gateway, credential-cleanup, account-replacement, and packaged-Bridge coverage passes; no real account was changed.
- Playlist rename remains `EVIDENCE_BLOCKED`: a bounded current-source rescan found only one detailed `EditPlaylist` contract, whose own implementation says description editing is ineffective. No Client request will be inferred from that single source.
- Owned-playlist deletion now runs through Client, Provider, a cancellable generated Bridge, and an independent Dart gateway without UI wiring. Only an exact Provider-owned target may reach one request, and success requires the same returned directory ID; missing/zero/mismatched responses and cancellation/replacement remain unknown outcomes. Offline Rust/Dart coverage and the packaged Linux Bridge smoke pass; no real account was changed.
- Daily 30 now has a truthful authenticated read foundation from direct Client request through a cancellable generated Bridge and Dart gateway. Three simultaneous semantic markers select zero or one existing catalog playlist; absence is not failure, ambiguity is rejected, and no heterogeneous feed data or presentation work crossed the boundary. Two current sources, one public real-response fixture, offline lifecycle coverage, and an anonymous structure-only probe support the contract; authenticated availability remains unclaimed.
- Personalized playlist discovery now has a truthful authenticated read foundation from the same evidenced recommendation feed through Client, Provider, a cancellable generated Bridge, and an independent Dart gateway. Exactly zero or one `playlist...` shelf may yield at most 64 unique existing catalog summaries; source labels, tracking fields, heterogeneous cards, and “Treasure” presentation wording do not cross the boundary. Authenticated availability and recommendation quality remain unclaimed.
- Personalized Track recommendations now use one independently cross-validated personal-radio request for at most five existing Track summaries through Client, Provider, a cancellable generated Bridge, and an independent Dart gateway. Radio identity, feedback/continuation fields, listening-history claims, and Home wording do not cross the boundary. Authenticated content and recommendation quality remain unclaimed.
- Artist mutation remains evidence-blocked; do not infer its write contract from the existing follow-list read.
- Keep Home, Library, Discover, Search, catalog, Queue, Now Playing, authentication, and global M7 visual work paused. Capability work may add only the smallest verification control when genuinely required.
- Do not automate stored-account access or real-account mutation acceptance.

# Blockers

- M1 still needs one user-operated, secret-safe observation of corrected authenticated QQ playback → Queue navigation → synchronized lyrics → word timing. This blocks only the M1 end-to-end acceptance claim.
- Physical Android and Apple/Windows runtime evidence require those actual environments.
- Production identity, signing, external distribution, and release-time native-video notices remain blocked by HD-001 and the linked debt items.

# Next Candidates

1. Run the whole capability convergence review without inventing another feature.

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
- Playlist creation has exact offline request/result/lifecycle coverage, including the independently observed `tid`/`id` response variation, but no repository or maintainer-account live roundtrip and no post-write UI refresh path.
- Album favorite writes have current method-level cross-validation, exact offline cross-layer coverage, and an external authenticated reversible test for the numeric-ID form, but this repository has not retained a real response fixture or executed the maintainer account. Artist write semantics remain evidence-blocked.
- Playlist rename remains evidence-blocked on one detailed current implementation; its mask, optional-field, and success semantics must not be guessed. Playlist deletion has only offline cross-layer validation; later UI must explicitly confirm it, refresh after unknown outcomes, and leave live acceptance to the maintainer.
- Daily 30 has exact offline request/selection/lifecycle coverage and packaged Bridge cancellation, but no authenticated maintainer-account observation. The credential-free probe returned no Daily match, as expected, and proves only endpoint structure.
- Personalized playlists have exact offline request/selection/lifecycle coverage, current independent source agreement, and a public real-response fixture, but no authenticated maintainer-account observation. The credential-free probe returned no shelf-level playlist marker, so it proves endpoint structure rather than personalization or content quality.
- Personalized Tracks have exact offline request/mapping/lifecycle coverage and three current-source implementations, but no authenticated maintainer-account observation. The credential-free probe reached the named result and received explicit rejection, proving endpoint shape rather than personalized content, recommendation quality, media resolution, or playback.
