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
