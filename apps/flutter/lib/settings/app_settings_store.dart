import 'dart:convert';

import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSettingsLoadState {
  defaults,
  stored,
  migrated,
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
  Future<void> _mutationTail = Future.value();

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
    if (version < 1 || version > AppSettings.currentSchemaVersion) {
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

    final playbackQualityName = decoded['playbackQuality'];
    final playbackQuality = version == 1
        ? AppPlaybackQualityPreference.standard
        : AppPlaybackQualityPreference.values
              .where((candidate) => candidate.name == playbackQualityName)
              .firstOrNull;
    if (playbackQuality == null) {
      return const AppSettingsLoadResult(
        settings: AppSettings.defaults,
        state: AppSettingsLoadState.invalidDocument,
      );
    }

    final providerName = decoded['musicProvider'];
    final musicProvider = version < 3
        ? AppMusicProvider.qqMusic
        : AppMusicProvider.values
                  .where((candidate) => candidate.name == providerName)
                  .firstOrNull ??
              AppMusicProvider.qqMusic;
    final localeName = decoded['localePreference'];
    final localePreference = version < 4
        ? AppLocalePreference.system
        : AppLocalePreference.values
                  .where((candidate) => candidate.name == localeName)
                  .firstOrNull ??
              AppLocalePreference.system;
    final colorSourceName = decoded['colorSource'];
    final colorSource = version < 5
        ? AppColorSourcePreference.brand
        : AppColorSourcePreference.values
                  .where((candidate) => candidate.name == colorSourceName)
                  .firstOrNull ??
              AppColorSourcePreference.brand;
    final lyricAuxiliaryModeName = decoded['lyricAuxiliaryMode'];
    final lyricAuxiliaryMode = version < 6
        ? LyricAuxiliaryMode.auto
        : LyricAuxiliaryMode.values
                  .where(
                    (candidate) => candidate.name == lyricAuxiliaryModeName,
                  )
                  .firstOrNull ??
              LyricAuxiliaryMode.auto;
    final migrated =
        version < AppSettings.currentSchemaVersion ||
        (version >= 3 &&
            !AppMusicProvider.values.any(
              (candidate) => candidate.name == providerName,
            )) ||
        (version >= 4 &&
            !AppLocalePreference.values.any(
              (candidate) => candidate.name == localeName,
            )) ||
        (version >= 5 &&
            !AppColorSourcePreference.values.any(
              (candidate) => candidate.name == colorSourceName,
            )) ||
        (version >= 6 &&
            !LyricAuxiliaryMode.values.any(
              (candidate) => candidate.name == lyricAuxiliaryModeName,
            ));

    return AppSettingsLoadResult(
      settings: AppSettings(
        theme: theme,
        colorSource: colorSource,
        playbackQuality: playbackQuality,
        lyricAuxiliaryMode: lyricAuxiliaryMode,
        musicProvider: musicProvider,
        localePreference: localePreference,
      ),
      state: migrated
          ? AppSettingsLoadState.migrated
          : AppSettingsLoadState.stored,
    );
  }

  Future<AppSettingsWriteResult> save(AppSettings settings) =>
      _serializeMutation(() async {
        final document = jsonEncode(<String, Object>{
          'schemaVersion': AppSettings.currentSchemaVersion,
          'theme': settings.theme.name,
          'colorSource': settings.colorSource.name,
          'playbackQuality': settings.playbackQuality.name,
          'lyricAuxiliaryMode': settings.lyricAuxiliaryMode.name,
          'musicProvider': settings.musicProvider.name,
          'localePreference': settings.localePreference.name,
        });
        try {
          await _storage.write(document);
          return AppSettingsWriteResult.saved;
        } on Object {
          return AppSettingsWriteResult.storageUnavailable;
        }
      });

  Future<AppSettingsWriteResult> reset() => _serializeMutation(() async {
    try {
      await _storage.delete();
      return AppSettingsWriteResult.saved;
    } on Object {
      return AppSettingsWriteResult.storageUnavailable;
    }
  });

  Future<T> _serializeMutation<T>(Future<T> Function() mutation) {
    final result = _mutationTail.then((_) => mutation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
