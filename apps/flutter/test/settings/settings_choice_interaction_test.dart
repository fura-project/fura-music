import 'dart:async';
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_controller.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';

import 'settings_review_harness.dart';

void main() {
  testWidgets(
    'current menu and inline radio have labelled selected semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(const SettingsReviewHarness());
        await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
        await tester.pumpAndSettle();
        final current = tester
            .getSemantics(find.byKey(const ValueKey('settings-theme-system')))
            .getSemanticsData();
        expect(current.label, contains('System'));
        expect(current.flagsCollection.isSelected, Tristate.isTrue);
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('settings-theme-light')))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isFalse,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        final color = find.byKey(
          const ValueKey('settings-color-source-selector'),
        );
        expect(
          tester.getSemantics(color).flagsCollection.isExpanded,
          Tristate.isFalse,
        );
        await tester.tap(color);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(color).flagsCollection.isExpanded,
          Tristate.isTrue,
        );
        for (final (key, label, checked) in [
          (
            'settings-color-source-system',
            'System colors (Monet)',
            CheckedState.isFalse,
          ),
          (
            'settings-color-source-brand',
            'Brand impression',
            CheckedState.isTrue,
          ),
        ]) {
          final option = tester
              .getSemantics(
                find.descendant(
                  of: find.byKey(ValueKey(key)),
                  matching: find.byType(Radio<AppColorSourcePreference>),
                ),
              )
              .getSemanticsData();
          expect(option.label, contains(label));
          expect(option.flagsCollection.isChecked, checked);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final width in [320.0, 390.0, 1180.0]) {
    testWidgets('short choices use anchored menus at $width', (tester) async {
      setSettingsViewport(tester, Size(width, 844));
      final semantics = tester.ensureSemantics();
      for (final (section, selectors) in settingsChoiceSelectors) {
        await tester.pumpWidget(
          SettingsReviewHarness(key: ValueKey(section), section: section),
        );
        await tester.pumpAndSettle();
        for (final (key, optionKey) in selectors) {
          if (key == 'settings-color-source-selector') continue;
          final row = find.byKey(ValueKey(key));
          await tester.ensureVisible(row);
          final oldValue = tester
              .widget<Text>(find.byKey(ValueKey('$key-current')))
              .data;
          final group = tester.getSize(
            find.byKey(const ValueKey('settings-group')),
          );
          final anchor = tester.widget<MenuAnchor>(
            find.ancestor(of: row, matching: find.byType(MenuAnchor)).first,
          );
          expect(tester.getSemantics(row).label, contains(oldValue));
          await tester.tapAt(
            tester.getTopRight(row) +
                Offset(-12, tester.getSize(row).height / 2),
          );
          await tester.pumpAndSettle();
          expect(anchor.controller!.isOpen, isTrue);
          expect(find.byType(BottomSheet), findsNothing);
          expect(
            find.byWidgetPredicate((w) => w is DropdownMenu),
            findsNothing,
          );
          expect(find.byType(TextField), findsNothing);
          expect(
            tester.getSize(find.byKey(const ValueKey('settings-group'))),
            group,
          );
          final option = find.byKey(ValueKey(optionKey));
          await tester.ensureVisible(option);
          expect(tester.getSize(option).height, greaterThanOrEqualTo(48));
          await tester.tap(option);
          await tester.pumpAndSettle();
          expect(anchor.controller!.isOpen, isFalse);
          expect(
            tester.widget<Text>(find.byKey(ValueKey('$key-current'))).data,
            isNot(oldValue),
          );
          expect(tester.takeException(), isNull);
        }
      }
      semantics.dispose();
    });
  }

  for (final succeeds in [true, false]) {
    testWidgets(
      'short selection saves once and reconciles persistence=$succeeds',
      (tester) async {
        final storage = _PendingStorage();
        final owner = AppSettingsController(
          AppSettingsStore(storage: storage),
          null,
          initialSettings: AppSettings.defaults,
        );
        addTearDown(owner.dispose);
        await tester.pumpWidget(SettingsReviewHarness(owner: owner));
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('settings-theme-selector'));
        await tester.tap(row);
        await tester.pumpAndSettle();
        final current = tester.widget<MenuItemButton>(
          find.byKey(const ValueKey('settings-theme-system')),
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('settings-theme-system')),
            matching: find.byIcon(Icons.check),
          ),
          findsOneWidget,
        );
        expect(current.onPressed, isNotNull);
        await tester.tap(find.byKey(const ValueKey('settings-theme-light')));
        // Pending storage intentionally keeps the saving indicator animating.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(owner.settings.theme, AppThemePreference.light);
        expect(storage.writes, 1);
        expect(settingsRowInk(tester, row).onTap, isNull);
        if (succeeds) {
          storage.completion.complete();
        } else {
          storage.completion.completeError(
            StateError('synthetic write failure'),
          );
        }
        await tester.pumpAndSettle();
        expect(
          owner.settings.theme,
          succeeds ? AppThemePreference.light : AppThemePreference.system,
        );
        expect(settingsRowInk(tester, row).onTap, isNotNull);
        expect(settingsRowInk(tester, row).focusNode!.hasFocus, isTrue);
        expect(find.byType(SnackBar), succeeds ? findsNothing : findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final dismiss in ['escape', 'back', 'outside', 'current']) {
    testWidgets('popup $dismiss dismisses without write and returns focus', (
      tester,
    ) async {
      var writes = 0;
      await tester.pumpWidget(
        SettingsReviewHarness(
          onChanged: (_) async {
            writes++;
            return AppSettingsWriteResult.saved;
          },
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('settings-theme-selector'));
      await tester.tap(row);
      await tester.pumpAndSettle();
      switch (dismiss) {
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'back':
          await tester.binding.handlePopRoute();
        case 'outside':
          await tester.tapAt(const Offset(8, 8));
        case 'current':
          await tester.tap(find.byKey(const ValueKey('settings-theme-system')));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-theme-light')), findsNothing);
      expect(row, findsOneWidget);
      expect(writes, 0);
      expect(settingsRowInk(tester, row).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'keyboard opens, navigates without preview mutation and selects',
    (tester) async {
      await tester.pumpWidget(const SettingsReviewHarness());
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('settings-theme-selector'));
      final focus = settingsRowInk(tester, row).focusNode!;
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-theme-system')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('settings-theme-selector-current')),
            )
            .data,
        'System',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('settings-theme-selector-current')),
            )
            .data,
        'Light',
      );
      expect(focus.hasFocus, isTrue);
    },
  );
  for (final available in [true, false]) {
    testWidgets(
      'color expands inline and keeps truthful availability=$available',
      (tester) async {
        await tester.pumpWidget(
          SettingsReviewHarness(systemColorsAvailable: available),
        );
        await tester.pumpAndSettle();
        final row = find.byKey(
          const ValueKey('settings-color-source-selector'),
        );
        final route = ModalRoute.of(tester.element(row));
        expect(
          find.byKey(const ValueKey('settings-color-details')),
          findsNothing,
        );
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(ModalRoute.of(tester.element(row)), same(route));
        expect(route!.willHandlePopInternally, isFalse);
        expect(
          find.ancestor(of: row, matching: find.byType(MenuAnchor)),
          findsNothing,
        );
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          find.byKey(
            ValueKey(
              available
                  ? 'settings-system-colors-available'
                  : 'settings-system-colors-unavailable',
            ),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<RadioGroup<AppColorSourcePreference>>(
                find.byType(RadioGroup<AppColorSourcePreference>),
              )
              .groupValue,
          AppColorSourcePreference.brand,
        );
        await tester.tap(
          find.byKey(const ValueKey('settings-color-source-system')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<RadioGroup<AppColorSourcePreference>>(
                find.byType(RadioGroup<AppColorSourcePreference>),
              )
              .groupValue,
          AppColorSourcePreference.system,
        );
        expect(
          find.byKey(const ValueKey('settings-color-details')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('settings-color-palette-preview')),
          findsOneWidget,
        );
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-color-details')),
          findsNothing,
        );
      },
    );
  }
}

class _PendingStorage implements AppSettingsDocumentStorage {
  final completion = Completer<void>();
  int writes = 0;
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String document) {
    writes++;
    return completion.future;
  }

  @override
  Future<void> delete() async {}
}
