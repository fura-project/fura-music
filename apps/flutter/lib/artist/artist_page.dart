import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_controller.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_controller.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/catalog/music_catalog_header.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/music_track_tile.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

class ArtistPage extends StatefulWidget {
  const ArtistPage({
    required this.artist,
    required this.gateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onSignInAgain,
    this.albumGateway,
    this.onOpenAlbum,
    this.backTooltip = 'Back',
    super.key,
  });

  final ArtistSummary artist;
  final ArtistTrackGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final ArtistAlbumGateway? albumGateway;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final String backTooltip;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

enum _ArtistSection { tracks, albums }

class _ArtistPageState extends State<ArtistPage> {
  late final ArtistController _controller;
  late final ArtistAlbumController _albumController;
  late final Listenable _controllers;
  _ArtistSection _section = _ArtistSection.tracks;

  @override
  void initState() {
    super.initState();
    _controller = ArtistController(widget.artist, widget.gateway);
    _albumController = ArtistAlbumController(
      widget.artist,
      widget.albumGateway ?? const RustArtistAlbumGateway(),
    );
    _controllers = Listenable.merge([_controller, _albumController]);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _albumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        key: const ValueKey('artist-back'),
        tooltip: widget.backTooltip,
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Artist'),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _controllers,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;
            return Column(
              children: [
                _ArtistHeader(
                  artist: widget.artist,
                  total: _visibleTotal,
                  totalLabel: _section == _ArtistSection.tracks
                      ? 'Track'
                      : 'Album',
                  desktop: desktop,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    desktop ? 48 : 20,
                    0,
                    desktop ? 48 : 20,
                    16,
                  ),
                  child: SegmentedButton<_ArtistSection>(
                    key: const ValueKey('artist-sections'),
                    segments: const [
                      ButtonSegment(
                        value: _ArtistSection.tracks,
                        icon: Icon(Icons.music_note_rounded),
                        label: Text('Tracks'),
                      ),
                      ButtonSegment(
                        value: _ArtistSection.albums,
                        icon: Icon(Icons.album_rounded),
                        label: Text('Albums'),
                      ),
                    ],
                    selected: {_section},
                    onSelectionChanged: _selectSection,
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _section == _ArtistSection.tracks
                        ? _trackBody(desktop)
                        : _albumBody(desktop),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
    bottomNavigationBar: NowPlayingBar(
      controller: widget.queuePlaybackController,
      onSignInAgain: widget.onSignInAgain,
    ),
  );

  int? get _visibleTotal => switch (_section) {
    _ArtistSection.tracks =>
      _controller.stage == ArtistTrackStage.content ? _controller.total : null,
    _ArtistSection.albums =>
      _albumController.stage == ArtistAlbumStage.content
          ? _albumController.total
          : null,
  };

  void _selectSection(Set<_ArtistSection> selected) {
    final section = selected.single;
    if (_section == section) return;
    setState(() => _section = section);
    if (section == _ArtistSection.albums) {
      unawaited(_albumController.load());
    }
  }

  Widget _trackBody(bool desktop) => switch (_controller.stage) {
    ArtistTrackStage.loading => const MusicLoadingPanel(
      key: ValueKey('artist-loading'),
      label: 'Loading Artist Tracks',
    ),
    ArtistTrackStage.empty => const MusicContentStatePanel(
      key: ValueKey('artist-empty'),
      icon: Icons.person_off_outlined,
      title: 'This Artist has no available Tracks',
      detail: 'QQ Music returned an empty Artist Track list.',
    ),
    ArtistTrackStage.error => MusicContentStatePanel(
      key: const ValueKey('artist-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load this Artist',
      detail: _failureCopy(_controller.failure),
      liveRegion: true,
      action: _controller.canRetry
          ? FilledButton.tonal(
              onPressed: _controller.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    ArtistTrackStage.content => _ArtistTracks(
      key: const ValueKey('artist-content'),
      tracks: _controller.tracks,
      hasMore: _controller.hasMore,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
      onPlay: _play,
      onQueue: _queue,
      onOpenAlbum: widget.onOpenAlbum,
      desktop: desktop,
    ),
  };

  Widget _albumBody(bool desktop) => switch (_albumController.stage) {
    ArtistAlbumStage.loading => const MusicLoadingPanel(
      key: ValueKey('artist-albums-loading'),
      label: 'Loading Artist Albums',
    ),
    ArtistAlbumStage.empty => const MusicContentStatePanel(
      key: ValueKey('artist-albums-empty'),
      icon: Icons.album_outlined,
      title: 'This Artist has no available Albums',
      detail: 'QQ Music returned an empty Artist Album list.',
    ),
    ArtistAlbumStage.error => MusicContentStatePanel(
      key: const ValueKey('artist-albums-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load this Artist’s Albums',
      detail: _albumFailureCopy(_albumController.failure),
      liveRegion: true,
      action: _albumController.canRetry
          ? FilledButton.tonal(
              onPressed: _albumController.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    ArtistAlbumStage.content => _ArtistAlbums(
      key: const ValueKey('artist-albums-content'),
      albums: _albumController.albums,
      hasMore: _albumController.hasMore,
      isLoadingMore: _albumController.isLoadingMore,
      appendFailure: _albumController.appendFailure,
      onLoadMore: _albumController.loadMore,
      onRetryMore: _albumController.retryMore,
      onOpen: widget.onOpenAlbum,
      desktop: desktop,
    ),
  };

  void _play(int index) {
    unawaited(
      widget.queuePlaybackController.replaceAndPlay(_controller.tracks, index),
    );
  }

  void _queue(PlaylistTrackSummary track) {
    final playbackStart = widget.queuePlaybackController.push(track);
    if (!mounted) {
      unawaited(playbackStart);
      return;
    }
    final message = widget.queuePlaybackController.failure == null
        ? 'Added to queue'
        : 'Couldn’t update the queue';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    unawaited(playbackStart);
  }
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({
    required this.artist,
    required this.total,
    required this.totalLabel,
    required this.desktop,
  });

  final ArtistSummary artist;
  final int? total;
  final String totalLabel;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final portrait = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      child: Icon(
        Icons.person_rounded,
        size: desktop ? 68 : 48,
        color: colors.onPrimaryContainer,
      ),
    );
    return MusicCatalogHeader(
      artwork: portrait,
      eyebrow: 'ARTIST',
      title: artist.name,
      titleKey: const ValueKey('artist-name'),
      desktop: desktop,
      children: [
        if (total case final count?) ...[
          const SizedBox(height: 8),
          Text('$count ${count == 1 ? totalLabel : '${totalLabel}s'}'),
        ],
      ],
    );
  }
}

class _ArtistAlbums extends StatelessWidget {
  const _ArtistAlbums({
    required this.albums,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onOpen,
    required this.desktop,
    super.key,
  });

  final List<AlbumSummary> albums;
  final bool hasMore;
  final bool isLoadingMore;
  final ArtistAlbumFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<AlbumSummary>? onOpen;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120),
      child: CustomScrollView(
        key: const PageStorageKey('artist-albums'),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              desktop ? 40 : 12,
              0,
              desktop ? 40 : 12,
              8,
            ),
            sliver: desktop
                ? SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisExtent: 262,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                        ),
                    itemCount: albums.length,
                    itemBuilder: (context, index) => _ArtistAlbumCard(
                      key: ValueKey('artist-album-$index'),
                      album: albums[index],
                      onOpen: onOpen,
                    ),
                  )
                : SliverList.builder(
                    itemCount: albums.length,
                    itemBuilder: (context, index) => _ArtistAlbumTile(
                      key: ValueKey('artist-album-$index'),
                      album: albums[index],
                      onOpen: onOpen,
                    ),
                  ),
          ),
          SliverToBoxAdapter(
            child: _ArtistAlbumFooter(
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              appendFailure: appendFailure,
              onLoadMore: onLoadMore,
              onRetryMore: onRetryMore,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ArtistAlbumTile extends StatelessWidget {
  const _ArtistAlbumTile({
    required this.album,
    required this.onOpen,
    super.key,
  });

  final AlbumSummary album;
  final ValueChanged<AlbumSummary>? onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 78,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    leading: SizedBox.square(
      dimension: 56,
      child: _ArtistAlbumArtwork(uri: album.artworkUri),
    ),
    title: Text(album.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: const Text('Album'),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onOpen == null ? null : () => onOpen!(album),
  );
}

class _ArtistAlbumCard extends StatelessWidget {
  const _ArtistAlbumCard({
    required this.album,
    required this.onOpen,
    super.key,
  });

  final AlbumSummary album;
  final ValueChanged<AlbumSummary>? onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onOpen == null ? null : () => onOpen!(album),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: _ArtistAlbumArtwork(uri: album.artworkUri),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            album.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'Album',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ArtistAlbumArtwork extends StatelessWidget {
  const _ArtistAlbumArtwork({required this.uri});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Icon(Icons.album_rounded, color: colors.onSecondaryContainer),
    );
    final artwork = uri == null
        ? fallback
        : Image.network(
            uri!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: artwork);
  }
}

class _ArtistAlbumFooter extends StatelessWidget {
  const _ArtistAlbumFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final ArtistAlbumFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: isLoadingMore
          ? const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : appendFailure != null
          ? FilledButton.tonal(
              key: const ValueKey('artist-albums-retry-more'),
              onPressed: onRetryMore,
              child: const Text('Try loading more again'),
            )
          : hasMore
          ? FilledButton.tonal(
              key: const ValueKey('artist-albums-load-more'),
              onPressed: onLoadMore,
              child: const Text('Load more'),
            )
          : Text(
              'End of Artist Albums',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

class _ArtistTracks extends StatelessWidget {
  const _ArtistTracks({
    required this.tracks,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onPlay,
    required this.onQueue,
    required this.onOpenAlbum,
    required this.desktop,
    super.key,
  });

  final List<PlaylistTrackSummary> tracks;
  final bool hasMore;
  final bool isLoadingMore;
  final ArtistTrackFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<int> onPlay;
  final ValueChanged<PlaylistTrackSummary> onQueue;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1040),
      child: ListView.builder(
        key: const PageStorageKey('artist-tracks'),
        padding: EdgeInsets.fromLTRB(
          desktop ? 40 : 12,
          0,
          desktop ? 40 : 12,
          24,
        ),
        itemCount: tracks.length + 1,
        itemBuilder: (context, index) {
          if (index == tracks.length) {
            return _ArtistFooter(
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              appendFailure: appendFailure,
              onLoadMore: onLoadMore,
              onRetryMore: onRetryMore,
            );
          }
          final track = tracks[index];
          return MusicTrackTile(
            itemKey: ValueKey('artist-track-$index'),
            queueKey: ValueKey('artist-queue-$index'),
            contextKey: ValueKey('artist-context-$index'),
            track: track,
            position: index + 1,
            desktop: desktop,
            onPlay: () => onPlay(index),
            onQueue: () => onQueue(track),
            onOpenAlbum: onOpenAlbum,
          );
        },
      ),
    ),
  );
}

class _ArtistFooter extends StatelessWidget {
  const _ArtistFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final ArtistTrackFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: isLoadingMore
          ? const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : appendFailure != null
          ? FilledButton.tonal(
              onPressed: onRetryMore,
              child: const Text('Try loading more again'),
            )
          : hasMore
          ? FilledButton.tonal(
              key: const ValueKey('artist-load-more'),
              onPressed: onLoadMore,
              child: const Text('Load more'),
            )
          : Text(
              'End of Artist Tracks',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

String _failureCopy(ArtistTrackFailure? failure) => switch (failure) {
  ArtistTrackFailure.network => 'Check your connection and try again.',
  ArtistTrackFailure.serviceUnavailable =>
    'QQ Music Artist browsing is temporarily unavailable.',
  ArtistTrackFailure.cancelled => 'The Artist request was cancelled.',
  ArtistTrackFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  ArtistTrackFailure.invalidResponse ||
  ArtistTrackFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected Artist response.',
};

String _albumFailureCopy(ArtistAlbumFailure? failure) => switch (failure) {
  ArtistAlbumFailure.network => 'Check your connection and try again.',
  ArtistAlbumFailure.serviceUnavailable =>
    'QQ Music Artist Album browsing is temporarily unavailable.',
  ArtistAlbumFailure.cancelled => 'The Artist Album request was cancelled.',
  ArtistAlbumFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  ArtistAlbumFailure.invalidResponse ||
  ArtistAlbumFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected Artist Album response.',
};
