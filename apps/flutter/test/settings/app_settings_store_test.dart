import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';

void main() {
  test('loads validated defaults when no settings document exists', () async {
    final storage = _MemoryDocumentStorage();

    final result = await AppSettingsStore(storage: storage).load();

    expect(result.state, AppSettingsLoadState.defaults);
    expect(result.settings, AppSettings.defaults);
  });

  test('round trips every supported setting', () async {
    for (final theme in AppThemePreference.values) {
      for (final colorSource in AppColorSourcePreference.values) {
        for (final playbackQuality in AppPlaybackQualityPreference.values) {
          for (final lyricAuxiliaryMode in LyricAuxiliaryMode.values) {
            for (final musicProvider in AppMusicProvider.values) {
              for (final localePreference in AppLocalePreference.values) {
                final storage = _MemoryDocumentStorage();
                final store = AppSettingsStore(storage: storage);
                final settings = AppSettings(
                  theme: theme,
                  colorSource: colorSource,
                  playbackQuality: playbackQuality,
                  lyricAuxiliaryMode: lyricAuxiliaryMode,
                  musicProvider: musicProvider,
                  localePreference: localePreference,
                );

                expect(
                  await store.save(settings),
                  AppSettingsWriteResult.saved,
                );
                final stored =
                    jsonDecode(storage.document!) as Map<String, dynamic>;
                expect(
                  stored['schemaVersion'],
                  AppSettings.currentSchemaVersion,
                );
                expect(stored['theme'], theme.name);
                expect(stored['colorSource'], colorSource.name);
                expect(stored['playbackQuality'], playbackQuality.name);
                expect(stored['lyricAuxiliaryMode'], lyricAuxiliaryMode.name);
                expect(stored['musicProvider'], musicProvider.name);
                expect(stored['localePreference'], localePreference.name);

                final loaded = await store.load();
                expect(loaded.state, AppSettingsLoadState.stored);
                expect(loaded.settings, settings);
              }
            }
          }
        }
      }
    }
  });

  test(
    'migrates the theme-only version 1 document to standard quality',
    () async {
      final storage = _MemoryDocumentStorage(
        document: jsonEncode(<String, Object>{
          'schemaVersion': 1,
          'theme': 'dark',
        }),
      );

      final result = await AppSettingsStore(storage: storage).load();

      expect(result.state, AppSettingsLoadState.migrated);
      expect(
        result.settings,
        const AppSettings(
          theme: AppThemePreference.dark,
          playbackQuality: AppPlaybackQualityPreference.standard,
        ),
      );
      expect(storage.writeCount, 0);
    },
  );

  test('migrates version 2 documents to QQ Music', () async {
    final storage = _MemoryDocumentStorage(
      document: jsonEncode(<String, Object>{
        'schemaVersion': 2,
        'theme': 'light',
        'playbackQuality': 'high',
      }),
    );

    final result = await AppSettingsStore(storage: storage).load();

    expect(result.state, AppSettingsLoadState.migrated);
    expect(
      result.settings,
      const AppSettings(
        theme: AppThemePreference.light,
        playbackQuality: AppPlaybackQualityPreference.high,
        musicProvider: AppMusicProvider.qqMusic,
      ),
    );
  });

  test('unknown provider safely falls back to QQ Music', () async {
    final storage = _MemoryDocumentStorage(
      document: jsonEncode(<String, Object>{
        'schemaVersion': AppSettings.currentSchemaVersion,
        'theme': 'dark',
        'playbackQuality': 'lossless',
        'musicProvider': 'futureProvider',
        'localePreference': 'english',
        'colorSource': 'brand',
      }),
    );

    final result = await AppSettingsStore(storage: storage).load();

    expect(result.state, AppSettingsLoadState.migrated);
    expect(
      result.settings,
      const AppSettings(
        theme: AppThemePreference.dark,
        playbackQuality: AppPlaybackQualityPreference.lossless,
        musicProvider: AppMusicProvider.qqMusic,
        localePreference: AppLocalePreference.english,
      ),
    );
  });

  test('migrates version 3 documents to follow the system language', () async {
    final storage = _MemoryDocumentStorage(
      document: jsonEncode(<String, Object>{
        'schemaVersion': 3,
        'theme': 'dark',
        'playbackQuality': 'high',
        'musicProvider': 'netEaseCloudMusic',
      }),
    );

    final result = await AppSettingsStore(storage: storage).load();

    expect(result.state, AppSettingsLoadState.migrated);
    expect(
      result.settings,
      const AppSettings(
        theme: AppThemePreference.dark,
        playbackQuality: AppPlaybackQualityPreference.high,
        musicProvider: AppMusicProvider.netEaseCloudMusic,
        localePreference: AppLocalePreference.system,
      ),
    );
  });

  test(
    'unknown locale safely falls back to system and requests migration',
    () async {
      final storage = _MemoryDocumentStorage(
        document: jsonEncode(<String, Object>{
          'schemaVersion': AppSettings.currentSchemaVersion,
          'theme': 'light',
          'playbackQuality': 'standard',
          'musicProvider': 'qqMusic',
          'localePreference': 'futureLocale',
          'colorSource': 'brand',
        }),
      );

      final result = await AppSettingsStore(storage: storage).load();

      expect(result.state, AppSettingsLoadState.migrated);
      expect(result.settings.localePreference, AppLocalePreference.system);
      expect(result.settings.theme, AppThemePreference.light);
      expect(result.settings.musicProvider, AppMusicProvider.qqMusic);
    },
  );

  test('migrates version 4 documents to brand impression colors', () async {
    final storage = _MemoryDocumentStorage(
      document: jsonEncode(<String, Object>{
        'schemaVersion': 4,
        'theme': 'system',
        'playbackQuality': 'high',
        'musicProvider': 'netEaseCloudMusic',
        'localePreference': 'simplifiedChinese',
      }),
    );

    final result = await AppSettingsStore(storage: storage).load();

    expect(result.state, AppSettingsLoadState.migrated);
    expect(result.settings.colorSource, AppColorSourcePreference.brand);
    expect(result.settings.musicProvider, AppMusicProvider.netEaseCloudMusic);
    expect(
      result.settings.localePreference,
      AppLocalePreference.simplifiedChinese,
    );
  });

  test(
    'unknown color source safely falls back to brand and requests migration',
    () async {
      final storage = _MemoryDocumentStorage(
        document: jsonEncode(<String, Object>{
          'schemaVersion': AppSettings.currentSchemaVersion,
          'theme': 'dark',
          'colorSource': 'futurePalette',
          'playbackQuality': 'standard',
          'musicProvider': 'qqMusic',
          'localePreference': 'system',
        }),
      );

      final result = await AppSettingsStore(storage: storage).load();

      expect(result.state, AppSettingsLoadState.migrated);
      expect(result.settings.colorSource, AppColorSourcePreference.brand);
      expect(result.settings.theme, AppThemePreference.dark);
    },
  );

  test(
    'migrates version 5 to automatic lyrics without resetting system colors',
    () async {
      final storage = _MemoryDocumentStorage(
        document: jsonEncode(<String, Object>{
          'schemaVersion': 5,
          'theme': 'system',
          'colorSource': 'system',
          'playbackQuality': 'high',
          'musicProvider': 'netEaseCloudMusic',
          'localePreference': 'simplifiedChinese',
        }),
      );

      final result = await AppSettingsStore(storage: storage).load();

      expect(result.state, AppSettingsLoadState.migrated);
      expect(result.settings.colorSource, AppColorSourcePreference.system);
      expect(result.settings.lyricAuxiliaryMode, LyricAuxiliaryMode.auto);
      expect(
        result.settings.playbackQuality,
        AppPlaybackQualityPreference.high,
      );
    },
  );

  test(
    'unknown lyric mode falls back to auto without resetting settings',
    () async {
      final storage = _MemoryDocumentStorage(
        document: jsonEncode(<String, Object>{
          'schemaVersion': AppSettings.currentSchemaVersion,
          'theme': 'dark',
          'colorSource': 'system',
          'playbackQuality': 'lossless',
          'lyricAuxiliaryMode': 'futureMode',
          'musicProvider': 'netEaseCloudMusic',
          'localePreference': 'simplifiedChinese',
        }),
      );

      final result = await AppSettingsStore(storage: storage).load();

      expect(result.state, AppSettingsLoadState.migrated);
      expect(result.settings.lyricAuxiliaryMode, LyricAuxiliaryMode.auto);
      expect(result.settings.colorSource, AppColorSourcePreference.system);
      expect(
        result.settings.playbackQuality,
        AppPlaybackQualityPreference.lossless,
      );
      expect(result.settings.musicProvider, AppMusicProvider.netEaseCloudMusic);
    },
  );

  test(
    'uses defaults without rewriting malformed or future documents',
    () async {
      for (final (document, state) in <(String, AppSettingsLoadState)>[
        ('not-json', AppSettingsLoadState.invalidDocument),
        ('[]', AppSettingsLoadState.invalidDocument),
        (
          jsonEncode(<String, Object>{'schemaVersion': 1, 'theme': 'sepia'}),
          AppSettingsLoadState.invalidDocument,
        ),
        (
          jsonEncode(<String, Object>{
            'schemaVersion': AppSettings.currentSchemaVersion + 1,
            'theme': 'dark',
          }),
          AppSettingsLoadState.unsupportedVersion,
        ),
        (
          jsonEncode(<String, Object>{
            'schemaVersion': 2,
            'theme': 'dark',
            'playbackQuality': 'ultra',
          }),
          AppSettingsLoadState.invalidDocument,
        ),
      ]) {
        final storage = _MemoryDocumentStorage(document: document);

        final result = await AppSettingsStore(storage: storage).load();

        expect(result.state, state);
        expect(result.settings, AppSettings.defaults);
        expect(storage.document, document);
        expect(storage.writeCount, 0);
      }
    },
  );

  test(
    'reset deletes only the settings document through its storage edge',
    () async {
      final storage = _MemoryDocumentStorage(document: 'stored');
      final store = AppSettingsStore(storage: storage);

      expect(await store.reset(), AppSettingsWriteResult.saved);

      expect(storage.document, isNull);
      expect(storage.deleteCount, 1);
    },
  );

  test('maps read write and reset storage failures without throwing', () async {
    final readFailure = AppSettingsStore(
      storage: _MemoryDocumentStorage(failRead: true),
    );
    final writeFailure = AppSettingsStore(
      storage: _MemoryDocumentStorage(failWrite: true),
    );
    final resetFailure = AppSettingsStore(
      storage: _MemoryDocumentStorage(failDelete: true),
    );

    final loaded = await readFailure.load();
    expect(loaded.state, AppSettingsLoadState.storageUnavailable);
    expect(loaded.settings, AppSettings.defaults);
    expect(
      await writeFailure.save(
        const AppSettings(theme: AppThemePreference.dark),
      ),
      AppSettingsWriteResult.storageUnavailable,
    );
    expect(
      await resetFailure.reset(),
      AppSettingsWriteResult.storageUnavailable,
    );
  });

  test('serializes settings mutations in request order', () async {
    final storage = _ControlledDocumentStorage();
    final store = AppSettingsStore(storage: storage);
    final first = store.save(const AppSettings(theme: AppThemePreference.dark));
    final second = store.save(
      const AppSettings(
        theme: AppThemePreference.dark,
        playbackQuality: AppPlaybackQualityPreference.lossless,
      ),
    );

    await _flushTasks();
    expect(storage.writes, hasLength(1));

    storage.complete(0);
    expect(await first, AppSettingsWriteResult.saved);
    await _flushTasks();
    expect(storage.writes, hasLength(2));

    storage.complete(1);
    expect(await second, AppSettingsWriteResult.saved);
    expect(storage.document, contains('"playbackQuality":"lossless"'));
  });
}

Future<void> _flushTasks() => Future<void>.delayed(Duration.zero);

class _MemoryDocumentStorage implements AppSettingsDocumentStorage {
  _MemoryDocumentStorage({
    this.document,
    this.failRead = false,
    this.failWrite = false,
    this.failDelete = false,
  });

  String? document;
  final bool failRead;
  final bool failWrite;
  final bool failDelete;
  int writeCount = 0;
  int deleteCount = 0;

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('synthetic read failure');
    return document;
  }

  @override
  Future<void> write(String document) async {
    if (failWrite) throw StateError('synthetic write failure');
    writeCount += 1;
    this.document = document;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('synthetic delete failure');
    deleteCount += 1;
    document = null;
  }
}

class _ControlledDocumentStorage implements AppSettingsDocumentStorage {
  String? document;
  final List<String> writes = [];
  final List<Completer<void>> _completions = [];

  @override
  Future<String?> read() async => document;

  @override
  Future<void> write(String document) async {
    writes.add(document);
    final completion = Completer<void>();
    _completions.add(completion);
    await completion.future;
    this.document = document;
  }

  @override
  Future<void> delete() async => document = null;

  void complete(int index) => _completions[index].complete();
}
