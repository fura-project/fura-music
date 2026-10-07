import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Runtime overrides on Linux let separate processes reuse the same test
  // binary. Android can use dart-defines instead; neither path selects a real
  // settings key or reads account data.
  final restartPhase =
      (kIsWeb ? null : Platform.environment['FURA_SETTINGS_STORAGE_PHASE']) ??
      const String.fromEnvironment('FURA_SETTINGS_STORAGE_PHASE');
  final restartNonce =
      (kIsWeb ? null : Platform.environment['FURA_SETTINGS_STORAGE_NONCE']) ??
      const String.fromEnvironment('FURA_SETTINGS_STORAGE_NONCE');
  if (restartPhase.isNotEmpty) {
    if (!{'seed', 'verify', 'reset'}.contains(restartPhase) ||
        !RegExp(r'^[a-zA-Z0-9_-]{8,64}$').hasMatch(restartNonce)) {
      throw ArgumentError('invalid disposable settings restart fixture');
    }
    testWidgets('native settings survive a process restart ($restartPhase)', (
      _,
    ) async {
      final storage = SharedPreferencesAppSettingsDocumentStorage(
        documentKey:
            'flutterustmusic.integration.settings.restart.$restartNonce',
      );
      final store = AppSettingsStore(storage: storage);
      const expected = AppSettings(theme: AppThemePreference.dark);
      if (restartPhase == 'seed') {
        expect(await storage.read(), isNull, reason: 'test-key collision');
        expect(await store.save(expected), AppSettingsWriteResult.saved);
      } else {
        final loaded = await store.load();
        expect(loaded.state, AppSettingsLoadState.stored);
        expect(loaded.settings, expected);
        if (restartPhase == 'reset') {
          expect(await store.reset(), AppSettingsWriteResult.saved);
          expect(await storage.read(), isNull);
          expect((await store.load()).state, AppSettingsLoadState.defaults);
        }
      }
    }, skip: kIsWeb || !(Platform.isLinux || Platform.isAndroid));
  }

  testWidgets('native preferences round-trip a disposable settings document', (
    _,
  ) async {
    final nonce = Random.secure().nextInt(1 << 32).toRadixString(16);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final key = 'flutterustmusic.integration.settings.$timestamp.$nonce';
    final storage = SharedPreferencesAppSettingsDocumentStorage(
      documentKey: key,
    );
    final store = AppSettingsStore(storage: storage);

    try {
      expect(await storage.read(), isNull, reason: 'test-key collision');
      expect(
        await store.save(
          const AppSettings(
            theme: AppThemePreference.dark,
            colorSource: AppColorSourcePreference.system,
            playbackQuality: AppPlaybackQualityPreference.high,
            localePreference: AppLocalePreference.simplifiedChinese,
          ),
        ),
        AppSettingsWriteResult.saved,
      );
      final loaded = await store.load();
      expect(loaded.state, AppSettingsLoadState.stored);
      expect(
        loaded.settings,
        const AppSettings(
          theme: AppThemePreference.dark,
          colorSource: AppColorSourcePreference.system,
          playbackQuality: AppPlaybackQualityPreference.high,
          localePreference: AppLocalePreference.simplifiedChinese,
        ),
      );
      expect(await store.reset(), AppSettingsWriteResult.saved);
      expect(await storage.read(), isNull);
    } finally {
      await storage.delete();
      expect(
        await storage.read(),
        isNull,
        reason: 'disposable settings document must not remain',
      );
    }
  }, skip: kIsWeb || !(Platform.isLinux || Platform.isAndroid));
}
