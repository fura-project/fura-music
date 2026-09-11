# Discover

Status: `HUMAN_REVIEW`

Source: maintainer review on 2026-09-11. The first candidate overused filled
surfaces and oversized artwork; this correction follows the existing Liked
track list and Home media shelf instead.

## Scope

This candidate changes the presentation of the existing Discover destinations:

- Playlists
- Rankings
- Radar
- New albums
- New songs

It keeps the existing application Shell, search field, sidebar/navigation,
player overlay, tab state, lazy data loading, typed gateways, detail routes and
queue behavior. It does not reinterpret QQ Music responses or redesign ranking,
album, artist or playlist detail destinations.

## Visual hierarchy

- The page owns one large `Discover` heading and supporting copy. It collapses
  to the existing tabs-only header after downward scrolling. The page heading
  fades and contracts while the Shell title fades/slides into the top bar over
  the same 240 ms interval; reduced-motion mode performs the handoff
  immediately. The compact Shell title uses Material `titleLarge` with the same
  strong title weight instead of a secondary-label treatment.
- The title and tabs sit directly on the page canvas, matching Liked. Discover
  does not add section-description banners or a second filled header surface.
- Playlist and album items match the Home media-shelf density: artwork is about
  136--180 logical pixels rather than a page-dominant 232--240 pixels. Normal
  items have no filled backing card; only the artwork owns an ink response.
- Ranking groups use compact horizontal cards: intact artwork identifies the
  chart on the left, while the title, period and navigation affordance remain
  on a quiet tonal information pane. A bottom scrim on the artwork has one
  concrete job: it makes the Track count readable. The old broad horizontal
  fade is removed because it washed out the cover without improving text.
- Radar and New songs reuse Liked's table header and shared Track row content.
  `MusicTrackRowSurface` now also owns the 56/64 pixel row density,
  transparent/current/hover/focus treatment, focus acquisition, keyboard menu
  shortcuts and pointer gestures for Liked, ordinary playlists, Recent Plays,
  Radar and New songs. Each page still owns its data, paging and action copy;
  this intentionally avoids a flag-heavy universal list widget.
- Region/category filters use horizontally scrollable `SegmentedButton`s. The
  joined outline expresses one mutually exclusive sequence more clearly than a
  row of unrelated chips. The standard selected check is retained so these
  controls read as Material 3 segmented buttons rather than custom outlined
  tabs. Their outer Shell stays mounted while loading/content/error states
  switch inside it, so selection changes use the framework's native Material
  state animation instead of replacing two controls on top of each other.
  Segments use compact intrinsic label width inside a horizontal viewport; the
  selector does not claim the full row or collide with the separate Play
  action. The five top-level Discover destinations remain a secondary `TabBar`
  because they navigate peer content sections rather than filtering one set.
- Loading, empty and error content continues to use the shared Material state
  panels and retains the current retry/sign-in semantics.

## Adaptive behavior

- Below 760 logical pixels, media collections use two columns and Track rows
  switch to the Liked compact composition.
- At 760 logical pixels and above, content uses the shared 48 px page margin and
  is constrained to the 1180 px product content width.
- Track collections remain lazy slivers. The compact player allowance stays in
  the collection bottom padding so final rows remain reachable.
- Tabs remain horizontally scrollable at compact widths; no labels are removed
  or shortened solely to fit one viewport.

## Radar first-page behavior

Home and Discover own separate `RadarController` instances. They share the QQ
Music `GetRadarSong` gateway but do not share presentation state.

QQ Music can return a sparse first page (including one Track) while still
setting `hasMore`. Discover therefore requests at most two additional pages,
serially, only when the initial result contains fewer than ten unique Tracks.
The general controller default does not prefetch, so Home retains its existing
single-preview behavior. Once the Discover list is visible, the same
velocity/latency look-ahead policy used by Liked requests at most two more Radar
pages before the viewport reaches the end. Upward scrolling cancels pending
viewport demand. Cancellation, generation checks, deduplication and
append-error retention continue to apply.

## New-song pagination boundary

The current QQ route, `newsong.NewSongServer / get_new_song_info`, accepts the
selected category and returns one `songlist`. It exposes no offset, page,
cursor, total or `hasMore` contract. New-song rows are therefore built lazily by
the viewport, but the client does not invent network pagination or split the
response into fake pages. A true paged implementation requires a separately
evidenced QQ route with continuation semantics.

## Review artifacts

The synthetic visual fixture renders deterministic desktop and compact states
for all five sections, compact and desktop collapsed headers, and one compact
mid-transition frame. These images prove geometry, hierarchy and overflow
checks only. Real artwork, localized copy, live service density and aesthetic
acceptance remain Human review.

Playlist, Album and Ranking detail behavior opened from Discover is specified
by [Collection Detail Design](collection-details.md).
