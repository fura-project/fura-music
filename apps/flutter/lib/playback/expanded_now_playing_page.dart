import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/comments/track_comments_surface.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_panel.dart';
import 'package:flutterustmusic/music_video/track_music_video_engine.dart';
import 'package:flutterustmusic/music_video/track_music_video_gateway.dart';
import 'package:flutterustmusic/music_video/track_music_video_surface.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

class ExpandedNowPlayingPage extends StatelessWidget {
  const ExpandedNowPlayingPage({
    required this.controller,
    required this.onBack,
    required this.onSignInAgain,
    this.commentsGateway = const RustTrackCommentGateway(),
    this.musicVideoGateway = const RustTrackMusicVideoGateway(),
    this.musicVideoEngine = const MediaKitTrackMusicVideoEngine(),
    super.key,
  });

  final QueuePlaybackController controller;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final TrackCommentGateway commentsGateway;
  final TrackMusicVideoGateway musicVideoGateway;
  final TrackMusicVideoEngine musicVideoEngine;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('expanded-now-playing-page'),
    appBar: AppBar(
      leading: IconButton(
        key: const ValueKey('expanded-now-playing-back'),
        tooltip: 'Back to previous page',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Now playing'),
    ),
    body: _ExpandedNowPlayingBody(
      controller: controller,
      onBack: onBack,
      onSignInAgain: onSignInAgain,
      commentsGateway: commentsGateway,
      musicVideoGateway: musicVideoGateway,
      musicVideoEngine: musicVideoEngine,
    ),
    bottomNavigationBar: NowPlayingBar.expanded(
      controller: controller,
      onSignInAgain: onSignInAgain,
    ),
  );
}

class _ExpandedNowPlayingBody extends StatefulWidget {
  const _ExpandedNowPlayingBody({
    required this.controller,
    required this.onBack,
    required this.onSignInAgain,
    required this.commentsGateway,
    required this.musicVideoGateway,
    required this.musicVideoEngine,
  });

  final QueuePlaybackController controller;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final TrackCommentGateway commentsGateway;
  final TrackMusicVideoGateway musicVideoGateway;
  final TrackMusicVideoEngine musicVideoEngine;

  @override
  State<_ExpandedNowPlayingBody> createState() =>
      _ExpandedNowPlayingBodyState();
}

class _ExpandedNowPlayingBodyState extends State<_ExpandedNowPlayingBody> {
  PlaylistTrackSummary? _track;
  int? _currentIndex;

