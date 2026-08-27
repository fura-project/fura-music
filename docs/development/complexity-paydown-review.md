# Complexity Paydown Review — 2026-08-27

This review records the bounded maintenance pass authorized by the maintainer. New product capability and visual redesign are frozen; the objective is to preserve the running product while reducing the cognitive and governance cost of changing it.

## Initial code audit

| Rank | Hotspot | Evidence and maintenance problem | Bounded action | Benefit and risk |
| --- | --- | --- | --- | --- |
| 1 | Authenticated presentation coordination | `UserLibraryPage` owns the primary shell, four destinations, three Library sections, playback lifetime, focus restoration, and 15 nullable/boolean local-route fields. Its Back resolver repeats that implicit state as a 22-branch priority chain. | Replace only the implicit local-route fields with one typed presentation route stack, keep the retained `IndexedStack`, and test route/back/focus behavior. | Makes the active destination, subsection, top detail, and next Back result explicit. Main risk is losing retained page state or exact return focus. |
| 2 | Authenticated dependency propagation | More than 20 post-authentication dependencies are declared and forwarded individually through `MusicApp`, `LoginPage`, and `UserLibraryPage`; the same set changes at every hop. | After route behavior is stable, evaluate one immutable responsibility-grouped dependency value owned by the composition root. Keep constructor injection and per-test overrides explicit. | Shrinks mechanical propagation without a service locator. Main risk is hiding ownership in an oversized dependency bag. |
| 3 | Paged async controllers | Track/Artist/Album/Playlist Search and favorite Album/Artist controllers repeat generation, operation identity, cancellation, stale suppression, initial/append state, and disposal. Pairwise diffs show near-identical lifecycle code with feature-specific types substituted. | Extract only a small cancellation/generation primitive if at least three controllers retain identical rules after the navigation task; keep typed failures and pagination policies in each controller. | Reduces repeated lifecycle edits. Main risk is a generic paging framework that obscures feature semantics. |
| 4 | One-to-one Dart Bridge adapters | Search and saved-collection Gateways repeat handle wrapping, exception mapping, result-shape validation, DTO mapping, and near-identical failure enums. The typed boundary is still semantically necessary. | Identify one shared helper for operation execution or invariant checks only where semantics are identical; do not merge feature contracts or use raw JSON. | Lowers mechanical adapter tax. Main risk is erasing recovery or credential differences. |
| 5 | Flutter integration test fixture surface | `widget_test.dart` is about 4,800 lines and contains the authenticated journeys plus many local Gateway/operation fakes; the playback flow test adds another large independent fixture set. | Extract reusable test-only builders/fakes after production constructor shape settles, without deleting distinct regression scenarios. | Makes behavior tests cheaper to add and review. Main risk is a test harness that hides the behavior under test. |

## Initial governance audit

| Rank | Hotspot | Current cost and duplicated information | Durable information to keep | Proposed simplification |
| --- | --- | --- | --- | --- |
| 1 | `PROGRESS.md` | Current scheduling is mixed with a long M1–M7 implementation history already present in Git and checkpoint reviews. | Active work, local blockers, pending decisions, current evidence gaps, and the exact next action. | Rewrite around current state, active maintenance work, blockers, candidates, decisions, and risks. |
| 2 | `ROADMAP.md` | Completed M3–M6 sections retain per-slice implementation diaries; M7 is still marked active despite the new feature/UI freeze. | Each milestone's goal, short outcome, checkpoint date, useful review link, deferred scope, and the current authorized maintenance direction. | Compress completed milestones and replace active M7 scheduling with this bounded consolidation pass. |
| 3 | Micro-task discovery/ranking documents | Many M3/M4 files record selection and implementation outcome already recoverable from commits, Roadmap history, and checkpoint reviews. | Protocol evidence, unusual reproductions, architecture decisions, milestone audits, and checkpoint evidence. | Remove only clearly selection-only/ranking-only documents after checking references; do not mass-archive or delete protocol research. |
| 4 | `AGENTS.md` task ceremony | The safeguards are valuable, but the current loop can be read as requiring persistent selection/ranking documentation for every small task. | Security, boundaries, provenance, failure budget, tests, Human Decision scope, and `GLOBAL_STOP` semantics. | State that ordinary work is inspect → implement → test → commit, with persistent documentation only when durable knowledge or scheduling materially changes. |
| 5 | Completion language | Checkpoints carefully list evidence limits, but repeated “completed” summaries can still read as running-product completion. | Exact test, live-service, platform, and user-observation boundaries. | Define `Implemented`, `Verified`, and `Product-complete` once, then use concise milestone outcomes without another status framework. |

## Ranked execution

1. Make authenticated local navigation explicit while preserving the retained widget tree and focus behavior.
2. Reduce authenticated dependency propagation only if responsibility grouping remains explicit and independently overrideable.
3. Consolidate the highest-confidence repeated controller/adapter or test setup, choosing the smallest semantic primitive rather than a framework.
4. Simplify governance after the code ownership changes are known, then run the full repository gates and answer the maintenance self-review.

## Implemented outcome

