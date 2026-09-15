# Upstream response integrity audit (HD-032)

Date: 2026-09-16
Starting HEAD: `6703ac564eb571005fafdb6d3598a89b245bffe2`
Scope: all currently implemented QQ Music and NetEase capabilities, plus the
already committed KuGou Track Search slice. This is an offline, source-backed
matrix; “live” means previously recorded protocol evidence, not a new request.

## Policy

Every network response has an outer `STRICT_CONTAINER` boundary: HTTP/body
bounds, the business envelope, required root objects, totals and cursors remain
fail-closed. A second classification describes the payload inside that trusted
container:

- `STRICT_SECURITY`: authentication, credentials, authorization-bearing media,
  security challenges and confirmed writes. Any ambiguity fails closed.
- `STRICT_SINGLETON`: an exact account/catalog/media-video object. Canonical
  identity conflicts fail; only evidenced presentation-only fields may degrade.
- `TOLERANT_COLLECTION`: one malformed row may be omitted when the endpoint's
  raw progression and remaining identities are still provable. Omission must be
  explicit and must never change the upstream cursor.
- `TOLERANT_TEXT_DOCUMENT`: an independently malformed lyric/translation line
  may be omitted; a document with no trustworthy original content is not a
  successful empty document.

`STRICT_CONTAINER` and the payload classification are deliberately cumulative.
They are not a generic response framework and do not authorize data guessing,
cross-provider substitution, credential relaxation or mutation ambiguity.

## Pagination invariants

1. `more == true` requires a strictly advancing next position.
2. The next position comes from an upstream cursor, a raw identity table, or
   `requested offset + raw rows consumed`; never from the number of visible
   rows after omission.
3. A raw window that consumed positions may yield zero visible rows and still
   advance. A non-advancing `more` page is invalid.
4. Totals, offsets, explicit `next` values and collection bounds are container
   facts. They are never repaired from visible output.
5. Duplicates are endpoint-specific: identity-table conflicts remain invalid;
   editorial duplicates are retained where ordering is meaningful.

## Endpoint matrix

The `Class` column lists the payload rule; every row also carries the strict
container rule described above. “Partial” in the desired column means valid
rows plus an explicit omitted count, never a silent shorter list. The final
column records the baseline disposition that drove this audit; the machine
checkpoint below records the completed outcome.

