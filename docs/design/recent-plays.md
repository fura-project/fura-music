# Recently played and signed-out navigation

**Source:** Maintainer request and three attached screenshots, 2026-09-08. The first generated desktop image is the visual reference; the official Windows QQ Music image establishes the intended cloud-history semantics. The third image reproduces the unwanted guest MY MUSIC section.

**Execution mode:** `HUMAN_GATED_REGRESSION`. **Visual acceptance:** pending.

## Authorized scope

- Hide personal music navigation while signed out, including MY MUSIC, Liked, recent plays and personal playlists. Home, Discover, Search, Settings and sign-in remain reachable at desktop, rail and compact sizes.
- Introduce a Material 3 recent-plays destination following the supplied hierarchy: title, Songs count, playback/refresh/search controls, numbered artwork/Track/Artist/Album/duration rows, and retained Shell/player.
- Reuse Liked's long-list behavior. A shared `PagedTracksController` now receives a bounded page operation factory, while `PlaylistDetailController` retains only playlist identity adaptation. The existing scroll predictor and incremental search index are reused. No duplicate page pump or invented history playlist is introduced.
- Preserve the user's intended same-account QQ cloud history. Session-only Home recommendation seeds are not a data source for this page.

## Current implementation boundary

The sidebar/navigation and page candidate remain unchanged. Production now injects a typed Rust-backed cloud source. `PagedTracksController` still exclusively owns serial paging, adaptive prefetch, incremental full search, refresh snapshot retention, retry/backoff, cancellation and stale-result suppression; recent history has no parallel scheduler or playlist identity.

The evidenced read contract uses `begin`/`num`, with `num` bounded to 100. Because the observed response does not guarantee a total or continuation flag, Core exposes a safe known lower bound after a full page and closes the collection on a short page; it never derives a 2,500-row transport total from the Windows screenshot. Raw invalid records advance the source offset and increment the existing omitted count. `unPlayTime` remains an opaque Client value because its unit and semantics are not established, and it is not presented as a timestamp.

Read success does not imply write support. There is no playback-history upload and the Provider does not advertise `RecentHistoryWrite`. A valid empty response is distinct from authentication rejection, unsupported/service failure, malformed response and account replacement. Production's former not-connected state remains available only when a caller deliberately supplies no gateway, such as the bounded UI regression fixture.

## Reference translation

- Existing Material 3 color roles, typography and rounded controls are used; existing Shell/sidebar/player geometry stays intact.
- A dense desktop table becomes artwork plus title/metadata rows and a full-width search field at 390 px.
- Reference downloads, video history, batch actions and like toggles are not copied because this task has no verified matching capability for them.
- Cloud success indicators appear nowhere in the candidate. Even a future successful cloud read does not establish outbound history reporting or immediate bidirectional sync.

## Human review and remaining acceptance

1. Signed out: no personal music entry at 390, 900 or 1440 px; public browsing and login still work.
2. Signed in: recent plays is reachable, the selected destination and Back behave correctly, and resizing preserves the page.
3. Review synthetic desktop/compact table density and controls separately from the real not-connected screen.
4. Read acceptance remains Human-gated: verify account identity (including QQ versus WeChat identity), records created in an official client appearing in Fura, ordering/pagination while new plays arrive, refresh, credential rejection and account switching. Record only coarse results, never credentials or personal response content.
5. Write acceptance is separately blocked on an ordinary QQ-session protocol. If that evidence becomes available, verify a Fura-only test play first through a fresh cloud read and then in an official client; neither step may be inferred from the other.

No aesthetic acceptance or real QQ sync success is inferred from offline tests or screenshots.

## Current validation, 2026-09-08

- `dart analyze`: pass. Full Dart format gate: 252 files, zero changes.
- `flutter test`: all 498 tests pass. Recent-history coverage now also includes the production Gateway, unknown-total propagation, transient refresh retention and explicit credential-rejection cleanup.
- Rust workspace/all-target tests: 436 pass; 12 explicit live/Human tests remain ignored. `cargo fmt --check` and strict workspace/all-target Clippy pass.
- The original consecutive-row keyboard traversal test passes with its assertions unchanged after isolating sidebar/rail focus traversal.
- Linux Release builds successfully. No actual-account runtime test or Windows build/run was performed.
- Canonical review renders: `/tmp/fura-recent-plays-desktop.png` (1440×960), `/tmp/fura-recent-plays-mobile.png` (390×844), `/tmp/fura-recent-plays-unavailable-1440.0.png`, `/tmp/fura-recent-plays-unavailable-390.0.png`, `/tmp/fura-guest-navigation-1440.0.png`, `/tmp/fura-guest-navigation-390.0.png`. Loaded test fonts show CJK and Material icons; artwork uses real fallback rendering. These files stay outside Git. Contentful images remain synthetic UI evidence; production now requests the account cloud source, whose real content and ordering still require Human acceptance.
