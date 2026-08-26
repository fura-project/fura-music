# M3 Compact Library Actions Discovery — 2026-08-27

## Evidence boundary

- Adding favorite Artists made the authenticated library AppBar carry six independent 48 px actions. The 360 px regression can avoid overflow only by removing the visible `Your music` title below 390 px, so compact users lose the page identity while every action remains permanently expanded.
- The existing 390 px sign-out regression requires the title after dismissing its confirmation surface, while the favorite-Artist regression proves the same AppBar and collection routes at 360 px. This is a reproduced adaptive-layout conflict, not an aesthetic preference.
- Favorite Albums and favorite Artists are two closely related saved-collection destinations. Grouping only those destinations on compact width reduces permanent toolbar pressure without hiding Search, Discover, refresh, or sign-out and without changing Provider, Domain, Bridge, playback, or navigation ownership.

## Global ranking

### 1. Compact saved-collection actions — selected

- Goal: keep the authenticated library identity and every existing action reachable at 360 px without an overflowing six-icon toolbar.
- Provenance: reproduced adaptive-layout failure introduced by the now-complete M3 favorite-Artist slice; `PROJECT.md` mobile-first-class and clear information-hierarchy requirements.
- Scope: always retain the `Your music` title; at compact width replace only the two favorite-collection icons with one typed popup menu; preserve the two direct icons on wider layouts; restore keyboard focus to the actually mounted compact or wide entry after collection return.
- Acceptance criteria: no 360 px overflow; title remains visible; both collection destinations are reachable through touch/pointer, semantics, and keyboard activation; returning from either collection focuses the mounted entry; existing collection state/navigation and all other toolbar actions remain unchanged; focused widget regressions plus full Flutter/static/Linux validation pass.
- Explicit non-goals: a new navigation framework, bottom-navigation/rail redesign, moving Search or Discover, changing collection data/controllers, new protocol work, icon/style-system redesign, or grouping unrelated actions.

### 2. “Guess you like” Track batch — deferred

- Provenance: M3 recommendation direction and current source evidence for `music.radioProxy.MbTrackRadioSvr/get_radio_track`.
- Ranking reason: it overlaps the existing paged Radar Track surface, one source builds a larger list by repeated cursorless calls, and no current product requirement establishes how two personalized Track feeds should differ in this client.

### 3. Heterogeneous QQ Home Feed — deferred

- Provenance: M3 home direction and current source evidence for a multi-shelf feed.
- Ranking reason: returned cards are heterogeneous and tracking-rich; the current evidence does not yet justify a stable project Domain or a broad Home adapter, while the compact navigation failure is already reproduced locally.

Track availability/quality remains evidence-blocked, and unavailable platform validation remains environment-blocked.

## Selection

The compact saved-collection menu is the smallest correction that preserves mobile identity and reachability after M3 expanded the real toolbar. It addresses an observed regression without turning the task into a navigation rewrite or inventing another recommendation product.
