# QQ Music Capability Protocol Evidence Matrix

**Snapshot:** 2026-09-03

**Baseline before this pass:** local `41d5268`

**Scope:** direct QQ Music protocol evidence used by Fura's single `QQMusicProvider`

This matrix is an engineering decision aid, not a claim that undocumented QQ
Music interfaces are stable. A GitHub repository counts as another static
implementation only after the actual host, request profile, module/method and
response family have been compared. Several repositories using the same route
are corroboration for one strategy, not several fallbacks.

Production status has exactly five values:

- `PRIMARY`: deterministic production route for the stated auth/content context.
- `FALLBACK`: production route attempted only after an explicitly fallback-safe outcome.
- `EVIDENCE_ONLY`: useful protocol evidence, but not executable production routing.
- `REJECTED`: deliberately excluded from current production scope.
- `UNKNOWN`: not sufficiently characterized.

Evidence classes are kept separate:

- **Source:** static Fura or independent implementation inspection.
- **Fixture:** deterministic, synthetic or sanitized transport/decoder regression.
- **Live:** bounded read-only service observation with no retained response content.
- **Human:** maintainer-operated account/device observation; no credential is retained.

## Current production matrix

All musicu rows use `POST https://u.y.qq.com/cgi-bin/musicu.fcg` unless another
host is shown. `Anonymous` and `Authenticated` are deliberately separate
columns. “Not needed” means that the capability intentionally uses an anonymous
request even while an account exists; it does not mean an authenticated variant
was tested.

