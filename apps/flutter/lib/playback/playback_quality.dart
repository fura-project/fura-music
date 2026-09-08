import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/settings/app_settings.dart';

extension AppPlaybackQualityBehavior on AppPlaybackQualityPreference {
  PlaybackAudioQualityPreference get audioPreference => switch (this) {
    AppPlaybackQualityPreference.standard =>
      PlaybackAudioQualityPreference.standard,
    AppPlaybackQualityPreference.high => PlaybackAudioQualityPreference.high,
    AppPlaybackQualityPreference.lossless =>
      PlaybackAudioQualityPreference.lossless,
  };

  String get shortLabel => switch (this) {
    AppPlaybackQualityPreference.standard => 'STD',
    AppPlaybackQualityPreference.high => 'HQ',
    AppPlaybackQualityPreference.lossless => 'SQ',
  };

  String get displayLabel => switch (this) {
    AppPlaybackQualityPreference.standard => 'Standard',
    AppPlaybackQualityPreference.high => 'HQ',
    AppPlaybackQualityPreference.lossless => 'SQ',
  };

  String get menuLabel => switch (this) {
    AppPlaybackQualityPreference.standard => 'Standard · MP3 128 kbps',
    AppPlaybackQualityPreference.high => 'HQ · MP3 320 kbps',
    AppPlaybackQualityPreference.lossless => 'SQ · FLAC lossless',
  };

  String get settingsSummary => switch (this) {
    AppPlaybackQualityPreference.standard => 'Standard quality',
    AppPlaybackQualityPreference.high => 'High quality',
    AppPlaybackQualityPreference.lossless => 'SQ lossless quality',
  };

  bool matches(PlaybackAudioQuality? actual) => switch (this) {
    AppPlaybackQualityPreference.standard =>
      actual == PlaybackAudioQuality.standard,
    AppPlaybackQualityPreference.high => actual == PlaybackAudioQuality.high,
    AppPlaybackQualityPreference.lossless =>
      actual == PlaybackAudioQuality.lossless,
  };

  String selectionMessage(PlaybackAudioQuality? actual) {
    if (actual == null) {
      return '$displayLabel selected. It applies when the next Track starts.';
    }
    if (matches(actual)) return 'Playing ${actual.displayLabel} quality.';
    return '$displayLabel is unavailable for this Track. '
        'Playing ${actual.displayLabel} instead.';
  }
}

extension PlaybackAudioQualityPresentation on PlaybackAudioQuality {
  String get displayLabel => switch (this) {
    PlaybackAudioQuality.low => 'Low',
    PlaybackAudioQuality.standard => 'Standard',
    PlaybackAudioQuality.high => 'HQ',
    PlaybackAudioQuality.lossless => 'SQ',
  };
}

String playbackQualityTooltip(
  AppPlaybackQualityPreference preference,
  PlaybackAudioQuality? actual,
) {
  if (actual == null) return 'Playback quality: ${preference.shortLabel}';
  final fallback = preference.matches(actual) ? '' : ' fallback';
  return 'Playback quality: ${preference.shortLabel}. '
      'Current source: ${actual.displayLabel}$fallback';
}
