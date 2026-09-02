# Human Decisions

## HD-001 — Release identity and signing custody

**Status:** Partially accepted on 2026-09-02

**Context:** M1 packaging has produced development Android and Linux artifacts, so TD-002's packaging trigger is satisfied. Android release builds still use development signing and the platform shells still use generated identity. HD-015 permits only short-lived, manually requested GitHub Actions test artifacts; no production artifact or release channel has been authorized.

**Accepted decision:** The final product/display name is `fura music` (HD-018). This name may be applied to user-visible application chrome and platform display metadata without changing internal package or binary identifiers.

**Decision still needed:** The human maintainer defines per-platform application identifiers and the secret-safe ownership and custody workflow for release signing keys before external distribution.

**Options:**

1. Keep the existing development application identifiers and define signing custody.
2. Choose final production application identifiers and define signing custody before release setup.

**Blocked work:**

- Resolving TD-002.
- Production release identity and signing setup.
- Production release or distribution outside HD-015's bounded development-test workflow.

**Not blocked:**

- The remaining M1 real-account playback, queue, and lyric acceptance observation.
- Evidence-backed post-M4 reliability, accessibility, and daily-use work within the Roadmap.
- Development-signed local builds and tests.
- The short-lived maintainer-test artifacts explicitly authorized by HD-015.
- Evidence-backed QQ Music Provider/Core work within the Roadmap.

**Current agent action:** Continue any independently evidenced Roadmap work when available and keep generated or development-signed artifacts development-only.

## HD-018 — fura music product display name

**Status:** Accepted on 2026-09-02

**Decision:** The product is formally named `fura music`. User-visible application titles, brand copy, and platform display-name metadata use this name. The existing repository, Dart package, Rust crate, executable/build-target, application-ID, Settings storage-key, and signing identifiers remain unchanged unless separately authorized.

**Consequences:** Product-facing UI and documentation may adopt `fura music` immediately. This decision partially resolves HD-001's name question but does not authorize application-ID migration, signing-key custody, production release, or compatibility-breaking storage/package renames.

## HD-019 — QR-only direct account authorization

**Status:** Accepted on 2026-09-02

**Decision:** Direct account authorization in the first-release client uses QQ Web QR and WeChat Web QR. Remove the unverified phone/SMS one-time-code path from production Core, Bridge, Flutter presentation, and acceptance scheduling; the client continues not to collect account passwords.

**Consequences:** Historical phone-login research may remain as clearly dated evidence, but it is not a current capability or pending compatibility claim. A maintainer-operated confirmed QR approval is still required for live QQ credential-exchange and restore evidence, and no QR credential or account material may be retained in fixtures or diagnostics.

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

## HD-008 — First-release core capability completion before further UI work

**Status:** Accepted on 2026-08-27

**Decision:** Pause Home and all other page-level visual redesign. Audit and complete the finite mainstream first-release capability foundation across Account, truthful Home data, Personal Library, Playback/media, Catalog, Settings, Platform integration, Comments, and Track-associated MV before returning to page-by-page UI work. This authorizes bounded protocol discovery, safe read capabilities, typed offline remote-mutation semantics, and a local Settings foundation. It does not authorize stored-account automation or autonomous real-account writes.

**Consequences:** M7 remains paused without being rejected. The active workstream may implement one evidenced capability at a time within the existing Flutter/Rust/Bridge boundaries. A first-release capability checkpoint is core readiness for later product UI, not visual acceptance or release readiness. Background playback remains a separate product decision because it would add a material lifecycle/platform architecture; Popular Programs also requires boundary confirmation if it would turn the client into a podcast/general-media product.

**Fulfilled condition:** The first-release Core capability checkpoint on 2026-08-28 satisfied this decision's finite readiness purpose. HD-008 remains historical evidence; it no longer pauses the separately authorized page-by-page UI work in HD-009.

## HD-009 — Design-source-driven page-by-page UI implementation

**Status:** Accepted on 2026-08-28

