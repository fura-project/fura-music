import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/discover/new_album_controller.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';
import 'package:flutterustmusic/discover/new_song_controller.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/discover/radar_controller.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/discover/ranking_controller.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/discover/ranking_page.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_scroll_prefetch.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class RecommendedPlaylistsPage extends StatefulWidget {
  const RecommendedPlaylistsPage({
    required this.gateway,
    required this.newAlbumGateway,
    required this.newSongGateway,
    required this.rankingGateway,
    required this.radarGateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onOpenPlaylist,
    required this.onOpenRanking,
    required this.onOpenAlbum,
    required this.onSignInAgain,
    this.controller,
    this.onOpenTrackAlbum,
    this.onOpenTrackArtist,
    this.onHeaderCollapsedChanged,
    this.embedded = false,
    super.key,
  });

  final RecommendedPlaylistGateway gateway;
  final NewAlbumGateway newAlbumGateway;
  final NewSongGateway newSongGateway;
  final RankingGateway rankingGateway;
  final RadarGateway radarGateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final ValueChanged<RecommendedPlaylistSummary> onOpenPlaylist;
  final ValueChanged<RankingSummary> onOpenRanking;
  final ValueChanged<AlbumSummary> onOpenAlbum;
  final VoidCallback onSignInAgain;
  final RecommendedPlaylistController? controller;
  final ValueChanged<AlbumSummary>? onOpenTrackAlbum;
  final ValueChanged<ArtistSummary>? onOpenTrackArtist;
  final ValueChanged<bool>? onHeaderCollapsedChanged;
  final bool embedded;

  @override
  State<RecommendedPlaylistsPage> createState() =>
      _RecommendedPlaylistsPageState();
}