  @override
  void initState() {
    super.initState();
    _readCurrent();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(_ExpandedNowPlayingBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    _readCurrent();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    if (track == null) {
      return _ExpandedNowPlayingEmpty(onBack: widget.onBack);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final lyrics = _lyrics();
        if (wide) {
          return Row(
            key: const ValueKey('expanded-now-playing-wide-layout'),
            children: [
              Expanded(
                child: _ExpandedTrackHero(
                  track: track,
                  onOpenComments: () => _openComments(context, track),
                  onOpenMusicVideo: () => _openMusicVideo(context, track),
                ),
              ),
              VerticalDivider(
                width: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(child: lyrics),
            ],
          );
        }
        final heroHeight = math
            .min(constraints.maxWidth - 24, constraints.maxHeight * 0.46)
            .clamp(200.0, 360.0)
            .toDouble();
        return Column(
          key: const ValueKey('expanded-now-playing-compact-layout'),
          children: [
            SizedBox(
              width: double.infinity,
              height: heroHeight,
              child: _ExpandedTrackHero(
                track: track,
                compact: true,
                onOpenComments: () => _openComments(context, track),
                onOpenMusicVideo: () => _openMusicVideo(context, track),
              ),
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(child: lyrics),
          ],
        );
      },
    );
  }

  Widget _lyrics() {
    final lyrics = widget.controller.lyrics;
    if (lyrics == null) {
      return const _ExpandedLyricsUnavailable();
    }
    return LyricPanel(
      key: const ValueKey('expanded-now-playing-lyrics'),
      controller: lyrics,
      onClose: widget.onBack,
      onSignInAgain: widget.onSignInAgain,
      playbackState: widget.controller.playback,
      canSeek: () => widget.controller.playback.canSeek,
      onSeek: widget.controller.playback.seekToMs,
      showCloseButton: false,
    );
  }

  void _openComments(BuildContext context, PlaylistTrackSummary track) {
    unawaited(
      showTrackCommentsSurface(
        context: context,
        gateway: widget.commentsGateway,
        track: track,
        playbackController: widget.controller,
      ),
    );
  }

  void _openMusicVideo(BuildContext context, PlaylistTrackSummary track) {
    unawaited(
      showTrackMusicVideoSurface(
        context: context,
        gateway: widget.musicVideoGateway,
        engine: widget.musicVideoEngine,
        track: track,
        playbackController: widget.controller,
      ),
    );
  }

  void _readCurrent() {
    _track = widget.controller.current;
    _currentIndex = widget.controller.currentIndex;
  }

  void _handleControllerChanged() {
    final nextTrack = widget.controller.current;
    final nextIndex = widget.controller.currentIndex;
    if (identical(nextTrack, _track) && nextIndex == _currentIndex) return;
    setState(() {
      _track = nextTrack;
      _currentIndex = nextIndex;
    });
  }
}

class _ExpandedTrackHero extends StatelessWidget {
  const _ExpandedTrackHero({
    required this.track,
    required this.onOpenComments,
    required this.onOpenMusicVideo,
    this.compact = false,
  });

  final PlaylistTrackSummary track;
  final VoidCallback onOpenComments;
  final VoidCallback onOpenMusicVideo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final artists = track.artistNames.isEmpty
        ? 'Unknown artist'
        : track.artistNames.join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withValues(alpha: 0.78),
            colors.tertiaryContainer.withValues(alpha: 0.56),
            colors.surface,
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textReserve = compact ? 92.0 : 150.0;
          final maximum = compact ? 220.0 : 440.0;
          final artworkDimension = math
              .min(
                constraints.maxWidth - (compact ? 48 : 96),
                constraints.maxHeight - textReserve,
              )
              .clamp(88.0, maximum)
              .toDouble();
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 16 : 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ExpandedArtwork(track: track, dimension: artworkDimension),
                  SizedBox(height: compact ? 12 : 24),
                  Text(
                    track.title,
                    key: const ValueKey('expanded-now-playing-title'),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style:
                        (compact
                                ? theme.textTheme.titleLarge
                                : theme.textTheme.headlineMedium)
                            ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    artists,
                    key: const ValueKey('expanded-now-playing-artists'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (track.albumTitle case final albumTitle?)
                    Text(
                      albumTitle,
                      key: const ValueKey('expanded-now-playing-album'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  SizedBox(height: compact ? 8 : 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('expanded-now-playing-mv'),
                        onPressed: onOpenMusicVideo,
                        icon: const Icon(Icons.music_video_outlined),
                        label: const Text('MV'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('expanded-now-playing-comments'),
                        onPressed: onOpenComments,
                        icon: const Icon(Icons.mode_comment_outlined),
                        label: const Text('Comments'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ExpandedArtwork extends StatelessWidget {
  const _ExpandedArtwork({required this.track, required this.dimension});

  final PlaylistTrackSummary track;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.tertiaryContainer,
          ],
        ),
      ),
      child: Icon(
        Icons.album_rounded,
        size: dimension * 0.28,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
    return Semantics(
      image: true,
      label: 'Artwork for ${track.title}',
      child: SizedBox.square(
        key: const ValueKey('expanded-now-playing-artwork'),
        dimension: dimension,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_compactRadius(dimension)),
          child: track.artworkUri == null
              ? placeholder
              : Image.network(
                  track.artworkUri!,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : placeholder,
                  errorBuilder: (context, error, stackTrace) => placeholder,
                ),
        ),
      ),
    );
  }
}

double _compactRadius(double dimension) => math.min(32, dimension * 0.1);

class _ExpandedNowPlayingEmpty extends StatelessWidget {
  const _ExpandedNowPlayingEmpty({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    key: const ValueKey('expanded-now-playing-empty'),
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.queue_music_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Nothing is playing',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a track from your library, Search, or Discover.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.tonal(
            key: const ValueKey('expanded-now-playing-empty-back'),
            onPressed: onBack,
            child: const Text('Back to music'),
          ),
        ],
      ),
    ),
  );
}

class _ExpandedLyricsUnavailable extends StatelessWidget {
  const _ExpandedLyricsUnavailable();

  @override
  Widget build(BuildContext context) => Center(
    key: const ValueKey('expanded-now-playing-lyrics-unavailable'),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          const Text(
            'Lyrics are unavailable in this playback session.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
