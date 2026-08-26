# M4 Post-Queue Global Ranking — 2026-08-27

## Trigger

The adaptive Queue information-hierarchy slice completed and `PROGRESS.md` returned autonomous execution to whole-project ranking before another presentation task.

## Evidence review

- Strict Dart checks, all 308 Flutter tests, 267 offline Rust tests, strict all-target Clippy, Linux x64 Release, and packaged typed-Bridge integration pass. Four live QQ/WeChat tests remain gated and ignored.
- M1 still needs one user-operated real-account playback → queue → synchronized/word-timed lyric observation. Automation cannot truthfully manufacture that evidence or read the stored credential.
- TD-001 and TD-005 triggers remain unchanged. TD-002 remains locally blocked by HD-001, while the unavailable Apple/Windows instances of TD-004 do not displace locally executable M4 work.
- Expanded Now Playing already owns the deliberate large artwork, Track title, Artist, Album, and inline lyric hierarchy. Its bottom surface nevertheless embeds the complete mini player, duplicating artwork and Track copy while giving the primary transport the same visual weight as utility actions.
- The existing `NowPlayingBar` already centralizes progress, transport enablement, authentication recovery, volume, Queue entry, shortcuts, and one `QueuePlaybackController`. A bounded presentation mode can remove the duplicated mini-player identity while reusing those exact actions and ownership.
- Lyrics has no reproduced correctness or reachability failure. Its private live-region boundary remains intentional and should not be mechanically converted for visual consistency.

## Ranked candidates

### 1. Expanded Now Playing control hierarchy — selected

- **Provenance:** M4.5 and M4 exit criteria 1, 3, 4, and 6.
- **User value:** the immersive page reads as one coherent playback surface: hero content identifies the Track, while a deliberate control surface makes progress and the primary transport predictable without repeating mini-player content.
- **Current problem:** the expanded page currently renders both its large Track hero and the complete mini player, duplicating artwork/title/status and leaving primary transport visually undifferentiated from volume and Queue utilities.
- **Scope:** add one bounded expanded presentation mode to the existing `NowPlayingBar`; keep one progress implementation and the exact previous/primary/next/stop, authentication, volume, and Queue actions; omit duplicated mini-player artwork/title and the redundant modal Lyrics entry only on the expanded page.
- **Acceptance criteria:** compact and wide expanded pages show one Track identity hierarchy and one dedicated controls surface; the primary action is visually prominent; progress, previous/next/stop, sign-in recovery, volume, Queue, shortcuts, keys, enabled states, clear-to-empty behavior, and return state remain exact; 360 px does not overflow; focused and full validation pass.
- **Effort:** Medium.
- **Risk:** changing repeated control composition could break key-based tests, keyboard traversal, compact width, authentication recovery, or utility reachability.
- **Explicit non-goals:** new playback actions, duplicated controllers, queue semantics, lyric timing/state changes, gestures, palette extraction, animation experiments, protocol/Domain/Bridge/Rust changes, or a reusable design-system framework.

### 2. Lyrics state-language alignment — deferred

- **Provenance:** M4.5 and M4 exit criteria 1 and 4.
- **User value:** lyric loading and non-content states could eventually align more closely with the shared Material state language.
- **Ranking reason:** current Lyrics behavior is accessible and tested; its live announcement content is deliberately separated from recovery controls, so no mechanical migration is justified while the expanded hierarchy has a clearer user-visible gap.
- **Effort:** Medium.
- **Risk:** duplicate live announcements or recovery controls entering the announced region.
- **Explicit non-goals:** implementation during the expanded-controls task.

### 3. M4.6 cross-platform product audit — deferred

- **Provenance:** the next authorized M4 phase.
- **User value:** a bounded matrix audit can identify any remaining 360 px, desktop, resize, light/dark, keyboard, pointer, touch, state, or focus regression before checkpoint review.
- **Ranking reason:** complete the finite, evidenced M4.5 hierarchy gap first, then audit the resulting baseline rather than reviewing a surface already selected for change.
- **Effort:** Discovery.
- **Risk:** an unbounded audit could degrade into speculative visual polish.
- **Explicit non-goals:** immediate broad page rewrites or pixel-perfect golden infrastructure.

## Selection

Expanded Now Playing control hierarchy is the highest-value bounded task. It removes a concrete duplicated information hierarchy on a high-frequency surface while retaining the exact playback owner, action callbacks, shortcuts, and Rust positional Queue boundary.