**Decision:** The first-release Core capability checkpoint is sufficient to resume M7 one page at a time. For each page, a Human-approved Stitch/Figma design defines the visual composition; Codex implements it over truthful production data and the existing architecture, applies a bounded Material 3 quality review, and then stops for maintainer visual acceptance. Home is the first active page, and no other page starts before Home is accepted.

**Consequences:** Human-approved design sources are valid presentation-task provenance and must not be replaced with a generic layout merely because it is easier to implement or test. Clearly synthetic design fixtures are permitted, but production UI must remain truthful. This decision authorizes no new Provider, state or navigation framework, speculative visual framework, product category, or change to Flutter/Rust ownership.

**Authority model note:** HD-009 uses the domain-specific model routed by `AGENTS.md`: Core work retains high implementation autonomy under evidence and architecture, while UI work uses controlled, design-source-driven implementation autonomy under `docs/agent/ui-development.md`.

## HD-010 — Defer Home and activate Liked Songs visual integration

**Status:** Accepted on 2026-08-28

**Decision:** Keep the current Home candidate implemented but unaccepted, pause further Home correction, and make the Human-approved Stitch Liked Songs desktop screen the active M7 page. The maintainer's accompanying official QQ Music screenshot is information-architecture reference only. The approved Material 3 reinterpretation controls visual composition.

**Consequences:** This decision supersedes only HD-009's local requirement to accept Home before another page starts. Liked Songs may use the existing built-in liked-song capability and the smallest typed provider-neutral semantic needed to identify it without parsing QQ identity in Flutter. No new QQ endpoint, download/audiobook/video collection, navigation framework, state framework, Provider, or product category is authorized. With no approved compact frame, Codex may derive a bounded adaptive Material 3 translation that still requires maintainer visual acceptance. Home remains pending rather than accepted, rejected, deleted, or checkpointed.

## HD-011 — Resume Home for truthful real-data integration

**Status:** Accepted on 2026-08-29

**Decision:** Resume the pending Home candidate for a bounded real-data integration pass. Grey or missing artwork in the approved Stitch reference reflects unavailable design assets, not intended production placeholders. Every supported production slot must use its exact existing QQ Music capability and returned artwork/content: public recommendations, Daily 30, personalized Playlists, personalized Tracks, and Radar. Generic recommendations must not masquerade as Daily or Radar.

**Consequences:** Home becomes the active visual-review candidate and the implemented Liked Songs candidate remains intact but unaccepted. Popular Programs and a second independent personalized Track set remain unsupported and may not be fabricated, copied, or replaced with unrelated data. This decision authorizes no new endpoint, podcast capability, Provider, navigation/state framework, Shell redesign, or Core redesign.

## HD-012 — Redirect visual integration to artwork-led Now Playing

**Status:** Accepted on 2026-08-29

**Decision:** Leave Home and Liked Songs implemented but unaccepted, and make Expanded Now Playing the active M7 visual-review page. The maintainer-supplied frame is composition reference rather than a pixel-copy target. The page may derive a page-local official Material 3 color scheme from the current album artwork for both light and dark modes, while preserving the existing playback, Queue, lyrics, Comments, and Track-associated MV paths.

**Consequences:** Artwork color is limited to the active Expanded Now Playing subtree and does not establish a global theme persona or override HD-002's deferral of artwork-derived global color. This decision authorizes no Core/protocol change, second player, navigation/state framework change, Home/Shell redesign, or unrelated page work. The candidate remains pending maintainer visual acceptance.

## HD-013 — Remove programs from Home and use current-Track related listening

**Status:** Accepted on 2026-08-29

**Decision:** Popular Programs is outside the first-release Home and is removed rather than represented by an unavailable placeholder or a podcast/program capability. `More from your listening` remains a distinct Home slot, seeded only by the current QQ Music Track and backed by a narrow related-Track read; the existing authenticated personalized Track set may not be reused or relabeled for it.

**Consequences:** This supersedes HD-007 and HD-011 only where they required an explicit Popular Programs placeholder or treated the second Track slot as necessarily unavailable. A missing seed, empty related result, or typed failure stays truthful and compact. This decision does not authorize podcasts, persistent listening-history semantics, autoplay radio, a second personalized feed, another Provider, Shell/navigation redesign, or work on another page. Home must render a canonical wide and compact candidate and then stop for maintainer visual review.

