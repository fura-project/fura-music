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

## Current official Settings component contract, 2026-10-08

**Design source:** the latest explicit Human correction, not a new taxonomy.
**Status:** candidate; `HUMAN_REVIEW`. No aesthetic iteration is authorized
before Human sees these renders. Starting HEAD/origin/main:
`ba4ce107a538d1399dfb353515a4b9295b2335e0`, initial worktree clean.

The existing Shell, navigation, search, Back, grouped surface, section heading,
desktop content width, ordinary row composition, compact hierarchy and
Shell-owned Player remain unchanged. Business enums, schema, owner,
persistence and rollback do not change.

- Theme, Music service, Language, Default playback quality and Lyric auxiliary
  use official `showModalBottomSheet` / `BottomSheet` with standard drag handle,
  `RadioGroup` and `RadioListTile`. One Flutter path serves every platform.
  Explicit infinite maximum width overrides the SDK M3 640 dp fallback; the
  finite window constraint and stretched content supply full window width,
  including live resizing. Height follows content and can scroll at large
  text. The current M3 BottomSheetTheme supplies surface/elevation and 28 dp
  top-only rounding. SafeArea, standard scrim, Back/Escape/dismiss, no Apply,
  no-write current selection and owned-route cancellation remain.
- Color Source uses actual `DropdownMenu<AppColorSourcePreference>` and
  `DropdownMenuEntry` in the existing row's trailing/control area; compact
  layout stacks the control without introducing a new panel. Selecting the
  field opens the official SDK dropdown, not the whole row or a modal.
  Availability and five actual ColorScheme swatches remain small secondary
  content below it, not complex menu content or a second Card.
- `FuraChoiceSheet`, `FuraChoiceRow`, project MenuAnchor/MenuController popup
  and inline disclosure are removed. DropdownMenu uses MenuAnchor internally
  in Flutter; tests distinguish SDK ownership from project custom presentation.
  No DropdownButton/FormField or Android MethodChannel is introduced.

### Failure-path checks and current evidence

The earlier real Overlay-removal focus fix remains: modal results wait for
`ModalRoute.completed` before the existing triggering row restores focus.
New deterministic failures were retained, not overwritten by later passes:

1. A disabled TextField revokes its supplied FocusNode; DropdownMenu reads that
   node when enabled again. The Settings control explicitly restores its
   canRequestFocus on the save owner's enabled update.
2. SDK arrow traversal previews a label before a value is committed; dismissing
   with Escape left that unsaved label in the field. A supplied text controller
   restores the existing setting on Escape, outside tap and focus departure,
   while SDK DropdownMenu still owns opening, selection and dismissal.

Stale/external replacement and disposed callbacks cannot apply a value.
No change to Settings save semantics or shared visual theme is made.

Current synthetic renders/logs are outside Git:
`/tmp/fura-settings-official-m3-20261008-Ax9gpe`.
Production SettingsPage, current M3 theme, actual Noto CJK/MaterialIcons and
real shadow rendering are used. These renders do not prove native-platform
runtime or Human visual acceptance.

| Requested state | Evidence filename |
| --- | --- |
| Desktop Appearance idle | `1440_zh_light_1x-settings.png` |
| Compact Appearance idle | `390_zh_light_1x-settings.png` |
| Desktop Theme sheet | `1440_zh_light_1x-theme.png` |
| Compact Theme sheet | `390_zh_light_1x-theme.png` |
| Desktop Color dropdown | `1440_zh_light_1x-color.png` |
| Compact Color dropdown | `390_zh_light_1x-color.png` |
| Dark Theme sheet | `1440_zh_dark_1x-theme.png` |
| Dark Color dropdown | `390_zh_dark_1x-color.png` |

The matrix also covers English/Chinese, 320/390/640/1440/1600 widths,
light/dark and 1x/2x text. Final validation/review results are recorded below
after execution. The latest Human instruction overrides design consultation:
agy may inspect actual renders only for machine-oriented overflow, focus,
semantics, accessibility, touch or contrast; it cannot change the locked
BottomSheet/DropdownMenu model, shape, width or row structure.

### Executed validation and bounded machine review

- `flutter test test/settings`: 117 pass. Includes full window width/live
  resize, all five widget platform variants (not native-platform runtime),
  current/selected/no-write, Back/Escape/scrim/drag, keyboard/focus, disabled
  save/rollback, stale/disposed callbacks, preview cancellation, safe area,
  reduced motion, true capability/palette and 40 layout combinations.
- `flutter test test/widget_test.dart`: 123 pass. Obsolete popup-only
  availability assumptions were updated to always-visible secondary support;
  menu targets now distinguish real hit-testable SDK entries from the hidden
  intrinsic-width sizing copies. No business assertion is removed.
