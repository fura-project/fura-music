import 'dart:convert';

import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSettingsLoadState {
  defaults,
  stored,
  invalidDocument,
  unsupportedVersion,
  storageUnavailable,
}

class AppSettingsLoadResult {
  const AppSettingsLoadResult({required this.settings, required this.state});

  final AppSettings settings;
  final AppSettingsLoadState state;
}

enum AppSettingsWriteResult { saved, storageUnavailable }

abstract interface class AppSettingsDocumentStorage {
  Future<String?> read();

  Future<void> write(String document);

  Future<void> delete();
}

class SharedPreferencesAppSettingsDocumentStorage
    implements AppSettingsDocumentStorage {
  SharedPreferencesAppSettingsDocumentStorage({
    SharedPreferencesAsync? storage,
    this.documentKey = defaultDocumentKey,
  }) : _storage = storage ?? SharedPreferencesAsync();

  static const defaultDocumentKey = 'flutterustmusic.app_settings';

  final SharedPreferencesAsync _storage;
  final String documentKey;

  @override
  Future<String?> read() => _storage.getString(documentKey);

  @override
  Future<void> write(String document) =>
      _storage.setString(documentKey, document);

  @override
  Future<void> delete() => _storage.remove(documentKey);
}

class AppSettingsStore {
  AppSettingsStore({AppSettingsDocumentStorage? storage})
    : _storage = storage ?? SharedPreferencesAppSettingsDocumentStorage();

  final AppSettingsDocumentStorage _storage;

  Future<AppSettingsLoadResult> load() async {
    final String? document;
    try {
      document = await _storage.read();
    } on Object {
      return const AppSettingsLoadResult(
        settings: AppSettings.defaults,
        state: AppSettingsLoadState.storageUnavailable,
      );
    }

    if (document == null) {
      return const AppSettingsLoadResult(
        settings: AppSettings.defaults,
        state: AppSettingsLoadState.defaults,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(document);
    } on FormatException {
      return const AppSettingsLoadResult(
        settings: AppSettings.defaults,
        state: AppSettingsLoadState.invalidDocument,
      );
    }
    if (decoded is! Map<String, Object?>) {
      return const AppSettingsLoadResult(
        settings: AppSettings.defaults,
        state: AppSettingsLoadState.invalidDocument,
      );
    }

    final version = decoded['schemaVersion'];
    if (version is! int) {
      return const AppSettingsLoadResult(
        settings: AppSettings.defaults,
        state: AppSettingsLoadState.invalidDocument,
      );
    }
    if (version != AppSettings.currentSchemaVersion) {
      return const AppSettingsLoadResult(
        settings: AppSettings.defaults,
        state: AppSettingsLoadState.unsupportedVersion,
      );
    }

    final themeName = decoded['theme'];
    if (themeName is! String) {
      return const AppSettingsLoadResult(
        settings: AppSettings.defaults,
        state: AppSettingsLoadState.invalidDocument,
      );
    }
    final theme = AppThemePreference.values
        .where((candidate) => candidate.name == themeName)
        .firstOrNull;
    if (theme == null) {
      return const AppSettingsLoadResult(
        settings: AppSettings.defaults,
        state: AppSettingsLoadState.invalidDocument,
      );
    }

    return AppSettingsLoadResult(
      settings: AppSettings(theme: theme),
      state: AppSettingsLoadState.stored,
    );
  }

  Future<AppSettingsWriteResult> save(AppSettings settings) async {
    final document = jsonEncode(<String, Object>{
      'schemaVersion': AppSettings.currentSchemaVersion,
      'theme': settings.theme.name,
    });
    try {
      await _storage.write(document);
      return AppSettingsWriteResult.saved;
    } on Object {
      return AppSettingsWriteResult.storageUnavailable;
    }
  }

  Future<AppSettingsWriteResult> reset() async {
    try {
      await _storage.delete();
      return AppSettingsWriteResult.saved;
    } on Object {
      return AppSettingsWriteResult.storageUnavailable;
    }
  }
}