| Provider | Capability | Client method | Provider mapper | Bridge surface | Flutter consumer | Class | Container / row / optional semantics | Pagination | Current → desired failure granularity | Fixture / live evidence | Baseline disposition |
|---|---|---|---|---|---|---|---|---|---|---|---|
| QQ | Track search | `search_tracks` | `TrackSearchProvider::search_tracks` | `api/search.rs` | Search | `TOLERANT_COLLECTION` | Exact envelope/total; omit malformed Track; drop untrusted artwork/optional Album | page + raw row count | page-wide → partial | synthetic + recorded anonymous | audit target |
| QQ | Artist search | `search_artists` | `ArtistSearchProvider` | `api/search.rs` | Search | `TOLERANT_COLLECTION` | Exact envelope/total; omit malformed Artist; artwork optional | page + raw row count | page-wide → partial | synthetic + recorded anonymous | audit target |
| QQ | Album search | `search_albums` | `AlbumSearchProvider` | `api/search.rs` | Search | `TOLERANT_COLLECTION` | Exact envelope/total; omit malformed Album; artwork/date optional | page + raw row count | page-wide → partial | synthetic + recorded anonymous | audit target |
| QQ | Playlist search | `search_playlists` | `PlaylistSearchProvider` | `api/search.rs` | Search | `TOLERANT_COLLECTION` | Exact envelope/total; omit malformed Playlist; artwork optional | page + raw row count | page-wide → partial | synthetic + recorded anonymous | audit target |
| QQ | Album tracks | `album_tracks` | `AlbumTracksProvider` | `api/album.rs` | Album | `TOLERANT_COLLECTION` | Album route and totals strict; Track canonical fields row-local | offset + raw row count | page-wide → partial | synthetic | audit target |
| QQ | Album detail | `album_details` | `AlbumDetailsProvider` | album detail in `api/album.rs` | Album | `STRICT_SINGLETON` | Requested/returned Album identity exact; description/artwork may drop only when independently optional | none | strict retained | synthetic + recorded anonymous | retain strict identity |
| QQ | Artist tracks | `artist_tracks[_by_mid]` | `ArtistTracksProvider` | `api/artist.rs` | Artist | `TOLERANT_COLLECTION` | Artist route/total strict; malformed Track row omitted | offset + raw row count | page-wide → partial | synthetic | audit target |
| QQ | Artist albums | `artist_albums` | `ArtistAlbumsProvider` | `api/artist.rs` | Artist | `TOLERANT_COLLECTION` | Artist route/total strict; malformed Album row omitted | offset + raw row count | page-wide → partial | synthetic + recorded anonymous | audit target |
| QQ | New albums | `new_album_releases` | `NewAlbumReleasesProvider` | `api/new_albums.rs` | Discover | `TOLERANT_COLLECTION` | Region/envelope/total strict; malformed release omitted; date/artwork optional | offset + raw row count | page-wide → partial | synthetic + recorded anonymous | audit target |
| QQ | New songs | `new_songs` | `NewSongsProvider` | `api/new_songs.rs` | Discover | `TOLERANT_COLLECTION` | Category/envelope strict; malformed Track omitted | whole bounded raw list | page-wide → partial | synthetic | audit target |
| QQ | Recommended playlists | `recommended_playlists` | `RecommendedPlaylistsProvider` | `api/recommendations.rs` | Discover | `TOLERANT_COLLECTION` | Shelf/envelope strict; malformed Playlist omitted | offset + raw row count | page-wide → partial | synthetic + recorded anonymous | audit target |
| QQ | Daily recommendation | `daily_recommendation` | `DailyRecommendationProvider` | `api/recommendations.rs` | Home/Discover | `STRICT_SINGLETON` | At most one evidenced card; ambiguity or malformed canonical Playlist fails | none | strict retained | synthetic authenticated | retain strict identity |
| QQ | Personalized playlists | `personalized_playlists` | `PersonalizedPlaylistsProvider` | `api/recommendations.rs` | Home/Discover | `TOLERANT_COLLECTION` | Shelf identity strict; malformed Playlist row omitted | whole bounded raw list | page-wide → partial | synthetic authenticated | audit target |
| QQ | Personal radio | `personalized_tracks` | `PersonalizedTracksProvider` | `api/recommendations.rs` | Discover | `TOLERANT_COLLECTION` | Envelope strict; malformed Track omitted | whole bounded raw list | page-wide → partial | synthetic authenticated | audit target |
| QQ | Related tracks | `related_tracks` | `RelatedTracksProvider` | `api/recommendations.rs` | Now Playing | `TOLERANT_COLLECTION` | Seed exact; row identity local; endpoint duplicate policy retained | whole bounded raw list | page-wide → partial | synthetic | audit target |
| QQ | Radar tracks | `radar_tracks` | `RadarRecommendationsProvider` | `api/recommendations.rs` | Discover | `TOLERANT_COLLECTION` | Auth/envelope/page strict; malformed Track omitted | explicit page/`has_more` | page-wide → partial | synthetic authenticated | audit target |
| QQ | Ranking groups | `ranking_groups` | `RankingsProvider::ranking_groups` | `api/rankings.rs` | Discover | `TOLERANT_COLLECTION` | Group shape strict; malformed ranking entry omitted when grouping remains provable | whole bounded groups | page-wide → partial | synthetic + recorded anonymous | audit target |
| QQ | Ranking tracks | `ranking_tracks` | `RankingsProvider::ranking_tracks` | `api/rankings.rs` | Ranking | `TOLERANT_COLLECTION` | Ranking singleton exact; malformed Track omitted | explicit/raw next + omitted | partially tolerant → explicit partial | synthetic | strengthen |
| QQ | Owned playlists | `owned_playlists` | `OwnedPlaylistsProvider` | `api/library.rs` | Library | `TOLERANT_COLLECTION` | Credential/envelope strict; malformed Playlist omitted | whole bounded list | page-wide → partial | synthetic authenticated | audit target |
| QQ | User playlists | favorite-page aggregation | `UserPlaylistsProvider` | `api/library.rs` | Library | `TOLERANT_COLLECTION` | Credential/page chain strict; malformed rows omitted; ID duplicates remain endpoint-defined | upstream offset per page | page-wide → partial aggregate | synthetic authenticated | audit target |
| QQ | Favorite albums | `favorite_albums` | `FavoriteAlbumsProvider` | `api/favorite_albums.rs` | Library | `TOLERANT_COLLECTION` | Credential/envelope/total strict; malformed Album omitted | offset + raw row count | page-wide → partial | synthetic authenticated | audit target |
| QQ | Favorite artists | `favorite_artists` | `FavoriteArtistsProvider` | `api/favorite_artists.rs` | Library | `TOLERANT_COLLECTION` | Credential/envelope/total strict; malformed Artist omitted | offset + raw row count | page-wide → partial | synthetic authenticated | audit target |
| QQ | Playlist detail / liked songs | `playlist_tracks_page` / `liked_songs_page` | `PlaylistDetailsProvider` | `api/library.rs` | Playlist / Liked | `TOLERANT_COLLECTION` | Route/envelope/table strict; malformed Track omitted | existing raw next + omitted | row-tolerant client, mapper page-wide → partial end-to-end | good+bad+good synthetic | priority |
| QQ | Recent history | `recent_plays_snapshot` | `RecentHistoryProvider` | `api/library.rs` | Recent Plays | `TOLERANT_COLLECTION` | Credential/snapshot channels strict; malformed row omitted | snapshot raw next + omitted | partly tolerant → explicit partial UI | synthetic authenticated | strengthen |
| QQ | Track like write | `set_track_liked` | `TrackLikeMutationProvider` | `api/track_likes.rs` | Context actions | `STRICT_SECURITY` | Exact Track, credential, confirmed write response | none | strict retained | synthetic authenticated | retain strict |
| QQ | Album favorite write | `set_album_favorite` | `AlbumFavoriteMutationProvider` | `api/album_favorites.rs` | Album | `STRICT_SECURITY` | Exact Album, credential, confirmed desired state | none | strict retained | synthetic authenticated | retain strict |
| QQ | Playlist membership write | `set_playlist_track_membership` | `PlaylistTrackMutationProvider` | `api/playlist_tracks.rs` | Context actions | `STRICT_SECURITY` | Owned Playlist + exact Track + confirmed response | none | strict retained | synthetic authenticated | retain strict |
| QQ | Playlist creation | `create_playlist` | `PlaylistCreationProvider` | `api/playlist_creation.rs` | Library | `STRICT_SECURITY` | Credential and one unambiguous returned Playlist identity | none | strict retained | synthetic authenticated | retain strict |
| QQ | Playlist deletion | `delete_playlist` | `PlaylistDeletionProvider` | `api/playlist_deletion.rs` | Library | `STRICT_SECURITY` | Exact owned target and explicit confirmation | none | strict retained | synthetic authenticated | retain strict |
| QQ | Media resolution | `media_source` family | `MediaSourceResolver` | `api/media.rs` | Playback | `STRICT_SECURITY` | Credential generation, exact Track, HTTPS host/path/result/profile all strict | quality fallback only on explicit unavailable | strict retained | synthetic + recorded anonymous/authenticated | retain strict |
| QQ | Lyrics | `lyrics` | `LyricsProvider` | `api/lyrics.rs` | Now Playing | `TOLERANT_TEXT_DOCUMENT` | Envelope/decryption/document bounds strict; bad original/aux line local; original independent of translation | line timeline | partly tolerant → line-local | XML/pseudo-XML/QRC fixtures | strengthen |
| QQ | Comments | `track_comments` | `TrackCommentsProvider` | `api/comments.rs` | Comments sheet | `TOLERANT_COLLECTION` | Envelope/total/next strict; hot/latest independent; avatar presentation-only | offset + raw latest count | some omission silent → explicit partial | malformed/deleted synthetic | strengthen |
| QQ | Music video | `track_music_video` | `TrackMusicVideoProvider` | `api/music_video.rs` | Now Playing | `STRICT_SINGLETON` | Exact Track association and one trusted HTTPS MP4 source; artwork optional | none | strict retained | synthetic | retain strict |
| QQ | QR authentication | QR client/session methods | `QrAuthenticationProvider` | `api/authentication.rs` | Login | `STRICT_SECURITY` | Challenge, channel, credential and poll state exact | poll state machine | strict retained | synthetic/Human | retain strict |
| QQ | Desktop quick authentication | quick-auth client/session | `DesktopQuickAuthenticationProvider` | `api/authentication.rs` | Login | `STRICT_SECURITY` | Candidate credential stays in provider and requires server verification | state machine | strict retained | synthetic/Human | retain strict |
| QQ | Account summary | account client | `AccountSummaryProvider` | `api/authentication.rs` | Shell account | `STRICT_SINGLETON` | Current credential generation and exact account identity required; avatar optional | none | strict retained | synthetic authenticated | retain strict |
| NetEase | Track search | `search_tracks` | `TrackSearchProvider` | shared `api/search.rs` | Search | `TOLERANT_COLLECTION` | `result`/count strict; malformed Track omitted; nested optional Album/artwork degrade | offset + raw row count | row decode tolerant, mapper page-wide → partial | synthetic | priority |
| NetEase | Artist search | `search_artists` | `ArtistSearchProvider` | shared `api/search.rs` | Search | `TOLERANT_COLLECTION` | Count/array strict; malformed Artist omitted; artwork optional | offset + raw row count | page-wide → partial | synthetic | audit target |
| NetEase | Album search | `search_albums` | `AlbumSearchProvider` | shared `api/search.rs` | Search | `TOLERANT_COLLECTION` | Count/array strict; malformed Album omitted | offset + raw row count | page-wide → partial | synthetic | audit target |
| NetEase | Playlist search | `search_playlists` | `PlaylistSearchProvider` | shared `api/search.rs` | Search | `TOLERANT_COLLECTION` | Count/array strict; malformed Playlist omitted | offset + raw row count | page-wide → partial | synthetic | audit target |
| NetEase | Track detail | `songs` | `TrackDetailsProvider` | indirect playback/catalog | Playback | `STRICT_SINGLETON` | Requested Track identity and canonical title exact; nested presentation may degrade | none | strict retained | synthetic | retain strict identity |
| NetEase | Playlist detail | `playlist_page` / authenticated selection | `PlaylistDetailsProvider` | shared `api/library.rs` | Playlist | `TOLERANT_COLLECTION` | Playlist and identity table strict; missing/malformed detail row omitted | raw identity `next` + omitted | client tolerant, mapper page-wide → partial | synthetic | priority |
| NetEase | Liked songs | authenticated playlist selection | `liked_page` | shared `api/library.rs` | Liked | `TOLERANT_COLLECTION` | Owner/liked Playlist/table strict; malformed Song mapping omitted | raw identity `next` + omitted | mapper page-wide → partial | required good+bad+good | priority |
| NetEase | Album detail | `album` | `AlbumDetailsProvider` | shared `api/album.rs` | Album | `STRICT_SINGLETON` | Exact Album canonical identity; description/artwork optional | none | strict retained | synthetic | retain strict identity |
| NetEase | Album tracks | `album` songs | `AlbumTracksProvider` | shared `api/album.rs` | Album | `TOLERANT_COLLECTION` | Album container strict; malformed Song omitted | in-memory raw slice offset | page-wide → partial | synthetic | audit target |
| NetEase | Artist tracks | `artist_tracks` | `ArtistTracksProvider` | shared `api/artist.rs` | Artist | `TOLERANT_COLLECTION` | Artist/page metadata strict; malformed Song omitted | offset + raw row count | page-wide → partial | synthetic | audit target |
| NetEase | Artist albums | `artist_albums` | `ArtistAlbumsProvider` | shared `api/artist.rs` | Artist | `TOLERANT_COLLECTION` | Artist/page metadata strict; malformed Album omitted | offset + raw row count | page-wide → partial | synthetic | audit target |
| NetEase | Recommended playlists | `recommendations` | `RecommendedPlaylistsProvider` | shared `api/recommendations.rs` | Discover | `TOLERANT_COLLECTION` | Array/bounds strict; malformed Playlist omitted | bounded terminal list | page-wide → partial | synthetic | audit target |
| NetEase | Ranking groups | `rankings` | `RankingsProvider::ranking_groups` | shared `api/rankings.rs` | Discover | `TOLERANT_COLLECTION` | Root strict; malformed ranking omitted | bounded terminal list | page-wide → partial | synthetic | audit target |
| NetEase | Ranking tracks | `playlist_page` | `RankingsProvider::ranking_tracks` | shared `api/rankings.rs` | Ranking | `TOLERANT_COLLECTION` | Ranking singleton/table strict; malformed Track omitted | existing raw next + omitted | mapper page-wide → partial | synthetic | priority |
| NetEase | Lyrics | `lyrics` | `LyricsProvider` | shared `api/lyrics.rs` | Now Playing | `TOLERANT_TEXT_DOCUMENT` | LRC container/bounds strict; bad lines local; translation independent; `[00:00.00-1]` retained as evidenced | line timeline | partially tolerant → explicit line-local | LRC fixtures | strengthen |
| NetEase | Media resolution | media quality methods | `MediaSourceResolver` | shared `api/media.rs` | Playback | `STRICT_SECURITY` | Exact Track, entitlement, HTTPS first-party CDN normalization/host, TTL and format strict | quality selection | strict retained | synthetic + recorded anonymous | retain strict |
| NetEase | Comments | `comments` | `TrackCommentsProvider` | shared `api/comments.rs` | Comments sheet | `TOLERANT_COLLECTION` | `comments` array/total/more strict; hot/latest independent; bad avatar drops avatar | offset + raw latest count | page-wide → partial | malformed corpus required | priority |
| NetEase | Related tracks | `related_tracks` | `RelatedTracksProvider` | shared recommendations | Now Playing | `TOLERANT_COLLECTION` | Seed/root/bounds strict; malformed Song omitted | bounded terminal list | page-wide → partial | synthetic | audit target |
| NetEase | New songs | `new_songs` | `NewSongsProvider` | shared `api/new_songs.rs` | Discover | `TOLERANT_COLLECTION` | Area/root/bounds strict; malformed Song omitted | whole bounded list | page-wide → partial | synthetic | audit target |
| NetEase | New albums | `new_albums` | `NewAlbumReleasesProvider` | shared `api/new_albums.rs` | Discover | `TOLERANT_COLLECTION` | Area/total strict; malformed release omitted; publish time optional | offset + raw row count | page-wide → partial | synthetic | audit target |
| NetEase | Music video | `music_video` | `TrackMusicVideoProvider` | shared `api/music_video.rs` | Now Playing | `STRICT_SINGLETON` | Exact associated MV and HTTPS source identity; artwork optional | none | strict retained | synthetic | retain strict |
| NetEase | Account summary | `account` | `AccountSummaryProvider` | `api/netease_authentication.rs` | Shell account | `STRICT_SINGLETON` | Active generation and exact account identity required; avatar optional | none | strict retained | synthetic/Human | retain strict |
| NetEase | SMS challenge | SMS client methods | `SmsAuthenticationProvider::request_sms_code` | `api/netease_authentication.rs` | Login | `STRICT_SECURITY` | Phone/challenge/business result exact; no fabricated success | state transition | strict retained | synthetic/Human | retain strict |
| NetEase | SMS authentication | SMS login client | `SmsAuthenticationProvider::authenticate_sms_code` | `api/netease_authentication.rs` | Login | `STRICT_SECURITY` | Credential/security verification and account check exact | state transition | strict retained | synthetic/Human | retain strict |
| NetEase | QR authentication | QR client/session | `QrAuthenticationProvider` | `api/netease_authentication.rs` | Login | `STRICT_SECURITY` | QR key/poll/credential/security verification exact | poll state machine | strict retained | synthetic/Human | retain strict |
| NetEase | User playlists | `user_playlists` | `UserPlaylistsProvider` | shared `api/library.rs` | Library | `TOLERANT_COLLECTION` | Credential/page/liked uniqueness strict; malformed Playlist omitted | upstream offset per raw page | page-wide → partial aggregate | synthetic authenticated | audit target |
| NetEase | Owned playlists | derived user playlists | `OwnedPlaylistsProvider` | shared `api/library.rs` | Library | `TOLERANT_COLLECTION` | Same strict source; ownership filter after validated rows | inherited | inherited → explicit partial | synthetic authenticated | audit target |
| NetEase | Personal FM | `personal_fm` | `PersonalizedTracksProvider` | shared recommendations | Discover | `TOLERANT_COLLECTION` | Credential/root strict; malformed Song omitted | bounded terminal list | page-wide → partial | synthetic authenticated | audit target |
| NetEase | Daily tracks | `daily_tracks` | `DailyTracksProvider` | shared recommendations | Home/Discover | `TOLERANT_COLLECTION` | Credential/root strict; malformed Song omitted | bounded terminal list | page-wide → partial | synthetic authenticated | audit target |
| NetEase | Personalized playlists | `personalized_playlists` | `PersonalizedPlaylistsProvider` | shared recommendations | Home/Discover | `TOLERANT_COLLECTION` | Credential/root strict; malformed Playlist omitted | bounded terminal list | page-wide → partial | synthetic authenticated | audit target |
| NetEase | Favorite albums | `favorite_albums` | `FavoriteAlbumsProvider` | shared `api/favorite_albums.rs` | Library | `TOLERANT_COLLECTION` | Credential/total strict; malformed Album omitted | offset + raw row count | page-wide → partial | synthetic authenticated | audit target |
| NetEase | Favorite artists | `favorite_artists` | `FavoriteArtistsProvider` | shared `api/favorite_artists.rs` | Library | `TOLERANT_COLLECTION` | Credential/total strict; malformed Artist omitted | offset + raw row count | page-wide → partial | synthetic authenticated | audit target |
| KuGou | Track search | `search_tracks` | `TrackSearchProvider` | none (Core slice only) | none | `TOLERANT_COLLECTION` | HTTPS/envelope/total strict; malformed Search row omitted; optional Album/Artist/artwork degrade only by evidence | explicit page/size/raw row count | page-wide → partial Core | offline fixtures + prior one-request anonymous evidence | audit target; network closed |

