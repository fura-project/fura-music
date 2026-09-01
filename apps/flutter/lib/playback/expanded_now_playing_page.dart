import 'dart:async';
import 'dart:collection';
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
import 'package:flutterustmusic/theme/material_theme.dart';

typedef ArtworkImageProviderBuilder = ImageProvider<Object> Function(
  String artworkUri,
);

typedef ArtworkColorSchemeLoader = Future<ColorScheme> Function({
  required ImageProvider<Object> provider,
  required Brightness brightness,
});

class ArtworkColorSchemeCache {
  ArtworkColorSchemeCache({
    this.maximumEntries = 8,
    this.artworkImageProviderBuilder = _networkArtworkProvider,
    this.artworkColorSchemeLoader = _materialArtworkColorScheme,
  }) : assert(maximumEntries > 0);

  final int maximumEntries;
  final ArtworkImageProviderBuilder artworkImageProviderBuilder;
  final ArtworkColorSchemeLoader artworkColorSchemeLoader;
  final LinkedHashMap<_ArtworkPaletteKey, ColorScheme> _resolved =
      LinkedHashMap<_ArtworkPaletteKey, ColorScheme>();
  final Map<_ArtworkPaletteKey, Future<ColorScheme?>> _pending =
      <_ArtworkPaletteKey, Future<ColorScheme?>>{};

  ColorScheme? lookup({
    required String artworkUri,
    required Brightness brightness,
  }) {
    final key = _ArtworkPaletteKey(artworkUri, brightness);
    final scheme = _resolved.remove(key);
    if (scheme != null) _resolved[key] = scheme;
    return scheme;
  }

  Future<ColorScheme?> resolve({
    required String artworkUri,
    required Brightness brightness,
  }) {
    final cached = lookup(artworkUri: artworkUri, brightness: brightness);
    if (cached != null) return Future<ColorScheme?>.value(cached);
    final key = _ArtworkPaletteKey(artworkUri, brightness);
    return _pending[key] ??= _load(key);
  }

  Future<ColorScheme?> _load(_ArtworkPaletteKey key) async {
    try {
      final provider = artworkImageProviderBuilder(key.artworkUri);
      final scheme = await artworkColorSchemeLoader(
        provider: provider,
        brightness: key.brightness,
      );
      _resolved[key] = scheme;
      while (_resolved.length > maximumEntries) {
        _resolved.remove(_resolved.keys.first);
      }
      return scheme;
    } on Object {
      return null;
    } finally {
      _pending.remove(key);
    }
  }
}

@immutable
class _ArtworkPaletteKey {
  const _ArtworkPaletteKey(this.artworkUri, this.brightness);

  final String artworkUri;
  final Brightness brightness;

  @override
  bool operator ==(Object other) =>
      other is _ArtworkPaletteKey &&
      other.artworkUri == artworkUri &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(artworkUri, brightness);
}

class ExpandedNowPlayingPage extends StatefulWidget {
  const ExpandedNowPlayingPage({
    required this.controller,
    required this.onBack,
    required this.onSignInAgain,
    this.commentsGateway = const RustTrackCommentGateway(),
    this.musicVideoGateway = const RustTrackMusicVideoGateway(),
    this.musicVideoEngine = const MediaKitTrackMusicVideoEngine(),
    this.artworkImageProviderBuilder = _networkArtworkProvider,
    this.artworkColorSchemeLoader = _materialArtworkColorScheme,
    this.artworkColorSchemeCache,
    super.key,
  });

  final QueuePlaybackController controller;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final TrackCommentGateway commentsGateway;
  final TrackMusicVideoGateway musicVideoGateway;
  final TrackMusicVideoEngine musicVideoEngine;
  final ArtworkImageProviderBuilder artworkImageProviderBuilder;
  final ArtworkColorSchemeLoader artworkColorSchemeLoader;
  final ArtworkColorSchemeCache? artworkColorSchemeCache;

  @override
  State<ExpandedNowPlayingPage> createState() => _ExpandedNowPlayingPageState();
}

