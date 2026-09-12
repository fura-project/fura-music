import 'package:flutter/material.dart';

enum AppThemePreference { system, light, dark }

enum AppPlaybackQualityPreference { standard, high, lossless }

enum AppMusicProvider { qqMusic, netEaseCloudMusic }

enum AppLocalePreference { system, english, simplifiedChinese }

extension AppMusicProviderPresentation on AppMusicProvider {
  String get providerId => switch (this) {
    AppMusicProvider.qqMusic => 'qq-music',
    AppMusicProvider.netEaseCloudMusic => 'netease-cloud-music',
  };
}

extension AppThemePreferenceMaterial on AppThemePreference {
  ThemeMode get materialThemeMode => switch (this) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };
}

class AppSettings {
  const AppSettings({
    required this.theme,
    this.playbackQuality = AppPlaybackQualityPreference.standard,
    this.musicProvider = AppMusicProvider.qqMusic,
    this.localePreference = AppLocalePreference.system,
  });

  static const currentSchemaVersion = 4;
  static const defaults = AppSettings(
    theme: AppThemePreference.system,
    playbackQuality: AppPlaybackQualityPreference.standard,
    musicProvider: AppMusicProvider.qqMusic,
    localePreference: AppLocalePreference.system,
  );

  final AppThemePreference theme;
  final AppPlaybackQualityPreference playbackQuality;
  final AppMusicProvider musicProvider;
  final AppLocalePreference localePreference;

  AppSettings copyWith({
    AppThemePreference? theme,
    AppPlaybackQualityPreference? playbackQuality,
    AppMusicProvider? musicProvider,
    AppLocalePreference? localePreference,
  }) => AppSettings(
    theme: theme ?? this.theme,
    playbackQuality: playbackQuality ?? this.playbackQuality,
    musicProvider: musicProvider ?? this.musicProvider,
    localePreference: localePreference ?? this.localePreference,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.theme == theme &&
      other.playbackQuality == playbackQuality &&
      other.musicProvider == musicProvider &&
      other.localePreference == localePreference;

  @override
  int get hashCode =>
      Object.hash(theme, playbackQuality, musicProvider, localePreference);

  @override
  String toString() =>
      'AppSettings(theme: ${theme.name}, '
      'playbackQuality: ${playbackQuality.name}, '
      'musicProvider: ${musicProvider.name}, '
      'localePreference: ${localePreference.name})';
}
