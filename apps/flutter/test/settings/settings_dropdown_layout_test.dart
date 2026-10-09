import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings.dart';

import 'settings_review_harness.dart';

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('representative controls fit large text at $width', (
      tester,
    ) async {
      setSettingsViewport(tester, Size(width, 900));
      await tester.pumpWidget(
        SettingsReviewHarness(compact: width < 600, language: 'zh', scale: 2),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-group')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
      await tester.pumpAndSettle();
      for (final key in [
        'settings-theme-system',
        'settings-theme-light',
        'settings-theme-dark',
      ]) {
        final option = find.byKey(ValueKey(key));
        await tester.ensureVisible(option);
        expect(option.hitTestable(), findsOneWidget);
        expect(tester.getRect(option).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(option).right, lessThanOrEqualTo(width));
      }
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownMenu<AppColorSourcePreference>);
      await tester.tap(
        find.descendant(of: dropdown, matching: find.byType(TextField)),
      );
      await tester.pumpAndSettle();
      for (final key in [
        'settings-color-source-system',
        'settings-color-source-brand',
      ]) {
        final option = find.byKey(ValueKey(key)).hitTestable();
        expect(option, findsOneWidget);
        expect(tester.getRect(option).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(option).right, lessThanOrEqualTo(width));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
