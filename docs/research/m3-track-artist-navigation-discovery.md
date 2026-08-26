# M3 Track Artist Navigation Discovery — 2026-08-26

## Evidence

The repository-wide Track context audit already proved that every current QQ Track producer uses the same diagnostics-redacted `QqMusicTrackSummary`. That protocol value retains each credited Artist's optional numeric ID, MID, and required display name, while `QQMusicProvider::map_track_summary` currently reduces the credits to display-only names. Track Search separately maps the same validated credits into provider-neutral `ArtistSummary` values and demonstrates the existing Artist Tracks/Albums route plus explicit collaboration selection. Playlist, Album, Artist, Ranking, Radar, queue, and now-playing values lose those identities at the shared Domain mapping boundary and cannot recover them without illegally parsing opaque Track identity or guessing from names.

No QQ protocol change, real-account access, or new Provider is required. This is an existing-data product-coherence gap inside the authorized M3 Artist and richer-library direction.

## Ranked candidates

### 1. Playlist Track to credited Artist navigation — selected

- Provenance: authorized M3 Artist browsing, the reproduced shared Track mapping loss, and the demonstrated real-account user-playlist journey.
- User value: a user can select any credited Artist behind a playlist Track, browse the existing Artist Tracks/Albums, optionally open one of that Artist's Albums, and return to the same loaded playlist state.
- Scope: add validated credited Artists to shared Domain `TrackSummary`; populate them in the existing QQ Track mapper; preserve them through the shared Bridge DTO, handwritten Dart Track value, and Rust queue round-trip; reuse one presentation-safe Artist model; expose a bounded Artist action through existing playlist desktop/mobile context surfaces; and retain Artist plus nested existing Album presentation above every playlist-detail origin.
- Acceptance criteria: missing/incomplete Artist identity produces no fabricated action; every valid credit remains selectable rather than silently choosing the first; malformed or cross-Provider context is rejected at the Dart and queue boundaries; diagnostics redact names and identity; platform/AppBar return restores Artist → playlist or Album → Artist → playlist without reloading existing state; queue/playback ownership survives; strict Rust/Dart checks, offline suites, Linux Release, and packaged Bridge integration pass.
- Effort: medium-high but finite; the protocol fields, provider-neutral Artist model, Artist page, Album nesting, and context-action surfaces already exist.
- Risk: medium. Shared Track/Bridge/queue types change again, and collaboration selection must remain usable without creating a generic navigation or action framework.
- Explicit non-goals: Artist actions on non-playlist Track surfaces, Album-metadata Artist links, global now-playing navigation, Artist biography/follow, parsing display names or opaque IDs, new queue semantics, caching, or a navigation framework.

### 2. Album metadata to credited Artist navigation — deferred

- Provenance: Album details already expose provider-neutral credited Artists and M3 authorizes Album/Artist coherence.
- User value: every current Album origin could reach its credited Artist.
- Boundary gap: Album origins include Search, Artist nesting, Discover, favorites, and playlist Track context; correct cyclic return behavior deserves a separately bounded route audit rather than being merged into shared Track identity work.
- Non-goals: silently selecting one credit or rewriting current local navigation.

### 3. Global now-playing catalog navigation — deferred

- Provenance: M3 catalog coherence and the shared queue context.
- User value: catalog navigation would be reachable regardless of Track origin.
- Boundary gap: this requires a global retained route above every local page plus dialogs/sheets, and should follow proven Album and Artist context behavior rather than expanding the current queue owner speculatively.
- Non-goals: a navigation framework, background playback, or Rust-owned UI state.

## Selection

Playlist Track to credited Artist navigation ranks first because it connects the existing Artist product slice to the demonstrated daily-use library path, fixes the data loss at its actual shared boundary, and can reuse the exact local-overlay behavior just validated for Album context. The visible action remains limited to playlist detail so this task does not automatically turn every Track surface into another presentation-polish project.
