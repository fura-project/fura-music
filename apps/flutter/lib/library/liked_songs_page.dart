import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/catalog/partial_results_notice.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/favorite_albums_page.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_refresh_failure_banner.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_scroll_prefetch.dart';
import 'package:flutterustmusic/library/playlist_track_search_index.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/pagination/bounded_viewport_page_demand.dart';
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
    this.lastOpenedPlaylist,
    this.playlistReturnFocusNode,
    this.onOpenAlbum,
    this.onOpenFavoriteAlbum,
    this.onOpenArtist,
    this.onHeaderCollapsedChanged,
    this.collapsedHeaderActions,
    this.providerDisplayName = 'QQ Music',
    super.key,
  });

  final UserPlaylistSummary? playlist;
  final List<UserPlaylistSummary> playlists;
  final PlaylistDetailGateway gateway;
  final FavoriteAlbumGateway favoriteAlbumGateway;
  final QueuePlaybackController queuePlaybackController;
  final ValueChanged<UserPlaylistSummary> onOpenPlaylist;
  final VoidCallback onSignInAgain;
  final UserPlaylistSummary? lastOpenedPlaylist;
  final FocusNode? playlistReturnFocusNode;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<AlbumSummary>? onOpenFavoriteAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;
  final ValueChanged<bool>? onHeaderCollapsedChanged;
  final Widget? collapsedHeaderActions;
  final String providerDisplayName;

  @override
  State<LikedSongsPage> createState() => _LikedSongsPageState();
}

