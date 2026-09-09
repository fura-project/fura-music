# NetEase protocol evidence

Date: 2026-09-09. Authority: HD-023 + HD-024. Core-only, independent Rust implementation. No real account, credential extraction, media download, alternate source, or UI integration.

## Reference provenance and deduplication

- [api-enhanced at `d55d92cd0031`](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/tree/d55d92cd0031d7c7746b7068faecd7ade1d354ac) — active, pushed 2026-09-08; [MIT license](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/d55d92cd0031d7c7746b7068faecd7ade1d354ac/LICENSE) inspected. Endpoint modules and `util/crypto.js`, `util/request.js` inspected as wire behavior references. No implementation copied; unlocking modules/dependencies excluded.
- [MusicBox at `9c405f4bae23`](https://github.com/darknessomi/musicbox/tree/9c405f4bae2384d0410e63f8b816a707553d72d3) — active, pushed 2026-08-27; [MIT license](https://github.com/darknessomi/musicbox/blob/9c405f4bae2384d0410e63f8b816a707553d72d3/LICENSE) inspected. `NEMbox/api.py` and `encrypt.py` corroborate request families, current QR, catalog and ordinary media. Its eapi implementation explicitly references api-enhanced, so it is **not independent corroboration** of that algorithm.
- `SPlayer-Dev/ncm-api-rs` metadata was screened (WTFPL, last push 2026-04-07); no source adopted. No GPL or license-unclear implementation copied.
- [`SPlayer-Dev/ncm-api-rs` at `133b65bfe482`](https://github.com/SPlayer-Dev/ncm-api-rs/tree/133b65bfe482e41ebccf018870d3fce07bf58eb3) was subsequently inspected after the interrupted shallow clone succeeded. Its Rust modules corroborate the Comments, similar-song, new-song, new-Album, MV-detail/MV-source and recent-list paths below, but each says it corresponds to the Node module, so it is a second implementation rather than independent protocol provenance. No code was copied.
- Current module history checked: Search shape unchanged since 2024-08-10; QR poll fix 2024-10-03; media module updated 2026-08-20. Latest media reference defaults to xeapi, while MusicBox retains eapi. These are evidence variants, never automatic fallback choices.

## Protocol families

| Family | Wire behavior | Fura decision |
|---|---|---|
| weapi | AES-128-CBC twice, Base64 between stages, reversed random session key with RSA exponent 65537 | Independent Rust; deterministic OpenSSL/integer known answers; direct `music.163.com/weapi` |
| eapi | MD5 over path/JSON markers, AES-128-ECB, uppercase hex | Independent Rust; deterministic known answer; one standard media route at `interface.music.163.com/eapi`, JSON response requested |
| linuxapi | AES-128-ECB forward envelope | Investigated; no current requirement justifies another production path |
| plain api | Older/public unencrypted envelope over HTTPS | Investigated; no compatibility gap requires it |
| xeapi | New request session/envelope family in current Enhanced media code | Evidence-only; ordinary eapi sample works; no profile rotation or new runtime |

Runtime is Flutter → in-process Rust → direct HTTPS. RustCrypto AES/CBC and num-bigint implement wire primitives. Development-only independent known answers used OpenSSL and Python integer arithmetic; no subprocess or interpreter exists in runtime.

## Anonymous endpoint inventory

| Capability | Exact protocol path after `/api/` | Bound / semantics |
|---|---|---|
| Four Search types | `search/get` (weapi), types 1/100/10/1000 | 30 rows, 256-byte query; one-based Domain pages converted to offset; exact total and continuation |
| Song detail | `v3/song/detail` (weapi) | 100 requested exact IDs, no unrelated/duplicate output |
| Public playlist | `v6/playlist/detail` (weapi), then requested window through Song detail | Complete identity table ≤16,384, then at most 100 exact details; at most two requests per page, omissions consume raw cursor |
| Album | `v1/album/<id>` (weapi) | Whole response ≤4,096 songs; local bounded windows, exact Album correlation |
| Artist Tracks | `v1/artist/songs` (weapi) | 100 rows; public context, no private-cloud assumption |
| Artist Albums | `artist/albums/<id>` (weapi) | 100 rows, exact Artist correlation and total/continuation |
| Lyrics | `song/lyric` (weapi) | 512 KiB text, ≤10,000 lines; exact-time translation, no invented words or duration |
| Rankings | `toplist` (weapi) | ≤100 summaries; ranking identity is provider-owned playlist identity |
| Public recommendations | `personalized/playlist` (weapi) | Explicit bounded, non-paged sample; offset 0 only, no fabricated continuation/personalization |
| Standard source | `song/enhance/player/url/v1` (eapi) | One exact ID, standard only, normal service response; trial STOP, returned TTL, redacted URI |
| Track Comments | `v1/resource/comments/R_SO_4_<id>` (weapi) | True offset/limit page, latest `comments`, initial-page `hotComments`, exact IDs and bounded text; no mutation/user identity |
| Related Tracks | `v1/discovery/simiSong` (weapi) | One exact seed, ≤50 rows, duplicate/seed rows rejected; no fuzzy seed, history or autoplay claim |
| New songs | `v1/discovery/new/songs` (weapi) | Bounded whole response; exact All/Western/Japan/Korea area values, no invented pagination |
| New Albums | `album/new` (weapi) | True offset/limit/total page for exact Western/Korea/Japan area values; no fabricated release-date timezone |
| Track-associated MV | Song `mv` → `v1/mv/detail` → `song/enhance/play/mv/url` (weapi) | Exact 0/1 association; requested 1080 and retains actual 240/360/480/720/1080 result; HTTPS/redacted URI; no media download |

HTTP has a 20-second deadline, no redirects, a 2 MiB streaming body ceiling, and no retry. Network diagnostics omit URL parameters, encrypted bodies, cookies and content. Artwork upgrades only the service's own `.music.126.net` HTTP CDN URLs to same-host HTTPS; all other HTTP artwork is rejected.

## Live observations

2026-09-09: four one-request Search observations (first three identified a structural mapping issue; fourth passed after regression repair). Public artist credits can have ID 0 with a valid display name; retain the name, do not fabricate a navigable Artist identity. No endpoint was changed.

Then one explicit ignored serial catalog gate, hard budget 16 HTTPS requests and a one-second minimum cadence, passed all 13 observed capability points: Track/Artist/Album/Playlist Search, Song detail, Lyrics, standard Media, Album content, Artist Tracks/Albums, public Playlist, Rankings and public recommendations. The playlist path permits at most two serial requests per window. Only coarse outcomes and redacted field/type diagnostics were retained, never raw bodies, song titles, account data, lyrics or media URIs. The test's selected samples establish compatibility, not all-catalog availability, licensed-region coverage or account behavior.

One additional ignored serial read-parity window ran on 2026-09-09 with a hard ceiling of nine HTTPS requests and one-second cadence. It passed a bounded MV-seed Search plus Comments, related Tracks, new songs, new Albums, and exact associated-MV resolution in eight actual requests. A separate three-request maximum gate selected a public Playlist whose advertised count exceeded 1,000 and successfully read raw position 1,000. Only named PASS outcomes were emitted. Neither probe used credentials, logged catalog content/source URIs, fetched an audio/video body, or encountered 429/access-control/risk outcomes.

## Error interpretation

`Result::Ok` with actual empty collections is ValidEmpty; it is distinct from malformed output and missing count fields. HTTP 429 is RateLimited. Envelope 301 is AuthenticationRequired for anonymous requests and CredentialRejected for explicit authenticated requests. Unknown envelope or media codes are UpstreamUnknown and STOP. Explicit returned trial metadata is EntitlementDenied for this full-source contract; a null source is TrackUnavailable, not an inferred copyright/region/VIP reason. The private error vocabulary also reserves credential rejection, security verification, account restriction, copyright and region outcomes, but no undocumented code is assigned these meanings. Live observations conservatively stop their window on any non-success envelope.

## Current reference tests and account research

Enhanced `test/search.test.js` checks one cloudsearch song name and `test/album.test.js` checks success status through its own server. Both were inspected but **not executed or used as Fura's runtime**; these weak current tests do not establish Fura correctness. Fura instead has deterministic transport/mapping/negative tests and the bounded direct Rust observations above. Enhanced `module/comment_music.js` corroborates the implemented weapi `v1/resource/comments/R_SO_4_<id>` read; deterministic mapping/negative tests and the bounded anonymous parity gate cover the Fura path before `TrackCommentsProvider` is advertised.

Current QR key/poll, account, user playlist, like-list, daily/Personal FM and favorite Album/Artist module request shapes were inspected. The current MusicBox implementation explicitly documents QR codes 800 expired / 801 waiting / 802 scanned / 803 confirmed, the local `login?codekey=` image payload, and account/profile verification. See [authenticated evidence](netease-auth-evidence.md). `specialType=5` is corroborated by the MusicBox author's historical [playlist protocol sample](https://gist.github.com/darknessomi/5eb366ac2cbf1dd49192); this semantic is not promoted to real-account VERIFIED without Human observation. No personal sample content is retained.

## Provider contract audit

`SUPPORTED` means the bounded public Core contract is implemented and mapped. `PARTIAL` explicitly denotes a bounded semantic limitation or authenticated implementation awaiting Human live evidence. `NOT_SUPPORTED` is not an advertised capability. These statuses do not turn unimplemented capabilities into a generic Provider interface.

| Existing/new provider-api trait | NetEase status | Evidence / boundary |
|---|---|---|
| MusicProvider | SUPPORTED | Explicit built-in descriptor, tested Search/Catalog/Recommendations/Lyrics/Authentication/UserLibrary |
| TrackSearchProvider | SUPPORTED | Anonymous direct sample, bounded mapping/negative fixtures |
| ArtistSearchProvider | SUPPORTED | Anonymous sample, exact Artist identity |
| AlbumSearchProvider | SUPPORTED | Anonymous sample, HTTPS artwork |
| PlaylistSearchProvider | SUPPORTED | Anonymous sample, exact playlist identity/count |
| TrackDetailsProvider (new) | SUPPORTED | Exact lookup, missing detail is None, never Search/fuzzy matching |
| PlaylistDetailsProvider | SUPPORTED | Public bounded windows; ordinary authenticated/private and account-scoped liked routes are implemented with generation checks but separately HUMAN_EVIDENCE_REQUIRED |
| AlbumDetailsProvider | SUPPORTED | Canonical metadata, bounded whole response |
| AlbumTracksProvider | SUPPORTED | Requested local window over strict bounded whole response |
| ArtistTracksProvider | SUPPORTED | True upstream offset/total/more |
| ArtistAlbumsProvider | SUPPORTED | True upstream offset/total/more |
| LyricsProvider | SUPPORTED | True LRC starts, exact-time translation, zero unknown durations and no fabricated words |
| RankingsProvider | SUPPORTED | Bounded list and Track windows; neutral raw next-offset and omitted-count preserve continuation even when all details in a window are unavailable |
| RecommendedPlaylistsProvider | PARTIAL | One bounded public sample at offset 0; no fake pagination or account personalization |
| MediaSourceResolver | SUPPORTED | Exact static routing; normal standard source only; authenticated behavior awaits Human |
| QrAuthenticationProvider | PARTIAL | Native ProviderDefault channel, PNG-only challenge; Human QR approval not performed |
| QrAuthenticationSession | PARTIAL | Offline tested generation/cancel/drop/deadline/terminal/rejection transitions |
| AccountSummaryProvider | PARTIAL | Current credential generation, exact account/profile correlation; Human account evidence required |
| UserPlaylistsProvider | PARTIAL | Explicit complete contract bounded to 10×100 rows; owned/saved and liked-purpose mapping |
| OwnedPlaylistsProvider | PARTIAL | Filters exact creator identity after bounded complete collection |
| FavoriteAlbumsProvider | PARTIAL | Typed bounded page/total/continuation and synthetic tests; Human evidence required |
| FavoriteArtistsProvider | PARTIAL | Typed bounded page/total/continuation and synthetic tests; Human evidence required |
| PersonalizedPlaylistsProvider | PARTIAL | Explicit authenticated recommend/resource; no public substitutes |
| PersonalizedTracksProvider | PARTIAL | One bounded Personal FM batch; no autoplay, feedback, or continuation |
| DailyRecommendationProvider | NOT_SUPPORTED | Daily songs are not a canonical Playlist. Gap resolved with neutral DailyTracksProvider instead of a fake identity |
| DailyTracksProvider (new) | PARTIAL | Bounded authenticated daily songs; Human evidence required |
| NewAlbumReleasesProvider | SUPPORTED | Western/Korea/Japan exact mappings and true pages; incompatible existing region values reject before transport |
| NewSongsProvider | SUPPORTED | Latest(All), Western, Japan and Korea exact whole-response mappings; narrower Chinese regions reject before transport |
| RelatedTracksProvider | SUPPORTED | Exact seed and bounded results; no current/history/autoplay or cross-Provider claim |
| RadarRecommendationsProvider | NOT_SUPPORTED | QQ Radar semantics are not relabeled as NetEase daily/FM |
| TrackCommentsProvider | SUPPORTED | Exact read-only page with true latest/hot semantics; anonymous live sample passed |
| TrackMusicVideoProvider | SUPPORTED | Exact Track association and validated HTTPS source; anonymous live sample passed, no content download |
| DesktopQuickAuthenticationProvider | NOT_SUPPORTED | No local-client credential discovery/extraction |
| DesktopQuickAuthenticationSession | NOT_SUPPORTED | No local-client credential discovery/extraction |
| TrackLikeMutationProvider | NOT_SUPPORTED | No writes implemented or performed |
| AlbumFavoriteMutationProvider | NOT_SUPPORTED | No writes implemented or performed |
| PlaylistTrackMutationProvider | NOT_SUPPORTED | No writes implemented or performed |
| PlaylistCreationProvider | NOT_SUPPORTED | No writes implemented or performed |
| PlaylistDeletionProvider | NOT_SUPPORTED | No writes implemented or performed |
| RecentHistoryProvider | NOT_SUPPORTED | Current `play-record/song/list` is bounded by limit only and `pc/recent/listen/list` has no paging input; no clear neutral continuation, and QQ history is not reused |

Before implementation, native QR selection and daily Track delivery were `NEEDS_PROVIDER_API_EXTENSION`: existing channels offered only QQ/WeChat and the daily contract returned an optional Playlist. The implemented ProviderDefault variant and DailyTracksProvider resolve these neutral gaps without NetEase-specific traits. TrackDetailsProvider likewise supplies a neutral exact-lookup contract absent from the original API.

## Complexity and boundary review

Two protocol/provider crates are the only new production packages. Separate short modules own transport/crypto/catalog/lyrics/media/auth; three small operation-local mapping macros share proven repeated typed mapping. No framework, runtime discovery, generic injection system, sidecar, or provider-neutral raw JSON was introduced. Existing QQ transport was intentionally not pulled into NetEase or refactored across unrelated QR/local-loopback behavior.

The static enum and resolver pair are in provider-api; they do not contain endpoint/crypto/cookie/identity-decoding logic. Native composition instantiates NetEase only for its selected media route, preserving QQ behavior even if NetEase HTTPS initialization fails. Default presentation remains QQ. Existing Domain identities and catalog entities are reused. RankingTracksPage gains a provider-neutral raw next-offset and omitted-count, matching the existing Playlist page semantics; its original constructor preserves QQ behavior. QQ-specific explanatory comments were made neutral. Existing coarse error messages no longer misidentify a NetEase credential rejection as QQ.

Known finite bounds are intentional rather than silent partial success. The 2 MiB streaming transport cap now derives a 16,384-row bare-identity ceiling (128 bytes of decoded-memory policy per ID) and a 4,096-row whole-Album ceiling (512 bytes per richer row); Track detail remains 100 per request. The current Playlist endpoint returns the full identity table and the reference wrapper itself slices locally, so this is bounded local windowing rather than invented server paging. Account playlist aggregation remains ≤1,000 rows; normal source profile only; no fabricated lyric duration, word timing, release timezone or unsupported regional meaning. TD-011 records repeated whole-metadata cost.

The exhaustive stop audit is [netease-remaining-work-audit.md](netease-remaining-work-audit.md).

## Final machine checkpoint

The HD-024 final validation result and platform evidence are recorded in the [Remaining Work Audit](netease-remaining-work-audit.md). No public Bridge API or Flutter file changed in that pass, so FRB generation was intentionally not rerun. The prior pinned FRB 2.13.0 generation/orphan audit remains the generated-surface baseline.

No actual NetEase account observation is promoted to VERIFIED. The new Human matrix is compiled and ignored by default; the Agent did not run it.
