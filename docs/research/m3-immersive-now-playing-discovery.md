# M3 Immersive Now-Playing Discovery — 2026-08-27

## Evidence

`PROJECT.md` names an immersive now-playing view as part of the core product experience. The current implementation has a capable repeated bottom bar plus adaptive queue, volume, and synchronized-lyric modals, but no full current-Track surface. The gap is directly reproducible from every authenticated page: a Track can be playing, yet the user cannot expand it into a retained artwork-and-lyrics view and return to the exact underlying page.

The existing authenticated presentation owner already retains one `QueuePlaybackController`, its foreground playback state, and its `LyricController` across every local page. All eight now-playing bars consume that same owner. The missing view therefore requires presentation composition only: no QQ request, credential access, Domain value, Bridge DTO, queue rule, audio backend, dependency, or navigation framework.

## Global ranking

### 1. Adaptive immersive now playing — selected

- Provenance: `PROJECT.md` core experience plus a bounded product-completeness audit.
- User value: expand the current Track into one deliberate artwork-and-synchronized-lyrics surface from any existing page, keep transport available, follow queue changes, and return without losing the originating state.
- Scope: one optional presentation callback scope around the existing authenticated route tree; one retained topmost now-playing page; one precise title/metadata entry action in the existing bar; adaptive wide artwork/lyrics and compact stacked artwork/lyrics composition; reuse the existing bar, queue, playback, lyric controller, and shortcuts.
- Acceptance criteria: no current Track means no entry; pointer/touch and keyboard can open the page; wide and 360 px layouts remain reachable without overflow; current Track changes update the page in place; an emptied queue is represented truthfully; AppBar/platform back restores the exact origin and its controller state; the expanded page cannot recursively reopen itself; full static/offline/Linux checks pass.
- Expected effort: medium, presentation-only.
- Risk: focus, nested Scaffold, and playback-shortcut ownership must remain singular while the underlying page stays mounted.
- Explicit non-goals: artwork palette extraction, blur/video backgrounds, gestures or swipe navigation, a mini-player rewrite, queue or audio changes, background playback, catalog routing from inside the expanded page, protocol/Domain/Bridge changes, and a navigation framework.

### 2. Favorite Artists — deferred

- Provenance: richer QQ Music library navigation.
- Evidence gap: current response references disagree on routing/pagination, anonymous behavior supplies no usable rows, and the proven shape does not provide the positive numeric Artist ID required by the existing route. Stored account credentials remain outside autonomous discovery.

### 3. Track availability and quality representation — deferred

- Provenance: explicit M3 direction and the pending playback evidence boundary.
- Evidence gap: no sanitized unavailable, region-filtered, VIP-entitlement, grey-row, or alternate-quality behavior exists. One failed media resolution cannot safely distinguish those states.

## Selection

Immersive now playing ranks first because it is an explicit core-experience requirement with a reproduced user-visible gap and a finite solution over already-validated state. It adds no external behavior and does not promote the recent catalog-navigation implementation into a generic routing system.
