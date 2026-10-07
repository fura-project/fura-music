# Settings Shell

- **Design source:** Maintainer-provided desktop/mobile screenshots and explicit annotations, 2026-09-03–04; Stitch project `3692648008202843392`, screens `8e88b654ca6f4522853fd7dfb0fc1b84` and `0b0df5f6bc9b48b2b79c52d25e38f71c`
- **Status:** Implemented candidate; pending Human visual/runtime acceptance
- **Scope:** Settings navigation ownership, settings search, account-action visibility, responsive fallback, and Shell transition motion

## Desktop composition

Settings is a Shell state, not a content card inside the ordinary music Shell.

- The existing left navigation slot is reused at the same width.
- Entering Settings replaces music identity/destinations/playlists with:
  - a top-left Back control;
  - the `Settings` title;
  - `Appearance` and `Playback` destinations backed by existing real settings.
- The ordinary account identity and sign-in/sign-out actions are absent while Settings is open.
- The ordinary top QQ Music search becomes `Search settings` and filters the existing settings sections live.
- Search may return Appearance, Playback, both, or a truthful no-results state. It does not invent unsupported preferences.
- The persistent player remains owned by the Shell and is not recreated by Settings navigation.

## Responsive behavior

- At the extended desktop breakpoint, the full Settings sidebar replaces the full music sidebar.
- At the desktop rail breakpoint, a Settings rail reuses the rail slot with Back, Appearance, and Playback.
- Before Settings opens at the desktop rail breakpoint, its entry is pinned below the rail destinations at the bottom-left of the shared navigation slot. It is a real one-item Material `NavigationRail` destination with the same icon, label, state-layer, indicator, and keyboard grammar as the other medium-width destinations, rather than a standalone gear button.
- Compact layouts have no persistent left navigation slot, so Settings becomes a two-level hierarchy inside the retained Shell:
  - level one is a Settings category list with Back and functional Settings search;
  - level two contains the selected existing control and Back returns to level one before Settings exits;
  - Android/system Back follows the same level-two → level-one → previous-Shell order.
- The compact hierarchy exposes only Appearance and Playback because those are the settings with real storage and behavior today. Stitch's account sync, downloads, lyric preferences, network/privacy, gestures, updates, and sign-out entries remain visual references, not placeholder product claims.
- The compact primary bottom navigation is hidden while Settings owns the task flow, then restored on exit. The compact player remains Shell-owned and stays available when a Track is active.

## Motion

- Entering Settings moves the music navigation left while Settings navigation enters from the right; exit reverses the same motion.
- The top QQ Music search/account actions cross-fade and translate into the Settings search with the same direction.
- Settings content uses the existing Shell detail transition. Section/search result changes use a smaller Material-emphasized fade/translation.
- Compact level one enters level two from the right while the category list leaves to the left; Back reverses that direction.
- System reduced-motion disables the new navigation, top-bar, and content durations.

## Acceptance

At 1440×900:

1. Before opening Settings, the music sidebar, QQ Music search, and applicable account action are visible.
2. During entry and exit, both outgoing and incoming navigation/top-bar surfaces exist only for the bounded transition.
3. At the Settings endpoint, no music sidebar identity or sign-in/sign-out action remains reachable.
4. Appearance and Playback navigation select only their matching existing controls.
5. `Search settings` finds `dark` under Appearance, finds playback quality terms under Playback, and presents an explicit empty result for unmatched text.
6. Back restores the retained music Shell, original QQ Music search, account action, focus target, and page state.

At 390×844:

1. Settings opens on the category list without exposing a theme or quality control prematurely.
2. Appearance and Playback each open their own level-two page; the main bottom navigation stays hidden while the Shell-owned compact player remains available for an active Track.
3. Toolbar Back and system Back return from level two to the category list; a second Back exits Settings.
4. Mobile Settings search returns only real matching categories and selecting a result opens its level-two page.
5. No sign-in/sign-out action or unsupported Stitch category is exposed inside Settings.
6. Exiting Settings restores the compact primary bottom navigation; the hierarchy remains usable at 360 px and becomes immediate when reduced motion is enabled.