class _RecommendedPlaylistsPageState extends State<RecommendedPlaylistsPage>
    with SingleTickerProviderStateMixin {
  late final RecommendedPlaylistController _controller;
  late final NewAlbumController _newAlbumController;
  late final NewSongController _newSongController;
  late final RankingGroupController _rankingController;
  late final RadarController _radarController;
  late final TabController _tabController;
  late final bool _ownsPlaylistController;
  _DiscoverType _type = _DiscoverType.playlists;
  bool _headerCollapsed = false;
  bool _userReturningToHeader = false;
  bool _rankingsVisited = false;
  bool _radarVisited = false;
  bool _newAlbumsVisited = false;
  bool _newSongsVisited = false;

  @override
  void initState() {
    super.initState();
    _ownsPlaylistController = widget.controller == null;
    _controller =
        widget.controller ?? RecommendedPlaylistController(widget.gateway);
    _newAlbumController = NewAlbumController(widget.newAlbumGateway);
    _newSongController = NewSongController(widget.newSongGateway);
    _rankingController = RankingGroupController(widget.rankingGateway);
    _radarController = RadarController(
      widget.radarGateway,
      initialPrefetchTarget: 10,
      maxInitialPrefetchPages: 2,
    );
    _tabController = TabController(
      length: _DiscoverType.values.length,
      vsync: this,
    );
    if (_ownsPlaylistController) unawaited(_controller.load());
  }

  @override
  void dispose() {
    if (_ownsPlaylistController) _controller.dispose();
    _newAlbumController.dispose();
    _newSongController.dispose();
    _rankingController.dispose();
    _radarController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _controller,
          _newAlbumController,
          _newSongController,
          _rankingController,
          _radarController,
          widget.queuePlaybackController,
        ]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;
            final compactPlayerVisible =
                constraints.maxWidth < 640 &&
                widget.queuePlaybackController.current != null;
            final bottomPadding = compactPlayerVisible ? 104.0 : 24.0;
            return Column(
              key: const ValueKey('discover-page-scroll'),
              children: [
                _DiscoverHeader(
                  desktop: desktop,
                  collapsed: _headerCollapsed,
                  tabs: _DiscoverTabs(
                    controller: _tabController,
                    onSelected: _selectType,
                  ),
                ),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleCollectionScroll,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: switch (_type) {
                        _DiscoverType.playlists => _playlistBody(bottomPadding),
                        _DiscoverType.rankings => _rankingBody(bottomPadding),
                        _DiscoverType.radar => _radarBody(bottomPadding),
                        _DiscoverType.newAlbums => _newAlbumBody(bottomPadding),
                        _DiscoverType.newSongs => _newSongBody(bottomPadding),
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('recommendations-back'),
          tooltip: 'Back to your music',
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Discover'),
      ),
      body: body,
      bottomNavigationBar: NowPlayingBar(
        controller: widget.queuePlaybackController,
        onSignInAgain: widget.onSignInAgain,
      ),
    );
  }

  Widget _playlistBody(double bottomPadding) => switch (_controller.stage) {
    RecommendedPlaylistStage.loading => const MusicLoadingPanel(
      key: ValueKey('recommendations-loading'),
      label: 'Loading Recommended Playlists',
    ),
    RecommendedPlaylistStage.empty => const MusicContentStatePanel(
      key: ValueKey('recommendations-empty'),
      icon: Icons.explore_off_outlined,
      title: 'No recommendations right now',
      detail: 'QQ Music returned an empty recommended-playlist page.',
    ),
    RecommendedPlaylistStage.error => MusicContentStatePanel(
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
      bottomPadding: bottomPadding,
    ),
  };

  Widget _rankingBody(double bottomPadding) =>
      switch (_rankingController.stage) {
        RankingGroupStage.loading => const MusicLoadingPanel(
          key: ValueKey('rankings-loading'),
          label: 'Loading QQ Music Rankings',
        ),
        RankingGroupStage.empty => const MusicContentStatePanel(
          key: ValueKey('rankings-empty'),
          icon: Icons.leaderboard_outlined,
          title: 'No rankings right now',
          detail: 'QQ Music returned no current ranking groups.',
        ),
        RankingGroupStage.error => MusicContentStatePanel(
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
          bottomPadding: bottomPadding,
        ),
      };

  Widget _radarBody(double bottomPadding) => switch (_radarController.stage) {
    RadarStage.loading => const MusicLoadingPanel(
      key: ValueKey('radar-loading'),
      label: 'Loading QQ Music Radar',
    ),
    RadarStage.empty => const MusicContentStatePanel(
      key: ValueKey('radar-empty'),
      icon: Icons.radar_rounded,
      title: 'No Radar Tracks right now',
      detail: 'QQ Music returned an empty Radar Track page.',
    ),
    RadarStage.error => MusicContentStatePanel(
      key: const ValueKey('radar-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load Radar',
      detail: radarFailureCopy(_radarController.failure),
      liveRegion: true,
      action: _radarFailureAction(_radarController.failure),
    ),
    RadarStage.content => _RadarCollection(
      key: const ValueKey('radar-content'),
      controller: _radarController,
      tracks: _radarController.tracks,
      hasMore: _radarController.hasMore,
      isLoadingMore: _radarController.isLoadingMore,
      appendFailure: _radarController.appendFailure,
      canRetryMore: _radarController.canRetryMore,
      onRetryMore: _radarController.retryMore,
      onReload: () => unawaited(_radarController.load()),
      onSignInAgain: widget.onSignInAgain,
      onPlay: _playRadar,
      onQueue: _queueRadar,
      onOpenAlbum: widget.onOpenTrackAlbum,
      onOpenArtist: widget.onOpenTrackArtist,
      current: widget.queuePlaybackController.current,
      bottomPadding: bottomPadding,
    ),
  };

  Widget _newAlbumBody(double bottomPadding) => _NewAlbumShell(
    key: const ValueKey('new-albums-shell'),
    region: _newAlbumController.region,
    onRegionSelected: _newAlbumController.selectRegion,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: switch (_newAlbumController.stage) {
        NewAlbumStage.loading => const MusicLoadingPanel(
          key: ValueKey('new-albums-loading'),
          label: 'Loading New Albums',
        ),
        NewAlbumStage.empty => const MusicContentStatePanel(
          key: ValueKey('new-albums-empty'),
          icon: Icons.album_outlined,
          title: 'No new albums right now',
          detail: 'QQ Music returned an empty page for this region.',
        ),
        NewAlbumStage.error => MusicContentStatePanel(
          key: const ValueKey('new-albums-error'),
          icon: Icons.cloud_off_rounded,
          title: 'Couldn’t load new albums',
          detail: newAlbumFailureCopy(_newAlbumController.failure),
          liveRegion: true,
          action: _newAlbumController.canRetry
              ? FilledButton.tonal(
                  onPressed: _newAlbumController.retry,
                  child: const Text('Try again'),
                )
              : null,
        ),
        NewAlbumStage.content => _NewAlbumCollection(
          key: const ValueKey('new-albums-content'),
          region: _newAlbumController.region,
          releases: _newAlbumController.releases,
          hasMore: _newAlbumController.hasMore,
          isLoadingMore: _newAlbumController.isLoadingMore,
          appendFailure: _newAlbumController.appendFailure,
          onLoadMore: _newAlbumController.loadMore,
          onRetryMore: _newAlbumController.retryMore,
          onSelected: (release) => widget.onOpenAlbum(release.album),
          bottomPadding: bottomPadding,
        ),
      },
    ),
  );

  Widget _newSongBody(double bottomPadding) => _NewSongShell(
    key: const ValueKey('new-songs-shell'),
    category: _newSongController.category,
    onCategorySelected: _newSongController.selectCategory,
    onPlay:
        _newSongController.stage == NewSongStage.content &&
            _newSongController.tracks.isNotEmpty
        ? () => _playNewSong(0)
        : null,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: switch (_newSongController.stage) {
        NewSongStage.loading => const MusicLoadingPanel(
          key: ValueKey('new-songs-loading'),
          label: 'Loading New Songs',
        ),
        NewSongStage.empty => const MusicContentStatePanel(
          key: ValueKey('new-songs-empty'),
          icon: Icons.music_off_rounded,
          title: 'No new songs right now',
          detail: 'QQ Music returned no Tracks for this category.',
        ),
        NewSongStage.error => MusicContentStatePanel(
          key: const ValueKey('new-songs-error'),
          icon: Icons.cloud_off_rounded,
          title: 'Couldn’t load new songs',
          detail: newSongFailureCopy(_newSongController.failure),
          liveRegion: true,
          action: _newSongController.canRetry
              ? FilledButton.tonal(
                  onPressed: _newSongController.retry,
                  child: const Text('Try again'),
                )
              : null,
        ),
        NewSongStage.content => _NewSongCollection(
          key: const ValueKey('new-songs-content'),
          category: _newSongController.category,
          tracks: _newSongController.tracks,
          onPlay: _playNewSong,
          onQueue: _queueNewSong,
          onOpenAlbum: widget.onOpenTrackAlbum,
          onOpenArtist: widget.onOpenTrackArtist,
          current: widget.queuePlaybackController.current,
          bottomPadding: bottomPadding,
        ),
      },
    ),
  );

  Widget? _radarFailureAction(RadarFailure? failure) {
    if (_radarRequiresSignIn(failure)) {
      return FilledButton.tonal(
        onPressed: widget.onSignInAgain,
        child: const Text('Sign in again'),
      );
    }
    if (_radarController.canRetry) {
      return FilledButton.tonal(
        onPressed: _radarController.retry,
        child: const Text('Try again'),
      );
    }
    if (failure == RadarFailure.replaced) {
      return FilledButton.tonal(
        onPressed: () => unawaited(_radarController.load()),
        child: const Text('Reload Radar'),
      );
    }
    return null;
  }

  void _playRadar(int index) {
    unawaited(
      widget.queuePlaybackController.replaceAndPlay(
        _radarController.tracks,
        index,
      ),
    );
  }

  void _queueRadar(PlaylistTrackSummary track) {
    _queueTrack(track);
  }

  void _playNewSong(int index) {
    unawaited(
      widget.queuePlaybackController.replaceAndPlay(
        _newSongController.tracks,
        index,
      ),
    );
  }

  void _queueNewSong(PlaylistTrackSummary track) {
    _queueTrack(track);
  }

  void _queueTrack(PlaylistTrackSummary track) {
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

  void _selectType(_DiscoverType type) {
    if (_type == type) return;
    if (_tabController.index != type.index) {
      _tabController.animateTo(type.index);
    }
    setState(() => _type = type);
    _setHeaderCollapsed(false);
    if (type == _DiscoverType.rankings && !_rankingsVisited) {
      _rankingsVisited = true;
      unawaited(_rankingController.load());
    }
    if (type == _DiscoverType.radar && !_radarVisited) {
      _radarVisited = true;
      unawaited(_radarController.load());
    }
    if (type == _DiscoverType.newAlbums && !_newAlbumsVisited) {
      _newAlbumsVisited = true;
      unawaited(_newAlbumController.load());
    }
    if (type == _DiscoverType.newSongs && !_newSongsVisited) {
      _newSongsVisited = true;
      unawaited(_newSongController.load());
    }
  }

  bool _handleCollectionScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        _userReturningToHeader = true;
      } else if (notification.direction == ScrollDirection.reverse) {
        _userReturningToHeader = false;
      }
    }
    final returnedToHeader =
        _headerCollapsed &&
        _userReturningToHeader &&
        notification.metrics.pixels <= 4;
    if (returnedToHeader) _userReturningToHeader = false;
    final collapse = _headerCollapsed
        ? !returnedToHeader
        : notification.metrics.pixels > 48;
    _setHeaderCollapsed(collapse);
    return false;
  }

  void _setHeaderCollapsed(bool collapsed) {
    if (collapsed == _headerCollapsed) return;
    if (!collapsed) _userReturningToHeader = false;
    setState(() => _headerCollapsed = collapsed);
    widget.onHeaderCollapsedChanged?.call(collapsed);
  }
}

