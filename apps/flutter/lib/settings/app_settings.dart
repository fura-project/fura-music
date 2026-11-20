import 'package:flutter/material.dart';

enum AppThemePreference { system, light, dark }

enum AppColorSourcePreference { system, brand }

enum AppVisualStyle { material, editorial }

enum AppPlaybackQualityPreference { standard, high, lossless }

enum LyricAuxiliaryMode { auto, translation, romanization, off }

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
    this.visualStyle = AppVisualStyle.material,
    this.playbackQuality = AppPlaybackQualityPreference.standard,
    this.lyricAuxiliaryMode = LyricAuxiliaryMode.auto,
    this.musicProvider = AppMusicProvider.qqMusic,
    this.localePreference = AppLocalePreference.system,
  });

  static const currentSchemaVersion = 7;
  static const defaults = AppSettings(
    theme: AppThemePreference.system,
    colorSource: AppColorSourcePreference.brand,
    visualStyle: AppVisualStyle.material,
    playbackQuality: AppPlaybackQualityPreference.standard,
    lyricAuxiliaryMode: LyricAuxiliaryMode.auto,
    musicProvider: AppMusicProvider.qqMusic,
    localePreference: AppLocalePreference.system,
  );

  final AppThemePreference theme;
  final AppColorSourcePreference colorSource;
  final AppVisualStyle visualStyle;
  final AppPlaybackQualityPreference playbackQuality;
  final LyricAuxiliaryMode lyricAuxiliaryMode;
  final AppMusicProvider musicProvider;
  final AppLocalePreference localePreference;

  AppSettings copyWith({
    AppThemePreference? theme,
    AppColorSourcePreference? colorSource,
    AppVisualStyle? visualStyle,
    AppPlaybackQualityPreference? playbackQuality,
    LyricAuxiliaryMode? lyricAuxiliaryMode,
    AppMusicProvider? musicProvider,
    AppLocalePreference? localePreference,
  }) => AppSettings(
    theme: theme ?? this.theme,
    colorSource: colorSource ?? this.colorSource,
    visualStyle: visualStyle ?? this.visualStyle,
    playbackQuality: playbackQuality ?? this.playbackQuality,
    lyricAuxiliaryMode: lyricAuxiliaryMode ?? this.lyricAuxiliaryMode,
    musicProvider: musicProvider ?? this.musicProvider,
    localePreference: localePreference ?? this.localePreference,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.theme == theme &&
      other.colorSource == colorSource &&
      other.visualStyle == visualStyle &&
      other.playbackQuality == playbackQuality &&
      other.lyricAuxiliaryMode == lyricAuxiliaryMode &&
      other.musicProvider == musicProvider &&
      other.localePreference == localePreference;

  @override
  int get hashCode => Object.hash(
    theme,
    colorSource,
    visualStyle,
    playbackQuality,
    lyricAuxiliaryMode,
    musicProvider,
    localePreference,
  );

  @override
  String toString() =>
      'AppSettings(theme: ${theme.name}, '
      'colorSource: ${colorSource.name}, '
      'visualStyle: ${visualStyle.name}, '
      'playbackQuality: ${playbackQuality.name}, '
      'lyricAuxiliaryMode: ${lyricAuxiliaryMode.name}, '
      'musicProvider: ${musicProvider.name}, '
      'localePreference: ${localePreference.name})';
}
