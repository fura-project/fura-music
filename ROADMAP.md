# Roadmap

The Roadmap authorizes meaningful product and maintenance direction. It is not an implementation diary: detailed history belongs in Git, while exact milestone evidence belongs in the linked checkpoint reviews.

## Acceptance Milestone — M1 First QQ Music Vertical Slice

**Goal:** sign in and restore credentials, browse the user's playlists and details, play a Track through the Rust-backed positional Queue, and follow synchronized/word-timed lyrics.

**Implemented and automated-verified:** authentication/restore, user playlists/details, media resolution, foreground playback composition, Rust Queue, synchronized lyrics, word timing, retained presentation, Linux local-media integration, and bounded Linux/Android development packaging.

**Acceptance gap:** one maintainer-operated, secret-safe observation of corrected authenticated QQ playback → Queue navigation → synchronized lyrics → word timing. Offline, anonymous, local-file, or Fixture tests cannot close this user-facing claim.

This local evidence gap does not block independently authorized maintenance. No agent may read or persist the maintainer's stored credentials to automate it.

## Completed Checkpoint — M2 Reliability and Daily-Use Quality

- **Goal:** make the first vertical slice recoverable and usable under repeated actions, failures, refresh, adaptive layouts, keyboard/pointer/touch, and accessibility semantics.
- **Outcome:** shared transport/Queue behavior, failure recovery, retained refresh, sign-out ordering, adaptive access, and bounded Linux/Android development evidence were implemented without a new state/navigation framework or background-playback architecture.
- **Checkpoint:** 2026-08-26 — [M2 review](docs/development/m2-checkpoint-review.md).

## Completed Checkpoint — M3 QQ Music Core Product Coverage

- **Goal:** expand the vertical slice into a coherent QQ Music-first catalog and personal-library client while preserving Provider, Domain, Bridge, and Flutter ownership.
- **Outcome:** Track/Artist/Album/Playlist Search; Album/Artist browsing and metadata; recommended Playlists, rankings, Radar, new Albums/Songs; favorite Albums/Artists; and retained Track-to-catalog/Now Playing journeys were implemented. Only QQ Music exists as a Provider.
- **Checkpoint:** 2026-08-27 — [M3 review](docs/development/m3-checkpoint-review.md).

## Completed Checkpoint — M4 Deliberate Material 3 Product Experience

- **Goal:** establish one official-Flutter Material 3 baseline across desktop and compact/mobile without replacing the retained presentation or music architecture.
- **Outcome:** centralized light/dark Material foundations, adaptive shell/content hierarchy, shared Track/catalog state vocabulary, Queue/Now Playing/Lyrics hierarchy, 360 px reachability, and accessibility/focus regressions were implemented.
- **Deferred:** theme personas, artwork-derived global color, expressive visual systems, and speculative design-system infrastructure.
- **Checkpoint:** 2026-08-27 — [M4 review](docs/development/m4-checkpoint-review.md).

## Completed Checkpoint — M5 Mainstream QQ Music Product Experience

- **Goal:** establish a truthful Home-first mainstream product with distinct retained Home, Discover, Search, Library, and persistent Now Playing responsibilities.
- **Outcome:** bounded Home, coherent Library sections, Rust-authoritative sequential/shuffle and repeat modes, shared Track context, read-only comments, and one Track-associated MV journey were implemented.
- **Boundaries:** no remote mutation, downloads, background-playback architecture, additional Provider, generic social/video platform, or state/navigation replacement.
- **Checkpoint:** 2026-08-27 — [M5 review](docs/development/m5-checkpoint-review.md) and [product-completeness audit](docs/development/m5-product-completeness-audit.md).

## Completed Checkpoint — M6 Core Compatibility Evidence

- **Goal:** validate the newly introduced anonymous comments and Track-associated MV protocol paths without account material or new product capability.
- **Outcome:** default-ignored live gates pass. Evidence corrected comment identity to bounded opaque text and filters only the observed blank deleted-row shape while preserving raw-row pagination.
- **Evidence boundary:** this is selected direct-client compatibility, not full-application behavior, authenticated playback, remote MV playback, broad catalog quality, or release readiness.
- **Checkpoint:** 2026-08-27 — [M6 review](docs/development/m6-checkpoint-review.md).

## Active Workstream — M7 Page-by-Page Product UI Integration

**Goal:** integrate the existing product one page at a time against Human-approved Stitch/Figma sources so it reads as a mature QQ Music-familiar Material 3 client, using only truthful capabilities and no copied branding, proprietary assets, fake personalization, or new framework.

