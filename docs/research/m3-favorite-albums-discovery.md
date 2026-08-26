# M3 Favorite Albums Discovery — 2026-08-26

## Evidence boundary

- yakult-green-tea/qq-music-api commit `2c27d6b90dd56bcf0796883e27216f69189d8f68`, still its remote HEAD on 2026-08-26, records a real logged-in account with two favorite Albums. `music.musicasset.AlbumFavRead/CgiGetAlbumFavInfo` returned code `80000` and a zero-filled structure for 13 parameter shapes and four client identities, so that response is not an empty collection. Its implemented product route instead uses the authenticated legacy `fav/fcgi-bin/fcg_get_profile_order_asset.fcg` CGI.
- feeluown-qqmusic commit `241a9678bcd26e88d19e08e5da8048018f06e330`, also still its remote HEAD, independently uses the same CGI with `reqtype: 2`, numeric user identity, inclusive `sin`/`ein`, QQ headers, and credential cookies for its current-user favorite-Album reader.
- Both implementations agree on `ct: 20`, `cid: 205360956`, `reqtype: 2`, and inclusive page indexes. The current yakult implementation additionally supplies `format: json`; FeelUOwn supplies `reqfrom: 1`. Only fields required by both or current measured behavior enter the project request.
- Current response evidence uses `data.albumlist`, `data.totalalbum`, and `data.has_more`. yakult's current fixtures use lowercase `albumid`/`albummid`/`albumname`, while FeelUOwn's independent schema uses `albumID`/`albumMID`/`albumName`; the protocol model must accept both exact observed spellings.
- yakult records that an uncredentialed request was rejected with code `4000`. A bounded project-side anonymous request on 2026-08-26 used fixed non-account user identifiers, no Cookie/token/stored credential, and returned global code `-1`, subcode `-2`, and no collection shape. This confirms that the route is credential-bearing but does not justify treating every nonzero code as credential rejection. Only the authenticated rejection code with direct evidence may clear credential state.
- No request used the user's stored credential. Only codes and JSON value types were printed; no account identity, Album identity/title, Cookie, response body, or user collection was printed, retained, or committed.

Reference implementations remain research evidence only. Runtime requests will go directly to QQ Music, and neither third-party server nor response model becomes a dependency.

## Ranked candidates

### 1. Authenticated favorite Albums — selected

- Goal: let the signed-in user browse a bounded favorite-Album collection and open any result through the existing Album details/Tracks/queue path.
- Provenance: `ROADMAP.md` M3 richer-library direction, two current independent product implementations, the current real-account failure evidence for the tempting musicu route, and the bounded anonymous authentication-shape check above.
- User value: the user's Album collection becomes a first-class daily-use library destination instead of being reachable only through Search, Artist discography, recommendations, or new releases.
- Scope: one provider-neutral offset page of existing `AlbumSummary` values; direct credential-bearing CGI request; exact Provider credential candidate/rejection/replacement behavior; one single-use cancellable Bridge handle; an independently retained Flutter collection page; and existing Album/queue navigation.
- Acceptance criteria: inclusive range construction, Cookie redaction, global code, list/total/continuation and minimum Album identity/title validation, lowercase/uppercase field variants, first/empty/error/retry/pagination/append-failure/cancel/stale/disposal behavior, explicit sign-in recovery, shared-vault cleanup only after evidenced rejection, compact/desktop reachability, parent-state preservation, and existing Album/queue handoff have offline regressions. Strict Rust/Dart checks, Flutter tests, Linux Release, and packaged Bridge integration pass.
- Expected effort: high but finite because credential lifecycle and Album navigation already exist.
- Risk: medium-high because the endpoint is a legacy authenticated CGI and response spelling varies. Structural and upstream failures must not become an empty collection or sign the user out.
- Explicit non-goals: favorite/unfavorite mutation, favorite Artists or other asset types, a generic user-library union, cache/automatic refresh, accessing stored credentials for live probes, Track identity propagation, new queue semantics, or a navigation/state-management framework.

### 2. Cross-surface Track-to-Album/Artist navigation — deferred

- Provenance: M3 Album/Artist directions and the reproduced identity gap outside Search.
- User value: every Track origin could lead to its Album and credited Artists.
- Boundary gap: a correct solution spans shared Track Domain values, every producer, generated queue round-trips, and several return origins. It remains a larger independent slice than the selected collection.
- Non-goals: parsing QQ opaque identities in Dart or attaching raw response models to presentation Tracks.

### 3. Track availability and quality representation — deferred

- Provenance: M3 availability/quality direction and the pending real-account playback observation.
- Evidence gap: the repository still lacks sanitized unavailable/region/VIP action-row evidence. One resolution failure cannot establish restriction or quality semantics.
- Non-goals: guessing entitlement bits, exposing quality controls from file metadata alone, or using the user's stored account for automated discovery.

## Selection

Authenticated favorite Albums rank first because the user value is direct, the existing Album route keeps the product slice bounded, and two current implementations agree on a working authenticated CGI while one records why the more obvious musicu method is incorrect. The task preserves exact credential lifecycle semantics and requires no automatic account access.
