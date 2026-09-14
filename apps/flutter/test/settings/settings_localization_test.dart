import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/settings_page.dart';

void main() {
  final english = lookupAppLocalizations(const Locale('en'));
  final chinese = lookupAppLocalizations(
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  );

  test('English settings search indexes localized copy and summaries', () {
    const settings = AppSettings(
      theme: AppThemePreference.dark,
      musicProvider: AppMusicProvider.netEaseCloudMusic,
      localePreference: AppLocalePreference.english,
      playbackQuality: AppPlaybackQualityPreference.lossless,
    );

    expect(
      SettingsSection.appearance.matches('theme', settings, english),
      true,
    );
    expect(
      SettingsSection.appearance.matches('monet', settings, english),
      true,
    );
    expect(
      SettingsSection.musicService.matches('provider', settings, english),
      true,
    );
    expect(
      SettingsSection.musicService.matches('netease', settings, english),
      true,
    );
    expect(
      SettingsSection.language.matches('english', settings, english),
      true,
    );
    expect(
      SettingsSection.playback.matches('quality', settings, english),
      true,
    );
    expect(
      SettingsSection.playback.matches('lossless quality', settings, english),
      true,
    );
  });

  test('Chinese settings search indexes localized copy and summaries', () {
    const settings = AppSettings(
      theme: AppThemePreference.dark,
      musicProvider: AppMusicProvider.netEaseCloudMusic,
      localePreference: AppLocalePreference.system,
      playbackQuality: AppPlaybackQualityPreference.lossless,
    );

    expect(SettingsSection.appearance.matches('主题', settings, chinese), true);
    expect(SettingsSection.appearance.matches('莫奈', settings, chinese), true);
    expect(SettingsSection.musicService.matches('音源', settings, chinese), true);
    expect(
      SettingsSection.musicService.matches('网易云', settings, chinese),
      true,
    );
    expect(SettingsSection.language.matches('语言', settings, chinese), true);
    expect(SettingsSection.language.matches('跟随系统', settings, chinese), true);
    expect(SettingsSection.playback.matches('音质', settings, chinese), true);
  });
}
