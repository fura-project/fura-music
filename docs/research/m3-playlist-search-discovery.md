# M3 QQ Playlist Search Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` defines typed search value `SONGLIST = 3`, maps the result to a `SongListSearch` model, and follows service `nextpage` rather than deriving continuation from returned row count. Its current typed endpoint is the mobile search method, so it corroborates type, identity aliases, and pagination semantics rather than the exact Desktop envelope selected here.
- feeluown-qqmusic commit `241a9678bcd26e88d19e08e5da8048018f06e330` independently maps Desktop `music.search.SearchCgiService/DoSearchForQQMusicDesktop` type `3` to `body.songlist.list`. Its public 28-row playlist-search fixture uses numeric-string `dissid`, nonblank `dissname`, numeric `song_count`, and string `imgurl`. Its dedicated provider method remains disabled, so the repository is protocol/fixture evidence rather than a claim that its complete playlist-search product flow works.
- A bounded anonymous real-service probe sent the exact Desktop named-key request without top-level `comm`, Cookie, token, stored credential, user identifier, or user data. It returned zero global/module codes, exact requested page metadata, stable positive total across the first two pages, and service continuation for pages 1, 2, and 3.
- The three requested five-row pages returned 5, 4, and 5 playlist rows. All observed rows had a positive numeric-string `dissid`, nonblank `dissname`, nonnegative numeric `song_count`, string artwork, and object creator shape. The first two pages had no identity overlap. A short nonterminal page therefore must not be treated as the end; continuation comes from `nextpage`.
- The probes printed only codes, key names, page metadata, counts, field types, identity-validity booleans, and overlap size. They did not print, retain, or commit the query, playlist identity, title, creator, artwork, description, response body, or content.

Reference implementations remain research evidence only. Runtime requests will go directly to QQ Music, and neither third-party server behavior nor raw response models become project dependencies.

## Ranked candidates

### 1. Direct Playlist Search — selected

- Goal: let a user find a public QQ Music playlist by query, open it through the existing detail route, and hand its loaded Tracks to the existing queue.
- Provenance: `ROADMAP.md` M3 catalog Search and richer QQ-native navigation direction; two current source/fixture references; the bounded anonymous Desktop probe above; and an already implemented public-playlist detail/queue path.
- Scope: one provider-neutral paged Playlist-search result; direct anonymous type-3 QQ search; one small Provider contract; one single-use cancellable typed Bridge operation; a Playlists choice in the existing Search surface with independent retained state; and navigation into the existing playlist detail.
- Acceptance: exact request type and page metadata, positive playlist identity, nonblank title, optional artwork, nonnegative Track count, short nonterminal pages, empty/error/retry/replacement/cancel/stale/disposal state, and Search → playlist → Search state restoration have offline regressions. Strict Rust/Dart checks, Flutter tests, Linux packaging, and packaged Bridge integration must pass.
- Expected modules: `music-domain`, `provider-api`, `qqmusic-client`, `provider-qqmusic`, `bridges/flutter`, and the existing Flutter Search/navigation surface plus focused tests and generated bindings.
- Required tests: client request/response fixtures, Provider identity/error mapping, Bridge cancellation/redaction, Dart gateway/controller lifecycle, compact adaptive control, navigation/state preservation, full offline suites, Linux Release, and packaged typed-Bridge smoke.
- Known risk: QQ search may return fewer rows than requested while still advertising a next page; client/controller pagination must preserve the service page number and reject only incoherent metadata.
- Explicit non-goals: mixed Search results, playlist suggestions/history/hot words, creator profile navigation, playlist mutation/subscription, personalized ranking, comments, MV/user/lyric Search, a generic Search runtime, or a navigation/state-management framework.

### 2. Track availability and quality representation — deferred

- Provenance: `ROADMAP.md` M3 availability/quality direction and the pending authenticated playback observation.
- Evidence gap: the repository still has no sanitized unavailable/region/VIP Track row, and the corrected authenticated playback chain has not been observed by the user. Guessing entitlement from search metadata would be less reliable than the selected evidenced slice.

### 3. Heterogeneous QQ Music Home feed — deferred

- Provenance: `ROADMAP.md` M3 home/recommendation direction.
- Evidence gap: current Home shelves remain shape-heterogeneous and carry volatile editorial/tracking fields. A mixed card runtime would be larger and less coherent than the selected Search → existing playlist route.

## Selection

Direct Playlist Search ranks first because it is an authorized QQ-native catalog capability with current request/fixture evidence, explicit service pagination behavior, and a finite route into already tested detail and queue owners. The task reuses `PlaylistSummary` and the existing public catalog identity; it does not justify a heterogeneous Search model or broader Home abstraction.