| Capability | Protocol strategy / family | Module, method or CGI | Client profile and envelope | Anonymous evidence | Authenticated evidence | Credential requirement | Pagination and output completeness | Known outcomes and limits | Evidence / date | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Track Search | musicu Desktop Search, type 0 | `music.search.SearchCgiService/DoSearchForQQMusicDesktop` | `ct=19`, `cv=1859`, `platform=yqq.json`; top-level `search` result | Fixture pass; bounded live returned content and later code `2001` | Not needed; request carries no credential | None | 1-based page, max 30; Track, credited Artists and optional Album | Valid empty is success; `2001` is `RateLimited` and STOP; malformed identity/pagination is shape failure | Fura source/fixture/live audit; independent Desktop route evidence; 2026-09-03 | `PRIMARY` |
| Artist Search | musicu Desktop Search, type 1 | same module/method | named module key; Desktop params | Fixture pass | Not needed | None | 1-based page, max 30; numeric ID, MID, name | Same Search code policy; empty page is valid only with valid metadata | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| Album Search | musicu Desktop Search, type 2 | same module/method | named module key; Desktop params | Fixture pass | Not needed | None | 1-based page, max 30; numeric ID, MID, title | Same Search code policy; optional display fields cannot invalidate identity | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| Playlist Search | musicu Desktop Search, type 3 | same module/method | named module key; Desktop params | Fixture pass | Not needed | None | 1-based page, max 30; playlist ID/title/count; short continuing page is allowed | Same Search code policy; invalid numeric identity is shape failure | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| Playlist Detail, ordinary | musicu DissInfo | `music.srfDissInfo.DissInfo/CgiGetDiss` | mobile QQ profile `ct=11`, `cv/v=13020508`, `tmeAppID=qqmusic`; named result | `UNKNOWN`; current facade requires account state | Fixture pass; user library/detail has prior Human observation | Current QQ credential and Cookie | offset plus bounded `song_begin/song_num`, max 100; exact total/continuation and minimum playable Track context | Explicit credential rejection is distinct; nonzero service codes STOP; malformed/empty-continuing pages are invalid | Fura source/fixture/Human; independent current source corroboration; 2026-09-03 | `PRIMARY` |
| Playlist Detail, liked songs | DissInfo directory context | same module/method with `dirid=201` and encrypted UIN | same authenticated mobile envelope | Not applicable | Fixture pass; user library/detail has prior Human observation | Credential, Cookie and encrypted UIN | Same bounded page contract | Same as ordinary detail; content context selects this route, not fallback | Fura source/fixture/Human; 2026-09-03 | `PRIMARY` |
| Artist Tracks, numeric identity | musicu SongListInter | `music.musichallSong.SongListInter/GetSingerSongList` | `wk_v17`, `ct=20`, `cv=1770`; `singerid/begin/num` | Fixture pass | Not needed | None | offset, max 100; exact requested MID, total and continuation | Selected when Fura's QQ-owned opaque identity contains numeric ID; malformed identity/response does not switch routes | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| Artist Tracks, MID-only identity | musicu song-list server | `musichall.song_list_server/GetSingerSongList` | same public profile; `singerMid/begin/number` | Fixture pass | Not needed | None | Same bounded output and shared decoder | Content-context route for MID-only favorite Artists; not a retry fallback for the numeric route | Fura source/fixture; independent source corroboration; 2026-09-03 | `PRIMARY` |
| Artist Albums | musicu AlbumListServer | `music.musichallAlbum.AlbumListServer/GetAlbumList` | public `wk_v17`; `singerMid/begin/num` | Fixture and bounded field-comparison evidence pass | Not needed | None | offset, max 100; Album identity/title and total/continuation | Conflicting `number` field was observed ignored, so production retains `num` | Fura source/fixture/live field comparison; 2026-09-03 | `PRIMARY` |
| Favorite Albums | legacy profile assets | `GET https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg`, `cid=205360956`, `reqtype=2` | legacy JSON; inclusive `sin/ein` | Authentication required by current contract | Fixture pass; route chosen after earlier compatibility evidence | Credential Cookie plus account ID | offset/max 100 mapped to inclusive range; both observed field casings | Only evidenced code `4000` is credential rejection; other nonzero codes are unknown service failure, not sign-out | Fura source/fixture and repository compatibility history; 2026-09-03 | `PRIMARY` |
| Favorite Artists | musicu concern list | `music.concern.RelationList/GetFollowSingerList` | authenticated named result; `HostUin/From/Size` | Authentication required | Fixture pass | Credential, Cookie and encrypted UIN | offset/max 100; MID/name, exact total and continuation | Explicit credential rejection STOP; invalid rows/pagination are shape failures | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| Owned Playlists | musicu asset read | `music.musicasset.PlaylistBaseRead/GetPlaylistByUin` | `ct=11`, `cv=13020508`; named result | Authentication required | Fixture pass; playlist list has Human observation | Credential and Cookie | bounded collection; owned playlist/directory identity | Explicit rejection distinct; zero owned rows is valid | Fura source/fixture/Human; 2026-09-03 | `PRIMARY` |
| Favorite Playlists | musicu asset read | `music.musicasset.PlaylistFavRead/CgiGetPlaylistFavInfo` | same authenticated mobile profile | Authentication required | Fixture pass | Credential, Cookie and encrypted UIN | offset/max 100; raw-row continuation; Provider bounds aggregation | Explicit rejection distinct; empty/non-advancing continuation invalid | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| Rankings list/detail | musicu Toplist | `music.musicToplist.Toplist/GetAll` and `GetDetail` | anonymous named requests | Fixture pass | Not needed | None | bounded groups; detail offset/max 100 and current service period | Empty valid collections allowed; mismatched ranking/page identity invalid | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| Lyrics | musicu PlayLyricInfo | `music.musichallSong.PlayLyricInfo/GetPlayLyricInfo` | `ct=11`, `cv=13020508`; QRC/plain/translation/romanization flags | Fixture plus ignored live QRC pass; no Cookie or fabricated identity | Fixture pass; M1 end-to-end Human observation remains pending | Optional single-owner credential | One Track; bounded ciphertext, decompressed text, lines and timed segments | Empty/no usable lyric is `Unavailable`, not auth; explicit rejection STOP; malformed QRC/XML is invalid | Fura source/fixture/live; independent route corroboration; 2026-09-03 | `PRIMARY` |
| CDN Dispatch | musicu audio dispatch | `music.audioCdnDispatch.cdnDispatch/GetCdnDispatch` | anonymous mobile-style comm; named `req_0` | Fixture pass | Not needed | None | one bounded base list plus positive TTL | Invalid bases/TTL/shape stop; returned `sip` list is sorted only by a fixed host preference | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| Media VKey, guest | musicu VKey | `music.vkey.GetVkey/UrlGetVkey` | `ct=11`, `cv=13020508`; anonymous `uin=0`, no Cookie | Fixture plus ignored live new-song sample pass | Not applicable | None | one M500 MP3 item; exact filename/path; short-lived TTL | Per-Track unavailable remains truthful and does not infer VIP/region/copyright; malformed identity/path STOP | Fura source/fixture/live; independent route corroboration; 2026-09-03 | `PRIMARY` |
| Media VKey, signed in | same VKey route | same module/method | authenticated comm and Cookie | Guest route is independent evidence | Fixture pass; real playback/Queue/lyrics Human observation pending | Current credential from sole session owner | one requested M800 High item; Provider may try M500 Standard only after typed `Unavailable` | Credential, rate/risk, network and malformed outcomes never trigger quality or protocol fallback | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| Public Playlist Recommendations | musicu PlaylistSquare | `music.playlist.PlaylistSquare/GetRecommendFeed` | `wk_v17`, `ct=20`, `cv=1770`, `uin=0` | Fixture and prior bounded live behavior | Not needed | None | offset/max 50; raw row count advances feed | Valid empty is allowed; malformed rows/pages are invalid; no personalization claim | Fura source/fixture/live history; 2026-09-03 | `PRIMARY` |
| Radar | musicu TrackRelationServer | `music.recommend.TrackRelationServer/GetRadarSong` | authenticated `ct=19`, page number | Authentication required | Fixture pass; recommendation quality/live availability pending Human rerun | Credential and Cookie | service page/`HasMore`; bounded Track output and dedupe above Client | Explicit rejection STOP; empty page may be valid; personalization is not inferred from anonymous probes | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| Daily Recommendation | musicu RecommendFeed | `music.recommend.RecommendFeed/get_recommend_feed` | `wk_v17`, `ct=20`, `cv=1770`; page 1 shelves | Authentication required | Fixture pass; authenticated Home availability pending Human rerun | Credential and Cookie | one strictly identified Daily card | Missing Daily card is absence; ambiguous duplicate/invalid card is shape failure | Fura source/fixture; independent route corroboration; 2026-09-03 | `PRIMARY` |
| Personalized Playlists | same RecommendFeed call, separate shelf selection | same module/method | same authenticated feed envelope | Authentication required | Fixture pass; authenticated Home availability pending Human rerun | Credential and Cookie | bounded playlist shelf; optional valid artwork | Valid empty shelf is allowed; public recommendations cannot occupy this slot | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| Personalized Tracks | musicu personal radio | `music.radioProxy.MbTrackRadioSvr/get_radio_track` | `ct=19`, `cv=0`; fixed personal-radio ID | Authentication required | Fixture pass; authenticated Home availability pending Human rerun | Credential and Cookie | one fixed bounded five-Track set | Explicit rejection STOP; duplicate/oversized/invalid rows invalid; empty valid set allowed | Fura source/fixture; independent route corroboration; 2026-09-03 | `PRIMARY` |
| Related Tracks | signed musicu GET | `rcmusic.similarSongRadioServer/get_simsongs` | `platform=yqq`; signed serialized request in query | Live/fixture pass without account | Not needed | None | one bounded Track set; no invented pagination | Valid empty is success; missing/duplicate/invalid Track collection is invalid | Fura source/fixture/live; 2026-09-03 | `PRIMARY` |
| Comments | legacy comment CGI | `GET https://c.y.qq.com/base/fcgi-bin/fcg_global_comment_h5.fcg`, `cid=205360772`, `reqtype=2`, `biztype=1`, `cmd=8` | `yqq.json`, anonymous legacy JSON | Fixture plus ignored live pass | Not needed | None | aligned offset/page, max 25; hot and newest groups separate | Valid empty is success; only evidenced blank deleted newest rows are filtered; malformed nonblank rows invalid | Fura source/fixture/live; 2026-09-03 | `PRIMARY` |
| QQ Web QR authentication | ptlogin + QQ Connect + musicu exchange | `ptqrshow`, `ptqrlogin`, `check_sig`, OAuth authorize, then QQ login exchange | cookie/redirect flow plus named musicu login result | Public QR bootstrap/poll only | Maintainer-operated approval and full exchange passed | Temporary QR cookies/code; final credential enters sole Provider owner | one 180-second generation; bounded polling and transport failures | Refusal/expiry/replacement/security/service remain distinct; no password or SMS path | Fura fixture + Human observation; 2026-09-03 | `PRIMARY` |
| WeChat Web QR authentication | WeChat Connect + musicu exchange | `open.weixin.qq.com` QR/poll then QQ login exchange | cookie/redirect flow plus named musicu login result | Public QR bootstrap/poll only | Prior maintainer-operated approval/exchange passed | Temporary authorization code; final credential enters same owner | same bounded coordinator semantics | Same session-generation and redaction rules; no automatic approval | Fura fixture + Human observation; 2026-09-03 | `PRIMARY` |
| Account Summary / credential verification | musicu UserInfo | `music.UserInfo.userInfoServer/GetLoginUserInfo` | authenticated `ct=11`, `cv=13020508` | Authentication required | Fixture pass; QR-created session displayed signed-in state, clean-process restore remains Human evidence | Current credential and Cookie | one bounded optional public nickname/avatar | Explicit credential rejection STOP and clears only matching candidate; absent optional summary can still verify credential | Fura source/fixture/Human; 2026-09-03 | `PRIMARY` |
| Track-associated Music Video | three-stage musicu read | `music.pf_song_detail_svr/get_song_detail_yqq`; `video.VideoDataServer/get_video_info_batch`; `music.stream.MvUrlProxy/GetMvUrls` | anonymous web `ct=24`, `cv=0`; named results | Fixture plus ignored live pass | Not needed | None | zero or one correlated MV; supported HTTPS MP4 file types 40/30/20/10 | No associated VID is valid absence; associated MV without supported source is unavailable; identity mismatch/malformed shape invalid | Fura source/fixture/live; 2026-09-03 | `PRIMARY` |
| New Albums | musicu NewAlbumServer | `newalbum.NewAlbumServer/get_new_album_info` | anonymous named request | Fixture pass | Not needed | None | regional offset/max 50; Album and credited Artist identity | Valid terminal empty page allowed; mismatched region/page/identity invalid | Fura source/fixture; 2026-09-03 | `PRIMARY` |
| New Songs | musicu NewSongServer | `newsong.NewSongServer/get_new_song_info` | anonymous named request | Fixture plus bounded use by live guest-media gate | Not needed | None | one category, max 200 rows; no invented cursor | Valid empty collection allowed; mismatched category/oversized/invalid Track collection invalid | Fura source/fixture/live; 2026-09-03 | `PRIMARY` |

