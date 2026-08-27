# M5.3 Bounded Discovery — Authoritative Playback Modes

## Boundary

This pass inspected the provider-neutral Rust positional queue, its typed Bridge handle and snapshot, the Dart gateway, the single queue/playback/lyric coordinator, mini and expanded transport controls, Queue presentation, and their offline regressions. It did not call QQ Music, access stored credentials, change Provider/media/lyric behavior, or authorize persistence or background playback.

## Existing evidence and required semantics

The current queue deliberately preserves public insertion order, exact positional selection/removal, and duplicate Track identities. Flutter starts or stops the foreground engine only after a Rust update identifies the authoritative current position. Automatic completion is already routed separately from manual next/previous, so repeat-one can remain a Domain rule without leaking engine state into Rust.

M5 authorizes sequential, repeat-all, repeat-one, and shuffle as mainstream daily-use behavior. A coherent mainstream model has two independent settings rather than four mutually exclusive labels:

- order is sequential or shuffle;
- repeat is off, all, or one.

Sequential means shuffle off plus repeat off. Repeat one affects automatic completion, while manual next/previous still navigate the active order. Repeat all wraps manual navigation and automatic completion. Shuffle changes traversal, not the displayed Queue order or positional mutation API, and can compose with repeat all/one without inventing another queue owner.

Enabling shuffle starts a cycle anchored at the current position and randomizes the remaining positions. Selection, replacement, or membership mutation starts a new cycle anchored at the resulting current position; disabling shuffle retains the same current Track. Completion with repeat one replays the same position. With repeat off, completion stops at the end of the active order. Repeat all wraps sequential order or begins a newly shuffled cycle. Mode changes do not restart current playback, and mode state remains session-local across Queue replacement/clear.

## Ranked candidates

### 1. Complete two-axis Rust-owned mode slice

**Provenance:** HD-003; M5 phase M5.3 and exit criteria 4, 7, 8, and 9.

**User value:** The user gets the four expected daily playback behaviors with predictable controls in both mini and expanded Now Playing, while Queue order and duplicate entries remain understandable.

**Current problem:** Completion stops at the last position, previous/next are physically bounded, and no authoritative mode exists in snapshots. Adding presentation flags alone would make Flutter disagree with Rust about what completion or navigation means.

**Scope:** Add small provider-neutral order/repeat types and traversal state to `PlaybackQueue`; include them in the existing coarse snapshot; expose typed setters through the existing handle/gateway/controller; and add accessible compact/wide controls using the existing Now Playing implementation. Keep random cycle construction deterministic under a supplied seed for Domain tests and initialize production entropy at the Rust Bridge edge without adding a dependency.

**Acceptance criteria:**

- Sequential, repeat-all, repeat-one, shuffle, shuffle-plus-repeat, single-entry, duplicate-entry, terminal completion, manual navigation, explicit selection, replacement, push, removal, and clear have deterministic Rust tests.
- Public Queue order and positional identity never change merely because shuffle is enabled.
- Snapshot mode state is validated and mapped through one typed Bridge/Dart contract; mode changes never cause media resolution or restart current playback.
- Automatic completion follows repeat-one/all/off exactly once; Flutter never computes the next position.
- Mini and expanded Now Playing expose understandable, keyboard/touch-accessible state controls without hiding Queue/volume or overflowing at 360 px.
- Focused Domain, Bridge, gateway, controller, and widget regressions plus the repository baseline pass.

**Effort:** High but bounded.

**Major risks:** Shuffle history can become inconsistent after positional mutation; same-position replay can be confused with a no-op; adding controls can regress compact density; generated Bridge bindings can drift.

**Explicit non-goals:** Queue persistence, recent history, cross-session mode persistence, background playback, autoplay/radio, reordering or drag-and-drop, smart shuffle, Provider changes, a second player, or a new dependency/framework.

### 2. Repeat modes first, shuffle in a second slice

**Provenance:** The same M5 authorization, but only a partial phase result.

**User value:** Repeat all/one would arrive with less initial traversal complexity.

**Current problem:** It would temporarily establish a public mode shape and UI that must be expanded immediately for already-authorized shuffle, increasing Bridge/code-generation churn and control redesign.

**Scope:** Add repeat off/all/one to the existing order and defer shuffle state.

**Acceptance criteria:** Sequential and repeat completion/navigation work end to end without claiming M5.3 complete.

**Effort:** Medium.

**Major risk:** A locally smaller change creates avoidable interim architecture and presentation work.

**Explicit non-goals:** Shuffle until a follow-up task.

### 3. Flutter-owned mode flags over the bounded Rust queue

**Provenance:** None sufficient for implementation; retained only as a rejected comparison.

**User value:** It would minimize immediate Core changes.

**Current problem:** Flutter would have to decide wrapping, replay, shuffle order, and mutation repair while Rust still reports incompatible `hasNext`/`hasPrevious` state. That creates two queue authorities and violates the accepted boundary.

**Effort:** Medium initially, high to repair.

**Major risk:** Divergent completion/navigation behavior, duplicate-identity mistakes, and non-reusable business rules.

**Explicit non-goals:** This candidate is not selected or authorized as a task.

## Selection

Candidate 1 ranks first. The current queue already supplies the difficult positional foundation, and a single coherent typed change avoids an interim contract while satisfying the complete authorized daily-use behavior. Candidate 2 is smaller but causes immediate rework; candidate 3 violates the architecture and is rejected.