- Actual production MusicApp synthetic-player captures at 390/1440 pass:
  same Queue/session, one resolution/no stop, underlying controls blocked only
  while modal is open and reachable again after selection.
- Real Linux Debug build/GTK `settings_choice_runtime_test.dart` passes:
  real plugin-backed disposable preference key, exactly three writes,
  selection/readback/current/cancel/Escape/scrim/focus/2x; its unique key is
  deleted in teardown. No stored accounts, Providers or real media are used.
- `dart analyze`, affected-file format and `git diff --check` pass.
  No new remote CI or other native-platform runtime is claimed.

Before-fix logs (`interaction-rerun.log`, `keyboard-preview-before.log`)
remain beside `settings-final.log`, `widget-rerun-final.log`,
`render-final.log`, `linux-runtime-final.log` and integrated captures.
The manifest records the exact current source hashes/scoped diff and review
boundary. Raw review transcripts and images stay outside Git.

Real interactive `agy` 1.2.2 invoked in plan/read-only mode with the existing
configured Gemini 3.8 Flash (Low), using bounded packets/read-only source
snapshots. Component review received the ten listed renders and inspected
actual desktop/compact/light/dark/2x images (not a blanket ten-state
acceptance claim); a separate fresh integrated review explicitly listed
`settings-active-player-1440.png`,
`settings-active-player-390.png`, `390_zh_light_2x-color.png` and
`390_zh_light_2x-theme.png`. The explicit Human instruction forbids design
consultation here. No component/interaction/shape/width redesign is adopted.

The component review suggested checking dark auxiliary-text contrast.
Actual active onSurfaceVariant/group, onSecondaryContainer/control and
onSurface/sheet pairs pass >=4.5:1 in light/dark deterministic tests.
Background under the modal scrim is intentionally inactive; palette swatches
are decorative real colors rather than text or selectable controls. The
integrated review observed the dropdown extending beyond the group but inside
the viewport: normal SDK overlay behavior, not a clipping defect. Screenshot
claims about runtime focus/touch/semantics and the component review's COMPLETE
footer are not acceptance. Applicable widget and GTK checks supply separate
machine evidence; Human still owns visual acceptance. No further polish is
performed before that review.

## Superseded custom Settings component contract, 2026-10-08

**Design source:** Human's directed component correction. This supersedes the
2026-10-07 inline Color Source and default RadioListTile sheet candidate below.
**Status:** implemented candidate; `HUMAN_REVIEW`, not visually accepted.
Human explicitly sets the order: implement the fixed contract, render, inspect
with GPT, then bounded read-only agy audit. Neither reviewer chooses a new model.

| Setting | Current presentation |
| --- | --- |
| Theme, Music service, Language, Default playback quality, Lyric auxiliary | SIMPLE: FuraChoiceSheet / FuraChoiceRow / RadioGroup / Radio |
| Color Source | DETAILED: Material 3 MenuAnchor / MenuController / custom radio rows |
| Boolean, when supported | M3 Switch in the same row grammar |
| Complex workflow, when supported | Settings detail page |

### Retained surfaces and explicit row ownership

Settings Shell/navigation/search/Back/compact hierarchy and Shell-owned player
remain unchanged. Keep one quiet `surfaceContainerLow` Material per group,
16 dp rounding, external heading and the existing 880 dp padded content limit.
`_FuraSettingsRow` now owns Material/InkWell/Focus/Semantics and Row/Column:
minimum 64 dp, 16 dp horizontal / 12 dp vertical padding, quiet 24 dp icons.
Actual localized text/style/scaler measurement preserves desktop trailing
values and compact/long-text stacked values; no ellipsis or font reduction.
Simple entries have chevrons, Color Source has an expansion/menu affordance.
Ordinary rows have no persistent selected background; hover/focus/pressed state
layers return to exact idle pixels after leaving those states.

### Simple bottom choice dialog

`showSettingsSingleChoice` always enters the same Flutter-rendered component
on Android/Linux/Windows/macOS/iOS. `showModalBottomSheet` owns route, scrim,
bottom placement, Back and dismiss motion, not the content grammar. Its builder
uses project-owned `FuraChoiceSheet`: `surfaceContainerLow` Material, 28 dp top
corners, 24 dp handle area with a 32 x 4 dp handle, titleLarge with 24 dp side
padding, minimum 56 dp `FuraChoiceRow`, standard M3 Radio and 16 dp bottom
spacing plus SafeArea. Content determines height; Theme is approximately
256 dp at 1x. Desktop maximum width is 480 dp; compact uses available width.
No RadioListTile/ListTile stack, native dialog, Apply button, dropdown or
independent overlay framework. Standard route drag dismissal remains enabled.

