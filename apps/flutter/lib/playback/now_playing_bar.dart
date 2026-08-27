import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_panel.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_navigation.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_panel.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

/// Presentation-only callbacks for opening already-validated catalog context
/// from repeated now-playing bars. The authenticated page owns the actual
/// retained overlays and return semantics.
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
    super.key,
  }) : _expanded = false;

  const NowPlayingBar.expanded({
    required this.controller,
    required this.onSignInAgain,
    super.key,
  }) : _expanded = true;

  final QueuePlaybackController controller;
  final VoidCallback onSignInAgain;
  final bool _expanded;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final track = controller.current;
        if (track == null) return const SizedBox.shrink();
        final playback = controller.playback;
        final authenticationFailure = playback.requiresAuthentication;
        if (_expanded) {
          return _ExpandedPlaybackControls(
            controller: controller,
            track: track,
            authenticationFailure: authenticationFailure,
            onSignInAgain: onSignInAgain,
          );
        }
        final catalogNavigation = NowPlayingCatalogNavigation.maybeOf(context);
        final expandedNavigation = ExpandedNowPlayingNavigation.maybeOf(
          context,
        );
        final catalogActions = catalogNavigation == null
            ? const <_NowPlayingCatalogAction>[]
            : _catalogActions(track);
        final catalogLabel = catalogActions.isEmpty
            ? null
            : _catalogActionLabel(track, catalogActions);
        final openCatalog = catalogActions.isEmpty
            ? null
            : () => _openCatalog(
                context,
                catalogNavigation!,
                track,
                controller.currentIndex,
                catalogActions,
              );

        final error =
            controller.failure != null ||
            playback.stage == TrackPlaybackStage.resolutionError ||
            playback.stage == TrackPlaybackStage.engineError;

        return SafeArea(
          top: false,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            elevation: 3,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 520;
                final desktop = constraints.maxWidth >= 900;
                return Padding(
                  padding: EdgeInsets.fromLTRB(16, narrow ? 8 : 10, 12, 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (narrow)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                _NowPlayingArtwork(
                                  track: track,
                                  stage: playback.stage,
                                  dimension: 48,
                                  onOpenCatalog: openCatalog,
                                  catalogLabel: catalogLabel,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _TrackInfo(
                                    track: track,
                                    status: _statusCopy(controller),
                                    error: error,
                                    onOpenExpanded: expandedNavigation?.onOpen,
                                  ),
                                ),
                                if (controller.lyrics != null)
                                  _LyricsButton(
                                    controller: controller,
                                    onSignInAgain: onSignInAgain,
                                  ),
                                _VolumeButton(controller: controller),
                                _QueueButton(controller: controller),
                              ],
                            ),
                            Wrap(
                              alignment: WrapAlignment.end,
                              children: _transportControls(
                                controller,
                                authenticationFailure,
                                onSignInAgain,
                              ),
                            ),
                          ],
                        )
                      else if (desktop)
                        _DesktopNowPlayingLayout(
                          controller: controller,
                          track: track,
                          authenticationFailure: authenticationFailure,
                          error: error,
                          onSignInAgain: onSignInAgain,
                          onOpenCatalog: openCatalog,
                          catalogLabel: catalogLabel,
                          onOpenExpanded: expandedNavigation?.onOpen,
                        )
                      else
                        Row(
                          children: [
                            _NowPlayingArtwork(
                              track: track,
                              stage: playback.stage,
                              dimension: 52,
                              onOpenCatalog: openCatalog,
                              catalogLabel: catalogLabel,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TrackInfo(
                                track: track,
                                status: _statusCopy(controller),
                                error: error,
                                onOpenExpanded: expandedNavigation?.onOpen,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ..._transportControls(
                              controller,
                              authenticationFailure,
                              onSignInAgain,
                            ),
                            if (controller.lyrics != null)
                              _LyricsButton(
                                controller: controller,
                                onSignInAgain: onSignInAgain,
                              ),
                            _VolumeButton(controller: controller),
                            _QueueButton(controller: controller),
                          ],
                        ),
                      if (!desktop)
                        _PlaybackProgress(controller: playback, track: track),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCatalog(
    BuildContext context,
    NowPlayingCatalogNavigation navigation,
    PlaylistTrackSummary expectedTrack,
    int? expectedIndex,
    List<_NowPlayingCatalogAction> actions,
  ) async {
    if (!_isCurrentTrack(expectedTrack, expectedIndex)) return;
    if (actions.length == 1) {
      final action = actions.single;
      if (_currentTrackHasAction(action)) {
        _dispatchCatalogAction(navigation, action);
      }
      return;
    }
    final compact = MediaQuery.sizeOf(context).width < 600;
    final selected = compact
        ? await showModalBottomSheet<_NowPlayingCatalogAction>(
            context: context,
            showDragHandle: true,
            builder: (context) => PlaybackShortcuts(
              controller: controller,
              child: _NowPlayingCatalogSelection(
                actions: actions,
                compact: true,
              ),
            ),
          )
        : await showDialog<_NowPlayingCatalogAction>(
            context: context,
            builder: (context) => PlaybackShortcuts(
              controller: controller,
              child: AlertDialog(
                title: const Text('Browse current Track'),
                content: _NowPlayingCatalogSelection(
                  actions: actions,
                  compact: false,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          );
    if (!context.mounted ||
        selected == null ||
        !_isCurrentTrack(expectedTrack, expectedIndex) ||
        !_currentTrackHasAction(selected)) {
      return;
    }
    _dispatchCatalogAction(navigation, selected);
  }

  bool _isCurrentTrack(PlaylistTrackSummary expectedTrack, int? expectedIndex) {
    final current = controller.current;
    return controller.currentIndex == expectedIndex &&
        current?.providerId == expectedTrack.providerId &&
        current?.opaqueId == expectedTrack.opaqueId;
  }

  bool _currentTrackHasAction(_NowPlayingCatalogAction expectedAction) {
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
}

class _DesktopNowPlayingLayout extends StatelessWidget {
  const _DesktopNowPlayingLayout({
    required this.controller,
    required this.track,
    required this.authenticationFailure,
    required this.error,
    required this.onSignInAgain,
    required this.onOpenCatalog,
    required this.catalogLabel,
    required this.onOpenExpanded,
  });

  final QueuePlaybackController controller;
  final PlaylistTrackSummary track;
  final bool authenticationFailure;
  final bool error;
  final VoidCallback onSignInAgain;
  final VoidCallback? onOpenCatalog;
  final String? catalogLabel;
  final VoidCallback? onOpenExpanded;

  @override
  Widget build(BuildContext context) {
    final playback = controller.playback;
    return Row(
      key: const ValueKey('now-playing-desktop-layout'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 4,
          child: Row(
            key: const ValueKey('now-playing-track-zone'),
            children: [
              _NowPlayingArtwork(
                track: track,
                stage: playback.stage,
                dimension: 56,
                onOpenCatalog: onOpenCatalog,
                catalogLabel: catalogLabel,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TrackInfo(
                  track: track,
                  status: _statusCopy(controller),
                  error: error,
                  onOpenExpanded: onOpenExpanded,
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: Column(
            key: const ValueKey('now-playing-transport-zone'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: _transportControls(
                  controller,
                  authenticationFailure,
                  onSignInAgain,
                  prominentPrimary: true,
                ),
              ),
              _PlaybackProgress(controller: playback, track: track),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            key: const ValueKey('now-playing-utility-zone'),
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (controller.lyrics != null)
                _LyricsButton(
                  controller: controller,
                  onSignInAgain: onSignInAgain,
                ),
              _VolumeButton(controller: controller),
              _QueueButton(controller: controller),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpandedPlaybackControls extends StatelessWidget {
  const _ExpandedPlaybackControls({
    required this.controller,
    required this.track,
    required this.authenticationFailure,
    required this.onSignInAgain,
  });

  final QueuePlaybackController controller;
  final PlaylistTrackSummary track;
  final bool authenticationFailure;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playback = controller.playback;
    final status = _statusCopy(controller);
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
          padding: const EdgeInsets.fromLTRB(16, 6, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
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
              _PlaybackProgress(controller: playback, track: track),
              const SizedBox(height: 2),
              LayoutBuilder(
                builder: (context, constraints) {
                  final transport = _transportControls(
                    controller,
                    authenticationFailure,
                    onSignInAgain,
                    prominentPrimary: true,
                  );
                  final utilities = <Widget>[
                    _VolumeButton(controller: controller),
                    _QueueButton(controller: controller),
                  ];
                  if (constraints.maxWidth < 600) {
                    return Column(
                      key: const ValueKey(
                        'expanded-now-playing-compact-controls',
                      ),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: transport,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: utilities,
                        ),
                      ],
                    );
                  }
                  return SizedBox(
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

List<Widget> _transportControls(
  QueuePlaybackController controller,
  bool authenticationFailure,
  VoidCallback onSignInAgain, {
  bool prominentPrimary = false,
}) {
  final playback = controller.playback;
  final primaryAction = authenticationFailure
      ? TextButton(
          key: const ValueKey('now-playing-sign-in-again'),
          onPressed: onSignInAgain,
          child: const Text('Sign in again'),
        )
      : prominentPrimary
      ? IconButton.filled(
          key: const ValueKey('now-playing-primary-action'),
          tooltip: _primaryTooltip(playback.stage),
          onPressed: playback.canActivate
              ? () => unawaited(playback.activate())
              : null,
          style: IconButton.styleFrom(minimumSize: const Size.square(56)),
          icon: Icon(_primaryIcon(playback.stage), size: 30),
        )
      : IconButton(
          key: const ValueKey('now-playing-primary-action'),
          tooltip: _primaryTooltip(playback.stage),
          onPressed: playback.canActivate
              ? () => unawaited(playback.activate())
              : null,
          icon: Icon(_primaryIcon(playback.stage)),
        );
  return [
    _ShuffleButton(controller: controller),
    IconButton(
      key: const ValueKey('now-playing-previous'),
      tooltip: 'Previous',
      onPressed: !authenticationFailure && controller.hasPrevious
          ? () => unawaited(controller.rewind())
          : null,
      icon: const Icon(Icons.skip_previous_rounded),
    ),
    primaryAction,
    IconButton(
      key: const ValueKey('now-playing-next'),
      tooltip: 'Next',
      onPressed: !authenticationFailure && controller.hasNext
          ? () => unawaited(controller.advance())
          : null,
      icon: const Icon(Icons.skip_next_rounded),
    ),
    _RepeatButton(controller: controller),
    if (_canStop(playback.stage))
      IconButton(
        key: const ValueKey('now-playing-stop'),
        tooltip: 'Stop',
        onPressed: () => unawaited(playback.stop()),
        icon: const Icon(Icons.stop_rounded),
      ),
  ];
}

class _ShuffleButton extends StatelessWidget {
  const _ShuffleButton({required this.controller});

  final QueuePlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final enabled = controller.order == PlaybackOrder.shuffle;
    final label = enabled
        ? 'Shuffle on. Turn off shuffle'
        : 'Shuffle off. Turn on shuffle';
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
        icon: const Icon(Icons.shuffle_rounded),
        selectedIcon: const Icon(Icons.shuffle_rounded),
      ),
    );
  }
}

class _RepeatButton extends StatelessWidget {
  const _RepeatButton({required this.controller});

  final QueuePlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final mode = controller.repeatMode;
    final label = switch (mode) {
      PlaybackRepeatMode.off => 'Repeat off. Set repeat all',
      PlaybackRepeatMode.all => 'Repeat all. Set repeat one',
      PlaybackRepeatMode.one => 'Repeat one. Turn off repeat',
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
  PlaylistTrackSummary track,
  List<_NowPlayingCatalogAction> actions,
) {
  if (actions.length == 1) {
    return actions.single.album == null
        ? 'Open credited Artist for ${track.title}'
        : 'Open Album for ${track.title}';
  }
  final hasAlbum = actions.any((action) => action.album != null);
  return hasAlbum
      ? 'Browse Album and credited Artists for ${track.title}'
      : 'Choose a credited Artist for ${track.title}';
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
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: compact ? double.infinity : 440,
      maxHeight: 420,
    ),
    child: ListView.builder(
      key: const ValueKey('now-playing-catalog-selection'),
      shrinkWrap: true,
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        final album = action.album;
        final title = album?.title ?? action.artist!.name;
        final kind = album == null ? 'Artist' : 'Album';
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

class _PlaybackProgress extends StatefulWidget {
  const _PlaybackProgress({required this.controller, required this.track});

  final TrackPlaybackController controller;
  final PlaylistTrackSummary track;

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
    return Row(
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
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              key: const ValueKey('now-playing-progress'),
              value: position,
              max: durationMs.toDouble(),
              semanticFormatterCallback: (value) =>
                  '${_playbackTime(value.round())} of '
                  '${_playbackTime(durationMs)}',
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
    this.onOpenExpanded,
  });

  final PlaylistTrackSummary track;
  final String status;
  final bool error;
  final VoidCallback? onOpenExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artist = track.artistNames.isEmpty
        ? 'Unknown artist'
        : track.artistNames.join(' · ');
    final onOpenExpanded = this.onOpenExpanded;
    final information = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (onOpenExpanded == null)
          _trackTitle(theme)
        else
          ExcludeSemantics(child: _trackTitle(theme)),
        const SizedBox(height: 2),
        Semantics(
          container: true,
          liveRegion: true,
          label: '$artist · $status',
          excludeSemantics: true,
          child: Text(
            '$artist · $status',
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
    if (onOpenExpanded == null) return information;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          information,
          Positioned.fill(
            child: Tooltip(
              message: 'Open now playing',
              child: Semantics(
                button: true,
                label: 'Open now playing for ${track.title}',
                onTap: onOpenExpanded,
                excludeSemantics: true,
                child: InkWell(
                  key: const ValueKey('now-playing-open-expanded'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: onOpenExpanded,
                ),
              ),
            ),
          ),
        ],
      ),
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
  const _QueueButton({required this.controller});

  final QueuePlaybackController controller;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('now-playing-show-queue'),
    tooltip: 'Show queue',
    onPressed: () => unawaited(showPlaybackQueue(context, controller)),
    icon: const Icon(Icons.queue_music_rounded),
  );
}

class _VolumeButton extends StatelessWidget {
  const _VolumeButton({required this.controller});

  final QueuePlaybackController controller;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('now-playing-volume'),
    tooltip: 'Volume',
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
      title: const Text('Volume'),
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
                      '${(value * 100).round()} percent',
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

class _LyricsButton extends StatelessWidget {
  const _LyricsButton({required this.controller, required this.onSignInAgain});

  final QueuePlaybackController controller;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('now-playing-show-lyrics'),
    tooltip: 'Show lyrics',
    onPressed: () => showLyrics(
      context,
      controller.lyrics!,
      onSignInAgain,
      playbackState: controller.playback,
      canSeek: () => controller.playback.canSeek,
      onSeek: controller.playback.seekToMs,
      modalContentWrapper: (child) =>
          PlaybackShortcuts(controller: controller, child: child),
    ),
    icon: const Icon(Icons.lyrics_outlined),
  );
}

class _NowPlayingArtwork extends StatelessWidget {
  const _NowPlayingArtwork({
    required this.track,
    required this.stage,
    required this.dimension,
    required this.onOpenCatalog,
    required this.catalogLabel,
  });

  final PlaylistTrackSummary track;
  final TrackPlaybackStage stage;
  final double dimension;
  final VoidCallback? onOpenCatalog;
  final String? catalogLabel;

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
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    gaplessPlayback: true,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : const _NowPlayingArtworkPlaceholder(),
                    errorBuilder: (context, error, stackTrace) =>
                        const _NowPlayingArtworkPlaceholder(),
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
    final onOpenCatalog = this.onOpenCatalog;
    if (onOpenCatalog == null) {
      return Semantics(
        container: true,
        image: true,
        label: 'Artwork for ${track.title}',
        child: artwork,
      );
    }
    return Tooltip(
      message: catalogLabel!,
      child: Semantics(
        button: true,
        label: catalogLabel,
        excludeSemantics: true,
        onTap: onOpenCatalog,
        child: InkWell(
          key: const ValueKey('now-playing-catalog-action'),
          borderRadius: BorderRadius.circular(12),
          onTap: onOpenCatalog,
          child: artwork,
        ),
      ),
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

String _primaryTooltip(TrackPlaybackStage stage) => switch (stage) {
  TrackPlaybackStage.playing => 'Pause',
  TrackPlaybackStage.paused => 'Resume',
  TrackPlaybackStage.resolutionError ||
  TrackPlaybackStage.engineError => 'Try again',
  _ => 'Play',
};

IconData _primaryIcon(TrackPlaybackStage stage) => switch (stage) {
  TrackPlaybackStage.playing => Icons.pause_rounded,
  TrackPlaybackStage.resolutionError ||
  TrackPlaybackStage.engineError => Icons.refresh_rounded,
  _ => Icons.play_arrow_rounded,
};

String _statusCopy(QueuePlaybackController controller) {
  final queueFailure = controller.failure;
  if (queueFailure != null) return _queueFailureCopy(queueFailure);
  final playback = controller.playback;
  return switch (playback.stage) {
    TrackPlaybackStage.idle => 'Ready to play',
    TrackPlaybackStage.resolving => 'Finding a playable source…',
    TrackPlaybackStage.loading => 'Loading audio…',
    TrackPlaybackStage.playing => 'Playing',
    TrackPlaybackStage.paused => 'Paused',
    TrackPlaybackStage.stopped => 'Stopped',
    TrackPlaybackStage.completed => 'Finished',
    TrackPlaybackStage.resolutionError => _resolutionFailureCopy(
      playback.resolutionFailure,
    ),
    TrackPlaybackStage.engineError => 'Playback failed. Try this track again.',
  };
}

String _queueFailureCopy(PlaybackQueueFailure failure) => switch (failure) {
  PlaybackQueueFailure.invalidTrack => 'A queue track was invalid.',
  PlaybackQueueFailure.invalidPosition =>
    'That queue position is no longer available.',
  PlaybackQueueFailure.coreUnavailable =>
    'The music core could not update the queue.',
  PlaybackQueueFailure.invalidResponse =>
    'The music core returned an invalid queue state.',
};

String _resolutionFailureCopy(MediaResolutionFailure? failure) =>
    switch (failure) {
      MediaResolutionFailure.authenticationRequired ||
      MediaResolutionFailure.replaced ||
      MediaResolutionFailure.cancelled => 'Sign in to play this track.',
      MediaResolutionFailure.credentialRejected =>
        'Your QQ Music session was rejected and removed.',
      MediaResolutionFailure.credentialRejectedStorageCleanupFailed =>
        'Your session was rejected, but secure storage could not remove it.',
      MediaResolutionFailure.unavailable =>
        'QQ Music did not provide a playable source.',
      MediaResolutionFailure.network => 'Couldn’t reach QQ Music. Try again.',
      MediaResolutionFailure.serviceUnavailable =>
        'QQ Music playback is unavailable right now.',
      MediaResolutionFailure.invalidResponse =>
        'QQ Music returned a source this build could not safely play.',
      MediaResolutionFailure.coreUnavailable =>
        'The music core could not resolve this track.',
      MediaResolutionFailure.alreadyRunning =>
        'Another media request is still running.',
      null => 'This track could not be resolved.',
    };
