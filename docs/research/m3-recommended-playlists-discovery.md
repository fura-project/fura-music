# M3 Recommended Playlists Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` implements offset-paged recommended playlists with `music.playlist.PlaylistSquare/GetRecommendFeed`, `From`, and `Size`, and models `List[*].Playlist.basic`, `HasMore`, and `FromLimit`.
- Yyyangshenghao/simple-music commit `301d1ca159e88f6226acbc95fb01a28a99234e79` independently implements the same module, method, and offset/size request, maps the nested playlist identity/title/cover/creator/count shape separately from other QQ playlist responses, and uses the results as an existing discovery flow.
- A bounded anonymous POST requested ten rows with `From: 0` and `Size: 10`. It returned zero global/module codes, exactly ten entries, boolean continuation, numeric `FromLimit` metadata, and the independently documented `Playlist.basic` shape with playlist identity, title, cover, creator, track count, and play count fields.
- Follow-up bounded probes established that `FromLimit` is not a next-page cursor: using it as `From` skipped to a terminal non-overlapping page, while `From: 0` then `From: 10` returned two exact ten-row, non-overlapping pages and retained the same `FromLimit`. The implementation therefore advances by the raw returned row count and does not expose `FromLimit` as a cursor or total.
- The probe used no Cookie, token, stored credential, user identifier, or user data. It printed only codes, field names, counts, and JSON value types; no playlist identifier, title, creator, artwork URL, response body, or content was printed, retained, or committed.

Reference implementations remain research evidence only. The runtime will call QQ Music directly and will not import third-party response models or depend on a third-party server.

## Ranked candidates

### 1. Recommended playlists discovery — selected

- Provenance: `ROADMAP.md` M3 home/recommendation direction, product-completeness audit after Search/Album/Artist browsing, two current independent implementations, and a successful bounded anonymous probe.
- User value: a user can discover QQ Music playlists without already knowing a search query, open one through the existing detail flow, and play its Tracks through the existing queue.
- Problem: the authenticated application currently opens on the user's own collection and exposes only query-driven catalog discovery.
- Scope: one provider-neutral recommended-playlist page contract, a direct bounded anonymous QQ operation, provider-owned public-playlist identity, one cancellable Bridge page operation, an adaptive discovery surface with retry/pagination, and handoff to the existing authenticated playlist-detail and queue flow.
- Acceptance: first-page/empty/error/retry/pagination/append-failure/cancel/stale/disposal states are explicit; returned playlist identity/title and optional artwork/count are validated; opening a recommendation uses the existing detail page rather than duplicating Track loading; returning preserves discovery state; offline client/Provider/Bridge/controller/navigation/widget tests, strict analysis, and Linux packaging pass.
- Effort: high but finite.
- Risk: medium; the response is a specialized nested playlist shape and must not be forced through a raw user-library response model.
- Non-goals: heterogeneous home-feed cards, personalization claims, daily recommendations/radio, ranking lists, playlist mutation/follow, comments, Search changes, a navigation framework, or a generic recommendation runtime.

### 2. Heterogeneous QQ Music home feed — deferred

- Provenance: `ROADMAP.md` M3 home/recommendation direction and successful anonymous coarse probing of both current and legacy module names.
- User value: a richer, content-driven landing surface with multiple QQ-native sections.
- Current evidence gap: four returned shelves contain multiple volatile card and style shapes, exposure/cache continuation, and content-refresh metadata. Mapping them before one stable discovery vertical slice would introduce a broad recommendation abstraction without proven UI needs.
- Effort: high.
- Risk: high.
- Non-goals: copying official QQ Music layout or retaining tracking/exposure payloads.

### 3. Track availability and quality representation — deferred

- Provenance: `ROADMAP.md` M3 availability/quality direction and the pending M1 playback evidence boundary.
- User value: truthful explanation of unavailable content and selected quality.
- Current evidence gap: no sanitized unavailable/region/VIP action-row evidence exists, and the corrected authenticated playback path still awaits user observation. Inferring restriction or quality semantics now would be speculative.
- Effort: medium after representative evidence exists.
- Risk: high without that evidence.
- Non-goals: deriving entitlement from one vkey failure or exposing quality options from file metadata alone.

## Selection

Recommended playlists rank first because they add query-free discovery with a stable, bounded response and reuse the already proven public playlist-detail and queue path. This delivers a coherent QQ Music-native product gap without committing to the volatile heterogeneous home feed. Home shelves and availability remain authorized discovery candidates, not implicit implementation work.

## Implementation outcome

Implemented on 2026-08-26 as `QQMusicClient` direct anonymous loading → `RecommendedPlaylistsProvider` → provider-neutral `RecommendedPlaylistsPage` → single-use cancellable Bridge → adaptive Flutter Discover page. Public playlist rows use Provider-owned `catalog:<id>` identities and open the existing authenticated playlist-detail page; Flutter does not parse the identity or duplicate Track loading. Initial/empty/error/retry, append failure/retry, exact-offset pagination, cancellation, stale-result suppression, disposal, adaptive list/grid navigation, state preservation, and packaged Bridge cancellation have offline regression coverage.

Validation passed with Rust formatting, 182 offline Rust tests, strict Clippy, strict Dart analysis, 190 Flutter tests, Linux x64 Release build, and packaged Linux typed-Bridge integration. Four live QQ/WeChat tests remain separately gated and ignored. This evidence does not claim that the live recommendation endpoint or a recommended playlist's authenticated Track playback works for every account at this moment.
