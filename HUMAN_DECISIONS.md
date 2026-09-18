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

## HD-022 — Platform-native QQ and WeChat authorization targets

**Status:** Partially accepted on 2026-09-03

**Context:** The maintainer clarified that “desktop QQ authorization” means the QQ Connect quick-login surface used by QQ Music: a running desktop QQ exposes already signed-in account choices, the user selects an avatar, and desktop QQ supplies a one-time authorization ticket. It does not mean opening the QR payload in a generic browser. The requested mobile target likewise means authorization through installed QQ and WeChat clients, not merely dispatching an HTTPS URL.

**Accepted decision:** Desktop Fura may present the QQ Web QR beside account choices discovered from the official desktop QQ loopback quick-login service and authorize only after an explicit account selection. Local QQ identifiers and one-time tickets remain Rust-owned and redacted; presentation receives a nickname, masked account hint, and attempt-local selection index. The initial QQ/WeChat choice remains visible before any local discovery or QR request. QQ and WeChat QR remain fallback methods and Fura never collects an account password. Avatar loading may be added only without delaying account selection or exposing the raw QQ identifier outside Core.

**Requested but externally blocked:** Android/iOS should eventually offer installed-client QQ and WeChat authorization. Production integration requires an authorized application identity, matching Android package/signature, matching iOS Bundle ID/Universal Link, required privacy disclosures, and a credential exchange that Tencent permits for QQ Music access. Fura must not embed QQ Music's native application secrets or impersonate its registered package/signature. A Fura-owned social-login token must not be assumed interchangeable with a QQ Music session.

**Consequences:** HD-019 remains authoritative for the currently shipped mobile paths and password prohibition, but is superseded for desktop QQ local quick authorization. The bounded desktop candidate may be machine-tested with synthetic account data; account discovery and complete authorization remain maintainer-operated evidence. Mobile native SDK code does not start until the required identity and QQ Music exchange boundary are available.

## HD-020 — Capability-local, auth-aware QQ protocol strategy

**Status:** Accepted on 2026-09-03

**Decision:** Fura may maintain deterministic, evidence-driven protocol strategies inside `QQMusicClient` per capability, authentication state, and necessary content context. Anonymous and authenticated behavior are separate evidence surfaces. `QQMusicProvider` remains the only QQ Catalog/Account Provider, uses one credential/session owner, and keeps QQ protocol choices private from provider-api, Bridge, Flutter, Queue, playback, and the separately owned Media Source routing boundary. The maintainer explicitly switched execution to `AUTONOMOUS_DEVELOPMENT` for this bounded Core objective.

**Consequences:** Alternative QQ implementations may be researched and reimplemented as typed Rust request/decoder variants, but static similarity alone does not authorize a production fallback or a new Primary. This decision does not authorize another Provider, multi-service aggregation, dynamic plugins, a sidecar, runtime endpoint racing/learning, risk-control evasion, high-frequency account probes, or VIP/copyright/region bypass. A rate limit, security verification, credential/account/device restriction, or access-control result stops the capability rather than rotating client profiles.

## HD-021 — Safe autonomous promotion of anonymous QQ protocol strategies

**Status:** Accepted on 2026-09-03

**Decision:** Within HD-020, the agent may autonomously promote a capability-local QQ protocol candidate to deterministic production `PRIMARY` or compatibility-only `FALLBACK` when its exact request and decoder, bounded Domain completeness, identity and pagination semantics, safe failure classification, independent source evidence, deterministic fixtures, and—when relevant—an anonymous, read-only, serial, hard-budget live observation all agree. Authenticated, membership-, region-, device-, or account-dependent promotion remains Human evidence.

**Consequences:** This does not authorize stored-account automation, authenticated autonomous probes, profile rotation after risk control, endpoint racing or online learning, VIP/copyright/region bypass, another Provider, multi-service aggregation, a dynamic plugin/runtime, or a sidecar. `RateLimited`, security verification, credential/account/device restriction, access denial, and unknown upstream outcomes remain STOP results and may not trigger another protocol request.

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

## HD-018 — Recent plays and guest navigation