## Canvas correction, 2026-09-09

The Human reported that the earlier opaque-transition fix left an unwanted pale panel behind Settings and playlist detail. The backing now uses the same `Theme.scaffoldBackgroundColor` as the normal content canvas and resting toolbar, while retaining full opacity, clipping and content-only fading for the entire entry/exit transition. Sidebar/player container roles and all accepted geometry remain unchanged. This is one consistent canvas role, not a hard-coded light color; dark mode follows its existing theme. The corrected candidate requires Human visual review.

## Current Settings rows and choice sheets, 2026-10-07

**Design source:** Human's explicit Settings unification requirement on this
date. The dated composition above records earlier evidence; the current real
categories are Appearance, Music service, Language and Playback. No screenshot
of an earlier unsatisfactory implementation is a new design target.
**Status:** implemented candidate, `HUMAN_REVIEW`; not visually accepted.

The current approved page grammar is a plain page canvas, small section heading,
and quiet whole-row settings: optional leading icon, title, current-value
subtitle and decorative chevron. Both nested filled Appearance containers and
the permanent inline color-source radio/expansion panel are removed. Compact
category navigation/search/Back and the shared desktop Shell are retained,
not redesigned.

All six current simple enums use the same private `_SettingsChoiceTile<T>`:
Theme, Color source, Music service, Language, Default quality and Lyric
auxiliary mode. Desktop and compact both open `showModalBottomSheet<T>`;
there is no desktop dropdown, popup or central-dialog alternative. The
standard route owns scrim, drag handle, motion and dismissal. Its content
uses `RadioGroup`/`RadioListTile`, safe-area padding and a scroll view, with
a 640 dp maximum width and viewport-relative height limit. Option text wraps
without a smaller font or ellipsis. Geometry changes do not change the
interaction model.

Selection returns the enum and closes the route; the existing Settings save
owner then applies it, updates the row and persists it. The focused row is
restored on return. Current-value selection and Escape/Back/scrim dismissal
write nothing. A caller disposed while the route is open cannot apply a late
selection. Saving disables the current settings rows. Existing persistence
failure feedback/rollback is retained; no success Snackbar or Apply button is
added. There are no Boolean settings in the current page; this component does
not redefine future Switches or action/navigation controls as enums.

The secondary Palette preview row contains five 20 dp swatches from the
**actual effective page ColorScheme**. Color-source supporting text stays in
the sheet, including actual system-color availability and existing Provider
brand fallback. Availability no longer incorrectly claims that a currently
brand-selected page preview comes from the system palette. Preference enums,
schema, migration, dynamic-color loader, brand palette owner and persistence
semantics are unchanged.

### Machine and rendered evidence

Starting HEAD/tracked origin/main:
`65a2be28dd4748238adf407a36e4af78ab66e4ec`; initial worktree clean.
Render snapshot: that HEAD plus the Settings/l10n production diff with SHA256
`8c9f3f29c53879581c5950540d7b242f1733c9e24883ddd0240b7933d0904e94`.
The digest is from `git diff -- apps/flutter/lib/settings/settings_page.dart
apps/flutter/lib/l10n | sha256sum`, not an invented new commit.

The reused Settings render test exercises all six enums at 320/390/640/1440 dp,
English/Chinese, light/dark and 1x/2x text. It checks the actual rows, every
option's scroll reachability and hit target, selection/dismissal and no
overflow; it does not stop at checking widget existence. Interaction tests
also cover keyboard Enter/arrow selection, focus return, current-value
semantics, actual owner persistence success/failure, all-row saving state,
real top/bottom system insets and disposed callers. Existing MusicApp tests
continue to exercise category/search/Back, provider/locale transitions and
retained playback/Queue owners.

Additional MusicApp tests at 390/1440 dp begin with a playing synthetic source:
the sheet blocks underlying player hit testing while playback stays playing,
media resolution count remains one, stop count stays zero and Queue tracks
remain unchanged. After selection/dismissal the player controls become
reachable again. Actual renders are `settings-active-player-390.png` and
`settings-active-player-1440.png`. This proves UI/controller ownership with
test doubles, not native audio continuity on a physical device.

