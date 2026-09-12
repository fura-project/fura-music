import 'package:flutterustmusic/l10n/app_localizations.dart';
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

  String localizedDisplayLabel(AppLocalizations l10n) => switch (this) {
    AppPlaybackQualityPreference.standard => l10n.playbackQualityStandard,
    AppPlaybackQualityPreference.high => l10n.playbackQualityHigh,
    AppPlaybackQualityPreference.lossless => l10n.playbackQualityLossless,
  };

  String localizedMenuLabel(AppLocalizations l10n) => switch (this) {
    AppPlaybackQualityPreference.standard => l10n.playbackQualityMenuStandard,
    AppPlaybackQualityPreference.high => l10n.playbackQualityMenuHigh,
    AppPlaybackQualityPreference.lossless => l10n.playbackQualityMenuLossless,
  };

  bool matches(PlaybackAudioQuality? actual) => switch (this) {
    AppPlaybackQualityPreference.standard =>
      actual == PlaybackAudioQuality.standard,
    AppPlaybackQualityPreference.high => actual == PlaybackAudioQuality.high,
    AppPlaybackQualityPreference.lossless =>
      actual == PlaybackAudioQuality.lossless,
  };

  String localizedSelectionMessage(
    AppLocalizations l10n,
    PlaybackAudioQuality? actual,
  ) {
    final preferred = localizedDisplayLabel(l10n);
    if (actual == null) return l10n.playbackQualitySelectedNext(preferred);
    final actualLabel = actual.localizedDisplayLabel(l10n);
    if (matches(actual)) return l10n.playbackQualityPlaying(actualLabel);
    return l10n.playbackQualityFallback(actualLabel, preferred);
  }
}

extension PlaybackAudioQualityPresentation on PlaybackAudioQuality {
  String localizedDisplayLabel(AppLocalizations l10n) => switch (this) {
    PlaybackAudioQuality.low => l10n.playbackActualLow,
    PlaybackAudioQuality.standard => l10n.playbackQualityStandard,
    PlaybackAudioQuality.high => l10n.playbackQualityHigh,
    PlaybackAudioQuality.lossless => l10n.playbackQualityLossless,
  };
}

String localizedPlaybackQualityTooltip(
  AppLocalizations l10n,
  AppPlaybackQualityPreference preference,
  PlaybackAudioQuality? actual,
) {
  if (actual == null) {
    return l10n.playbackQualityTooltipPreferred(preference.shortLabel);
  }
  final fallback = preference.matches(actual)
      ? ''
      : l10n.playbackQualityFallbackSuffix;
  return l10n.playbackQualityTooltipCurrent(
    actual.localizedDisplayLabel(l10n),
    fallback,
    preference.shortLabel,
  );
}
