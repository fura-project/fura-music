import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_quality.dart';
import 'package:flutterustmusic/settings/app_settings.dart';

void main() {
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
    expect(AppPlaybackQualityPreference.high.menuLabel, contains('320 kbps'));
    expect(
      AppPlaybackQualityPreference.lossless.settingsSummary,
      'SQ lossless quality',
    );
  });

  test('reports exact, fallback, and next-Track quality states', () {
    expect(
      playbackQualityTooltip(
        AppPlaybackQualityPreference.lossless,
        PlaybackAudioQuality.lossless,
      ),
      'Playback quality: SQ. Current source: SQ',
    );
    expect(
      playbackQualityTooltip(
        AppPlaybackQualityPreference.lossless,
        PlaybackAudioQuality.high,
      ),
      'Playback quality: SQ. Current source: HQ fallback',
    );
    expect(
      AppPlaybackQualityPreference.lossless.selectionMessage(null),
      'SQ selected. It applies when the next Track starts.',
    );
    expect(
      AppPlaybackQualityPreference.lossless.selectionMessage(
        PlaybackAudioQuality.high,
      ),
      'SQ is unavailable for this Track. Playing HQ instead.',
    );
  });
}
