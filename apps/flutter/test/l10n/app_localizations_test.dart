import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/l10n/app_locale.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';

void main() {
  test(
    'every generated locale loads with the intended language family',
    () async {
      final english = await AppLocalizations.delegate.load(englishAppLocale);
      final genericChinese = await AppLocalizations.delegate.load(
        const Locale('zh'),
      );
      final simplifiedChinese = await AppLocalizations.delegate.load(
        simplifiedChineseAppLocale,
      );

      expect(english.settingsTitle, 'Settings');
      expect(genericChinese.settingsTitle, '设置');
      expect(simplifiedChinese.settingsTitle, '设置');
      expect(simplifiedChinese.appTitle, 'fura music');
    },
  );

  test('important placeholders preserve upstream values in both locales', () {
    final english = lookupAppLocalizations(englishAppLocale);
    final chinese = lookupAppLocalizations(simplifiedChineseAppLocale);

    expect(
      english.authSignInTitle('Provider Fixture'),
      'Sign in to Provider Fixture',
    );
    expect(chinese.authSignInTitle('Provider Fixture'), '登录 Provider Fixture');
    expect(
      english.playbackQualityFallback('SQ', 'HQ'),
      'HQ is unavailable for this track. Playing SQ instead.',
    );
    expect(chinese.playbackQualityFallback('SQ', 'HQ'), '此歌曲不支持 HQ，已改用 SQ。');
    expect(
      chinese.playbackSourceUnavailable('Provider Fixture'),
      'Provider Fixture 未提供可播放的音源。',
    );
    expect(
      chinese.commonTrackSemantics('Upstream Artist', 'Upstream Track'),
      'Upstream Track，Upstream Artist',
    );
  });

  test('English plurals and Chinese count messages remain semantic', () {
    final english = lookupAppLocalizations(englishAppLocale);
    final chinese = lookupAppLocalizations(simplifiedChineseAppLocale);

    expect(english.albumTrackCount(1), '1 track');
    expect(english.albumTrackCount(2), '2 tracks');
    expect(english.queueTrackCount(1), '1 track');
    expect(english.queueTrackCount(4), '4 tracks');
    expect(english.searchResultCount(1, 'aurora'), '1 result for “aurora”');
    expect(english.searchResultCount(3, 'aurora'), '3 results for “aurora”');
    expect(chinese.albumTrackCount(2), '2 首歌曲');
    expect(chinese.searchResultCount(3, 'aurora'), '找到 3 个与“aurora”相关的结果');
  });

  test('provider settings auth playback and error copy are locale-owned', () {
    final english = lookupAppLocalizations(englishAppLocale);
    final chinese = lookupAppLocalizations(simplifiedChineseAppLocale);

    expect(english.providerQqMusic, 'QQ Music');
    expect(english.providerNeteaseCloudMusic, 'NetEase Cloud Music');
    expect(chinese.providerQqMusic, 'QQ 音乐');
    expect(chinese.providerNeteaseCloudMusic, '网易云音乐');
    expect(chinese.settingsLanguageLabel, '语言');
    expect(chinese.settingsLanguageFollowSystem, '跟随系统');
    expect(chinese.authProviderQrSemantics('网易云音乐'), '网易云音乐 登录二维码');
    expect(chinese.playbackPause, '暂停');
    expect(chinese.playbackShowQueue, '显示播放队列');
    expect(chinese.settingsSaveFailure, '无法在此设备上保存设置。');
    expect(chinese.searchNoTracksTitle, '未找到歌曲');
  });

  test('translated ARB keeps key and placeholder parity with the template', () {
    final english = _readArb('lib/l10n/app_en.arb');
    final chinese = _readArb('lib/l10n/app_zh.arb');
    final englishMessages = _messages(english);
    final chineseMessages = _messages(chinese);

    expect(chineseMessages.keys.toSet(), englishMessages.keys.toSet());
    for (final key in englishMessages.keys) {
      expect(
        _placeholderNames(chineseMessages[key]!),
        _placeholderNames(englishMessages[key]!),
        reason: 'Placeholder mismatch for $key',
      );
    }
  });

  test('every dynamic template message documents its placeholders', () {
    final english = _readArb('lib/l10n/app_en.arb');
    final englishMessages = _messages(english);

    for (final entry in englishMessages.entries) {
      final placeholders = _placeholderNames(entry.value);
      if (placeholders.isEmpty) continue;
      final metadata = english['@${entry.key}'];
      expect(metadata, isA<Map<String, Object?>>(), reason: entry.key);
      final typedMetadata = metadata! as Map<String, Object?>;
      expect(
        typedMetadata['description'],
        isA<String>().having(
          (value) => value.trim(),
          'description',
          isNotEmpty,
        ),
        reason: entry.key,
      );
      final declared = (typedMetadata['placeholders']! as Map<String, Object?>)
          .keys
          .toSet();
      expect(declared, placeholders, reason: entry.key);
    }
  });

  test('translator-sensitive static messages include metadata', () {
    final english = _readArb('lib/l10n/app_en.arb');
    const keys = [
      'providerQqMusic',
      'providerNeteaseCloudMusic',
      'authQqQrSemantics',
      'authWechatQrSemantics',
      'settingsLanguageSearchKeywords',
      'settingsPlaybackSearchKeywords',
      'playbackQualityMenuLossless',
      'playbackQualityFallbackSuffix',
      'librarySignOutConfirmTitle',
      'queueClearTitle',
      'recentEmptyTitle',
      'nowPlayingEmptyTitle',
    ];

    for (final key in keys) {
      expect(
        english['@$key'],
        isA<Map<String, Object?>>().having(
          (metadata) => metadata['description'],
          'description',
          isA<String>().having(
            (description) => description.trim(),
            'non-empty description',
            isNotEmpty,
          ),
        ),
        reason: key,
      );
    }
  });
}

Map<String, Object?> _readArb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Map<String, String> _messages(Map<String, Object?> arb) => {
  for (final entry in arb.entries)
    if (!entry.key.startsWith('@')) entry.key: entry.value! as String,
};

Set<String> _placeholderNames(String message) =>
    RegExp(r'\{([A-Za-z][A-Za-z0-9]*)(?:[,}])')
        .allMatches(message)
        .map((match) => match.group(1)!)
        .toSet();
