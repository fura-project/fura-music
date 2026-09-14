import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/catalog/music_collection_detail_layout.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/discover/ranking_controller.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/provider_presentation.dart';

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
        tooltip: context.l10n.rankingBackTooltip,
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: Text(context.l10n.rankingTitle),
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
    RankingTrackStage.loading => MusicLoadingPanel(
      key: const ValueKey('ranking-tracks-loading'),
      label: context.l10n.rankingLoadingTracks,
    ),
    RankingTrackStage.empty => MusicContentStatePanel(
      key: const ValueKey('ranking-tracks-empty'),
      icon: Icons.leaderboard_outlined,
      title: context.l10n.rankingEmptyTitle,
      detail: context.l10n.rankingEmptyDetail(
        builtInProviderDisplayName(widget.ranking.providerId, context.l10n),
      ),
    ),
    RankingTrackStage.error => MusicContentStatePanel(
      key: const ValueKey('ranking-tracks-error'),
      icon: Icons.cloud_off_rounded,
      title: context.l10n.rankingFailureTitle,
      detail: rankingFailureCopy(
        context.l10n,
        _controller.failure,
        providerName: builtInProviderDisplayName(
          widget.ranking.providerId,
          context.l10n,
        ),
      ),
      liveRegion: true,
      action: _controller.canRetry
          ? FilledButton.tonal(
              onPressed: _controller.retry,
              child: Text(context.l10n.commonRetry),
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
        ? context.l10n.queueAddedMessage
        : context.l10n.queueUpdateFailureMessage;
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
      eyebrow: context.l10n.rankingEyebrow,
      title: ranking.title,
      titleKey: const ValueKey('ranking-title'),
      summary: [
        ?ranking.period,
        if (total case final count?) context.l10n.trackCount(count),
      ].join(' · '),
      onBack: onBack,
      backKey: const ValueKey('ranking-back'),
      backTooltip: context.l10n.rankingBackTooltip,
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
                child: MusicTrackTableHeader(
                  key: ValueKey('ranking-track-table-header'),
                  titleLabel: context.l10n.tableTitle,
                  artistLabel: context.l10n.tableArtist,
                  albumLabel: context.l10n.tableAlbum,
                  durationLabel: context.l10n.tableDuration,
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
                        ? context.l10n.trackUnknownArtist
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
                      semanticLabel: context.l10n.commonTrackSemantics(
                        artists,
                        track.title,
                      ),
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
                                ? context.l10n.commonChooseArtist
                                : context.l10n.commonOpenArtist,
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
              title: Text(context.l10n.commonPlayFromHere),
              onTap: () => Navigator.pop(context, MusicTrackAction.play),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(context.l10n.commonAddToQueue),
              onTap: () => Navigator.pop(context, MusicTrackAction.addToQueue),
            ),
            if (canOpenAlbum)
              ListTile(
                leading: const Icon(Icons.album_rounded),
                title: Text(context.l10n.commonOpenAlbum),
                onTap: () => Navigator.pop(context, MusicTrackAction.openAlbum),
              ),
            if (widget.onOpenArtist != null && track.artists.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: Text(
                  track.artists.length > 1
                      ? context.l10n.commonChooseArtist
                      : context.l10n.commonOpenArtist,
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
          context.l10n.rankingShowingTracks(shown, total),
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
            child: Text(context.l10n.commonTryLoadingMoreAgain),
          )
        else if (hasMore)
          FilledButton.tonal(
            key: const ValueKey('ranking-load-more'),
            onPressed: onLoadMore,
            child: Text(context.l10n.commonLoadMore),
          )
        else
          Text(
            context.l10n.rankingEnd,
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
              headers: musicArtworkRequestHeaders(uri!),
              fit: BoxFit.cover,
              errorBuilder: musicArtworkErrorBuilder(uri!, placeholder),
            ),
    );
  }
}

String rankingFailureCopy(
  AppLocalizations l10n,
  RankingFailure? failure, {
  required String providerName,
}) => switch (failure) {
  RankingFailure.network => l10n.commonNetworkFailure,
  RankingFailure.serviceUnavailable => l10n.rankingServiceFailure(providerName),
  RankingFailure.cancelled => l10n.rankingCancelled,
  RankingFailure.coreUnavailable => l10n.commonCoreUnavailable,
  RankingFailure.invalidResponse ||
  RankingFailure.alreadyRunning ||
  null => l10n.rankingUnexpected(providerName),
};