enum _DiscoverType { playlists, rankings, radar, newAlbums, newSongs }

class _DiscoverHeader extends StatelessWidget {
  const _DiscoverHeader({
    required this.desktop,
    required this.collapsed,
    required this.tabs,
  });

  final bool desktop;
  final bool collapsed;
  final Widget tabs;

  @override
  Widget build(BuildContext context) {
    final horizontal = desktop
        ? MusicSpacing.pageWide
        : MusicSpacing.pageCompact;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : MusicMotion.stateChange;
    return TweenAnimationBuilder<double>(
      key: const ValueKey('discover-header-transition'),
      tween: Tween<double>(begin: collapsed ? 0 : 1, end: collapsed ? 0 : 1),
      duration: duration,
      curve: Curves.easeInOutCubic,
      builder: (context, progress, _) => Padding(
        key: ValueKey(
          collapsed ? 'discover-collapsed-header' : 'discover-expanded-header',
        ),
        padding: EdgeInsets.fromLTRB(
          horizontal,
          2 + (14 * progress),
          0,
          2 + (4 * progress),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                heightFactor: progress,
                child: Opacity(
                  opacity: progress,
                  child: Transform.translate(
                    offset: Offset(0, -8 * (1 - progress)),
                    child: Padding(
                      padding: EdgeInsets.only(right: horizontal),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Discover',
                            key: const ValueKey('discover-heading'),
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Playlists, charts, Radar, and new releases from QQ Music',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            tabs,
          ],
        ),
      ),
    );
  }
}

class _DiscoverTabs extends StatelessWidget {
  const _DiscoverTabs({required this.controller, required this.onSelected});

  final TabController controller;
  final ValueChanged<_DiscoverType> onSelected;

  @override
  Widget build(BuildContext context) => TabBar.secondary(
    key: const ValueKey('discover-type-selector'),
    controller: controller,
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    dividerColor: Colors.transparent,
    indicatorAnimation: TabIndicatorAnimation.elastic,
    indicatorSize: TabBarIndicatorSize.label,
    indicatorWeight: 3,
    labelPadding: const EdgeInsets.symmetric(horizontal: 14),
    onTap: (index) => onSelected(_DiscoverType.values[index]),
    tabs: [
      for (final type in _DiscoverType.values)
        Tab(
          key: ValueKey(switch (type) {
            _DiscoverType.playlists => 'discover-type-playlists',
            _DiscoverType.rankings => 'discover-type-rankings',
            _DiscoverType.radar => 'discover-type-radar',
            _DiscoverType.newAlbums => 'discover-type-new-albums',
            _DiscoverType.newSongs => 'discover-type-new-songs',
          }),
          height: 48,
          text: switch (type) {
            _DiscoverType.playlists => 'Playlists',
            _DiscoverType.rankings => 'Rankings',
            _DiscoverType.radar => 'Radar',
            _DiscoverType.newAlbums => 'New albums',
            _DiscoverType.newSongs => 'New songs',
          },
        ),
    ],
  );
}

class _NewSongShell extends StatelessWidget {
  const _NewSongShell({
    required this.category,
    required this.onCategorySelected,
    required this.onPlay,
    required this.child,
    super.key,
  });

  final NewSongCategory category;
  final ValueChanged<NewSongCategory> onCategorySelected;
  final VoidCallback? onPlay;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: _NewSongCategoryPicker(
                category: category,
                onSelected: onCategorySelected,
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              key: const ValueKey('new-songs-play-all'),
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play'),
            ),
          ],
        ),
      ),
      Expanded(child: child),
    ],
  );
}