**Status:** Product scope authorized by the maintainer on 2026-09-08; implementation/visual acceptance pending.

**Decision:** In Human-gated regression mode, hide personal music navigation while signed out and add a Material 3 recent-plays page, using the supplied generated desktop reference and the existing Liked long-list behavior. Investigate and implement same-account QQ Music cloud-history interoperability when supported by actual protocol evidence. Extract shared loading logic where existing pages demonstrate duplication.

**Consequences:** This authorizes the specific navigation/page capability and the maintainer-directed, evidence-backed ordinary-session cloud read. The production read now uses `RecentPlayList/GetRecentPlayList` behind the existing Provider/typed Bridge and remains pending real-account Human acceptance. Cloud reporting is separately blocked: the IoT/H5 `reportRecentPlay` API is not authorization to transplant another credential environment or automate a stored account. This decision does not authorize autonomous real-account writes, video history, downloads, a new Provider, or unrelated page work. See `docs/design/recent-plays.md` and `docs/research/qqmusic-recent-plays-evidence.md`.

When a decision is needed, record its context, options, blocked and unblocked work, and the current autonomous action. A pending decision blocks only its affected scope unless every legitimate task depends on it.

## HD-023 — NetEase Cloud Music as second built-in Provider

**Status:** Accepted by explicit Human instruction on 2026-09-09.

**Decision:** QQ Music remains first-class. NetEase Cloud Music becomes the second built-in formal Provider. Switch and persist execution mode to `AUTONOMOUS_DEVELOPMENT`, work domain `CORE`. Retain current UI candidates and defer Human visual review; this neither accepts, rejects, deletes, nor authorizes editing them.

**Authorized:** independent Rust `netease-client` and `provider-netease`, existing provider-neutral Domain/API reuse, exact provider-scoped identity, a second MediaSourceResolver and minimal deterministic static composition. Research public protocol families and licenses; implement bounded anonymous Search first, public Playlist next, Album/Artist browsing, detail, lyrics, rankings/recommendations and normally authorized standard media. Use deterministic fixtures and ignored, anonymous, read-only, serial, hard-budget live evidence. After the anonymous slice, implement evidence-backed QR/session/restore/account/library/authenticated recommendation foundations; real-account confirmation remains `HUMAN_EVIDENCE_REQUIRED`. Commit logical local changes, never push.

**Excluded:** cross-Provider aggregation, fuzzy matching, automatic source substitution, shared collections/credentials, account migration, third Providers, dynamic plugins/marketplace/runtime, Node/Python/JS/Lua/WASM runtime, hosted/localhost sidecars, credential extraction, automated real login or writes, and any VIP/copyright/region bypass or third-party unlocking. Flutter/UI product integration requires separate Human authority. Unknown/risk/access-control outcomes STOP; no endpoint/profile rotation.

**Consequences:** supersedes prior QQ-only production-provider restrictions only for this second built-in Core Provider. First-class QQ behavior, in-process HTTPS architecture, opaque identities, unique credential owners, short-lived redacted media, and existing pending release/account/visual acceptance gates remain authoritative. This is real multi-Provider foundation, not a universal aggregator.

**HD-023 continuation clarification (same Human instruction):** checkpoints, commits, individual endpoint completion, or isolated Human/live blockers do not end this autonomous workstream. Before final reporting, perform the exhaustive Remaining Work Audit. Continue while any authorized item is `REMAINING_AUTONOMOUS_WORK`; ordinary implementation/test failures must be fixed, while risk outcomes stop only live probing. No automatic execution-mode switch is authorized.

## HD-024 — NetEase Core hardening and read-capability parity

**Status:** Accepted by explicit Human continuation instruction on 2026-09-09.

**Decision:** Continue HD-023 in `AUTONOMOUS_DEVELOPMENT / CORE` for one bounded hardening and provider-neutral read-parity pass. Unify all native NetEase edges behind one process-level Provider/session owner; retain a QR-confirmed credential as pending across transient account verification; add an explicit ignored Human account-read matrix; replace the unexplained 1,000-row Playlist/liked/Album ceilings with evidence-backed resource bounds; and implement current, read-only Comments, related Tracks, new songs, new Albums and exact Track-associated MV where existing neutral contracts can express the service semantics.

