# M5 Bounded Discovery — 2026-08-27

## Boundary

This discovery follows HD-003 and the active M5 Roadmap. It inspected the current authenticated Flutter shell, retained Library/Search/Discover navigation, favorite-collection ownership, the shared playback coordinator, Rust queue semantics, and focused widget coverage. It did not access stored credentials, call QQ Music, invent a feed contract, or treat protocol-facing Comments/MV work as implementation-ready without separate evidence.

## Ranked candidates

### 1. M5.1 — Home-first authenticated shell foundation

**Provenance:** HD-003; M5 exit criteria 1, 2, 7, and 8.

**User value:** A signed-in listener arrives at a useful product overview and can move predictably among Home, Discover, Search, and Library while the current Track remains persistent context.

**Current problem:** `_PrimaryDestination` contains only Library, Discover, and Search; Library is the implicit fallback/default. Discover already owns five stable typed QQ-native surfaces, Search owns four typed result paths, Library owns playlists plus two retained favorite collections, and `UserLibraryPage` already owns the one shared queue/playback/lyric coordinator. The product has enough truthful capabilities for a bounded Home, but no Home destination organizes them.

**Scope:** Add Home as the default primary destination and a presentation-only page with a small set of honest entry points into the existing Library, Discover, and Search journeys. Preserve the existing lazy retained stacks, overlays, focus behavior, and one playback owner.

**Acceptance criteria:**

- Home is the authenticated default on compact and desktop layouts.
- Home, Discover, Search, and Library are all reachable as primary destinations without compact overflow.
- Home contains useful entry points backed only by existing capabilities; it does not claim personalization, recent-history persistence, or introduce a feed API.
- Search and Discover retain their loaded state across Home/destination changes and resize.
- Back from a primary peer returns to Home; local details still unwind to their exact retained origin.
- The existing `NowPlayingBar` remains the only persistent transport and queue owner.
- Focused 360 px, desktop, navigation-retention, back, and accessibility regressions pass.

**Effort:** Medium.

**Major risk:** Changing the implicit Library fallback affects back/focus assumptions across a deeply retained local overlay stack. The change must be limited to primary-destination state and must not replace the current navigation architecture.

**Explicit non-goals:** Dynamic/personalized shelves, recent history, new Provider calls, a navigation framework, Library section restructuring, playback-mode semantics, or protocol work.

### 2. M5.2 — Coherent Library sections

**Provenance:** HD-003; M5 exit criteria 3 and 7.

**User value:** Playlists, favorite Albums, and favorite Artists become obvious parts of “My Music” instead of two collections being toolbar utilities that are folded into a compact popup.

**Current problem:** `_libraryBody()` presents only playlists. Favorite Albums and Artists have capable independent retained controllers, pagination, credential/failure states, focus restoration, and nested detail paths, but their entry points are AppBar actions and a compact popup rather than product sections.

**Scope:** Introduce a clear Library-level section selector or overview while reusing—not merging—the three existing controllers and their retained stacks.

**Acceptance criteria:** All three sections are directly discoverable at 360 px and desktop widths; each keeps independent loading/error/paging/scroll/focus/detail-return state; account replacement/rejection remains exact; no giant Library controller or generic collection union is introduced.

**Effort:** High.

**Major risk:** A superficial visual merge could accidentally recreate controller state, lose scroll/focus return, or weaken collection-specific credential failure behavior.

**Explicit non-goals:** Favorite/playlist mutation, automatic refresh/cache, generic collection infrastructure, or shell/navigation replacement.

### 3. M5.3 — Authoritative playback modes

**Provenance:** HD-003; M5 exit criteria 4 and 7.

**User value:** Sequential, repeat-all, repeat-one, and shuffle are expected daily playback controls and make the existing queue substantially more usable.

**Current problem:** `music-domain::PlaybackQueue` explicitly excludes repeat/shuffle, exposes only linear `has_previous`/`has_next`, and advances completion to the next physical position. The Bridge snapshot, Dart gateway, controller, and transport UI carry no playback mode.

**Scope:** Define queue-mode and traversal semantics in Rust, expose them through the existing coarse queue handle, and add one accessible Flutter mode control without creating a second queue or audio owner.

**Acceptance criteria:** All four modes have deterministic provider-neutral domain tests; manual next/previous and automatic completion semantics are explicit; shuffle handles duplicates and queue mutations without losing positional identity; the Bridge/Dart snapshot validates mode; the existing controller and transport remain the only owners; compact/desktop controls expose clear selected semantics.

**Effort:** High.

**Major risk:** Shuffle history, duplicate positions, current-track removal, queue replacement, and automatic completion can produce subtle disagreement between Rust state and audio completion if semantics are not specified before implementation.

**Explicit non-goals:** Queue persistence, radio/autoplay, crossfade, background lifecycle, media-session expansion, or audio-engine replacement.

## Selection

M5.1 ranks first. HD-003 makes Home the first-release default, and the current repository already contains enough stable, truthful destinations to implement a useful bounded Home without protocol discovery. Establishing the primary information architecture first also prevents the later Library and playback-mode surfaces from being placed against a temporary root. M5.2 follows because it completes the personal collection model; M5.3 follows because it adds high daily-use value but is independent of the immediate root-destination correction.
