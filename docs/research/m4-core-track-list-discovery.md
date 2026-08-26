# M4 Core Track List Discovery — 2026-08-27

## Evidence

- Album, Artist Tracks, and Ranking each implement the same bounded catalog interaction as separate private `ListTile` trees: position, one-line title/subtitle, play-on-activation, and an add-to-queue button. Their spacing, metadata composition, shape, and keys are nearly identical, but the implementation is copied three times.
- Playlist detail already has a richer pointer/keyboard/touch row with artwork, duration, Album/Artist context actions, and secondary-click/long-press behavior. Search also has a distinct result row with direct catalog actions. Those contextual differences are real and should not be flattened into a configuration-heavy universal row during the first slice.
- The three duplicated catalog rows currently omit artwork and duration even though `PlaylistTrackSummary` already carries both. Under the completed shell they occupy the same final content widths, so a shared compact/desktop presentation can now be tested without guessing future navigation chrome.
- Loading, empty, failure, retry, and append states are also repeated across pages, but their account and recovery semantics differ. A shared visual state panel remains useful only if it preserves those typed meanings.

## Ranked candidates

### 1. Shared dense catalog Track tile — selected

- **Provenance:** M4.3 and M4 exit criteria 1, 5, and 6.
- **User value:** Album, Artist, and Ranking Tracks gain the same predictable artwork, position, title, artist/Album metadata, duration, play target, and queue action at compact and desktop density.
- **Current problem:** three high-frequency core-browsing surfaces duplicate a visually incomplete row and can drift independently.
- **Scope:** one small Flutter presentation component over the existing `PlaylistTrackSummary`; migrate only Album, Artist Tracks, and Ranking; preserve all page controllers, paging footers, keys, play/queue callbacks, and failure behavior.
- **Acceptance criteria:** the three pages use one shared tile; 360 px and desktop layouts do not overflow; artwork failure has a local placeholder; known duration is rendered truthfully and unknown duration remains an em dash; row and queue actions remain pointer/touch/keyboard reachable; existing plus focused tests pass.
- **Effort:** Medium.
- **Risk:** extra metadata can reduce compact title width, and a shared component can become over-configurable if Search/Playlist context actions are pulled in prematurely.
- **Explicit non-goals:** migrating Playlist or Search, current-playing animation, context menus, selection/multi-select, controller/queue changes, page headers, async state panels, or a design-system package.

### 2. Shared asynchronous state panel — deferred

- **Provenance:** M4 exit criterion 7 and repeated loading/empty/error/retry layouts.
- **User value:** recovery and empty states would gain predictable hierarchy and spacing.
- **Ranking reason:** valuable, but lower-frequency than Track browsing and more likely to erase meaningful differences between anonymous catalog, authenticated account, unavailable content, and retryable failures if generalized too early.
- **Effort:** Medium.
- **Risk:** semantic over-generalization or duplicated live announcements.
- **Explicit non-goals:** one universal failure model or controller changes.

### 3. Core browsing header alignment — deferred

- **Provenance:** M4.3 and the differing Album/Artist/Ranking header/action structures.
- **User value:** titles, metadata, and primary playback actions would become more predictable.
- **Ranking reason:** headers should follow, rather than precede, the Track-density baseline and need a separate bounded audit of Album metadata and Artist sections.
- **Effort:** Medium.
- **Risk:** flattening legitimately different Album, Artist, and Ranking information.
- **Explicit non-goals:** a universal hero header or marketing-style artwork treatment.

## Selection

The shared dense catalog Track tile ranks first because it is backed by three concrete duplicate implementations, serves the highest-frequency content in those pages, and can establish one product grammar without touching navigation, protocol, queue semantics, or contextual Playlist/Search behavior. The component must stay small and accept only differences already present in the three selected surfaces.

## Outcome

Completed on 2026-08-27. Album, Artist Tracks, and Ranking now use one small Flutter `MusicTrackTile` that consistently presents position, local-or-network artwork, title/subtitle, Artist/Album metadata, known or explicitly unknown duration, play activation, and add-to-queue action at compact and desktop density. Existing page keys, callbacks, pagination footers, controllers, and typed failure behavior remain unchanged.

Focused tests cover 360 px reachability, desktop/dark density, artwork semantics, known/unknown duration, and both actions; the three consuming page suites and full project validation pass. The component did not absorb Playlist/Search context actions or listen to the frame-driven playback notifier for selected-state animation, avoiding both a configuration-heavy universal row and per-frame list rebuilds. No dependency, controller, queue, protocol, Domain, Bridge, or Rust change was introduced.
