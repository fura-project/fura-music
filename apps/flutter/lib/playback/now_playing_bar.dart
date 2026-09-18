import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_navigation.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_panel.dart';
import 'package:flutterustmusic/playback/playback_quality.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/provider_presentation.dart';
import 'package:flutterustmusic/settings/app_settings.dart';

const _desktopNowPlayingHeight = 88.0;
const _desktopNowPlayingVerticalInset = 8.0;
const _mobileNowPlayingHeight = 68.0;

typedef PlaybackQualityPreferenceChanged = Future<void> Function(
  AppPlaybackQualityPreference preference,
);
typedef LyricAuxiliaryModeChanged = Future<bool> Function(
  LyricAuxiliaryMode mode,
);

/// Presentation-only callbacks for opening already-validated catalog context
/// from the retained now-playing experience. The authenticated page owns the
/// actual retained overlays and return semantics.
class NowPlayingCatalogNavigation extends InheritedWidget {
  const NowPlayingCatalogNavigation({
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required super.child,
    super.key,
  });

  final ValueChanged<AlbumSummary> onOpenAlbum;
  final ValueChanged<ArtistSummary> onOpenArtist;

  static NowPlayingCatalogNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NowPlayingCatalogNavigation>();

  @override
  bool updateShouldNotify(NowPlayingCatalogNavigation oldWidget) =>
      onOpenAlbum != oldWidget.onOpenAlbum ||
      onOpenArtist != oldWidget.onOpenArtist;
}

class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({
    required this.controller,
    required this.onSignInAgain,
    this.qualityPreference,
    this.onQualityPreferenceChanged,
    this.lyricAuxiliaryMode,
    this.onLyricAuxiliaryModeChanged,
    super.key,
  }) : _expanded = false;

  const NowPlayingBar.expanded({
    required this.controller,
    required this.onSignInAgain,
    this.qualityPreference,
    this.onQualityPreferenceChanged,
    this.lyricAuxiliaryMode,
    this.onLyricAuxiliaryModeChanged,
    super.key,
  }) : _expanded = true;

  final QueuePlaybackController controller;
  final VoidCallback onSignInAgain;
  final AppPlaybackQualityPreference? qualityPreference;
  final PlaybackQualityPreferenceChanged? onQualityPreferenceChanged;
  final LyricAuxiliaryMode? lyricAuxiliaryMode;
  final LyricAuxiliaryModeChanged? onLyricAuxiliaryModeChanged;
  final bool _expanded;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final track = controller.current;
      if (track == null) {
        return _presenceTransition(
          context,
          const SizedBox.shrink(key: ValueKey('now-playing-empty')),
        );
      }
      final playback = controller.playback;
      final authenticationFailure = playback.requiresAuthentication;
      final error =
          controller.failure != null ||
          playback.stage == TrackPlaybackStage.resolutionError ||
          playback.stage == TrackPlaybackStage.engineError;
      final expandedNavigation = ExpandedNowPlayingNavigation.maybeOf(context);
      final Widget bar;
      if (_expanded) {
        bar = _ExpandedPlaybackControls(
          controller: controller,
          track: track,
          authenticationFailure: authenticationFailure,
          onSignInAgain: onSignInAgain,
          qualityPreference: qualityPreference,
          onQualityPreferenceChanged: onQualityPreferenceChanged,
          lyricAuxiliaryMode: lyricAuxiliaryMode,
          onLyricAuxiliaryModeChanged: onLyricAuxiliaryModeChanged,
        );
      } else if (MediaQuery.sizeOf(context).width < 640) {
        bar = _CompactNowPlayingBar(
          controller: controller,
          track: track,
          authenticationFailure: authenticationFailure,
          error: error,
          onSignInAgain: onSignInAgain,
          onOpenExpanded: expandedNavigation?.onOpen,
          qualityPreference: qualityPreference,
          onQualityPreferenceChanged: onQualityPreferenceChanged,
          lyricAuxiliaryMode: lyricAuxiliaryMode,
          onLyricAuxiliaryModeChanged: onLyricAuxiliaryModeChanged,
        );
      } else {
        bar = SafeArea(
          top: false,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            elevation: 3,
            child: SizedBox(
              key: const ValueKey('now-playing-desktop-bar'),
              height: _desktopNowPlayingHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  _desktopNowPlayingVerticalInset,
                  12,
                  _desktopNowPlayingVerticalInset,
                ),
                child: _DesktopNowPlayingLayout(
                  controller: controller,
                  track: track,
                  authenticationFailure: authenticationFailure,
                  error: error,
                  onSignInAgain: onSignInAgain,
                  onOpenExpanded: expandedNavigation?.onOpen,
                  qualityPreference: qualityPreference,
                  onQualityPreferenceChanged: onQualityPreferenceChanged,
                  lyricAuxiliaryMode: lyricAuxiliaryMode,
                  onLyricAuxiliaryModeChanged: onLyricAuxiliaryModeChanged,
                ),
              ),
            ),
          ),
        );
      }
      return _presenceTransition(
        context,
        KeyedSubtree(key: const ValueKey('now-playing-present'), child: bar),
      );
    },
  );

  Widget _presenceTransition(BuildContext context, Widget child) =>
      AnimatedSwitcher(
        key: const ValueKey('now-playing-presence-transition'),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        switchInCurve: Easing.emphasizedDecelerate,
        switchOutCurve: Easing.emphasizedAccelerate,
        transitionBuilder: (child, animation) {
          if (child.key != const ValueKey('now-playing-present')) return child;
          return ClipRect(
            child: SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.bottomCenter,
              child: FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.22),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: child,
      );
}

class _CompactNowPlayingBar extends StatelessWidget {
  const _CompactNowPlayingBar({
    required this.controller,
    required this.track,
    required this.authenticationFailure,
    required this.error,
    required this.onSignInAgain,
    required this.onOpenExpanded,
    required this.qualityPreference,
    required this.onQualityPreferenceChanged,
    required this.lyricAuxiliaryMode,
    required this.onLyricAuxiliaryModeChanged,
  });

  final QueuePlaybackController controller;
  final PlaylistTrackSummary track;
  final bool authenticationFailure;
  final bool error;
  final VoidCallback onSignInAgain;
  final VoidCallback? onOpenExpanded;
  final AppPlaybackQualityPreference? qualityPreference;
  final PlaybackQualityPreferenceChanged? onQualityPreferenceChanged;
  final LyricAuxiliaryMode? lyricAuxiliaryMode;
  final LyricAuxiliaryModeChanged? onLyricAuxiliaryModeChanged;

