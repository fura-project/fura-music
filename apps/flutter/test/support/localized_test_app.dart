import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_locale.dart';

Widget localizedTestApp({
  required Widget home,
  Locale locale = englishAppLocale,
  ThemeData? theme,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: theme,
  home: home,
);

extension LocalizedWidgetTester on WidgetTester {
  Future<void> pumpLocalizedApp(
    Widget home, {
    Locale locale = englishAppLocale,
    ThemeData? theme,
  }) => pumpWidget(localizedTestApp(home: home, locale: locale, theme: theme));
}
