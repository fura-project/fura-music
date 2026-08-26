# M4 Catalog State Discovery — 2026-08-27

## Evidence

- Album, Artist Tracks/Albums, and Ranking each own the same private centered message tree: primary-colored icon, title, detail, optional retry action, and an optional semantic live region. The implementations are structurally identical while their typed copy and retry decisions correctly remain page-owned.
- Their first-page loading states are unlabeled centered spinners. The visual result is similar, but assistive technology receives no product-specific loading label from those wrappers.
- Search, Library, saved collections, Playlist, and Discover also contain asynchronous states, but account reset, refresh snapshots, result-type selection, lazy sections, and live-announcement behavior differ. Migrating all states at once would erase evidence-backed semantics and exceed a bounded slice.
- M1 has no new automated correctness task beyond the user-operated authenticated playback observation; HD-001 blocks only release identity; no open technical-debt trigger outranks this active M4 exit-criterion gap.

## Ranked candidates

### 1. Shared catalog content-state panels — selected

- **Provenance:** M4 exit criteria 1 and 7, plus the three exact private message implementations and unlabeled catalog loading states.
- **User value:** Album, Artist, and Ranking communicate loading, empty, failure, and retry with one predictable Material hierarchy and explicit assistive loading labels.
- **Current problem:** identical visuals can drift independently, while loading context is implicit.
- **Scope:** one small Flutter loading panel and one small message panel; migrate Album Tracks, Artist Tracks/Albums, and Ranking only; keep all typed failure copy, retry eligibility, controller state, keys, and page transitions at their current owners.
- **Acceptance criteria:** selected catalog states use the shared components; loading has a page-specific semantic label; error-only live regions remain exact; actions and existing keys remain reachable; 360 px, dark, focused page, and full tests pass.
- **Effort:** Medium–Low.
- **Risk:** an overly broad state component could merge error semantics or duplicate live announcements.
- **Explicit non-goals:** shared failure enums/copy, Search/Library/Playlist/Discover migration, append/refresh banners, controller changes, snackbar policy, or a general design-system package.

### 2. Core browsing header alignment — deferred

- **Provenance:** M4.3 and differing Album/Artist/Ranking header/action structure.
- **User value:** page titles, metadata, artwork, and primary actions become more predictable.
- **Ranking reason:** meaningful but broader; it needs a separate content audit now that the Track and state grammars are stable.
- **Effort:** Medium.
- **Risk:** flattening genuinely different Album, Artist, and Ranking information.
- **Explicit non-goals:** one universal hero or marketing header.

### 3. Selected/current Track presentation — deferred

- **Provenance:** M4 exit criteria 5–7 and the absence of a list-level playing state outside the now-playing surface.
- **User value:** users can locate the current Track in long lists.
- **Ranking reason:** the current shared queue notifier also emits position frames; subscribing every row or whole list would create avoidable per-frame rebuilds. A bounded non-frame-driven observation seam needs separate evidence and design.
- **Effort:** Medium–High.
- **Risk:** performance regression, duplicate playback state, or a new controller abstraction created only for polish.
- **Explicit non-goals:** polling, per-frame list rebuilding, or moving playback presentation into Rust.

## Selection

The catalog content-state panels rank first because three exact implementations and unlabeled loaders provide direct evidence, while typed state and recovery rules can remain untouched at each page. The slice must stop at the selected catalog pages and preserve existing live-region boundaries.

## Outcome

Completed on 2026-08-27. Album Tracks, Artist Tracks/Albums, and Ranking now use one `MusicLoadingPanel` and one `MusicContentStatePanel`. Loading presents a visible label plus one merged assistive label; empty/error panels share Material hierarchy; each caller still owns typed copy, retry eligibility, keys, and the decision to create an error live region.

Focused tests cover 360 px dark loading, exact loading semantics, one opt-in error live region, and retry activation. Consuming page suites and full validation pass. Search, Library, Playlist, Discover, append failures, refresh banners, controller models, and snackbars were not changed; no dependency, protocol, Domain, Bridge, queue, or Rust change was introduced.
