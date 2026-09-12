import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/l10n/app_locale.dart';
import 'package:flutterustmusic/settings/app_settings.dart';

void main() {
  test('manual locale preferences map to the requested supported locale', () {
    expect(materialLocaleForPreference(AppLocalePreference.system), isNull);
    expect(
      materialLocaleForPreference(AppLocalePreference.english),
      englishAppLocale,
    );
    expect(
      materialLocaleForPreference(AppLocalePreference.simplifiedChinese),
      simplifiedChineseAppLocale,
    );
  });

  test('system locale resolution is explicit and deterministic', () {
    Locale resolve(Locale locale) => resolveSupportedAppLocale(
      [locale],
      const [englishAppLocale, simplifiedChineseAppLocale],
    );

    expect(resolve(const Locale('en', 'GB')), englishAppLocale);
    expect(
      resolve(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')),
      simplifiedChineseAppLocale,
    );
    expect(resolve(const Locale('zh', 'CN')), simplifiedChineseAppLocale);
    expect(resolve(const Locale('zh', 'SG')), simplifiedChineseAppLocale);
    expect(resolve(const Locale('zh')), simplifiedChineseAppLocale);
    expect(
      resolve(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
      englishAppLocale,
    );
    expect(resolve(const Locale('zh', 'TW')), englishAppLocale);
    expect(resolve(const Locale('zh', 'HK')), englishAppLocale);
    expect(resolve(const Locale('zh', 'MO')), englishAppLocale);
    expect(resolve(const Locale('fr', 'FR')), englishAppLocale);
    expect(
      resolveSupportedAppLocale(null, const [englishAppLocale]),
      englishAppLocale,
    );
  });
}
