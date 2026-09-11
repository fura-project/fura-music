# Liked Songs Design Source

**Status:** Human Approved

**Approval date:** 2026-08-28

## Stitch identity

- **Project:** `3692648008202843392` — Melodia for QQ Music
- **Desktop screen:** `291efbb8c5754928b66a51eb83a21e53` — 喜欢 - flutterustmusic (桌面管理版)

The Stitch frame is the visual source of truth for the current Liked Songs implementation. The maintainer's supplied official QQ Music screenshot is information-architecture reference only, not a pixel-copy source.

## Human constraints

- Follow the approved Material 3 reinterpretation: persistent desktop Sidebar, Main Region Top Bar, dense management-oriented Track table, and persistent player.
- Preserve the existing wide/compact Shell, retained state, Queue/playback ownership, keyboard/pointer/touch access, and truthful loading/error/empty behavior.
- Bind this page only to the typed built-in liked-songs collection. Do not infer it from a translated title or parse QQ-owned identity in Flutter.
- Do not fabricate downloads, audiobooks, liked videos, or another unsupported collection merely because a reference frame contains those controls.
- No compact Stitch frame is approved. Compact/mobile must be a faithful Material 3 translation of the same hierarchy and remains subject to maintainer visual review.

Home remains deferred and unaccepted. This source record authorizes only the current Liked Songs page.

## Candidate comparison

- The desktop composition follows the approved persistent Sidebar, Top Bar, dense Track table, page actions, search, current-row state, and persistent player hierarchy.
- The existing product does not yet support downloads or batch Track mutation, so the candidate uses the truthful supported actions: play all, refresh, incremental full-collection search, Queue insertion, and Album/Artist navigation.
- The official reference's audiobook and video collection categories are outside the current product capability and are not shown.
- No compact source frame exists. The 390 px candidate translates the same title, categories, actions, current-row state, metadata, context actions, Mini Player, and Bottom Navigation without introducing a second product composition.

## Liked-root and collapsing-header revision

**Design source:** Maintainer-provided compact-rail and extended-sidebar screenshots plus explicit requirements, 2026-09-04.

- The visible primary `Library` destination is removed. The existing fourth retained destination now presents `喜欢`/Liked and always resets to the Liked root when selected.
- Extended desktop keeps one Liked destination and the existing direct playlist list; compact and medium navigation use the same Liked destination. Internal legacy collection state remains only to avoid deleting data/controller code in this UI pass.
- Home's former Library actions now open Liked. When QQ Music does not identify a built-in liked-songs playlist, Liked keeps its real category tabs and shows a truthful unavailable Songs state so Playlists and Albums remain reachable.
- Scrolling any active Liked collection beyond the header threshold transfers the live compact header into the Shell's topmost application-bar position instead of leaving it below the ordinary Top Bar. The ordinary QQ Music search is removed for that state while the Shell account actions move into the same live header. Compact places title/search/account actions first with tabs/actions below; desktop places title, tabs, collection actions, search, and account action in one bounded row. The full header returns only when the user scrolls back toward its start, avoiding relayout-driven oscillation when the application bar is removed.
- Returning from a retained playlist detail preserves the selected Liked tab, grid scroll position, and focus. The Shell keeps a stable base wrapper so opening a compact detail no longer recreates the Liked page.
- Reduced motion makes the expanded/collapsed header swap immediate. Automated 390 px and wide renders remain Human-review evidence rather than visual acceptance.

### Collapsed action-spacing correction, 2026-09-09

The maintainer's comparison identified that compact Play and Refresh targets visually touched in both the desktop one-row and mobile two-row collapsed headers. Their existing 48 dp Material targets and hierarchy remain unchanged; an explicit 8 dp gap now separates them at both breakpoints. Geometry regressions assert the rendered gap, and refreshed CJK-font review artifacts are `/tmp/flutterustmusic-liked-desktop-collapsed.png` and `/tmp/flutterustmusic-liked-mobile-collapsed.png`. This is a bounded spacing correction, not a redesign of the approved Liked composition; final visual judgment remains Human review.

## Incremental full-collection search revision

**Evidence source:** Maintainer-operated 1,032-row Liked search and explicit follow-up on 2026-09-08.

- The Core's evidenced 100-row request maximum remains a per-request boundary. Ordinary browsing uses the bounded viewport prefetch below; a non-empty Songs query serially drains the remaining pages without requiring repeated downward scrolling.
- Search publishes the current local matches after every successful page. It does not wait for the complete playlist before showing a later-page result, and clearing the query stops the automatic drain after its current bounded request.
- Successful search pages use a 180 ms cadence rather than the earlier unconditional 500 ms wait. A transient failure still receives finite one-second/three-second backoff, and the first successful recovery page is followed by a conservative 500 ms interval. Requests remain single-flight and ordered.
- A page-local incremental index stores normalized presentation copies of title, subtitle, credited Artists, and Album title. It handles case, full-width ASCII, punctuation, common Latin accents, and terms split across fields. Exact equality/prefix/substring/token matches rank before approximate matches.
- Approximate matching is deliberately limited to Latin/number tokens of at least four characters: four-to-seven-character tokens allow one edit and longer bounded tokens allow two, including adjacent transposition. Short and CJK tokens do not use edit-distance expansion. The UI explicitly labels possible results rather than presenting them as exact.
- The index rebuilds when refresh replaces the loaded prefix, extends when a page appends, and never persists account content. Synthetic coverage includes a possible result beyond row 1,000, progressive result publication, cancellation/retry, and unrelated/short-query rejection. Real perceived latency and result relevance remain Human-review evidence.

## Viewport-aware loading revision

**Scope source:** Maintainer request to explore, plan, and implement smoother up/down playlist loading, 2026-09-08.

- Liked Songs and ordinary playlist detail share one layout-neutral scroll adapter. Downward movement estimates the visible trailing row from current scroll metrics and requests a lookahead of 50–200 rows based on scroll speed and a smoothed successful-page latency. This replaces their separate fixed 720 px footer triggers. Initial mount alone does not drain the playlist.
- The controller translates that demand into at most two serial 100-row requests per outstanding scroll demand, including a request already in flight. Short, duplicate, or omitted pages consume the budget as well. Once the horizon is covered, no further page is fetched until there is new demand; reaching the end of a scroll gesture does not itself enqueue a page.
- Upward scrolling withdraws pending browse demand and reuses retained metadata. Any active page may finish; appending never evicts earlier rows or intentionally moves the scroll anchor. The existing lazy ListView builders still mount only the viewport/cache neighborhood. This is advance prefetch with retained session data, not sparse random-access loading, an LRU metadata cache, or cross-launch persistence.
- Manual loading, browse prefetch, and full-collection search have one append scheduler. Search promotes an active prefetch, consumes the same progressively published rows/index, and does not fetch that offset again. Repeated actions cannot bypass an active cadence/backoff; search cancellation withdraws its drain after the active page, and refresh/dispose invalidate older work.
- Browsing stops on append failure and preserves the explicit retry control. Search retains its finite transient backoff policy. Filtered lists and inactive Liked sections do not generate browse demand. Neither path changes QQ request sizes, credentials, provider cursors, search matching rules, Queue ownership, header layout, or navigation.
- Offline policy/controller/Widget checks cover early fetching, one/two-page bounds, retained upward scroll position, lazy row construction, search handoff, backoff coalescing, short/omitted pages, failure retry, refresh, and disposal. Real QQ latency and perceived scrolling smoothness still require maintainer-operated review; no real-account benchmark is inferred from synthetic timing.