**Consequences:** Anonymous, serial, hard-budget live observations may support these read paths. Natural category mismatches must fail before transport rather than relabel NetEase's broader Chinese-language catalog as a narrower QQ region. Recent-history stays research-only without a current ordinary-session endpoint with clear pagination. This decision does not authorize Flutter/UI changes, Provider selection UI, account automation, writes, scrobbling, cross-Provider matching/substitution, unlock/bypass behavior, a third Provider, dynamic runtime or sidecar. Logical commits remain local; no push is authorized.

## HD-025 — Existing UI integration for built-in Providers

**Status:** Accepted by explicit Human instruction on 2026-09-12.

**Decision:** Reuse the existing Material 3 product surfaces for the two fixed
built-in Providers. Settings owns one persisted catalog/account Provider
selection, defaulting and migrating to QQ Music. NetEase Cloud Music is wired
through the same Home, Discover, Search, Library, detail, playback-adjacent and
authentication presentation rather than receiving copied pages. Provider
credentials and session owners remain independently namespaced. Changing the
selection resets provider-scoped catalog/account navigation and rejects late
results, but does not sign either Provider out, clear the Queue, stop the
current Track, or rewrite an existing provider-scoped identity. Media, lyrics,
comments, MV and related reads continue to route from the owning entity's exact
`ProviderId`. Presentation hides capabilities and mutations that the selected
or owning Provider does not implement, and uses NetEase Daily Tracks and
Personal FM only under their truthful semantics.

**Consequences:** This supersedes HD-023/HD-024 only where they deferred
Flutter integration. It authorizes a small static QQ/NetEase dispatch, a
provider-aware typed Bridge, independent secure-vault keys, NetEase QR
presentation, settings migration, capability-aware navigation and synthetic
integration tests. It does not authorize mixed Search, cross-Provider matching,
automatic source substitution, unified likes, account migration, a shared
credential, NetEase writes, a third Provider, runtime Provider discovery,
plugins, a sidecar, credential extraction, stored-account automation, real
account writes, or access-control bypass. NetEase real-account and visual/runtime
acceptance remain Human evidence. Logical commits stay local; no push is
authorized.

## HD-026 — First-party Flutter localization

**Status:** Accepted by explicit Human instruction on 2026-09-12.

**Decision:** Localize every Fura-authored user-visible Flutter string through
Flutter's official `gen_l10n` toolchain. English and Simplified Chinese are the
first supported languages. Settings owns one persisted `system`, `english`, or
`simplifiedChinese` preference, defaults existing installations to `system`,
and applies changes live without replacing Provider sessions, retained catalog
controllers, the Queue, current Track, or the app-lifetime playback host.
Provider-owned content and protocol values remain unchanged.

**Consequences:** Settings schema version 4 adds `localePreference`; versions
1–3 migrate to `system`, and an unknown version-4 locale value falls back to
`system` while retaining every other valid setting. Generic Chinese, `zh-Hans`,
`zh-CN`, and `zh-SG` resolve to Simplified Chinese. Traditional Chinese regions
and scripts currently fall back to English because no reviewed Traditional
Chinese catalog exists. Rust, generated Bridge protocol values, upstream song,
Artist, Album, Playlist, comment and lyric content, codec/quality abbreviations,
identifiers, logs, URLs, and native pre-`runApp` AudioService strings are outside
translation scope. Native startup strings remain a documented follow-up rather
than risking Android media-service initialization. Human acceptance is required
for Chinese wording and final visual rhythm; machine checks cannot self-accept
either.

## HD-027 — Bounded `webview_all` NetEase official Web-login trial

**Status:** Accepted by explicit Human instruction on 2026-09-14.