class _LikedSongsPageState extends State<LikedSongsPage>
    with SingleTickerProviderStateMixin {
  PlaylistDetailController? _controller;
  late final Listenable _pageListenable;
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _LikedCollectionSection _section = _LikedCollectionSection.songs;
  bool _albumsVisited = false;
  bool _headerCollapsed = false;
  bool _userReturningToHeader = false;
  bool _searchLoadScheduled = false;
  final PlaylistTrackSearchIndex _trackSearchIndex = PlaylistTrackSearchIndex();
  List<PlaylistTrackSummary>? _indexedTrackSource;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _LikedCollectionSection.values.length,
      vsync: this,
    )..addListener(_handleTabChanged);
    final playlist = widget.playlist;
    _controller = playlist == null
        ? null
        : PlaylistDetailController(playlist, widget.gateway);
    _pageListenable = Listenable.merge([?_controller]);
    _searchController.addListener(_updateQuery);
    final controller = _controller;
    if (controller != null) {
      controller.addListener(_scheduleSearchLoad);
      unawaited(controller.load());
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _searchController
      ..removeListener(_updateQuery)
      ..dispose();
    _controller
      ?..removeListener(_scheduleSearchLoad)
      ..dispose();
    super.dispose();
  }

  void _updateQuery() {
    final query = normalizePlaylistSearchText(_searchController.text);
    if (query == _query) return;
    _controller?.cancelSearchScan();
    setState(() => _query = query);
    if (query.isEmpty) {
      _controller?.cancelLoadAll();
    } else {
      _scheduleSearchLoad();
    }
  }

  void _scheduleSearchLoad() {
    final controller = _controller;
    if (!mounted ||
        _query.isEmpty ||
        _section != _LikedCollectionSection.songs ||
        controller == null ||
        controller.isRefreshing ||
        controller.stage != PlaylistDetailStage.content ||
        controller.searchScanStage != CollectionSearchScanStage.idle ||
        controller.appendFailure != null ||
        !controller.hasMore ||
        _searchLoadScheduled) {
      return;
    }
    _searchLoadScheduled = true;
    scheduleMicrotask(() {
      _searchLoadScheduled = false;
      if (!mounted ||
          _query.isEmpty ||
          _section != _LikedCollectionSection.songs) {
        return;
      }
      unawaited(_requestSearchWindow());
    });
  }

  Future<void> _requestSearchWindow({bool retryInterrupted = false}) {
    final controller = _controller;
    if (controller == null || _query.isEmpty) return Future.value();
    return controller.requestSearchWindow(
      hasEnoughMatches: () {
        final tracks = controller.tracks;
        if (!identical(tracks, _indexedTrackSource)) {
          _trackSearchIndex.update(tracks);
          _indexedTrackSource = tracks;
        }
        return _trackSearchIndex.search(_query).tracks.length >= 20;
      },
      retryInterrupted: retryInterrupted,
    );
  }

  PlaylistTrackSearchResult get _trackSearchResult {
    final tracks = _controller?.tracks ?? const <PlaylistTrackSummary>[];
    if (!identical(tracks, _indexedTrackSource)) {
      _trackSearchIndex.update(tracks);
      _indexedTrackSource = tracks;
    }
    if (_query.isEmpty) {
      return PlaylistTrackSearchResult(
        tracks: tracks,
        exactMatchCount: tracks.length,
      );
    }
    return _trackSearchIndex.search(_query);
  }

  List<UserPlaylistSummary> get _visiblePlaylists {
    final playlists = widget.playlists
        .where((playlist) => !playlist.isLikedSongs)
        .toList(growable: false);
    if (_query.isEmpty) return playlists;
    return playlists
        .where(
          (playlist) =>
              normalizePlaylistSearchText(playlist.title).contains(_query),
        )
        .toList(growable: false);
  }

  void _handleTabChanged() {
    final section = _LikedCollectionSection.values[_tabController.index];
    if (_section == section) return;
    _controller?.cancelPrefetch();
    _searchController.clear();
    setState(() {
      _section = section;
      if (section == _LikedCollectionSection.albums) _albumsVisited = true;
    });
    _setHeaderCollapsed(false);
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
        : notification.metrics.pixels > 56;
    _setHeaderCollapsed(collapse);
    return false;
  }

  void _setHeaderCollapsed(bool collapsed) {
    if (collapsed == _headerCollapsed) return;
    if (!collapsed) _userReturningToHeader = false;
    setState(() => _headerCollapsed = collapsed);
    widget.onHeaderCollapsedChanged?.call(collapsed);
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
          final l10n = context.l10n;
          final desktop = constraints.maxWidth >= 820;
          final searchResult = _trackSearchResult;
          final tracks = searchResult.tracks;
          final controller = _controller;
          return Column(
            key: const ValueKey('liked-songs-page'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LikedSongsHeader(
                total: controller == null
                    ? null
                    : switch (controller.stage) {
                        PlaylistDetailStage.content ||
                        PlaylistDetailStage.empty => controller.total,
                        _ => widget.playlist?.trackCount,
                      },
                desktop: desktop,
                canPlay: tracks.isNotEmpty,
                isRefreshing: controller?.isRefreshing ?? false,
                searchController: _searchController,
                onPlayAll: tracks.isEmpty ? null : () => _playAll(tracks),
                onRefresh: controller == null || controller.isLoading
                    ? null
                    : controller.refresh,
                selectedSection: _section,
                tabController: _tabController,
                collapsed: _headerCollapsed,
                collapsedActions: widget.collapsedHeaderActions,
                playlistCount: widget.playlists
                    .where((playlist) => !playlist.isLikedSongs)
                    .length,
              ),
              if (_section == _LikedCollectionSection.songs &&
                  (controller?.isRefreshing ?? false))
                const LinearProgressIndicator(
                  key: ValueKey('liked-songs-refresh-progress'),
                ),
              if (_section == _LikedCollectionSection.songs &&
                  controller?.refreshFailure != null)
                LibraryRefreshFailureBanner(
                  key: const ValueKey('liked-songs-refresh-failure'),
                  message: _refreshFailureCopy(
                    l10n,
                    controller!.refreshFailure!,
                    widget.providerDisplayName,
                  ),
                  canRetry: controller.canRetryRefresh,
                  onRetry: controller.retryRefresh,
                  onDismiss: controller.dismissRefreshFailure,
                ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleCollectionScroll,
                  child: TabBarView(
                    key: const ValueKey('liked-collection-pages'),
                    controller: _tabController,
                    children: [
                      _RetainedLikedSection(
                        child: _body(
                          desktop,
                          tracks,
                          approximateMatchCount:
                              searchResult.approximateMatchCount,
                        ),
                      ),
                      _RetainedLikedSection(
                        child: _LikedPlaylistsCollection(
                          playlists: _visiblePlaylists,
                          searching: _query.isNotEmpty,
                          onOpenPlaylist: widget.onOpenPlaylist,
                          lastOpenedPlaylist: widget.lastOpenedPlaylist,
                          returnFocusNode: widget.playlistReturnFocusNode,
                          providerDisplayName: widget.providerDisplayName,
                        ),
                      ),
                      _RetainedLikedSection(
                        child: _albumsVisited
                            ? FavoriteAlbumsPage(
                                key: const ValueKey('liked-favorite-albums'),
                                gateway: widget.favoriteAlbumGateway,
                                queuePlaybackController:
                                    widget.queuePlaybackController,
                                onBack: () => _selectSection(
                                  _LikedCollectionSection.songs,
                                ),
                                onOpenAlbum: (album) =>
                                    widget.onOpenFavoriteAlbum?.call(album),
                                onSignInAgain: widget.onSignInAgain,
                                embedded: true,
                                showHeader: false,
                                filterQuery: _query,
                                providerDisplayName: widget.providerDisplayName,
                              )
                            : const SizedBox.shrink(),
                      ),
                      _RetainedLikedSection(
                        child: _UnavailableLikedCollection(
                          key: const ValueKey('liked-programs-unavailable'),
                          icon: Icons.podcasts_rounded,
                          title: l10n.likedProgramsUnavailableTitle,
                          detail: l10n.likedProgramsUnavailableDetail,
                        ),
                      ),
                      _RetainedLikedSection(
                        child: _UnavailableLikedCollection(
                          key: const ValueKey('liked-videos-unavailable'),
                          icon: Icons.video_library_outlined,
                          title: l10n.likedVideosUnavailableTitle,
                          detail: l10n.likedVideosUnavailableDetail,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _body(
    bool desktop,
    List<PlaylistTrackSummary> tracks, {
    required int approximateMatchCount,
  }) {
    final l10n = context.l10n;
    final controller = _controller;
    if (controller == null) {
      return _LikedSongsMessage(
        key: const ValueKey('liked-songs-unavailable'),
        icon: Icons.favorite_border_rounded,
        title: l10n.likedPlaylistUnavailableTitle,
        detail: l10n.likedPlaylistUnavailableDetail(widget.providerDisplayName),
      );
    }
    return switch (controller.stage) {
      PlaylistDetailStage.loading => _LikedSongsMessage(
        key: const ValueKey('liked-songs-loading'),
        loading: true,
        icon: Icons.favorite_rounded,
        title: l10n.likedLoadingTitle,
        detail: l10n.likedLoadingDetail(widget.providerDisplayName),
      ),
      PlaylistDetailStage.content when tracks.isEmpty => _searchEmpty(
        controller,
      ),
      PlaylistDetailStage.content => BoundedViewportPageDemand(
        enabled:
            _query.isNotEmpty &&
            controller.hasMore &&
            controller.appendFailure == null,
        generation: _query,
        onDemand: _requestSearchWindow,
        onRetreat: controller.cancelSearchScan,
        child: PlaylistScrollPrefetch(
          controller: controller,
          enabled: _query.isEmpty && _section == _LikedCollectionSection.songs,
          child: ValueListenableBuilder<PlaylistTrackSummary?>(
            valueListenable:
                widget.queuePlaybackController.currentTrackListenable,
            builder: (context, current, _) => _LikedTrackCollection(
              tracks: tracks,
              processedCount: controller.processedCount,
              availableTrackCount: controller.tracks.length,
              omittedTrackCount: controller.omittedTrackCount,
              partialResultRevision: controller.partialResultRevision,
              total: controller.total,
              hasMore: controller.hasMore,
              isLoadingMore: controller.isLoadingMore,
              isLoadingAll: controller.isScanningSearch,
              searching: _query.isNotEmpty,
              approximateMatchCount: approximateMatchCount,
              appendFailure: controller.appendFailure,
              desktop: desktop,
              current: current,
              onLoadMore: controller.loadMore,
              onRetryMore: _query.isEmpty
                  ? controller.retryMore
                  : () =>
                        unawaited(_requestSearchWindow(retryInterrupted: true)),
              onTrackSelected: (index) => unawaited(
                widget.queuePlaybackController.replaceAndPlay(tracks, index),
              ),
              onTrackQueued: _addToQueue,
              onOpenAlbum: widget.onOpenAlbum,
              onOpenArtist: widget.onOpenArtist,
            ),
          ),
        ),
      ),
      PlaylistDetailStage.empty => _LikedSongsMessage(
        key: const ValueKey('liked-songs-empty'),
        icon: Icons.favorite_border_rounded,
        title: l10n.likedEmptyTitle,
        detail: l10n.likedEmptyDetail(widget.providerDisplayName),
      ),
      PlaylistDetailStage.error => _LikedSongsFailure(
        failure: controller.failure,
        providerDisplayName: widget.providerDisplayName,
        canRetry: controller.canRetry,
        showSignInAgain: false,
        onRetry: controller.retry,
        onSignInAgain: widget.onSignInAgain,
      ),
      PlaylistDetailStage.authenticationRequired ||
      PlaylistDetailStage.credentialRejected => _LikedSongsFailure(
        failure: controller.failure,
        providerDisplayName: widget.providerDisplayName,
        canRetry: false,
        showSignInAgain: true,
        onRetry: controller.retry,
        onSignInAgain: widget.onSignInAgain,
      ),
    };
  }

  Widget _searchEmpty(PlaylistDetailController controller) {
    final l10n = context.l10n;
    final stillSearching = controller.isScanningSearch;
    final failure = controller.appendFailure;
    final omittedSuffix = controller.omittedTrackCount == 0
        ? ''
        : l10n.likedOmittedSearchSuffix(controller.omittedTrackCount);
    return _LikedSongsMessage(
      key: const ValueKey('liked-songs-search-empty'),
      loading: stillSearching,
      icon: stillSearching
          ? Icons.manage_search_rounded
          : Icons.search_off_rounded,
      title: stillSearching
          ? l10n.likedSearchingAllTitle
          : failure == null
          ? l10n.likedNoTrackMatchTitle
          : l10n.likedSearchInterruptedTitle,
      detail: stillSearching
          ? l10n.likedSearchProgress(
              controller.processedCount,
              controller.total,
            )
          : failure == null
          ? l10n.likedSearchFinishedNoMatch(omittedSuffix, controller.total)
          : l10n.likedSearchInterruptedDetail(
              controller.processedCount,
              controller.total,
            ),
      action: failure == null && !controller.hasMore
          ? null
          : FilledButton.tonal(
              onPressed: () => unawaited(
                _requestSearchWindow(retryInterrupted: failure != null),
              ),
              child: Text(l10n.likedContinueSearch),
            ),
    );
  }

  void _playAll(List<PlaylistTrackSummary> tracks) {
    if (tracks.isEmpty) return;
    unawaited(widget.queuePlaybackController.replaceAndPlay(tracks, 0));
  }

  void _addToQueue(PlaylistTrackSummary track) {
    final playbackStart = widget.queuePlaybackController.push(track);
    final message = widget.queuePlaybackController.failure == null
        ? context.l10n.likedQueueAdded
        : context.l10n.queueUpdateFailureMessage;
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
    required this.collapsed,
    required this.collapsedActions,
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
  final bool collapsed;
  final Widget? collapsedActions;
  final int playlistCount;

  @override
  Widget build(BuildContext context) {
    final horizontal = desktop ? MusicSpacing.page : MusicSpacing.pageCompact;
    return AnimatedSwitcher(
      key: const ValueKey('liked-songs-header-transition'),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : MusicMotion.stateChange,
      switchInCurve: Easing.emphasizedDecelerate,
      switchOutCurve: Easing.emphasizedAccelerate,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
      child: Padding(
        key: ValueKey(
          collapsed
              ? 'liked-songs-collapsed-header'
              : 'liked-songs-expanded-header',
        ),
        padding: EdgeInsets.fromLTRB(
          collapsed ? 12 : horizontal,
          collapsed && desktop
              ? 4
              : collapsed
              ? 6
              : 16,
          collapsed ? 12 : horizontal,
          collapsed && desktop
              ? 4
              : collapsed
              ? 6
              : 14,
        ),
        child: collapsed ? _collapsedHeader(context) : _expandedHeader(context),
      ),
    );
  }

  Widget _expandedHeader(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(context, compact: false),
      const SizedBox(height: 18),
      _tabs(),
      const SizedBox(height: 18),
      if (desktop)
        Row(
          children: [
            if (selectedSection == _LikedCollectionSection.songs) ...[
              _PlayAllButton(onPressed: onPlayAll),
              const SizedBox(width: 10),
              _RefreshButton(refreshing: isRefreshing, onPressed: onRefresh),
            ],
            const Spacer(),
            SizedBox(width: 220, child: _search()),
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
        _search(),
      ],
    ],
  );

  Widget _collapsedHeader(BuildContext context) {
    if (desktop) {
      return SizedBox(
        height: 48,
        child: Row(
          key: const ValueKey('liked-songs-collapsed-row'),
          children: [
            _title(context, compact: true),
            const SizedBox(width: 12),
            Expanded(child: _tabs()),
            if (selectedSection == _LikedCollectionSection.songs) ...[
              const SizedBox(width: 8),
              _PlayAllButton(onPressed: onPlayAll, compact: true),
              const SizedBox(width: 8),
              _RefreshButton(
                refreshing: isRefreshing,
                onPressed: onRefresh,
                compact: true,
              ),
            ],
            const SizedBox(width: 12),
            SizedBox(width: 220, child: _search()),
            if (collapsedActions case final actions?) ...[
              const SizedBox(width: 4),
              actions,
            ],
          ],
        ),
      );
    }
    return Column(
      key: const ValueKey('liked-songs-collapsed-column'),
      children: [
        Row(
          children: [
            _title(context, compact: true),
            const SizedBox(width: 12),
            Expanded(child: _search()),
            if (collapsedActions case final actions?) ...[
              const SizedBox(width: 4),
              actions,
            ],
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(child: _tabs()),
              if (selectedSection == _LikedCollectionSection.songs) ...[
                _PlayAllButton(onPressed: onPlayAll, compact: true),
                const SizedBox(width: 8),
                _RefreshButton(
                  refreshing: isRefreshing,
                  onPressed: onRefresh,
                  compact: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _title(BuildContext context, {required bool compact}) => Text(
    context.l10n.likedTitle,
    key: const ValueKey('liked-songs-title'),
    style: compact
        ? Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
  );

  Widget _tabs() => _LikedCategoryTabs(
    total: total,
    playlistCount: playlistCount,
    controller: tabController,
  );

  Widget _search() => _LikedCollectionSearch(
    controller: searchController,
    section: selectedSection,
  );
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
            _LikedCollectionSection.songs =>
              total == null
                  ? context.l10n.likedSongsTabWithoutCount
                  : context.l10n.likedSongsTab(total!),
            _LikedCollectionSection.playlists => context.l10n.likedPlaylistsTab(
              playlistCount,
            ),
            _LikedCollectionSection.albums => context.l10n.likedAlbumsTab,
            _LikedCollectionSection.programs => context.l10n.likedProgramsTab,
            _LikedCollectionSection.videos => context.l10n.likedVideosTab,
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
    required this.lastOpenedPlaylist,
    required this.returnFocusNode,
    required this.providerDisplayName,
  });

  final List<UserPlaylistSummary> playlists;
  final bool searching;
  final ValueChanged<UserPlaylistSummary> onOpenPlaylist;
  final UserPlaylistSummary? lastOpenedPlaylist;
  final FocusNode? returnFocusNode;
  final String providerDisplayName;

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
        title: searching
            ? context.l10n.likedNoPlaylistMatch
            : context.l10n.likedNoOtherPlaylists,
        detail: searching
            ? context.l10n.likedTryAnotherKeyword
            : context.l10n.likedPlaylistCollectionDetail(providerDisplayName),
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
              title: context.l10n.likedCreatedPlaylists,
              playlists: owned,
              columns: columns,
              horizontal: horizontal,
            ),
            ..._playlistSection(
              context,
              title: context.l10n.likedSavedPlaylists,
              playlists: saved,
              columns: columns,
              horizontal: horizontal,
            ),
            ..._playlistSection(
              context,
              title: context.l10n.likedOtherPlaylists,
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
            context.l10n.likedPlaylistSectionCount(playlists.length, title),
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
              focusNode:
                  lastOpenedPlaylist?.providerId ==
                          playlists[index].providerId &&
                      lastOpenedPlaylist?.opaqueId == playlists[index].opaqueId
                  ? returnFocusNode
                  : null,
            ),
            childCount: playlists.length,
          ),
        ),
      ),
    ];
  }
}

class _LikedPlaylistCard extends StatelessWidget {
  const _LikedPlaylistCard({
    required this.playlist,
    required this.onTap,
    required this.focusNode,
  });

  final UserPlaylistSummary playlist;
  final VoidCallback onTap;
  final FocusNode? focusNode;

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
      label: context.l10n.likedPlaylistSemantics(playlist.title),
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: ValueKey('liked-playlist-${playlist.opaqueId}'),
        focusNode: focusNode,
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
                          headers: musicArtworkRequestHeaders(
                            playlist.artworkUri!,
                          ),
                          fit: BoxFit.cover,
                          errorBuilder: musicArtworkErrorBuilder(
                            playlist.artworkUri!,
                            artwork,
                          ),
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
                context.l10n.likedTrackCount(count),
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
  const _PlayAllButton({required this.onPressed, this.compact = false});

  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) => compact
      ? IconButton.filled(
          key: const ValueKey('liked-songs-play-all'),
          tooltip: context.l10n.likedPlayAll,
          onPressed: onPressed,
          icon: const Icon(Icons.play_arrow_rounded),
        )
      : FilledButton.icon(
          key: const ValueKey('liked-songs-play-all'),
          onPressed: onPressed,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(context.l10n.likedPlayAll),
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
          key: const ValueKey('liked-songs-refresh-compact'),
          tooltip: refreshing
              ? context.l10n.likedRefreshing
              : context.l10n.likedRefreshSongs,
          onPressed: onPressed,
          icon: const Icon(Icons.refresh_rounded),
        )
      : FilledButton.tonalIcon(
          key: const ValueKey('liked-songs-refresh'),
          onPressed: onPressed,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(
            refreshing
                ? context.l10n.likedRefreshing
                : context.l10n.commonRefresh,
          ),
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
      _LikedCollectionSection.songs => context.l10n.likedSearchEntirePlaylist,
      _LikedCollectionSection.playlists => context.l10n.likedSearchPlaylists,
      _LikedCollectionSection.albums => context.l10n.likedSearchLoadedAlbums,
      _LikedCollectionSection.programs =>
        context.l10n.likedProgramsSearchUnavailable,
      _LikedCollectionSection.videos =>
        context.l10n.likedVideosSearchUnavailable,
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
                  tooltip: context.l10n.commonClearSearch,
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
    required this.processedCount,
    required this.availableTrackCount,
    required this.omittedTrackCount,
    required this.partialResultRevision,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
    required this.isLoadingAll,
    required this.searching,
    required this.approximateMatchCount,
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
  final int processedCount;
  final int availableTrackCount;
  final int omittedTrackCount;
  final int partialResultRevision;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isLoadingAll;
  final bool searching;
  final int approximateMatchCount;
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
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
          child: MusicTrackLocatorOverlay(
            controller: _scrollController,
            currentIndex: musicTrackIndexOf(widget.tracks, widget.current),
            desktop: widget.desktop,
            child: NotificationListener<ScrollNotification>(
              onNotification: _clearHoverOnScroll,
              child: ListView.separated(
                controller: _scrollController,
                key: const PageStorageKey<String>('liked-songs-track-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 20),
                itemCount: widget.tracks.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 1),
                itemBuilder: (context, index) {
                  if (index == widget.tracks.length) {
                    return _LikedTrackFooter(
                      processedCount: widget.processedCount,
                      availableTrackCount: widget.availableTrackCount,
                      omittedTrackCount: widget.omittedTrackCount,
                      partialResultRevision: widget.partialResultRevision,
                      total: widget.total,
                      hasMore: widget.hasMore,
                      loading: widget.isLoadingMore,
                      loadingAll: widget.isLoadingAll,
                      searching: widget.searching,
                      matchCount: widget.tracks.length,
                      approximateMatchCount: widget.approximateMatchCount,
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
                    onOpenAlbum:
                        widget.onOpenAlbum == null || track.album == null
                        ? null
                        : () => widget.onOpenAlbum!(track.album!),
                    onOpenArtist: widget.onOpenArtist,
                  );
                },
              ),
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
  Widget build(BuildContext context) => MusicTrackTableHeader(
    key: const ValueKey('liked-songs-table-header'),
    titleLabel: context.l10n.tableTitle,
    artistLabel: context.l10n.tableArtist,
    albumLabel: context.l10n.tableAlbum,
    durationLabel: context.l10n.tableDuration,
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
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<_LikedTrackRow> createState() => _LikedTrackRowState();
}

class _LikedTrackRowState extends State<_LikedTrackRow> {
  @override
  Widget build(BuildContext context) {
    final artists = widget.track.artistNames.isEmpty
        ? context.l10n.trackUnknownArtist
        : widget.track.artistNames.join(' / ');
    return MusicTrackRowSurface(
      itemKey: ValueKey('liked-track-row-${widget.index}'),
      desktop: widget.desktop,
      current: widget.current,
      hovered: widget.hovered,
      onHoverChanged: widget.onHoverChanged,
      semanticLabel: context.l10n.commonTrackSemantics(
        artists,
        widget.track.title,
      ),
      onTap: widget.onPlay,
      onContextMenuRequested: (position) => unawaited(
        position == null
            ? _showCompactMenu(context)
            : _showDesktopMenu(context, position),
      ),
      contentBuilder: (context, active, hovered) => widget.desktop
          ? _desktopContent(context, artists, active, hovered)
          : _compactContent(context, artists),
    );
  }

  Widget _desktopContent(
    BuildContext context,
    String artists,
    bool active,
    bool hovered,
  ) {
    return MusicTrackRowContent(
      index: widget.index,
      track: widget.track,
      desktop: true,
      current: widget.current,
      active: active,
      artistNames: artists,
      onPlay: widget.onPlay,
      onAddToQueue: widget.onAddToQueue,
      onOpenAlbum: widget.onOpenAlbum,
      onOpenArtist: widget.onOpenArtist == null || widget.track.artists.isEmpty
          ? null
          : _openArtist,
      onMore: () => unawaited(_showDesktopMenuAtRow(context)),
      showInlineQueueAction: hovered,
      addToQueueTooltip: context.l10n.commonAddToQueue,
      moreTooltip: context.l10n.commonMoreActions,
      playTooltip: context.l10n.commonPlayFromHere,
      albumTooltip: context.l10n.commonOpenAlbum,
      artistTooltip: widget.track.artists.length > 1
          ? context.l10n.commonChooseArtist
          : context.l10n.commonOpenArtist,
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
        onPlay: widget.onPlay,
        onAddToQueue: widget.onAddToQueue,
        onOpenAlbum: widget.onOpenAlbum,
        onOpenArtist:
            widget.onOpenArtist == null || widget.track.artists.isEmpty
            ? null
            : _openArtist,
        onMore: () => unawaited(_showCompactMenu(context)),
        addToQueueTooltip: context.l10n.commonAddToQueue,
        moreTooltip: context.l10n.commonMoreActions,
        playTooltip: context.l10n.commonPlayFromHere,
        albumTooltip: context.l10n.commonOpenAlbum,
        artistTooltip: widget.track.artists.length > 1
            ? context.l10n.commonChooseArtist
            : context.l10n.commonOpenArtist,
      );

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
              title: Text(context.l10n.commonPlayFromHere),
              onTap: () => Navigator.pop(context, _LikedTrackAction.play),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(context.l10n.commonAddToQueue),
              onTap: () => Navigator.pop(context, _LikedTrackAction.addToQueue),
            ),
            if (widget.onOpenAlbum != null)
              ListTile(
                leading: const Icon(Icons.album_rounded),
                title: Text(context.l10n.commonOpenAlbum),
                onTap: () =>
                    Navigator.pop(context, _LikedTrackAction.openAlbum),
              ),
            if (widget.onOpenArtist != null)
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: Text(context.l10n.commonOpenArtist),
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
    PopupMenuItem(
      value: _LikedTrackAction.play,
      child: ListTile(
        leading: Icon(Icons.play_arrow_rounded),
        title: Text(context.l10n.commonPlayFromHere),
      ),
    ),
    PopupMenuItem(
      value: _LikedTrackAction.addToQueue,
      child: ListTile(
        leading: Icon(Icons.playlist_add_rounded),
        title: Text(context.l10n.commonAddToQueue),
      ),
    ),
    if (widget.onOpenAlbum != null)
      PopupMenuItem(
        value: _LikedTrackAction.openAlbum,
        child: ListTile(
          leading: Icon(Icons.album_rounded),
          title: Text(context.l10n.commonOpenAlbum),
        ),
      ),
    if (widget.onOpenArtist != null)
      PopupMenuItem(
        value: _LikedTrackAction.openArtist,
        child: ListTile(
          leading: Icon(Icons.person_rounded),
          title: Text(context.l10n.commonOpenArtist),
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
        _openArtist();
      case null:
        return;
    }
  }

  void _openArtist() {
    unawaited(
      openMusicTrackArtists(
        context: context,
        artists: widget.track.artists,
        onSelected: widget.onOpenArtist,
        title: context.l10n.trackChooseArtistTitle,
        detail: context.l10n.likedMultipleArtistsDetail,
        cancelLabel: context.l10n.commonCancel,
        itemKeyPrefix: 'liked-track-artist',
      ),
    );
  }
}

enum _LikedTrackAction { play, addToQueue, openAlbum, openArtist }

class _LikedTrackFooter extends StatelessWidget {
  const _LikedTrackFooter({
    required this.processedCount,
    required this.availableTrackCount,
    required this.omittedTrackCount,
    required this.partialResultRevision,
    required this.total,
    required this.hasMore,
    required this.loading,
    required this.loadingAll,
    required this.searching,
    required this.matchCount,
    required this.approximateMatchCount,
    required this.failure,
    required this.onLoadMore,
    required this.onRetry,
  });

  final int processedCount;
  final int availableTrackCount;
  final int omittedTrackCount;
  final int partialResultRevision;
  final int total;
  final bool hasMore;
  final bool loading;
  final bool loadingAll;
  final bool searching;
  final int matchCount;
  final int approximateMatchCount;
  final UserLibraryFailure? failure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Column(
      children: [
        Text(
          _statusText(context.l10n),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        if (omittedTrackCount > 0) ...[
          const SizedBox(height: 8),
          PartialResultsNotice(
            omittedCount: omittedTrackCount,
            resultRevision: partialResultRevision,
          ),
        ],
        const SizedBox(height: 10),
        if (loading || loadingAll)
          const SizedBox.square(
            dimension: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        else if (failure != null)
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text(context.l10n.likedRetryLoad),
          )
        else if (hasMore)
          FilledButton.tonal(
            key: const ValueKey('liked-songs-load-more'),
            onPressed: onLoadMore,
            child: Text(context.l10n.commonLoadMore),
          ),
      ],
    ),
  );

  String _statusText(AppLocalizations l10n) {
    if (!searching) {
      return l10n.likedReadStatus(availableTrackCount, processedCount, total);
    }
    if (failure != null) {
      return l10n.likedSearchInterruptedStatus(processedCount, total);
    }
    final approximateOnly =
        matchCount > 0 && approximateMatchCount == matchCount;
    final resultSummary = approximateMatchCount == 0
        ? l10n.likedExactResults(matchCount)
        : approximateOnly
        ? l10n.likedApproximateResults(matchCount)
        : l10n.likedMixedResults(approximateMatchCount, matchCount);
    if (loadingAll || hasMore) {
      return l10n.likedSearchingStatus(processedCount, resultSummary, total);
    }
    return approximateOnly
        ? l10n.likedApproximateOnlyStatus(resultSummary)
        : l10n.likedSearchCompleteStatus(resultSummary, total);
  }
}

class _LikedSongsFailure extends StatelessWidget {
  const _LikedSongsFailure({
    required this.failure,
    required this.providerDisplayName,
    required this.canRetry,
    required this.showSignInAgain,
    required this.onRetry,
    required this.onSignInAgain,
  });

  final UserLibraryFailure? failure;
  final String providerDisplayName;
  final bool canRetry;
  final bool showSignInAgain;
  final VoidCallback onRetry;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final copy = _failureCopy(context.l10n, failure, providerDisplayName);
    return _LikedSongsMessage(
      key: const ValueKey('liked-songs-error'),
      icon: showSignInAgain
          ? Icons.lock_outline_rounded
          : Icons.cloud_off_rounded,
      title: copy.$1,
      detail: copy.$2,
      action: showSignInAgain
          ? FilledButton(
              onPressed: onSignInAgain,
              child: Text(context.l10n.authSignInAgain),
            )
          : canRetry
          ? FilledButton.tonal(
              onPressed: onRetry,
              child: Text(context.l10n.commonRetry),
            )
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
    label: context.l10n.commonAnnouncement(detail, title),
    liveRegion: loading || action != null,
    excludeSemantics: true,
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MusicSpacing.panel),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
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

(String, String) _failureCopy(
  AppLocalizations l10n,
  UserLibraryFailure? failure,
  String providerDisplayName,
) => switch (failure) {
  UserLibraryFailure.network => (
    l10n.likedFailureNetworkTitle,
    l10n.likedFailureNetworkDetail,
  ),
  UserLibraryFailure.serviceUnavailable => (
    l10n.likedFailureServiceTitle(providerDisplayName),
    l10n.likedFailureServiceDetail,
  ),
  UserLibraryFailure.credentialRejected ||
  UserLibraryFailure.credentialRejectedStorageCleanupFailed => (
    l10n.likedFailureSignedOutTitle,
    l10n.likedFailureSignedOutDetail,
  ),
  UserLibraryFailure.authenticationRequired ||
  UserLibraryFailure.replaced ||
  UserLibraryFailure.cancelled => (
    l10n.likedFailureAuthenticationTitle,
    l10n.likedFailureAuthenticationDetail(providerDisplayName),
  ),
  UserLibraryFailure.invalidResponse => (
    l10n.likedFailureInvalidTitle,
    l10n.likedFailureInvalidDetail,
  ),
  UserLibraryFailure.coreUnavailable || UserLibraryFailure.alreadyRunning => (
    l10n.likedFailureCoreTitle,
    l10n.likedFailureCoreDetail,
  ),
  null => (l10n.likedFailureCoreTitle, l10n.likedFailureGenericDetail),
};

String _refreshFailureCopy(
  AppLocalizations l10n,
  UserLibraryFailure failure,
  String providerDisplayName,
) => switch (failure) {
  UserLibraryFailure.network => l10n.likedRefreshNetworkFailure,
  UserLibraryFailure.serviceUnavailable => l10n.likedRefreshServiceFailure(
    providerDisplayName,
  ),
  UserLibraryFailure.invalidResponse => l10n.likedRefreshInvalidResponse,
  _ => l10n.likedRefreshFailure,
};