class _ExpandedNowPlayingPageState extends State<ExpandedNowPlayingPage> {
  String? _resolvedArtworkUri;
  Brightness? _resolvedBrightness;
  ColorScheme? _artworkColorScheme;
  late ArtworkColorSchemeCache _paletteCache;
  int _colorRequestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _paletteCache = _cacheFor(widget);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveArtworkColors(notify: false);
  }

  @override
  void didUpdateWidget(ExpandedNowPlayingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    final paletteSourceChanged =
        oldWidget.artworkColorSchemeCache != widget.artworkColorSchemeCache ||
        oldWidget.artworkImageProviderBuilder !=
            widget.artworkImageProviderBuilder ||
        oldWidget.artworkColorSchemeLoader != widget.artworkColorSchemeLoader;
    if (paletteSourceChanged) _paletteCache = _cacheFor(widget);
    if (oldWidget.controller != widget.controller || paletteSourceChanged) {
      _resolvedArtworkUri = null;
      _resolvedBrightness = null;
      _resolveArtworkColors(notify: false);
    }
  }

  @override
  void dispose() {
    _colorRequestGeneration += 1;
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final colors = _artworkColorScheme ?? baseTheme.colorScheme;
    final pageTheme = baseTheme.copyWith(
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: baseTheme.dividerTheme.copyWith(
        color: colors.outlineVariant,
      ),
      progressIndicatorTheme: baseTheme.progressIndicatorTheme.copyWith(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
        circularTrackColor: colors.surfaceContainerHighest,
      ),
    );
    return AnimatedTheme(
      data: pageTheme,
      duration: MusicMotion.stateChange,
      curve: Curves.easeOutCubic,
      child: Builder(
        builder: (context) => Scaffold(
          key: const ValueKey('expanded-now-playing-page'),
          appBar: AppBar(
            leading: IconButton(
              key: const ValueKey('expanded-now-playing-back'),
              tooltip: 'Back to previous page',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            title: const Text('Now playing'),
          ),
          body: _ExpandedNowPlayingBackdrop(
            key: const ValueKey('expanded-now-playing-palette-ready'),
            child: _ExpandedNowPlayingBody(
              controller: widget.controller,
              onBack: widget.onBack,
              onSignInAgain: widget.onSignInAgain,
              commentsGateway: widget.commentsGateway,
              musicVideoGateway: widget.musicVideoGateway,
              musicVideoEngine: widget.musicVideoEngine,
              artworkImageProviderBuilder: widget.artworkImageProviderBuilder,
            ),
          ),
          bottomNavigationBar: NowPlayingBar.expanded(
            controller: widget.controller,
            onSignInAgain: widget.onSignInAgain,
          ),
        ),
      ),
    );
  }

  void _handleControllerChanged() => _resolveArtworkColors();

  ArtworkColorSchemeCache _cacheFor(ExpandedNowPlayingPage page) =>
      page.artworkColorSchemeCache ??
      ArtworkColorSchemeCache(
        artworkImageProviderBuilder: page.artworkImageProviderBuilder,
        artworkColorSchemeLoader: page.artworkColorSchemeLoader,
      );

  void _resolveArtworkColors({bool notify = true}) {
    if (!mounted) return;
    final brightness = Theme.of(context).brightness;
    final artworkUri = widget.controller.current?.artworkUri;
    if (_resolvedArtworkUri == artworkUri &&
        _resolvedBrightness == brightness) {
      return;
    }
    final generation = ++_colorRequestGeneration;
    _resolvedArtworkUri = artworkUri;
    _resolvedBrightness = brightness;
    _artworkColorScheme = artworkUri == null
        ? null
        : _paletteCache.lookup(artworkUri: artworkUri, brightness: brightness);
    if (notify) setState(() {});
    if (artworkUri == null || _artworkColorScheme != null) return;

    _paletteCache.resolve(artworkUri: artworkUri, brightness: brightness).then((
      scheme,
    ) {
      if (!mounted || generation != _colorRequestGeneration || scheme == null) {
        return;
      }
      setState(() => _artworkColorScheme = scheme);
    });
  }
}

ImageProvider<Object> _networkArtworkProvider(String artworkUri) =>
    NetworkImage(artworkUri);

Future<ColorScheme> _materialArtworkColorScheme({
  required ImageProvider<Object> provider,
  required Brightness brightness,
}) => ColorScheme.fromImageProvider(
  provider: provider,
  brightness: brightness,
  dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
);

class _ExpandedNowPlayingBackdrop extends StatelessWidget {
  const _ExpandedNowPlayingBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final surface = colors.surface;
    return DecoratedBox(
      key: const ValueKey('expanded-now-playing-artwork-backdrop'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              colors.primaryContainer.withValues(alpha: dark ? 0.34 : 0.52),
              surface,
            ),
            Color.alphaBlend(
              colors.tertiaryContainer.withValues(alpha: dark ? 0.18 : 0.3),
              surface,
            ),
            surface,
          ],
          stops: const [0, 0.48, 1],
        ),
      ),
      child: child,
    );
  }
}

class _ExpandedNowPlayingBody extends StatefulWidget {
  const _ExpandedNowPlayingBody({
    required this.controller,
    required this.onBack,
    required this.onSignInAgain,
    required this.commentsGateway,
    required this.musicVideoGateway,
    required this.musicVideoEngine,
    required this.artworkImageProviderBuilder,
  });

