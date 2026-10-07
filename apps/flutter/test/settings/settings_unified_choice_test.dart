import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_controller.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';

import 'settings_review_harness.dart';

const allPlatforms = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.linux,
  TargetPlatform.windows,
  TargetPlatform.macOS,
  TargetPlatform.iOS,
});

void main() {
  testWidgets(
    'inline disclosure supports keyboard selection and current no-op',
    (tester) async {
      final storage = _PendingStorage(Future.value());
      final owner = AppSettingsController(
        AppSettingsStore(storage: storage),
        null,
        initialSettings: AppSettings.defaults,
      );
      addTearDown(owner.dispose);
      await tester.pumpWidget(SettingsReviewHarness(owner: owner));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('settings-color-source-selector'));
      final focus = tester.widget<ListTile>(row).focusNode!;
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      final system = find.byKey(const ValueKey('settings-color-source-system'));
      tester
          .widget<RadioListTile<AppColorSourcePreference>>(system)
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(owner.settings.colorSource, AppColorSourcePreference.system);
      expect(storage.writes, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(owner.settings.colorSource, AppColorSourcePreference.brand);
      expect(storage.writes, 2);
      await tester.tap(
        find.byKey(const ValueKey('settings-color-source-brand')),
      );
      await tester.pumpAndSettle();
      expect(storage.writes, 2);
      expect(
        find.byKey(const ValueKey('settings-color-palette-preview')),
        findsOneWidget,
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-color-palette-preview')),
        findsNothing,
      );
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale, duplicate and invalid sheet results cannot write', (
    tester,
  ) async {
    final storage = _PendingStorage(Future.value());
    final owner = AppSettingsController(
      AppSettingsStore(storage: storage),
      null,
      initialSettings: AppSettings.defaults,
    );
    addTearDown(owner.dispose);
    await tester.pumpWidget(SettingsReviewHarness(owner: owner));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-theme-selector'));
    tester.widget<ListTile>(row).onTap!();
    tester.widget<ListTile>(row).onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await owner.update(owner.settings.copyWith(theme: AppThemePreference.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-theme-light')));
    await tester.pumpAndSettle();
    expect(owner.settings.theme, AppThemePreference.dark);
    expect(
      storage.writes,
      1,
    ); // Only the external update, not the stale result.
    for (final index in [-1, 100]) {
      await tester.tap(row);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(BottomSheet))).pop(index);
      await tester.pumpAndSettle();
      expect(owner.settings.theme, AppThemePreference.dark);
      expect(storage.writes, 1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('idle row pixels return after hover and focus state layers', (
    tester,
  ) async {
    setSettingsViewport(tester, const Size(1440, 900));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundary, child: const SettingsReviewHarness()),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-theme-selector'));
    expect(tester.widget<ListTile>(row).selected, isFalse);
    final idle = await _rowPixels(tester, boundary, row);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 0));
    await mouse.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();
    expect(listEquals(idle, await _rowPixels(tester, boundary, row)), isFalse);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(listEquals(idle, await _rowPixels(tester, boundary, row)), isTrue);
    final focus = tester.widget<ListTile>(row).focusNode!;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(listEquals(idle, await _rowPixels(tester, boundary, row)), isFalse);
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(listEquals(idle, await _rowPixels(tester, boundary, row)), isTrue);
  });

  testWidgets('all platforms use one content-driven Flutter M3 choice', (
    tester,
  ) async {
    const oldChannel = MethodChannel('com.fura/settings_choice');
    var nativeCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(oldChannel, (
      _,
    ) async {
      nativeCalls++;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        oldChannel,
        null,
      ),
    );
    setSettingsViewport(tester, const Size(1440, 900));
    await tester.pumpWidget(const SettingsReviewHarness());
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-theme-selector'));
    await tester.tap(row);
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(nativeCalls, 0);
    expect(Theme.of(tester.element(sheet)).useMaterial3, isTrue);
    final content = find.byKey(const ValueKey('settings-choice-sheet'));
    expect(tester.getSize(content).width, lessThanOrEqualTo(560));
    expect(tester.getSize(content).height, lessThan(400));
    expect(tester.getBottomLeft(sheet).dy, 900);
    expect(
      tester.widget<RadioGroup<int>>(find.byType(RadioGroup<int>)).groupValue,
      0,
    );
    await tester.tap(find.byKey(const ValueKey('settings-theme-light')));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('settings-theme-selector-current')),
          )
          .data,
      'Light',
    );
    expect(tester.widget<ListTile>(row).focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: allPlatforms);

  testWidgets('detailed Color Source is inline and owns the palette', (
    tester,
  ) async {
    await tester.pumpWidget(const SettingsReviewHarness());
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-color-source-selector'));
    expect(
      find.byKey(const ValueKey('settings-color-palette-preview')),
      findsNothing,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-color-palette-preview')),
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
      find.byKey(const ValueKey('settings-color-palette-preview')),
      findsOneWidget,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-color-palette-preview')),
      findsNothing,
    );
    expect(tester.widget<ListTile>(row).focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: allPlatforms);

  for (final success in [true, false]) {
    testWidgets(
      'inline selection keeps save owner and rollback success=$success',
      (tester) async {
        final saved = Completer<void>();
        final storage = _PendingStorage(saved.future);
        final owner = AppSettingsController(
          AppSettingsStore(storage: storage),
          null,
          initialSettings: AppSettings.defaults,
        );
        addTearDown(owner.dispose);
        await tester.pumpWidget(SettingsReviewHarness(owner: owner));
        final row = find.byKey(
          const ValueKey('settings-color-source-selector'),
        );
        await tester.tap(row);
        await tester.pumpAndSettle();
        final option = find.byKey(
          const ValueKey('settings-color-source-system'),
        );
        await tester.tap(option);
        await tester.pump();
        expect(storage.writes, 1);
        expect(owner.settings.colorSource, AppColorSourcePreference.system);
        expect(tester.widget<ListTile>(row).enabled, isFalse);
        expect(
          tester
              .widget<RadioListTile<AppColorSourcePreference>>(option)
              .enabled,
          isFalse,
        );
        if (success) {
          saved.complete();
        } else {
          saved.completeError(StateError('synthetic failure'));
        }
        await tester.pumpAndSettle();
        expect(
          owner.settings.colorSource,
          success
              ? AppColorSourcePreference.system
              : AppColorSourcePreference.brand,
        );
        expect(
          find.byKey(const ValueKey('settings-color-palette-preview')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<RadioListTile<AppColorSourcePreference>>(option)
              .focusNode!
              .hasFocus,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'disclosure height and chevron motion reduced=$reduced rapid toggle',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(const SettingsReviewHarness());
        await tester.pumpAndSettle();
        final group = find.byKey(const ValueKey('settings-group'));
        final row = find.byKey(
          const ValueKey('settings-color-source-selector'),
        );
        final collapsed = tester.getSize(group).height;
        await tester.tap(row);
        await tester.pump();
        final rotation = tester.widget<AnimatedRotation>(
          find.byKey(const ValueKey('settings-color-chevron')),
        );
        if (reduced) {
          expect(
            find.byKey(const ValueKey('settings-color-size')),
            findsNothing,
          );
          expect(tester.getSize(group).height, greaterThan(collapsed));
        } else {
          expect(
            tester
                .widget<AnimatedSize>(
                  find.byKey(const ValueKey('settings-color-size')),
                )
                .duration,
            const Duration(milliseconds: 200),
          );
        }
        expect(rotation.turns, 0.5);
        if (!reduced) {
          await tester.pump(const Duration(milliseconds: 80));
          expect(tester.getSize(group).height, greaterThan(collapsed));
        }
        for (var i = 0; i < 10; i++) {
          await tester.tap(row);
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-color-palette-preview')),
          findsOneWidget,
        );
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(tester.getSize(group).height, collapsed);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<List<int>> _rowPixels(
  WidgetTester tester,
  GlobalKey boundary,
  Finder row,
) async {
  final rect = tester.getRect(row);
  return (await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    final pixels = <int>[];
    for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
      pixels.addAll(
        bytes.sublist(
          (y * image.width + rect.left.ceil()) * 4,
          (y * image.width + rect.right.floor()) * 4,
        ),
      );
    }
    image.dispose();
    return pixels;
  }))!;
}

class _PendingStorage implements AppSettingsDocumentStorage {
  _PendingStorage(this.pending);
  final Future<void> pending;
  int writes = 0;
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String document) {
    writes++;
    return pending;
  }

  @override
  Future<void> delete() async {}
}