| Area | Change | Result |
| --- | --- | --- |
| Authenticated presentation | Replaced 15 unrelated nullable/boolean route fields and the 22-branch Back resolver with one small typed local-route stack. The existing retained `IndexedStack`, controllers, detail widgets, focus targets, playback owner, Queue, lyrics, comments, and MV surfaces remain in place. | The primary destination, Library section, top local detail, and next Back target are independently inspectable. `UserLibraryPage` decreased from 2,123 to 1,668 lines without moving its widget tree into another coordinator. |
| Composition root | Grouped post-authentication constructor dependencies by Library/Catalog, Discovery/Search, and Playback responsibility. Defaults and granular test overrides remain at `MusicApp`; no global lookup was introduced. | `MusicApp` → `LoginPage` → `UserLibraryPage` forwards three explicit immutable values instead of more than 20 parallel values. `app.dart` decreased from 1,015 to 913 lines. |
| Cross-feature semantics | Shared the four Search types' identical failure taxonomy and retry rule. Results, pagination, credential handling, Bridge validation, and presentation states remain feature-specific. | Removes repeated policy edits without a universal application error or generic paging framework. |
| Test setup | Shared the identical playback-Queue fake used by Album, Artist, and Track Search widget tests. | Distinct regression scenarios and assertions remain; only mechanical setup moved to test support. |

The controller audit confirmed substantial structural similarity, but no generic paged controller was introduced: lifecycle, pagination, and typed-result differences still make that extraction higher-risk than the demonstrated benefit. The Bridge adapter audit likewise retained all typed provider-neutral boundaries; reducing file count there would have removed semantic ownership rather than duplication.

## Governance outcome

- `AGENTS.md` now defines the ordinary workflow and evidence vocabulary once while preserving provenance, architecture, credential safety, failure-budget, validation, Human Decision, and stop rules.
- `PROGRESS.md` contains current scheduling and evidence gaps rather than the M1–M7 implementation chronology.
- `ROADMAP.md` retains milestone goals, concise outcomes, checkpoint links, the M1 acceptance gap, the paused M7 boundary, and future authority without per-slice diaries.
- Those three governance files decreased from 546 to 222 lines.
- Five unreferenced M4 post-task ranking snapshots were removed after inspection. They contained only superseded task selection and repeated test summaries; milestone reviews, protocol research, reproduction evidence, and checkpoint documents remain.
- `ARCHITECTURE.md`, `README.md`, and HD-005 now describe the actual typed route stack, grouped composition dependencies, maintenance freeze, and evidence boundary.

## Verification

- Rust formatting and strict Clippy passed.
- All 300 offline Rust tests passed; 6 credential-free live QQ compatibility tests remained ignored by default and were not run.
- Dart formatting and analysis passed.
- All 342 Flutter tests passed.
- Linux release build passed.
- Linux packaged integration passed for the typed Rust Bridge, one disposable non-account secure-storage marker, generated local/loopback audio, and generated local MP4 control.

These checks prove the preserved offline rules and the named local Linux paths. They do not prove current authenticated QQ CDN playback, broad live catalog behavior, remote MV playback, physical devices, Apple/Windows runtime, release readiness, or user-visible product completeness.

## Final self-review

**Is the authenticated presentation easier to modify?** Yes. A primary destination change no longer requires understanding every detail flag, while one local-detail route is represented by one typed value and Back removes the top value. Playback lifetime and focus restoration remain visibly owned by `UserLibraryPage`, rather than being hidden inside the navigation state.

**Can a future developer alter a destination without understanding every overlay state?** Yes for primary destinations and Library sections. Adding a new local detail still intentionally requires a route type and its retained builder, but no priority condition must be inserted into a global Back chain.

**Was complexity reduced rather than moved?** Yes. The new navigation model and dependency values total 258 focused lines, while they remove implicit state coupling and hundreds of lines from the two former hotspots. Search sharing is a 17-line semantic policy, not a generic controller framework. Test sharing contains no production behavior.

**Did an abstraction make behavior harder to trace?** No identified case. Dependency groups are immutable constructor values, navigation mutations are synchronous and typed, and all feature-specific result and recovery paths remain at their previous layers. The deliberately rejected generic controller and Bridge flattening avoid the two highest abstraction risks found in the audit.

**Is documentation cheaper to maintain, and is `PROGRESS.md` current?** Yes. Ordinary tasks no longer require selection/checkpoint documents; completed implementation detail remains in Git and checkpoint evidence. `PROGRESS.md` now states only the current freeze, completed maintenance result, blockers, next evidence, decisions, and risks.

**Were useful disciplines preserved?** Yes. The Flutter/Rust, Provider, Bridge, playback, Queue, lyrics, comments, and MV ownership boundaries did not change. No endpoint, Provider, feature, theme, framework, raw JSON boundary, account automation, regression deletion, or protocol-evidence deletion was introduced.

## Post-pass ranking

1. Representative authenticated compact/desktop running-app review has the highest immediate information value because automated tests cannot establish M7's user-visible product effect. It must be maintainer-operated: autonomous startup could consume stored account credentials.
2. The existing M1 playback → Queue → synchronized/word-timed lyrics observation can be recorded from the same kind of coarse maintainer operation when convenient.
3. Physical-target and release evidence remains environment- or HD-001-blocked.

No agent-only feature, compatibility probe, refactor, or numbered milestone has stronger current evidence. M7 remains paused; this maintenance result does not silently authorize its resumption.
