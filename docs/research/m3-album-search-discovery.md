# M3 Direct Album Search Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` defines Album search as typed Search value `2`, maps it through a dedicated `AlbumSearch` model, and recognizes numeric Album ID, Album MID, name/title, artwork identity, release text, and structured Artist rows. Its current operation uses the Mobile method, so it supports type and model semantics rather than proving the Desktop envelope selected here.
- feeluown-qqmusic commit `241a9678bcd26e88d19e08e5da8048018f06e330` independently uses `music.search.SearchCgiService/DoSearchForQQMusicDesktop`, maps type `2` to `data.body.album.list`, and requires `albumID`, `albumMID`, `albumName`, artwork, release text, Track count, and structured Artist rows.
- A bounded anonymous real-service probe used the exact Desktop named-key envelope without Cookie, token, stored credential, user identifier, or user data. It requested five rows per page and received five pages of five rows, stable total `25`, advancing current/next pages, and terminal `nextpage: -1` on page five.
- All 25 observed rows carried a positive numeric Album ID, nonblank Album MID, and nonblank title. Album identity overlap across the five pages was zero. The response placed rows at `data.body.album.list` and pagination at `data.meta`.
- The probe printed only codes, counts, key names, booleans, JSON value types, and overlap size. It did not print, retain, or commit the query, Album/Artist identity, title, artwork, response body, or result content.

Reference implementations remain research evidence only. The runtime will call QQ Music directly and will not import third-party response models or depend on a third-party server.

## Ranked candidates

### 1. Direct Album Search — selected

- Provenance: `ROADMAP.md` M3 Search/Album directions, the deferred candidate from the prior Artist Search discovery, two current independent implementations, and a successful bounded anonymous exact-size/terminal-page probe.
- User value: users can reach a known Album directly and continue through the already implemented Album Tracks and queue/playback path without first finding a matching Track or Artist.
- Problem: the downstream Album surface is implemented, but the current Search type control exposes only Tracks and Artists.
- Scope: one provider-neutral paged Album-search contract; direct bounded anonymous QQ operation; Provider mapping to existing `AlbumSummary`; one cancellable Bridge page handle; an Albums option in the existing Search type control with independent query/result/pagination/cancellation state; and direct handoff to the existing Album page while preserving all Search-type state.
- Acceptance: exact page/total/continuation and minimum Album identity/title validation have offline regressions; empty or structurally invalid identities do not become actions; query replacement and type switching cannot surface stale results; returning Album → Search restores the Albums type and prior results; Album Track/queue behavior reuses existing controllers; strict Rust/Dart checks, Flutter tests, Linux packaging, and packaged Bridge integration pass.
- Effort: medium-high but finite because the type-switch interaction and downstream Album route already exist.
- Risk: medium; the two current implementations use different Mobile/Desktop methods, and optional display fields must not become required protocol identity.
- Non-goals: mixed-result ranking, playlist/MV/user Search, suggestions/history/hot words, Album metadata expansion or mutation, Artist biography/follow, a generic Search union/runtime, or a navigation/state-management framework.

### 2. QQ Music ranking lists — deferred

- Provenance: `ROADMAP.md` M3 QQ-native catalog-flow direction and current public Toplist references.
- User value: query-free chart discovery can feed the existing Track queue and complement recommended playlists.
- Current evidence gap: list/detail identity, current-period selection, Track-page bounds, and editorial metadata have not yet been cross-validated by a bounded product/protocol pass.
- Effort: high.
- Risk: medium-high because periods and editorial list metadata are externally controlled and may require a new list/detail surface rather than reuse a completed route.
- Non-goals: chart history, third-party charts, heterogeneous Home shelves, or personalization.

## Selection

Direct Album Search ranks first because its real Desktop response honors exact typed pagination, supplies the existing Album route's identity, and closes a visible user path with no new destination or navigation architecture. Rankings remain authorized, but their list/detail/period contract needs a separate discovery before implementation.

## Implementation outcome

Implemented on 2026-08-26 as the seventh finite M3 slice. The client sends the exact Desktop type-2 request and rejects invalid pagination or Album identity before Domain mapping; Provider, Domain, and Bridge reuse opaque `AlbumSummary` and keep query/Album content out of diagnostics. Flutter adds an independent Albums controller to the existing type control, suppresses replacement/disposal races, preserves all three Search types, and returns from the existing Album Tracks page without reloading Album Search. Rust formatting, 203 offline Rust tests, strict Clippy, strict Dart formatting/analysis, all 216 Flutter tests, a 360px three-type adaptive regression, the Linux x64 Release bundle, and packaged typed-Bridge integration pass. Four live QQ/WeChat tests remain gated, and no live application compatibility or authenticated downstream playback claim is made.
