# M4 Adaptive App Shell Discovery — 2026-08-27

## Evidence

- The authenticated root currently mixes primary destinations (Search and Discover), saved-Library destinations (favorite Artists and Albums), the Library-local refresh action, and account sign-out in one AppBar. The prior 360 px fix preserved reachability by grouping two actions, but did not classify their product roles.
- Library, Search, and Discover are mutually exclusive top-level states owned by `UserLibraryPage`; all three already share one `QueuePlaybackController`, lyric controller, vault composition, `PageStorageBucket`, `PopScope`, and retained detail overlays. This is sufficient for a presentation-only shell without changing Domain, Bridge, controllers, or navigation framework.
- Search and Discover currently build their own `Scaffold`, AppBar, and Now Playing bar. Their content/controller lifecycles can be preserved by an embedded presentation mode and a lazy retained primary `IndexedStack`; detail/catalog pages can continue to overlay that stack with their existing full-page AppBars and return order.
- Existing tests already prove 360 px reachability, desktop focus, Search/Discover return, nested detail state, platform/desktop back, playback shortcuts, and one playback owner. They provide concrete regression constraints rather than permission for a navigation rewrite.

## Ranked candidates

### 1. Retained adaptive primary shell — selected

- **Provenance:** M4.2 and M4 exit criteria 2–4, plus the reproduced mixed-action authenticated root.
- **User value:** Library, Search, and Discover become stable named destinations instead of toolbar icons; desktop gets persistent rail navigation and compact/mobile gets thumb-reachable bottom navigation while the existing Now Playing bar remains available.
- **Current problem:** the authenticated information architecture is encoded as an expanding AppBar action row and whole-page replacement, so navigation, page actions, and account utilities are visually indistinguishable.
- **Scope:** one presentation-only primary destination enum; a wide `NavigationRail` and compact `NavigationBar`; one shell AppBar whose actions depend on the selected destination; embedded Search/Discover content; lazy retained primary pages; existing detail/favorite/catalog/expanded-now-playing overlays remain full pages above the shell.
- **Acceptance criteria:** 360 px and desktop shell render without overflow; every primary destination is pointer/touch/keyboard reachable and exposes a selected state; Search query/results and Discover loaded state survive switching through Library; Library refresh and saved collections remain Library actions, sign-out remains a utility; platform/AppBar/detail return order and focus restoration remain valid; exactly one Now Playing bar/controller exists; focused plus full validation passes.
- **Effort:** High but bounded.
- **Risk:** nested Scaffold removal and retained primary pages can regress back handling, focus ownership, lazy network loading, or duplicate playback presentation.
- **Explicit non-goals:** `go_router`/Navigator 2, new state management, changing detail/catalog overlays, rebuilding saved collections as tabs, adding a second Now Playing destination/player, protocol/Bridge/Rust changes, or page visual overhaul.

### 2. Shared dense Track row — deferred

- **Provenance:** M4.3/M4.4 and the repeated Playlist/Album/Artist/Ranking/Search/Discover Track row audit.
- **User value:** core music lists gain predictable artwork, metadata, duration, playing state, hover, and action placement.
- **Ranking reason:** high value, but row density and action placement should consume the shell's final content width and navigation chrome rather than be tuned against the temporary full-width layout.
- **Effort:** Medium–High.
- **Risk:** a universal row can erase meaningful context and become configuration-heavy.
- **Explicit non-goals:** migrating every Track surface at once or changing queue semantics.

### 3. Shared asynchronous state panel — deferred

- **Provenance:** M4 exit criteria 1 and 7 plus repeated loading/empty/error/retry messages.
- **User value:** recovery states become predictable across the product.
- **Ranking reason:** smaller and lower risk, but it does not solve the authenticated information-architecture problem and can follow the shell without rework.
- **Effort:** Medium.
- **Risk:** over-generalization can merge distinct account, unavailable, and retry semantics.
- **Explicit non-goals:** one universal error model or controller changes.

## Selection

The retained adaptive primary shell ranks first because the toolbar conflict is already reproduced, the current presentation owner supplies the necessary shared lifecycles, and the completed Material foundation removes the need for local shell styling. The implementation must retain current primary controllers and overlay behavior rather than replacing navigation infrastructure.