  @override
  Widget build(BuildContext context) {
    final playback = controller.playback;
    final colors = Theme.of(context).colorScheme;
    final onOpenExpanded = this.onOpenExpanded;
    final row = LayoutBuilder(
      builder: (context, constraints) {
        final hasLyricSelector =
            lyricAuxiliaryMode != null && onLyricAuxiliaryModeChanged != null;
        final hasQualitySelector =
            qualityPreference != null && onQualityPreferenceChanged != null;
        final combineOptions =
            constraints.maxWidth <= 360 &&
            hasLyricSelector &&
            hasQualitySelector;
        return SizedBox(
          height: _mobileNowPlayingHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final identity = Row(
                        children: [
                          _NowPlayingArtwork(
                            track: track,
                            stage: playback.stage,
                            dimension: 48,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TrackInfo(
                              track: track,
                              status: _statusCopy(context.l10n, controller),
                              error: error,
                            ),
                          ),
                        ],
                      );
                      if (onOpenExpanded == null) return identity;
                      return Tooltip(
                        message: context.l10n.playbackOpenNowPlaying,
                        child: Semantics(
                          key: const ValueKey('now-playing-open-expanded'),
                          button: true,
                          container: true,
                          explicitChildNodes: true,
                          label: context.l10n.playbackOpenNowPlayingFor(
                            track.title,
                          ),
                          onTap: onOpenExpanded,
                          child: InkWell(
                            onTap: onOpenExpanded,
                            excludeFromSemantics: true,
                            child: identity,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (authenticationFailure)
                  TextButton(
                    key: const ValueKey('now-playing-sign-in-again'),
                    onPressed: onSignInAgain,
                    child: Text(context.l10n.playbackSignIn),
                  )
                else
                  IconButton.filled(
                    key: const ValueKey('now-playing-primary-action'),
                    tooltip: _primaryTooltip(context.l10n, playback.stage),
                    onPressed: playback.canActivate
                        ? () => unawaited(controller.activateCurrent())
                        : null,
                    constraints: const BoxConstraints.tightFor(
                      width: 42,
                      height: 42,
                    ),
                    icon: Icon(_primaryIcon(playback.stage)),
                  ),
                if (combineOptions)
                  _PlaybackOptionsButton(
                    key: constraints.maxWidth > 320
                        ? const ValueKey('now-playing-quality')
                        : const ValueKey('now-playing-lyric-auxiliary'),
                    preference: qualityPreference!,
                    actualQuality: playback.resolvedQuality,
                    onQualityChanged: onQualityPreferenceChanged!,
                    lyricMode: lyricAuxiliaryMode!,
                    hasTranslation:
                        controller.lyrics?.lyrics?.hasTranslation ?? false,
                    hasRomanization:
                        controller.lyrics?.lyrics?.hasRomanization ?? false,
                    onLyricChanged: onLyricAuxiliaryModeChanged!,
                    exposeLyricKey: constraints.maxWidth > 320,
                    dimension: 40,
                  )
                else ...[
                  if (hasLyricSelector)
                    _LyricAuxiliaryButton(
                      mode: lyricAuxiliaryMode!,
                      hasTranslation:
                          controller.lyrics?.lyrics?.hasTranslation ?? false,
                      hasRomanization:
                          controller.lyrics?.lyrics?.hasRomanization ?? false,
                      onChanged: onLyricAuxiliaryModeChanged!,
                      dimension: 40,
                    ),
                  if (hasQualitySelector)
                    _PlaybackQualityButton(
                      preference: qualityPreference!,
                      actualQuality: playback.resolvedQuality,
                      onChanged: onQualityPreferenceChanged!,
                      dimension: 40,
                    ),
                ],
                _QueueButton(controller: controller, dimension: 40),
              ],
            ),
          ),
        );
      },
    );
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Material(
          key: const ValueKey('now-playing-compact-layout'),
          color: colors.surfaceContainerHigh,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: row,
        ),
      ),
    );
  }
}

class _DesktopNowPlayingLayout extends StatelessWidget {
  const _DesktopNowPlayingLayout({
    required this.controller,
    required this.track,
    required this.authenticationFailure,
    required this.error,
    required this.onSignInAgain,
    required this.onOpenExpanded,
    required this.qualityPreference,
    required this.onQualityPreferenceChanged,
    required this.lyricAuxiliaryMode,
    required this.onLyricAuxiliaryModeChanged,
  });

  final QueuePlaybackController controller;
  final PlaylistTrackSummary track;
  final bool authenticationFailure;
  final bool error;
  final VoidCallback onSignInAgain;
  final VoidCallback? onOpenExpanded;
  final AppPlaybackQualityPreference? qualityPreference;
  final PlaybackQualityPreferenceChanged? onQualityPreferenceChanged;
  final LyricAuxiliaryMode? lyricAuxiliaryMode;
  final LyricAuxiliaryModeChanged? onLyricAuxiliaryModeChanged;