**Current sequence:** Home → Library → Discover → Search → Playlist → Album → Artist → Player/Queue → Now Playing → Lyrics/Comments/MV. Each arrow requires separate Human visual acceptance or direction; it is not an autonomous implementation queue.

**Current scope:** Home is active against the approved Stitch desktop and mobile frames. No other page begins until Home receives Human visual acceptance. Automated tests establish correctness and accessibility boundaries, not visual acceptance.

**Boundaries:** approved frames are visual sources of truth, while implementation must preserve retained state, accessibility, truthful Provider semantics, and the existing Flutter/Rust/music ownership. M7 is product integration, not a design-framework, navigation-framework, or architecture-rewrite project.

**Prior Home evidence:** HD-006 and HD-007 produced the current full-height desktop Sidebar/Main Region and a truthful six-section Home snapshot. HD-008 then paused presentation while the Core capability audit completed; HD-009 supersedes that scheduling pause and authorizes the approved Stitch-driven Home replacement.

## Completed Checkpoint — First-Release Core Capability Completion

**Goal:** freeze page-level visual redesign and complete the smallest truthful Account, Home-data, Library, Playback/media, Catalog, Settings, Platform, and Track-related capability foundation needed by the already authorized QQ Music-first first release.

**Execution:** maintain one repository-wide capability matrix, implement one bounded capability at a time, run layer-appropriate tests, and rerank current evidence. Safe reads and offline mutation semantics are authorized; stored account automation and autonomous real-account writes are forbidden.

**Exit criteria:** every required capability in `docs/development/first-release-capability-audit.md` is `VERIFIED` or carries an exact `EVIDENCE_BLOCKED`, `ENVIRONMENT_BLOCKED`, or `HUMAN_DECISION_REQUIRED` boundary, with no untracked executable `MISSING` first-release capability. A checkpoint proves core readiness for later UI wiring, not user-visible product completion.

**Non-goals:** page redesign, Settings-page design, all QQ APIs, social/video or download expansion, another Provider, background-service architecture without product authority, real-account mutation automation, or a generic capability, settings, paging, or dependency-injection framework.

**Outcome:** the repository-wide audit contains no required executable `MISSING` capability. Account summary, truthful Home-data contracts, bounded library mutations, two-quality media, typed Settings, and related Track foundations are available through their intended layers. Playlist rename, Artist mutation, authenticated M1 playback/lyrics, unavailable target runtimes, Popular Programs, background playback, and release work retain exact local blockers.

**Checkpoint:** 2026-08-28 — [Core capability review](docs/development/first-release-core-capability-checkpoint.md).

## Completed Maintenance Pass — Complexity Paydown

**Goal:** reduce accumulated implementation and governance complexity while preserving every existing user-visible behavior, retained state, test, supported flow, and architecture boundary.

### Outcome

- Authenticated destination, Library subsection, local-detail, and Back state are explicit while retained widgets, focus, playback, Queue, and lyrics ownership remain unchanged.
- Post-authentication dependencies are grouped by responsibility while constructor injection and granular test overrides remain explicit.
- Identical Search failure/retry semantics and repeated catalog Queue test setup are shared without generic controller, Bridge, navigation, or state frameworks.
- Governance records durable evidence/current scheduling instead of microtask ceremony or implementation diaries.

### Preserved boundaries

- No new QQ Music endpoint, Provider, product capability, Search type, recommendation surface, mutation, download, background-playback architecture, local/fallback Provider, Home content, theme, visual redesign, state framework, or navigation framework.
- Do not flatten QQ protocol → Provider → Domain → Bridge → Dart presentation boundaries solely to reduce file count.
- Do not delete regressions or evidence documents merely to reduce totals.

**Verified on 2026-08-27:** all full Rust, Dart/Flutter, Linux release-build, and required Linux integration gates passed. The audit, outcomes, claim limits, and final self-review are recorded in [the complexity-paydown review](docs/development/complexity-paydown-review.md).

## Later Evidence-Gated Direction

The Core-capability checkpoint is complete. M7 is active only for the current Human-approved page; the next page remains gated on acceptance and separate visual direction. Automated tests do not establish visual product completion.

Offline/cache behavior, a narrow local-library capability, or media fallback require demonstrated user value and separate Roadmap authority. They must not turn the product into a multi-service aggregator. Release identity/signing and external distribution remain governed by HD-001 and the linked technical debt.
