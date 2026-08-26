# M4.5 Playback Product Discovery — 2026-08-27

## Audit boundary

This bounded pass inspected the mini player, expanded Now Playing, adaptive Queue sheet/dialog, Lyrics sheet/dialog and inline wide layout, plus existing compact, wide, keyboard, pointer, focus, duplicate-position, loading, unavailable, error, retry, selected, playing, and seek regressions. It did not access QQ Music, read stored credentials, change playback ownership, or propose new queue behavior.

## Findings

- One `QueuePlaybackController` still owns the Rust positional queue, foreground playback, and lyric controller. The same progress, transport, queue, volume, and lyric paths survive retained navigation and modal focus; no second owner is needed.
- The Queue correctly preserves duplicates, positional selection/removal, current state, artwork fallback, clear confirmation, and one failure live region. However each row shows only title and Artist even when the existing provider-neutral Track already carries its queue position, Album title, and truthful duration. Compact and desktop dialogs use the same information density.
- Expanded Now Playing already adapts artwork/lyrics at 900 px and reuses the mini player as the only transport/progress/queue/volume implementation. Moving controls into the hero is a larger product/architecture decision than the Queue row gap and should not be mixed into a first M4.5 slice.
- Lyrics intentionally isolates announcement copy from recovery controls, supports exact line seeking and follow suspension, and has strong controller regressions. Its private state layout cannot be mechanically replaced by the shared panel without first preserving that semantic distinction.

## Ranked candidates

### 1. Adaptive Queue information hierarchy — selected

- **Provenance:** M4.5 and M4 exit criteria 1, 4, 5, 6, and 8.
- **User value:** users can identify queue order and distinguish similarly named Tracks by Album and duration without opening another surface.
- **Current problem:** existing queue rows discard presentation of already-available position, Album, and duration and do not adapt density between a compact sheet and desktop dialog.
- **Scope:** improve Queue rows only; show one-based position, existing Artist/Album metadata, truthful duration, compact/desktop density, and the existing selected/current/remove actions.
- **Acceptance criteria:** 360 px rows show position plus Artist/Album/duration without overflow; wider Queue rows keep duration in a compact dedicated column; unknown metadata remains honest; duplicate positions, selection, removal, current indicator, action keys, and semantics remain exact; focused and full validation pass.
- **Effort:** Medium.
- **Risk:** additional leading/trailing content can narrow long titles or accidentally merge visual metadata into action semantics.
- **Explicit non-goals:** queue reorder, persistence, shuffle/repeat, controller/Rust/Bridge changes, new context actions, playback controls, or Now Playing/Lyrics redesign.

### 2. Expanded Now Playing transport hierarchy — deferred

- **Provenance:** M4.5 and the explicit expanded Now Playing product goal.
- **User value:** a deliberate full-screen hierarchy could make primary transport feel native to the expanded surface rather than visually inherited from a mini bar.
- **Ranking reason:** higher scope and architecture risk because the current accepted implementation deliberately keeps one transport/progress implementation in the bar. It requires a separate finite design and reuse plan after the Queue slice.
- **Effort:** High.
- **Risk:** duplicated controls, divergent enabled states, compact-height overflow, or a second playback presentation owner.
- **Explicit non-goals:** immediate implementation during the Queue task.

### 3. Lyrics state-language alignment — deferred

- **Provenance:** M4.5 and M4 exit criteria 4 and 7.
- **User value:** loading and non-content lyric states could align more closely with the Material baseline.
- **Ranking reason:** the current state component deliberately keeps live announcement copy separate from sign-in/retry actions. Preserving that accessibility behavior matters more than a mechanical visual conversion.
- **Effort:** Medium.
- **Risk:** duplicate announcements or recovery actions entering a live region.
- **Explicit non-goals:** QRC/timing changes, lyric animation experiments, or shared-panel expansion without a demonstrated need.

## Selection

Adaptive Queue information hierarchy is the highest-value bounded M4.5 slice. It exposes existing honest data in a high-frequency surface, has clear compact/desktop acceptance criteria, and does not alter playback, queue, lyric, Provider, or Bridge ownership.

## Outcome

Completed on 2026-08-27. Queue rows now show one-based visual position, existing Artist/Album metadata, and truthful duration; compact sheets keep duration in metadata while desktop dialogs use a dedicated duration column. Current selection, duplicate positions, positional removal, artwork, action keys, and the existing Queue semantics remain unchanged.

The focused Queue/Now Playing suite passes 32 tests. Strict Dart formatting and analysis, all 308 Flutter tests, 267 offline Rust tests, strict all-target Clippy, the Linux x64 Release build, and the packaged typed-Bridge integration pass. Four live QQ/WeChat tests remain gated and ignored, so this outcome does not close the user-operated M1 real-account playback, queue, or lyric observation.
