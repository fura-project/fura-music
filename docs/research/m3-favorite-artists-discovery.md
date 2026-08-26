# M3 Favorite Artists Discovery — 2026-08-27

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` implements authenticated `music.concern.RelationList/GetFollowSingerList` with encrypted `HostUin`, offset `From`, bounded `Size`, `Total`, `HasMore`, and `List`. Its current login-gated integration test executes the operation, and its response model requires each returned row to carry `MID` and `Name` while treating avatar and social fields as Provider data rather than Artist identity.
- feeluown-qqmusic commit `241a9678bcd26e88d19e08e5da8048018f06e330` independently uses the same named operation, encrypted identity, credential cookies, and `List` rows for its current-user favorite-Artist product route. Its `From: page - 1` calculation is explicitly marked guessed and its response key is inconsistent, so neither behavior is adopted.
- The repository's prior bounded anonymous Artist-browsing probe already proved that `musichall.song_list_server/GetSingerSongList` accepts Artist MID without numeric Artist ID and returns two advancing 30-row pages. Favorite rows can therefore remain honest `artist:-:<mid>` Provider identities and use that already-evidenced route instead of fabricating an unavailable number.
- A bounded anonymous call to the favorite-Artist operation returned module code `1000` and no data. This confirms the credential-bearing boundary but supplies no account collection evidence. It must not become an empty collection or a synthetic fixture derived from user data.

Reference implementations remain research evidence only. Runtime requests go directly to QQ Music. This task will not read the stored credential outside the existing Provider-owned authenticated operation, run an autonomous real-account probe, or retain account identifiers, cookies, Artist content, or response bodies.

## Global ranking

### 1. Authenticated favorite Artists — selected

- Goal: let the signed-in user browse one bounded favorite-Artist collection and open any row through the existing Artist Tracks/Albums/queue path.
- Provenance: `ROADMAP.md` richer QQ Music library direction, two independent product implementations, L-1124's current login-gated integration path, and the repository's existing anonymous proof that MID-only Artist browsing works.
- Scope: one provider-neutral offset page of existing `ArtistSummary` values; a direct credential-bearing QQ request with exact Provider candidate/rejection/replacement semantics; support for a valid QQ Artist identity whose numeric component is absent; one cancellable Bridge page operation; one retained adaptive Flutter collection; and the existing Artist/Album/queue route.
- Acceptance criteria: exact `HostUin`/`From`/`Size` request mapping; global/module code and rejection handling; bounded response/text/row validation; required safe MID/nonblank name; coherent total/continuation/page rules; redacted diagnostics; MID-only Artist Track and Album routing; first/empty/error/retry/pagination/append-failure/cancel/stale/disposal behavior; vault cleanup only after evidenced credential rejection; compact and desktop Artist entry; exact return with underlying state retained; offline client/Provider/Domain/Bridge/controller/widget regressions; strict Rust/Dart checks, Linux Release, and packaged Bridge integration.
- Risk: medium-high. The route is authenticated and one older independent implementation has known pagination/routing defects, so response validation must be strict and no nonzero code may become an empty collection.
- Explicit non-goals: follow/unfollow mutation, Artist biography or social data, generic user-library unions, cache/automatic refresh, stored-credential probing, numeric-ID fabrication, a navigation/state-management framework, Track availability/quality, or new queue semantics.

### 2. Track availability and quality representation — deferred

- Provenance: explicit M3 direction and the pending authenticated playback evidence boundary.
- Evidence gap: no sanitized unavailable, region-filtered, VIP-entitlement, grey-row, or alternate-quality behavior exists. One failed media request still cannot distinguish those states safely.

### 3. Additional platform validation — environment-blocked

- Provenance: TD-004 and intended cross-platform support.
- Evidence gap: Apple/Windows runtimes and a physical Android device are unavailable on the current host. Existing Linux/emulator results cannot be promoted into those claims.

## Selection

Favorite Artists ranks first because the current upstream operation and its authenticated model are now concrete, while the previously blocking route identity can be satisfied by the repository's already-proven MID-only Artist request. The slice adds a high-value QQ-native account collection without guessing entitlement, expanding Providers, or accessing the user's account during development.

## Outcome

Implemented on 2026-08-27 as the twentieth finite M3 slice. The direct client validates the evidenced request and strict page shape; Provider and Bridge preserve exact credential generation, cancellation, coarse failure, and redacted-diagnostic boundaries; MID-only Artist identities reuse the existing Track/Album route; and Flutter retains the adaptive collection through nested Artist/Album navigation. Synthetic offline tests cover request mapping, malformed/rejected/upstream responses, account replacement, Bridge lifecycle, Dart mapping/vault cleanup, pagination/deduplication/stale suppression, compact pointer use, desktop keyboard use, semantics, and exact return. No stored credential or live account collection was accessed, so real-account favorite-Artist compatibility remains unclaimed.
