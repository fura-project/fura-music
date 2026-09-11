import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/catalog/music_collection_detail_layout.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/discover/ranking_controller.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

class RankingPage extends StatefulWidget {
  const RankingPage({
    required this.ranking,
    required this.gateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onSignInAgain,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.onHeaderCollapsedChanged,
    this.embedded = false,
    super.key,
  });

  final RankingSummary ranking;
  final RankingGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;
  final ValueChanged<bool>? onHeaderCollapsedChanged;
  final bool embedded;

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  late final RankingTrackController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RankingTrackController(widget.ranking, widget.gateway);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toolbar = AppBar(
      leading: IconButton(
        key: const ValueKey('ranking-back'),
        tooltip: 'Back to rankings',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Ranking'),
    );
    final body = SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => MusicCollectionDetailLayout(
          key: ValueKey('ranking-detail-layout-${widget.ranking.opaqueId}'),
          onHeaderCollapsedChanged: widget.onHeaderCollapsedChanged,
          headerBuilder: (context, desktop, progress) => _RankingHeader(
            ranking: _controller.ranking,
            total:
                _controller.stage == RankingTrackStage.content ||
                    _controller.stage == RankingTrackStage.empty
                ? _controller.total
                : null,
            desktop: desktop,
            collapseProgress: progress,
            embedded: widget.embedded,
            onBack: widget.onBack,
          ),
          bodyBuilder: (context, desktop) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _body(desktop),
          ),
        ),
      ),
    );
    if (widget.embedded) {
      return ColoredBox(
        key: const ValueKey('embedded-ranking-detail'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: body,
      );
    }
    return Scaffold(
      appBar: toolbar,
      body: body,
      bottomNavigationBar: NowPlayingBar(
        controller: widget.queuePlaybackController,
        onSignInAgain: widget.onSignInAgain,
      ),
    );
  }

  Widget _body(bool desktop) => switch (_controller.stage) {
    RankingTrackStage.loading => const MusicLoadingPanel(
      key: ValueKey('ranking-tracks-loading'),
      label: 'Loading Ranking Tracks',
    ),
    RankingTrackStage.empty => const MusicContentStatePanel(
      key: ValueKey('ranking-tracks-empty'),
      icon: Icons.leaderboard_outlined,
      title: 'This ranking has no available Tracks',
      detail: 'QQ Music returned an empty current-ranking Track list.',
    ),
    RankingTrackStage.error => MusicContentStatePanel(
      key: const ValueKey('ranking-tracks-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load this ranking',
      detail: rankingFailureCopy(_controller.failure),
      liveRegion: true,
      action: _controller.canRetry
          ? FilledButton.tonal(
              onPressed: _controller.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    RankingTrackStage.content => _RankingTracks(
      key: const ValueKey('ranking-tracks-content'),
      tracks: _controller.tracks,
      total: _controller.total,
      hasMore: _controller.hasMore,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
      onPlay: _play,
      onQueue: _queue,
      onOpenAlbum: widget.onOpenAlbum,
      onOpenArtist: widget.onOpenArtist,
      current: widget.queuePlaybackController.current,
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

class _RankingHeader extends StatelessWidget {
  const _RankingHeader({
    required this.ranking,
    required this.total,
    required this.desktop,
    required this.collapseProgress,
    required this.embedded,
    required this.onBack,
  });

  final RankingSummary ranking;
  final int? total;
  final bool desktop;
  final double collapseProgress;
  final bool embedded;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return MusicCollectionDetailHeader(
      collapseProgress: collapseProgress,
      desktop: desktop,
      embedded: embedded,
      artwork: RankingArtwork(uri: ranking.artworkUri),
      eyebrow: 'QQ MUSIC RANKING',
      title: ranking.title,
      titleKey: const ValueKey('ranking-title'),
      summary: [
        ?ranking.period,
        if (total case final count?)
          '$count ${count == 1 ? 'Track' : 'Tracks'}',
      ].join(' · '),
      onBack: onBack,
      backKey: const ValueKey('ranking-back'),
      backTooltip: 'Back to rankings',
    );
  }
}

class _RankingTracks extends StatefulWidget {
  const _RankingTracks({
    required this.tracks,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onPlay,
    required this.onQueue,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required this.current,
    required this.desktop,
    super.key,
  });

  final List<PlaylistTrackSummary> tracks;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;
  final RankingFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<int> onPlay;
  final ValueChanged<PlaylistTrackSummary> onQueue;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;
  final PlaylistTrackSummary? current;
  final bool desktop;

  @override
  State<_RankingTracks> createState() => _RankingTracksState();
}

class _RankingTracksState extends State<_RankingTracks> {
  (String, String)? _hoveredTrack;

  bool _handleScroll(ScrollNotification notification) {
    if (_hoveredTrack != null && notification is ScrollUpdateNotification) {
      setState(() => _hoveredTrack = null);
    }
    return false;
  }

  void _setHovered(PlaylistTrackSummary track, bool hovered) {
    final identity = (track.providerId, track.opaqueId);
    if (hovered && _hoveredTrack != identity) {
      setState(() => _hoveredTrack = identity);
    } else if (!hovered && _hoveredTrack == identity) {
      setState(() => _hoveredTrack = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.desktop ? 24.0 : 10.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(
          children: [
            if (widget.desktop)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                child: const MusicTrackTableHeader(
                  key: ValueKey('ranking-track-table-header'),
                  titleLabel: 'Title',
                  artistLabel: 'Artist',
                  albumLabel: 'Album',
                  durationLabel: 'Duration',
                ),
              ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScroll,
                child: ListView.separated(
                  key: const PageStorageKey('ranking-tracks'),
                  padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 24),
                  itemCount: widget.tracks.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 1),
                  itemBuilder: (context, index) {
                    if (index == widget.tracks.length) {
                      return _RankingFooter(
                        shown: widget.tracks.length,
                        total: widget.total,
                        hasMore: widget.hasMore,
                        isLoadingMore: widget.isLoadingMore,
                        appendFailure: widget.appendFailure,
                        onLoadMore: widget.onLoadMore,
                        onRetryMore: widget.onRetryMore,
                      );
                    }
                    final track = widget.tracks[index];
                    final identity = (track.providerId, track.opaqueId);
                    final selected =
                        widget.current?.providerId == track.providerId &&
                        widget.current?.opaqueId == track.opaqueId;
                    final artists = track.artistNames.isEmpty
                        ? 'Unknown artist'
                        : track.artistNames.join(' / ');
                    return MusicTrackRowSurface(
                      key: ValueKey(
                        'ranking-track-state-${track.providerId}-${track.opaqueId}',
                      ),
                      itemKey: ValueKey('ranking-track-$index'),
                      desktop: widget.desktop,
                      current: selected,
                      hovered: _hoveredTrack == identity,
                      onHoverChanged: (hovered) => _setHovered(track, hovered),
                      semanticLabel: '${track.title}, $artists',
                      onTap: () => widget.onPlay(index),
                      onContextMenuRequested: (_) =>
                          unawaited(_showActions(track, index)),
                      contentBuilder: (context, active, hovered) =>
                          MusicTrackRowContent(
                            index: index + 1,
                            track: track,
                            desktop: widget.desktop,
                            current: selected,
                            active: active,
                            artistNames: artists,
                            onPlay: () => widget.onPlay(index),
                            onAddToQueue: () => widget.onQueue(track),
                            onOpenAlbum:
                                widget.onOpenAlbum == null ||
                                    track.album == null
                                ? null
                                : () => widget.onOpenAlbum!(track.album!),
                            onOpenArtist:
                                widget.onOpenArtist == null ||
                                    track.artists.isEmpty
                                ? null
                                : () => _openArtist(track),
                            onMore: () => unawaited(_showActions(track, index)),
                            showInlineQueueAction: hovered,
                            queueKey: ValueKey('ranking-queue-$index'),
                            moreKey: ValueKey('ranking-context-$index'),
                            artistTooltip: track.artists.length > 1
                                ? 'Choose artist'
                                : 'Open artist',
                          ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(PlaylistTrackSummary track, int index) async {
    final canOpenAlbum = widget.onOpenAlbum != null && track.album != null;
    final action = await showModalBottomSheet<MusicTrackAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Play from here'),
              onTap: () => Navigator.pop(context, MusicTrackAction.play),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Add to queue'),
              onTap: () => Navigator.pop(context, MusicTrackAction.addToQueue),
            ),
            if (canOpenAlbum)
              ListTile(
                leading: const Icon(Icons.album_rounded),
                title: const Text('Open album'),
                onTap: () => Navigator.pop(context, MusicTrackAction.openAlbum),
              ),
            if (widget.onOpenArtist != null && track.artists.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: Text(
                  track.artists.length > 1 ? 'Choose artist' : 'Open artist',
                ),
                onTap: () =>
                    Navigator.pop(context, MusicTrackAction.openArtist),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (action) {
      case MusicTrackAction.play:
        widget.onPlay(index);
      case MusicTrackAction.addToQueue:
        widget.onQueue(track);
      case MusicTrackAction.openAlbum:
        widget.onOpenAlbum!(track.album!);
      case MusicTrackAction.openArtist:
        _openArtist(track);
      case null:
        return;
    }
  }

  void _openArtist(PlaylistTrackSummary track) {
    unawaited(
      openMusicTrackArtists(
        context: context,
        artists: track.artists,
        onSelected: widget.onOpenArtist,
        itemKeyPrefix: 'ranking-track-artist',
      ),
    );
  }
}

class _RankingFooter extends StatelessWidget {
  const _RankingFooter({
    required this.shown,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final int shown;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;
  final RankingFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Text(
          'Showing $shown of $total Tracks',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (isLoadingMore)
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        else if (appendFailure != null)
          FilledButton.tonal(
            onPressed: onRetryMore,
            child: const Text('Try loading more again'),
          )
        else if (hasMore)
          FilledButton.tonal(
            key: const ValueKey('ranking-load-more'),
            onPressed: onLoadMore,
            child: const Text('Load more'),
          )
        else
          Text(
            'End of current ranking',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}

class RankingArtwork extends StatelessWidget {
  const RankingArtwork({this.uri, super.key});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      child: Icon(Icons.leaderboard_rounded, color: colors.onPrimaryContainer),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: uri == null
          ? placeholder
          : Image.network(
              uri!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

String rankingFailureCopy(RankingFailure? failure) => switch (failure) {
  RankingFailure.network => 'Check your connection and try again.',
  RankingFailure.serviceUnavailable =>
    'QQ Music rankings are temporarily unavailable.',
  RankingFailure.cancelled => 'The ranking request was cancelled.',
  RankingFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  RankingFailure.invalidResponse ||
  RankingFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected ranking response.',
};
