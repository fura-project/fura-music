import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/settings_choice_presentation.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';

import 'settings_review_harness.dart';

void main() {
  testWidgets(
    'fallback cancelled before first build cannot leave an orphan route',
    (tester) async {
      await tester.pumpWidget(const SettingsReviewHarness());
      final context = tester.element(
        find.byKey(const ValueKey('settings-theme-selector')),
      );
      final pending = showSettingsSingleChoice(
        context: context,
        title: 'Synthetic choice',
        options: const [SettingsChoiceOption(label: 'One')],
        selectedIndex: 0,
      );
      pending.cancel();
      await tester.pumpAndSettle();
      expect(await pending.result, isNull);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets('saving disables every real enum row, not just theme', (
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
      expect(find.byType(BottomSheet), findsNothing);
      for (final (rowKey, _) in selectors) {
        final row = tester.widget<ListTile>(find.byKey(ValueKey(rowKey)));
        expect(row.enabled, isFalse);
        expect(row.onTap, isNull);
      }
      save.complete(AppSettingsWriteResult.saved);
      await tester.pumpAndSettle();
      for (final (rowKey, _) in selectors) {
        expect(
          tester.widget<ListTile>(find.byKey(ValueKey(rowKey))).enabled,
          isTrue,
        );
      }
      expect(tester.takeException(), isNull);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'standard sheet owns real route motion reduced=$reducedMotion',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reducedMotion);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(const SettingsReviewHarness());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
        await tester.pump();
        final sheet = find.byType(BottomSheet);
        final sheetContext = tester.element(sheet);
        final route = ModalRoute.of(sheetContext)! as ModalBottomSheetRoute;
        final before = route.animation!.value;
        await tester.pump(const Duration(milliseconds: 100));
        if (reducedMotion) {
          expect(route.animation!.value, 1);
        } else {
          expect(route.animation!.value, greaterThan(before));
        }
        await tester.pumpAndSettle();
        expect(route.animation!.value, 1);
        expect(tester.widget<BottomSheet>(sheet).showDragHandle, isTrue);
        expect(route.useSafeArea, isTrue);
        expect(route.isScrollControlled, isTrue);
        expect(find.byType(RadioListTile<int>), findsNWidgets(3));
        // Stock modal route handles motion. No outer animation framework.
        await tester.tapAt(const Offset(8, 8));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
      },

      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

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
