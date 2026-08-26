# M3 Artist Albums Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` implements offset-paged Artist albums with `music.musichallAlbum.AlbumListServer/GetAlbumList`, `singerMid`, `order: 1`, `begin`, and a requested page size. Its response model identifies `singerMid`, `total`, and `albumList` plus Album identity, title, artwork identity, release text, and Track count.
- Yyyangshenghao/simple-music commit `301d1ca159e88f6226acbc95fb01a28a99234e79` independently implements the same module, method, Artist identity, order, and offset, and maps Album identity/title/artwork/count for an existing Artist-albums flow.
- The references disagree on the page-size field: L-1124 uses `number`, while simple-music uses `num`. A bounded anonymous comparison returned 30 rows when requesting five through `number`, but exactly five through `num`; the service accepted both requests with zero global/module codes. Real behavior therefore selects `num` and treats `number` as an ignored field rather than protocol evidence.
- A follow-up anonymous probe used `num: 5` with `begin: 0` and `begin: 5`. Both pages returned five rows, the same positive total, matching Artist identity, and zero overlapping Album identities.
- The probes used no Cookie, token, stored credential, user identifier, or user data. They printed only codes, counts, booleans, field names, and JSON value types; no Artist or Album identity, title, artwork URL, response body, or content was printed, retained, or committed.

Reference implementations remain research evidence only. The runtime will call QQ Music directly and will not import third-party response models or depend on a third-party server.

## Ranked candidates

### 1. Artist albums — selected

- Provenance: `ROADMAP.md` M3 Album/Artist browsing direction, product-completeness audit of the implemented Artist page, two current independent implementations, and successful bounded anonymous exact-size/pagination probes.
- User value: from a credited Artist, a user can browse the Artist's discography, open an Album, and use the already implemented Album Track and playback-queue path.
- Problem: the current Artist page exposes only Tracks, even though Album browsing already exists and the Artist identity required by the Album-list protocol is present.
- Scope: one provider-neutral offset-paged Artist Album contract, direct bounded anonymous QQ operation, Provider mapping to existing `AlbumSummary`, one cancellable Bridge page operation, a lazy adaptive Albums section in the existing Artist surface, and nested return to the preserved Artist page after opening an existing Album page.
- Acceptance: exact-size offset pagination and response identity/total/list validation are offline tested; initial/empty/error/retry/append-failure/cancel/stale/disposal states are explicit; switching between Artist Tracks and Albums preserves both local states; Album selection reuses the existing Album page and queue; nested back returns Album → Artist → Search; strict Rust/Dart checks, Flutter tests, Linux packaging, and packaged Bridge integration pass.
- Effort: high but finite.
- Risk: medium; the response uses an Album-summary shape and the reference page-size mismatch must remain regression-tested.
- Non-goals: Artist biography/artwork/follow, Album mutation, multi-type Search, discography grouping/filtering, a generic catalog runtime, or a navigation/state-management framework.

### 2. Multi-type Search — deferred

- Provenance: `ROADMAP.md` M3 Search direction and current active implementations documenting Artist, Album, and playlist search types.
- User value: direct discovery of non-Track catalog objects without first finding a Track.
- Current evidence gap: a coherent mixed/category Search contract and compact/desktop result-selection model need a separate bounded product audit; folding them into the existing Track query would broaden both Domain and presentation at once.
- Effort: high.
- Risk: medium-high until result-type pagination and identity shapes are probed independently.
- Non-goals: suggestions, history, fuzzy ranking control, or copying the official client.

### 3. QQ Music ranking lists — deferred

- Provenance: `ROADMAP.md` M3 QQ-native catalog-flow direction and current public `music.musicToplist.Toplist/GetAll` and `GetDetail` references.
- User value: stable query-free chart discovery that can reuse existing Track playback.
- Current evidence gap: one mature current implementation exposes the raw protocol, while another current project only documents it as cross-validated rather than integrated; list/detail identity, period semantics, and navigation require a bounded probe before implementation.
- Effort: high.
- Risk: medium-high because chart periods and heterogeneous list metadata can be volatile.
- Non-goals: charts from other Providers, editorial Home shelves, chart history, or recommendation personalization.

## Selection

Artist albums rank first because they close a visible gap inside an already implemented Artist → Album → playback journey, reuse the existing Album Domain and page, and have stronger live protocol evidence than rankings. They are smaller and more coherent than broadening Search across several heterogeneous result types. Multi-type Search and rankings remain discovery candidates, not implicit follow-up work.

## Implementation outcome

Implemented on 2026-08-26 as `QQMusicClient` direct anonymous loading → `ArtistAlbumsProvider` → provider-neutral `ArtistAlbumsPage` of existing `AlbumSummary` values → single-use cancellable Bridge → lazy adaptive Flutter Artist Albums section. The client sends only the real-service-validated `num` page-size field, validates Artist identity and exact offset/total/list bounds, and redacts Artist/Album content from diagnostics. Flutter preserves independent Track/Album controller state, renders a compact list or desktop grid, and reuses the existing Album Track/queue page with nested Album → Artist → Search return behavior.

Validation passed with Rust formatting, 187 offline Rust tests, strict Clippy, strict Dart analysis, 199 Flutter tests, a Linux x64 Release build, and packaged Linux typed-Bridge cancellation integration. Four live QQ/WeChat tests remain separately gated and ignored. This evidence does not claim that every live Artist discography or downstream authenticated Album playback works for every account at this moment.
