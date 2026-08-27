import 'package:flutter/material.dart';

enum AppThemePreference { system, light, dark }

extension AppThemePreferenceMaterial on AppThemePreference {
  ThemeMode get materialThemeMode => switch (this) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };
}

class AppSettings {
  const AppSettings({required this.theme});

  static const currentSchemaVersion = 1;
  static const defaults = AppSettings(theme: AppThemePreference.system);

  final AppThemePreference theme;

  AppSettings copyWith({AppThemePreference? theme}) =>
      AppSettings(theme: theme ?? this.theme);

  @override
  bool operator ==(Object other) =>
      other is AppSettings && other.theme == theme;

  @override
  int get hashCode => theme.hashCode;

  @override
  String toString() => 'AppSettings(theme: ${theme.name})';
}
