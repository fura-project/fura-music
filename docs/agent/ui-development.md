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

Local `agy` is a Material Design 3 QA reviewer, not the product designer. Use it only for Material surface, color, typography, state, focus/hover/selected, component, and shape questions; approved composition remains fixed.

Prefer page-specific widgets and small semantic components. Share only after real pages demonstrate the same semantic grammar. Do not create a generic visual framework, dashboard runtime, UI DSL, design renderer, autonomous visual scorer, or new test framework.

If an approved page needs a genuine missing Core capability, define a bounded Core subtask, verify it under the Core guide, and return to the unchanged UI task. Do not fake data, delete the section, change its semantic meaning, or redesign backend architecture.

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