Temporary CURRENT images/logs are in
`/tmp/fura-settings-choice-20261007-wds6JI/`; no fonts or bulk screenshots are
repository assets. The eight required states are:

| State | Actual render filename |
| --- | --- |
| Desktop normal | `1440_zh_light_1x-settings.png` |
| Compact normal | `390_zh_light_1x-settings.png` |
| Desktop Theme open | `1440_zh_light_1x-theme.png` |
| Compact Theme open | `390_zh_light_1x-theme.png` |
| Desktop Color source open | `1440_zh_light_1x-color.png` |
| Compact Color source open | `390_zh_light_1x-color.png` |
| Dark Settings | `1440_zh_dark_1x-settings.png` |
| Enlarged/long supporting copy | `390_zh_dark_2x-color.png` |

These are real Flutter-rendered synthetic Settings fixtures, not physical
Android captures. Additional MusicApp integrated renders are
`settings-shell-desktop-normal.png` and `settings-shell-desktop-theme.png`;
the existing compact capture test writes
`/tmp/fura-settings-mobile-menu.png`,
`/tmp/fura-settings-mobile-appearance.png` and
`/tmp/fura-settings-mobile-system-colors.png`.

The local Flutter 3.47.1 implementation supplies the standard 640 dp M3 sheet
width and 250 ms enter / 200 ms exit animation. Actual time-sequence captures
are `motion-open-{000,125,250}ms.png` and
`motion-close-{000,100,200}ms.png`; route tests verify animation progress and
completion. Final static screenshots alone are not motion evidence. Stock
modal behavior, including its current response to reduced-animation settings,
is preserved; no extra animation owner is added.

### Read-only review and Human boundary

The installed Antigravity CLI 1.2.2, locally configured Gemini 3.8 Flash (Low),
was used interactively from the repository in `agy --mode plan` for component
preflight and then actual component-render review. Preflight read Settings and
theme source; it identified focus/keyboard/scroll/saving/unmounted-caller risks
within the Human-selected interaction. Render review actually read all eight
CURRENT images above. It identified no concrete new machine defect; desktop
space/width proportions and compact 2x text density remain Human judgments.

A separate fresh integrated-page session used
`agy --mode plan --log-file /tmp/fura-settings-choice-20261007-wds6JI/agy-page.log
--add-dir /tmp/fura-settings-choice-20261007-wds6JI`. It read the original Human
requirement, Settings source, both MusicApp desktop images, all three compact
MusicApp images, dark desktop and enlarged compact risk renders. It found no
new concretely supported defect and left palette/icon alignment, density and
sheet/canvas whitespace to Human. No edit permission, model switch or global
configuration change was granted.

That page session also actually read both added active-player renders. It
reported correct modal z-order and no player hit-through, leaving the desktop
sheet's visual occlusion of the central player controls as a Human judgment.
The standard modal blocking behavior is deliberately retained; no new local
avoidance scheme or change to the shared player was adopted.

Final executed checks: `flutter test test/settings` (80 pass),
`flutter test test/widget_test.dart` (123 pass), render capture test (33 pass),
both integrated capture tests and active-player capture tests, `dart analyze`
(no issues), affected `dart format --output=none --set-exit-if-changed`, source
privacy audit and `git diff --check`. Test-development failures (asserting
radio state before opening, fixture API/import/semantics-handle mistakes and
a formatting lint) were corrected and rerun, not attributed to product code.
The before-change regression at the old inline expansion is preserved in the
temporary `before.log`; obsolete dropdown/ExpansionTile-style assertions were
replaced by the approved row/sheet contract, not by weakened persistence,
keyboard or large-text assertions.

GPT checked those suggestions against actual source/SDK/tests. The reviewer's
static "no crash"/gesture claims are **not** adopted as runtime proof; only
executed interaction tests establish those machine behaviors. Render review
cannot accept aesthetics, prove physical native behavior or replace Human
acceptance. No new decision permits changing the sheet into a dropdown or
dialog. Final native-device appearance/interaction and remote CI are not
verified by these offline renders; no commit/push was performed.
