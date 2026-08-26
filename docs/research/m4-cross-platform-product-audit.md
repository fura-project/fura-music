# M4.6 Cross-Platform Product Audit — 2026-08-27

## Audit boundary

This bounded audit reviewed Theme, Authentication, the retained App Shell, Library, Playlist, Search, Discover, Album, Artist, favorite Albums/Artists, mini and expanded Now Playing, Queue, and Lyrics against the current 360 px, medium, desktop, resize, light/dark, keyboard, pointer/touch, focus/return, loading, empty, error, retry, selected, and playing implementation and regression evidence. It did not access QQ Music, read stored credentials, claim unavailable target hardware, create screenshots as product evidence, or authorize new features.

## Evidence matrix

| Area | Current evidence | Exact limit or gap |
| --- | --- | --- |
| Material light/dark | One centralized official-Flutter theme, direct theme unit tests, dark Auth/Library application regression, and dark shared header/tile/state/selector component coverage. No major page uses fixed product-background colors; remaining black/white values are bounded artwork/QR contrast overlays. | This is rule/component evidence, not manual visual inspection of every page on every display. |
| 360 px compact | Auth, App Shell, Library, Playlist, Search types/states, Discover sections/states, catalog headers/Track rows, saved collections, Now Playing, Queue, and modal Lyrics/volume have compact regressions and no-overflow assertions. | Text-scale extremes and every platform font renderer are not claimed. |
| Medium and desktop | Secondary selectors have medium/desktop coverage; primary shell, catalog headers/rows, saved-collection grid transitions, Discover resize, Queue dialogs, expanded Now Playing, Lyrics dialogs, keyboard/context actions, and focus restoration have wide evidence. | Exact 520/600/760/820/840/900 threshold boundaries are not all independently enumerated. |
| Resize and retained state | Compact-to-wide Search/Discover, saved collections, local Album/Artist/Playlist overlays, scroll restoration, queue ownership, and current-Track routes preserve state in existing regressions. | Apple/Windows window-manager behavior and physical-device rotation are unavailable here. |
| Keyboard, pointer, touch, focus, back | Primary navigation, compact menus, Track context actions, transport shortcuts, modal focus, retained-return focus, AppBar/platform/desktop back, semantic tap, and mobile long press are covered. | No new correctness failure appeared in this audit. |
| Loading/empty/error/retry | Search, Discover, Album, Artist, Ranking, Library, Playlist, Lyrics, playback, and Queue expose typed state and recovery behavior. Shared catalog panels provide labeled loading and one optional error live region. | Favorite Albums and Favorite Artists remain the clear exception: each duplicates a bare loader plus private empty/error Columns, loading has no page label, and asynchronous initial failures have no live region. |
| Selected/playing | Navigation destinations, Queue current position, playback stage/status/progress, lyric line/word selection, and retained current Track transitions have regressions over the single playback owner. | Live QQ CDN behavior remains the separate user-operated M1 evidence gap. |
| Platform/build | Linux x64 Release and packaged typed-Bridge smoke pass; the prior Android 16 x64 signed-out runtime evidence remains bounded and development-only. | Apple/Windows runtime and physical Android playback remain unverified; HD-001 still blocks release identity/signing. |

## Ranked candidates

### 1. Favorite collection state language — selected

- **Provenance:** M4.3/M4.6 and M4 exit criteria 1, 3, 4, and 6; reproduced accessibility/state inconsistency in both saved-collection pages.
- **User value:** favorite Albums and Artists communicate loading, empty, service failure, retry, and account recovery with the same predictable Material grammar as the rest of the product, including meaningful assistive announcements.
- **Current problem:** both pages duplicate a bare spinner and private empty/error Columns; loading has no collection-specific semantic label, and asynchronous errors are not live regions.
- **Scope:** migrate only initial loading/empty/error/authentication presentation in `FavoriteAlbumsPage` and `FavoriteArtistsPage` to the existing bounded shared panels; preserve exact controller stages, keys, failure distinctions, retry/sign-in callbacks, content collections, append footers, refresh, paging, navigation, and playback owner.
- **Acceptance criteria:** both pages expose collection-specific labeled loading; empty/error/account states use the shared Material panel; each error/account state owns one live region and the exact eligible recovery action; 360 px has no overflow; content/paging/navigation remain unchanged; focused and full validation pass.
- **Effort:** Medium.
- **Risk:** a mechanical conversion could collapse credential cleanup failure copy, expose retry for terminal account states, or accidentally alter retained content/paging behavior.
- **Explicit non-goals:** collection cards/rows, append footers, refresh semantics, controllers, failure enums, Provider/Bridge/Rust changes, navigation, Library/Playlist state rewrites, or new favorite mutation.

### 2. Adaptive threshold-boundary regression matrix — deferred

- **Provenance:** M4.6 and M4 exit criteria 2, 3, and 6.
- **User value:** exact boundary tests could detect future control overlap or state loss at the shell and page transition widths.
- **Current problem:** representative compact/medium/wide and resize tests pass, but not every exact threshold is enumerated.
- **Scope:** after the selected state slice, decide whether a small parameterized test can cover only product-critical 520/840 shell boundaries without duplicating every component test.
- **Acceptance criteria:** if selected later, prove mounted destination/actions, no exception, retained controller identity, and correct NavigationBar/Rail switch immediately around each chosen threshold.
- **Effort:** Low.
- **Risk:** brittle implementation-detail tests with little user value.
- **Explicit non-goals:** testing every numeric breakpoint or changing breakpoints without a reproduced failure.

### 3. M4 checkpoint review — deferred

- **Provenance:** M4.7 and M4 exit criterion 7.
- **User value:** a criterion-by-criterion review can decide whether the default Material baseline is stable or whether another high-value gap remains.
- **Current problem:** the selected favorite-state inconsistency is still open, so checkpoint review would be premature.
- **Scope:** review only after the selected slice and subsequent global ranking.
- **Acceptance criteria:** verify every M4 exit criterion, architecture/scope drift, debt triggers, evidence limits, and unresolved high-value gaps.
- **Effort:** Review.
- **Risk:** turning a checkpoint into a project stop or overstating unavailable platform/live-service evidence.
- **Explicit non-goals:** project completion, release readiness, theme-persona implementation, or waiting for the locally scoped M1 user observation.

## Selection

Favorite collection state language is the highest-value finite task. It closes the one directly reproduced initial-state/accessibility inconsistency found across the integrated product while reusing an already accepted presentation component and leaving collection content, controllers, navigation, playback, and Rust boundaries untouched.
