import 'package:flutter/material.dart';

enum AppThemePreference { system, light, dark }

enum AppPlaybackQualityPreference { standard, high }

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
  });

  static const currentSchemaVersion = 2;
  static const defaults = AppSettings(
    theme: AppThemePreference.system,
    playbackQuality: AppPlaybackQualityPreference.standard,
  );

  final AppThemePreference theme;
  final AppPlaybackQualityPreference playbackQuality;

  AppSettings copyWith({
    AppThemePreference? theme,
    AppPlaybackQualityPreference? playbackQuality,
  }) => AppSettings(
    theme: theme ?? this.theme,
    playbackQuality: playbackQuality ?? this.playbackQuality,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.theme == theme &&
      other.playbackQuality == playbackQuality;

  @override
  int get hashCode => Object.hash(theme, playbackQuality);

  @override
  String toString() =>
      'AppSettings(theme: ${theme.name}, '
      'playbackQuality: ${playbackQuality.name})';
}