class _NewSongCollection extends StatelessWidget {
  const _NewSongCollection({
    required this.category,
    required this.tracks,
    required this.onPlay,
    required this.onQueue,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required this.current,
    required this.bottomPadding,
    super.key,
  });

  final NewSongCategory category;
  final List<PlaylistTrackSummary> tracks;
  final ValueChanged<int> onPlay;
  final ValueChanged<PlaylistTrackSummary> onQueue;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;
  final PlaylistTrackSummary? current;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      final horizontal = desktop
          ? MusicSpacing.pageWide
          : MusicSpacing.pageCompact;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: MusicSizes.contentMaxWidth,
          ),
          child: CustomScrollView(
            key: PageStorageKey<String>('new-song-list-${category.name}'),
            slivers: [
              if (desktop)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: horizontal),
                  sliver: const SliverToBoxAdapter(
                    child: _DiscoverTrackTableHeader(
                      key: ValueKey('new-song-table-header'),
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                sliver: SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return _DiscoverTrackRow(
                      key: ValueKey(
                        'new-song-track-state-${track.providerId}-${track.opaqueId}',
                      ),
                      itemKey: ValueKey('new-song-track-$index'),
                      queueKey: ValueKey('new-song-queue-$index'),
                      moreKey: ValueKey('new-song-context-$index'),
                      index: index + 1,
                      track: track,
                      desktop: desktop,
                      current: _sameTrack(current, track),
                      onPlay: () => onPlay(index),
                      onAddToQueue: () => onQueue(track),
                      onOpenAlbum: onOpenAlbum == null || track.album == null
                          ? null
                          : () => onOpenAlbum!(track.album!),
                      onOpenArtist: onOpenArtist,
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
            ],
          ),
        ),
      );
    },
  );
}

class _NewSongCategoryPicker extends StatelessWidget {
  const _NewSongCategoryPicker({
    required this.category,
    required this.onSelected,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 12),
  });

  final NewSongCategory category;
  final ValueChanged<NewSongCategory> onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('new-song-category-selector'),
    scrollDirection: Axis.horizontal,
    padding: padding,
    child: SegmentedButton<NewSongCategory>(
      segments: [
        for (final value in NewSongCategory.values)
          ButtonSegment(
            value: value,
            label: Text(
              newSongCategoryLabel(value),
              key: ValueKey('new-song-category-${value.name}'),
            ),
          ),
      ],
      selected: {category},
      selectedIcon: const Icon(Icons.check_rounded, size: 18),
      style: _compactSegmentedButtonStyle(),
      onSelectionChanged: (selection) => onSelected(selection.single),
    ),
  );
}

class _NewAlbumShell extends StatelessWidget {
  const _NewAlbumShell({
    required this.region,
    required this.onRegionSelected,
    required this.child,
    super.key,
  });

  final NewAlbumRegion region;
  final ValueChanged<NewAlbumRegion> onRegionSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _NewAlbumRegionPicker(region: region, onSelected: onRegionSelected),
      Expanded(child: child),
    ],
  );
}

class _NewAlbumCollection extends StatelessWidget {
  const _NewAlbumCollection({
    required this.region,
    required this.releases,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onSelected,
    required this.bottomPadding,
    super.key,
  });

