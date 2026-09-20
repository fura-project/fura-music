# UI / Product Development

Use this guide for Flutter page composition, visual hierarchy, layout, adaptive behavior, Material 3 presentation, visual states, interaction, accessibility, and implementation of approved Stitch/Figma designs.

The shared authority, execution-mode, security, Git, and reporting rules in [`AGENTS.md`](../../AGENTS.md) always apply.

## Visual authority

```text
Human or approved design defines visual WHAT and visual HOW.
The Agent decides implementation HOW.
```

Use this order:

1. Human product decision;
2. latest Human-approved Stitch/Figma frame;
3. explicit Human annotation or `DESIGN_SPEC`;
4. approved reference screenshot;
5. Material Design 3 rules;
6. existing implementation;
7. Agent visual preference.

An approved design is executable UI provenance. Do not replace its composition with a generic Material layout, change hierarchy because another structure is easier, or silently reduce visual requirements. Implementation mechanics such as `Row` versus `Flex`, breakpoints, widget decomposition, focus behavior, animation, and state wiring remain implementation choices.

Material deviation requires a concrete accessibility, responsive, platform, production-data, architecture, or measured performance constraint and must be reported explicitly:

```text
Design expected: ...
Implementation differs: ...
Reason: ...
```

## Design source and truthful data

- Record durable design identifiers, approval status/date, and important Human constraints under `docs/design/`; temporary Stitch/Figma exports stay outside Git.
- Inspect structured design evidence and extract its relevant geometry, density, spacing, responsive behavior, player/navigation heights, and artwork ratios before implementation. Derive semantic constraints rather than arbitrary proportional formulas.
- A semantic design slot binds only to its matching capability. Generic or adjacent data must not silently substitute for unavailable data; preserve truthful empty, error, or unavailable states.
- Canonical synthetic fixtures must exercise every already-supported design-critical surface needed for review. Unsupported capabilities remain truthful, and synthetic content never enters production behavior.

## Acceptance and stable product structure

UI product completion requires implementation, responsive behavior, accessibility, automated checks, approved-design comparison, and Human visual acceptance. Rendered output is the visual evidence; constants, assertions, and implementation intent are supporting evidence only.

Before requesting review, inspect canonical desktop and compact renders for required supported surfaces, obvious overflow/clipping, perceptible intended changes, and comparability with the approved design. Do not self-approve aesthetics.

Work one approved page at a time. Do not begin an adjacent page while the current page awaits Human visual acceptance. Preserve accepted shared Shell geometry and behavior—including Sidebar, Top Bar, persistent desktop Player, mobile Mini Player, Bottom Navigation, and primary navigation—unless the Human requests a change or a concrete accessibility, responsive, platform, or correctness defect proves it necessary.

## Execution-mode interpretation

### UI + AUTONOMOUS_DEVELOPMENT

The Agent may implement and machine-verify an approved visual task, but aesthetics remain Human-gated. The loop ends at a canonical candidate:

```text
implement -> targeted verification -> render -> HUMAN_REVIEW
```

Do not autonomously correct the render, accept it, or begin another page.

### UI + HUMAN_GATED_REGRESSION

Assume accepted visual structure is stable. Regression work may address only reproduced overflow/clipping, broken responsive behavior, incorrect visual state, a missing supported surface, wrong semantic data binding, interaction/focus/keyboard failures, or exact Human-reported visual differences.

- For **M** defects: reproduce, make the smallest correction, and run targeted verification.
- For **H** differences: render actual evidence, batch small findings where practical, stop for Human review, then apply only the exact requested correction and render again.
- For **D** questions: stop the affected scope and request the exact product decision.

Do not reopen an entire page or accepted shared Shell area because one local defect exists.

## Material 3 and implementation discipline

Local `agy` is a read-only Material Design 3, visual, and interaction-risk reviewer, not the product designer. Human-approved structure and behavior take precedence over its preferences. The implementing Agent (GPT) remains the sole production-code writer: `agy` must not edit production files, goldens, test assertions, or Git state. Protocol truth, Queue correctness, and pagination semantics require their own Core evidence and cannot be accepted from visual review.

Prefer page-specific widgets and small semantic components. Share only after real pages demonstrate the same semantic grammar. Do not create a generic visual framework, dashboard runtime, UI DSL, design renderer, autonomous visual scorer, or new test framework.

If an approved page needs a genuine missing Core capability, define a bounded Core subtask, verify it under the Core guide, and return to the unchanged UI task. Do not fake data, delete the section, change its semantic meaning, or redesign backend architecture.

## `agy` component preflight and rendered review

For a new interaction component or a substantive change to an existing interaction component, use this bounded sequence:

```text
component preflight -> Agent implementation and tests
-> rendered component review -> integrated-page review -> HUMAN_REVIEW
```

Consult on a complete user-interaction component, such as a theme selector, expanded color card, compact player capsule, or Hero carousel. Do not consult separately for every primitive `Widget`. Preflight each new or materially changed interaction pattern once. An accepted instance of the same pattern may reuse its short recorded constraints without another consultation.

Re-review the affected scope when behavior or responsive structure changes, a shared theme changes, new localization changes component dimensions, or text-scale or hit-target policy changes. Work on only the currently approved page; do not modify several pages concurrently while waiting for review.

### Real local consultation and read-only boundary

Run the locally installed `agy` from an interactive terminal in the project directory and interact with its TUI. A successful launch or welcome screen is not a completed consultation; the implementing Agent must read the substantive response.

On first actual use, establish from the installed version rather than assumptions:

