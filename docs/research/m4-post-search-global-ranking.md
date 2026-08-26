# M4 Post-search Global Ranking — 2026-08-27

## Trigger

The finite Search content-state migration completed and `PROGRESS.md` returned autonomous execution to whole-project ranking before another presentation task.

## Evidence review

- Strict Dart checks, all 304 Flutter tests, 267 offline Rust tests, strict all-target Clippy, Linux x64 Release, and packaged typed-Bridge integration pass. No new playback, credential, Provider, Bridge, navigation, data-safety, or platform correctness failure appeared.
- M1 still needs one user-operated real-account playback → queue → synchronized/word-timed lyric observation. Automation cannot truthfully manufacture that evidence or read the stored credential.
- TD-001 and TD-005 triggers remain unchanged. TD-002 remains locally blocked by HD-001, while TD-004 needs unavailable target-specific runtime environments and does not displace local M4 work.
- All five Discover sections still duplicate bare loading indicators and a private content-state layout. The established shared panels can close that active M4.4 consistency gap without changing controllers, Provider behavior, retained state, or navigation.
- Radar has credential-rejection and account-replacement recovery actions that must stay page-owned. New Albums and New Songs must retain their region/category shells around every state.
- Playback, Queue, and Lyrics already have one shared owner and extensive correctness coverage. M4.5 needs a fresh bounded product-surface discovery rather than an aesthetics-led change.

## Ranked candidates

### 1. Shared Discover content states — selected

- **Provenance:** M4.4 and M4 exit criteria 1, 4, and 6.
- **User value:** Playlists, Rankings, Radar, New Albums, and New Songs use one predictable Material grammar for loading, empty, failure, and recovery while preserving contextual controls.
- **Current problem:** the five sections repeat bare progress indicators and a private state panel despite an established bounded shared component.
- **Scope:** migrate only initial loading/empty/error presentation in `RecommendedPlaylistsPage`; keep exact keys, copy, retry/sign-in/reload actions, Radar credential distinctions, and New Album/Song selectors.
- **Acceptance criteria:** all five sections use the shared panels; loading labels identify the active section; errors own one live region; Radar recovery remains exact; region/category controls remain reachable; 360 px has no overflow; focused and full validation pass.
- **Effort:** Medium.
- **Risk:** a mechanical conversion could flatten Radar account recovery or move New Album/Song selectors outside their retained shells.
- **Explicit non-goals:** content rows, append footers, controllers, failure enums, Provider/Bridge/Rust changes, navigation, Search, or new Discover features.

### 2. M4.5 playback/queue/lyrics discovery — deferred

- **Provenance:** the next authorized M4 phase.
- **User value:** identifies the highest-value product-level playback surface slice without duplicating ownership or inventing controls.
- **Ranking reason:** valid after the finite remaining M4.4 family closes; no reproduced playback correctness failure currently requires interrupting it.
- **Effort:** Discovery.
- **Risk:** beginning from visual preference could create a second transport surface or unsupported queue behavior.
- **Explicit non-goals:** background playback, shuffle/repeat, palette/theme experiments, new queue rules, or protocol guessing.

## Selection

Shared Discover content states are the highest-value legal task. The slice completes the explicit Search/Discover state-language family using existing presentation components, while preserving every credential-aware and contextual action at the page boundary.

## Outcome

Completed as a Discover-only presentation slice. Recommended Playlists, ranking groups, Radar, New Albums, and New Songs now reuse `MusicLoadingPanel` and `MusicContentStatePanel`; exact keys, copy, retry/sign-in/reload actions, Radar credential distinctions, controllers, and lazy retained state remain page-owned. The New Album region and New Song category selectors continue to wrap loading, empty, error, and content states.

Regressions cover the labeled compact recommendation loading state, all five 360 px empty states, both contextual selectors, and Radar credential rejection with exactly one live region plus the existing sign-in recovery. Strict Dart formatting/analysis, all 307 Flutter tests, Rust formatting, 267 offline Rust tests, strict all-target Clippy, Linux x64 Release, and packaged typed-Bridge integration pass. Four live QQ/WeChat tests remain gated and ignored; no stored credential or live service was accessed, so this does not close the M1 real-account playback evidence gap.
