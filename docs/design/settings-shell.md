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