## Baseline findings

- **Typed-array amplification:** numerous QQ client payloads deserialize an
  entire JSON array as `Vec<Raw…>`, so one structurally malformed element fails
  before the row mapper can apply collection policy.
- **Second-stage amplification:** NetEase search already obtains raw `Value`
  rows, but client and provider `collect::<Result<Vec<_>, _>>()` chains still
  turn one bad row or optional nested mapping failure into a page failure.
- **Good cursor foundation:** QQ playlist/recent/ranking and NetEase playlist /
  liked/ranking already preserve raw progression and omission counts. Those
  facts must be propagated, not recomputed from visible items.
- **Presentation fields are over-strict in collection context:** artwork and
  nested navigation metadata can currently invalidate a canonical Track or
  comment row. Singleton identity and media-source paths must remain strict.
- **Comments are uneven:** QQ already omits a few evidenced unavailable/deleted
  shapes but does not expose the omission end-to-end. NetEase decodes and
  validates both arrays all-or-nothing.
- **Lyrics already have useful compatibility work:** QQ strict XML plus bounded
  pseudo-XML recovery and translation independence, and NetEase's evidenced
  negative-suffix LRC timestamp handling, must be retained while making bad
  lines local.

## Implementation order

1. Extend only affected Domain page/collection types with omitted counts and,
   where needed, raw next positions.
