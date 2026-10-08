import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/settings_choice_presentation.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';

import 'settings_review_harness.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'active Settings text contrast uses actual M3 roles $brightness',
      (tester) async {
        await tester.pumpWidget(SettingsReviewHarness(brightness: brightness));
        final availability = find.byKey(
          const ValueKey('settings-system-colors-available'),
        );
        final theme = Theme.of(tester.element(availability));
        final foreground = tester.widget<Text>(availability).style!.color!;
        final group = tester
            .widget<Material>(find.byKey(const ValueKey('settings-group')))
            .color!;
        double contrast(Color a, Color b) {
          final first = a.computeLuminance();
          final second = b.computeLuminance();
          return (first > second
              ? (first + .05) / (second + .05)
              : (second + .05) / (first + .05));
        }

        expect(contrast(foreground, group), greaterThanOrEqualTo(4.5));
        expect(
          contrast(
            theme.colorScheme.onSecondaryContainer,
            theme.colorScheme.secondaryContainer,
          ),
          greaterThanOrEqualTo(4.5),
        );
        await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
        await tester.pumpAndSettle();
        expect(
          contrast(
            theme.colorScheme.onSurface,
            theme.bottomSheetTheme.modalBackgroundColor!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        // Background content under the modal scrim is deliberately inactive.
        // Palette swatches are decorative real colors, not text/active controls.
      },
    );
  }
  testWidgets('choice result waits for actual outgoing route removal', (
    tester,
  ) async {
    await tester.pumpWidget(const SettingsReviewHarness());
    final context = tester.element(
      find.byKey(const ValueKey('settings-theme-selector')),
    );
    final pending = showSettingsSingleChoice(
      context: context,
      title: 'Synthetic',
      options: const [SettingsChoiceOption(label: 'One')],
      selectedIndex: 0,
    );
    var settled = false;
    pending.result.then((_) => settled = true);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pump();
    expect(settled, isFalse);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.pumpAndSettle();
    expect(settled, isTrue);
    expect(find.byType(BottomSheet), findsNothing);
  });
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
      // Present the save owner's rebuild after the outgoing route completes.
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      for (final (rowKey, _) in selectors) {
        final row = settingsRowInk(tester, find.byKey(ValueKey(rowKey)));
        if (rowKey == 'settings-color-source-selector') {
          expect(
            tester
                .widget<DropdownMenu>(
                  find.byWidgetPredicate((w) => w is DropdownMenu),
                )
                .enabled,
            isFalse,
          );
        } else {
          expect(row.onTap, isNull);
        }
      }
      save.complete(AppSettingsWriteResult.saved);
      await tester.pumpAndSettle();
      for (final (rowKey, _) in selectors) {
        if (rowKey == 'settings-color-source-selector') {
          expect(
            tester
                .widget<DropdownMenu>(
                  find.byWidgetPredicate((w) => w is DropdownMenu),
                )
                .enabled,
            isTrue,
          );
        } else {
          expect(
            settingsRowInk(tester, find.byKey(ValueKey(rowKey))).onTap,
            isNotNull,
          );
        }
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
        expect(find.byType(Radio<int>), findsNWidgets(3));
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