  @override
  Widget build(BuildContext context) {
    final playback = controller.playback;
    final trackIdentity = Row(
      key: const ValueKey('now-playing-track-zone'),
      children: [
        _NowPlayingArtwork(track: track, stage: playback.stage, dimension: 56),
        const SizedBox(width: 12),
        Expanded(
          child: _TrackInfo(
            track: track,
            status: _statusCopy(context.l10n, controller),
            error: error,
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
    final onOpenExpanded = this.onOpenExpanded;
    final interactiveTrackIdentity = onOpenExpanded == null
        ? trackIdentity
        : Tooltip(
            message: context.l10n.playbackOpenNowPlaying,
            child: Semantics(
              key: const ValueKey('now-playing-open-expanded'),
              button: true,
              container: true,
              explicitChildNodes: true,
              label: context.l10n.playbackOpenNowPlayingFor(track.title),
              onTap: onOpenExpanded,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onOpenExpanded,
                excludeFromSemantics: true,
                child: trackIdentity,
              ),
            ),
          );
    return SizedBox(
      key: const ValueKey('now-playing-desktop-layout'),
      height: _desktopNowPlayingHeight - (2 * _desktopNowPlayingVerticalInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 3, child: interactiveTrackIdentity),
          Expanded(
            flex: 5,
            child: Column(
              key: const ValueKey('now-playing-transport-zone'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: _transportControls(
                    context,
                    controller,
                    authenticationFailure,
                    onSignInAgain,
                    prominentPrimary: true,
                    prominentPrimarySize: 48,
                  ),
                ),
                _PlaybackProgress(
                  controller: playback,
                  track: track,
                  dense: true,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              key: const ValueKey('now-playing-utility-zone'),
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (lyricAuxiliaryMode case final mode?)
                  if (onLyricAuxiliaryModeChanged case final onChanged?)
                    _LyricAuxiliaryButton(
                      mode: mode,
                      hasTranslation:
                          controller.lyrics?.lyrics?.hasTranslation ?? false,
                      hasRomanization:
                          controller.lyrics?.lyrics?.hasRomanization ?? false,
                      onChanged: onChanged,
                    ),
                if (qualityPreference case final preference?)
                  if (onQualityPreferenceChanged case final onChanged?)
                    _PlaybackQualityButton(
                      preference: preference,
                      actualQuality: playback.resolvedQuality,
                      onChanged: onChanged,
                    ),
                _VolumeButton(controller: controller),
                _QueueButton(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedPlaybackControls extends StatelessWidget {
  const _ExpandedPlaybackControls({
    required this.controller,
    required this.track,
    required this.authenticationFailure,
    required this.onSignInAgain,
    required this.qualityPreference,
    required this.onQualityPreferenceChanged,
    required this.lyricAuxiliaryMode,
    required this.onLyricAuxiliaryModeChanged,
  });

  final QueuePlaybackController controller;
  final PlaylistTrackSummary track;
  final bool authenticationFailure;
  final VoidCallback onSignInAgain;
  final AppPlaybackQualityPreference? qualityPreference;
  final PlaybackQualityPreferenceChanged? onQualityPreferenceChanged;
  final LyricAuxiliaryMode? lyricAuxiliaryMode;
  final LyricAuxiliaryModeChanged? onLyricAuxiliaryModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playback = controller.playback;
    final status = _statusCopy(context.l10n, controller);
    final error =
        controller.failure != null ||
        playback.stage == TrackPlaybackStage.resolutionError ||
        playback.stage == TrackPlaybackStage.engineError;
    return SafeArea(
      top: false,
      child: Material(
        key: const ValueKey('expanded-now-playing-controls'),
        color: theme.colorScheme.surfaceContainer,
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 16, end: 12),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  label: status,
                  excludeSemantics: true,
                  child: Text(
                    status,
                    key: const ValueKey('now-playing-status'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: error
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 16, end: 12),
                child: _PlaybackProgress(controller: playback, track: track),
              ),
              const SizedBox(height: 2),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 600) {
                    return _CompactExpandedPlaybackControls(
                      controller: controller,
                      authenticationFailure: authenticationFailure,
                      onSignInAgain: onSignInAgain,
                      qualityPreference: qualityPreference,
                      onQualityPreferenceChanged: onQualityPreferenceChanged,
                      lyricAuxiliaryMode: lyricAuxiliaryMode,
                      onLyricAuxiliaryModeChanged: onLyricAuxiliaryModeChanged,
                    );
                  }
                  final transport = _transportControls(
                    context,
                    controller,
                    authenticationFailure,
                    onSignInAgain,
                    prominentPrimary: true,
                    buttonSize: 48,
                  );
                  final utilities = <Widget>[
                    if (lyricAuxiliaryMode case final mode?)
                      if (onLyricAuxiliaryModeChanged case final onChanged?)
                        _LyricAuxiliaryButton(
                          mode: mode,
                          hasTranslation:
                              controller.lyrics?.lyrics?.hasTranslation ??
                              false,
                          hasRomanization:
                              controller.lyrics?.lyrics?.hasRomanization ??
                              false,
                          onChanged: onChanged,
                          dimension: 48,
                        ),
                    if (qualityPreference case final preference?)
                      if (onQualityPreferenceChanged case final onChanged?)
                        _PlaybackQualityButton(
                          preference: preference,
                          actualQuality: playback.resolvedQuality,
                          onChanged: onChanged,
                          dimension: 48,
                        ),
                    _VolumeButton(controller: controller),
                    _QueueButton(controller: controller),
                  ];
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 16,
                      end: 12,
                    ),
                    child: SizedBox(
                      key: const ValueKey('expanded-now-playing-wide-controls'),
                      height: 56,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: transport,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: utilities,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactExpandedPlaybackControls extends StatelessWidget {
  const _CompactExpandedPlaybackControls({
    required this.controller,
    required this.authenticationFailure,
    required this.onSignInAgain,
    required this.qualityPreference,
    required this.onQualityPreferenceChanged,
    required this.lyricAuxiliaryMode,
    required this.onLyricAuxiliaryModeChanged,
  });

  static const _secondaryExtent = 40.0;
  static const _primaryExtent = 48.0;
  static const _minimumGap = 2.0;
  static const _preferredGap = 4.0;
  static const _horizontalInset = 4.0;

  final QueuePlaybackController controller;
  final bool authenticationFailure;
  final VoidCallback onSignInAgain;
  final AppPlaybackQualityPreference? qualityPreference;
  final PlaybackQualityPreferenceChanged? onQualityPreferenceChanged;
  final LyricAuxiliaryMode? lyricAuxiliaryMode;
  final LyricAuxiliaryModeChanged? onLyricAuxiliaryModeChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('expanded-now-playing-compact-controls'),
    height: 56,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final transport = _transportControls(
          context,
          controller,
          authenticationFailure,
          onSignInAgain,
          prominentPrimary: true,
          prominentPrimarySize: _primaryExtent,
          includeStop: false,
          buttonSize: _secondaryExtent,
        );
        final quality = switch ((
          qualityPreference,
          onQualityPreferenceChanged,
        )) {
          (final preference?, final onChanged?) => _PlaybackQualityButton(
            preference: preference,
            actualQuality: controller.playback.resolvedQuality,
            onChanged: onChanged,
            dimension: _secondaryExtent,
          ),
          _ => null,
        };
        final auxiliary = switch ((
          lyricAuxiliaryMode,
          onLyricAuxiliaryModeChanged,
        )) {
          (final mode?, final onChanged?) => _LyricAuxiliaryButton(
            mode: mode,
            hasTranslation: controller.lyrics?.lyrics?.hasTranslation ?? false,
            hasRomanization:
                controller.lyrics?.lyrics?.hasRomanization ?? false,
            onChanged: onChanged,
            dimension: _secondaryExtent,
          ),
          _ => null,
        };
        final combineOptions =
            constraints.maxWidth <= 360 && quality != null && auxiliary != null;
        final combinedOptions = combineOptions
            ? _PlaybackOptionsButton(
                key: constraints.maxWidth > 320
                    ? const ValueKey('now-playing-quality')
                    : const ValueKey('now-playing-lyric-auxiliary'),
                preference: qualityPreference!,
                actualQuality: controller.playback.resolvedQuality,
                onQualityChanged: onQualityPreferenceChanged!,
                lyricMode: lyricAuxiliaryMode!,
                hasTranslation:
                    controller.lyrics?.lyrics?.hasTranslation ?? false,
                hasRomanization:
                    controller.lyrics?.lyrics?.hasRomanization ?? false,
                onLyricChanged: onLyricAuxiliaryModeChanged!,
                exposeLyricKey: constraints.maxWidth > 320,
                dimension: _secondaryExtent,
              )
            : null;
        final primary = authenticationFailure
            ? IconButton.filled(
                key: const ValueKey('now-playing-sign-in-again'),
                tooltip: context.l10n.playbackSignIn,
                onPressed: onSignInAgain,
                constraints: const BoxConstraints.tightFor(
                  width: _primaryExtent,
                  height: _primaryExtent,
                ),
                icon: const Icon(Icons.login_rounded),
              )
            : transport[2];
        final leadingControls = <Widget>[
          ?combinedOptions,
          if (!combineOptions && auxiliary != null) auxiliary,
          ...transport.take(2),
        ];
        final trailingControls = <Widget>[
          transport[3],
          transport[4],
          if (!combineOptions && quality != null) quality,
          _QueueButton(controller: controller, dimension: _secondaryExtent),
        ];
        final secondaryCount = leadingControls.length + trailingControls.length;
        final gapCount = secondaryCount;
        final baseStripExtent =
            (secondaryCount * _secondaryExtent) + _primaryExtent;
        final centeredGapCapacity =
            ((constraints.maxWidth / 2) -
                _horizontalInset -
                (_primaryExtent / 2) -
                (trailingControls.length * _secondaryExtent)) /
            trailingControls.length;
        final fitGapCapacity =
            (constraints.maxWidth - (2 * _horizontalInset) - baseStripExtent) /
            gapCount;
        final gapCapacity = centeredGapCapacity < fitGapCapacity
            ? centeredGapCapacity
            : fitGapCapacity;
        final gap = gapCapacity.clamp(_minimumGap, _preferredGap).toDouble();
        final stripExtent = baseStripExtent + (gapCount * gap);
        final primaryCenterInsideStrip =
            (leadingControls.length * _secondaryExtent) +
            (leadingControls.length * gap) +
            (_primaryExtent / 2);
        final idealStart =
            (constraints.maxWidth / 2) - primaryCenterInsideStrip;
        const minimumStart = _horizontalInset;
        final maximumStart =
            constraints.maxWidth - _horizontalInset - stripExtent;
        final stripStart = idealStart
            .clamp(
              minimumStart,
              maximumStart < minimumStart ? minimumStart : maximumStart,
            )
            .toDouble();
        final controls = <Widget>[
          ...leadingControls,
          primary,
          ...trailingControls,
        ];
        final spacedControls = <Widget>[];
        for (final control in controls) {
          if (spacedControls.isNotEmpty) {
            spacedControls.add(SizedBox(width: gap));
          }
          spacedControls.add(control);
        }
        return IconButtonTheme(
          data: const IconButtonThemeData(
            style: ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
          child: Stack(
            key: const ValueKey('expanded-now-playing-compact-control-row'),
            clipBehavior: Clip.none,
            children: [
              PositionedDirectional(
                start: stripStart,
                top: 4,
                child: Row(
                  key: const ValueKey(
                    'expanded-now-playing-compact-control-strip',
                  ),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: spacedControls,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _PlaybackQualityButton extends StatefulWidget {
  const _PlaybackQualityButton({
    required this.preference,
    required this.actualQuality,
    required this.onChanged,
    this.dimension = 48,
  });

  final AppPlaybackQualityPreference preference;
  final PlaybackAudioQuality? actualQuality;
  final PlaybackQualityPreferenceChanged onChanged;
  final double dimension;

  @override
  State<_PlaybackQualityButton> createState() => _PlaybackQualityButtonState();
}

class _PlaybackQualityButtonState extends State<_PlaybackQualityButton> {
  bool _saving = false;

  Future<void> _select(AppPlaybackQualityPreference preference) async {
    if (_saving || preference == widget.preference) return;
    setState(() => _saving = true);
    try {
      await widget.onChanged(preference);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tooltip = localizedPlaybackQualityTooltip(
      context.l10n,
      widget.preference,
      widget.actualQuality,
    );
    return Semantics(
      button: true,
      enabled: !_saving,
      label: tooltip,
      excludeSemantics: true,
      child: PopupMenuButton<AppPlaybackQualityPreference>(
        key: const ValueKey('now-playing-quality'),
        enabled: !_saving,
        tooltip: tooltip,
        onSelected: (value) => unawaited(_select(value)),
        itemBuilder: (context) => [
          for (final preference in AppPlaybackQualityPreference.values)
            CheckedPopupMenuItem(
              key: ValueKey('now-playing-quality-${preference.name}'),
              value: preference,
              checked: preference == widget.preference,
              child: Text(preference.localizedMenuLabel(context.l10n)),
            ),
        ],
        child: SizedBox.square(
          dimension: widget.dimension,
          child: Center(
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    widget.preference.shortLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

String _lyricAuxiliaryModeLabel(
  AppLocalizations l10n,
  LyricAuxiliaryMode mode,
) => switch (mode) {
  LyricAuxiliaryMode.auto => l10n.lyricsAuxiliaryAuto,
  LyricAuxiliaryMode.translation => l10n.lyricsAuxiliaryTranslation,
  LyricAuxiliaryMode.romanization => l10n.lyricsAuxiliaryPronunciation,
  LyricAuxiliaryMode.off => l10n.lyricsAuxiliaryOff,
};

IconData _lyricAuxiliaryModeIcon(LyricAuxiliaryMode mode) => switch (mode) {
  LyricAuxiliaryMode.auto => Icons.auto_awesome_rounded,
  LyricAuxiliaryMode.translation => Icons.translate_rounded,
  LyricAuxiliaryMode.romanization => Icons.record_voice_over_rounded,
  LyricAuxiliaryMode.off => Icons.subtitles_off_rounded,
};

bool _lyricAuxiliaryModeAvailable(
  LyricAuxiliaryMode mode, {
  required bool hasTranslation,
  required bool hasRomanization,
}) => switch (mode) {
  LyricAuxiliaryMode.auto || LyricAuxiliaryMode.off => true,
  LyricAuxiliaryMode.translation => hasTranslation,
  LyricAuxiliaryMode.romanization => hasRomanization,
};

Future<void> _announceLyricAuxiliaryMode(
  BuildContext context,
  LyricAuxiliaryMode mode,
) async {
  final l10n = context.l10n;
  final message = l10n.lyricsAuxiliaryChanged(
    _lyricAuxiliaryModeLabel(l10n, mode),
  );
  final view = View.of(context);
  final direction = Directionality.of(context);
  try {
    await SemanticsService.sendAnnouncement(view, message, direction);
  } on Object {
    // Accessibility announcements are best effort and must never roll back a
    // setting that has already been persisted.
  }
}

class _LyricAuxiliaryButton extends StatefulWidget {
  const _LyricAuxiliaryButton({
    required this.mode,
    required this.hasTranslation,
    required this.hasRomanization,
    required this.onChanged,
    this.dimension = 48,
  });

  final LyricAuxiliaryMode mode;
  final bool hasTranslation;
  final bool hasRomanization;
  final LyricAuxiliaryModeChanged onChanged;
  final double dimension;

  @override
  State<_LyricAuxiliaryButton> createState() => _LyricAuxiliaryButtonState();
}

class _LyricAuxiliaryButtonState extends State<_LyricAuxiliaryButton> {
  bool _saving = false;

  Future<void> _select(LyricAuxiliaryMode mode) async {
    if (_saving || mode == widget.mode) return;
    setState(() => _saving = true);
    var saved = false;
    try {
      saved = await widget.onChanged(mode);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (saved && mounted) await _announceLyricAuxiliaryMode(context, mode);
  }

  @override
  Widget build(BuildContext context) {
    final label = _lyricAuxiliaryModeLabel(context.l10n, widget.mode);
    final tooltip = context.l10n.lyricsAuxiliaryTooltip(label);
    return Semantics(
      button: true,
      enabled: !_saving,
      label: tooltip,
      excludeSemantics: true,
      child: PopupMenuButton<LyricAuxiliaryMode>(
        key: const ValueKey('now-playing-lyric-auxiliary'),
        enabled: !_saving,
        tooltip: tooltip,
        onSelected: (mode) => unawaited(_select(mode)),
        itemBuilder: (context) => [
          for (final mode in LyricAuxiliaryMode.values)
            CheckedPopupMenuItem(
              key: ValueKey('now-playing-lyric-auxiliary-${mode.name}'),
              value: mode,
              checked: mode == widget.mode,
              enabled: _lyricAuxiliaryModeAvailable(
                mode,
                hasTranslation: widget.hasTranslation,
                hasRomanization: widget.hasRomanization,
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_lyricAuxiliaryModeIcon(mode)),
                title: Text(_lyricAuxiliaryModeLabel(context.l10n, mode)),
              ),
            ),
        ],
        child: SizedBox.square(
          dimension: widget.dimension,
          child: Center(
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _lyricAuxiliaryModeIcon(widget.mode),
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ),
        ),
      ),
    );
  }
}

enum _PlaybackOptionChoice {
  qualityStandard,
  qualityHigh,
  qualityLossless,
  lyricAuto,
  lyricTranslation,
  lyricRomanization,
  lyricOff,
}

extension on _PlaybackOptionChoice {
  AppPlaybackQualityPreference? get quality => switch (this) {
    _PlaybackOptionChoice.qualityStandard =>
      AppPlaybackQualityPreference.standard,
    _PlaybackOptionChoice.qualityHigh => AppPlaybackQualityPreference.high,
    _PlaybackOptionChoice.qualityLossless =>
      AppPlaybackQualityPreference.lossless,
    _ => null,
  };

  LyricAuxiliaryMode? get lyricMode => switch (this) {
    _PlaybackOptionChoice.lyricAuto => LyricAuxiliaryMode.auto,
    _PlaybackOptionChoice.lyricTranslation => LyricAuxiliaryMode.translation,
    _PlaybackOptionChoice.lyricRomanization => LyricAuxiliaryMode.romanization,
    _PlaybackOptionChoice.lyricOff => LyricAuxiliaryMode.off,
    _ => null,
  };
}

class _PlaybackOptionsButton extends StatefulWidget {
  const _PlaybackOptionsButton({
    required this.preference,
    required this.actualQuality,
    required this.onQualityChanged,
    required this.lyricMode,
    required this.hasTranslation,
    required this.hasRomanization,
    required this.onLyricChanged,
    required this.exposeLyricKey,
    required this.dimension,
    super.key,
  });

  final AppPlaybackQualityPreference preference;
  final PlaybackAudioQuality? actualQuality;
  final PlaybackQualityPreferenceChanged onQualityChanged;
  final LyricAuxiliaryMode lyricMode;
  final bool hasTranslation;
  final bool hasRomanization;
  final LyricAuxiliaryModeChanged onLyricChanged;
  final bool exposeLyricKey;
  final double dimension;

  @override
  State<_PlaybackOptionsButton> createState() => _PlaybackOptionsButtonState();
}

class _PlaybackOptionsButtonState extends State<_PlaybackOptionsButton> {
  bool _saving = false;

  Future<void> _select(_PlaybackOptionChoice choice) async {
    if (_saving) return;
    if (choice.quality case final quality?) {
      if (quality == widget.preference) return;
      setState(() => _saving = true);
      try {
        await widget.onQualityChanged(quality);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    final mode = choice.lyricMode;
    if (mode == null || mode == widget.lyricMode) return;
    setState(() => _saving = true);
    var saved = false;
    try {
      saved = await widget.onLyricChanged(mode);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (saved && mounted) await _announceLyricAuxiliaryMode(context, mode);
  }

  @override
  Widget build(BuildContext context) {
    final lyricLabel = _lyricAuxiliaryModeLabel(context.l10n, widget.lyricMode);
    final tooltip = context.l10n.playbackOptionsTooltip(
      widget.preference.shortLabel,
      lyricLabel,
    );
    return Semantics(
      button: true,
      enabled: !_saving,
      label: tooltip,
      excludeSemantics: true,
      child: PopupMenuButton<_PlaybackOptionChoice>(
        enabled: !_saving,
        tooltip: tooltip,
        onSelected: (choice) => unawaited(_select(choice)),
        itemBuilder: (context) => [
          for (final preference in AppPlaybackQualityPreference.values)
            CheckedPopupMenuItem(
              key: ValueKey('now-playing-quality-${preference.name}'),
              value: _qualityChoice(preference),
              checked: preference == widget.preference,
              child: Text(preference.localizedMenuLabel(context.l10n)),
            ),
          const PopupMenuDivider(),
          for (final mode in LyricAuxiliaryMode.values)
            CheckedPopupMenuItem(
              key: ValueKey('now-playing-lyric-auxiliary-${mode.name}'),
              value: _lyricChoice(mode),
              checked: mode == widget.lyricMode,
              enabled: _lyricAuxiliaryModeAvailable(
                mode,
                hasTranslation: widget.hasTranslation,
                hasRomanization: widget.hasRomanization,
              ),
              child: Text(_lyricAuxiliaryModeLabel(context.l10n, mode)),
            ),
        ],
        child: SizedBox.square(
          key: widget.exposeLyricKey
              ? const ValueKey('now-playing-lyric-auxiliary')
              : null,
          dimension: widget.dimension,
          child: Center(
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.tune_rounded),
          ),
        ),
      ),
    );
  }

  _PlaybackOptionChoice _qualityChoice(
    AppPlaybackQualityPreference preference,
  ) => switch (preference) {
    AppPlaybackQualityPreference.standard =>
      _PlaybackOptionChoice.qualityStandard,
    AppPlaybackQualityPreference.high => _PlaybackOptionChoice.qualityHigh,
    AppPlaybackQualityPreference.lossless =>
      _PlaybackOptionChoice.qualityLossless,
  };

  _PlaybackOptionChoice _lyricChoice(LyricAuxiliaryMode mode) => switch (mode) {
    LyricAuxiliaryMode.auto => _PlaybackOptionChoice.lyricAuto,
    LyricAuxiliaryMode.translation => _PlaybackOptionChoice.lyricTranslation,
    LyricAuxiliaryMode.romanization => _PlaybackOptionChoice.lyricRomanization,
    LyricAuxiliaryMode.off => _PlaybackOptionChoice.lyricOff,
  };
}

List<Widget> _transportControls(
  BuildContext context,
  QueuePlaybackController controller,
  bool authenticationFailure,
  VoidCallback onSignInAgain, {
  bool prominentPrimary = false,
  double prominentPrimarySize = 56,
  bool includeStop = true,
  double buttonSize = 48,
}) {
  final playback = controller.playback;
  final primaryAction = authenticationFailure
      ? TextButton(
          key: const ValueKey('now-playing-sign-in-again'),
          onPressed: onSignInAgain,
          child: Text(context.l10n.playbackSignIn),
        )
      : prominentPrimary
      ? IconButton.filled(
          key: const ValueKey('now-playing-primary-action'),
          tooltip: _primaryTooltip(context.l10n, playback.stage),
          onPressed: playback.canActivate
              ? () => unawaited(controller.activateCurrent())
              : null,
          style: IconButton.styleFrom(
            minimumSize: Size.square(prominentPrimarySize),
          ),
          icon: Icon(
            _primaryIcon(playback.stage),
            size: prominentPrimarySize == 48 ? 28 : 30,
          ),
        )
      : IconButton(
          key: const ValueKey('now-playing-primary-action'),
          tooltip: _primaryTooltip(context.l10n, playback.stage),
          onPressed: playback.canActivate
              ? () => unawaited(controller.activateCurrent())
              : null,
          icon: Icon(_primaryIcon(playback.stage)),
        );
  return [
    _ShuffleButton(controller: controller, dimension: buttonSize),
    IconButton(
      key: const ValueKey('now-playing-previous'),
      tooltip: context.l10n.playbackPrevious,
      onPressed: !authenticationFailure && controller.hasPrevious
          ? () => unawaited(controller.rewind())
          : null,
      constraints: BoxConstraints.tightFor(
        width: buttonSize,
        height: buttonSize,
      ),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.skip_previous_rounded),
    ),
    primaryAction,
    IconButton(
      key: const ValueKey('now-playing-next'),
      tooltip: context.l10n.playbackNext,
      onPressed: !authenticationFailure && controller.hasNext
          ? () => unawaited(controller.advance())
          : null,
      constraints: BoxConstraints.tightFor(
        width: buttonSize,
        height: buttonSize,
      ),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.skip_next_rounded),
    ),
    _RepeatButton(controller: controller, dimension: buttonSize),
    if (includeStop && _canStop(playback.stage))
      IconButton(
        key: const ValueKey('now-playing-stop'),
        tooltip: context.l10n.playbackStop,
        onPressed: () => unawaited(controller.stop()),
        icon: const Icon(Icons.stop_rounded),
      ),
  ];
}

class _ShuffleButton extends StatelessWidget {
  const _ShuffleButton({required this.controller, this.dimension = 48});

  final QueuePlaybackController controller;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final enabled = controller.order == PlaybackOrder.shuffle;
    final label = enabled
        ? context.l10n.playbackShuffleOn
        : context.l10n.playbackShuffleOff;
    return Semantics(
      button: true,
      toggled: enabled,
      label: label,
      excludeSemantics: true,
      child: IconButton(
        key: const ValueKey('now-playing-shuffle'),
        tooltip: label,
        isSelected: enabled,
        onPressed: () => unawaited(controller.toggleShuffle()),
        constraints: BoxConstraints.tightFor(
          width: dimension,
          height: dimension,
        ),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.shuffle_rounded),
        selectedIcon: const Icon(Icons.shuffle_rounded),
      ),
    );
  }
}

class _RepeatButton extends StatelessWidget {
  const _RepeatButton({required this.controller, this.dimension = 48});

  final QueuePlaybackController controller;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final mode = controller.repeatMode;
    final label = switch (mode) {
      PlaybackRepeatMode.off => context.l10n.playbackRepeatOff,
      PlaybackRepeatMode.all => context.l10n.playbackRepeatAll,
      PlaybackRepeatMode.one => context.l10n.playbackRepeatOne,
    };
    return Semantics(
      button: true,
      selected: mode != PlaybackRepeatMode.off,
      label: label,
      excludeSemantics: true,
      child: IconButton(
        key: const ValueKey('now-playing-repeat'),
        tooltip: label,
        isSelected: mode != PlaybackRepeatMode.off,
        onPressed: () => unawaited(controller.cycleRepeatMode()),
        constraints: BoxConstraints.tightFor(
          width: dimension,
          height: dimension,
        ),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.repeat_rounded),
        selectedIcon: Icon(
          mode == PlaybackRepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
        ),
      ),
    );
  }
}

String? nowPlayingCatalogContextLabel(
  BuildContext context,
  PlaylistTrackSummary track,
) {
  if (NowPlayingCatalogNavigation.maybeOf(context) == null) return null;
  final actions = _catalogActions(track);
  return actions.isEmpty
      ? null
      : _catalogActionLabel(context.l10n, track, actions);
}

Future<void> openNowPlayingCatalogContext({
  required BuildContext context,
  required QueuePlaybackController controller,
  required PlaylistTrackSummary expectedTrack,
  required int? expectedIndex,
}) async {
  final navigation = NowPlayingCatalogNavigation.maybeOf(context);
  if (navigation == null ||
      !_isCurrentTrack(controller, expectedTrack, expectedIndex)) {
    return;
  }
  final actions = _catalogActions(expectedTrack);
  if (actions.isEmpty) return;
  if (actions.length == 1) {
    final action = actions.single;
    if (_currentTrackHasAction(controller, action)) {
      _dispatchCatalogAction(navigation, action);
    }
    return;
  }
  final compact = MediaQuery.sizeOf(context).width < 600;
  final selected = compact
      ? await showModalBottomSheet<_NowPlayingCatalogAction>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            top: false,
            child: PlaybackShortcuts(
              controller: controller,
              child: _NowPlayingCatalogSelection(
                actions: actions,
                compact: true,
              ),
            ),
          ),
        )
      : await showDialog<_NowPlayingCatalogAction>(
          context: context,
          builder: (context) => PlaybackShortcuts(
            controller: controller,
            child: AlertDialog(
              title: Text(context.l10n.playbackBrowseCurrentTrack),
              content: _NowPlayingCatalogSelection(
                actions: actions,
                compact: false,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.commonCancel),
                ),
              ],
            ),
          ),
        );
  if (!context.mounted ||
      selected == null ||
      !_isCurrentTrack(controller, expectedTrack, expectedIndex) ||
      !_currentTrackHasAction(controller, selected)) {
    return;
  }
  _dispatchCatalogAction(navigation, selected);
}

bool _isCurrentTrack(
  QueuePlaybackController controller,
  PlaylistTrackSummary expectedTrack,
  int? expectedIndex,
) {
  final current = controller.current;
  return controller.currentIndex == expectedIndex &&
      current?.providerId == expectedTrack.providerId &&
      current?.opaqueId == expectedTrack.opaqueId;
}

bool _currentTrackHasAction(
  QueuePlaybackController controller,
  _NowPlayingCatalogAction expectedAction,
) {
  final current = controller.current;
  if (current == null) return false;
  return _catalogActions(current).any(
    (action) =>
        action.album?.providerId == expectedAction.album?.providerId &&
        action.album?.opaqueId == expectedAction.album?.opaqueId &&
        action.artist?.providerId == expectedAction.artist?.providerId &&
        action.artist?.opaqueId == expectedAction.artist?.opaqueId,
  );
}

void _dispatchCatalogAction(
  NowPlayingCatalogNavigation navigation,
  _NowPlayingCatalogAction action,
) {
  final album = action.album;
  if (album != null) {
    navigation.onOpenAlbum(album);
    return;
  }
  navigation.onOpenArtist(action.artist!);
}

List<_NowPlayingCatalogAction> _catalogActions(PlaylistTrackSummary track) {
  final actions = <_NowPlayingCatalogAction>[];
  final album = track.album;
  if (album != null &&
      album.providerId == track.providerId &&
      album.opaqueId.trim().isNotEmpty &&
      album.title.trim().isNotEmpty) {
    actions.add(_NowPlayingCatalogAction.album(album));
  }
  final seenArtists = <String>{};
  for (final artist in track.artists) {
    if (artist.providerId != track.providerId ||
        artist.opaqueId.trim().isEmpty ||
        artist.name.trim().isEmpty ||
        !seenArtists.add('${artist.providerId}\u0000${artist.opaqueId}')) {
      continue;
    }
    actions.add(_NowPlayingCatalogAction.artist(artist));
  }
  return List.unmodifiable(actions);
}

String _catalogActionLabel(
  AppLocalizations l10n,
  PlaylistTrackSummary track,
  List<_NowPlayingCatalogAction> actions,
) {
  if (actions.length == 1) {
    return actions.single.album == null
        ? l10n.playbackOpenCreditedArtist(track.title)
        : l10n.playbackOpenAlbum(track.title);
  }
  final hasAlbum = actions.any((action) => action.album != null);
  return hasAlbum
      ? l10n.playbackBrowseAlbumArtists(track.title)
      : l10n.playbackChooseCreditedArtist(track.title);
}

class _NowPlayingCatalogAction {
  const _NowPlayingCatalogAction.album(this.album) : artist = null;
  const _NowPlayingCatalogAction.artist(this.artist) : album = null;

  final AlbumSummary? album;
  final ArtistSummary? artist;
}

class _NowPlayingCatalogSelection extends StatelessWidget {
  const _NowPlayingCatalogSelection({
    required this.actions,
    required this.compact,
  });

  final List<_NowPlayingCatalogAction> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = (actions.length * 72.0).clamp(72.0, 420.0).toDouble();
    return SizedBox(
      width: compact ? double.infinity : 440,
      height: height,
      child: ListView.builder(
        key: const ValueKey('now-playing-catalog-selection'),
        itemCount: actions.length,
        itemBuilder: (context, index) {
          final action = actions[index];
          final album = action.album;
          final title = album?.title ?? action.artist!.name;
          final kind = album == null
              ? context.l10n.artistType
              : context.l10n.albumType;
          return ListTile(
            key: ValueKey(
              album == null
                  ? 'now-playing-open-artist-$index'
                  : 'now-playing-open-album',
            ),
            leading: Icon(
              album == null ? Icons.person_rounded : Icons.album_rounded,
            ),
            title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(kind),
            onTap: () => Navigator.pop(context, action),
          );
        },
      ),
    );
  }
}

class _PlaybackProgress extends StatefulWidget {
  const _PlaybackProgress({
    required this.controller,
    required this.track,
    this.dense = false,
  });

  final TrackPlaybackController controller;
  final PlaylistTrackSummary track;
  final bool dense;

  @override
  State<_PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<_PlaybackProgress> {
  double? _previewMs;
  int _seekAttempt = 0;

  @override
  void didUpdateWidget(covariant _PlaybackProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.providerId != widget.track.providerId ||
        oldWidget.track.opaqueId != widget.track.opaqueId) {
      _seekAttempt += 1;
      _previewMs = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = widget.controller.durationMs;
    if (durationMs == null) return const SizedBox.shrink();
    final rawPosition = _previewMs ?? widget.controller.positionMs.toDouble();
    final position = rawPosition.clamp(0, durationMs.toDouble()).toDouble();
    final colors = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final progress = Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            _playbackTime(position.round()),
            key: const ValueKey('now-playing-position'),
            style: textStyle,
            textAlign: TextAlign.end,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: widget.dense ? 5 : 6,
              ),
              overlayShape: RoundSliderOverlayShape(
                overlayRadius: widget.dense ? 11 : 14,
              ),
            ),
            child: Slider(
              key: const ValueKey('now-playing-progress'),
              value: position,
              max: durationMs.toDouble(),
              semanticFormatterCallback: (value) =>
                  context.l10n.playbackProgressSemantics(
                    _playbackTime(durationMs),
                    _playbackTime(value.round()),
                  ),
              onChangeStart: widget.controller.canSeek
                  ? (value) => setState(() => _previewMs = value)
                  : null,
              onChanged: widget.controller.canSeek
                  ? (value) => setState(() => _previewMs = value)
                  : null,
              onChangeEnd: widget.controller.canSeek ? _commitSeek : null,
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            _playbackTime(durationMs),
            key: const ValueKey('now-playing-duration'),
            style: textStyle,
          ),
        ),
      ],
    );
    return widget.dense
        ? SizedBox(
            key: const ValueKey('now-playing-desktop-progress-row'),
            height: 24,
            child: progress,
          )
        : progress;
  }

  void _commitSeek(double value) {
    final attempt = ++_seekAttempt;
    setState(() => _previewMs = value);
    unawaited(() async {
      await widget.controller.seekToMs(value.round());
      if (!mounted || attempt != _seekAttempt) return;
      setState(() => _previewMs = null);
    }());
  }
}

String _playbackTime(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({
    required this.track,
    required this.status,
    required this.error,
  });

  final PlaylistTrackSummary track;
  final String status;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artist = track.artistNames.isEmpty
        ? context.l10n.trackUnknownArtist
        : track.artistNames.join(' · ');
    final semantics = context.l10n.playbackTrackStatusSemantics(artist, status);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _trackTitle(theme),
        const SizedBox(height: 2),
        Semantics(
          container: true,
          liveRegion: true,
          label: semantics,
          excludeSemantics: true,
          child: Text(
            semantics,
            key: const ValueKey('now-playing-status'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: error
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _trackTitle(ThemeData theme) => Text(
    track.title,
    key: const ValueKey('now-playing-title'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _QueueButton extends StatelessWidget {
  const _QueueButton({required this.controller, this.dimension = 48});

  final QueuePlaybackController controller;
  final double dimension;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('now-playing-show-queue'),
    tooltip: context.l10n.playbackShowQueue,
    onPressed: () => unawaited(showPlaybackQueue(context, controller)),
    constraints: BoxConstraints.tightFor(width: dimension, height: dimension),
    padding: EdgeInsets.zero,
    icon: const Icon(Icons.queue_music_rounded),
  );
}

class _VolumeButton extends StatelessWidget {
  const _VolumeButton({required this.controller});

  final QueuePlaybackController controller;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('now-playing-volume'),
    tooltip: context.l10n.playbackVolume,
    onPressed: () => unawaited(_showVolumeControl(context, controller)),
    icon: Icon(
      controller.playback.volume == 0
          ? Icons.volume_off_rounded
          : controller.playback.volume < 0.5
          ? Icons.volume_down_rounded
          : Icons.volume_up_rounded,
    ),
  );
}

Future<void> _showVolumeControl(
  BuildContext context,
  QueuePlaybackController controller,
) async {
  if (MediaQuery.sizeOf(context).width < 600) {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: PlaybackShortcuts(
          controller: controller,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: _VolumePanel(controller: controller.playback),
          ),
        ),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.playbackVolume),
      content: PlaybackShortcuts(
        controller: controller,
        child: SizedBox(
          width: 320,
          child: _VolumePanel(controller: controller.playback),
        ),
      ),
    ),
  );
}

class _VolumePanel extends StatefulWidget {
  const _VolumePanel({required this.controller});

  final TrackPlaybackController controller;

  @override
  State<_VolumePanel> createState() => _VolumePanelState();
}

class _VolumePanelState extends State<_VolumePanel> {
  double? _preview;
  int _attempt = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final value = (_preview ?? widget.controller.volume)
          .clamp(0, 1)
          .toDouble();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                value == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_down_rounded,
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('volume-slider'),
                  value: value,
                  semanticFormatterCallback: (value) =>
                      context.l10n.playbackVolumePercent((value * 100).round()),
                  onChangeStart: (value) => setState(() => _preview = value),
                  onChanged: (value) => setState(() => _preview = value),
                  onChangeEnd: _commit,
                ),
              ),
              Icon(
                value < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
              ),
            ],
          ),
          Text(
            '${(value * 100).round()}%',
            key: const ValueKey('volume-percent'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      );
    },
  );

  void _commit(double value) {
    final attempt = ++_attempt;
    setState(() => _preview = value);
    unawaited(() async {
      await widget.controller.setVolume(value);
      if (!mounted || attempt != _attempt) return;
      setState(() => _preview = null);
    }());
  }
}

class _NowPlayingArtwork extends StatelessWidget {
  const _NowPlayingArtwork({
    required this.track,
    required this.stage,
    required this.dimension,
  });

  final PlaylistTrackSummary track;
  final TrackPlaybackStage stage;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final artworkUri = track.artworkUri;
    final busy =
        stage == TrackPlaybackStage.resolving ||
        stage == TrackPlaybackStage.loading;
    final error =
        stage == TrackPlaybackStage.resolutionError ||
        stage == TrackPlaybackStage.engineError;
    final artwork = SizedBox.square(
      key: const ValueKey('now-playing-artwork'),
      dimension: dimension,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            artworkUri == null
                ? const _NowPlayingArtworkPlaceholder()
                : Image.network(
                    artworkUri,
                    headers: musicArtworkRequestHeaders(artworkUri),
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    gaplessPlayback: true,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : const _NowPlayingArtworkPlaceholder(),
                    errorBuilder: musicArtworkErrorBuilder(
                      artworkUri,
                      const _NowPlayingArtworkPlaceholder(),
                    ),
                  ),
            if (busy || error)
              ColoredBox(
                key: const ValueKey('now-playing-artwork-state'),
                color: Colors.black.withValues(alpha: 0.44),
                child: Center(
                  child: busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          Icons.error_outline_rounded,
                          color: Theme.of(context).colorScheme.errorContainer,
                          size: 24,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      image: true,
      label: context.l10n.playbackArtworkSemantics(track.title),
      child: artwork,
    );
  }
}

class _NowPlayingArtworkPlaceholder extends StatelessWidget {
  const _NowPlayingArtworkPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('now-playing-artwork-placeholder'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      child: Icon(
        Icons.album_rounded,
        color: colors.onPrimaryContainer,
        size: 28,
      ),
    );
  }
}

bool _canStop(TrackPlaybackStage stage) => switch (stage) {
  TrackPlaybackStage.resolving ||
  TrackPlaybackStage.loading ||
  TrackPlaybackStage.playing ||
  TrackPlaybackStage.paused => true,
  _ => false,
};

String _primaryTooltip(AppLocalizations l10n, TrackPlaybackStage stage) =>
    switch (stage) {
      TrackPlaybackStage.playing => l10n.playbackPause,
      TrackPlaybackStage.paused => l10n.playbackResume,
      TrackPlaybackStage.resolutionError ||
      TrackPlaybackStage.engineError => l10n.playbackRetry,
      _ => l10n.commonPlay,
    };

IconData _primaryIcon(TrackPlaybackStage stage) => switch (stage) {
  TrackPlaybackStage.playing => Icons.pause_rounded,
  TrackPlaybackStage.resolutionError ||
  TrackPlaybackStage.engineError => Icons.refresh_rounded,
  _ => Icons.play_arrow_rounded,
};

String _statusCopy(AppLocalizations l10n, QueuePlaybackController controller) {
  final queueFailure = controller.failure;
  if (queueFailure != null) return _queueFailureCopy(l10n, queueFailure);
  final playback = controller.playback;
  final providerDisplayName = builtInProviderDisplayName(
    controller.currentTrackListenable.value?.providerId ?? '',
    l10n,
  );
  return switch (playback.stage) {
    TrackPlaybackStage.idle => l10n.playbackReady,
    TrackPlaybackStage.resolving => l10n.playbackFindingSource,
    TrackPlaybackStage.loading => l10n.playbackLoadingAudio,
    TrackPlaybackStage.playing => l10n.playbackPlaying,
    TrackPlaybackStage.paused => l10n.playbackPaused,
    TrackPlaybackStage.stopped => l10n.playbackStopped,
    TrackPlaybackStage.completed => l10n.playbackFinished,
    TrackPlaybackStage.resolutionError => _resolutionFailureCopy(
      l10n,
      playback.resolutionFailure,
      providerDisplayName,
    ),
    TrackPlaybackStage.engineError => l10n.playbackEngineFailure,
  };
}

String _queueFailureCopy(AppLocalizations l10n, PlaybackQueueFailure failure) =>
    switch (failure) {
      PlaybackQueueFailure.invalidTrack => l10n.playbackQueueInvalidTrack,
      PlaybackQueueFailure.invalidPosition => l10n.queueFailureInvalidPosition,
      PlaybackQueueFailure.coreUnavailable => l10n.queueFailureCore,
      PlaybackQueueFailure.invalidResponse => l10n.queueFailureInvalidResponse,
    };

String _resolutionFailureCopy(
  AppLocalizations l10n,
  MediaResolutionFailure? failure,
  String providerDisplayName,
) => switch (failure) {
  MediaResolutionFailure.authenticationRequired ||
  MediaResolutionFailure.replaced ||
  MediaResolutionFailure.cancelled => l10n.playbackAuthRequired,
  MediaResolutionFailure.credentialRejected => l10n.playbackCredentialRejected(
    providerDisplayName,
  ),
  MediaResolutionFailure.credentialRejectedStorageCleanupFailed =>
    l10n.playbackCredentialCleanupFailure,
  MediaResolutionFailure.unavailable => l10n.playbackSourceUnavailable(
    providerDisplayName,
  ),
  MediaResolutionFailure.network => l10n.playbackNetworkFailure(
    providerDisplayName,
  ),
  MediaResolutionFailure.serviceUnavailable => l10n.playbackServiceUnavailable(
    providerDisplayName,
  ),
  MediaResolutionFailure.invalidResponse => l10n.playbackInvalidResponse(
    providerDisplayName,
  ),
  MediaResolutionFailure.coreUnavailable => l10n.playbackCoreUnavailable,
  MediaResolutionFailure.alreadyRunning => l10n.playbackRequestRunning,
  null => l10n.playbackResolutionFailure,
};
