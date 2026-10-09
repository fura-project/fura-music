import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_controller.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/settings/settings_page.dart';

import 'settings_review_harness.dart';

void main() {
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
          if (section == SettingsSection.appearance) continue;
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
        await tester.pumpWidget(
          SettingsReviewHarness(
            section: SettingsSection.language,
            owner: owner,
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('settings-language-selector'));
        await tester.tap(row);
        await tester.pumpAndSettle();
        final current = tester.widget<MenuItemButton>(
          find.byKey(const ValueKey('settings-language-system')),
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('settings-language-system')),
            matching: find.byIcon(Icons.check),
          ),
          findsOneWidget,
        );
        expect(current.onPressed, isNotNull);
        await tester.tap(
          find.byKey(const ValueKey('settings-language-english')),
        );
        // Pending storage intentionally keeps the saving indicator animating.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(owner.settings.localePreference, AppLocalePreference.english);
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
          owner.settings.localePreference,
          succeeds ? AppLocalePreference.english : AppLocalePreference.system,
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
          section: SettingsSection.language,
          onChanged: (_) async {
            writes++;
            return AppSettingsWriteResult.saved;
          },
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('settings-language-selector'));
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
          await tester.tap(
            find.byKey(const ValueKey('settings-language-system')),
          );
      }
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-language-english')),
        findsNothing,
      );
      expect(row, findsOneWidget);
      expect(writes, 0);
      expect(settingsRowInk(tester, row).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'keyboard opens, navigates without preview mutation and selects',
    (tester) async {
      await tester.pumpWidget(
        const SettingsReviewHarness(section: SettingsSection.language),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('settings-language-selector'));
      final focus = settingsRowInk(tester, row).focusNode!;
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-language-system')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('settings-language-selector-current')),
            )
            .data,
        'Follow system',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('settings-language-selector-current')),
            )
            .data,
        'English',
      );
      expect(focus.hasFocus, isTrue);
    },
  );
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
