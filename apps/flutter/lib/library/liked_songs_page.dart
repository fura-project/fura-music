import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/favorite_albums_page.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_refresh_failure_banner.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class LikedSongsPage extends StatefulWidget {
  const LikedSongsPage({
    required this.playlist,
    required this.playlists,
    required this.gateway,
    required this.favoriteAlbumGateway,
    required this.queuePlaybackController,
    required this.onOpenPlaylist,
    required this.onSignInAgain,
    this.onOpenAlbum,
    this.onOpenArtist,
    super.key,
  });

  final UserPlaylistSummary playlist;
  final List<UserPlaylistSummary> playlists;
  final PlaylistDetailGateway gateway;
  final FavoriteAlbumGateway favoriteAlbumGateway;
  final QueuePlaybackController queuePlaybackController;
  final ValueChanged<UserPlaylistSummary> onOpenPlaylist;
  final VoidCallback onSignInAgain;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<LikedSongsPage> createState() => _LikedSongsPageState();
}

class _LikedSongsPageState extends State<LikedSongsPage>
    with SingleTickerProviderStateMixin {
  late final PlaylistDetailController _controller;
  late final Listenable _pageListenable;
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _LikedCollectionSection _section = _LikedCollectionSection.songs;
  bool _albumsVisited = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _LikedCollectionSection.values.length,
      vsync: this,
    )..addListener(_handleTabChanged);
    _controller = PlaylistDetailController(widget.playlist, widget.gateway);
    _pageListenable = Listenable.merge([
      _controller,
      widget.queuePlaybackController,
    ]);
    _searchController.addListener(_updateQuery);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _searchController
      ..removeListener(_updateQuery)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _updateQuery() {
    final query = _searchController.text.trim().toLowerCase();
    if (query == _query) return;
    setState(() => _query = query);
  }

  List<PlaylistTrackSummary> get _visibleTracks {
    if (_query.isEmpty) return _controller.tracks;
    return _controller.tracks
        .where((track) {
          final searchable = [
            track.title,
            ?track.subtitle,
            ...track.artistNames,
            ?track.albumTitle,
          ].join('\n').toLowerCase();
          return searchable.contains(_query);
        })
        .toList(growable: false);
  }

  List<UserPlaylistSummary> get _visiblePlaylists {
    final playlists = widget.playlists
        .where((playlist) => !playlist.isLikedSongs)
        .toList(growable: false);
    if (_query.isEmpty) return playlists;
    return playlists
        .where((playlist) => playlist.title.toLowerCase().contains(_query))
        .toList(growable: false);
  }

  void _handleTabChanged() {
    final section = _LikedCollectionSection.values[_tabController.index];
    if (_section == section) return;
    _searchController.clear();
    setState(() {
      _section = section;
      if (section == _LikedCollectionSection.albums) _albumsVisited = true;
    });
  }

  void _selectSection(_LikedCollectionSection section) {
    if (_tabController.index == section.index) return;
    _tabController.animateTo(
      section.index,
      duration: const Duration(milliseconds: 300),
      curve: Easing.emphasizedDecelerate,
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: AnimatedBuilder(
      animation: _pageListenable,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 820;
          final tracks = _visibleTracks;
          return Column(
            key: const ValueKey('liked-songs-page'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LikedSongsHeader(
                total: switch (_controller.stage) {
                  PlaylistDetailStage.content ||
                  PlaylistDetailStage.empty => _controller.total,
                  _ => widget.playlist.trackCount,
                },
                desktop: desktop,
                canPlay: tracks.isNotEmpty,
                isRefreshing: _controller.isRefreshing,
                searchController: _searchController,
                onPlayAll: tracks.isEmpty ? null : () => _playAll(tracks),
                onRefresh: _controller.isLoading ? null : _controller.refresh,
                selectedSection: _section,
                tabController: _tabController,
                playlistCount: widget.playlists
                    .where((playlist) => !playlist.isLikedSongs)
                    .length,
              ),
              if (_section == _LikedCollectionSection.songs &&
                  _controller.isRefreshing)
                const LinearProgressIndicator(
                  key: ValueKey('liked-songs-refresh-progress'),
                ),
              if (_section == _LikedCollectionSection.songs &&
                  _controller.refreshFailure != null)
                LibraryRefreshFailureBanner(
                  key: const ValueKey('liked-songs-refresh-failure'),
                  message: _refreshFailureCopy(_controller.refreshFailure!),
                  canRetry: _controller.canRetryRefresh,
                  onRetry: _controller.retryRefresh,
                  onDismiss: _controller.dismissRefreshFailure,
                ),
              Expanded(
                child: TabBarView(
                  key: const ValueKey('liked-collection-pages'),
                  controller: _tabController,
                  children: [
                    _RetainedLikedSection(child: _body(desktop, tracks)),
                    _RetainedLikedSection(
                      child: _LikedPlaylistsCollection(
                        playlists: _visiblePlaylists,
                        searching: _query.isNotEmpty,
                        onOpenPlaylist: widget.onOpenPlaylist,
                      ),
                    ),
                    _RetainedLikedSection(
                      child: _albumsVisited
                          ? FavoriteAlbumsPage(
                              key: const ValueKey('liked-favorite-albums'),
                              gateway: widget.favoriteAlbumGateway,
                              queuePlaybackController:
                                  widget.queuePlaybackController,
                              onBack: () =>
                                  _selectSection(_LikedCollectionSection.songs),
                              onOpenAlbum: (album) =>
                                  widget.onOpenAlbum?.call(album),
                              onSignInAgain: widget.onSignInAgain,
                              embedded: true,
                              showHeader: false,
                              filterQuery: _query,
                            )
                          : const SizedBox.shrink(),
                    ),
                    const _RetainedLikedSection(
                      child: _UnavailableLikedCollection(
                        key: ValueKey('liked-programs-unavailable'),
                        icon: Icons.podcasts_rounded,
                        title: '有声节目收藏尚未接入',
                        detail: '当前 Core 没有经过验证的 QQ Music 有声节目收藏读取能力。',
                      ),
                    ),
                    const _RetainedLikedSection(
                      child: _UnavailableLikedCollection(
                        key: ValueKey('liked-videos-unavailable'),
                        icon: Icons.video_library_outlined,
                        title: '视频收藏尚未接入',
                        detail: '歌曲关联 MV 不等同于账号的视频收藏，不会在这里混用。',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _body(bool desktop, List<PlaylistTrackSummary> tracks) =>
      switch (_controller.stage) {
        PlaylistDetailStage.loading => const _LikedSongsMessage(
          key: ValueKey('liked-songs-loading'),
          loading: true,
          icon: Icons.favorite_rounded,
          title: '正在加载喜欢的歌曲…',
          detail: '正在从 QQ Music 读取收藏。',
        ),
        PlaylistDetailStage.content when tracks.isEmpty => _LikedSongsMessage(
          key: const ValueKey('liked-songs-search-empty'),
          icon: Icons.search_off_rounded,
          title: '未找到匹配的歌曲',
          detail: '请尝试其他关键词，搜索范围为已加载的喜欢歌曲。',
        ),
        PlaylistDetailStage.content => _LikedTrackCollection(
          tracks: tracks,
          loadedCount: _controller.tracks.length,
          total: _controller.total,
          hasMore: _controller.hasMore,
          isLoadingMore: _controller.isLoadingMore,
          appendFailure: _controller.appendFailure,
          desktop: desktop,
          current: widget.queuePlaybackController.current,
          onLoadMore: _controller.loadMore,
          onRetryMore: _controller.retryMore,
          onTrackSelected: (index) => unawaited(
            widget.queuePlaybackController.replaceAndPlay(tracks, index),
          ),
          onTrackQueued: _addToQueue,
          onOpenAlbum: widget.onOpenAlbum,
          onOpenArtist: widget.onOpenArtist,
        ),
        PlaylistDetailStage.empty => const _LikedSongsMessage(
          key: ValueKey('liked-songs-empty'),
          icon: Icons.favorite_border_rounded,
          title: '还没有喜欢的歌曲',
          detail: '在 QQ Music 中喜欢的歌曲会显示在这里。',
        ),
        PlaylistDetailStage.error => _LikedSongsFailure(
          failure: _controller.failure,
          canRetry: _controller.canRetry,
          showSignInAgain: false,
          onRetry: _controller.retry,
          onSignInAgain: widget.onSignInAgain,
        ),
        PlaylistDetailStage.authenticationRequired ||
        PlaylistDetailStage.credentialRejected => _LikedSongsFailure(
          failure: _controller.failure,
          canRetry: false,
          showSignInAgain: true,
          onRetry: _controller.retry,
          onSignInAgain: widget.onSignInAgain,
        ),
      };

  void _playAll(List<PlaylistTrackSummary> tracks) {
    if (tracks.isEmpty) return;
    unawaited(widget.queuePlaybackController.replaceAndPlay(tracks, 0));
  }

  void _addToQueue(PlaylistTrackSummary track) {
    final playbackStart = widget.queuePlaybackController.push(track);
    final message = widget.queuePlaybackController.failure == null
        ? '已添加到播放队列'
        : '无法更新播放队列';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    unawaited(playbackStart);
  }
}

class _LikedSongsHeader extends StatelessWidget {
  const _LikedSongsHeader({
    required this.total,
    required this.desktop,
    required this.canPlay,
    required this.isRefreshing,
    required this.searchController,
    required this.onPlayAll,
    required this.onRefresh,
    required this.selectedSection,
    required this.tabController,
    required this.playlistCount,
  });

  final int? total;
  final bool desktop;
  final bool canPlay;
  final bool isRefreshing;
  final TextEditingController searchController;
  final VoidCallback? onPlayAll;
  final VoidCallback? onRefresh;
  final _LikedCollectionSection selectedSection;
  final TabController tabController;
  final int playlistCount;

  @override
  Widget build(BuildContext context) {
    final horizontal = desktop ? MusicSpacing.page : MusicSpacing.pageCompact;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '喜欢',
            key: const ValueKey('liked-songs-title'),
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
          ),
          const SizedBox(height: 18),
          _LikedCategoryTabs(
            total: total,
            playlistCount: playlistCount,
            controller: tabController,
          ),
          const SizedBox(height: 18),
          if (desktop)
            Row(
              children: [
                if (selectedSection == _LikedCollectionSection.songs) ...[
                  _PlayAllButton(onPressed: onPlayAll),
                  const SizedBox(width: 10),
                  _RefreshButton(
                    refreshing: isRefreshing,
                    onPressed: onRefresh,
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: 220,
                  child: _LikedCollectionSearch(
                    controller: searchController,
                    section: selectedSection,
                  ),
                ),
              ],
            )
          else ...[
            if (selectedSection == _LikedCollectionSection.songs) ...[
              Row(
                children: [
                  Expanded(child: _PlayAllButton(onPressed: onPlayAll)),
                  const SizedBox(width: 10),
                  _RefreshButton(
                    refreshing: isRefreshing,
                    onPressed: onRefresh,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            _LikedCollectionSearch(
              controller: searchController,
              section: selectedSection,
            ),
          ],
        ],
      ),
    );
  }
}

class _LikedCategoryTabs extends StatelessWidget {
  const _LikedCategoryTabs({
    required this.total,
    required this.playlistCount,
    required this.controller,
  });

  final int? total;
  final int playlistCount;
  final TabController controller;

  @override
  Widget build(BuildContext context) => TabBar.secondary(
    key: const ValueKey('liked-songs-tabs'),
    controller: controller,
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    dividerColor: Colors.transparent,
    indicatorAnimation: TabIndicatorAnimation.elastic,
    indicatorSize: TabBarIndicatorSize.label,
    indicatorWeight: 3,
    labelPadding: const EdgeInsets.symmetric(horizontal: 14),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      final colors = Theme.of(context).colorScheme;
      if (states.contains(WidgetState.pressed)) {
        return colors.onSurface.withValues(alpha: 0.10);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return colors.onSurface.withValues(alpha: 0.08);
      }
      return Colors.transparent;
    }),
    tabs: [
      for (final section in _LikedCollectionSection.values)
        Tab(
          key: ValueKey('liked-tab-${section.name}'),
          height: 44,
          text: switch (section) {
            _LikedCollectionSection.songs => total == null ? '歌曲' : '歌曲 $total',
            _LikedCollectionSection.playlists => '歌单 $playlistCount',
            _LikedCollectionSection.albums => '专辑',
            _LikedCollectionSection.programs => '有声节目',
            _LikedCollectionSection.videos => '视频',
          },
        ),
    ],
  );
}

enum _LikedCollectionSection { songs, playlists, albums, programs, videos }

class _LikedPlaylistsCollection extends StatelessWidget {
  const _LikedPlaylistsCollection({
    required this.playlists,
    required this.searching,
    required this.onOpenPlaylist,
  });

  final List<UserPlaylistSummary> playlists;
  final bool searching;
  final ValueChanged<UserPlaylistSummary> onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    final visible = playlists
        .where((playlist) => !playlist.isLikedSongs)
        .toList(growable: false);
    final owned = visible
        .where((playlist) => playlist.ownership == UserPlaylistOwnership.owned)
        .toList(growable: false);
    final saved = visible
        .where((playlist) => playlist.ownership == UserPlaylistOwnership.saved)
        .toList(growable: false);
    final unclassified = visible
        .where(
          (playlist) => playlist.ownership == UserPlaylistOwnership.unspecified,
        )
        .toList(growable: false);
    if (visible.isEmpty) {
      return _UnavailableLikedCollection(
        key: const ValueKey('liked-playlists-empty'),
        icon: searching ? Icons.search_off_rounded : Icons.queue_music_rounded,
        title: searching ? '未找到匹配的歌单' : '还没有其他歌单',
        detail: searching ? '请尝试其他关键词。' : '你创建或收藏的 QQ Music 歌单会显示在这里。',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        var columns = constraints.maxWidth ~/ 188;
        if (columns < 2) columns = 2;
        if (columns > 6) columns = 6;
        final horizontal = constraints.maxWidth >= 820
            ? MusicSpacing.page
            : MusicSpacing.pageCompact;
        return CustomScrollView(
          key: const PageStorageKey<String>('liked-playlists-grid'),
          slivers: [
            ..._playlistSection(
              context,
              title: '自创歌单',
              playlists: owned,
              columns: columns,
              horizontal: horizontal,
            ),
            ..._playlistSection(
              context,
              title: '收藏歌单',
              playlists: saved,
              columns: columns,
              horizontal: horizontal,
            ),
            ..._playlistSection(
              context,
              title: '其他歌单',
              playlists: unclassified,
              columns: columns,
              horizontal: horizontal,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }

  List<Widget> _playlistSection(
    BuildContext context, {
    required String title,
    required List<UserPlaylistSummary> playlists,
    required int columns,
    required double horizontal,
  }) {
    if (playlists.isEmpty) return const [];
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 12),
        sliver: SliverToBoxAdapter(
          child: Text(
            '$title ${playlists.length}',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 24),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 20,
            crossAxisSpacing: 18,
            childAspectRatio: 0.78,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _LikedPlaylistCard(
              playlist: playlists[index],
              onTap: () => onOpenPlaylist(playlists[index]),
            ),
            childCount: playlists.length,
          ),
        ),
      ),
    ];
  }
}

class _LikedPlaylistCard extends StatelessWidget {
  const _LikedPlaylistCard({required this.playlist, required this.onTap});

  final UserPlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final artwork = ColoredBox(
      color: colors.secondaryContainer,
      child: Icon(
        Icons.queue_music_rounded,
        size: 42,
        color: colors.onSecondaryContainer,
      ),
    );
    return Semantics(
      label: '${playlist.title}, 歌单',
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: ValueKey('liked-playlist-${playlist.opaqueId}'),
        onTap: onTap,
        borderRadius: MusicRadii.artwork,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: MusicRadii.artwork,
                child: SizedBox.expand(
                  child: playlist.artworkUri == null
                      ? artwork
                      : Image.network(
                          playlist.artworkUri!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => artwork,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              playlist.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (playlist.trackCount case final count?) ...[
              const SizedBox(height: 3),
              Text(
                '$count 首歌曲',
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnavailableLikedCollection extends StatelessWidget {
  const _UnavailableLikedCollection({
    required this.icon,
    required this.title,
    required this.detail,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(MusicSpacing.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RetainedLikedSection extends StatefulWidget {
  const _RetainedLikedSection({required this.child});

  final Widget child;

  @override
  State<_RetainedLikedSection> createState() => _RetainedLikedSectionState();
}

class _RetainedLikedSectionState extends State<_RetainedLikedSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _PlayAllButton extends StatelessWidget {
  const _PlayAllButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    key: const ValueKey('liked-songs-play-all'),
    onPressed: onPressed,
    icon: const Icon(Icons.play_arrow_rounded),
    label: const Text('播放全部'),
  );
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({
    required this.refreshing,
    required this.onPressed,
    this.compact = false,
  });

  final bool refreshing;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) => compact
      ? IconButton.filledTonal(
          tooltip: refreshing ? '正在刷新' : '刷新喜欢的歌曲',
          onPressed: onPressed,
          icon: const Icon(Icons.refresh_rounded),
        )
      : FilledButton.tonalIcon(
          key: const ValueKey('liked-songs-refresh'),
          onPressed: onPressed,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(refreshing ? '正在刷新' : '刷新'),
        );
}

class _LikedCollectionSearch extends StatelessWidget {
  const _LikedCollectionSearch({
    required this.controller,
    required this.section,
  });

  final TextEditingController controller;
  final _LikedCollectionSection section;

  @override
  Widget build(BuildContext context) {
    final enabled =
        section == _LikedCollectionSection.songs ||
        section == _LikedCollectionSection.playlists ||
        section == _LikedCollectionSection.albums;
    final hint = switch (section) {
      _LikedCollectionSection.songs => '搜索已加载歌曲',
      _LikedCollectionSection.playlists => '搜索歌单',
      _LikedCollectionSection.albums => '搜索已加载专辑',
      _LikedCollectionSection.programs => '有声节目收藏尚未接入',
      _LikedCollectionSection.videos => '视频收藏尚未接入',
    };
    return TextField(
      key: ValueKey(
        section == _LikedCollectionSection.songs
            ? 'liked-songs-search'
            : 'liked-${section.name}-search',
      ),
      controller: controller,
      enabled: enabled,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: '清除搜索',
                  onPressed: controller.clear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
      ),
    );
  }
}

class _LikedTrackCollection extends StatefulWidget {
  const _LikedTrackCollection({
    required this.tracks,
    required this.loadedCount,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.desktop,
    required this.current,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onTrackSelected,
    required this.onTrackQueued,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

  final List<PlaylistTrackSummary> tracks;
  final int loadedCount;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;
  final UserLibraryFailure? appendFailure;
  final bool desktop;
  final PlaylistTrackSummary? current;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<int> onTrackSelected;
  final ValueChanged<PlaylistTrackSummary> onTrackQueued;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<_LikedTrackCollection> createState() => _LikedTrackCollectionState();
}

class _LikedTrackCollectionState extends State<_LikedTrackCollection> {
  (String, String)? _hoveredTrack;

  void _setHovered(PlaylistTrackSummary track, bool hovered) {
    final identity = (track.providerId, track.opaqueId);
    if (hovered) {
      if (_hoveredTrack != identity) setState(() => _hoveredTrack = identity);
    } else if (_hoveredTrack == identity) {
      setState(() => _hoveredTrack = null);
    }
  }

  bool _clearHoverOnScroll(ScrollNotification notification) {
    if (_hoveredTrack != null && notification is ScrollUpdateNotification) {
      setState(() => _hoveredTrack = null);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.desktop ? MusicSpacing.page : 10.0;
    return Column(
      children: [
        if (widget.desktop)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: const _LikedTrackTableHeader(),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _clearHoverOnScroll,
            child: ListView.separated(
              key: const PageStorageKey<String>('liked-songs-track-list'),
              padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 20),
              itemCount: widget.tracks.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 1),
              itemBuilder: (context, index) {
                if (index == widget.tracks.length) {
                  return _LikedTrackFooter(
                    loadedCount: widget.loadedCount,
                    total: widget.total,
                    hasMore: widget.hasMore,
                    loading: widget.isLoadingMore,
                    failure: widget.appendFailure,
                    onLoadMore: widget.onLoadMore,
                    onRetry: widget.onRetryMore,
                  );
                }
                final track = widget.tracks[index];
                final identity = (track.providerId, track.opaqueId);
                return _LikedTrackRow(
                  key: ValueKey(
                    'liked-track-state-${identity.$1}-${identity.$2}',
                  ),
                  index: index + 1,
                  track: track,
                  desktop: widget.desktop,
                  current: _sameTrack(widget.current, track),
                  hovered: _hoveredTrack == identity,
                  onHoverChanged: (hovered) => _setHovered(track, hovered),
                  onPlay: () => widget.onTrackSelected(index),
                  onAddToQueue: () => widget.onTrackQueued(track),
                  onOpenAlbum: widget.onOpenAlbum == null || track.album == null
                      ? null
                      : () => widget.onOpenAlbum!(track.album!),
                  onOpenArtist:
                      widget.onOpenArtist == null || track.artists.length != 1
                      ? null
                      : () => widget.onOpenArtist!(track.artists.single),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _LikedTrackTableHeader extends StatelessWidget {
  const _LikedTrackTableHeader();

  @override
  Widget build(BuildContext context) => const MusicTrackTableHeader(
    key: ValueKey('liked-songs-table-header'),
    titleLabel: '标题',
    artistLabel: '歌手',
    albumLabel: '专辑',
    durationLabel: '时长',
  );
}

class _LikedTrackRow extends StatefulWidget {
  const _LikedTrackRow({
    required this.index,
    required this.track,
    required this.desktop,
    required this.current,
    required this.hovered,
    required this.onHoverChanged,
    required this.onPlay,
    required this.onAddToQueue,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    super.key,
  });

  final int index;
  final PlaylistTrackSummary track;
  final bool desktop;
  final bool current;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onPlay;
  final VoidCallback onAddToQueue;
  final VoidCallback? onOpenAlbum;
  final VoidCallback? onOpenArtist;

  @override
  State<_LikedTrackRow> createState() => _LikedTrackRowState();
}

class _LikedTrackRowState extends State<_LikedTrackRow> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artists = widget.track.artistNames.isEmpty
        ? '未知歌手'
        : widget.track.artistNames.join(' / ');
    final active = widget.hovered || _focusNode.hasFocus;
    final background = widget.current
        ? theme.colorScheme.surfaceContainerHigh
        : active
        ? theme.colorScheme.surfaceContainerLow
        : Colors.transparent;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): () =>
            _showKeyboardMenu(context),
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
            _showKeyboardMenu(context),
      },
      child: Semantics(
        label: '${widget.track.title}, $artists',
        button: true,
        selected: widget.current,
        onTap: widget.onPlay,
        excludeSemantics: true,
        child: MouseRegion(
          onEnter: (_) => widget.onHoverChanged(true),
          onExit: (_) => widget.onHoverChanged(false),
          child: InkWell(
            key: ValueKey('liked-track-row-${widget.index}'),
            focusNode: _focusNode,
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onPlay,
            onLongPress: widget.desktop
                ? null
                : () => unawaited(_showCompactMenu(context)),
            onSecondaryTapDown: widget.desktop
                ? (details) => unawaited(
                    _showDesktopMenu(context, details.globalPosition),
                  )
                : null,
            child: Container(
              constraints: BoxConstraints(minHeight: widget.desktop ? 56 : 64),
              padding: EdgeInsets.symmetric(
                horizontal: widget.desktop ? 12 : 8,
                vertical: widget.desktop ? 7 : 6,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: widget.desktop
                  ? _desktopContent(context, artists, active)
                  : _compactContent(context, artists),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopContent(BuildContext context, String artists, bool active) {
    return MusicTrackRowContent(
      index: widget.index,
      track: widget.track,
      desktop: true,
      current: widget.current,
      active: active,
      artistNames: artists,
      onAddToQueue: widget.onAddToQueue,
      onMore: () => _showKeyboardMenu(context),
      addToQueueTooltip: '添加到队列',
      moreTooltip: '更多操作',
    );
  }

  Widget _compactContent(BuildContext context, String artists) =>
      MusicTrackRowContent(
        index: widget.index,
        track: widget.track,
        desktop: false,
        current: widget.current,
        active: false,
        artistNames: artists,
        onAddToQueue: widget.onAddToQueue,
        onMore: () => unawaited(_showCompactMenu(context)),
        addToQueueTooltip: '添加到队列',
        moreTooltip: '更多操作',
      );

  void _showKeyboardMenu(BuildContext context) {
    if (!widget.desktop) {
      unawaited(_showCompactMenu(context));
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    unawaited(
      _showDesktopMenu(
        context,
        box.localToGlobal(box.size.center(Offset.zero)),
      ),
    );
  }

  Future<void> _showDesktopMenu(BuildContext context, Offset position) async {
    _focusNode.requestFocus();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final action = await showMenu<_LikedTrackAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: _menuItems(),
    );
    _runAction(action);
  }

  Future<void> _showCompactMenu(BuildContext context) async {
    final action = await showModalBottomSheet<_LikedTrackAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('从这里播放'),
              onTap: () => Navigator.pop(context, _LikedTrackAction.play),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('添加到队列'),
              onTap: () => Navigator.pop(context, _LikedTrackAction.addToQueue),
            ),
            if (widget.onOpenAlbum != null)
              ListTile(
                leading: const Icon(Icons.album_rounded),
                title: const Text('打开专辑'),
                onTap: () =>
                    Navigator.pop(context, _LikedTrackAction.openAlbum),
              ),
            if (widget.onOpenArtist != null)
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: const Text('打开歌手'),
                onTap: () =>
                    Navigator.pop(context, _LikedTrackAction.openArtist),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    _runAction(action);
  }

  List<PopupMenuEntry<_LikedTrackAction>> _menuItems() => [
    const PopupMenuItem(
      value: _LikedTrackAction.play,
      child: ListTile(
        leading: Icon(Icons.play_arrow_rounded),
        title: Text('从这里播放'),
      ),
    ),
    const PopupMenuItem(
      value: _LikedTrackAction.addToQueue,
      child: ListTile(
        leading: Icon(Icons.playlist_add_rounded),
        title: Text('添加到队列'),
      ),
    ),
    if (widget.onOpenAlbum != null)
      const PopupMenuItem(
        value: _LikedTrackAction.openAlbum,
        child: ListTile(
          leading: Icon(Icons.album_rounded),
          title: Text('打开专辑'),
        ),
      ),
    if (widget.onOpenArtist != null)
      const PopupMenuItem(
        value: _LikedTrackAction.openArtist,
        child: ListTile(
          leading: Icon(Icons.person_rounded),
          title: Text('打开歌手'),
        ),
      ),
  ];

  void _runAction(_LikedTrackAction? action) {
    switch (action) {
      case _LikedTrackAction.play:
        widget.onPlay();
      case _LikedTrackAction.addToQueue:
        widget.onAddToQueue();
      case _LikedTrackAction.openAlbum:
        widget.onOpenAlbum?.call();
      case _LikedTrackAction.openArtist:
        widget.onOpenArtist?.call();
      case null:
        return;
    }
  }
}

enum _LikedTrackAction { play, addToQueue, openAlbum, openArtist }

class _LikedTrackFooter extends StatelessWidget {
  const _LikedTrackFooter({
    required this.loadedCount,
    required this.total,
    required this.hasMore,
    required this.loading,
    required this.failure,
    required this.onLoadMore,
    required this.onRetry,
  });

  final int loadedCount;
  final int total;
  final bool hasMore;
  final bool loading;
  final UserLibraryFailure? failure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Column(
      children: [
        Text(
          '已加载 $loadedCount / $total 首',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        if (loading)
          const SizedBox.square(
            dimension: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        else if (failure != null)
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试加载'))
        else if (hasMore)
          FilledButton.tonal(
            key: const ValueKey('liked-songs-load-more'),
            onPressed: onLoadMore,
            child: const Text('加载更多'),
          ),
      ],
    ),
  );
}

class _LikedSongsFailure extends StatelessWidget {
  const _LikedSongsFailure({
    required this.failure,
    required this.canRetry,
    required this.showSignInAgain,
    required this.onRetry,
    required this.onSignInAgain,
  });

  final UserLibraryFailure? failure;
  final bool canRetry;
  final bool showSignInAgain;
  final VoidCallback onRetry;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final copy = _failureCopy(failure);
    return _LikedSongsMessage(
      key: const ValueKey('liked-songs-error'),
      icon: showSignInAgain
          ? Icons.lock_outline_rounded
          : Icons.cloud_off_rounded,
      title: copy.$1,
      detail: copy.$2,
      action: showSignInAgain
          ? FilledButton(onPressed: onSignInAgain, child: const Text('重新登录'))
          : canRetry
          ? FilledButton.tonal(onPressed: onRetry, child: const Text('重试'))
          : null,
    );
  }
}

class _LikedSongsMessage extends StatelessWidget {
  const _LikedSongsMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.loading = false,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$title. $detail',
    liveRegion: loading || action != null,
    excludeSemantics: true,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(MusicSpacing.panel),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const CircularProgressIndicator()
              else
                Icon(
                  icon,
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    ),
  );
}

bool _sameTrack(PlaylistTrackSummary? left, PlaylistTrackSummary right) =>
    left != null &&
    left.providerId == right.providerId &&
    left.opaqueId == right.opaqueId;

(String, String) _failureCopy(UserLibraryFailure? failure) => switch (failure) {
  UserLibraryFailure.network => ('网络不可用', '请检查网络后重试。'),
  UserLibraryFailure.serviceUnavailable => (
    'QQ Music 暂时无法加载',
    '你的会话状态保持不变，稍后重试即可。',
  ),
  UserLibraryFailure.credentialRejected ||
  UserLibraryFailure.credentialRejectedStorageCleanupFailed => (
    '登录已失效',
    '请重新登录后加载喜欢的歌曲。',
  ),
  UserLibraryFailure.authenticationRequired ||
  UserLibraryFailure.replaced ||
  UserLibraryFailure.cancelled => ('需要登录', '请登录 QQ Music 后继续。'),
  UserLibraryFailure.invalidResponse => ('无法安全读取喜欢的歌曲', '请重试；当前结果未被部分显示。'),
  UserLibraryFailure.coreUnavailable ||
  UserLibraryFailure.alreadyRunning => ('无法加载喜欢的歌曲', '请重试，或重启应用后再试。'),
  null => ('无法加载喜欢的歌曲', '请重试。'),
};

String _refreshFailureCopy(UserLibraryFailure failure) => switch (failure) {
  UserLibraryFailure.network => '刷新失败：请检查网络。',
  UserLibraryFailure.serviceUnavailable => 'QQ Music 暂时无法刷新。',
  UserLibraryFailure.invalidResponse => '无法安全读取刷新结果。',
  _ => '刷新失败，仍保留上一次结果。',
};
