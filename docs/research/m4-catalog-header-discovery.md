# M4 Catalog Header Discovery — 2026-08-27

## Evidence

- Album, Artist, and Ranking each implement the same adaptive header frame: 92/132 px artwork, compact centered column versus wide row, 14/24 px artwork gap, 20/48 px page padding, 1040 px maximum content width, a semantic two-line title, and the same headline weight.
- Their content below the title is legitimately different. Album owns asynchronous metadata, credited-Artist/About actions, description, and detail retry; Artist owns only identity/count plus a separate Tracks/Albums section control; Ranking owns category eyebrow, period, and count.
- Album and Artist currently begin directly with the title, while Ranking establishes an eyebrow → title → metadata hierarchy. A small shared frame can make page type and title structure predictable without flattening the page-specific content.
- No newly reproduced correctness, playback, Provider, debt-trigger, or platform failure outranks this active M4.3 information-hierarchy gap. Selected/current Track styling remains deferred because the queue notifier is frame-driven.

## Ranked candidates

### 1. Shared adaptive catalog header frame — selected

- **Provenance:** M4.3 and M4 exit criteria 1, 3, 5, and 6.
- **User value:** Album, Artist, and Ranking gain one predictable page-type/title/artwork hierarchy across compact and desktop layouts while retaining their useful distinct metadata.
- **Current problem:** three exact responsive frames can drift, and two pages lack the page-type cue already present on Ranking.
- **Scope:** one small Flutter header frame accepting artwork, eyebrow, title, title key, desktop mode, and page-owned detail children; migrate Album, Artist, and Ranking only.
- **Acceptance criteria:** all three pages use the shared frame; 360 px and desktop layouts retain current reachability and no overflow; title semantics and existing title keys remain exact; Album actions/detail state, Artist section control, Ranking period/count, and artwork behavior remain unchanged; focused plus full tests pass.
- **Effort:** Medium.
- **Risk:** a generic header API could grow into a slot-heavy hero system or accidentally impose one page's metadata rhythm on another.
- **Explicit non-goals:** new primary playback actions, universal metadata models, marketing hero treatment, artwork redesign, moving section controls, other page migration, animation, or a design-system package.

### 2. Selected/current Track presentation — deferred

- **Provenance:** M4 exit criteria 5–7.
- **User value:** long lists visibly identify the active Track.
- **Ranking reason:** still lacks a safe non-frame-driven observation seam; visual work must not make whole lists rebuild for every playback position frame.
- **Effort:** Medium–High.
- **Risk:** performance regression or duplicate playback state.
- **Explicit non-goals:** polling or a second playback controller.

### 3. M4.4 Search/Discover hierarchy audit — deferred

- **Provenance:** M4.4 and the now-stable primary shell.
- **User value:** Search result-type controls and Discover sections become more predictable inside the new shell.
- **Ranking reason:** high value but broader; completing the bounded core-browsing header grammar first avoids mixing phases and page families.
- **Effort:** High.
- **Risk:** scope expansion into a heterogeneous Home or Search features.
- **Explicit non-goals:** new Search/Discover capability.

## Selection

The shared adaptive catalog header frame ranks first because three existing implementations prove the common layout, while every page-specific child and controller boundary can remain where it is. The component must define only the shared frame and title hierarchy, not a universal catalog data model.

## Outcome

Implemented on 2026-08-27 as the fifth finite M4 slice. `MusicCatalogHeader` now owns only the proven 92/132 px artwork frame, compact/wide placement, page-type eyebrow, and semantic two-line title. Album, Artist, and Ranking retain their existing title keys and every page-specific child, action, retry rule, section, controller, and artwork implementation. Focused light/compact and dark/wide regressions pass without overflow, as do strict Dart formatting/analysis, all 299 Flutter tests, Rust formatting, 267 offline Rust tests, strict all-target Clippy, Linux x64 Release, and packaged typed-Bridge integration. Four live QQ/WeChat tests remain gated and ignored; no credential, account endpoint, remote media, or user content was accessed.
