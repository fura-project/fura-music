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
import 'package:flutterustmusic/settings/settings_choice_presentation.dart';

import 'settings_review_harness.dart';

const allPlatforms = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.linux,
  TargetPlatform.windows,
  TargetPlatform.macOS,
  TargetPlatform.iOS,
});

void main() {
  testWidgets('radio keyboard focus paints the whole custom choice row', (
    tester,
  ) async {
    setSettingsViewport(tester, const Size(1440, 900));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundary, child: const SettingsReviewHarness()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-theme-system'));
    // Radio's autofocus owns its internal focus node. Focus.of at the Radio
    // widget's element instead finds its non-requestable ancestor InkWell.
    final focus = FocusManager.instance.primaryFocus!;
    expect(
      focus.context!.findAncestorWidgetOfExactType<FuraChoiceRow<int>>()?.key,
      const ValueKey('settings-theme-system'),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    await tester.pumpAndSettle();
    // Blank trailing pixels exclude the Radio's own circular focus highlight.
    final rect = tester.getRect(row);
    final area = Rect.fromLTWH(rect.right - 48, rect.top + 12, 24, 24);
    final idle = await _rowPixels(tester, boundary, row, area: area);
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(
      listEquals(idle, await _rowPixels(tester, boundary, row, area: area)),
      isFalse,
    );
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(
      listEquals(idle, await _rowPixels(tester, boundary, row, area: area)),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom handle retains route drag-dismiss with no write', (
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
    await tester.fling(
      find.byKey(const ValueKey('settings-choice-handle')),
      const Offset(0, 350),
      1500,
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(writes, 0);
    expect(settingsRowInk(tester, row).focusNode!.hasFocus, isTrue);
  });

  testWidgets(
    '2x short compact menu stays in viewport and all options remain reachable',
    (tester) async {
      setSettingsViewport(tester, const Size(320, 480));
      await tester.pumpWidget(
        const SettingsReviewHarness(compact: true, scale: 2, language: 'zh'),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('settings-color-source-selector'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      final popup = find.byKey(const ValueKey('settings-color-popup'));
      final rect = tester.getRect(popup);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(480));
      for (final option in [
        'settings-color-source-system',
        'settings-color-source-brand',
      ]) {
        final target = find.byKey(ValueKey(option));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
      }
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-color-palette-preview')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('anchored radio keyboard selection closes and restores focus', (
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
    final row = find.byKey(const ValueKey('settings-color-source-selector'));
    final focus = settingsRowInk(tester, row).focusNode!;
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('settings-color-popup')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(owner.settings.colorSource, AppColorSourcePreference.system);
    expect(storage.writes, 1);
    expect(find.byKey(const ValueKey('settings-color-popup')), findsNothing);
    expect(focus.hasFocus, isTrue);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(storage.writes, 1);
    expect(find.byKey(const ValueKey('settings-color-popup')), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
    settingsRowInk(tester, row).onTap!();
    settingsRowInk(tester, row).onTap!();
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
    expect(
      find.descendant(of: row, matching: find.byType(ListTile)),
      findsNothing,
    );
    final idle = await _rowPixels(tester, boundary, row);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 0));
    await mouse.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();
    expect(listEquals(idle, await _rowPixels(tester, boundary, row)), isFalse);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(listEquals(idle, await _rowPixels(tester, boundary, row)), isTrue);
    final focus = settingsRowInk(tester, row).focusNode!;
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
    expect(tester.getSize(content).width, lessThanOrEqualTo(480));
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
    expect(settingsRowInk(tester, row).focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: allPlatforms);

  testWidgets(
    'Color Source is anchored, leaves the group fixed, and owns palette',
    (tester) async {
      await tester.pumpWidget(const SettingsReviewHarness());
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('settings-color-source-selector'));
      final group = find.byKey(const ValueKey('settings-group'));
      final before = tester.getRect(group);
      expect(
        find.byKey(const ValueKey('settings-color-palette-preview')),
        findsNothing,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(MenuAnchor), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(FuraChoiceSheet), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-color-details')),
        findsNothing,
      );
      expect(tester.getRect(group), before);
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
      expect(find.byKey(const ValueKey('settings-color-popup')), findsNothing);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<AppColorSourcePreference>>(
              find.byType(RadioGroup<AppColorSourcePreference>),
            )
            .groupValue,
        AppColorSourcePreference.system,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-color-palette-preview')),
        findsNothing,
      );
      expect(settingsRowInk(tester, row).focusNode!.hasFocus, isTrue);
      expect(tester.getRect(group), before);
      expect(tester.takeException(), isNull);
    },
    variant: allPlatforms,
  );

  for (final success in [true, false]) {
    testWidgets('menu closes then existing save reconciles success=$success', (
      tester,
    ) async {
      final saved = Completer<void>();
      final storage = _PendingStorage(saved.future);
      final owner = AppSettingsController(
        AppSettingsStore(storage: storage),
        null,
        initialSettings: AppSettings.defaults,
      );
      addTearDown(owner.dispose);
      await tester.pumpWidget(SettingsReviewHarness(owner: owner));
      final row = find.byKey(const ValueKey('settings-color-source-selector'));
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-color-source-system')),
      );
      await tester.pump();
      expect(storage.writes, 1);
      expect(owner.settings.colorSource, AppColorSourcePreference.system);
      expect(find.byKey(const ValueKey('settings-color-popup')), findsNothing);
      expect(settingsRowInk(tester, row).onTap, isNull);
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
      expect(settingsRowInk(tester, row).focusNode!.hasFocus, isTrue);
      expect(find.byType(SnackBar), success ? findsNothing : findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<AppColorSourcePreference>>(
              find.byType(RadioGroup<AppColorSourcePreference>),
            )
            .groupValue,
        owner.settings.colorSource,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final dismiss in ['outside', 'escape', 'back', 'current']) {
    testWidgets('menu $dismiss closes without write, restores focus', (
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
      final row = find.byKey(const ValueKey('settings-color-source-selector'));
      await tester.tap(row);
      await tester.pumpAndSettle();
      switch (dismiss) {
        case 'outside':
          await tester.tapAt(const Offset(8, 8));
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'back':
          await tester.binding.handlePopRoute();
        case 'current':
          await tester.tap(
            find.byKey(const ValueKey('settings-color-source-brand')),
          );
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-color-popup')), findsNothing);
      expect(writes, 0);
      expect(settingsRowInk(tester, row).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stale menu snapshot and disposed anchor cannot write', (
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
    final row = find.byKey(const ValueKey('settings-color-source-selector'));
    await tester.tap(row);
    await tester.pumpAndSettle();
    await owner.update(
      owner.settings.copyWith(colorSource: AppColorSourcePreference.system),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-color-source-brand')));
    await tester.pumpAndSettle();
    expect(storage.writes, 1);
    expect(owner.settings.colorSource, AppColorSourcePreference.system);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      SettingsReviewHarness(owner: owner, showPage: false),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-color-popup')), findsNothing);
    expect(storage.writes, 1);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'anchored menu rapid toggles reduced=$reduced keep group fixed',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(const SettingsReviewHarness());
        await tester.pumpAndSettle();
        final row = find.byKey(
          const ValueKey('settings-color-source-selector'),
        );
        final group = find.byKey(const ValueKey('settings-group'));
        final size = tester.getSize(group);
        for (var i = 0; i < 10; i++) {
          settingsRowInk(tester, row).onTap!();
          await tester.pump();
          expect(tester.getSize(group), size);
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-color-popup')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<List<int>> _rowPixels(
  WidgetTester tester,
  GlobalKey boundary,
  Finder row, {
  Rect? area,
}) async {
  final rect = area ?? tester.getRect(row);
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