**Decision:** Fura may perform one bounded experiment with an exactly pinned
`webview_all` 1.4.x release for the official NetEase Web-login path. The trial
is Linux-first because the previous embedded-WebKit candidate repeatedly
failed in the Web process with EGL/DMA-BUF and GStreamer symptoms before
Flutter lost its device connection. It must first prove a visible page
lifecycle, native HttpOnly-cookie access, website-data cleanup and at least 50
deterministic open/close cycles. Product integration may proceed only through
the existing `OfficialWebAuthenticationGateway` / `OfficialWebLoginBroker`,
Rust browser-credential staging, account verification and NetEase-only secure
vault boundaries.

**Preserved baseline:** Direct QR, the external official QR-confirmation
handoff, and the mobile-EAPI phone-code compatibility candidate remain intact
throughout the experiment. A build or synthetic test does not promote the
candidate to the sole or primary production login method. Fura does not
collect passwords, submit SMS from the WebView layer, automate CAPTCHA or
security verification, bypass TLS, inject risk-control material, or copy the
GPL-3.0 go-musicfox implementation; that project is behavioral evidence only.

**Consequences:** `webview_all` still uses WebKitGTK 4.1 on Linux, so default
renderer stability and the earlier native crash class remain the decisive
runtime gate. Machine-complete work with real login and repeated Linux use
still unobserved ends at `HUMAN_REVIEW`. If survival requires a process-global
renderer/backend environment override, a higher supported OS minimum or a new
distribution policy, the affected scope stops at `HUMAN_DECISION`. A failed
candidate is rejected without weakening or deleting the existing external-QR
rollback path. No push is authorized by this decision.

**2026-09-14 follow-up decision:** After Human evidence reproduced the blank
page and DMA-BUF EGL-import failure, the maintainer explicitly authorized an
exact default-versus-SHM A/B and a bounded production correction if the SHM
path passed. The short A/B and deterministic local suite passed, but the
required actual-official-page soak crashed `WebKitWebProcess` after the 17th
completed page load. Under the explicitly supplied Case C rule, the SHM
production candidate is rejected and removed; no compositing-disable,
software/X11 or other renderer workaround may be stacked. Choosing a CEF/non-
WebKit Linux backend or no embedded Linux login is a new `HUMAN_DECISION`.

## HD-028 — Isolated Tauri/Wry WebKitGTK diagnostic probe

**Status:** Accepted by explicit Human instruction on 2026-09-14; bounded
diagnostic complete.

**Decision:** Create a repository-external Linux Tauri 2 / Wry probe that loads
the real official NetEase login page through its default WebKitGTK backend on
the same host/session as HD-027. Compare natural renderer behavior with only
`WEBKIT_DMABUF_RENDERER_FORCE_SHM=1`, using one sequential WebView at a time,
strict Started/Finished/resize/close/destroy counts and immediate native-crash
collection. The probe must not modify Fura production source, join its Cargo
workspace, initialize its Core/player, authenticate an account or introduce a
sidecar. Cookie capability is authorized only after at least 50 crash-free
official-page cycles.

**Observed consequence:** Tauri default visibly rendered the official page,
logged no DMA-BUF import error and completed 12 strict cycles before attempt 13
timed out waiting for `Finished`; no default core occurred. The SHM arm
completed two cycles, reached `Finished` on attempt 3 and then reproduced the
HD-027 crash class: `WebKitWebProcess`, SIGSEGV, `SkiaGPUWorker`,
`libnvidia-eglcore.so.610.57.04` and `libEGL_nvidia.so.0`. The Tauri host was
still alive when the harness detected the core and terminated it. Therefore
Flutter/`webview_all` embedding is not necessary for the fatal native crash,
although its contribution to the separate default blank/DMA-BUF behavior is
not excluded. The stop rule made the Cookie phase `NOT_RUN`; no helper or
production Tauri dependency was created. The WebKitGTK Linux embedded-login
line remains rejected, and any non-WebKit helper/backend is a new Human
decision. No push is authorized.

## HD-029 — Isolated Linux system-Chromium NetEase official login

**Status:** Accepted by explicit Human instruction on 2026-09-14; machine
candidate complete, real-account acceptance pending.

