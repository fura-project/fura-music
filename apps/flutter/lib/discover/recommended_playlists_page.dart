import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/discover/ranking_controller.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/discover/ranking_page.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

class RecommendedPlaylistsPage extends StatefulWidget {
  const RecommendedPlaylistsPage({
    required this.gateway,
    required this.rankingGateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onOpenPlaylist,
    required this.onOpenRanking,
    required this.onSignInAgain,
    super.key,
  });

  final RecommendedPlaylistGateway gateway;
  final RankingGateway rankingGateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final ValueChanged<RecommendedPlaylistSummary> onOpenPlaylist;
  final ValueChanged<RankingSummary> onOpenRanking;
  final VoidCallback onSignInAgain;

  @override
  State<RecommendedPlaylistsPage> createState() =>
      _RecommendedPlaylistsPageState();
}

class _RecommendedPlaylistsPageState extends State<RecommendedPlaylistsPage> {
  late final RecommendedPlaylistController _controller;
  late final RankingGroupController _rankingController;
  _DiscoverType _type = _DiscoverType.playlists;
  bool _rankingsVisited = false;

  @override
  void initState() {
    super.initState();
    _controller = RecommendedPlaylistController(widget.gateway);
    _rankingController = RankingGroupController(widget.rankingGateway);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _rankingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        key: const ValueKey('recommendations-back'),
        tooltip: 'Back to your music',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Discover'),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, _rankingController]),
        builder: (context, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<_DiscoverType>(
                  key: const ValueKey('discover-type-selector'),
                  segments: const [
                    ButtonSegment(
                      value: _DiscoverType.playlists,
                      icon: Icon(Icons.queue_music_rounded),
                      label: Text('Playlists'),
                    ),
                    ButtonSegment(
                      value: _DiscoverType.rankings,
                      icon: Icon(Icons.leaderboard_rounded),
                      label: Text('Rankings'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (selection) =>
                      _selectType(selection.single),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _type == _DiscoverType.playlists
                    ? _playlistBody()
                    : _rankingBody(),
              ),
            ),
          ],
        ),
      ),
    ),
    bottomNavigationBar: NowPlayingBar(
      controller: widget.queuePlaybackController,
      onSignInAgain: widget.onSignInAgain,
    ),
  );

  Widget _playlistBody() => switch (_controller.stage) {
    RecommendedPlaylistStage.loading => const Center(
      key: ValueKey('recommendations-loading'),
      child: CircularProgressIndicator(),
    ),
    RecommendedPlaylistStage.empty => const _RecommendationMessage(
      key: ValueKey('recommendations-empty'),
      icon: Icons.explore_off_outlined,
      title: 'No recommendations right now',
      detail: 'QQ Music returned an empty recommended-playlist page.',
    ),
    RecommendedPlaylistStage.error => _RecommendationMessage(
      key: const ValueKey('recommendations-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load recommendations',
      detail: _failureCopy(_controller.failure),
      liveRegion: true,
      action: _controller.canRetry
          ? FilledButton.tonal(
              onPressed: _controller.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    RecommendedPlaylistStage.content => _RecommendationCollection(
      key: const ValueKey('recommendations-content'),
      playlists: _controller.playlists,
      hasMore: _controller.hasMore,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
      onSelected: widget.onOpenPlaylist,
    ),
  };

  Widget _rankingBody() => switch (_rankingController.stage) {
    RankingGroupStage.loading => const Center(
      key: ValueKey('rankings-loading'),
      child: CircularProgressIndicator(),
    ),
    RankingGroupStage.empty => const _RecommendationMessage(
      key: ValueKey('rankings-empty'),
      icon: Icons.leaderboard_outlined,
      title: 'No rankings right now',
      detail: 'QQ Music returned no current ranking groups.',
    ),
    RankingGroupStage.error => _RecommendationMessage(
      key: const ValueKey('rankings-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load rankings',
      detail: rankingFailureCopy(_rankingController.failure),
      liveRegion: true,
      action: _rankingController.canRetry
          ? FilledButton.tonal(
              onPressed: _rankingController.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    RankingGroupStage.content => _RankingCollection(
      key: const ValueKey('rankings-content'),
      groups: _rankingController.groups,
      onSelected: widget.onOpenRanking,
    ),
  };

  void _selectType(_DiscoverType type) {
    if (_type == type) return;
    setState(() => _type = type);
    if (type == _DiscoverType.rankings && !_rankingsVisited) {
      _rankingsVisited = true;
      unawaited(_rankingController.load());
    }
  }
}

enum _DiscoverType { playlists, rankings }

class _RankingCollection extends StatelessWidget {
  const _RankingCollection({
    required this.groups,
    required this.onSelected,
    super.key,
  });

  final List<RankingGroup> groups;
  final ValueChanged<RankingSummary> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      return ListView(
        key: const PageStorageKey<String>('ranking-groups'),
        padding: EdgeInsets.fromLTRB(
          desktop ? 48 : 16,
          desktop ? 24 : 16,
          desktop ? 48 : 16,
          28,
        ),
        children: [
          Text(
            'QQ Music rankings',
            style:
                (desktop
                        ? Theme.of(context).textTheme.headlineMedium
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Current charts from QQ Music',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: desktop ? 28 : 20),
          for (final group in groups) ...[
            Semantics(
              header: true,
              child: Text(
                group.title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            if (desktop)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final ranking in group.rankings)
                    SizedBox(
                      width: 280,
                      child: _RankingTile(
                        ranking: ranking,
                        onTap: () => onSelected(ranking),
                      ),
                    ),
                ],
              )
            else
              for (final ranking in group.rankings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RankingTile(
                    ranking: ranking,
                    onTap: () => onSelected(ranking),
                  ),
                ),
            const SizedBox(height: 24),
          ],
        ],
      );
    },
  );
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({required this.ranking, required this.onTap});

  final RankingSummary ranking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = <String>[];
    if (ranking.period case final period?) details.add(period);
    if (ranking.trackCount case final count?) details.add('$count Tracks');
    final semantic = details.isEmpty
        ? ranking.title
        : '${ranking.title}, ${details.join(', ')}';
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: ListTile(
        key: ValueKey('ranking-${ranking.opaqueId}'),
        minTileHeight: 80,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: SizedBox.square(
          dimension: 60,
          child: RankingArtwork(uri: ranking.artworkUri),
        ),
        title: Text(
          ranking.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: details.isEmpty
            ? const Text('Current ranking')
            : Text(details.join(' · ')),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _RecommendationCollection extends StatelessWidget {
  const _RecommendationCollection({
    required this.playlists,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onSelected,
    super.key,
  });

  final List<RecommendedPlaylistSummary> playlists;
  final bool hasMore;
  final bool isLoadingMore;
  final RecommendedPlaylistFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      final header = Padding(
        padding: EdgeInsets.fromLTRB(
          desktop ? 48 : 20,
          desktop ? 24 : 16,
          desktop ? 48 : 20,
          desktop ? 24 : 16,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recommended playlists',
                style:
                    (desktop
                            ? Theme.of(context).textTheme.headlineMedium
                            : Theme.of(context).textTheme.headlineSmall)
                        ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Public picks from QQ Music',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
      final footer = _RecommendationFooter(
        hasMore: hasMore,
        isLoadingMore: isLoadingMore,
        appendFailure: appendFailure,
        onLoadMore: onLoadMore,
        onRetryMore: onRetryMore,
      );
      return Column(
        children: [
          header,
          Expanded(
            child: desktop
                ? GridView.builder(
                    key: const PageStorageKey<String>(
                      'recommended-playlist-grid',
                    ),
                    padding: const EdgeInsets.fromLTRB(48, 0, 48, 24),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisExtent: 270,
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 28,
                        ),
                    itemCount: playlists.length + 1,
                    itemBuilder: (context, index) => index == playlists.length
                        ? footer
                        : _RecommendationGridItem(
                            key: ValueKey('recommendations-item-$index'),
                            playlist: playlists[index],
                            onTap: () => onSelected(playlists[index]),
                          ),
                  )
                : ListView.separated(
                    key: const PageStorageKey<String>(
                      'recommended-playlist-list',
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: playlists.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => index == playlists.length
                        ? footer
                        : _RecommendationListItem(
                            key: ValueKey('recommendations-item-$index'),
                            playlist: playlists[index],
                            onTap: () => onSelected(playlists[index]),
                          ),
                  ),
          ),
        ],
      );
    },
  );
}

class _RecommendationGridItem extends StatelessWidget {
  const _RecommendationGridItem({
    required this.playlist,
    required this.onTap,
    super.key,
  });

  final RecommendedPlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _semanticLabel(playlist),
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _RecommendationArtwork(uri: playlist.artworkUri)),
          const SizedBox(height: 12),
          Text(
            playlist.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
          ),
          if (playlist.trackCount case final count?) ...[
            const SizedBox(height: 4),
            Text(
              '$count tracks',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _RecommendationListItem extends StatelessWidget {
  const _RecommendationListItem({
    required this.playlist,
    required this.onTap,
    super.key,
  });

  final RecommendedPlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _semanticLabel(playlist),
    excludeSemantics: true,
    onTap: onTap,
    child: ListTile(
      minTileHeight: 80,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: SizedBox.square(
        dimension: 60,
        child: _RecommendationArtwork(uri: playlist.artworkUri),
      ),
      title: Text(playlist.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: playlist.trackCount != null
          ? Text('${playlist.trackCount} tracks')
          : const Text('QQ Music playlist'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _RecommendationArtwork extends StatelessWidget {
  const _RecommendationArtwork({this.uri});

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
      child: Icon(Icons.queue_music_rounded, color: colors.onPrimaryContainer),
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

class _RecommendationFooter extends StatelessWidget {
  const _RecommendationFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final RecommendedPlaylistFailure? appendFailure;
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
              key: const ValueKey('recommendations-load-more'),
              onPressed: onLoadMore,
              child: const Text('Load more'),
            )
          : Text(
              'End of recommendations',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

class _RecommendationMessage extends StatelessWidget {
  const _RecommendationMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
    this.liveRegion = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      container: true,
      liveRegion: liveRegion,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    ),
  );
}

String _semanticLabel(RecommendedPlaylistSummary playlist) {
  final count = playlist.trackCount;
  return count == null ? playlist.title : '${playlist.title}, $count tracks';
}

String _failureCopy(RecommendedPlaylistFailure? failure) => switch (failure) {
  RecommendedPlaylistFailure.network => 'Check your connection and try again.',
  RecommendedPlaylistFailure.serviceUnavailable =>
    'QQ Music recommendations are temporarily unavailable.',
  RecommendedPlaylistFailure.cancelled =>
    'The recommendation request was cancelled.',
  RecommendedPlaylistFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  RecommendedPlaylistFailure.invalidResponse ||
  RecommendedPlaylistFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected recommendation response.',
};
