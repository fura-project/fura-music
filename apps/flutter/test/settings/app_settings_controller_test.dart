import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_controller.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';

void main() {
  test(
    'concurrent failures roll back to the last persisted settings',
    () async {
      final storage = _ControlledDocumentStorage();
      final qualityChanges = <AppPlaybackQualityPreference>[];
      final controller = AppSettingsController(
        AppSettingsStore(storage: storage),
        qualityChanges.add,
        initialSettings: AppSettings.defaults,
      );
      const dark = AppSettings(theme: AppThemePreference.dark);
      const lossless = AppSettings(
        theme: AppThemePreference.dark,
        playbackQuality: AppPlaybackQualityPreference.lossless,
      );

      final first = controller.update(dark);
      final second = controller.update(lossless);
      expect(controller.settings, lossless);
      expect(qualityChanges, [AppPlaybackQualityPreference.lossless]);

      await _flushTasks();
      expect(storage.writes, hasLength(1));
      storage.fail(0);
      expect(await first, AppSettingsWriteResult.storageUnavailable);

      await _flushTasks();
      expect(storage.writes, hasLength(2));
      storage.fail(1);
      expect(await second, AppSettingsWriteResult.storageUnavailable);

      expect(controller.settings, AppSettings.defaults);
      expect(qualityChanges, [
        AppPlaybackQualityPreference.lossless,
        AppPlaybackQualityPreference.standard,
      ]);
      controller.dispose();
    },
  );

  test('later failure rolls back to the preceding successful write', () async {
    final storage = _ControlledDocumentStorage();
    final controller = AppSettingsController(
      AppSettingsStore(storage: storage),
      null,
      initialSettings: AppSettings.defaults,
    );
    const dark = AppSettings(theme: AppThemePreference.dark);
    const lossless = AppSettings(
      theme: AppThemePreference.dark,
      playbackQuality: AppPlaybackQualityPreference.lossless,
    );

    final first = controller.update(dark);
    final second = controller.update(lossless);
    await _flushTasks();
    storage.complete(0);
    expect(await first, AppSettingsWriteResult.saved);

    await _flushTasks();
    storage.fail(1);
    expect(await second, AppSettingsWriteResult.storageUnavailable);
    expect(controller.settings, dark);
    controller.dispose();
  });

  test('late persistence failure does not roll back after dispose', () async {
    final storage = _ControlledDocumentStorage();
    final qualityChanges = <AppPlaybackQualityPreference>[];
    final controller = AppSettingsController(
      AppSettingsStore(storage: storage),
      qualityChanges.add,
      initialSettings: AppSettings.defaults,
    );
    final update = controller.update(
      const AppSettings(
        theme: AppThemePreference.system,
        playbackQuality: AppPlaybackQualityPreference.lossless,
      ),
    );
    await _flushTasks();
    controller.dispose();
    storage.fail(0);

    expect(await update, AppSettingsWriteResult.storageUnavailable);
    expect(qualityChanges, [AppPlaybackQualityPreference.lossless]);
  });

  test(
    'provider persistence failure rolls back to persisted provider',
    () async {
      final storage = _ControlledDocumentStorage();
      final controller = AppSettingsController(
        AppSettingsStore(storage: storage),
        null,
        initialSettings: AppSettings.defaults,
      );

      final update = controller.update(
        AppSettings.defaults.copyWith(
          musicProvider: AppMusicProvider.netEaseCloudMusic,
        ),
      );
      expect(
        controller.settings.musicProvider,
        AppMusicProvider.netEaseCloudMusic,
      );
      await _flushTasks();
      storage.fail(0);

      expect(await update, AppSettingsWriteResult.storageUnavailable);
      expect(controller.settings.musicProvider, AppMusicProvider.qqMusic);
      controller.dispose();
    },
  );

  test(
    'rapid provider writes serialize and retain the final success',
    () async {
      final storage = _ControlledDocumentStorage();
      final controller = AppSettingsController(
        AppSettingsStore(storage: storage),
        null,
        initialSettings: AppSettings.defaults,
      );

      final netEase = controller.update(
        AppSettings.defaults.copyWith(
          musicProvider: AppMusicProvider.netEaseCloudMusic,
        ),
      );
      final qq = controller.update(AppSettings.defaults);
      expect(controller.settings.musicProvider, AppMusicProvider.qqMusic);

      await _flushTasks();
      expect(storage.writes, hasLength(1));
      storage.complete(0);
      expect(await netEase, AppSettingsWriteResult.saved);
      await _flushTasks();
      expect(storage.writes, hasLength(2));
      storage.complete(1);
      expect(await qq, AppSettingsWriteResult.saved);

      expect(controller.settings.musicProvider, AppMusicProvider.qqMusic);
      expect(storage.writes.last, contains('"musicProvider":"qqMusic"'));
      controller.dispose();
    },
  );

  test(
    'locale changes apply optimistically, serialize, and roll back on failure',
    () async {
      final storage = _ControlledDocumentStorage();
      final controller = AppSettingsController(
        AppSettingsStore(storage: storage),
        null,
        initialSettings: AppSettings.defaults,
      );

      final english = controller.update(
        AppSettings.defaults.copyWith(
          localePreference: AppLocalePreference.english,
        ),
      );
      final chinese = controller.update(
        AppSettings.defaults.copyWith(
          localePreference: AppLocalePreference.simplifiedChinese,
        ),
      );
      expect(
        controller.settings.localePreference,
        AppLocalePreference.simplifiedChinese,
      );

      await _flushTasks();
      storage.complete(0);
      expect(await english, AppSettingsWriteResult.saved);
      await _flushTasks();
      storage.fail(1);
      expect(await chinese, AppSettingsWriteResult.storageUnavailable);

      expect(controller.settings.localePreference, AppLocalePreference.english);
      expect(storage.writes.first, contains('"localePreference":"english"'));
      expect(
        storage.writes.last,
        contains('"localePreference":"simplifiedChinese"'),
      );
      controller.dispose();
    },
  );

  test(
    'System to English to Chinese to System retains the final success',
    () async {
      final storage = _ControlledDocumentStorage();
      final controller = AppSettingsController(
        AppSettingsStore(storage: storage),
        null,
        initialSettings: AppSettings.defaults,
      );

      final english = controller.update(
        AppSettings.defaults.copyWith(
          localePreference: AppLocalePreference.english,
        ),
      );
      final chinese = controller.update(
        AppSettings.defaults.copyWith(
          localePreference: AppLocalePreference.simplifiedChinese,
        ),
      );
      final system = controller.update(AppSettings.defaults);

      await _flushTasks();
      storage.complete(0);
      expect(await english, AppSettingsWriteResult.saved);
      await _flushTasks();
      storage.complete(1);
      expect(await chinese, AppSettingsWriteResult.saved);
      await _flushTasks();
      storage.complete(2);
      expect(await system, AppSettingsWriteResult.saved);

      expect(controller.settings.localePreference, AppLocalePreference.system);
      expect(storage.writes, hasLength(3));
      expect(storage.writes.last, contains('"localePreference":"system"'));
      controller.dispose();
    },
  );

  test(
    'rapid locale and provider writes keep one serialized final document',
    () async {
      final storage = _ControlledDocumentStorage();
      final controller = AppSettingsController(
        AppSettingsStore(storage: storage),
        null,
        initialSettings: AppSettings.defaults,
      );

      final chinese = controller.update(
        AppSettings.defaults.copyWith(
          localePreference: AppLocalePreference.simplifiedChinese,
        ),
      );
      final netEaseEnglish = controller.update(
        AppSettings.defaults.copyWith(
          musicProvider: AppMusicProvider.netEaseCloudMusic,
          localePreference: AppLocalePreference.english,
          playbackQuality: AppPlaybackQualityPreference.high,
        ),
      );

      await _flushTasks();
      expect(storage.writes, hasLength(1));
      storage.complete(0);
      expect(await chinese, AppSettingsWriteResult.saved);
      await _flushTasks();
      expect(storage.writes, hasLength(2));
      storage.complete(1);
      expect(await netEaseEnglish, AppSettingsWriteResult.saved);

      expect(
        controller.settings,
        const AppSettings(
          theme: AppThemePreference.system,
          musicProvider: AppMusicProvider.netEaseCloudMusic,
          localePreference: AppLocalePreference.english,
          playbackQuality: AppPlaybackQualityPreference.high,
        ),
      );
      expect(
        storage.writes.last,
        contains('"musicProvider":"netEaseCloudMusic"'),
      );
      expect(storage.writes.last, contains('"localePreference":"english"'));
      expect(storage.writes.last, contains('"playbackQuality":"high"'));
      controller.dispose();
    },
  );
}

Future<void> _flushTasks() => Future<void>.delayed(Duration.zero);

class _ControlledDocumentStorage implements AppSettingsDocumentStorage {
  final List<String> writes = [];
  final List<Completer<void>> _completions = [];

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String document) async {
    writes.add(document);
    final completion = Completer<void>();
    _completions.add(completion);
    await completion.future;
  }

  @override
  Future<void> delete() async {}

  void complete(int index) => _completions[index].complete();

  void fail(int index) =>
      _completions[index].completeError(StateError('synthetic write failure'));
}
