# M5.2 Bounded Discovery — Library Sections

## Boundary

This pass inspected the authenticated Library composition, playlist controller, favorite Album and Artist controllers, adaptive entry actions, local detail overlays, scroll/focus storage, and current widget regressions. It did not call QQ Music, access stored credentials, change Provider contracts, or propose collection mutation or a generic library model.

## Ranked candidates

### 1. Retained adaptive Library sections

**Provenance:** HD-003; M5 exit criteria 3, 7, 8, and 9.

**User value:** Playlists, favorite Albums, and favorite Artists become three obvious parts of Your Music on compact and desktop layouts, while switching among them does not discard loaded content or the user's place.

**Current problem:** Playlists are the entire Library body. Favorite Albums and Artists are capable paged journeys, but they are launched from two wide AppBar icons or one compact popup and their page-owned controllers are disposed when the user returns to playlists.

**Scope:** Add one official-Material adaptive Library section selector. Keep each collection in its existing controller and view, instantiate favorite sections lazily, retain visited section roots in one presentation-only stack, and keep their detail pages above that stack. Move collection refresh into the selected section rather than leaving collection navigation in utility actions.

**Acceptance criteria:**

- Playlists, Albums, and Artists are directly discoverable at 360 px and desktop widths.
- Favorite controllers remain lazy before first visit and remain the same mounted instances across section and width changes.
- Paging, loading, empty, error, retry, scroll, focus, and nested detail return remain page-owned and do not merge into `UserLibraryController`.
- The authenticated primary navigation and the one persistent Now Playing owner remain visible at every section root.
- Back from Albums or Artists returns to Playlists; back from Playlists returns to Home; detail return restores the selected retained section.
- Focused compact/wide, keyboard/semantics, state-retention, detail-return, and no-overflow regressions pass.

**Effort:** High.

**Major risk:** The current favorite roots sit above the authenticated shell. Moving only their roots into the shell while leaving detail overlays intact can accidentally recreate controllers, duplicate Now Playing, or confuse return precedence.

**Explicit non-goals:** A combined collection feed, shared collection controller, mutation, automatic refresh/cache, Provider/Bridge changes, shell replacement, or a new navigation/state framework.

### 2. Static Library overview cards

**Provenance:** HD-003; M5 exit criterion 3.

**User value:** Two visible cards would make the saved collections easier to find than toolbar icons.

**Current problem:** This improves discovery but preserves three disconnected roots and still disposes a favorite controller when leaving it.

**Scope:** Add bounded entry cards above the playlist collection and keep the existing overlay flows unchanged.

**Acceptance criteria:** All collections are visible and reachable at compact/wide widths without changing their current flows.

**Effort:** Low.

**Major risk:** It can satisfy a screenshot while leaving the retained-state and information-architecture problem unresolved.

**Explicit non-goals:** Retained switching or any collection lifecycle change.

### 3. Combined personalized Library feed

**Provenance:** None sufficient for implementation; retained only as a rejected comparison.

**User value:** A mixed overview could expose sample rows from every collection.

**Current problem:** It would require eager loading, cross-controller aggregation, new partial-failure rules, and a product decision about ordering and density for which the repository has no evidence.

**Effort:** High.

**Major risk:** It creates a second library model and speculative feed behavior while weakening truthful independent failures.

**Explicit non-goals:** This candidate is not selected or authorized as a task.

## Selection

Candidate 1 ranks first. It resolves both the visible product problem and the existing controller-lifecycle problem using the already accepted presentation architecture. Candidate 2 is smaller but incomplete; candidate 3 has no sufficient provenance and is rejected.
