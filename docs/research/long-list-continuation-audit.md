# Long-list continuation audit

Date: 2026-09-18
Decision: HD-035

## Invariants

`VISIBLE_COUNT IS NOT A CURSOR.` A Provider window that consumed 20 raw
positions advances by 20 even when one row was omitted and another exact
identity was deduplicated before presentation. Flutter may validate a typed
continuation, but it never reconstructs one from visible rows.

Likewise, one user or viewport demand must not drain an unbounded remote
collection. Normal scrolling emits one page demand. Progressive local
collection search receives at most two upstream pages per demand, including a
page already in flight. A later scroll or explicit Continue action can grant a
new bounded window.

## Inventory

| Surface | Provider contract | Protocol pagination kind | Flutter controller | Cursor owner | Current next calculation | Row omission possible | Dedup possible | Correct after omission? | Needs fix? | Tests |
|---|---|---|---|---|---|---|---|---|---|---|
| Playlist detail / Liked Songs | `PlaylistTracksProvider` -> Bridge page `next_offset` | RAW_OFFSET / IDENTITY_CURSOR selected inside Provider | `PagedTracksController` / `PlaylistDetailController` | Provider/Core and Bridge | exact `result.nextOffset` | yes | exact Track identity in Flutter | yes | fixed | raw 100-page advance, omitted-only page, non-advancing rejection, retry same cursor, dedup cursor |
| Recent Plays | `RecentTracksProvider` -> typed `next_offset` | RAW_OFFSET | `PagedTracksController` | Provider/Core and Bridge | exact `result.nextOffset` | yes | exact Track identity | yes | fixed/shared | shared paged-controller and Recent widget regressions |
| Favorite Albums | `FavoriteAlbumsProvider` page | RAW_OFFSET | `FavoriteAlbumController` | Provider/Core and Bridge | exact `continuationOffset` | yes | exact Album identity | yes | fixed | controller raw rows/dedup/retry; gateway Bridge mapping |
| Favorite Artists | `FavoriteArtistsProvider` page | RAW_OFFSET | `FavoriteArtistController` | Provider/Core and Bridge | exact `continuationOffset` | yes | exact Artist identity | yes | fixed | controller raw rows/dedup/retry; gateway Bridge mapping |
| Album Tracks | `AlbumTracksProvider` page | RAW_OFFSET | `AlbumController` | Provider/Core and Bridge | exact `continuationOffset` | yes | exact Track identity | yes | fixed | omitted upstream row advances from 0 to 2; retry retains rows |
| Artist Tracks | `ArtistTracksProvider` page | RAW_OFFSET | `ArtistController` | Provider/Core and Bridge | exact `continuationOffset` | yes | exact Track identity | yes | fixed | pagination/dedup/retry/cancellation |
| Artist Albums | `ArtistAlbumsProvider` page | RAW_OFFSET | `ArtistAlbumController` | Provider/Core and Bridge | exact `continuationOffset` | yes | exact Album identity | yes | fixed | empty/invalid separation, pagination/dedup/retry |
| Rankings | `RankingsProvider` Track page | RAW_OFFSET | `RankingTrackController` | Provider/Core and Bridge | exact `continuationOffset` | yes | exact Track identity | yes | fixed | pagination/dedup/append retry/cancellation |
| Recommended Playlists | `RecommendedPlaylistsProvider` page | RAW_OFFSET | `RecommendedPlaylistController` | Provider/Core and Bridge | exact `continuationOffset` | yes | exact Playlist identity | yes | fixed | raw progression/dedup/retry/cancellation |
| New Albums | `NewAlbumsProvider` page | RAW_OFFSET | `NewAlbumController` | Provider/Core and Bridge | exact `continuationOffset` | yes | exact Album identity | yes | fixed | region paging/dedup/retry/cancellation |
| Radar | `RadarProvider` Track page | PAGE_NUMBER | `RadarController` | Provider/Core validates returned page; Flutter advances validated page by one | `returnedPage + 1` while `hasMore` | yes | exact Track identity | yes | no new cursor fix | focused page/omission/prefetch tests |
| Track Search | `TrackSearchProvider` page | PAGE_NUMBER | `TrackSearchController` | Provider/Core validates returned page; Flutter advances validated page by one | `expectedPage + 1` independent of visible count | yes | exact Track identity | yes | viewport wiring added | content/empty, short/omitted page, dedup, failure/retry, stale query |
| Artist Search | `ArtistSearchProvider` page | PAGE_NUMBER | `ArtistSearchController` | same | `expectedPage + 1` | yes | exact Artist identity | yes | viewport wiring added | content/empty, pagination/dedup, failure/retry, stale query |
| Album Search | `AlbumSearchProvider` page | PAGE_NUMBER | `AlbumSearchController` | same | `expectedPage + 1` | yes | exact Album identity | yes | viewport wiring added | content/empty, pagination/dedup, failure/retry, stale query |
| Playlist Search | `PlaylistSearchProvider` page | PAGE_NUMBER | `PlaylistSearchController` | same | `expectedPage + 1` | yes | exact Playlist identity | yes | viewport wiring added | content/empty, short page, failure/retry, stale query |
| Track Comments | `TrackCommentsProvider` page | PAGE_NUMBER for QQ, RAW_OFFSET for NetEase; normalized to typed raw offset | `TrackCommentController` | Provider/Core and Bridge | exact `nextOffset` | yes, including all newest rows | exact comment identity | yes | fixed + viewport wiring | all-omitted advancing page, hot-only-first-page, retry same cursor, rapid single flight, near-end widget load |
| New Songs | `NewSongsProvider` bounded collection | WHOLE_RESPONSE | `NewSongController` | no cursor | none | yes | no cross-page dedup | not applicable | none | whole-response validation tests |
| User playlists / account library | `UserPlaylistsProvider` complete bounded collection | WHOLE_RESPONSE at Flutter boundary; Provider internally owns bounded pages | `LibraryController` | Provider | none exposed to Flutter | yes where Provider supports it | Provider exact Playlist identity | yes at boundary | none | library load/retry/replacement tests |
| Related Tracks | `RelatedTracksProvider` bounded batch | WHOLE_RESPONSE | Roam orchestration only | Provider | no cursor; new request only at the next true terminal | yes | exact identity filtered before Queue extension | not applicable | Roam wiring added | same-Provider, dedup, failure, cancellation, repeated-terminal tests |

