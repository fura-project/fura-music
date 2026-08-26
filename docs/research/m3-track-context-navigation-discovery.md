# M3 Track Context Navigation Discovery — 2026-08-26

## Reproduced gap

Track Search already returns a separate `TrackSearchItem` with optional provider-neutral Album and credited-Artist identities, so its rows can open the existing catalog pages. Every other Track surface receives only `TrackSummary`/`LibraryTrackSummary`: title, artist names, Album title, artwork, duration, and opaque Track identity. Playlist, Album, Artist, Ranking, Radar, queue, and now-playing presentation therefore cannot recover an Album or Artist route without illegally parsing QQ's opaque Track ID.

This is a mapping loss, not missing upstream data. The common diagnostics-redacted `QqMusicTrackSummary` already carries optional `QqMusicAlbumSummary` and credited `QqMusicArtistSummary` values. Playlist detail, Album Tracks, Artist Tracks, rankings, Radar, and Search all construct that same protocol type before `QQMusicProvider::map_track_summary` deliberately keeps display strings but discards catalog identity. The generated `LibraryTrackSummary` and the Rust queue round-trip have no context fields, so adding context at only one Flutter gateway would be incomplete and would lose it again when queued.

## Ranked candidates

### 1. Playlist Track to Album navigation — selected

- Provenance: M3 Album browsing plus the reproduced shared Track mapping loss above. User playlists are the demonstrated real-account daily-use collection, and Search already establishes the intended provider-neutral Album transition.
- User value: a user can open the Album behind a Track directly from any existing playlist-detail origin, then return to the same loaded playlist state.
- Scope: add one optional `AlbumSummary` to shared Domain `TrackSummary`; populate it from the existing QQ protocol Album only when current identity/title validation succeeds; preserve it through the shared Bridge DTO and positional queue round-trip; expose it in the handwritten Dart Track summary; add an Album action to the existing desktop context menu/keyboard menu and mobile long-press sheet; and present the existing Album page as a retained local overlay above every playlist-detail origin.
- Acceptance criteria: absent or incomplete Album identity remains no action rather than a fabricated route; diagnostics redact identity/content; all current QQ Track producers preserve valid Album context through the shared mapper; Bridge and queue conversion preserve it exactly; playlist paging/deduplication still advances by Track rows; secondary click, Context Menu/Shift+F10, long press, and platform/AppBar back are covered; playlist controller/scroll state and queue playback survive Album open/return; strict Rust/Dart checks, Flutter tests, Linux Release, and packaged Bridge integration pass.
- Effort: medium-high but finite because the protocol and Album route already exist.
- Risk: medium. Shared Track and generated Bridge types change, so every mapper and queue conversion must be audited; the visible action remains deliberately limited to playlist detail for this slice.
- Explicit non-goals: credited-Artist navigation, visible context actions on Album/Artist/Ranking/Radar/now-playing surfaces, parsing opaque Track identity, changing queue semantics, caching, a generic navigation framework, or a mixed catalog context abstraction.

### 2. Credited-Artist context on every Track — deferred

- Provenance: M3 Artist browsing and the same mapping loss.
- User value: collaborations could open any credited Artist outside Search.
- Boundary gap: multi-credit selection needs a reusable interaction and Artist return behavior across several retained origins. Combining it with the Album slice would enlarge both the shared data change and the presentation state machine.
- Non-goals: treating display-only artist names as identities or selecting the first credit silently.

### 3. Global now-playing catalog transitions — deferred

- Provenance: M3 catalog coherence and the queue round-trip loss.
- User value: the current Track could open its Album or Artists regardless of origin.
- Boundary gap: this needs both Album and multi-Artist context plus a global retained return path above dialogs/sheets and every local surface. The selected slice preserves Album context through the queue now so later work does not need another data migration, but it does not expose speculative controls.
- Non-goals: a navigation framework, background playback, or a remote Rust UI state machine.

## Selection

Playlist Track to Album navigation is the smallest coherent user-visible slice. It fixes the shared data loss at its actual Rust/Bridge boundary, preserves the new value through the existing queue, and adds one bounded interaction to the demonstrated library journey. Artist and global now-playing transitions remain separately rankable work rather than being smuggled into this task.

## Implementation outcome

Completed on 2026-08-26. The shared Track value now retains an optional validated same-Provider Album summary from the existing QQ protocol model; generated Bridge and handwritten Dart mapping preserve it, and the Rust queue validates and returns it without changing positional semantics. Playlist detail exposes the existing Album page only when the context exists through secondary click, Context Menu/Shift+F10, or mobile long press. Album presentation overlays each current playlist origin in a retained `IndexedStack`, so platform/AppBar return restores the same loaded rows and pagination while the existing queue/playback owner remains mounted.

The full offline Rust and Flutter suites, strict formatting/static checks, Linux x64 Release build, and packaged Bridge integration passed. This evidence proves local mapping, queue round-trip, interaction, retained-navigation, and packaging behavior; it does not prove live QQ catalog compatibility or the still-pending authenticated media/queue/lyric observation.