## Candidate and rejected strategies

No row in this table is executed in production. Static evidence alone does not
prove anonymous behavior, authenticated behavior, Fura's bounded pagination, or
compatibility with its typed decoder.

| Capability | Candidate strategy | Protocol family / host | Profile and envelope difference | Anonymous status | Authenticated status | Pagination/output gap | Evidence | Production status and reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Search, per result type | `DoSearchForQQMusicMobile` | musicu SearchCgiService | Mobile method/profile/response decoder differs from Fura Desktop | Static external evidence only | `UNKNOWN` | Fura decoder contract not characterized | L-1124 pinned source and another independent source; 2026-09-03 | `EVIDENCE_ONLY`; no failure case currently justifies a second production route |
| Search, per result type | `DoSearchForQQMusicLite` | musicu SearchCgiService | Lite profile and envelope | Static external documentation only | `UNKNOWN` | Decoder/pagination equivalence unknown | simple-music pinned documentation; 2026-09-03 | `EVIDENCE_ONLY` |
| Search, per result type | `SearchAdaptor/do_search_v2` | musicu adaptor family | Different module, params and response family | Static external documentation only | `UNKNOWN` | Output completeness and page semantics unknown | external source survey; 2026-09-03 | `EVIDENCE_ONLY` |
| Search | legacy `client_search_cp` family | legacy CGI | legacy query/envelope | Historical only; a recent implementation report describes `new_json=1` breakage | `UNKNOWN` | Modern Track context and pagination not characterized | independent issue/source history; 2026-09-03 | `EVIDENCE_ONLY`; not a safe compatibility fallback |
| Playlist Detail | `music.srfDissInfo.aiDissInfo/uniform_get_Dissinfo` | musicu | alternate named module/method and response family | Weak static script evidence | `UNKNOWN` | Bounded pagination and Domain completeness unproven | source survey; 2026-09-03 | `EVIDENCE_ONLY`; evidence is not strong enough for production |
| Playlist Detail | `fcg_ucc_getcdinfo_byids_cp.fcg` | legacy qzone CGI | legacy full-list response | Historical static evidence | `UNKNOWN` | Bounded page contract and large-playlist behavior unproven | simple-music documentation/history; 2026-09-03 | `EVIDENCE_ONLY`; must not silently perform unbounded loads |
| Favorite Albums | `music.musicasset.AlbumFavRead/CgiGetAlbumFavInfo` | musicu asset read | named musicu response rather than legacy profile asset | `UNKNOWN` | Static external evidence; earlier Fura compatibility was incomplete | Field completeness/continuation compatibility unresolved | L-1124 pinned source plus Fura historical decision; 2026-09-03 | `EVIDENCE_ONLY`; current legacy route remains evidence-driven Primary |
| Lyrics | legacy lyric CGI | legacy CGI | plain/base64 or legacy lyric response | Historical/static external evidence | `UNKNOWN` | QRC word timing, translation alignment and bounds not equivalent | simple-music documentation; 2026-09-03 | `EVIDENCE_ONLY`; cannot replace the current richer contract |
| Media VKey | `vkey.GetVkeyServer/CgiGetVkey` | musicu legacy VKey | different module/method and response shape | Static external evidence | Static external evidence | Exact item identity, TTL and authorization outcomes not characterized | simple-music documentation; 2026-09-03 | `EVIDENCE_ONLY`; live/Human evidence would be required before production |
| Media VKey | EVkey / lossless-format requests | musicu media authorization | additional formats/qualities | `UNKNOWN` | Static ecosystem evidence only | Fura intentionally supports only MP3 Standard/High | source survey; 2026-09-03 | `REJECTED` for current scope; no speculative codec or entitlement expansion |
| Account Summary | legacy profile CGI | legacy profile | incomplete-data fallback candidate only | Authentication required | Static/historical evidence only | Current public nickname/avatar completeness and rejection semantics unproven | source survey; 2026-09-03 | `EVIDENCE_ONLY`; no demonstrated incomplete-data failure warrants fallback |

