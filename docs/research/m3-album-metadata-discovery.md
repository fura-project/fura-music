# M3 Album Metadata Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10`, still the remote HEAD on 2026-08-26, implements anonymous `music.musichallAlbum.AlbumInfoServer/GetAlbumDetail` for either Album ID or MID. Its typed model exposes canonical Album identity/title, credited Artists, translated subtitle, release date, description, language, Album type, genre, and company.
- feeluown-qqmusic commit `241a9678bcd26e88d19e08e5da8048018f06e330`, also still its remote HEAD, independently presents Album detail and description through a legacy QQ endpoint. This corroborates the user-facing product behavior, not the exact current musicu request.
- A bounded anonymous current-service probe used the public MID already present in L-1124's live-gated Album-song tests. The exact `albumMId` request returned zero global/module codes, a matching response MID, positive numeric Album identity, nonblank title, string metadata fields, and minimum-shape credited Artists.
- A second public-ID probe confirmed the response groups `basicInfo`, `company`, `extra`, and `singer`; the minimum fields use `albumID`, `albumMid`, `albumName`, `tranName`, `publishDate`, `desc`, `language`, `albumType`, `genre`, `company.name`, and `singer.singerList`.
- Neither probe supplied a Cookie, token, credential, user identifier, query, or user data. Only codes, field names/types, lengths/booleans, and requested-MID equality were printed. No returned identity, title, description, Artist, company, artwork, or response body was retained or committed.

Reference implementations remain research evidence only. Runtime requests will go directly to QQ Music, and no third-party server or response model becomes a dependency.

## Ranked candidates

### 1. Existing Album-page metadata — selected

- Goal: make every existing Album entry open a coherent detail page with canonical credits, release metadata, and an accessible description while retaining the existing Track/queue flow.
- Task provenance: `ROADMAP.md` M3 Album-browsing direction; the reproduced product gap in the current title/artwork/Track-only Album page; one current direct implementation and live-gated test; the bounded anonymous exact-request/field-shape evidence above; and an independent legacy product implementation.
- User value: Track Search, Album Search, Artist discography, and New Albums all converge on the same Album page, so one bounded detail operation improves four already implemented user paths without adding another navigation system.
- Scope: one provider-neutral `AlbumDetails` value and Provider capability; one direct anonymous QQ detail operation by existing opaque Album MID; one single-use cancellable typed Bridge load; one short-lived Flutter metadata controller/gateway; and adaptive canonical title/Artist/release/type/language/genre/company/description presentation beside the existing independent Track state.
- Acceptance criteria: exact `albumMId` request and global/module/data mapping; returned MID equality; bounded canonical Album/Artist identity and text fields; optional metadata remains optional and no raw QQ keys reach Flutter; metadata loading/failure/retry/cancel/stale/disposal are independent from Track loading so a detail failure never hides playable Tracks; compact and desktop layouts keep full description reachable; every current Album origin uses the same path and preserves its parent on return; strict Rust/Dart checks, offline suites, Linux Release, and packaged Bridge integration pass.
- Expected modules/files: `music-domain`, `provider-api`, `qqmusic-client`, `provider-qqmusic`, `bridges/flutter`, generated bindings, the existing Flutter Album gateway/controller/page plus app injection, focused tests, and current architecture/state documentation.
- Required tests: client exact request/shape/redaction and invalid identity/text fixtures; Provider/Domain mapping and error coverage; Bridge mapping/cancellation/redaction; Dart gateway/controller lifecycle including independent metadata failure/retry; compact and desktop Album metadata/description plus existing Track/queue regressions; full offline suites and packaged Linux validation.
- Known risks: externally supplied descriptions can be large or malformed, optional fields vary by Album, and canonical metadata can disagree with the summary used for navigation. The protocol layer must bound all text, require exact returned identity, and prefer validated canonical detail without making metadata success a Track-list prerequisite.
- Explicit non-goals: Album favorites or mutation, booklet/wiki/head-video/rights/tracking fields, comments, Artist navigation, Track Domain identity propagation, Search changes, cache/automatic refresh, a generic catalog-detail runtime, or a navigation/state-management framework.

### 2. Authenticated favorite Albums — deferred

- Provenance: M3 richer-library direction, L-1124's current `music.musicasset.AlbumFavRead/CgiGetAlbumFavInfo` implementation and authenticated live-gated test, plus FeelUOwn's independent legacy favorite-Album product path.
- Evidence gap: the exact current route still has no secret-safe project observation and would add another credential-bearing collection lifecycle. Album metadata has current anonymous request/shape evidence and improves every existing Album origin first.
- Non-goals: automating against the user's stored credential or inferring remote mutation semantics from the read path.

### 3. Cross-surface Track-to-Album/Artist navigation — deferred

- Provenance: M3 Album/Artist directions plus the reproduced identity gap outside Search.
- Boundary gap: a correct change spans shared Track Domain values, every Track-producing Provider map, generated queue round-trips, and multiple return origins. It needs its own bounded design pass and should not be smuggled into the existing Album header task.
- Non-goals: parsing QQ opaque identity in Flutter, retaining raw QQ models, or adding a navigation framework.

## Selection

Existing Album-page metadata ranks first because it has exact current anonymous evidence, improves four implemented Album entry paths, and stays independent from both account credentials and Track/queue identity semantics. The metadata operation remains optional beside Track loading so external detail instability cannot regress the already working Album-to-queue path.
