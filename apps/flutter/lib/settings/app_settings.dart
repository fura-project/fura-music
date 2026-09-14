import 'package:flutter/material.dart';

enum AppThemePreference { system, light, dark }

enum AppColorSourcePreference { system, brand }

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
    this.colorSource = AppColorSourcePreference.brand,
    this.playbackQuality = AppPlaybackQualityPreference.standard,
    this.musicProvider = AppMusicProvider.qqMusic,
    this.localePreference = AppLocalePreference.system,
  });

  static const currentSchemaVersion = 5;
  static const defaults = AppSettings(
    theme: AppThemePreference.system,
    colorSource: AppColorSourcePreference.brand,
    playbackQuality: AppPlaybackQualityPreference.standard,
    musicProvider: AppMusicProvider.qqMusic,
    localePreference: AppLocalePreference.system,
  );

  final AppThemePreference theme;
  final AppColorSourcePreference colorSource;
  final AppPlaybackQualityPreference playbackQuality;
  final AppMusicProvider musicProvider;
  final AppLocalePreference localePreference;

  AppSettings copyWith({
    AppThemePreference? theme,
    AppColorSourcePreference? colorSource,
    AppPlaybackQualityPreference? playbackQuality,
    AppMusicProvider? musicProvider,
    AppLocalePreference? localePreference,
  }) => AppSettings(
    theme: theme ?? this.theme,
    colorSource: colorSource ?? this.colorSource,
    playbackQuality: playbackQuality ?? this.playbackQuality,
    musicProvider: musicProvider ?? this.musicProvider,
    localePreference: localePreference ?? this.localePreference,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.theme == theme &&
      other.colorSource == colorSource &&
      other.playbackQuality == playbackQuality &&
      other.musicProvider == musicProvider &&
      other.localePreference == localePreference;

  @override
  int get hashCode => Object.hash(
    theme,
    colorSource,
    playbackQuality,
    musicProvider,
    localePreference,
  );

  @override
  String toString() =>
      'AppSettings(theme: ${theme.name}, '
      'colorSource: ${colorSource.name}, '
      'playbackQuality: ${playbackQuality.name}, '
      'musicProvider: ${musicProvider.name}, '
      'localePreference: ${localePreference.name})';
}
