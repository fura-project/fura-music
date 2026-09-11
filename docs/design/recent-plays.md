# Recently played and signed-out navigation

**Source:** Maintainer request and three attached screenshots, 2026-09-08. The first generated desktop image is the visual reference; the official Windows QQ Music image establishes the intended cloud-history semantics. The third image reproduces the unwanted guest MY MUSIC section.

**Execution mode:** `HUMAN_GATED_REGRESSION`. **Visual acceptance:** pending.

## Authorized scope

- Hide personal music navigation while signed out, including MY MUSIC, Liked, recent plays and personal playlists. Home, Discover, Search, Settings and sign-in remain reachable at desktop, rail and compact sizes.
- Introduce a Material 3 recent-plays destination following the supplied hierarchy: title, Songs count, playback/refresh/search controls, numbered artwork/Track/Artist/Album/duration rows, and retained Shell/player.
- Reuse Liked's long-list behavior. A shared `PagedTracksController` now receives a bounded page operation factory, while `PlaylistDetailController` retains only playlist identity adaptation. The existing scroll predictor and incremental search index are reused. No duplicate page pump or invented history playlist is introduced.
- Preserve the user's intended same-account QQ cloud history. Session-only Home recommendation seeds are not a data source for this page.

## Current implementation boundary

The sidebar/navigation composition remains retained; the latest authorized page corrections are recorded below. Production now injects a typed Rust-backed cloud source. `PagedTracksController` still exclusively owns serial paging, adaptive prefetch, incremental full search, refresh snapshot retention, retry/backoff, cancellation and stale-result suppression; recent history has no parallel scheduler or playlist identity.

The corrected official read contract uses `PlayRecentlyRead.GetPlayRecentlyInfo` with `type=2 / updateTime=0`. Core bounds the snapshot to 8 MiB / 5,000 raw records, retains it only in the exact authenticated session, and serves 1–100-row local pages with omitted-record accounting. Refresh replaces that snapshot; no 2,500-row total is inferred from a screenshot. See the [protocol evidence](../research/qqmusic-recent-plays-evidence.md). The maintainer confirmed successful loading of 500 records on 2026-09-09; writeback and broader cross-client ordering/refresh remain separate evidence.

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

## Earlier Human corrections, 2026-09-09

The latest three Human screenshots/request authorize only:

1. A single page canvas for Recent Plays, matching other playlist pages: normal rows are transparent, with existing InkWell hover/focus/pressed state layers and current-Track text/icon indications retained.
2. A dynamic header: one lazy `CustomScrollView` scrolls the large title/subtitle away, and the existing Shell top-search slot crossfades to a semantic small title. Local playback/refresh/search/table controls remain pinned with an opaque canvas. Short viewports (including a visible soft keyboard) let the controls scroll so they remain reachable. The viewport never changes height when the top slot changes. Real title measurement supports text scaling; a 12 px return threshold buffer prevents boundary chatter. Focused global search defers replacement until focus leaves. Navigation preserves position and reduced motion removes the crossfade duration.
3. Restore matching content/toolbar canvas colors in Settings and playlist detail. Their moving transition backing uses the existing `scaffoldBackgroundColor` (`surfaceContainerLowest` in this theme) at full opacity; only content fades. This addresses the earlier mismatch with `surface` without removing clipping or allowing the retained page to paint through.

`agy` / Gemini 3.8 Flash (High) was consulted separately on row states, collapsing title/accessibility, and backing surfaces. Its advisory cautions about focus, semantic headings, threshold chatter and opaque sticky headers were checked against local implementation. It did not receive private screenshots, account data or repository context, and did not edit files. Existing composition remains Human authority.

