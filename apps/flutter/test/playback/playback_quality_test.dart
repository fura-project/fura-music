import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_quality.dart';
import 'package:flutterustmusic/settings/app_settings.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('maps every persisted preference to playback and presentation', () {
    expect(
      AppPlaybackQualityPreference.standard.audioPreference,
      PlaybackAudioQualityPreference.standard,
    );
    expect(
      AppPlaybackQualityPreference.high.audioPreference,
      PlaybackAudioQualityPreference.high,
    );
    expect(
      AppPlaybackQualityPreference.lossless.audioPreference,
      PlaybackAudioQualityPreference.lossless,
    );

    expect(AppPlaybackQualityPreference.standard.shortLabel, 'STD');
    expect(
      AppPlaybackQualityPreference.high.localizedMenuLabel(l10n),
      contains('320 kbps'),
    );
    expect(
      AppPlaybackQualityPreference.lossless.localizedDisplayLabel(l10n),
      'SQ',
    );
  });

  test('reports exact, fallback, and next-Track quality states', () {
    expect(
      localizedPlaybackQualityTooltip(
        l10n,
        AppPlaybackQualityPreference.lossless,
        PlaybackAudioQuality.lossless,
      ),
      'Playback quality: SQ. Current source: SQ',
    );
    expect(
      localizedPlaybackQualityTooltip(
        l10n,
        AppPlaybackQualityPreference.lossless,
        PlaybackAudioQuality.high,
      ),
      'Playback quality: SQ. Current source: HQ fallback',
    );
    expect(
      AppPlaybackQualityPreference.lossless.localizedSelectionMessage(
        l10n,
        null,
      ),
      'SQ selected. It applies when the next track starts.',
    );
    expect(
      AppPlaybackQualityPreference.lossless.localizedSelectionMessage(
        l10n,
        PlaybackAudioQuality.high,
      ),
      'SQ is unavailable for this track. Playing HQ instead.',
    );
  });
}