No production result DTO in these raw-offset surfaces derives a continuation
from `items.length`, `tracks.length`, `albums.length`, `artists.length`,
`releases.length`, or a post-dedup count. A missing typed continuation uses the
invalid sentinel and is rejected by the controller validator. The Bridge-backed
gateways always populate it from the Bridge result.

`OPAQUE_CURSOR` is part of the project taxonomy even though none of the current
Flutter long-list surfaces exposes an opaque Provider cursor. If such a
capability is added, the cursor must remain an uninterpreted Provider value.

## Validation policy

Raw-offset validation is shared only at the invariant boundary, not through a
universal paging framework. `isValidRawOffsetPage` requires nonnegative bounded
values, `visible + omitted <= raw consumed`, strict monotonic progress when
`hasMore`, no backward or overflowing cursor, and exact-total consistency where
the Provider declares an exact total. A zero-visible, all-omitted page is valid
when its typed cursor advances. A continuing page that does not advance is
invalid.

Page-number Search and Radar retain their native model. A raw page may produce
zero visible rows when every row was explicitly omitted; `hasMore` remains the
Provider fact and the next page number is based on the validated returned page,
never the visible count.

## Viewport demand policy

`BoundedViewportPageDemand` is a small presentation-neutral notification
adapter used only where the existing controller already owns pagination. A
downward approach within about 1.25 viewports emits one demand and disarms until
the user retreats or the query generation changes. It does not loop, retry, or
own transport. Controllers remain the single-flight, failure, retry,
continuation, cancellation, and stale-generation owners.

The adapter is connected to Comments; Track, Artist, Album, and Playlist Search;
Favorite Albums and Artists; Album and Artist lists; Rankings; New Albums; and
Recommended Playlists. Playlist, Liked, Recent, and Radar retain their existing
specialized bounded look-ahead because it already accounts for row geometry and
page latency.

Comments now use `ListView.builder`, retain the manual Load more / Retry footer,
and treat viewport demand as the normal path. One notification cannot create
parallel loads; upward retreat only cancels unconsumed demand and never aborts a
valid in-flight page.

## Progressive collection search

Liked Songs and Recent Plays search their already loaded `PlaylistTrackSearchIndex`
immediately. A query with at least 20 loaded matches issues no request. Otherwise
one automatic demand grants at most two raw pages. Every accepted page is added
to the shared index and published immediately. Reaching 20 matches pauses the
scan; terminal data marks it complete; a retryable append failure marks it
interrupted; exhausting the two-page budget while more data exists marks it
paused.

Changing a query reuses every loaded page. It cancels only unconsumed search
budget, not a valid browse request already in flight. Clearing the query stops
automatic scanning. Scrolling filtered results or activating the existing
Continue action grants another bounded window; an interrupted scan retries the
same Provider cursor only after that explicit action. The pre-existing explicit
`loadAll` capability remains for callers that deliberately request a complete
scan, but normal query entry no longer calls it.

Ordinary Playlist Detail currently has no local search field, so progressive
Playlist search is not applicable to that surface in this checkpoint.

## Remaining review

The continuation and demand rules are deterministic and offline-testable. Human
review is limited to long real collections confirming that the existing visual
loading/footer presentation remains understandable; no visual redesign is part
of HD-035.