Selection closes, then the existing Settings owner saves. Current value and
Back/Escape/scrim/drag cancellation do not write. Radio null toggles explicitly
map back to the current value so current-option keyboard activation closes
without deselecting or writing. Duplicate/stale/invalid/disposed results and
pending-write disable/rollback behavior remain tested.

### Detailed anchored Color Source

`_SettingsColorMenu` owns only MenuController/focus/lifecycle, never Settings
truth. MenuAnchor and M3 MenuStyle own the anchored surface; project radio rows
show actual selection, supporting explanations and truthful dynamic-color
availability. A Wrap shows five 20 dp real effective-ColorScheme dots. These
non-interactive previews exist only inside the popup, never as a first-level
row. Appearance stays two rows and opening does not increase group height.

The popup is 400 dp maximum, limited to viewport width minus 32 dp, with
16 dp rounded M3 surface and SDK viewport placement. Bounded internal scrolling
retains explanations/options at 2x and short 320 x 480 viewports; no modal
route/scrim, inline disclosure, MD2 dropdown or second card. Selecting closes
then uses the unchanged save/rollback owner; current/outside/Escape/Back close
without writes. Stale snapshots, disposal, rapid toggles, focus return and
keyboard radio traversal are covered. Unsupported capabilities remain truthful.

### Failure investigation and evidence boundary

Starting HEAD, tracked origin/main and live remote main were
`c2cb5295dab93610eb68e276b7194e6cb4a24fdf`; initial worktree clean. Existing Core
playback/MPRIS work is preserved. Production evidence fingerprint:

```bash
git diff -- apps/flutter/lib/settings | sha256sum
# dc6b9218872ce4f29bd440b8b7fb127825806d26e2a9db18d514988785fba63a
```

Evidence lives outside Git at `/tmp/fura-settings-contract-20261008-LLaPt7/`.
Two reproduced presentation defects were fixed, not dismissed after a rerun:

- Menu scrolling inherited the page PrimaryScrollController and produced a
  multiple-ScrollPosition assertion; its own `primary: false` scroll owner
  fixes the failure, including compact/short/large-text tests.
- Real Linux Escape initially returned focus before the outgoing route's
  Overlay teardown, which then replaced that focus. The result now waits on
  actual `ModalRoute.completed`, not an invented delay. A deterministic route
  test and real GTK rerun prove cleanup precedes save/focus return. Save tests
  explicitly render the following scheduled frame, retaining disabled assertions.

Capture-only investigation also found Flutter test bindings replace shadows
with outlines. Evidence capture temporarily enables real shadow painting and
restores the binding invariant in finally; production elevation is unchanged.
The failed global-shadow test attempt remains in the log, not accepted output.

Real Linux integration uses production Settings and preference plugin with a
unique disposable fixture key: three writes/readback, current/cancel no-write,
focus, anchored color and 2x succeed. It never restores credentials or starts
MusicApp/accounts/playback; only its own preference key is removed. Separate
synthetic MusicApp active-player tests prove one resolution, no stop, retained
Queue/Track and modal interaction isolation. Static renders alone do not.

### Actual renders and bounded review

All ten below are real Flutter renders with synthetic data under the production
fingerprint above, not physical-phone/native-five-platform captures. GPT
inspected them individually. English/Chinese, light/dark, 1x/2x and all six
controls are also exercised across 320/390/640/1440/1600 dp.

| State | Desktop | Compact |
| --- | --- | --- |
| Appearance idle | `1440_zh_light_1x-settings.png` | `390_zh_light_1x-settings.png` |
| Theme FuraChoiceSheet | `1440_zh_light_1x-theme.png` | `390_zh_light_1x-theme.png` |
| Color Source MenuAnchor | `1440_zh_light_1x-color.png` | `390_zh_light_1x-color.png` |
| Dark | `1440_zh_dark_1x-theme.png`, `1440_zh_dark_1x-color.png` | — |
| 2x text | — | `390_zh_light_2x-theme.png`, `390_zh_light_2x-color.png` |

`settings-active-player-{1440,390}.png` show the retained integrated Shell;
sheet route opening/closing frame sequences are separate from settled images.
The anchored menu uses SDK ownership, not the superseded inline height tween.

