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
          .widget<Material>(
            find.ancestor(
              of: availability,
              matching: find.byKey(const ValueKey('settings-group')),
            ),
          )
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
      expect(
        tester.widget(find.byKey(const ValueKey('settings-theme-selector'))),
        isA<ListTile>(),
      );
      await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is PopupMenuItem),
        findsNWidgets(3),
      );
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
    final groups = find.byKey(const ValueKey('settings-group'));
    expect(groups, findsNWidgets(2));
    for (final material in tester.widgetList<Material>(groups)) {
      expect(material.color, scheme.surfaceContainerLow);
      expect(material.borderRadius, BorderRadius.circular(16));
    }
    expect(
      tester.getTopLeft(groups.at(1)).dy -
          tester.getBottomLeft(groups.at(0)).dy,
      12,
    );
    final systemCard = find.byKey(
      const ValueKey('settings-color-source-system'),
    );
    final brandCard = find.byKey(const ValueKey('settings-color-source-brand'));
    expect(
      tester.getTopLeft(brandCard).dy - tester.getBottomLeft(systemCard).dy,
      8,
    );
    expect(find.byType(ExpansionTile), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'stacked value pills hug content, retain subtitles, and keep 320px zh titles single-line',
    (tester) async {
      setSettingsViewport(tester, const Size(320, 900));
      await tester.pumpWidget(
        const SettingsReviewHarness(language: 'zh', compact: true),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.text('配色来源')).height, lessThan(30));

      await tester.pumpWidget(
        const SettingsReviewHarness(language: 'zh', scale: 2, compact: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('跟随系统主题'), findsOneWidget);
      final currentText = find.byKey(
        const ValueKey('settings-theme-selector-current'),
      );
      final themePill = find
          .ancestor(of: currentText, matching: find.byType(DecoratedBox))
          .first;
      final themeRow = find.byKey(const ValueKey('settings-theme-selector'));
      expect(
        tester.getSize(themePill).width,
        lessThan(tester.getSize(themeRow).width - 96),
      );

      await tester.tap(themeRow);
      await tester.pumpAndSettle();
      final menuCard = find
          .ancestor(
            of: find.byKey(const ValueKey('settings-theme-light')),
            matching: find.byWidgetPredicate(
              (w) => w is Material && w.type == MaterialType.card,
            ),
          )
          .first;
      expect(
        tester.getTopLeft(menuCard).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(themePill).dy),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
