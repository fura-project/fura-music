# M4 Material Product Discovery — 2026-08-27

## Audit boundary

This bounded pass inspected the current `ThemeData`, signed-out authentication surface, authenticated `UserLibraryPage` owner and retained `IndexedStack` routing, Library/Playlist/Search/Discover/Album/Artist/Now Playing/Queue/Lyrics presentation, adaptive thresholds, and existing 360 px, desktop, keyboard, pointer, touch, focus, loading, empty, error, and retry regressions. It did not call QQ Music, read stored credentials, run a live account flow, or propose a navigation-framework replacement.

## Inventory findings

- The application enables Material 3 with one seeded light/dark `ColorScheme`, but has no centralized typography, shape, surface, spacing, or component-theme baseline and no focused light/dark theme regression.
- Current colors are generally scheme-derived; the few hard-coded black/white values are bounded artwork-overlay contrast treatments. The larger inconsistency is repeated local shape, spacing, duration, title-weight, list-row, and state-message decisions.
- Authentication, Library, Search, Discover, Playlist, Album, Artist, Ranking, and expanded Now Playing each own a `Scaffold`/`AppBar`. The authenticated root mixes saved-collection navigation, Discover, Search, refresh, and sign-out in one action row; the existing compact menu fixes reachability but not the underlying navigation/action classification.
- Existing pages already use meaningful adaptive layouts and content constraints, but thresholds are locally chosen across 520, 600, 760, 820, 860, and 900 px. This is not automatically wrong; shell/content responsibilities need to be made explicit before consolidating breakpoints.
- Track/list and loading/empty/error/retry presentation is repeated across Playlist, Album, Artist, Search, Rankings, Radar/New Songs, Queue, and Lyrics. A later shared product vocabulary can reduce drift, but replacing every row or state at once would be an unsafe broad rewrite.
- Existing retained state, focus restoration, context actions, semantics, shortcuts, and 360 px coverage are valuable constraints. M4 must compose around them rather than treating complex-looking local navigation as disposable.

## Ranked candidates

### 1. Default Material foundation — selected

- **Provenance:** M4.1 and M4 exit criteria 1, 4, 6, and 7; the audited Theme is only a seed scheme plus `useMaterial3` while representative pages repeat visual constants.
- **User value:** every current and later page receives predictable light/dark surfaces, typography, controls, focus/hover states, and spacing instead of accumulating another local visual dialect.
- **Current problem:** there is no single product-level Material baseline against which App Shell and page consolidation can be implemented or reviewed.
- **Scope:** move theme creation out of `app.dart`; define a small official-Flutter Material theme and only the spacing/shape/motion tokens already repeated; set baseline themes for current AppBars, buttons, inputs, menus, dialogs/sheets, list tiles, and progress/divider surfaces; migrate the signed-out authentication panel and authenticated Library collection as two representative consumers.
- **Acceptance criteria:** light and dark themes expose the same semantic rules; representative surfaces no longer own their baseline panel/list shapes and page spacing as anonymous values; existing signed-out, 360 px Library, desktop Library, semantics, focus, and navigation regressions pass; focused tests prove both brightness variants and component defaults; no new dependency or framework appears.
- **Effort:** Medium.
- **Risk:** broad component defaults can unintentionally change hit targets, density, or contrast across existing pages; keep defaults conservative and verify current widget flows before wider migration.
- **Explicit non-goals:** App Shell navigation redesign, wholesale page migration, pixel-perfect goldens, custom fonts, theme personas, artwork palettes, expressive clones, protocol/Bridge/Rust changes, or state/navigation frameworks.

### 2. Adaptive authenticated App Shell — next foundation consumer

- **Provenance:** M4.2 and M4 exit criteria 2–4; the authenticated root currently exposes six mixed navigation/utility actions and every local destination repeats its own top bar.
- **User value:** Library, Search, Discover, and Now Playing gain stable, predictable entry points appropriate to desktop and compact/mobile without toolbar hunting.
- **Current problem:** navigation actions, page-local refresh, and account utility actions share the same AppBar, while wide layouts have no persistent desktop navigation.
- **Scope:** classify existing destinations/actions, add one retained adaptive shell around the current local route owner, and preserve controllers, back order, focus restoration, and the one playback owner.
- **Acceptance criteria:** wide and compact primary navigation is explicit; refresh/sign-out remain utilities; 360 px, resize, keyboard, pointer/touch, back, and retained-state regressions pass without reloading current controllers.
- **Effort:** High.
- **Risk:** high retained-state and focus regression risk; the selected Material foundation should land first so shell work does not invent its visual contract locally.
- **Explicit non-goals:** `go_router`, Navigator 2 migration, new state management, protocol changes, or changing existing product destinations.

### 3. Shared music content and state vocabulary — deferred until shell direction is stable

- **Provenance:** M4.3–M4.5 and M4 exit criteria 1, 5, and 7; the audit found repeated Track rows and independent loading/empty/error/retry messages across core journeys.
- **User value:** dense music content and recovery states become predictable across Library, catalog, discovery, queue, and lyrics.
- **Current problem:** visually similar rows and messages use separate shapes, spacing, action placement, and metadata hierarchy, making the product feel assembled screen by screen.
- **Scope:** one bounded primitive at a time, beginning with a representative high-frequency Track row or state panel after shell and foundation rules are available.
- **Acceptance criteria:** the chosen primitive serves at least two real existing surfaces without hiding their semantic or interaction differences; compact/desktop density and existing actions remain covered.
- **Effort:** Medium–High.
- **Risk:** a universal row/state abstraction can erase meaningful page differences or create an overly configurable framework.
- **Explicit non-goals:** migrating every screen in one task, universal content-card schemas, heterogeneous Home, or generic design-system infrastructure.

## Selection

The Default Material foundation ranks first because it is the smallest common prerequisite, directly addresses the audited absence of a product theme, and reduces visual rework before the higher-risk App Shell change. Its first implementation remains deliberately representative rather than repository-wide.
