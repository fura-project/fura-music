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
- The existing product does not yet support downloads or batch Track mutation, so the candidate uses the truthful supported actions: play all, refresh, loaded-result search, Queue insertion, and Album/Artist navigation.
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