**Decision:** Linux may use an already-installed native Chromium-family browser
for official NetEase login only through a Fura-owned, attempt-scoped `0700`
profile and localhost-only ephemeral CDP. Discovery accepts a root-owned
executable under `/usr` or `/opt` in fixed Chrome/Chromium priority order. Fura
must never inspect/reuse a default profile, Cookie database, existing browser
session, extension, WebKit/CEF runtime, automation driver, TLS/sandbox bypass,
or risk-control workaround. Only exact-domain `MUSIC_U` and optional `__csrf`
may enter the Rust Provider pending-candidate path; raw values may not cross
into Dart or logs.

**Observed consequence:** The repository-external probe passed synthetic
HttpOnly Cookie capture and fresh-profile isolation, official-page no-login
smoke, and 20/20 sequential launch/CDP/official-target/clean-close/profile-
delete cycles with zero force, crash, or leftover process. The Linux production
candidate therefore replaces the rejected WebKitGTK default behind the
existing official-Web gateway. Direct/external QR and SMS remain available.
Cleanup precedes staging; transient Provider verification retains the pending
candidate for explicit retry, while rejection and cleanup failure save nothing.
The Agent did not perform a real login, so the result remains `HUMAN_REVIEW`,
not accepted account capability. See
[the HD-029 evidence](docs/research/netease-linux-system-chromium-login.md).
No push is authorized.

## HD-030 — Android physical system-playback diagnosis and completion

**Status:** Accepted by explicit Human instruction on 2026-09-14.

**Decision:** Complete the Android system-playback root-cause diagnosis,
necessary minimal repair, secret-safe diagnostics and reproducible adb/physical
acceptance flow. Observe the separate `ANDROID_SYSTEM_PLAYBACK` and
`NETEASE_ANDROID_MEDIA_PLAYBACK` branches in the same device pass, but do not
assume they share a cause. Rust remains the only positional Queue truth;
`AppPlaybackHost` remains the only playback owner; `audio_service` owns Android
MediaSession, foreground media notification and system callbacks;
`audio_session` owns focus, interruptions and becoming-noisy policy; the
existing `ForegroundAudioEngine` only decodes and outputs sound.

**Consequences:** The machine pass may audit the exactly locked plugin/native
sources, add an AudioService initialization success/failure seam, correct
conflicting focus ownership, and normalize an evidenced strict first-party
NetEase media CDN from HTTP to HTTPS while preserving path/query. It may not
replace the engine with `just_audio`, MediaKit or ExoPlayer; add another
`AudioPlayer`, Queue, handler or custom MediaSession framework; enable global
cleartext; add a proxy/source substitution; persist Queue state across process
death; add background download/autoplay; automate a real account; or change
product task/background semantics. Android notification, lock-screen,
media-button, focus/interruption, background lifecycle and real NetEase audio
progress remain `HUMAN_REVIEW` until recorded on a physical device.

## HD-031 — Third built-in KuGou Provider, public/read-first

**Status:** Accepted by explicit Human instruction on 2026-09-15.

**Decision:** Add KuGou Music as Fura's third static built-in Provider through
an independent in-process Rust implementation. Work proceeds
`AUTONOMOUS_DEVELOPMENT / MIXED`, beginning with provenance and bounded public
Core evidence, then Track Search, exact identity, public catalog, synchronized
lyrics, rankings and other existing read-only Provider traits whose current
semantics can be proved. Direct media resolution may be added only for an exact
KuGou Track when a normally authorized, directly playable source can be
independently established without encrypted-audio cracking, entitlement
escalation or another service. Machine-complete Core and bounded anonymous
compatibility evidence may then enter the existing static Bridge and Flutter
product surfaces. Authentication, private Library and account/playlist
mutation are not part of this first authorization.

**Source and license boundary:** MakcRe/KuGouMusicApi is the current MIT
wire-behavior reference. MoeKoeMusic (GPL-2.0) and EchoMusic (GPL-3.0) both
embed that implementation family as a git submodule, so they are real-client
integration/compatibility evidence but not independent wire corroboration.
KugouMusic.NET is a modern independent MIT cross-check; LX Music Desktop is an
Apache-2.0 public-catalog cross-check whose media URL path delegates elsewhere;
Listen1 is a lower-weight historical MIT cross-check; and the unlicensed
KugouMusic.rs repository is evidence-only and declares that it is based on
KugouMusic.NET. Fura may observe behavior and independently implement bounded
Rust requests/decoders, but must not copy, translate, vendor or structurally
port GPL TypeScript/Electron code or run a third-party sidecar.

