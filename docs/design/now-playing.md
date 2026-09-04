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
- On desktop, artwork and Track identity form one focusable/clickable destination that opens Expanded Now Playing; the artwork and title are no longer competing sibling actions. Transport, progress, Lyrics, volume, and Queue retain their existing actions.
- Album/credited-Artist catalog navigation is no longer attached to persistent-bar artwork. Expanded Now Playing presents the validated catalog entry on its Artist line; one valid destination opens directly and multiple destinations use the existing adaptive chooser.
- Catalog selection still verifies the exact current Track/index before dispatch, so a Track change while the chooser is open cannot navigate using stale context.

This revision does not add a second player, change Queue/audio/lyric ownership, or claim that automated screenshots constitute maintainer visual acceptance.