- the active CLI version and model;
- the available help and permission controls;
- how that version reads source files and images.

Use the locally configured, authorized model. Do not silently change the model or global settings, guess flags or TUI shortcuts, or automatically approve login, payment, expanded permissions, or dangerous commands. Restrict production-file writes during review. If that cannot be done reliably, prepare a read-only snapshot containing only the required material. Never allow two models to modify the same working tree.

Provide only necessary, redacted code and synthetic-data renders. Never expose credentials, cookies, real-account private responses, expiring media URLs, or unrelated files.

### Independent preflight packet

Give every component preflight a small, self-contained packet that does not depend on `agy` remembering a long prior conversation. Do not send the whole repository, complete chat history, or unrelated multi-page reports. Include:

- component name, review stage, current revision, and the relevant commit or scoped working-diff identifier;
- the Human's original requirement and immutable constraints;
- component reference images and a contextual image of the containing page;
- current SDK, language, theme, relevant viewport widths, and text scales;
- only the necessary component and theme code excerpts;
- relevant primary, secondary, disabled, loading, hover, focus, selected, and other material states;
- the behavior and visual risks that must be checked.

Ask `agy` to report:

1. which supplied materials it actually read and which it did not;
2. which standard component should be used or retained, and why;
3. the smallest component or theme adjustments it recommends;
4. interaction, responsive, and accessibility constraints that must remain intact;
5. the easiest failure cases to miss;
6. what it still cannot determine.

It may provide a short implementation sketch, but must not produce or apply a page-wide production patch. A structural change without Human approval is not implementation authority.

### Agent implementation

Check every recommendation against the current SDK, source, approved reference, and Human requirement before adopting it. Do not copy a suggestion merely because `agy` made it. Record conflicts with the approved requirement; if resolution requires a product or visual decision, classify it as Human-owned instead of choosing a new design.

Retain or add behavior tests for real user actions. Correct component class, absence of framework exceptions, or a higher test count does not prove the intended behavior. Existing regression assertions must not be weakened. Reusing a standard Material component does not automatically establish acceptable final appearance.

### Rendered component review

After implementation, give `agy` actual renders, not only code or a completion claim. Select evidence according to the component's risks, including as applicable:

- normal, long-copy, and enlarged-text states using the actual application font;
- open, closed, hover, focus, disabled, loading, and selected states;
- relevant desktop and compact dimensions;
- a recording or clearly labelled time sequence for motion;
- the behavior tests that ran and their exact proof boundary.

Confirm which images `agy` actually read. If it did not see an image, the result is code review only. Static images cannot prove animation, hit testing, or a complete state machine. Every render must identify the code snapshot it represents; for an uncommitted tree, record the current `HEAD` and a scoped diff identifier so an old image cannot be used to approve new code.

The review conclusion must map each requirement to a location, state, and piece of evidence. Generic approval such as "conforms to MD3", "looks good", or a score is insufficient.

### Integrated-page review and finding ownership

When the currently approved page is integrated, start a separate fresh review session. Initially provide the original requirement, approved reference, real current-page screenshots, key state evidence, a short summary of accepted component constraints, and necessary runtime conditions. Do not prime the review with a statement that implementation is already complete.

The page review checks component alignment and density, hierarchy, shared-style consistency, menu and overlay occlusion, avoidance between player and navigation surfaces, and responsive transitions. Classify findings under the repository's existing ownership model:

- **M:** reproduce the error, then make and re-verify the smallest correction inside the approved scope;
- **H:** send aesthetic or layout preference to the Human instead of autonomously redesigning;
- **D:** pause only the affected scope for the new product or capability decision.

An unblocked `agy` conclusion is not Human acceptance. A suggestion without supporting material is pending verification, not a defect. By default, perform one preflight and one rendered review per component; use another consultation only for a concrete finding. Do not loop indefinitely, and apply the repository rule to stop and report after three materially similar failures.

### Review records and unavailable tooling

Persist only durable component constraints, the adopted approach, important deviations, and Human acceptance status. Keep complete transcripts, screenshots, recordings, and temporary logs in a temporary review directory referenced accurately by the completion report; do not commit fonts or bulk review artifacts.

Record the real `agy` invocation, active model, supplied review material, and returned findings. The implementing Agent must not fabricate a "Gemini review passed" summary in place of a tool response.

If `agy` cannot start, cannot read an image, has insufficient quota, or the interaction fails:

- record the blocked stage and exact error;
- do not fabricate review or substitute another model without Human direction;
- continue only already-authorized machine-verifiable implementation and tests;
- leave visual review incomplete for the Human to decide.

## Validation

Before Human visual acceptance, normally format affected Dart files, run `dart analyze`, run targeted Widget/controller/adaptive/accessibility tests, and render/inspect canonical desktop and compact screenshots. Broader checks are required only when the changed shared layer could regress the behavior they prove.

After explicit Human visual acceptance, run the applicable full Flutter gate once before an accepted-page checkpoint or final accepted commit:

```bash
cd apps/flutter
dart format --output=none --set-exit-if-changed lib test integration_test
dart analyze
flutter test
flutter build linux
flutter test integration_test/simple_test.dart -d linux
flutter test integration_test/secure_storage_test.dart -d linux
flutter test integration_test/settings_storage_test.dart -d linux
flutter test integration_test/playback_engine_test.dart -d linux
flutter test integration_test/music_video_engine_test.dart -d linux
```

Run only applicable integration targets. Mixed Core/Bridge work follows the Core guide for that bounded subtask. Human acceptance changes when expensive validation runs, not the correctness requirement.
