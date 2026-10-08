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
  testWidgets('official RadioListTile owns choices and SDK handle dismisses', (
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
    await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
    await tester.pumpAndSettle();
    expect(find.byType(RadioListTile<int>), findsNWidgets(3));
    final sheet = find.byType(BottomSheet);
    expect(tester.widget<BottomSheet>(sheet).showDragHandle, isTrue);
    expect(
      FocusManager.instance.primaryFocus!.context!
          .findAncestorWidgetOfExactType<RadioListTile<int>>()
          ?.value,
      0,
    );
    await tester.flingFrom(
      tester.getTopLeft(sheet) + const Offset(100, 16),
      const Offset(0, 350),
      1500,
    );
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(writes, 0);
  });
  testWidgets('full-width sheet tracks live window resize', (tester) async {
    setSettingsViewport(tester, const Size(1440, 900));
    await tester.pumpWidget(const SettingsReviewHarness());
    await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BottomSheet)).width, 1440);
    tester.view.physicalSize = const Size(1000, 900);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BottomSheet)).width, 1000);
    expect(
      tester.getBottomLeft(find.byType(BottomSheet)),
      const Offset(0, 900),
    );
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
    expect(tester.getSize(content).width, 1440);
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
    'official color dropdown leaves group fixed and owns no radio panel',
    (tester) async {
      await tester.pumpWidget(const SettingsReviewHarness());
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownMenu<AppColorSourcePreference>);
      final group = find.byKey(const ValueKey('settings-group'));
      final before = tester.getRect(group);
      expect(
        find.byKey(const ValueKey('settings-color-palette-preview')),
        findsOneWidget,
      );
      expect(find.byType(DropdownButton), findsNothing);
      expect(find.byType(DropdownButtonFormField), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-color-menu-anchor')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-color-details')),
        findsNothing,
      );
      expect(find.byType(RadioGroup<AppColorSourcePreference>), findsNothing);
      // DropdownMenu's internal SDK MenuAnchor is not a Fura-owned popup.
      expect(
        find.ancestor(of: find.byType(MenuAnchor), matching: dropdown),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DropdownMenu<AppColorSourcePreference>>(dropdown)
            .initialSelection,
        AppColorSourcePreference.brand,
      );
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getRect(group), before);
      await tester.tap(_colorOption('system'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownMenu<AppColorSourcePreference>>(dropdown)
            .initialSelection,
        AppColorSourcePreference.system,
      );
      expect(tester.getRect(group), before);
      expect(tester.takeException(), isNull);
    },
    variant: allPlatforms,
  );

  for (final success in [true, false]) {
    testWidgets('dropdown existing save reconciles success=$success', (
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
      final dropdown = find.byType(DropdownMenu<AppColorSourcePreference>);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(_colorOption('system'));
      await tester.pump();
      // The Settings saving flag schedules a second rebuild after the
      // optimistic owner notification; inspect the rendered disabled state.
      await tester.pump();
      expect(storage.writes, 1);
      expect(owner.settings.colorSource, AppColorSourcePreference.system);
      expect(
        tester.widget<DropdownMenu<AppColorSourcePreference>>(dropdown).enabled,
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
      final widget = tester.widget<DropdownMenu<AppColorSourcePreference>>(
        dropdown,
      );
      expect(widget.initialSelection, owner.settings.colorSource);
      expect(widget.focusNode!.hasFocus, isTrue);
      expect(find.byType(SnackBar), success ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final dismiss in ['outside', 'escape', 'current']) {
    testWidgets('dropdown $dismiss dismisses without write', (tester) async {
      var writes = 0;
      await tester.pumpWidget(
        SettingsReviewHarness(
          onChanged: (_) async {
            writes++;
            return AppSettingsWriteResult.saved;
          },
        ),
      );
      await tester.tap(find.byType(DropdownMenu<AppColorSourcePreference>));
      await tester.pumpAndSettle();
      switch (dismiss) {
        case 'outside':
          await tester.tapAt(const Offset(8, 8));
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'current':
          await tester.tap(_colorOption('brand'));
      }
      await tester.pumpAndSettle();
      expect(_colorOption('system'), findsNothing);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('dropdown keyboard traverses choices and persists once', (
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
    final dropdown = find.byType(DropdownMenu<AppColorSourcePreference>);
    tester
        .widget<DropdownMenu<AppColorSourcePreference>>(dropdown)
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(owner.settings.colorSource, AppColorSourcePreference.system);
    expect(storage.writes, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'externally replaced dropdown and disposed caller cannot write stale result',
    (tester) async {
      final storage = _PendingStorage(Future.value());
      final owner = AppSettingsController(
        AppSettingsStore(storage: storage),
        null,
        initialSettings: AppSettings.defaults,
      );
      addTearDown(owner.dispose);
      await tester.pumpWidget(SettingsReviewHarness(owner: owner));
      final dropdown = find.byType(DropdownMenu<AppColorSourcePreference>);
      final oldCallback = tester
          .widget<DropdownMenu<AppColorSourcePreference>>(dropdown)
          .onSelected!;
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await owner.update(
        owner.settings.copyWith(colorSource: AppColorSourcePreference.system),
      );
      await tester.pumpAndSettle();
      oldCallback(AppColorSourcePreference.brand);
      await tester.pumpAndSettle();
      expect(storage.writes, 1);
      expect(_colorOption('brand'), findsNothing);
      final disposedCallback = tester
          .widget<DropdownMenu<AppColorSourcePreference>>(dropdown)
          .onSelected!;
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        SettingsReviewHarness(owner: owner, showPage: false),
      );
      await tester.pumpAndSettle();
      disposedCallback(AppColorSourcePreference.brand);
      await tester.pumpAndSettle();
      expect(storage.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dismiss in ['escape', 'outside']) {
    testWidgets(
      'keyboard preview dismissed with $dismiss restores saved selection',
      (tester) async {
        await tester.pumpWidget(const SettingsReviewHarness());
        final dropdown = find.byType(DropdownMenu<AppColorSourcePreference>);
        final initialText = tester
            .widget<TextField>(
              find.descendant(of: dropdown, matching: find.byType(TextField)),
            )
            .controller!
            .text;
        tester
            .widget<DropdownMenu<AppColorSourcePreference>>(dropdown)
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        if (dismiss == 'escape') {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tapAt(const Offset(8, 8));
        }
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.descendant(of: dropdown, matching: find.byType(TextField)),
              )
              .controller!
              .text,
          initialText,
        );
      },
    );
  }
  for (final reduced in [false, true]) {
    testWidgets(
      'SDK dropdown rapid toggles reduced=$reduced do not expand the group',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(const SettingsReviewHarness());
        final dropdown = find.byType(DropdownMenu<AppColorSourcePreference>);
        final group = find.byKey(const ValueKey('settings-group'));
        final size = tester.getSize(group);
        for (var i = 0; i < 10; i++) {
          await tester.tap(dropdown);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          expect(tester.getSize(group), size);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder _colorOption(String value) =>
    find.byKey(ValueKey('settings-color-source-$value')).hitTestable();

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
