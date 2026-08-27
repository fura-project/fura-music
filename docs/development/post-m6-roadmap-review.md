# Post-M6 Roadmap Review — 2026-08-27

## Outcome

The bounded discovery pass found no currently executable, evidence-backed milestone inside the accepted product and architecture boundaries. M6 closed the only immediately executable protocol-compatibility risk selected by the post-M5 audit. The remaining ranked candidates are important, but each requires user operation, a missing target environment, or pending human release authority.

This is `NO_LEGITIMATE_WORK`, not `GLOBAL_STOP`, project completion, or a request for generic approval. New coarse M1 evidence, a supplied target environment, a reproduced regression, a debt trigger, or an accepted product/release decision returns execution directly to global ranking.

## Discovery coverage

The review reread `PROJECT.md`, accepted Human Decisions, `ROADMAP.md`, `PROGRESS.md`, the M5 completeness/checkpoint reviews, the M6 evidence and checkpoint, current technical-debt triggers, architecture boundaries, and the current validation results. It checked the implemented Home, Library, Search, Discover, browsing, playback, Queue, lyrics, comments, and MV journeys; Provider/Domain/Bridge ownership; adaptive/accessibility evidence; live-protocol risks; target-platform evidence; release constraints; and handwritten TODO/FIXME/HACK markers.

No new failing test, reproduced user-flow defect, untracked architecture violation, triggered autonomous debt, or executable platform requirement was found. Generated bridge `unimplemented!` arms and platform-template TODOs are generated/template code, not newly discovered product gaps.

## Ranked candidates

### 1. M1 authenticated playback/Queue/Lyrics observation — Highest value, user-blocked

- **Provenance:** M1 acceptance criterion and the user's earlier all-track playback failure after successful login/library validation.
- **User value:** Establishes that the defining sign-in-to-listening vertical slice works with a real account and corrected media mapping.
- **Current problem:** Offline/local playback, anonymous media resolution, and lyric tests cannot prove authenticated QQ CDN playback followed by Queue and synchronized/word-timed lyrics.
- **Bounded scope:** One maintainer-operated ordinary-Track observation with only coarse `PLAYED` / Queue / lyric outcomes returned; no credential, URL, Track identity, or lyric content is captured.
- **Acceptance criteria:** Playback starts; previous/next or exact Queue selection behaves correctly; synchronized lines advance; word timing is visibly active when the selected lyric provides it; only coarse result is recorded.
- **Effort:** Low user operation; no autonomous implementation unless the observation reproduces a failure.
- **Risk:** Credential/content leakage or a false claim from substituting offline evidence.
- **Explicit non-goals:** Automated vault access, response capture, arbitrary protocol guessing, VIP entitlement conclusions, or broad catalog certification.
- **Why not selected now:** The agent cannot safely perform the real-account observation and must not read stored credentials.

### 2. Required target-runtime validation — High release value, environment-blocked

- **Provenance:** TD-004, M5/M6 platform boundaries, and the cross-platform product claim.
- **User value:** Prevents shipping a target whose secure storage, media, lifecycle, or adaptive behavior is unverified.
- **Current problem:** Physical Android and Apple/Windows environments are absent. Existing Linux, Android x64 emulator, and translated ARM64 evidence cannot prove those runtimes.
- **Bounded scope:** For one supplied release-relevant target at a time, build and run the existing signed-out app, disposable vault contract, Bridge call, local media lifecycle, and focused adaptive smoke appropriate to that target.
- **Acceptance criteria:** The exact target builds; bounded runtime checks pass with cleanup; failures are classified without broadening architecture; claims remain target-specific.
- **Effort:** Medium per target.
- **Risk:** Treating emulation, cross-compilation, or another OS as runtime proof; platform-specific signing or keychain risk.
- **Explicit non-goals:** Emulating unavailable targets, publishing artifacts, redesigning the bridge/audio stack, or claiming all-platform readiness from one target.
- **Why not selected now:** No missing real target environment is available in this session.

### 3. Production identity/signing and native-video notices — Required before release, human-blocked

- **Provenance:** HD-001, triggered TD-002, and release-triggered TD-006.
- **User value:** Makes an eventual external artifact identifiable, securely signed, and accompanied by the exact native-media obligations it distributes.
- **Current problem:** Final name, platform identifiers, signing custody, distribution ownership, and final artifact shape are not decided.
- **Bounded scope:** After HD-001, configure one agreed identity/signing workflow and inventory notices for the exact authorized artifact; add repeatable checks without committing secrets.
- **Acceptance criteria:** Human-selected identities are applied consistently; signing material remains outside Git with documented custody; exact artifact dependencies/notices are inventoried and checked; no development-signed artifact is presented as production.
- **Effort:** Medium to high, target-dependent.
- **Risk:** Credential leakage, irreversible identifier choices, invalid signing custody, or incomplete native-library compliance.
- **Explicit non-goals:** Inventing product identity, generating or taking custody of production secrets without authority, store submission, or broad legal conclusions.
- **Why not selected now:** HD-001 is pending and intentionally blocks this scope.

## Why no new milestone was created

- M5's product-completeness audit found and resolved its sole evidenced autonomous feature gap. No new user report or failing regression contradicts that result.
- M6 now supplies direct selected comments/MV client evidence; serially probing every anonymous catalog endpoint would optimize test activity rather than a demonstrated product risk.
- Cache/offline policy, local/fallback Provider work, background playback, persistent history, mutations, additional discovery/search features, and theme personas either require new evidence or human product authority. They do not become legitimate because the current milestone checkpointed.
- Open TD-001 and TD-005 triggers have not fired. TD-002/TD-006 are release-bound, and the remaining TD-004 instances need unavailable environments.
- Presentation micro-polish without a reproduced adaptive/accessibility/product failure is not a task.

## Resume conditions

Return to `SELECT_OR_DISCOVER_NEXT_TASK` when at least one of the following appears:

- the maintainer supplies the coarse M1 observation or a reproducible playback failure;
- a real required target environment becomes available;
- HD-001 or another accepted Human Decision authorizes bounded work;
- a test, user report, protocol change, dependency breakage, measured performance issue, or debt trigger supplies new evidence;
- Later Direction receives demonstrated user value and Roadmap authority.

Until then, `state: ACTIVE`, `global_stop: false`, and `next_action: NO_LEGITIMATE_WORK` truthfully preserve the distinction between an active maintainable project and manufactured work.
