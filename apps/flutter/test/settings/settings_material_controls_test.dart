import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';

import 'settings_review_harness.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('group, details and menu use truthful M3 roles $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(SettingsReviewHarness(brightness: brightness));
      await tester.tap(
        find.byKey(const ValueKey('settings-color-source-selector')),
      );
      await tester.pumpAndSettle();
      final availability = find.byKey(
        const ValueKey('settings-system-colors-available'),
      );
      final theme = Theme.of(tester.element(availability));
      final foreground = tester.widget<Text>(availability).style!.color!;
      final group = tester
          .widget<Material>(find.byKey(const ValueKey('settings-group')))
          .color!;
      double contrast(Color a, Color b) {
        final first = a.computeLuminance(), second = b.computeLuminance();
        return first > second
            ? (first + .05) / (second + .05)
            : (second + .05) / (first + .05);
      }

      expect(contrast(foreground, group), greaterThanOrEqualTo(4.5));
      expect(find.byType(RadioListTile), findsNothing);
      expect(find.byWidgetPredicate((w) => w is DropdownMenu), findsNothing);
      expect(find.byWidgetPredicate((w) => w is DropdownButton), findsNothing);
      expect(find.byType(Card), findsNothing);
      await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(3));
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        contrast(
          theme.colorScheme.onSurface,
          theme.colorScheme.surfaceContainer,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
  testWidgets('saving disables every settings row and inline radio', (
    tester,
  ) async {
    for (final (section, selectors) in settingsChoiceSelectors) {
      final save = Completer<AppSettingsWriteResult>();
      await tester.pumpWidget(
        SettingsReviewHarness(
          key: ValueKey(section),
          section: section,
          onChanged: (_) => save.future,
        ),
      );
      await tester.pumpAndSettle();
      final (key, option) = selectors.first;
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(option)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      for (final (rowKey, _) in selectors) {
        expect(
          settingsRowInk(tester, find.byKey(ValueKey(rowKey))).onTap,
          isNull,
        );
      }
      save.complete(AppSettingsWriteResult.saved);
      await tester.pumpAndSettle();
      for (final (rowKey, _) in selectors) {
        expect(
          settingsRowInk(tester, find.byKey(ValueKey(rowKey))).onTap,
          isNotNull,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('palette is compact and uses the actual effective ColorScheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      const SettingsReviewHarness(brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('settings-color-source-selector')),
    );
    await tester.pumpAndSettle();
    final palette = find.byKey(
      const ValueKey('settings-color-palette-preview'),
    );
    final scheme = Theme.of(tester.element(palette)).colorScheme;
    final dots = tester
        .widgetList<Container>(
          find.descendant(of: palette, matching: find.byType(Container)),
        )
        .toList();
    expect(dots, hasLength(5));
    expect(dots.map((dot) => (dot.decoration! as BoxDecoration).color), [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.primaryContainer,
      scheme.surfaceContainerHighest,
    ]);
    expect(tester.getSize(palette).height, 20);
    for (final material in tester.widgetList<Material>(
      find.byKey(const ValueKey('settings-group')),
    )) {
      expect(material.color, scheme.surfaceContainerLow);
      expect(material.borderRadius, BorderRadius.circular(16));
    }
    expect(find.byType(ExpansionTile), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