## Auth-aware deterministic policy

Authentication is selected per capability; it is not a global “logged in means
send credentials everywhere” switch.

| Policy | Current examples | Deterministic behavior |
| --- | --- | --- |
| Anonymous-only by typed request signature | Search, public catalog, rankings, comments, public recommendations | Never fabricate or attach a credential. A valid empty response stays empty rather than becoming `AuthenticationRequired`. |
| Authenticated-preferred | Lyrics; media selection above the Client chooses authenticated High when a current credential exists and anonymous Standard otherwise | Use the sole current credential when supplied; otherwise use the separately evidenced anonymous request. Anonymous unavailability does not invalidate a credential. |
| Authenticated-required by typed request signature | Daily/Radar/personalized content, account/library reads and playlist detail | Provider rejects signed-out access before the request. The strategy never creates, refreshes or replaces credentials. |

The private `qqmusic-client` policy vocabulary can represent these selections,
but existing single-path capabilities retain their stronger Rust signatures.
Adding a policy enum does not justify wrapping every request in a strategy
object.

## Typed outcome and fallback policy

QQ-private classification remains inside `qqmusic-client`; `provider-qqmusic`
continues mapping it to existing provider-neutral failures.

| QQ-private outcome | Decision | Constraint |
| --- | --- | --- |
| `Success`, `ValidEmpty` | `RETURN` | Empty must be supported by the exact capability response contract. |
| `ProtocolUnavailable`, `EndpointUnavailable`, `UnsupportedByStrategy`, `ResponseShapeMismatch`, `IncompleteData` | `TRY_NEXT` | Only if that capability already has a known deterministic fallback with compatible bounds/output. No current new candidate meets that bar. |
| `TemporaryNetworkFailure` | `RETRY_BOUNDEDLY` | The capability must define its retry count. It must not reset a session budget or automatically change protocol afterward. Current catalog reads retain their existing one-attempt behavior. |
| `AuthenticationRequired`, `RateLimited`, `SecurityVerificationRequired`, `CredentialRejected`, `AccountRestricted`, `DeviceRestricted`, `VipRequired`, `EntitlementDenied`, `CopyrightRestricted`, `RegionRestricted`, `UpstreamUnknown` | `STOP` | Never rotate Desktop/Mobile/Lite/Web/legacy profiles. Preserve the truthful failure. |