2. Repair NetEase playlist/liked/search/comments mapping first, including the
   required `valid A + malformed + valid B` fixture.
3. Convert QQ typed collection arrays and provider mappers without changing
   strict singleton/security/write/media behavior.
4. Make lyric/translation line tolerance explicit.
5. Propagate omission through the existing Bridge DTOs and one shared Flutter
   inline partial-result notice with localized semantics.
6. Run the malformed corpus, robustness tests, full Rust/Flutter gates and both
   native Release builds. No new live request is planned; KuGou networking stays
   closed.

## Machine checkpoint

Completed on 2026-09-16 from starting HEAD
`6703ac564eb571005fafdb6d3598a89b245bffe2`.

- The matrix contains 69 implemented response boundaries: 36 QQ Music, 32
  NetEase and the one committed KuGou Track Search Core slice. All 69 retain a
  strict outer container. The payload classifications are 47 tolerant
  collections, 2 tolerant text documents, 12 strict security boundaries and 8
  strict singleton boundaries.
- All 47 collection-classified capability paths now either isolate malformed
  rows or preserve their already row-tolerant behavior, expose omission at the
  Domain/Bridge boundary applicable to the committed capability, and retain
  raw progression. No collection-classified path remains intentionally
  page-wide merely because one display row is malformed. The 20 security and
  singleton paths remain intentionally fail-closed.
