import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_controller.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';

import 'settings_review_harness.dart';

void main() {
  for (final width in [320.0, 390.0, 1180.0]) {
    testWidgets('simple choices use the same bottom sheet at $width', (
      tester,
    ) async {
      setSettingsViewport(tester, Size(width, 844));
      final semantics = tester.ensureSemantics();
      for (final (section, selectors) in settingsChoiceSelectors) {
        await tester.pumpWidget(SettingsReviewHarness(section: section));
        await tester.pumpAndSettle();
        expect(find.byType(ExpansionTile), findsNothing);
        expect(find.byType(DropdownButton), findsNothing);
        for (final (selectorKey, optionKey) in selectors) {
          if (selectorKey == 'settings-color-source-selector') continue;
          final selector = find.byKey(ValueKey(selectorKey));
          await tester.ensureVisible(selector);
          expect(tester.getSize(selector).height, greaterThanOrEqualTo(48));
          final tile = settingsRowInk(tester, selector);
          final previousValue = tester
              .widget<Text>(find.byKey(ValueKey('$selectorKey-current')))
              .data;
          expect(tile.onTap, isNotNull);
          expect(find.byKey(ValueKey('$selectorKey-current')), findsOneWidget);
          expect(
            tester.getSemantics(selector).label,
            contains(
              tester
                  .widget<Text>(
                    find
                        .descendant(of: selector, matching: find.byType(Text))
                        .first,
                  )
                  .data,
            ),
          );
          expect(tester.getSemantics(selector).label, contains(previousValue));
          await tester.tapAt(
            tester.getTopRight(selector) +
                Offset(-12, tester.getSize(selector).height / 2),
          );
          await tester.pumpAndSettle();
          final sheet = find.byType(BottomSheet);
          expect(sheet, findsOneWidget);
          expect(tester.getBottomLeft(sheet).dy, closeTo(844, 1));
          expect(
            tester
                .getSize(find.byKey(const ValueKey('settings-choice-sheet')))
                .width,
            width,
          );
          expect(find.byType(AlertDialog), findsNothing);
          final option = find.byKey(ValueKey(optionKey));
          await tester.ensureVisible(option);
          expect(option, findsOneWidget);
          expect(tester.getSize(option).height, greaterThanOrEqualTo(48));
          await tester.tap(option);
          await tester.pumpAndSettle();
          expect(sheet, findsNothing);
          expect(
            tester
                .widget<Text>(
                  find
                      .descendant(of: selector, matching: find.byType(Text))
                      .last,
                )
                .data,
            isNot(previousValue),
          );
          expect(tester.takeException(), isNull);
        }
      }
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  for (final succeeds in [true, false]) {
    testWidgets('theme applies once and reconciles persistence=$succeeds', (
      tester,
    ) async {
      setSettingsViewport(tester, const Size(390, 844));
      final semantics = tester.ensureSemantics();
      final storage = _PendingStorage();
      final owner = AppSettingsController(
        AppSettingsStore(storage: storage),
        null,
        initialSettings: AppSettings.defaults,
      );
      addTearDown(owner.dispose);
      await tester.pumpWidget(SettingsReviewHarness(owner: owner));
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('settings-theme-selector'));
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(
        tester.widget<RadioGroup<int>>(find.byType(RadioGroup<int>)).groupValue,
        0,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('settings-theme-system')))
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('settings-theme-light')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Route.completed settles after overlay removal; render the saving state
      // scheduled by the result owner on the following frame.
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      expect(owner.settings.theme, AppThemePreference.light);
      expect(storage.writes, 1);
      expect(settingsRowInk(tester, selector).onTap, isNull);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('settings-theme-selector-current')),
            )
            .data,
        'Light',
      );
      if (succeeds) {
        storage.completion.complete();
      } else {
        storage.completion.completeError(StateError('synthetic write failure'));
      }
      await tester.pumpAndSettle();
      expect(
        owner.settings.theme,
        succeeds ? AppThemePreference.light : AppThemePreference.system,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('settings-theme-selector-current')),
            )
            .data,
        succeeds ? 'Light' : 'System',
      );
      expect(settingsRowInk(tester, selector).onTap, isNotNull);
      expect(settingsRowInk(tester, selector).focusNode!.hasFocus, isTrue);
      expect(find.byType(SnackBar), succeeds ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('keyboard opens row, selects radio and restores focus', (
    tester,
  ) async {
    await tester.pumpWidget(const SettingsReviewHarness());
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('settings-theme-selector'));
    final focus = settingsRowInk(tester, selector).focusNode!;
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('settings-theme-selector-current')),
          )
          .data,
      'Light',
    );
    expect(focus.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('sheet options respect real system safe-area insets', (
    tester,
  ) async {
    setSettingsViewport(tester, const Size(390, 844));
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(const SettingsReviewHarness(scale: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
    await tester.pumpAndSettle();
    final lastOption = find.byKey(const ValueKey('settings-theme-dark'));
    await tester.ensureVisible(lastOption);
    expect(tester.getTopLeft(lastOption).dy, greaterThanOrEqualTo(24));
    expect(tester.getBottomLeft(lastOption).dy, lessThanOrEqualTo(810));
    await tester.tap(lastOption);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('disposed choice caller cannot apply a late sheet selection', (
    tester,
  ) async {
    var writes = 0;
    Future<AppSettingsWriteResult> save(AppSettings _) async {
      writes++;
      return AppSettingsWriteResult.saved;
    }

    await tester.pumpWidget(SettingsReviewHarness(onChanged: save));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      SettingsReviewHarness(onChanged: save, showPage: false),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-theme-selector')), findsNothing);
    // The disposed caller cancels only its own modal route.
    expect(find.byType(BottomSheet), findsNothing);
    expect(writes, 0);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final dismiss in ['escape', 'back', 'scrim', 'current']) {
    testWidgets('$dismiss dismisses without a settings write', (tester) async {
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
      final selector = find.byKey(const ValueKey('settings-theme-selector'));
      await tester.tap(selector);
      await tester.pumpAndSettle();
      switch (dismiss) {
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'back':
          await tester.binding.handlePopRoute();
        case 'scrim':
          await tester.tapAt(const Offset(8, 8));
        case 'current':
          await tester.tap(find.byKey(const ValueKey('settings-theme-system')));
      }
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(writes, 0);
      expect(settingsRowInk(tester, selector).focusNode!.hasFocus, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  for (final available in [true, false]) {
    testWidgets('official color dropdown preserves availability=$available', (
      tester,
    ) async {
      await tester.pumpWidget(
        SettingsReviewHarness(systemColorsAvailable: available),
      );
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownMenu<AppColorSourcePreference>);
      expect(
        tester
            .widget<DropdownMenu<AppColorSourcePreference>>(dropdown)
            .initialSelection,
        AppColorSourcePreference.brand,
      );
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
      expect(find.byType(RadioGroup<AppColorSourcePreference>), findsNothing);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(const ValueKey('settings-color-source-system'))
            .hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownMenu<AppColorSourcePreference>>(dropdown)
            .initialSelection,
        AppColorSourcePreference.system,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
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
