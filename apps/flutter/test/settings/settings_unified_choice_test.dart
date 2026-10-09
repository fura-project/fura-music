import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_controller.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';

import 'settings_review_harness.dart';

Finder get themeRow => find.byKey(const ValueKey('settings-theme-selector'));
Finder get colorMenu => find.byType(DropdownMenu<AppColorSourcePreference>);
Future<void> openColor(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: colorMenu, matching: find.byType(TextField)),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'official Theme sheet fits $width and retains page base',
      (tester) async {
        setSettingsViewport(tester, Size(width, 900));
        await tester.pumpWidget(SettingsReviewHarness(compact: width < 600));
        final group = tester.getSize(
          find.byKey(const ValueKey('settings-group')),
        );
        await tester.tap(themeRow);
        await tester.pumpAndSettle();
        final sheet = find.byType(BottomSheet);
        final rect = tester.getRect(
          find
              .ancestor(
                of: find.byType(RadioGroup<AppThemePreference>),
                matching: find.byWidgetPredicate(
                  (w) => w is Material && w.type == MaterialType.canvas,
                ),
              )
              .first,
        );
        expect(rect.width, width < 640 ? width : 640);
        expect(rect.bottom, 900);
        expect(rect.height, lessThan(450));
        expect(tester.widget<BottomSheet>(sheet).showDragHandle, isTrue);
        expect(find.byType(Radio<AppThemePreference>), findsNWidgets(3));
        expect(
          tester
              .widget<RadioGroup<AppThemePreference>>(
                find.byType(RadioGroup<AppThemePreference>),
              )
              .groupValue,
          AppThemePreference.system,
        );
        expect(Theme.of(tester.element(sheet)).useMaterial3, isTrue);
        expect(
          tester.getSize(find.byKey(const ValueKey('settings-group'))),
          group,
        );
        expect(find.byType(ModalBarrier), findsWidgets);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.linux,
      }),
    );
  }

  for (final action in ['escape', 'back', 'outside', 'current']) {
    testWidgets('Theme $action dismisses with no write and restores focus', (
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
      await tester.tap(themeRow);
      await tester.pumpAndSettle();
      switch (action) {
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
      expect(writes, 0);
      expect(find.byType(BottomSheet), findsNothing);
      expect(settingsRowInk(tester, themeRow).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keyboard opens Theme and Escape returns to row', (tester) async {
    await tester.pumpWidget(const SettingsReviewHarness());
    final focus = settingsRowInk(tester, themeRow).focusNode!;
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
  });

  for (final color in [false, true]) {
    for (final success in [true, false]) {
      testWidgets(
        '${color ? "Color" : "Theme"} saves once / rollback=$success',
        (tester) async {
          final storage = _Storage();
          final owner = AppSettingsController(
            AppSettingsStore(storage: storage),
            null,
            initialSettings: AppSettings.defaults,
          );
          addTearDown(owner.dispose);
          await tester.pumpWidget(SettingsReviewHarness(owner: owner));
          if (color) {
            await openColor(tester);
            await tester.tap(
              find
                  .byKey(const ValueKey('settings-color-source-system'))
                  .hitTestable(),
            );
          } else {
            await tester.tap(themeRow);
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('settings-theme-light')),
            );
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump();
          expect(storage.writes, 1);
          expect(settingsRowInk(tester, themeRow).onTap, isNull);
          expect(
            tester
                .widget<DropdownMenu<AppColorSourcePreference>>(colorMenu)
                .enabled,
            isFalse,
          );
          if (success) {
            storage.pending.complete();
          } else {
            storage.pending.completeError(
              StateError('synthetic storage failure'),
            );
          }
          await tester.pumpAndSettle();
          expect(
            owner.settings.theme,
            !color && success
                ? AppThemePreference.light
                : AppThemePreference.system,
          );
          expect(
            owner.settings.colorSource,
            color && success
                ? AppColorSourcePreference.system
                : AppColorSourcePreference.brand,
          );
          expect(
            tester
                .widget<DropdownMenu<AppColorSourcePreference>>(colorMenu)
                .initialSelection,
            owner.settings.colorSource,
          );
          final field = tester.widget<TextField>(
            find.descendant(of: colorMenu, matching: find.byType(TextField)),
          );
          expect(
            field.controller!.text,
            color && success ? 'System colors (Monet)' : 'Brand impression',
          );
          expect(
            find.byType(SnackBar),
            success ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Theme retired sheet cannot write after replacement, reopen or disposal',
    (tester) async {
      final storage = _Storage(completed: true);
      final owner = AppSettingsController(
        AppSettingsStore(storage: storage),
        null,
        initialSettings: AppSettings.defaults,
      );
      addTearDown(owner.dispose);
      await tester.pumpWidget(SettingsReviewHarness(owner: owner));
      await tester.tap(themeRow);
      await tester.pumpAndSettle();
      final retired = tester
          .widget<RadioGroup<AppThemePreference>>(
            find.byType(RadioGroup<AppThemePreference>),
          )
          .onChanged;
      await owner.update(
        owner.settings.copyWith(theme: AppThemePreference.dark),
      );
      await tester.pump();
      await owner.update(
        owner.settings.copyWith(theme: AppThemePreference.system),
      );
      await tester.pump();
      retired(AppThemePreference.light);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(themeRow);
      await tester.pumpAndSettle();
      retired(AppThemePreference.light);
      await tester.pumpAndSettle();
      expect(storage.writes, 2);
      expect(find.byType(BottomSheet), findsOneWidget);
      final disposed = tester
          .widget<RadioGroup<AppThemePreference>>(
            find.byType(RadioGroup<AppThemePreference>),
          )
          .onChanged;
      await tester.pumpWidget(
        SettingsReviewHarness(owner: owner, showPage: false),
      );
      await tester.pumpAndSettle();
      disposed(AppThemePreference.light);
      await tester.pumpAndSettle();
      expect(storage.writes, 2);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Color uses official select-only menu, no inline radios, truthful availability',
    (tester) async {
      for (final available in [false, true]) {
        await tester.pumpWidget(
          SettingsReviewHarness(
            key: ValueKey(available),
            systemColorsAvailable: available,
          ),
        );
        final menu = tester.widget<DropdownMenu<AppColorSourcePreference>>(
          colorMenu,
        );
        expect(menu.selectOnly, isTrue);
        expect(menu.enableSearch, isFalse);
        expect(menu.enableFilter, isFalse);
        expect(menu.initialSelection, AppColorSourcePreference.brand);
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
          find.byKey(const ValueKey('settings-color-details')),
          findsNothing,
        );
        expect(find.byType(Radio<AppColorSourcePreference>), findsNothing);
        expect(
          find.byWidgetPredicate((w) => w is DropdownButton),
          findsNothing,
        );
        await openColor(tester);
        expect(find.byType(BottomSheet), findsNothing);
        await tester.tap(
          find
              .byKey(const ValueKey('settings-color-source-system'))
              .hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownMenu<AppColorSourcePreference>>(colorMenu)
              .initialSelection,
          AppColorSourcePreference.system,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final dismiss in [false, true]) {
    testWidgets('Color current/dismiss no write, dismiss=$dismiss', (
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
      await openColor(tester);
      if (dismiss) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tap(
          find
              .byKey(const ValueKey('settings-color-source-brand'))
              .hitTestable(),
        );
      }
      await tester.pumpAndSettle();
      expect(writes, 0);
    });
  }

  testWidgets('Color stale / duplicate / disposed selection cannot write', (
    tester,
  ) async {
    final storage = _Storage(completed: true);
    final owner = AppSettingsController(
      AppSettingsStore(storage: storage),
      null,
      initialSettings: AppSettings.defaults,
    );
    addTearDown(owner.dispose);
    await tester.pumpWidget(SettingsReviewHarness(owner: owner));
    final old = tester
        .widget<DropdownMenu<AppColorSourcePreference>>(colorMenu)
        .onSelected!;
    await owner.update(
      owner.settings.copyWith(colorSource: AppColorSourcePreference.system),
    );
    await tester.pumpAndSettle();
    await owner.update(
      owner.settings.copyWith(colorSource: AppColorSourcePreference.brand),
    );
    await tester.pumpAndSettle();
    old(AppColorSourcePreference.system);
    await tester.pumpAndSettle();
    expect(storage.writes, 2);
    final current = tester
        .widget<DropdownMenu<AppColorSourcePreference>>(colorMenu)
        .onSelected!;
    current(AppColorSourcePreference.system);
    current(AppColorSourcePreference.system);
    await tester.pumpAndSettle();
    expect(storage.writes, 3);
    final disposed = tester
        .widget<DropdownMenu<AppColorSourcePreference>>(colorMenu)
        .onSelected!;
    await tester.pumpWidget(
      SettingsReviewHarness(owner: owner, showPage: false),
    );
    await tester.pumpAndSettle();
    disposed(AppColorSourcePreference.brand);
    expect(storage.writes, 3);
    expect(tester.takeException(), isNull);
  });
}

class _Storage implements AppSettingsDocumentStorage {
  _Storage({bool completed = false}) {
    if (completed) pending.complete();
  }
  final pending = Completer<void>();
  int writes = 0;
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String document) {
    writes++;
    return pending.future;
  }

  @override
  Future<void> delete() async {}
}
