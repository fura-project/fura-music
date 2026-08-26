import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/music_catalog_header.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/music_track_tile.dart';
import 'package:flutterustmusic/discover/ranking_controller.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
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
    super.key,
  });

  final RankingSummary ranking;
  final RankingGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        key: const ValueKey('ranking-back'),
        tooltip: 'Back to rankings',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Ranking'),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;
            return Column(
              children: [
                _RankingHeader(
                  ranking: _controller.ranking,
                  total:
                      _controller.stage == RankingTrackStage.content ||
                          _controller.stage == RankingTrackStage.empty
                      ? _controller.total
                      : null,
                  desktop: desktop,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _body(desktop),
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
  });

  final RankingSummary ranking;
  final int? total;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return MusicCatalogHeader(
      artwork: RankingArtwork(uri: ranking.artworkUri),
      eyebrow: 'QQ MUSIC RANKING',
      title: ranking.title,
      titleKey: const ValueKey('ranking-title'),
      desktop: desktop,
      children: [
        if (ranking.period case final period?) ...[
          const SizedBox(height: 6),
          Text(period),
        ],
        if (total case final count?) ...[
          const SizedBox(height: 6),
          Text('$count ${count == 1 ? 'Track' : 'Tracks'}'),
        ],
      ],
    );
  }
}

class _RankingTracks extends StatelessWidget {
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
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1040),
      child: ListView.builder(
        key: const PageStorageKey('ranking-tracks'),
        padding: EdgeInsets.fromLTRB(
          desktop ? 40 : 12,
          0,
          desktop ? 40 : 12,
          24,
        ),
        itemCount: tracks.length + 1,
        itemBuilder: (context, index) {
          if (index == tracks.length) {
            return _RankingFooter(
              shown: tracks.length,
              total: total,
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              appendFailure: appendFailure,
              onLoadMore: onLoadMore,
              onRetryMore: onRetryMore,
            );
          }
          final track = tracks[index];
          return MusicTrackTile(
            itemKey: ValueKey('ranking-track-$index'),
            queueKey: ValueKey('ranking-queue-$index'),
            track: track,
            position: index + 1,
            desktop: desktop,
            onPlay: () => onPlay(index),
            onQueue: () => onQueue(track),
          );
        },
      ),
    ),
  );
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