- NetEase Liked and playlist detail have explicit `valid A + malformed + valid
  B` regressions. Search, album/artist/favorite/discovery/ranking/library and
  recommendation collections preserve valid canonical rows; optional artwork
  or nested navigation context may disappear without inventing identity.
- Comment hot/latest rows are isolated independently, raw latest-comment
  progression is retained, and a malformed avatar degrades only the avatar.
  Lyrics isolate malformed lines, keep original and translation failure
  independent, and still reject an untrustworthy original document. Media,
  authentication, credentials, writes, singleton identity and contradictory
  cursor/container metadata remain strict.
- Flutter maps the omission fields without deriving them from visible length.
  A shared English/Simplified-Chinese inline notice appears only for an
  explicit positive omission count, announces once per newly accepted partial
  result, and leaves queue/current/context-menu indexes based on the validated
  visible list. Paged controllers advance over visible plus omitted raw
  positions.
- Six wholly new Rust malformed-integrity tests were added and existing parser
  fixtures were expanded for malformed positions, all-malformed input,
  optional metadata and contradictory pagination. Seven new Flutter tests
  cover raw-offset progression, shared localization/accessibility and partial
  Liked, playlist, Search, comments and lyrics presentation.
- Final offline gates: 33 Rust test targets with 577 passed, 0 failed and 27
  explicitly ignored live/Human tests; strict Rust format and all-target Clippy
  passed. Flutter localization generation, strict formatting, analysis and all
  625 tests passed. Linux Release and Android ARM64 Release builds succeeded.
- No live provider request, telemetry, raw response/body/content/identity log,
  credential relaxation, cross-provider fallback, generic response envelope or
  new KuGou capability was introduced. KuGou networking remains closed.

Only Human observation of naturally malformed real-account Liked/playlist,
comment and lyric responses remains. Machine evidence cannot manufacture that
provider state, so the gate is `HUMAN_REVIEW` rather than a claim of live
acceptance.