  final NewAlbumRegion region;
  final List<NewAlbumRelease> releases;
  final bool hasMore;
  final bool isLoadingMore;
  final NewAlbumFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<NewAlbumRelease> onSelected;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      final footer = _NewAlbumFooter(
        hasMore: hasMore,
        isLoadingMore: isLoadingMore,
        appendFailure: appendFailure,
        onLoadMore: onLoadMore,
        onRetryMore: onRetryMore,
      );
      final horizontal = desktop
          ? MusicSpacing.pageWide
          : MusicSpacing.pageCompact;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: MusicSizes.contentMaxWidth,
          ),
          child: CustomScrollView(
            key: PageStorageKey<String>('new-album-grid-${region.name}'),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                sliver: SliverGrid.builder(
                  gridDelegate: desktop
                      ? const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisExtent: 228,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 20,
                        )
                      : const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisExtent: 226,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                        ),
                  itemCount: releases.length,
                  itemBuilder: (context, index) => _NewAlbumCard(
                    key: ValueKey('new-album-$index'),
                    release: releases[index],
                    onTap: () => onSelected(releases[index]),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                sliver: SliverToBoxAdapter(child: footer),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _NewAlbumRegionPicker extends StatelessWidget {
  const _NewAlbumRegionPicker({required this.region, required this.onSelected});

  final NewAlbumRegion region;
  final ValueChanged<NewAlbumRegion> onSelected;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('new-album-region-selector'),
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
    child: SegmentedButton<NewAlbumRegion>(
      segments: [
        for (final value in NewAlbumRegion.values)
          ButtonSegment(
            value: value,
            label: Text(
              newAlbumRegionLabel(value),
              key: ValueKey('new-album-region-${value.name}'),
            ),
          ),
      ],
      selected: {region},
      selectedIcon: const Icon(Icons.check_rounded, size: 18),
      style: _compactSegmentedButtonStyle(),
      onSelectionChanged: (selection) => onSelected(selection.single),
    ),
  );
}

ButtonStyle _compactSegmentedButtonStyle() => SegmentedButton.styleFrom(
  minimumSize: const Size(0, 40),
  padding: const EdgeInsets.symmetric(horizontal: 10),
  visualDensity: VisualDensity.compact,
  animationDuration: const Duration(milliseconds: 200),
);

class _NewAlbumCard extends StatelessWidget {
  const _NewAlbumCard({required this.release, required this.onTap, super.key});

  final NewAlbumRelease release;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _newAlbumSemanticLabel(release),
    excludeSemantics: true,
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _NewAlbumArtwork(uri: release.album.artworkUri),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onTap,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          release.album.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
        ),
        const SizedBox(height: 3),
        Text(
          _newAlbumDetails(release),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class _NewAlbumArtwork extends StatelessWidget {
  const _NewAlbumArtwork({this.uri});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.secondaryContainer, colors.primaryContainer],
        ),
      ),
      child: Icon(Icons.album_rounded, color: colors.onSecondaryContainer),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
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

