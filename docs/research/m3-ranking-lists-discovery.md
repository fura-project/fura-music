# M3 QQ Ranking Lists Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` implements anonymous ranking discovery as `music.musicToplist.Toplist/GetAll` and current-ranking Tracks as offset-paged `GetDetail`. Its typed models place categories at `data.group`, list identity and current-period metadata in each `toplist` row, ranking metadata at detail `data.data`, and Tracks at `data.songInfoList`.
- ylw1997/qqmusic-api commit `5f87b07b85923f8862d7b57f9d558ce0314ba1a7` independently uses the same named-key module/method pair and the same `topId`, `offset`, `num`, and `withTags` detail parameters without requiring credentials.
- A bounded anonymous real-service probe used those exact named-key requests without `comm`, Cookie, token, stored credential, user identifier, or user data. The list response returned zero global/module codes, four non-empty groups, and 30 summaries; every summary had a positive numeric ID, nonblank title, and preview-song array. Twenty-nine supplied a nonblank period, so period is optional display metadata rather than identity.
- Two five-row detail requests returned zero codes, exact five-row pages, stable positive total, matching list/detail identity and period, complete Track ID/MID/title identity, and no cross-page Track overlap. The response shape matched the current typed model: summary at `data.data`, Tracks at `data.songInfoList`, and disabled tags produced no tag rows.
- The probe printed only response sizes, codes, key names, counts, booleans, and overlap size. It did not print, retain, or commit ranking/Track identity, titles, artwork, periods, response bodies, or content.

Reference implementations remain research evidence only. The runtime will call QQ Music directly and will not import third-party response models or depend on a third-party server.

## Ranked candidates

### 1. Current QQ ranking lists — selected

- Provenance: `ROADMAP.md` M3 QQ-native catalog direction, the repeatedly deferred ranking candidate, two independent current implementations, and successful bounded anonymous list/detail probes.
- User value: users can browse QQ Music's current charts without a query, open one, and send its Tracks through the existing queue/playback path.
- Problem: the current Discover surface contains recommended playlists only; ranking categories and current chart Tracks are not reachable.
- Scope: provider-neutral ranking group/summary and paged Track-detail values; direct bounded anonymous QQ list and detail operations; one small Provider capability; cancellable typed Bridge operations; a Playlists/Rankings choice inside the existing Discover route with independent retained state; grouped ranking summaries; and a current-ranking Track page that reuses the existing queue.
- Acceptance: minimum group/ranking/Track identity and exact list/detail shape are validated offline; optional period/artwork never become identity; current-detail pagination, first/empty/error/retry/append-failure/cancel/stale/disposal state are explicit; switching discovery type and returning from a ranking preserve prior state; strict Rust/Dart checks, Flutter regressions, Linux packaging, and packaged Bridge integration pass.
- Effort: high but finite because the existing Discover route, Track presentation, queue, and request/Bridge patterns are reusable.
- Risk: medium; list editorial metadata is volatile, one list has no current period, and `topId` selects the service's current period rather than a historical snapshot.
- Non-goals: ranking history/period selection, subscriptions, third-party charts, personalization, mixed home shelves, comments, mutation, a generic recommendation/catalog runtime, or a navigation/state-management framework.

### 2. Track availability and quality representation — deferred

- Provenance: `ROADMAP.md` M3 availability/quality direction and the outstanding authenticated playback observation.
- User value: a truthful explanation of unavailable content and resolved quality.
- Current evidence gap: no sanitized unavailable/region/VIP Track row exists, and the corrected authenticated playback path still awaits user observation. Deriving restrictions from general metadata or anonymous vkey failure would be speculative.
- Effort: medium once representative evidence exists.
- Risk: high without that evidence.
- Non-goals: guessing entitlement, exposing unsupported quality choices, or changing media resolution from file metadata alone.

### 3. Heterogeneous QQ Music home feed — deferred

- Provenance: `ROADMAP.md` M3 home/recommendation direction.
- User value: richer editorial discovery.
- Current evidence gap: the previously observed shelves have multiple volatile card/style shapes and tracking metadata, while rankings provide a smaller coherent QQ-native route.
- Effort: high.
- Risk: high without a stable section contract.
- Non-goals: copying the official home layout, retaining exposure/tracking payloads, or building a generic card runtime.

## Selection

Current QQ ranking lists rank first because list/detail identity, current-period behavior, exact Track pagination, and a finite Discover → ranking → queue route are now evidenced. The selected slice treats period as optional display state and always loads the service's current `topId`; historical periods remain out of scope.
