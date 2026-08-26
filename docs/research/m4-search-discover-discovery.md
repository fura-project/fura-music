# M4 Search and Discover Discovery — 2026-08-27

## Evidence

- Search and Discover already preserve independent controllers and return state inside the retained Material app shell. No reproduced back-stack, focus-restoration, or state-loss failure justifies replacing the current navigation structure.
- Search exposes four typed result controllers behind one horizontally scrollable `SegmentedButton`; Discover exposes five retained content types through the same compact pattern. Both remain reachable at 360 px in existing regressions, so their secondary-navigation hierarchy is a product-quality candidate rather than a correctness emergency.
- Search and Discover still use separate bare progress indicators and private message panels instead of the shared Material loading/content-state presentation. A migration would touch nine independently typed state machines and therefore needs a bounded follow-up rather than an incidental rewrite.
- Radar and New songs implement two near-identical Track `ListTile` rows beside the shared catalog `MusicTrackTile`. Both already use the same presentation-safe Track model and the same play/add-to-queue contract, but omit the shared position, Album metadata, truthful duration, artwork semantics, and compact/desktop density grammar.
- Theme, authenticated shell, light/dark baseline, primary navigation, and retained page ownership remain consistent with M4.1/M4.2. No Provider, Bridge, playback, credential, debt-trigger, or platform failure outranks the concrete M4.4 Track-row inconsistency.

## Ranked candidates

### 1. Shared Discover Track rows — selected

- **Provenance:** M4.4 and M4 exit criteria 1, 5, 6, 7, and 8.
- **User value:** Radar and New songs show the same position, artwork, title, Artist/Album metadata, duration, density, and queue action that users already learn on Album, Artist, and Ranking pages.
- **Current problem:** two Discover Track collections duplicate a reduced row that drifts from the established catalog grammar despite consuming the same model and callbacks.
- **Scope:** migrate only Radar and New songs to `MusicTrackTile`, preserve their exact item/queue keys and callbacks, and remove the two now-unused private artwork widgets.
- **Acceptance criteria:** both collections use the shared tile with one-based positions; existing queue/play behavior, pagination/category state, retained Discover state, and test keys remain exact; 360 px has no overflow; focused and full validation pass.
- **Effort:** Low–Medium.
- **Risk:** changing leading width and metadata could regress compact reachability or invalidate existing interaction finders.
- **Explicit non-goals:** Search/Playlist rows, current-playing styling, controller or queue changes, selectors, state panels, Provider/Bridge work, and artwork redesign.

### 2. Adaptive Search/Discover secondary selector — deferred

- **Provenance:** M4.4 and M4 exit criteria 3–5 and 8.
- **User value:** four Search types and five Discover types could remain immediately understandable without relying on a partly off-screen segmented control at compact widths.
- **Current problem:** the controls are reachable by horizontal scroll but do not expose every option simultaneously at 360 px.
- **Scope:** one official-Material adaptive secondary-navigation pattern shared by Search and Discover while preserving every retained controller.
- **Acceptance criteria:** all types remain keyboard/touch/pointer reachable at 360 px and desktop; selected state, lazy loading, query/controller state, focus, and back behavior remain exact.
- **Effort:** Medium.
- **Risk:** control replacement can break existing semantics, focus, and tests despite no current correctness failure.
- **Explicit non-goals:** new Search/Discover types, navigation framework, heterogeneous Home, suggestions/history, or controller consolidation.

### 3. Shared Search/Discover content states — deferred

- **Provenance:** M4.4 and M4 exit criterion 7.
- **User value:** loading, empty, error, retry, and credential-recovery states would use one predictable visual and assistive pattern.
- **Current problem:** nine typed surfaces use bare spinners and two private message implementations even though a shared Material state panel now exists.
- **Scope:** migrate states in bounded page-family slices while retaining exact typed copy, retry eligibility, keys, and live-region ownership.
- **Acceptance criteria:** labels, retry/account actions, announcements, controller snapshots, and all existing state keys remain exact without duplicate live regions.
- **Effort:** Medium–High.
- **Risk:** a broad mechanical conversion could flatten genuinely different credential and retry semantics.
- **Explicit non-goals:** error-domain unification, controller changes, new cache/retry rules, or generic state framework.

## Selection

Shared Discover Track rows rank first because the common data and interaction contract already exists, the visible inconsistency affects two current high-value Track journeys, and the slice can be completed without changing state ownership or navigation. Selector and state-panel work remain valid M4.4 candidates but require separate focused evidence and regressions.