Search code `2001` is the first production-integrated classification: all four
Search result types now return a typed rate-limit error which maps through the
unchanged Provider contract as `ServiceUnavailable`. It never becomes an empty
page or a fallback attempt.

No shared request-budget/cooldown object was added. There is currently no
production capability that switches protocol after a request, so such state
would be unused framework. QR authentication already owns its separate bounded
session deadline and consecutive-transport-failure count. When a real
multi-strategy capability is justified, its fallback attempts must share one
session-scoped risk state instead of constructing a budget per endpoint.

## Evidence sources and limits

- Fura implementation, fixtures and ignored live gates at the snapshot above
  are the primary evidence. Live gates retain no returned content or account
  material.
- [L-1124 `QQMusicApi` at commit `108617ffe80abefec6358717b9f4d3677550db10`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10)
  corroborates current musicu Search,
  Playlist Detail, Artist MID, Lyrics, VKey and recommendation families, and
  provides static evidence for Mobile Search and `AlbumFavRead`.
- [`yakult-green-tea/qq-music-api` at commit `2c27d6b90dd56bcf0796883e27216f69189d8f68`](https://github.com/yakult-green-tea/qq-music-api/tree/2c27d6b90dd56bcf0796883e27216f69189d8f68)
  is a second MIT-licensed source
  surveyed for overlapping Search, playlist, Artist, account and QR families.
- [`simple-music` documentation at commit `5a30a109c6b8cd01038cb3ae74669277e93bef59`](https://github.com/Yyyangshenghao/simple-music/blob/5a30a109c6b8cd01038cb3ae74669277e93bef59/docs/qq-music-api.md)
  supplies static evidence for legacy
  Playlist/Lyrics/VKey and additional Search variants. Documentation is not a
  Fura decoder or live-compatibility proof.
- [A recent independent legacy-Search compatibility report](https://github.com/Rain120/qq-music-api/issues/113)
  is kept as issue-level evidence only; it cannot promote that route.
- Repository-specific observed outcome rules remain in
  [QQ Music read availability audit](qqmusic-read-availability-audit.md).

Changing a `PRIMARY`, adding a production `FALLBACK`, or interpreting a new
restriction code requires a sanitized fixture, a bounded independently
repeatable integration result, or Human-operated evidence when account,
membership, region or device context is essential. Required Human evidence
currently includes authenticated recommendation availability/quality, a clean
process credential restore after the confirmed QR login, authenticated
playback/Queue/synchronized and word-timed lyrics, and any A/B comparison that
would promote an evidence-only endpoint. No stored credential may be automated
to obtain it.
