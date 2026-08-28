# UI / Product Development Mode

Use this mode for Flutter page composition, visual hierarchy, layout, adaptive behavior, Material 3 presentation, spacing, typography, surfaces, visual states, desktop/mobile translation, and implementation of approved Stitch/Figma designs.

The shared rules in [`AGENTS.md`](../../AGENTS.md) always apply.

## Authority model

```text
Human or approved design defines visual WHAT and visual HOW.
Codex decides implementation HOW.
```

Use this visual authority order:

1. Human product decision;
2. latest Human-approved Stitch/Figma frame;
3. explicit Human annotation or `DESIGN_SPEC`;
4. approved reference screenshot;
5. Material Design 3 rules;
6. existing implementation;
7. Codex visual preference.

A Human-approved Stitch/Figma frame, MCP design, annotated screenshot, or explicit visual specification is executable UI provenance. Do not downgrade it because it is aesthetic. Codex's aesthetic preference is the lowest authority.

## Faithful implementation

When an approved design exists, do not redesign its composition, replace it with a generic Material layout, change hierarchy because another structure is easier, invent another style, reinterpret page proportions, or silently reduce visual requirements. Codex may choose implementation details such as `Row` versus `Flex`, `LayoutBuilder`, semantic breakpoints, widget decomposition, focus behavior, animation mechanics, and state wiring.

Material deviation is allowed only for a concrete accessibility, responsive, platform, production-data, architecture, or measured performance constraint. Report every material deviation explicitly:

```text
Design expected: ...
Implementation differs: ...
Reason: ...
```

Visual authority never overrides security, truthful Provider/Domain semantics, Flutter/Rust ownership, or Provider isolation.

## Design-source discipline

- Record durable Project/Screen identifiers, approval status/date, and important Human constraints under `docs/design/`.
- Stitch/Figma PNG or HTML exports may remain temporary under `/tmp`; do not commit generated exports merely for permanence.
- Before implementation, inspect structured MCP/HTML design and extract at least Sidebar width, Top Bar and persistent-player heights, content maximum width and padding, section spacing, Hero and card geometry, artwork ratio, Track-row height, responsive breakpoints, mobile Mini Player height, and Bottom Navigation height.
- Derive semantic layout constraints from the design. Do not invent arbitrary proportional formulas unless the design demonstrates fluid proportional behavior.

## Visual truth

Production UI uses truthful Provider results, Domain state, account data, recommendation semantics, and availability behavior. A design slot with specific product semantics binds to that exact capability: changing its label does not change its meaning, and adjacent or generic data must not silently substitute for it. When matching data is unavailable, preserve the slot's honest empty, error, or unavailable state.

Canonical visual-review fixtures should use clearly synthetic, semantically matching content to exercise every already-supported, design-critical surface needed to judge the approved composition. A screenshot that omits such a surface is incomplete visual evidence. Unsupported capabilities remain explicitly unavailable, and synthetic fixtures never authorize fabricated production recommendations, account content, or behavior.

## Acceptance model

UI Product completion requires all of:

```text
Flutter implementation
responsive behavior
accessibility
automated tests
approved-design comparison
Human visual acceptance
```

Automated tests alone do not establish visual completion. Compare approved design and actual Flutter output concretely: Sidebar and player geometry, content origin, Hero ratio, card dimensions, shelf density, section spacing, typography scale, mobile navigation, light/dark state, and responsive behavior—not merely “approximately similar.”

Rendered output is the visual evidence; implementation intent, numeric constants, test assertions, and the agent's prose are supporting evidence only. Before requesting Human visual acceptance, inspect the canonical Desktop and Mobile renders and confirm that required supported surfaces are visible, obvious overflow or clipping is absent, the intended change is perceptible, and the output can actually be compared with the approved design. Do not self-approve aesthetic quality.

Work one page at a time. The current accepted sequence and active page are recorded in `ROADMAP.md` and `PROGRESS.md`. Do not begin the next page until the maintainer accepts the current page. This is a local UI gate, not permission to redefine the project's global execution state.

After a shared Shell surface receives explicit Human visual acceptance, preserve its accepted user-visible geometry and behavior on later pages. Do not materially redesign the Sidebar, Top Bar, persistent desktop Player, mobile Mini Player, Bottom Navigation, or shared primary-navigation composition unless a newly approved design requires it or a concrete accessibility, responsive, platform, or correctness defect proves a correction is needed. This stabilizes the product frame without freezing implementation internals.

## Material 3 review and refactoring

Local `agy` is a Material Design 3 QA reviewer, not the product designer. Ask it only about surface hierarchy, `ColorScheme`, typography, state layers, focus/hover/selected treatment, component appropriateness, shape consistency, and Material authenticity. The approved composition remains fixed.

Prefer page-specific widgets and small semantic components. Share a component only after two real pages demonstrate the same semantic grammar. Do not create a generic dashboard runtime, UI DSL, design renderer, or speculative design infrastructure.

For new M7 page-specific regressions, prefer an existing page- or domain-specific test location when one naturally exists instead of continuously expanding a monolithic test file. Do not split the existing suite solely for this preference or introduce a new test framework.

## Mixed work

When an approved page needs a genuine missing Core capability:

```text
identify the exact blocker -> switch to a bounded Core subtask
-> implement and verify under Core rules -> return to the approved UI task
```

Do not fake production data, delete the section, silently alter the design, or redesign backend architecture from the UI task.

## Validation

Use two validation stages so a visually rejectable candidate reaches Human review quickly without weakening accepted-page correctness.

### Visual iteration

Before Human visual acceptance, normally:

- format affected Dart files;
- run `dart analyze`;
- run targeted Widget/controller/adaptive/accessibility tests for the changed surface;
- render and inspect the canonical Desktop and Mobile screenshots.

The loop is:

```text
implement -> targeted verification -> render -> Human visual review
```

Do not routinely run the entire Flutter suite, Linux release packaging, unrelated integration targets, or Rust workspace tests for every visual correction. Run a broader check at this stage only when the changed layer or shared component could regress the behavior that check proves. Mixed Core/Bridge changes follow the Core guide for that bounded subtask. If a candidate is rejected visually, iterate from the rendered result without first running an unrelated release gate. Do not create an autonomous visual-correction loop.

### Accepted-page validation

After the maintainer explicitly accepts the page visually, run the full applicable Flutter gate once before the accepted-page checkpoint or final accepted commit:

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

Use `dart analyze`, not `flutter analyze`, for this checkout as explained in `AGENTS.md` and `MEMORY.md`. Run a specific integration target only when the accepted change touches or could regress the behavior it proves; unrelated platform integration is not required as ceremony. Human visual acceptance changes when expensive validation runs, not the correctness requirement. Validation establishes implementation behavior and accessibility boundaries; the approved-design comparison and Human review establish visual acceptance.