class _NewAlbumFooter extends StatelessWidget {
  const _NewAlbumFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final NewAlbumFailure? appendFailure;
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
              key: const ValueKey('new-albums-load-more'),
              onPressed: onLoadMore,
              child: const Text('Load more'),
            )
          : Text(
              'End of new albums',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

String _newAlbumDetails(NewAlbumRelease release) {
  final details = <String>[
    if (release.artists.isNotEmpty)
      release.artists.map((artist) => artist.name).join(' · '),
    ?release.releaseDate,
  ];
  return details.isEmpty ? 'Album' : details.join(' · ');
}

String _newAlbumSemanticLabel(NewAlbumRelease release) =>
    '${release.album.title}, ${_newAlbumDetails(release)}';

class _RankingCollection extends StatelessWidget {
  const _RankingCollection({
    required this.groups,
    required this.onSelected,
    required this.bottomPadding,
    super.key,
  });

  final List<RankingGroup> groups;
  final ValueChanged<RankingSummary> onSelected;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      final horizontal = desktop
          ? MusicSpacing.pageWide
          : MusicSpacing.pageCompact;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: MusicSizes.contentMaxWidth,
          ),
          child: ListView(
            key: const PageStorageKey<String>('ranking-groups'),
            padding: EdgeInsets.fromLTRB(
              horizontal,
              12,
              horizontal,
              bottomPadding,
            ),
            children: [
              for (final group in groups) ...[
                Semantics(
                  header: true,
                  child: Text(
                    group.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 12),
                if (desktop)
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final ranking in group.rankings)
                        SizedBox(
                          width: 344,
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
                const SizedBox(height: 28),
              ],
            ],
          ),
        ),
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
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: MusicRadii.content,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: semantic,
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          key: ValueKey('ranking-${ranking.opaqueId}'),
          onTap: onTap,
          child: SizedBox(
            height: 120,
            child: Row(
              children: [
                SizedBox(
                  width: 132,
                  child: _RankingArtworkPane(
                    uri: ranking.artworkUri,
                    trackCount: ranking.trackCount,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ranking.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ranking.period ?? 'Current ranking',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RankingArtworkPane extends StatelessWidget {
  const _RankingArtworkPane({this.uri, this.trackCount});

  final String? uri;
  final int? trackCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RankingArtwork(uri: uri),
        if (trackCount != null) ...[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.48, 1],
                colors: [Colors.transparent, Color(0xB3000000)],
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 9,
            child: Text(
              '$trackCount tracks',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}

class _DiscoverTrackTableHeader extends StatelessWidget {
  const _DiscoverTrackTableHeader({super.key});

  @override
  Widget build(BuildContext context) => const MusicTrackTableHeader(
    titleLabel: 'Title',
    artistLabel: 'Artist',
    albumLabel: 'Album',
    durationLabel: 'Duration',
  );
}

class _DiscoverTrackRow extends StatelessWidget {
  const _DiscoverTrackRow({
    required this.itemKey,
    required this.queueKey,
    required this.moreKey,
    required this.index,
    required this.track,
    required this.desktop,
    required this.current,
    required this.onPlay,
    required this.onAddToQueue,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    super.key,
  });

  final Key itemKey;
  final Key queueKey;
  final Key moreKey;
  final int index;
  final PlaylistTrackSummary track;
  final bool desktop;
  final bool current;
  final VoidCallback onPlay;
  final VoidCallback onAddToQueue;
  final VoidCallback? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  Widget build(BuildContext context) {
    final artists = track.artistNames.isEmpty
        ? 'Unknown artist'
        : track.artistNames.join(' / ');
    return MusicTrackRowSurface(
      itemKey: itemKey,
      desktop: desktop,
      current: current,
      semanticLabel: '${track.title}, $artists',
      onTap: onPlay,
      onContextMenuRequested: (position) => unawaited(
        position == null
            ? _showCompactMenu(context)
            : _showDesktopMenu(context, position),
      ),
      contentBuilder: (context, active, hovered) => MusicTrackRowContent(
        index: index,
        track: track,
        desktop: desktop,
        current: current,
        active: active,
        artistNames: artists,
        showInlineQueueAction: hovered,
        queueKey: queueKey,
        moreKey: moreKey,
        onPlay: onPlay,
        onAddToQueue: onAddToQueue,
        onOpenAlbum: onOpenAlbum,
        onOpenArtist: onOpenArtist == null || track.artists.isEmpty
            ? null
            : () => _openArtist(context),
        onMore: () => unawaited(
          desktop ? _showDesktopMenuAtRow(context) : _showCompactMenu(context),
        ),
        addToQueueTooltip: 'Add to queue',
        moreTooltip: 'More actions',
      ),
    );
  }

  Future<void> _showDesktopMenuAtRow(BuildContext context) async {
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    await _showDesktopMenu(
      context,
      box.localToGlobal(box.size.center(Offset.zero)),
    );
  }

  Future<void> _showDesktopMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final action = await showMenu<MusicTrackAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: _menuItems(),
    );
    if (!context.mounted) return;
    _runAction(context, action);
  }

  Future<void> _showCompactMenu(BuildContext context) async {
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
            if (onOpenAlbum != null)
              ListTile(
                key: const ValueKey('track-context-album'),
                leading: const Icon(Icons.album_rounded),
                title: const Text('Open album'),
                onTap: () => Navigator.pop(context, MusicTrackAction.openAlbum),
              ),
            if (onOpenArtist != null)
              ListTile(
                key: const ValueKey('track-context-artist-0'),
                leading: const Icon(Icons.person_rounded),
                title: const Text('Open artist'),
                onTap: () =>
                    Navigator.pop(context, MusicTrackAction.openArtist),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    _runAction(context, action);
  }

  List<PopupMenuEntry<MusicTrackAction>> _menuItems() => [
    const PopupMenuItem(
      value: MusicTrackAction.play,
      child: ListTile(
        leading: Icon(Icons.play_arrow_rounded),
        title: Text('Play from here'),
      ),
    ),
    const PopupMenuItem(
      value: MusicTrackAction.addToQueue,
      child: ListTile(
        leading: Icon(Icons.playlist_add_rounded),
        title: Text('Add to queue'),
      ),
    ),
    if (onOpenAlbum != null)
      const PopupMenuItem(
        value: MusicTrackAction.openAlbum,
        child: ListTile(
          leading: Icon(Icons.album_rounded),
          title: Text('Open album'),
        ),
      ),
    if (onOpenArtist != null)
      const PopupMenuItem(
        value: MusicTrackAction.openArtist,
        child: ListTile(
          leading: Icon(Icons.person_rounded),
          title: Text('Open artist'),
        ),
      ),
  ];

  void _runAction(BuildContext context, MusicTrackAction? action) {
    switch (action) {
      case MusicTrackAction.play:
        onPlay();
      case MusicTrackAction.addToQueue:
        onAddToQueue();
      case MusicTrackAction.openAlbum:
        onOpenAlbum?.call();
      case MusicTrackAction.openArtist:
        _openArtist(context);
      case null:
        return;
    }
  }

  void _openArtist(BuildContext context) {
    unawaited(
      openMusicTrackArtists(
        context: context,
        artists: track.artists,
        onSelected: onOpenArtist,
        itemKeyPrefix: 'discover-track-artist',
      ),
    );
  }
}

class _RadarCollection extends StatefulWidget {
  const _RadarCollection({
    required this.controller,
    required this.tracks,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.canRetryMore,
    required this.onRetryMore,
    required this.onReload,
    required this.onSignInAgain,
    required this.onPlay,
    required this.onQueue,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required this.current,
    required this.bottomPadding,
    super.key,
  });

  final RadarController controller;
  final List<PlaylistTrackSummary> tracks;
  final bool hasMore;
  final bool isLoadingMore;
  final RadarFailure? appendFailure;
  final bool canRetryMore;
  final VoidCallback onRetryMore;
  final VoidCallback onReload;
  final VoidCallback onSignInAgain;
  final ValueChanged<int> onPlay;
  final ValueChanged<PlaylistTrackSummary> onQueue;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;
  final PlaylistTrackSummary? current;
  final double bottomPadding;

  @override
  State<_RadarCollection> createState() => _RadarCollectionState();
}

class _RadarCollectionState extends State<_RadarCollection> {
  final _prefetchPolicy = PlaylistPrefetchPolicy();

  @override
  void didUpdateWidget(_RadarCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.cancelPrefetch();
      _prefetchPolicy.reset();
    }
  }

  bool _handlePrefetch(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _prefetchPolicy.reset();
    }
    final delta = switch (notification) {
      ScrollUpdateNotification() => notification.scrollDelta ?? 0,
      OverscrollNotification() => notification.overscroll,
      _ => 0.0,
    };
    if (delta < 0) {
      widget.controller.cancelPrefetch();
      _prefetchPolicy.reset();
    } else if (delta > 0) {
      final metrics = notification.metrics;
      widget.controller.prefetchTo(
        _prefetchPolicy.targetTrackCount(
          loadedCount: widget.tracks.length,
          extentAfter: metrics.extentAfter,
          contentExtent:
              metrics.maxScrollExtent -
              metrics.minScrollExtent +
              metrics.viewportDimension,
          scrollDelta: delta,
          sampleTime: WidgetsBinding.instance.currentSystemFrameTimeStamp,
          pageLatency: widget.controller.estimatedPageLatency,
          pageSize: 10,
        ),
      );
    }
    return false;
  }

  @override
  void dispose() {
    widget.controller.cancelPrefetch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      final horizontal = desktop
          ? MusicSpacing.pageWide
          : MusicSpacing.pageCompact;
      return NotificationListener<ScrollNotification>(
        onNotification: _handlePrefetch,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: MusicSizes.contentMaxWidth,
            ),
            child: CustomScrollView(
              key: const PageStorageKey<String>('radar-tracks'),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 12),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('radar-play-all'),
                          onPressed: widget.tracks.isEmpty
                              ? null
                              : () => widget.onPlay(0),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Play'),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          key: const ValueKey('radar-refresh'),
                          tooltip: 'Refresh Radar',
                          onPressed: widget.onReload,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                if (desktop)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: horizontal),
                    sliver: const SliverToBoxAdapter(
                      child: _DiscoverTrackTableHeader(
                        key: ValueKey('radar-table-header'),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: horizontal),
                  sliver: SliverList.builder(
                    itemCount: widget.tracks.length,
                    itemBuilder: (context, index) {
                      final track = widget.tracks[index];
                      return _DiscoverTrackRow(
                        key: ValueKey(
                          'radar-track-state-${track.providerId}-${track.opaqueId}',
                        ),
                        itemKey: ValueKey('radar-track-$index'),
                        queueKey: ValueKey('radar-queue-$index'),
                        moreKey: ValueKey('radar-context-$index'),
                        index: index + 1,
                        track: track,
                        desktop: desktop,
                        current: _sameTrack(widget.current, track),
                        onPlay: () => widget.onPlay(index),
                        onAddToQueue: () => widget.onQueue(track),
                        onOpenAlbum:
                            widget.onOpenAlbum == null || track.album == null
                            ? null
                            : () => widget.onOpenAlbum!(track.album!),
                        onOpenArtist: widget.onOpenArtist,
                      );
                    },
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.only(bottom: widget.bottomPadding),
                  sliver: SliverToBoxAdapter(
                    child: _RadarFooter(
                      hasMore: widget.hasMore,
                      isLoadingMore: widget.isLoadingMore,
                      appendFailure: widget.appendFailure,
                      canRetryMore: widget.canRetryMore,
                      onRetryMore: widget.onRetryMore,
                      onReload: widget.onReload,
                      onSignInAgain: widget.onSignInAgain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _RadarFooter extends StatelessWidget {
  const _RadarFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.canRetryMore,
    required this.onRetryMore,
    required this.onReload,
    required this.onSignInAgain,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final RadarFailure? appendFailure;
  final bool canRetryMore;
  final VoidCallback onRetryMore;
  final VoidCallback onReload;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final failure = appendFailure;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: isLoadingMore
            ? const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : _radarRequiresSignIn(failure)
            ? FilledButton.tonal(
                onPressed: onSignInAgain,
                child: const Text('Sign in again'),
              )
            : canRetryMore
            ? FilledButton.tonal(
                onPressed: onRetryMore,
                child: const Text('Try loading more again'),
              )
            : failure == RadarFailure.replaced
            ? FilledButton.tonal(
                onPressed: onReload,
                child: const Text('Reload Radar'),
              )
            : failure != null
            ? Text(
                radarFailureCopy(failure),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              )
            : hasMore
            ? Text(
                'Scroll to load more',
                key: const ValueKey('radar-auto-load-more'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : Text(
                'End of Radar recommendations',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
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
    required this.bottomPadding,
    super.key,
  });

  final List<RecommendedPlaylistSummary> playlists;
  final bool hasMore;
  final bool isLoadingMore;
  final RecommendedPlaylistFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      final footer = _RecommendationFooter(
        hasMore: hasMore,
        isLoadingMore: isLoadingMore,
        appendFailure: appendFailure,
        onLoadMore: onLoadMore,
        onRetryMore: onRetryMore,
      );
      final horizontal = desktop
          ? MusicSpacing.pageWide
          : MusicSpacing.pageCompact;
      return CustomScrollView(
        key: const PageStorageKey<String>('recommended-playlist-grid'),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 8),
            sliver: SliverGrid.builder(
              gridDelegate: desktop
                  ? const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      mainAxisExtent: 228,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 20,
                    )
                  : const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisExtent: 226,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
              itemCount: playlists.length,
              itemBuilder: (context, index) => _RecommendationGridItem(
                key: ValueKey('recommendations-item-$index'),
                playlist: playlists[index],
                onTap: () => onSelected(playlists[index]),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            sliver: SliverToBoxAdapter(child: footer),
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _RecommendationArtwork(uri: playlist.artworkUri),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onTap,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          playlist.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
        ),
        const SizedBox(height: 3),
        Text(
          playlist.trackCount != null
              ? '${playlist.trackCount} tracks'
              : 'QQ Music playlist',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
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
      borderRadius: BorderRadius.circular(8),
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

String _semanticLabel(RecommendedPlaylistSummary playlist) {
  final count = playlist.trackCount;
  return count == null ? playlist.title : '${playlist.title}, $count tracks';
}

bool _sameTrack(PlaylistTrackSummary? left, PlaylistTrackSummary right) =>
    left != null &&
    left.providerId == right.providerId &&
    left.opaqueId == right.opaqueId;

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

bool _radarRequiresSignIn(RadarFailure? failure) =>
    failure == RadarFailure.authenticationRequired ||
    failure == RadarFailure.credentialRejected ||
    failure == RadarFailure.credentialRejectedStorageCleanupFailed;

String radarFailureCopy(RadarFailure? failure) => switch (failure) {
  RadarFailure.authenticationRequired =>
    'Sign in to load QQ Music Radar Tracks.',
  RadarFailure.credentialRejected =>
    'Your QQ Music session expired. Sign in again to continue.',
  RadarFailure.credentialRejectedStorageCleanupFailed =>
    'Your QQ Music session expired, but its saved copy could not be removed. '
        'Sign in again after checking secure storage.',
  RadarFailure.network => 'Check your connection and try again.',
  RadarFailure.serviceUnavailable =>
    'QQ Music Radar is temporarily unavailable.',
  RadarFailure.replaced =>
    'The signed-in account changed while Radar was loading.',
  RadarFailure.cancelled => 'The Radar request was cancelled.',
  RadarFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  RadarFailure.invalidResponse ||
  RadarFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected Radar response.',
};

String newAlbumRegionLabel(NewAlbumRegion region) => switch (region) {
  NewAlbumRegion.mainlandChina => 'Mainland China',
  NewAlbumRegion.hongKongTaiwan => 'Hong Kong / Taiwan',
  NewAlbumRegion.western => 'Western',
  NewAlbumRegion.korea => 'Korea',
  NewAlbumRegion.japan => 'Japan',
  NewAlbumRegion.other => 'Other',
};

String newAlbumFailureCopy(NewAlbumFailure? failure) => switch (failure) {
  NewAlbumFailure.network => 'Check your connection and try again.',
  NewAlbumFailure.serviceUnavailable =>
    'QQ Music new albums are temporarily unavailable.',
  NewAlbumFailure.cancelled => 'The new-album request was cancelled.',
  NewAlbumFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  NewAlbumFailure.invalidResponse ||
  NewAlbumFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected new-album response.',
};

String newSongCategoryLabel(NewSongCategory category) => switch (category) {
  NewSongCategory.latest => 'Latest',
  NewSongCategory.mainlandChina => 'Mainland China',
  NewSongCategory.hongKongTaiwan => 'Hong Kong / Taiwan',
  NewSongCategory.western => 'Western',
  NewSongCategory.korea => 'Korea',
  NewSongCategory.japan => 'Japan',
};

String newSongFailureCopy(NewSongFailure? failure) => switch (failure) {
  NewSongFailure.network => 'Check your connection and try again.',
  NewSongFailure.serviceUnavailable =>
    'QQ Music new songs are temporarily unavailable.',
  NewSongFailure.cancelled => 'The new-song request was cancelled.',
  NewSongFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  NewSongFailure.invalidResponse ||
  NewSongFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected new-song response.',
};