**TME boundary:** QQ Music and KuGou Music may share group-level content or
infrastructure, but this is a hypothesis to test per identity, rights, media,
artwork, account, transport and catalog primitive. It does not authorize a
`provider-tme`, shared credential/session/Track identity, fuzzy mapping or
source fallback. QQ credentials and identities never enter KuGou code, KuGou
credentials and identities never enter QQ code, and any future cross-service
catalog mapping requires explicit evidence plus a separate Human decision.

**Excluded:** password/SMS/account automation, CAPTCHA or risk-control
automation, VIP claiming/trials, membership/copyright/region bypass,
official-package or device-attestation impersonation, persistent fabricated
hardware identity, encrypted-media cracking, cross-Provider matching or source
substitution, runtime Provider discovery, a plugin/marketplace, hosted or
localhost API proxy, and real-account writes. Rate limit, security verification,
unknown access control, an official private secret or required package
signature stops the affected capability. Logical commits remain local; no push
is authorized.

**Consequences:** This supersedes prior two-Provider and no-third-Provider
statements only for the exact static KuGou scope above. QQ Music remains
first-class; NetEase remains independently owned; all Provider identities,
credentials, sessions, pagination and media resolution remain exact and
provider-scoped. Public distribution and legal authorization remain a future
Human/legal decision rather than a claim established by technical integration.

## HD-032 — Upstream response integrity and partial-resilience audit

**Status:** Accepted by explicit Human instruction on 2026-09-16.

**Decision:** Audit every currently implemented QQ Music and NetEase response
boundary, plus only the already committed KuGou Track Search slice, so failure
granularity matches data risk. HTTP/body/business envelopes, required page
metadata, cursor progression, credentials, authentication/security challenges,
canonical singleton identity, authorization-bearing media and all write
confirmations remain fail-closed. Inside a valid collection container, one
isolated malformed row may be omitted only when remaining canonical identities
and raw progression remain provable. Optional presentation fields may degrade
without inventing data; malformed auxiliary lyric or translation lines may not
destroy valid original lyrics. Every omission is explicit and pagination is
based on upstream/raw positions, never the visible item count.

**Boundaries:** No generic response framework, guessed identity, repaired
business metadata, cross-provider fallback, credential/media/write relaxation,
account automation or new capability is authorized. HD-031 remains in force:
KuGou detail, catalog, lyrics, media, authentication, Bridge and Flutter work
remain outside this task, and its network budget stays closed. Small private
decoder helpers and the minimum Domain/Bridge/Flutter fields needed to carry an
omitted count are allowed. Machine completion requires malformed fixture
coverage, Rust/Flutter gates and Linux/Android ARM64 Release builds; real-account
liked/comment/lyric acceptance remains Human review. See
[the endpoint audit](docs/research/upstream-response-integrity-audit.md). Logical
commits remain local; no push is authorized.

**Machine checkpoint:** Completed on 2026-09-16. The 69 implemented boundaries
retain strict containers; all 47 collection classifications now preserve valid
rows with explicit omission/raw progression where provable, both lyric
documents are line-local, and the 12 security plus 8 singleton boundaries stay
strict. Domain, Bridge and Flutter propagation, localized/accessibility-safe
partial presentation, malformed fixtures, all Rust/Flutter tests and both
required Release builds pass. No live provider request or KuGou expansion was
made. Only naturally occurring real-account partial-response presentation
remains Human review.

## HD-033 — Playback engine and system-media adapter bake-off

**Status:** Reversible experiment accepted by explicit Human instruction on
2026-09-16; production cutover is not accepted.

