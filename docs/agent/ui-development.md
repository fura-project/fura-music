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

## Truthful production and complete fixtures

Production UI uses truthful Provider results, Domain state, account data, recommendation semantics, and availability behavior. When data is unavailable, show an honest empty, error, or unavailable state.

Widgetbook, visual fixtures, and design previews may use clearly synthetic content such as `Example Playlist` or `Synthetic Track` so all intended states can be reviewed. Synthetic fixtures never authorize fabricated production recommendations or account content.

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

Work one page at a time. The current accepted sequence and active page are recorded in `ROADMAP.md` and `PROGRESS.md`. Do not begin the next page until the maintainer accepts the current page. This is a local UI gate, not permission to redefine the project's global execution state.

## Material 3 review and refactoring

Local `agy` is a Material Design 3 QA reviewer, not the product designer. Ask it only about surface hierarchy, `ColorScheme`, typography, state layers, focus/hover/selected treatment, component appropriateness, shape consistency, and Material authenticity. The approved composition remains fixed.

Prefer page-specific widgets and small semantic components. Share a component only after two real pages demonstrate the same semantic grammar. Do not create a generic dashboard runtime, UI DSL, design renderer, or speculative design infrastructure.

## Mixed work

When an approved page needs a genuine missing Core capability:

```text
identify the exact blocker -> switch to a bounded Core subtask
-> implement and verify under Core rules -> return to the approved UI task
```

Do not fake production data, delete the section, silently alter the design, or redesign backend architecture from the UI task.

## Validation

Run targeted Widget/controller/adaptive/accessibility tests for every affected surface. The normal full Flutter gate is:

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

Use `dart analyze`, not `flutter analyze`, for this checkout as explained in `AGENTS.md` and `MEMORY.md`. Validation establishes implementation behavior and accessibility boundaries; the approved-design comparison and Human review establish visual acceptance.
