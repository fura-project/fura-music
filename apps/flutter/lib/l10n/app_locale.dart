import 'package:flutter/widgets.dart';
import 'package:flutterustmusic/settings/app_settings.dart';

const englishAppLocale = Locale('en');
const simplifiedChineseAppLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hans',
);

Locale? materialLocaleForPreference(AppLocalePreference preference) =>
    switch (preference) {
      AppLocalePreference.system => null,
      AppLocalePreference.english => englishAppLocale,
      AppLocalePreference.simplifiedChinese => simplifiedChineseAppLocale,
    };

Locale resolveSupportedAppLocale(
  List<Locale>? preferredLocales,
  Iterable<Locale> supportedLocales,
) {
  final preferred = preferredLocales?.firstOrNull;
  if (preferred == null) return englishAppLocale;
  final language = preferred.languageCode.toLowerCase();
  if (language == 'en') return englishAppLocale;
  if (language != 'zh') return englishAppLocale;

  final script = preferred.scriptCode?.toLowerCase();
  if (script == 'hant') return englishAppLocale;
  if (script == 'hans') return simplifiedChineseAppLocale;

  final country = preferred.countryCode?.toUpperCase();
  if (country == 'TW' || country == 'HK' || country == 'MO') {
    return englishAppLocale;
  }
  if (country == 'CN' || country == 'SG') {
    return simplifiedChineseAppLocale;
  }

  // Generic Chinese is resolved to the only supported Chinese script.
  return simplifiedChineseAppLocale;
}
