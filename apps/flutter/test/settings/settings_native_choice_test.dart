import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_controller.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';

import 'settings_review_harness.dart';

void main() {
  const channel = MethodChannel('com.fura/settings_choice');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('native interruption returns focus when the Activity resumes', (
    tester,
  ) async {
    final result = Completer<int?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => result.future);
    await tester.pumpWidget(const SettingsReviewHarness());
    final row = find.byKey(const ValueKey('settings-theme-selector'));
    final focus = tester.widget<ListTile>(row).focusNode!;
    await tester.tap(row);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    result.complete(null);
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final succeeds in [true, false]) {
    testWidgets(
      'focus returns after saving succeeds=$succeeds',
      (tester) async {
        final saved = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => 2);
        final owner = AppSettingsController(
          AppSettingsStore(storage: _PendingStorage(saved.future)),
          null,
          initialSettings: AppSettings.defaults,
        );
        addTearDown(owner.dispose);
        await tester.pumpWidget(SettingsReviewHarness(owner: owner));
        final row = find.byKey(const ValueKey('settings-theme-selector'));
        final focus = tester.widget<ListTile>(row).focusNode!;
        await tester.tap(row);
        await tester.pump();
        if (Theme.of(tester.element(row)).platform != TargetPlatform.android) {
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('settings-theme-dark')));
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(owner.settings.theme, AppThemePreference.dark);
        expect(tester.widget<ListTile>(row).enabled, isFalse);
        if (succeeds) {
          saved.complete();
        } else {
          saved.completeError(StateError('synthetic storage failure'));
        }
        await tester.pumpAndSettle();
        expect(tester.widget<ListTile>(row).enabled, isTrue);
        expect(focus.hasFocus, isTrue);
        expect(
          owner.settings.theme,
          succeeds ? AppThemePreference.dark : AppThemePreference.system,
        );
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.linux,
      }),
    );
  }

  testWidgets(
    'external setting replacement suppresses an old native selection',
    (tester) async {
      final pending = Completer<int?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) => pending.future);
      final storage = _Storage();
      final owner = AppSettingsController(
        AppSettingsStore(storage: storage),
        null,
        initialSettings: AppSettings.defaults,
      );
      addTearDown(owner.dispose);
      await tester.pumpWidget(SettingsReviewHarness(owner: owner));
      await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
      await tester.pump();
      await owner.update(
        owner.settings.copyWith(theme: AppThemePreference.dark),
      );
      await tester.pump();
      pending.complete(1);
      await tester.pumpAndSettle();
      expect(owner.settings.theme, AppThemePreference.dark);
      expect(storage.writes, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('Android uses presentation-only native data and maps result', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 2;
        });
    AppSettings? saved;
    await tester.pumpWidget(
      SettingsReviewHarness(
        onChanged: (next) async {
          saved = next;
          return AppSettingsWriteResult.saved;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'show');
    final data = calls.single.arguments as Map;
    expect(data.keys.toSet(), {
      'requestId',
      'title',
      'options',
      'selectedIndex',
      'brightness',
      'primary',
      'footer',
    });
    expect(data['selectedIndex'], 0);
    expect(data['options'], [
      {'label': 'System', 'supportingText': null, 'enabled': true},
      {'label': 'Light', 'supportingText': null, 'enabled': true},
      {'label': 'Dark', 'supportingText': null, 'enabled': true},
    ]);
    expect(saved?.theme, AppThemePreference.dark);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final result in [null, 0, -1, 99]) {
    testWidgets('native cancel/current/invalid result $result never writes', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => result);
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
      expect(writes, 0);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets(
    'pending native call guards duplicate open and cancels on disposal',
    (tester) async {
      final pending = Completer<int?>();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            calls.add(call);
            return call.method == 'show' ? pending.future : Future.value();
          });
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
      await tester.pump();
      await tester.tap(row);
      await tester.pump();
      expect(calls.where((call) => call.method == 'show'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls.last.method, 'dismiss');
      expect(
        (calls.last.arguments as Map)['requestId'],
        (calls.first.arguments as Map)['requestId'],
      );
      pending.complete(1);
      await tester.pumpAndSettle();
      expect(writes, 0);
    },

    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final missing in [true, false]) {
    testWidgets(
      'native unavailable host missing=$missing never silently falls back',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              if (missing) throw MissingPluginException();
              throw PlatformException(code: 'unavailable');
            });
        await tester.pumpWidget(const SettingsReviewHarness());
        await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },

      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}

class _Storage implements AppSettingsDocumentStorage {
  int writes = 0;
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String document) async {
    writes++;
  }

  @override
  Future<void> delete() async {}
}

class _PendingStorage extends _Storage {
  _PendingStorage(this.completion);
  final Future<void> completion;
  @override
  Future<void> write(String document) => completion;
}