Primary technical references: [Flutter ColorScheme roles](https://api.flutter.dev/flutter/material/ColorScheme-class.html) describes tone-based surface roles; [PinnedHeaderSliver](https://api.flutter.dev/flutter/widgets/PinnedHeaderSliver-class.html) supports dynamically sized pinned controls and a measured scrolling-title handoff. A tinted surface is not inherently outside MD3: this defect was inconsistent roles for one continuous canvas, not a rule that MD3 always requires white.

The candidate remains pending Human visual review. Synthetic renders and interaction tests do not self-accept aesthetics or claim additional cloud behavior.

### Candidate validation for this correction

- Changed Dart files format cleanly; `dart analyze` passes.
- Complete Shell/widget suite: 79 passed. Supplemental recent/paging/search/controller selection: 38 passed, including the final title-threshold/focus/retention checks; these sets overlap and are not a summed full Flutter test count.
- Seven gated canonical render checks pass. Inspected `/tmp/fura-recent-plays-desktop.png`, `/tmp/fura-recent-plays-desktop-collapsed.png`, `/tmp/fura-recent-plays-mobile.png`, `/tmp/fura-recent-plays-mobile-collapsed.png`, dark/reduced-motion, Settings desktop/compact, and playlist desktop/compact plus entry frames. Content is synthetic, CJK/Material fonts are loaded, and images remain outside Git.
- Linux Release builds. Human review launcher: `/tmp/fura-ui-review-002dr3b6/run.sh`; syntax and shared-library resolution pass. The Agent did not launch the account app. The corrected QQ read implementation is retained in this bundle.
- Visual acceptance remains pending; no Core, Provider API, generated Bridge or runtime protocol behavior was changed by the UI batch. No push or commit.

## Adaptive collection-header correction, 2026-09-09

**Source:** Maintainer's three comparison screenshots and explicit instruction to make Recent Plays follow the already-established Liked collapsing-header model. This supersedes only the earlier Shell-title handoff mechanics; it does not reopen row density, paging, cloud protocol, playback, Sidebar or player design.

- The scrolling title/subtitle still leaves the viewport naturally, but the pinned Recent Plays controls now have real expanded and collapsed compositions. Once the collection passes the same 56 px threshold used by Liked, the collapsed page header completely replaces the Shell AppBar instead of leaving a second title bar above a separate controls panel.
- Extended desktop collapses to one row containing the semantic page title, selected Songs/count indicator, compact Play and Refresh, page search and the existing Shell account actions. Medium/compact layouts use two rows: title/search/Shell actions first, count and page actions second. The desktop table header remains aligned below the adaptive header.
- Play and Refresh retain separate 48 dp Material icon-button targets with an explicit 8 dp visual gap. Search remains enabled from the collapsed state. The compact unknown-total label uses a truthful `count+` form to avoid overflow without claiming an exact total.
- The header does not expand merely because removing the Shell AppBar changes layout. It stays collapsed until the user deliberately scrolls back toward the first four pixels, matching Liked's return-to-header protection. Global-search focus temporarily suppresses page-header takeover so the focused field is not unmounted; leaving focus reveals the pending collapsed state without moving the list.
- Viewports shorter than 480 px keep the ordinary Shell AppBar and let the controls scroll instead of pinning a header larger than the available list. Reduced motion changes expanded/collapsed composition immediately. Retained navigation and responsive resizing preserve the collection scroll offset.
- A short, sanitized AGY/Gemini 3.8 Flash (High) Material check recommended 8 dp between adjacent 48 dp icon buttons, 12–16 dp between semantic groups, a single page-owned collapsed top surface, and immediate reduced-motion state changes. No screenshot, account content or repository data was shared; the implementation remained local and maintainer-directed.

Candidate review renders are `/tmp/fura-recent-plays-desktop.png`, `/tmp/fura-recent-plays-desktop-collapsed.png`, `/tmp/fura-recent-plays-medium-collapsed.png`, and `/tmp/fura-recent-plays-mobile-collapsed.png`. The synthetic fixture uses an explicitly loaded CJK/Material font for readable geometry. Desktop, medium and compact renders show one top surface with no overflow; aesthetic acceptance remains Human review.
