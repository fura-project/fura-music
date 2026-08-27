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

  test('round trips every supported theme and playback quality', () async {
    for (final theme in AppThemePreference.values) {
      for (final playbackQuality in AppPlaybackQualityPreference.values) {
        final storage = _MemoryDocumentStorage();
        final store = AppSettingsStore(storage: storage);

        expect(
          await store.save(
            AppSettings(theme: theme, playbackQuality: playbackQuality),
          ),
          AppSettingsWriteResult.saved,
        );
        final stored = jsonDecode(storage.document!) as Map<String, dynamic>;
        expect(stored['schemaVersion'], AppSettings.currentSchemaVersion);
        expect(stored['theme'], theme.name);
        expect(stored['playbackQuality'], playbackQuality.name);

        final loaded = await store.load();
        expect(loaded.state, AppSettingsLoadState.stored);
        expect(
          loaded.settings,
          AppSettings(theme: theme, playbackQuality: playbackQuality),
        );
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
          jsonEncode(<String, Object>{'schemaVersion': 3, 'theme': 'dark'}),
          AppSettingsLoadState.unsupportedVersion,
        ),
        (
          jsonEncode(<String, Object>{
            'schemaVersion': 2,
            'theme': 'dark',
            'playbackQuality': 'lossless',
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
}

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
