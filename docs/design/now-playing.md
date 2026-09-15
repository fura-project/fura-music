# Expanded Now Playing Design Source

**Status:** Human Approved Reference

**Approval date:** 2026-08-29

## Source identity

The maintainer supplied one desktop playback-detail image in the Codex task and explicitly marked it as a reference rather than a pixel-for-pixel target. The temporary image is not a repository asset.

## Human constraints

- Album artwork and lyrics establish the primary hierarchy; the actual product keeps its supported playback, Queue, Comments, Track-associated MV, synchronized-lyric, and word-timing actions.
- The full Expanded Now Playing surface uses a page-local official Flutter Material 3 color scheme derived from the current artwork, with separate light and dark generation and a normal-theme fallback when artwork is absent or cannot be decoded.
- Artwork-derived color does not become a global theme persona or affect the authenticated Shell and other pages.
- Wide and compact layouts are deliberate translations of the same product state rather than a compressed desktop layout.
- Translation and romanization remain fully wrapping, uncapped text. A presentation fix must not invent fuzzy Provider lyric alignment without sanitized protocol evidence.

Expanded Now Playing remains pending maintainer visual acceptance. This record preserves the source and scope; it does not establish visual completion.

## Persistent playback bar revision

**Design source:** Maintainer-provided Home and Discover screenshots plus explicit interaction requirements, 2026-09-04.

- The first current Track reveals the persistent player with a bounded Material-emphasized size/fade/vertical transition on desktop and compact layouts. Later Track changes update the retained bar in place; reduced motion makes the first reveal immediate.
- Compact Shell pages use one 68 px `surfaceContainerHigh` player with 28 px corners, no outline or physical shadow, 12 px horizontal floating insets, artwork, Track identity, a filled primary action, and Queue. Tonal separation supplies the Material 3 surface hierarchy without recreating a dark outline at 1× density. The player is identical across Home, Discover, Search, Liked, and retained details.
- Compact primary navigation has one 72 px height across destinations. Settings hides that primary navigation while retaining the same player owner.
- On compact layouts, tapping artwork, Track identity, or the remaining card surface opens Expanded Now Playing; primary playback and Queue controls consume their own taps and do not navigate.
- On desktop, artwork and Track identity form one focusable/clickable destination that opens Expanded Now Playing; the artwork and title are no longer competing sibling actions. Transport, progress, quality, volume, and Queue retain their existing actions. The redundant persistent-bar Lyrics action is removed because the same destination already opens the lyric-first Expanded Now Playing page.
- Album/credited-Artist catalog navigation is no longer attached to persistent-bar artwork. Expanded Now Playing presents the validated catalog entry on its Artist line; one valid destination opens directly and multiple destinations use the existing adaptive chooser.
- Catalog selection still verifies the exact current Track/index before dispatch, so a Track change while the chooser is open cannot navigate using stale context.

This revision does not add a second player, change Queue/audio/lyric ownership, or claim that automated screenshots constitute maintainer visual acceptance.

## Responsive lyric-page refinement

**Design source:** Maintainer-provided overflow and Queue screenshots plus the
explicit Expanded Now Playing refinement request, 2026-09-15.

- The wide Track hero no longer owns a vertical scroller. Artwork size is
  calculated from both available width and the height left after metadata and
  actions; the complete hero scales down as one unit in short desktop windows,
  and exceptionally short bounds use the compact horizontal composition.
- At 900 px and wider, Queue and Comments use one full-height trailing Material
  3 side sheet. Between 600 and 899 px the existing centered dialog remains;
  compact layouts retain their bottom sheets. All three forms keep the same
  Queue, comment-loading, cancellation, retry, and playback-shortcut owners.
- The side sheet captures the Expanded Now Playing theme before crossing the
  root Navigator, so its surface, tint, selection, and scrim use the current
  artwork-derived scheme rather than the global brand or system palette.
- The top bar uses a restrained `surfaceContainerLow` gradient blended from
  the page-local primary and tertiary containers. It remains distinct from the
  immersive background without returning to an unrelated flat theme color.
- Read-only comments carry an optional Provider avatar from the bounded Rust
  clients through the Domain and generated Bridge. The UI requests it with the
  existing provider image policy, clips it as a circle, and falls back to the
  author's initial on absence or load failure. Avatar URLs and user content stay
  out of diagnostics.
- The existing first-current-Track reveal remains the only persistent-player
  entrance owner: size, fade, and slight vertical motion on desktop and compact
  layouts, with immediate presentation when reduced motion is enabled.

Automated renders cover normal desktop, short desktop, compact dark, and a
wide Queue side sheet. They are review artifacts; final motion feel and visual
acceptance remain Human-owned.

## Playback-quality selector revision

**Design source:** Maintainer request to expose QQ Music-style Standard, HQ,
and SQ selection on the persistent player, 2026-09-07.

- Compact, desktop, and Expanded Now Playing controls expose one 48 px
  `STD`/`HQ`/`SQ` menu target. It uses the existing Material popup grammar and
  does not introduce another toolbar or change player height.
- The selected preference is persisted through the existing Settings owner.
  Changing it during active playback re-resolves the exact current Track,
  retains its approximate position and paused/playing state, and does not
  modify Queue identity or lyrics ownership.
- The menu and tooltip distinguish the requested preference from the actual
  resolved quality. A snackbar reports exact success or a truthful lower-tier
  fallback without exposing media URLs or account data.
- SQ means the F000 FLAC candidate. It falls back only on typed per-item
  unavailability through HQ, Standard, and Low; network, credential, service,
  malformed-response, and replacement failures stop immediately.

The adaptive renders and automated interaction checks do not establish
authenticated SQ/HQ availability. Exact profile selection remains a
maintainer-operated observation.