  final QueuePlaybackController controller;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final TrackCommentGateway commentsGateway;
  final TrackMusicVideoGateway musicVideoGateway;
  final TrackMusicVideoEngine musicVideoEngine;
  final ArtworkImageProviderBuilder artworkImageProviderBuilder;

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
          return Padding(
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: Row(
                  key: const ValueKey('expanded-now-playing-wide-layout'),
                  children: [
                    Expanded(
                      flex: 5,
                      child: _ExpandedTrackHero(
                        track: track,
                        artworkImageProviderBuilder:
                            widget.artworkImageProviderBuilder,
                        onOpenComments: () => _openComments(context, track),
                        onOpenMusicVideo: () => _openMusicVideo(context, track),
                      ),
                    ),
                    const SizedBox(width: 40),
                    Expanded(
                      flex: 6,
                      child: _ExpandedLyricsSurface(child: lyrics),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final heroHeight = math
            .min(constraints.maxWidth * 0.52, constraints.maxHeight * 0.38)
            .clamp(176.0, 240.0)
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
                artworkImageProviderBuilder: widget.artworkImageProviderBuilder,
                onOpenComments: () => _openComments(context, track),
                onOpenMusicVideo: () => _openMusicVideo(context, track),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _ExpandedLyricsSurface(child: lyrics),
              ),
            ),
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
      immersive: true,
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

class _ExpandedLyricsSurface extends StatelessWidget {
  const _ExpandedLyricsSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('expanded-now-playing-lyrics-surface'),
      color: colors.surfaceContainerLowest.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: MusicRadii.panel,
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _ExpandedTrackHero extends StatelessWidget {
  const _ExpandedTrackHero({
    required this.track,
    required this.artworkImageProviderBuilder,
    required this.onOpenComments,
    required this.onOpenMusicVideo,
    this.compact = false,
  });

  final PlaylistTrackSummary track;
  final ArtworkImageProviderBuilder artworkImageProviderBuilder;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (compact) {
          final artworkDimension = math
              .min(136.0, constraints.maxHeight - 32)
              .clamp(96.0, 136.0)
              .toDouble();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                _ExpandedArtwork(
                  track: track,
                  dimension: artworkDimension,
                  imageProviderBuilder: artworkImageProviderBuilder,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        key: const ValueKey('expanded-now-playing-title'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        artists,
                        key: const ValueKey('expanded-now-playing-artists'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (track.albumTitle case final albumTitle?)
                        Text(
                          albumTitle,
                          key: const ValueKey('expanded-now-playing-album'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton.filledTonal(
                            key: const ValueKey('expanded-now-playing-mv'),
                            tooltip: 'Open music video',
                            onPressed: onOpenMusicVideo,
                            icon: const Icon(Icons.music_video_outlined),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            key: const ValueKey(
                              'expanded-now-playing-comments',
                            ),
                            tooltip: 'Open comments',
                            onPressed: onOpenComments,
                            icon: const Icon(Icons.mode_comment_outlined),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final artworkDimension = math
            .min(constraints.maxWidth - 96, constraints.maxHeight * 0.58)
            .clamp(160.0, 420.0)
            .toDouble();
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ExpandedArtwork(
                  track: track,
                  dimension: artworkDimension,
                  imageProviderBuilder: artworkImageProviderBuilder,
                ),
                const SizedBox(height: 24),
                Text(
                  track.title,
                  key: const ValueKey('expanded-now-playing-title'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
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
    );
  }
}

class _ExpandedArtwork extends StatelessWidget {
  const _ExpandedArtwork({
    required this.track,
    required this.dimension,
    required this.imageProviderBuilder,
  });

  final PlaylistTrackSummary track;
  final double dimension;
  final ArtworkImageProviderBuilder imageProviderBuilder;

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
    final artworkUri = track.artworkUri;
    ImageProvider<Object>? provider;
    if (artworkUri != null) {
      try {
        provider = imageProviderBuilder(artworkUri);
      } on Object {
        provider = null;
      }
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_compactRadius(dimension) + 2),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Semantics(
        image: true,
        label: 'Artwork for ${track.title}',
        child: SizedBox.square(
          key: const ValueKey('expanded-now-playing-artwork'),
          dimension: dimension,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_compactRadius(dimension)),
            child: provider == null
                ? placeholder
                : Image(
                    image: provider,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    gaplessPlayback: true,
                    frameBuilder: (context, child, frame, synchronous) =>
                        synchronous || frame != null ? child : placeholder,
                    errorBuilder: (context, error, stackTrace) => placeholder,
                  ),
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
