# Human Decisions

## HD-001 — Release identity and signing custody

**Status:** Pending

**Context:** M1 packaging has produced development Android and Linux artifacts, so TD-002's packaging trigger is satisfied. Android release builds still use development signing and the platform shells still use generated identity. No artifact has been authorized for external distribution.

**Decision needed:** The human maintainer defines the final product/display name, per-platform application identifiers, and the secret-safe ownership and custody workflow for release signing keys before external distribution.

**Options:**

1. Keep the current working product name and define final platform identifiers plus signing custody.
2. Choose a different final product name and corresponding platform identifiers plus signing custody before release setup.

**Blocked work:**

- Resolving TD-002.
- Production release identity and signing setup.
- Distribution of artifacts outside development.

**Not blocked:**

- The remaining M1 real-account playback, queue, and lyric acceptance observation.
- Evidence-backed post-M4 reliability, accessibility, and daily-use work within the Roadmap.
- Development-signed local builds and tests.
- Evidence-backed QQ Music Provider/Core work within the Roadmap.

**Current agent action:** Continue any independently evidenced Roadmap work when available and keep generated or development-signed artifacts development-only.

## HD-002 — Default Material baseline before theme personas

**Status:** Accepted on 2026-08-27

**Decision:** M4 first establishes a coherent official-Flutter Material 3 product baseline across desktop and compact/mobile. Quiet, Calm, Luminous, Temporal, artwork-derived global color, signature music motion, and other theme personas remain deferred until that baseline is stable. M4 does not introduce a third-party Material 3 Expressive library or a project-owned full M3 Expressive clone.

**Consequences:** Theme, adaptive shell, page hierarchy, component consistency, interaction states, accessibility, and daily-use product cohesion are authorized M4 work. Theme-plugin infrastructure, speculative design-system frameworks, navigation/state-management replacement, and experimental identity effects are not authorized by this decision.

## HD-003 — Home-first mainstream first-release experience

**Status:** Accepted on 2026-08-27

**Context:** The post-M4 client had a deliberate Material baseline but still opened into Library and treated Discover and Search as peer destinations. The maintainer has decided that the first release should be a familiar mainstream QQ Music product rather than a deliberately Library-first or focus-oriented variant.

**Decision:** M5 establishes Home as the authenticated default, with Home, Discover, Search, and Library as distinct first-class destinations and Now Playing as persistent context. Home must stay small and truthful, composed only from stable capabilities. Library remains prominent and exposes Playlists, favorite Albums, and favorite Artists as product sections. M5 also authorizes common playback modes, a bounded Track-context audit, read-only song comments, and bounded QQ MV support after current protocol/product discovery.

**Consequences:** The agent may autonomously execute bounded Home/shell, Library-coherence, queue-mode, read-only comment, Track-context, and QQ MV slices within `PROJECT.md`, `ROADMAP.md`, and the accepted architecture. This decision does not authorize other Providers, aggregation, podcasts, downloads, social or collection mutations, background-playback lifecycle, persistent recent-history semantics, new state/navigation frameworks, or release identity/signing. A later Focus/quiet experience may reuse the mature product baseline, but it is neither implemented nor anticipated with infrastructure during M5.

## HD-004 — QQ Music-familiar Material 3 product UI

**Status:** Accepted on 2026-08-27

**Context:** The M4 foundation and M5 feature coverage are structurally complete, but manual inspection found that their user-visible effect is too subtle relative to the implementation complexity. The generic Material defaults, launcher-like Home, and narrow default desktop rail do not yet communicate a mature QQ Music client at first glance.

**Decision:** M7 may reorganize the existing product into a broadly QQ Music-familiar Material 3 experience: green-accented light/dark surfaces, deliberate desktop sidebar and top search affordance, artwork-led content hierarchy, dense music lists, compact bottom navigation, and persistent playback context. It may use current QQ Music layout conventions as product reference without copying logos, proprietary artwork, promotional content, or exact trade dress.

**Consequences:** The agent may autonomously execute bounded presentation slices over existing capabilities, beginning with the authenticated Shell and truthful Home, then Library/catalog, Search/Discover, and Now Playing/Lyrics. This decision does not authorize new QQ protocol operations, a heterogeneous personalized feed, fake recommendation data, theme personas, a new navigation/state framework, additional Providers, or a product category expansion. Manual screenshots and product-level review are required evidence for the eventual M7 checkpoint; widget tests alone are insufficient.

## HD-005 — Complexity paydown before further product expansion

**Status:** Accepted on 2026-08-27

**Decision:** Freeze new QQ Music capabilities and visual redesign while the repository completes a bounded complexity-paydown pass. Preserve existing behavior, retained state, tests, and Flutter/Rust ownership while simplifying authenticated presentation coordination, repeated dependency propagation, proven-identical mechanics, test setup, and governance ceremony. This is maintenance authority, not permission for a navigation/state framework migration, architecture rewrite, test reduction, or documentation purge.

**Consequences:** M7 remains authorized but paused and not checkpointed. The maintenance pass may autonomously perform evidence-backed refactors and governance compression within its Roadmap exit criteria. After full regression and complexity review, whole-project ranking must inspect the running product and available evidence; it must not automatically invent another milestone or resume visual work without current product authority.

## HD-006 — Home-only visual integration pass

**Status:** Accepted on 2026-08-27

**Decision:** After the complexity-paydown pass, authorize one bounded Home-only Material 3 visual integration task. Codex owns implementation and architecture; the local `agy`/Gemini workflow may provide visual critique only. The pass may use existing truthful recommendation and personal-library data, perform at most three visual review rounds, and must stop for maintainer visual acceptance before changing another page.

**Consequences:** This decision does not resume M7 globally or authorize new data, another page, Shell/navigation redesign, playback changes, theme work, framework adoption, or pixel copying. Home may receive Home-specific layout/widgets and the smallest compatible Shell/test adjustment. Final authenticated screenshots remain ephemeral because they contain current catalog and personal-library presentation; they are not committed.

## HD-007 — Directed Home composition and desktop Shell hierarchy

**Status:** Accepted on 2026-08-27

**Decision:** The focused Home pass uses QQ Music only as a composition reference and Material 3 as the implementation language. Wide desktop places the persistent Sidebar beside a Main Region that alone owns the Top Bar, page content, and active player. Home keeps the six ordered product sections supplied by the maintainer. Existing public recommendations and personal playlists may populate only truthful matching sections; unavailable program and listening-history recommendation sections must remain explicit rather than substituting unrelated data or expanding the QQ protocol.

**Consequences:** The agent may make the smallest shared Shell geometry and neutral dark-surface correction required to render this Home coherently, while preserving Home, Discover, Search, and Library navigation, retained resize state, accessibility, compact reachability, and playback ownership. This does not resume another M7 page, authorize new data/API work, or permit a UI checkpoint before maintainer visual approval.

When a decision is needed, record its context, options, blocked and unblocked work, and the current autonomous action. A pending decision blocks only its affected scope unless every legitimate task depends on it.
