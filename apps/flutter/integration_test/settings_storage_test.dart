import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
            playbackQuality: AppPlaybackQualityPreference.high,
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
          playbackQuality: AppPlaybackQualityPreference.high,
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