## HD-014 — Cross-platform system playback adaptation

**Status:** Accepted on 2026-08-31

**Context:** Foreground music playback, one Rust positional Queue, transport modes, seek, and focused-window media shortcuts already exist, but lock-screen/notification, desktop media-session, headset-button, audio-focus, and background-lifecycle integration were intentionally deferred for separate product authority.

**Decision:** Authorize one bounded system-playback capability for Android, iOS, macOS, Linux, and Windows. Native media surfaces must remain thin adapters over the existing Flutter playback controller and Rust Queue; they may publish provider-neutral current metadata/state and delegate native transport, seek, shuffle, and repeat commands only where the target supports them. Android/iOS may keep active music alive through their standard media background facilities. Audio focus/interruption and unplugged-output events must pause safely rather than inventing resume policy.

**Consequences:** This supersedes earlier background/system-playback deferrals only for music playback. It does not authorize a second player, duplicate Queue/resolver, persistent Queue/history, background downloading, autoplay radio, background MV/video, raw QQ protocol in Dart, a sidecar, release identity/signing, or claims about an untested target. Per-platform packaging and runtime evidence remain independent, and current adapter limitations must stay visible.

## HD-015 — Short-lived cross-platform CI test artifacts

**Status:** Accepted on 2026-08-31

**Context:** Linux and Android development packaging can be exercised locally, but macOS, iOS, and Windows need their matching build hosts before the maintainer can test the application and system-playback integrations on those platforms.

**Decision:** Authorize one manual GitHub Actions workflow to run the offline quality gate and upload seven-day development test artifacts for Android ARM64/x64, Linux x64, Windows x64, the hosted macOS architecture, and the hosted iOS Simulator architecture. Artifacts must retain an explicit development-only boundary and toolchain record. The workflow may not create a GitHub Release, publish to a store, use production signing secrets, automate account access, or run on every push.

**Consequences:** This supersedes HD-001 only for the narrow, short-lived maintainer testing channel above. It does not decide final product identity, application identifiers, signing custody, notarization, physical iOS provisioning, public release distribution, or the native-video notice work in TD-006. A successful job proves only the named build/test boundary; runtime acceptance remains independent on each target.

## HD-016 — Media Source Separation

**Status:** Accepted on 2026-09-01

**Decision:** Separate immediate-playback Media Source Resolution from Catalog/Account Provider ownership. QQ Music remains the default bundled first-class Catalog/Account Provider and also supplies the only bundled production Media Source Resolver. Flutter consumes one typed provider-neutral playback-resolution Bridge, while Rust Core owns source routing and QQ-owned code retains QQ identity, authorization, protocol, and fallback behavior. The maintainer explicitly switches execution mode to `AUTONOMOUS_DEVELOPMENT` for this bounded objective.

**Consequences:** A future real Media Source Resolver requires separate Human product authority. This decision does not authorize a broad aggregator, another production music service, cross-service Track matching, universal Track identity, dynamic plugins, a marketplace, runtime source discovery/install/update, a sidecar, or authorization/DRM bypass. Queue, playback-engine, and system-playback ownership remain unchanged.

## HD-017 — Signed-out Home uses truthful public recommendations

**Status:** Accepted on 2026-09-01

**Decision:** When no QQ account is active, Home replaces unavailable account-only Daily 30, Radar, personalized Playlist, and personalized Track presentation with existing anonymous QQ Music public recommendations and public new songs. These surfaces use public labels such as `Popular playlist`, `Popular playlists`, and `New songs`; they must not imply personalization. The authenticated Home composition and capability mapping remain unchanged.

**Consequences:** This supersedes HD-011 only for signed-out Home presentation. It authorizes no new QQ endpoint, fake Daily/Radar content, listening-history inference, additional Provider, Shell/navigation redesign, or generic feed framework. Public recommendation and new-song failures remain truthful and retryable, and guest playback keeps the existing availability and authorization rules.

When a decision is needed, record its context, options, blocked and unblocked work, and the current autonomous action. A pending decision blocks only its affected scope unless every legitimate task depends on it.
