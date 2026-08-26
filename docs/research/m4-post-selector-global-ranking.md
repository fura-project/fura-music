# M4 Post-selector Global Ranking — 2026-08-27

## Trigger

The catalog header, Discover Track rows, and adaptive Search/Discover secondary selector completed three consecutive presentation-focused slices. Per repository anti-drift rules, task selection returned to the whole project before another presentation task.

## Evidence review

- M1 still needs one user-operated real-account playback → queue → synchronized/word-timed lyric observation. The implementation, local playback engine, queue, lyric timing, retry, cancellation, and offline regressions already exist; automation cannot truthfully manufacture the remaining authenticated CDN evidence or read the user's stored credential.
- No new reproduced playback, credential, Provider, Bridge, navigation, data-safety, or platform correctness failure appeared during the three slices. The complete 301-test Flutter and 267-test offline Rust baselines, strict analysis/Clippy, Linux Release, and packaged typed Bridge all pass.
- TD-001 and TD-005 triggers have not changed. TD-002 remains locally blocked by accepted HD-001 release identity/signing choices. TD-004 requires target-specific Apple/Windows runtime environments before those platforms can make distribution claims; it does not displace authorized local M4 product work.
- M4.4 still has one concrete exit-criterion gap: four Search types use bare spinners plus private idle/empty/error panels, while the established Material loading/content-state components already preserve page-owned copy, actions, keys, and live-region policy.
- Discover has a similar but broader gap across five typed surfaces, including credential-specific Radar recovery. It should follow as a separate page-family task rather than be mixed with Search.
- M4.5 playback/queue/lyrics remains the next authorized phase, but it needs a fresh bounded discovery after the remaining finite M4.4 state work rather than speculative transport or animation changes.

## Ranked candidates

### 1. Shared Search content states — selected

- **Provenance:** M4.4 and M4 exit criteria 1, 5, 7, and 8.
- **User value:** every Track/Artist/Album/Playlist search has predictable labeled loading, empty, error, retry, and edit-query presentation in light/dark and compact/desktop contexts.
- **Current problem:** the four types duplicate bare progress indicators and private state panels even though the shared bounded Material components already exist.
- **Scope:** migrate Search idle/loading/empty/error presentation only; preserve exact copy, keys, retry eligibility, edit action, live-region ownership, controllers, queries, results, pagination, and navigation.
- **Acceptance criteria:** all four types use shared state components; loading has type-specific assistive labels; exact existing keys and actions remain; error owns one live region; compact Search has no overflow; focused and full validation pass.
- **Effort:** Medium.
- **Risk:** a mechanical conversion could lose retry/edit combinations or duplicate assistive announcements.
- **Explicit non-goals:** Discover states, result rows, append footers, error-domain/controller changes, new retry policy, Search features, or generic state framework.

### 2. Shared Discover content states — deferred

- **Provenance:** M4.4 and M4 exit criterion 7.
- **User value:** all five Discover types would use the same Material state grammar.
- **Ranking reason:** valid and likely next, but broader because Radar owns sign-in/reload distinctions and New albums wraps region selection around its states.
- **Effort:** Medium–High.
- **Risk:** flattening credential recovery or removing context controls from empty/error states.
- **Explicit non-goals:** controller or Provider changes.

### 3. M4.5 playback/queue/lyrics discovery — deferred

- **Provenance:** next authorized M4 phase.
- **User value:** establishes the next product-level playback surface work from evidence rather than local visual preference.
- **Ranking reason:** no newly reproduced playback correctness failure outranks the finite active M4.4 consistency gap; the real-account M1 observation remains user-operated.
- **Effort:** Discovery.
- **Risk:** starting from aesthetics could duplicate the playback owner or invent unsupported controls.
- **Explicit non-goals:** background playback, new queue rules, shuffle/repeat, palette/theme experiments, or protocol guessing.

## Selection

Shared Search content states remain the highest-value legal task after whole-project review. The slice closes an explicit active-Roadmap gap with existing components and no architecture expansion, while all higher-severity alternatives are either already covered, evidence-gated, environment-specific, or locally blocked.
