# M3 New Songs Discovery — 2026-08-27

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` implements `newsong.NewSongServer/get_new_song_info` as a current direct recommendation operation. It uses one `type` value and models `lanlist`, `lan`, `songlist`, returned `type`, and optional tag metadata. Its authenticated/live-gated tests require every mapped Track MID.
- yakult-green-tea/qq-music-api commit `2c27d6b90dd56bcf0796883e27216f69189d8f68` independently includes the same named operation and `{type: 5}` request in its current QQ recommendation controller.
- Both implementations identify six service categories: `1` mainland China, `2` western, `3` Japan, `4` Korea, `5` latest, and `6` Hong Kong/Taiwan. These are QQ-owned channel values rather than Provider-generic region strings.
- A bounded anonymous project-side probe on 2026-08-27 called exact types `5` and `1` without Cookie, token, stored credential, or account identity. Both returned zero global/module codes, exact returned type, six language options, two tag records, and one uniform Track field shape. Latest returned 55 rows and mainland China returned 89; every observed row had positive numeric ID, nonempty MID/title, and at least one Artist.
- The probe printed only codes, counts, value types, field names, and all-row booleans. It did not print, retain, or commit Track, Album, Artist, tag, URL, trace, or response content.

Reference implementations remain research evidence only. Runtime requests will go directly to QQ Music, and no third-party server or response model becomes a dependency.

## Global ranking

### 1. Typed QQ new-song channels — selected

- Provenance: M3 evidence-backed QQ Music home/recommendation direction, two current independent direct implementations, and the bounded anonymous structural probe.
- User value: users can browse a QQ-native, query-free new-song collection by the six service categories and send any Track to the existing playback queue.
- Scope: one typed provider-neutral category; one bounded whole-response Track collection because the operation exposes no pagination input; direct anonymous QQ request; reuse the minimum Track protocol/domain mapper; one cancellable Bridge handle; one lazy retained adaptive Discover section with exact category replacement; and existing queue/playback actions.
- Acceptance criteria: exact category mapping and returned-type validation; global/module/data/list bounds; response byte/row/time limits; minimum Track identity/title/Artist mapping; diagnostics redaction; first/empty/error/retry/category-replacement/cancel/stale/disposal state; compact/desktop category reachability and Track actions; retained Discover state; offline client/Provider/Bridge/controller/widget regressions; strict Rust/Dart checks, Linux Release, and packaged Bridge integration.
- Risk: medium. The service controls a comparatively large whole collection (55/89 rows observed), so byte and row caps are mandatory and the UI must not invent pagination.
- Explicit non-goals: heterogeneous Home shelves, editorial/tag rendering, personalization or recommendation-quality claims, infinite radio/autoplay, daily aggregation, availability/quality inference, new queue semantics, caching/automatic refresh, or a generic recommendation runtime.

### 2. Favorite Artists — deferred

- Provenance: richer QQ library direction and two public implementations referencing `music.concern.RelationList/GetFollowSingerList`.
- Evidence gap: the anonymous exact request returns module code `1000` with no data, one implementation marks pagination as guessed and appears to read a mismatched response key, and the current independent model proves MID/name but not the positive numeric Artist ID required by the selected bounded Artist-song route. No stored credential may be used to fill that gap automatically.
- Non-goals: fabricating a numeric ID, parsing display names, switching the shared Artist route to an unbounded request shape, or treating authentication rejection as an empty collection.

### 3. Global now-playing catalog navigation — deferred

- Provenance: M3 catalog coherence and retained queue context.
- Evidence gap: three consecutive completed tasks already changed local catalog presentation. This candidate spans every page plus open dialogs/sheets and needs an independent ownership audit; it does not outrank the direct QQ-native Core/Provider capability with current protocol evidence.

## Selection

Typed new-song channels rank first because they add a core QQ-native discovery capability with two current independent implementations, a successful content-free live shape, a finite whole-response boundary, and direct reuse of the existing shared Track mapper and queue. This rebalances work toward protocol/Provider correctness after three presentation-heavy catalog tasks without expanding into a heterogeneous Home runtime.

## Outcome

Implemented on 2026-08-27 as direct anonymous `QQMusicClient` loading → `NewSongsProvider` → provider-neutral typed whole-response Track collection → single-use cancellable Bridge → lazy retained Flutter Discover state. The client enforces the exact requested/returned category, 2 MiB response, 30-second request, and 200-row bounds; the shared Provider mapper retains opaque Track, Album, and credited-Artist context while diagnostics expose only category/count/failure metadata. Flutter owns loading/empty/error/retry/category replacement/cancellation/stale/disposal state, keeps the six-category selector reachable on a 360px surface, and reuses the existing queue for play/add actions without inventing pagination.

Validation passed Rust formatting, 258 offline Rust tests with four separately gated live tests ignored, strict all-target/all-feature Clippy, strict Dart formatting/analysis, all 273 Flutter tests, the Linux x64 Release bundle, and packaged Linux typed-Bridge cancellation integration. These checks prove the bounded request/mapping/lifecycle/adaptive UI and Linux packaging path. They do not prove current live application compatibility, editorial or recommendation quality, Track availability, or authenticated QQ CDN playback. No account credential or returned catalog content was used by implementation tests or retained in the repository.