**Decision:** Preserve `audioplayers 6.8.1 + audio_service 0.18.19` as the
default production baseline and regression oracle while adding independently
selectable `media_kit 1.2.6` music-engine and exact-pinned
`flutter_media_session 3.0.5` system-edge candidates. Internal compile-time
selection must express A/B/C/D without constructing two music engines or
activating two system sessions. Rust remains the canonical positional Queue;
`QueuePlaybackController` remains the application owner; all system commands
return to it; `audio_session 0.2.4` remains the sole intended focus and
interruption owner; and Linux always retains Fura's custom MPRIS edge.

**Retention boundary:** The current Audioplayers engine, AudioService handler,
Linux MPRIS, Windows AudioService edge, native registrations, dependencies, and
tests remain. MediaKit does not own a canonical playlist, Flutter Media Session
does not operate a native player directly, and neither candidate may silently
fall back to the other engine/edge and claim success. Provider resolution,
authentication, browser login, and response-integrity behavior are outside
this experiment.

**Machine checkpoint, completed 2026-09-18:** The shared engine contract, one-engine/one-edge
selection regressions, Queue command delegation, focus denial, source
replacement, completion/error, and MV ownership tests pass. Linux A/B playback,
custom MPRIS, all 645 Flutter tests, and Release builds pass. Android ARM64
Debug and Release A/B/C/D all package; the four Release APKs are each
45,412,046 bytes and have the same ARM64 native-size inventory because the
retained MV stack already ships the MediaKit runtime. No Android device was
attached, so notification, lock-screen, headset, background/task, focus/noisy,
replacement-soak, RSS, service, and single-live-session claims remain Human
runtime evidence.

**Decision required:** Exact 3.0.5 source audit found that iOS activation
unconditionally configures/activates AVAudioSession and exposes no switch to
leave focus ownership solely with `audio_session`. Fura rejects that candidate
before activation rather than hiding the conflict. Human must choose whether
to retain AudioService on iOS, accept a platform-specific split, wait for or
change the dependency, or revise the ownership rule. Until that decision and
the Android physical matrix pass, A remains the production default and no
cleanup migration is authorized. See
[the HD-033 bake-off](docs/research/playback-stack-bakeoff.md).

## HD-034 — Lyric auxiliary-track alignment and presentation

**Status:** Accepted by explicit Human instruction on 2026-09-18; real-song
content/presentation remains Human review.

**Decision:** Model Provider-supplied translation and romanization as independent
timed auxiliary tracks over the unchanged original lyric. QQ Music omits only an
exact trimmed `//` translation placeholder; it does not rewrite original,
romanization, `/`, `///`, or embedded `//`. NetEase may parse the independently
corroborated `romalrc` field alongside `lrc` and `tlyric`. Both Providers use one
small provider-neutral alignment primitive: unique exact timestamps first, then
mutually unique nearest pairs inside a conservative 10 ms bound, with one-to-one
monotonic ordering and no tie, conflict, crossing, or out-of-window guess.

Flutter persists one global `LyricAuxiliaryMode`: Auto, Translation,
Pronunciation (internal romanization), or Off. Auto chooses translation per line,
then romanization; explicit modes never substitute the other track. At most one
auxiliary text/semantics node accompanies an original line. The playback bar is
the primary responsive selector; switching changes presentation only and does
not refetch lyrics or media. Existing word timing, active original selection,
seek, follow-current and manual-scroll state remain authoritative.

**Boundaries:** Provider parsers remain independent; optional auxiliary failure
cannot erase a valid original. No language/script inference, machine translation,
cross-Provider lookup, timestamp movement, unlimited nearest match, copyrighted
fixture, lyric-content diagnostic, Provider-specific UI preference, playback
stack change, account automation, or live request is authorized. A wider
tolerance requires new sanitized evidence and review. See
[the HD-034 evidence and policy](docs/research/lyric-auxiliary-track-alignment.md).

**Machine checkpoint:** Rust format, both workspace test modes (585 passed, 27
live/Human ignored), strict all-target Clippy, Flutter localization/format/analyze,
all 652 Flutter tests, Linux Release and Android ARM64 Release pass. Machine work
is complete. Human checks one QQ Japanese Track, one QQ English Track with a
known small timestamp delta, and one NetEase Track with available auxiliary
tracks; observations retain only counts, presence and delta buckets. Commits
remain local and no push is authorized.