Actual interactive agy 1.2.2 ran in the existing trusted project with the
authorized Gemini 3.8 Flash (Low), `--mode plan --log-file <temporary log>
--add-dir <evidence directory> --prompt-interactive <bounded packet>`.
Read-only copies of component/theme code were supplied. No model/global setting
change, production patch or expanded permission was approved. Component
session `614e8c51-f52a-4142-9fb5-6c0d93b6c986` confirmed reading the ten PNGs
and snapshots. Fresh integrated-page session
`e80aa221-fb87-4c9c-b84c-13a13bfa843a` read the separate Shell/player and
responsive companions and reported no new concrete M finding.

GPT does not blindly adopt the component review: its current-radio dismissal
objection contradicts Human's explicit no-write/close contract. Its claimed
circle-only keyboard focus is disproved by a pixel regression of blank
trailing row area (the Radio's real owned focus propagates to ancestor InkWell),
with exact idle restoration. Compact asymmetric anchoring is contained in the
viewport, so symmetry is H, not overflow; non-interactive palette contrast is
not a control contrast failure. Its no-drag inference is disproved by a real
gesture test. Any blanket COMPLETE/remainder statement is not Human acceptance.
Durable findings and test references are recorded here; full operational logs
and concise observed-response records remain in the temporary directory.

Human still judges the new sheet feel, row density, popup rhythm and palette
subtlety. Native non-Linux runtime, physical touch/screen-reader experience
and new remote CI are not inferred from widget platform variants or screenshots.

Final executed checks: `settings-acceptance-final.log` reports 115 Settings
tests passed; `app-final.log` reports 123 whole-MusicApp regressions passed;
`integrated-player-renders.log` reports two retained-player renders/tests passed.
`linux-runtime-route-settled.log` builds/runs real Linux Debug and reports one
integration passed with exactly three fixture writes. Full `dart analyze` has
no issues; affected format reports 11 files / zero changes. Source audit finds
no production legacy dialog/inline/dropdown path, new network/credential fields
or platform-specific presentation dispatch; `git diff --check` passes.
Ordinary `flutter build apk --debug --target-platform android-x64` succeeds in
`android-debug-build.log`. This is compilation only: no physical/Waydroid APK
installation or non-Linux native interaction claim is made for this candidate.
The existing Gradle native-access warning is not a build failure or a reason
to change Java/toolchain in this UI task. No dependency/registrant changes,
Core edits, commit, push or reset/restore/clean/rebase were performed.

## Superseded Settings interaction candidate, 2026-10-07

**Design source:** Human's latest Settings interaction correction supersedes
the native-Android presentation decision below. Preserve the accepted grouped
surface and Shell; all platforms use the same Flutter Material 3 interaction.
**Status:** implemented candidate, `HUMAN_REVIEW`, not visually accepted.

| Setting / complexity | Presentation |
| --- | --- |
| Theme, Language, Default quality, Lyric auxiliary, Music service selection | SIMPLE: unified Flutter M3 bottom choice sheet |
| Color Source (explanations, availability, Provider brand, preview) | DETAILED: inline disclosure in the same grouped surface |
| Boolean settings, when supported | M3 Switch |
| Complex workflows, when supported | Settings subpage |

This is interaction taxonomy, not an all-enums rule or a schema framework.
No business enum, Settings schema, capability or save owner changes.

### Retained grouped surface and detailed Color Source

Keep one quiet `surfaceContainerLow` Material per group, existing 16 dp radius,
880 dp padded content constraint (832 dp desktop group), external heading,
quiet icons, measured trailing desktop values and stacked compact/large text.
Ordinary setting rows are not selected destinations. Standard hover/focus/
pressed layers remain valid; canonical idle captures clear pointer/focus, not
the keyboard accessibility policy. A pixel regression checks hover and focus
actually alter the row and that both return to identical idle pixels.

Color Source owns only disclosure state. `RadioGroup` / `RadioListTile` show
the real current enum, existing explanations, actual dynamic-color availability
and Provider brand fallback. Five real effective-ColorScheme palette dots live
only inside expanded details, without a separate collapsed preview row or a
second Card. Selection uses the existing save/rollback owner, stays expanded
on success or failure, and restores selected-option focus after saving.

`AnimatedRotation` and `AnimatedSize` use restrained 200 ms height/chevron
motion; rapid toggles remain safe. Reduced motion renders details directly and
rotates immediately. Actual testing rejected `AnimatedSize(Duration.zero)`:
this local SDK synchronously notified during layout and asserted. The direct
reduced-motion branch fixes that reproduced negative evidence, not an ignored
test or a second animation owner.

### One simple bottom dialog on every platform

`settings_choice_presentation.dart` now always uses `showModalBottomSheet<int>`
with current M3 ColorScheme `surfaceContainerLow`, 28 dp top rounding, zero
elevation, standard handle/scrim, title, `RadioGroup` / `RadioListTile`, SafeArea,
scroll continuation and standard modal-route motion. Maximum width is 520 dp;
height follows content rather than reserving 90% of the viewport. Android,
Linux, Windows, macOS and iOS use this same code, row grammar and motion owner;
responsive width/insets are not platform-specific dialogs. No Apply button.

Selection closes and saves immediately. Current value and cancel do not write.
Back/Escape/scrim, keyboard selection, focus return, disabled/save-pending state,
stale external value, duplicate open, invalid result and disposed route retain
their tests. Cancellation removes only the caller's owned modal route. There
is no DropdownButton/FormField, centered AlertDialog or native fallback.

Only Settings-exclusive Android presentation is removed: SettingsChoiceChannel,
SettingsChoiceResult, local native styles/JVM result test, MethodChannel wiring
and its sole-owner direct Material/JUnit dependencies. Activity diagnostics,
lifecycle and AudioService registration are preserved. The final MainActivity
content hash equals the pre-native candidate's host; no playback changes.

### Current evidence boundary

Starting HEAD and tracked origin/main were
`73da77571e4cb289b178803824d8a7a1cb4867bd`, initial worktree clean.
Current production render snapshot is that HEAD plus scoped Git diff SHA256
`86978108582581ad0ad102a797a1dfb5f4404ad23a1cd8cdb5b432697fda3fff`, computed by:

```bash
git diff -- apps/flutter/lib/settings apps/flutter/lib/l10n \
  apps/flutter/android/app/build.gradle.kts apps/flutter/android/app/src/main | sha256sum
```

Actual baseline/failure logs, renders and read-only review material remain
outside Git at `/tmp/fura-settings-taxonomy-20261007-EVucxo/`. Before-fix tests
prove the Android/native path, 640 dp simple sheet and modal Color Source did
not meet this corrected requirement. These rejected implementation captures
are CURRENT evidence, never promoted to Human TARGET.

Settings and whole-MusicApp regressions, five-platform presentation variants,
pending-save rollback/focus and idle-state pixel checks pass. Real Linux GTK
runtime exercises the production Settings page and real preference plugin with
a unique disposable key: three writes/readback, current/cancel no-write,
inline Color Source and 2x text pass. The fixture does not restore credentials,
access accounts or start playback; it removes its own preference key.

### Canonical renders and verification

All files below are actual current Flutter renders under the snapshot above,
with synthetic data, not native Windows/macOS/iOS or physical-phone captures.
The ten requested visual states were individually inspected by GPT:

| State | Desktop | Compact |
| --- | --- | --- |
| Appearance collapsed | `1440_zh_light_1x-settings.png` | `390_zh_light_1x-settings.png` |
| Inline Color Source expanded | `1440_zh_light_1x-color.png` | `390_zh_light_1x-color.png` |
| Dark expanded | `1440_zh_dark_1x-color.png` | `390_zh_dark_1x-color.png` |
| Theme choice sheet | `1440_zh_light_1x-theme.png` | `390_zh_light_1x-theme.png` |
| 2x text | — | `390_zh_light_2x-color.png`, `390_zh_light_2x-theme.png` |

Integrated MusicApp evidence: `settings-shell-desktop-{normal,color,theme}.png`,
`settings-shell-compact-{normal,color}.png`; synthetic active-player sheets:
`settings-active-player-{390,1440}.png`. Existing tests prove modal hit isolation
while the retained Queue/player keeps playing with one resolution and no stop.
The compact modal legitimately covers the mini-player; it does not stop it.
Motion is captured at actual opening/closing frame times:
`color-motion-{open,close}-{000,100,200}ms.png` and stock sheet
`motion-open-{000,125,250}ms.png`, `motion-close-{000,100,200}ms.png`.
Static final screenshots alone are not animation proof.

Actual checks: Settings + whole MusicApp regression pass; the final additional
inline-keyboard/current-no-op regression also passes. The layout test covers
320/390/640/1440/1600 dp, English/Chinese, light/dark, 1x/2x and every current
control, not only Theme. `dart analyze`, affected format (no changes), source
privacy and `git diff --check` pass. Ordinary Android x64 Debug APK builds after
native-edge/dependency removal. Real Linux GTK runtime passes as above.

Actual interactive local `agy` 1.2.2 uses the existing authorized
Gemini 3.8 Flash (Low), `--mode plan`, no model/global permission changes.
One preflight and a rendered component review ran; the component session
`9ce1959c-e852-44b7-a98c-34374e0ce9dc` explicitly read all ten state images,
motion frames, rejected before-images, relevant component/theme/tests and
bounded build/runtime logs. Its scratch report is copied to
`agy-component-report.md` in the temporary evidence directory. No new
reproducible component defect was identified. GPT does not adopt its unsupported
dark-scrim comfort inference (no dark sheet supplied to that review), claimed
both X11/Wayland runtime proof, or native Back proof from an Escape-labelled
runtime phase. Existing deterministic Back and real Escape tests have their
own narrower proof; preference/density and motion feel remain Human-owned.

A separate fresh integrated-page session
`08d8e018-13ff-44c8-9a02-2cc8cf5db24a` read the Human constraint packet, five
integrated Shell states, both active-player sheets, 2x/dark companions and
motion opening frames/closing midpoint. Invocation was `agy --mode plan
--log-file /tmp/fura-settings-taxonomy-20261007-EVucxo/agy-page.log --add-dir
/tmp/fura-settings-taxonomy-20261007-EVucxo --prompt-interactive <bounded page
packet>`. Its actual outside-repository scratch result is copied to
`agy-page-report.md`. It identified no new reproducible page defect; desktop
palette whitespace and compact dark surface contrast remain H observations.
GPT corrected its erroneous scrim inference from a non-modal dark expanded
image before final reporting. The supplied image cannot prove hit blocking,
immediate writes or widget-tree absence: existing interaction/runtime tests
prove those claims. Likewise dynamic availability is not determined by whether
the System option is selected. The review's blanket acceptance/remainder
statements are not adopted as Human acceptance or as five native-runtime proof.

Human retains visual acceptance of density, spacing, grouped composition,
inline rhythm, desktop width and phone touch/insets. Widget platform variants
are not five native-runtime proofs; Android build is not physical-phone
acceptance. Remote CI and native Windows/macOS/iOS runtime are unverified.
Android Debug compilation is verified. Initial ADB inventory had no device
and Waydroid session was stopped; privileged shell checks required a sudo
password. An independent safe check found the existing container service was
already active, so normal unprivileged session startup was possible without
sudo, new runtime installation or data reset. Existing ADB authorization then
succeeded (`device`), but property reads hung and independent 10-second
`shell true` / echo probes timed out. A single transport reconnect failed and
the following probe reported device offline. This happened before any test
APK installation or application launch; it is an environment/transport blocker,
not Fura runtime failure. Android interaction remains unverified, with evidence
in `android-runtime-boundary.txt`. The session started by this task was stopped
and initial STOPPED state verified; no app data or shared root service was
cleared/disabled. Physical-phone proof is not inferred from compilation.

## Historical grouped Settings and native Android choices, 2026-10-07 (superseded)

**Historical interpretation, superseded by the correction above:** candidate
`a68c320f358fe6fcf36bd8c031d28b923f22ae35` was rejected for its flat transparent
groups. The previous Agent interpreted the dialog correction as Android-native;
that interpretation was incorrect. Human's final direction is one unified
Flutter M3 bottom dialog on all platforms. The dated native candidate and its
evidence below remain historical, not current presentation requirements; the
retained Shell/navigation/search/player ownership is unchanged.
**Status:** implemented candidate, `HUMAN_REVIEW`; no Human visual acceptance.

### Current page grammar

Each real section owns one quiet `surfaceContainerLow` Material surface with
the existing 16 dp `MusicRadii.content`, no elevation, and its heading outside.
Rows share that surface and standard state layers; 4 dp inter-row spacing
replaces hard divider rules. There are no per-row cards, brand-green selected
panels, permanent radios, accordions, dropdowns or color expansion owner.

The content constraint is 880 dp including 24 dp padding on each side, giving
an actual 832 dp desktop surface. At 1440 and 1600 dp the title is primary and
the current value is right-aligned in `onSurfaceVariant`, before the chevron.
The layout measures both effective text styles with locale, direction and
text scaler, reserving icon, gaps, padding and chevron space. Compact, long
and enlarged text stack/wrap rather than shrinking or ellipsizing. Quiet
icons use `onSurfaceVariant`. Palette preview remains five real 20 dp
effective-ColorScheme dots: trailing desktop, under the title when compact.

All six enums share the same presentation/index boundary: Theme, Color source,
Music service, Language, Default quality and Lyric auxiliary mode. Existing
enum/schema, dynamic-color availability, Provider brand fallback and save
owner remain unchanged. The row maps the safe returned index to its captured
enum list; cancel, current value, invalid index, disposed caller or an external
current-value replacement cannot write. Rows remain disabled during saving,
with existing failure feedback/rollback. Focus returns after that existing
save completes and the enabled row rebuilds; Android pause cancellation
defers focus return until the Activity resumes.

### ANDROID_NATIVE

`settings_choice_presentation.dart` uses the Activity-owned MethodChannel
`com.fura/settings_choice`, implemented by `SettingsChoiceChannel.kt` and
owned by `MainActivity`. The payload contains only request correlation, title,
option labels/supporting text/enabled flags, selected index, optional footer,
brightness and primary presentation color. No Settings model, enum name,
Provider object, credential, persistence or business rule enters Android.

The actual component is Android Material Components `BottomSheetDialog`,
with native `MaterialRadioButton` and `MaterialTextView` rows inside a native
scroll view. Material owns scrim, shape, motion, system Back, touch feedback
and insets. One whole-row native radio accessibility target avoids duplicate
label/button nodes. Result ownership is correlated and exactly-once; an older
dismiss callback cannot complete a newer request. Pause/configuration change,
caller disposal and host detach cancel; inactive/destroyed Activity and a
second pending dialog fail truthfully. Unavailable Android presentation shows
localized failure feedback, never a silent Flutter replacement.

Material 1.7.0 was already resolved transitively before this task; the app now
explicitly declares that same version for its direct native API use. Only
JUnit 4.13.2 is added to the test configuration. There is no dependency graph,
toolchain, splash/Activity-theme or playback plugin-policy upgrade.

Dialog-only Material 3 light/dark themes receive the minimum brightness and
selection-accent tokens, not a copied Flutter ColorScheme. Actual rendering
exposed a white-on-dark defect even though interaction tests passed. Material
1.7.0's zero-theme constructor re-resolves `bottomSheetDialogTheme`; using
`BottomSheetDialog(context, theme)` retains the explicit local dark style.
Corrected native screenshots show a dark tonal surface/light labels on a dark
Fura page. The original wrong-color images are retained as negative evidence.

### FLUTTER_FALLBACK

Every non-Android target uses one standard Flutter
`showModalBottomSheet<int>` with RadioGroup/RadioListTile, safe-area padding,
scrolling, selected focus, Escape and the existing 640 dp width / 90% viewport
height limits. It is bottom-aligned on desktop as well as compact; it is not
an Android native implementation. Owned-route cancellation removes only that
caller's route, including disposal before its first builder runs. No new
animation, message queue, navigation framework or Settings owner is introduced.

### Current actual evidence

Starting HEAD and tracked origin/main were
`a68c320f358fe6fcf36bd8c031d28b923f22ae35`, initial worktree clean. Current
production snapshot is that HEAD plus scoped file-content SHA256
`dc7f9577170097bdbf299e5be15259df72fcf766374168d6758a1446d19506af`.
This includes new untracked native/presentation files, not only tracked diff:

```bash
sha256sum \
  apps/flutter/lib/settings/settings_page.dart \
  apps/flutter/lib/settings/settings_choice_presentation.dart \
  apps/flutter/lib/l10n/app_en.arb apps/flutter/lib/l10n/app_zh.arb \
  apps/flutter/android/app/build.gradle.kts \
  apps/flutter/android/app/src/main/kotlin/com/fura/flutterustmusic/MainActivity.kt \
  apps/flutter/android/app/src/main/kotlin/com/fura/flutterustmusic/SettingsChoiceChannel.kt \
  apps/flutter/android/app/src/main/kotlin/com/fura/flutterustmusic/SettingsChoiceResult.kt \
  apps/flutter/android/app/src/main/res/values/settings_choice_styles.xml | sha256sum
```

Temporary evidence is `/tmp/fura-settings-native-20261007-hqozHY/`, outside Git:

These paths identify the actual inspected implementation checkpoint. The
temporary directory was no longer present at the subsequent Human-authorized
Git publication check. Screenshots/logs were not committed, and their current
readability is not claimed; a new visual comparison requires fresh captures.

| Required state | Actual current image |
| --- | --- |
| 1440 desktop Appearance | `1440_zh_light_1x-settings.png` |
| 1600 desktop Appearance | `1600_zh_light_1x-settings.png` |
| 390 compact Appearance | `390_zh_light_1x-settings.png` |
| 390 compact 2x | `390_zh_light_2x-settings.png` |
| Dark desktop | `1440_zh_dark_1x-settings.png` |
| Dark compact | `390_zh_dark_1x-settings.png` |
| Real native Android Theme | `android-native-theme.png` |
| Real native Android Color source | `android-native-color.png` |
| Real native Android dark | `android-native-dark.png` |
| Non-Android desktop Theme fallback | `1440_zh_light_1x-theme.png` |

`settings-shell-desktop-{normal,theme}.png` and
`settings-shell-compact-{appearance,color}.png` use the retained actual MusicApp
Shell with synthetic dependencies. Component matrix: 320/390/640/1440/1600 dp,
English/Chinese, light/dark, 1x/2x; every option remains scroll-reachable.
Review fonts load only under explicit capture flags, isolated from normal
regressions. Fallback motion has actual opening 0/125/250 ms and closing
0/100/200 ms captures, not just a final PNG.

Executed Settings + full MusicApp regression: 226 passes. Native result JVM
seam: three passes, zero failures; Android Debug compilation succeeds. Native
channel tests prove safe data, result mapping, stale/disposed suppression,
duplicate/open guard, truthful unavailable handling and no Flutter sheet.
Targeted failure tests reproduce and then verify post-save and pause/resume
focus return; fallback owned-route early-disposal regression also passes.

`settings_choice_runtime_test.dart` runs production Settings with a unique
disposable SharedPreferences key and synthetic state, without authenticating
or starting playback. Waydroid 1.6.3 / Android 13 API 33 / native x86_64 Debug
passes Theme and Color selection/readback/reopen, current/cancel/Back/scrim
no-write behavior, underlying hit isolation, real Activity pause/resume and
post-dismiss focus, plus enlarged Flutter rows: `all_success writes=3
presentation=ANDROID_NATIVE`. The local Linux GTK run passes the same owner
selection/readback/cancel/large-text paths, Escape and focus:
`all_success writes=3 presentation=FLUTTER_FALLBACK`. Native captures are real
portrait freeform Waydroid windows inside host screenshots, not widget renders
or cropped/fabricated phone frames. Temporary display overrides were restored;
Waydroid data and accounts were not reset. A pre-existing Waydroid Flutter
glyph-rendering limitation remains visible beneath the crisp native dialog;
it is not declared fixed or visually accepted by this Settings task.

### Read-only review and acceptance boundary

Installed Antigravity CLI 1.2.2 / authorized Gemini 3.8 Flash (Low) was used
interactively in `agy --mode plan`, without production edit permissions or a
model/configuration change. Preflight read the Human requirement, Settings,
theme/host sources and rejected-current references. Component review read
actual desktop/compact/fallback/native images. Its initial generic dark-theme
claim missed the white-on-dark defect; GPT rejected that claim against actual
pixels and the Material source. A concrete follow-up read the corrected three
native captures and acknowledged the corrected dark surface/text state.
The retained response is the CLI's own
`brain/e3ed2a84-86cf-4f49-bf12-a6fa2981399f/scratch/review.md`;
`agy-preflight.log` and `agy-component.log` are temporary operational logs,
not substitutes for the substantive responses.

After the desktop-app interruption, the incomplete final capture/review was
not counted as a pass. The integrated desktop capture was rerun to terminal
PASS, then a separate fresh interactive page session actually read all ten
supplied images: both integrated desktop, both integrated compact, 1600 light,
1440 dark, 390 light 2x and the three native captures. Invocation was
`agy --mode plan --log-file /tmp/fura-settings-native-20261007-hqozHY/agy-page-retry.log
--add-dir /tmp/fura-settings-native-20261007-hqozHY
--add-dir <Human-attachment-directory>
--prompt-interactive <bounded independent page packet>`. Its substantive
response is `brain/e89bbad5-e156-485a-8862-02358bc40df3/scratch/page-review.md`.
It identified no concrete new image-supported defect and left desktop density
and dark palette-dot contrast to Human. GPT does not adopt its inaccurate
icon-container description or estimated 760–800 dp surface width: actual
icons have no container and the surface is 832 dp. Its static IPC/behavior
claims also are not proof; only actual compile/tests/runtime establish those
behaviors. No change is made merely to follow reviewer aesthetic preference.
The Human attachment directory is redacted here to avoid publishing a local
maintainer home path; the actual invocation remains in the temporary log.

Final targeted interaction/native tests pass (28), `dart analyze` has no
issues, affected Dart formatting is unchanged and `git diff --check` passes.
The source-privacy check caught a local-home path in the first draft of this
review record; it was removed and the strict audit rerun, not allowlisted.

Desktop proportion/whitespace, row density/separation, native default tonal
color and physical-phone touch/insets/motion feel remain Human judgments.
Static images do not prove focus, persistence or gesture timing; those claims
use executed tests/runtime only. Waydroid does not establish physical-phone
acceptance. Windows/macOS/iOS fallback runtime and new remote CI have not run.
No commit/push/reset/restore/clean or unrelated production change is performed.

## Historical Settings rows and choice sheets candidate, 2026-10-07 (superseded)

The following is preserved dated evidence for the candidate subsequently
published as `a68c320f` and rejected by Human. Its transparent page grammar and
all-Flutter presentation are **not current normative design**; they were not
native Android even at that checkpoint. The current correction above controls.

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
