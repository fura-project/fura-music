import 'package:flutter/material.dart';

enum AppThemePreference { system, light, dark }

enum AppPlaybackQualityPreference { standard, high, lossless }

enum AppMusicProvider { qqMusic, netEaseCloudMusic }

extension AppMusicProviderPresentation on AppMusicProvider {
  String get providerId => switch (this) {
    AppMusicProvider.qqMusic => 'qq-music',
    AppMusicProvider.netEaseCloudMusic => 'netease-cloud-music',
  };

  String get displayName => switch (this) {
    AppMusicProvider.qqMusic => 'QQ Music',
    AppMusicProvider.netEaseCloudMusic => 'NetEase Cloud Music',
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
  });

  static const currentSchemaVersion = 3;
  static const defaults = AppSettings(
    theme: AppThemePreference.system,
    playbackQuality: AppPlaybackQualityPreference.standard,
    musicProvider: AppMusicProvider.qqMusic,
  );

  final AppThemePreference theme;
  final AppPlaybackQualityPreference playbackQuality;
  final AppMusicProvider musicProvider;

  AppSettings copyWith({
    AppThemePreference? theme,
    AppPlaybackQualityPreference? playbackQuality,
    AppMusicProvider? musicProvider,
  }) => AppSettings(
    theme: theme ?? this.theme,
    playbackQuality: playbackQuality ?? this.playbackQuality,
    musicProvider: musicProvider ?? this.musicProvider,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.theme == theme &&
      other.playbackQuality == playbackQuality &&
      other.musicProvider == musicProvider;

  @override
  int get hashCode => Object.hash(theme, playbackQuality, musicProvider);

  @override
  String toString() =>
      'AppSettings(theme: ${theme.name}, '
      'playbackQuality: ${playbackQuality.name}, '
      'musicProvider: ${musicProvider.name})';
}
