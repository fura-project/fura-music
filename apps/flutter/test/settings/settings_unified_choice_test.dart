import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('all platforms use SDK compact M3 menu without native channel', (
    tester,
  ) async {
    const channel = MethodChannel('com.fura/settings_choice');
    var nativeCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      _,
    ) async {
      nativeCalls++;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    setSettingsViewport(tester, const Size(1440, 900));
    await tester.pumpWidget(const SettingsReviewHarness());
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-theme-selector'));
    final groupSize = tester.getSize(
      find.byKey(const ValueKey('settings-group')),
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    final option = find.byKey(const ValueKey('settings-theme-light'));
    expect(find.byType(MenuItemButton), findsNWidgets(3));
    expect(Theme.of(tester.element(option)).useMaterial3, isTrue);
    final panel = find
        .ancestor(
          of: option,
          matching: find.byWidgetPredicate(
            (w) => w is Material && w.type == MaterialType.canvas,
          ),
        )
        .first;
    // The SDK's desktop compact VisualDensity adjusts 160 dp by -8 dp.
    expect(tester.getSize(panel).width, inInclusiveRange(152, 320));
    expect(
      tester.getSize(find.byKey(const ValueKey('settings-group'))),
      groupSize,
    );
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(nativeCalls, 0);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('settings-theme-selector-current')),
          )
          .data,
      'Light',
    );
  }, variant: allPlatforms);

  testWidgets(
    'external replace, duplicate tap and late disposed menu cannot write',
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
      final row = find.byKey(const ValueKey('settings-theme-selector'));
      await tester.tap(row);
      await tester.pumpAndSettle();
      final oldCallback = tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey('settings-theme-light')),
          )
          .onPressed!;
      await owner.update(
        owner.settings.copyWith(theme: AppThemePreference.dark),
      );
      await tester.pumpAndSettle();
      oldCallback();
      oldCallback();
      await tester.pumpAndSettle();
      expect(owner.settings.theme, AppThemePreference.dark);
      expect(storage.writes, 1);
      expect(find.byType(MenuItemButton), findsNothing);
      await tester.tap(row);
      await tester.pumpAndSettle();
      final disposed = tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey('settings-theme-light')),
          )
          .onPressed!;
      await tester.pumpWidget(
        SettingsReviewHarness(owner: owner, showPage: false),
      );
      await tester.pumpAndSettle();
      disposed();
      await tester.pumpAndSettle();
      expect(storage.writes, 1);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('ABA external replacement invalidates original menu callback', (
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
    await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
    await tester.pumpAndSettle();
    final old = tester
        .widget<MenuItemButton>(
          find.byKey(const ValueKey('settings-theme-light')),
        )
        .onPressed!;
    await owner.update(owner.settings.copyWith(theme: AppThemePreference.dark));
    await tester.pumpAndSettle();
    await owner.update(
      owner.settings.copyWith(theme: AppThemePreference.system),
    );
    await tester.pumpAndSettle();
    old();
    await tester.pumpAndSettle();
    expect(storage.writes, 2);
    expect(owner.settings.theme, AppThemePreference.system);
  });
  testWidgets('a reopened menu cannot accept a retired popup callback', (
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
    final row = find.byKey(const ValueKey('settings-theme-selector'));
    await tester.tap(row);
    await tester.pumpAndSettle();
    final retired = tester
        .widget<MenuItemButton>(
          find.byKey(const ValueKey('settings-theme-light')),
        )
        .onPressed!;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    retired();
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.byKey(const ValueKey('settings-theme-light')), findsOneWidget);
  });
  testWidgets(
    'inactive popup close returns focus on resume, not a retired scope',
    (tester) async {
      await tester.pumpWidget(const SettingsReviewHarness());
      final row = find.byKey(const ValueKey('settings-theme-selector'));
      final focus = settingsRowInk(tester, row).focusNode!;
      await tester.tap(row);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'rapid taps during popup close preserve the next keyboard session',
    (tester) async {
      await tester.pumpWidget(const SettingsReviewHarness());
      final row = find.byKey(const ValueKey('settings-theme-selector'));
      await tester.tap(row);
      await tester.pumpAndSettle();
      final menu = tester
          .widget<MenuAnchor>(
            find.ancestor(of: row, matching: find.byType(MenuAnchor)).first,
          )
          .controller!;
      menu.close();
      // The SDK stays isOpen while reversing its closing animation; another
      // toggle during that transition must not write or leave a stale overlay.
      settingsRowInk(tester, row).onTap!();
      await tester.pumpAndSettle();
      expect(menu.isOpen, isFalse);
      expect(settingsRowInk(tester, row).focusNode!.hasFocus, isTrue);
      settingsRowInk(tester, row).onTap!();
      await tester.pumpAndSettle();
      expect(menu.isOpen, isTrue);
      expect(settingsRowInk(tester, row).focusNode!.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(menu.isOpen, isFalse);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('settings-theme-selector-current')),
            )
            .data,
        'Light',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reopened color details reject a previous expansion callback', (
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
    final row = find.byKey(const ValueKey('settings-color-source-selector'));
    await tester.tap(row);
    await tester.pumpAndSettle();
    final retired = tester
        .widget<InkWell>(
          find.byKey(const ValueKey('settings-color-source-system')),
        )
        .onTap!;
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    retired();
    await tester.pumpAndSettle();
    expect(writes, 0);
  });
  for (final success in [true, false]) {
    testWidgets(
      'inline color saves once, stays expanded and rollback=$success',
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
        await tester.tap(
          find.byKey(const ValueKey('settings-color-source-selector')),
        );
        await tester.pumpAndSettle();
        final option = find.byKey(
          const ValueKey('settings-color-source-system'),
        );
        final oldTap = tester.widget<InkWell>(option).onTap!;
        oldTap();
        oldTap();
        // Saving has an intentional indeterminate progress indicator.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(storage.writes, 1);
        expect(owner.settings.colorSource, AppColorSourcePreference.system);
        expect(tester.widget<InkWell>(option).onTap, isNull);
        expect(
          settingsRowInk(
            tester,
            find.byKey(const ValueKey('settings-color-source-selector')),
          ).onTap,
          isNull,
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
        final group = tester.widget<RadioGroup<AppColorSourcePreference>>(
          find.byType(RadioGroup<AppColorSourcePreference>),
        );
        expect(group.groupValue, owner.settings.colorSource);
        expect(
          find.byKey(const ValueKey('settings-color-details')),
          findsOneWidget,
        );
        final radio = tester.widget<Radio<AppColorSourcePreference>>(
          find.byWidgetPredicate(
            (w) =>
                w is Radio<AppColorSourcePreference> &&
                w.value == owner.settings.colorSource,
          ),
        );
        expect(radio.focusNode!.hasFocus, isTrue);
        expect(find.byType(SnackBar), success ? findsNothing : findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'inline disposed, collapsed and externally replaced callbacks are stale',
    (tester) async {
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
      final first = tester
          .widget<InkWell>(
            find.byKey(const ValueKey('settings-color-source-system')),
          )
          .onTap!;
      await tester.tap(row);
      await tester.pumpAndSettle();
      first();
      await tester.pumpAndSettle();
      expect(storage.writes, 0);
      await tester.tap(row);
      await tester.pumpAndSettle();
      final stale = tester
          .widget<InkWell>(
            find.byKey(const ValueKey('settings-color-source-system')),
          )
          .onTap!;
      await owner.update(
        owner.settings.copyWith(colorSource: AppColorSourcePreference.system),
      );
      await tester.pumpAndSettle();
      stale();
      await tester.pumpAndSettle();
      expect(storage.writes, 1);
      final disposed = tester
          .widget<InkWell>(
            find.byKey(const ValueKey('settings-color-source-brand')),
          )
          .onTap!;
      await tester.pumpWidget(
        SettingsReviewHarness(owner: owner, showPage: false),
      );
      await tester.pumpAndSettle();
      disposed();
      await tester.pumpAndSettle();
      expect(storage.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'inline restrained motion, rapid toggles and stable focus reduced=$reduced',
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
        final focus = settingsRowInk(tester, row).focusNode!;
        focus.requestFocus();
        await tester.pump();
        final group = find.byKey(const ValueKey('settings-group'));
        final collapsed = tester.getSize(group).height;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        if (reduced) {
          expect(
            find.byKey(const ValueKey('settings-color-size')),
            findsNothing,
          );
          expect(tester.getSize(group).height, greaterThan(collapsed));
        } else {
          final start = tester.getSize(group).height;
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.getSize(group).height, greaterThan(start));
        }
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        expect(
          tester
              .widget<AnimatedRotation>(
                find.descendant(
                  of: row,
                  matching: find.byType(AnimatedRotation),
                ),
              )
              .turns,
          .5,
        );
        for (var i = 0; i < 10; i++) {
          await tester.tap(row);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-color-details')),
          findsOneWidget,
        );
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(tester.getSize(group).height, collapsed);
        expect(focus.hasFocus, isTrue);
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
