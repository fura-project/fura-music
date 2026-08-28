import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_refresh_failure_banner.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class LikedSongsPage extends StatefulWidget {
  const LikedSongsPage({
    required this.playlist,
    required this.gateway,
    required this.queuePlaybackController,
    required this.onOpenAlbums,
    required this.onOpenArtists,
    required this.onSignInAgain,
    this.onOpenAlbum,
    this.onOpenArtist,
    super.key,
  });

  final UserPlaylistSummary playlist;
  final PlaylistDetailGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onOpenAlbums;
  final VoidCallback onOpenArtists;
  final VoidCallback onSignInAgain;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<LikedSongsPage> createState() => _LikedSongsPageState();
}

class _LikedSongsPageState extends State<LikedSongsPage> {
  late final PlaylistDetailController _controller;
  late final Listenable _pageListenable;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
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
                onOpenAlbums: widget.onOpenAlbums,
                onOpenArtists: widget.onOpenArtists,
              ),
              if (_controller.isRefreshing)
                const LinearProgressIndicator(
                  key: ValueKey('liked-songs-refresh-progress'),
                ),
              if (_controller.refreshFailure case final failure?)
                LibraryRefreshFailureBanner(
                  key: const ValueKey('liked-songs-refresh-failure'),
                  message: _refreshFailureCopy(failure),
                  canRetry: _controller.canRetryRefresh,
                  onRetry: _controller.retryRefresh,
                  onDismiss: _controller.dismissRefreshFailure,
                ),
              Expanded(child: _body(desktop, tracks)),
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
    required this.onOpenAlbums,
    required this.onOpenArtists,
  });

  final int? total;
  final bool desktop;
  final bool canPlay;
  final bool isRefreshing;
  final TextEditingController searchController;
  final VoidCallback? onPlayAll;
  final VoidCallback? onRefresh;
  final VoidCallback onOpenAlbums;
  final VoidCallback onOpenArtists;

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
            onOpenAlbums: onOpenAlbums,
            onOpenArtists: onOpenArtists,
          ),
          const SizedBox(height: 18),
          if (desktop)
            Row(
              children: [
                _PlayAllButton(onPressed: onPlayAll),
                const SizedBox(width: 10),
                _RefreshButton(refreshing: isRefreshing, onPressed: onRefresh),
                const Spacer(),
                SizedBox(
                  width: 220,
                  child: _LikedSongsSearch(controller: searchController),
                ),
              ],
            )
          else ...[
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
            _LikedSongsSearch(controller: searchController),
          ],
        ],
      ),
    );
  }
}

class _LikedCategoryTabs extends StatelessWidget {
  const _LikedCategoryTabs({
    required this.total,
    required this.onOpenAlbums,
    required this.onOpenArtists,
  });

  final int? total;
  final VoidCallback onOpenAlbums;
  final VoidCallback onOpenArtists;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('liked-songs-tabs'),
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _LikedCategoryTab(
          label: total == null ? '歌曲' : '歌曲 $total',
          selected: true,
        ),
        const SizedBox(width: 28),
        _LikedCategoryTab(label: '专辑', onTap: onOpenAlbums),
        const SizedBox(width: 28),
        _LikedCategoryTab(label: '歌手', onTap: onOpenArtists),
      ],
    ),
  );
}

class _LikedCategoryTab extends StatelessWidget {
  const _LikedCategoryTab({
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: !selected,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 7),
              AnimatedContainer(
                duration: MusicMotion.stateChange,
                width: selected ? 28 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

class _LikedSongsSearch extends StatelessWidget {
  const _LikedSongsSearch({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
    key: const ValueKey('liked-songs-search'),
    controller: controller,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: '搜索已加载歌曲',
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
  );
}

class _LikedTrackCollection extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final horizontal = desktop ? MusicSpacing.page : 10.0;
    return Column(
      children: [
        if (desktop)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: const _LikedTrackTableHeader(),
          ),
        Expanded(
          child: ListView.separated(
            key: const PageStorageKey<String>('liked-songs-track-list'),
            padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 20),
            itemCount: tracks.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 1),
            itemBuilder: (context, index) {
              if (index == tracks.length) {
                return _LikedTrackFooter(
                  loadedCount: loadedCount,
                  total: total,
                  hasMore: hasMore,
                  loading: isLoadingMore,
                  failure: appendFailure,
                  onLoadMore: onLoadMore,
                  onRetry: onRetryMore,
                );
              }
              final track = tracks[index];
              return _LikedTrackRow(
                index: index + 1,
                track: track,
                desktop: desktop,
                current: _sameTrack(current, track),
                onPlay: () => onTrackSelected(index),
                onAddToQueue: () => onTrackQueued(track),
                onOpenAlbum: onOpenAlbum == null || track.album == null
                    ? null
                    : () => onOpenAlbum!(track.album!),
                onOpenArtist: onOpenArtist == null || track.artists.length != 1
                    ? null
                    : () => onOpenArtist!(track.artists.single),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LikedTrackTableHeader extends StatelessWidget {
  const _LikedTrackTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    return Container(
      key: const ValueKey('liked-songs-table-header'),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text('#', style: style)),
          Expanded(flex: 3, child: Text('标题', style: style)),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: Text('歌手', style: style)),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: Text('专辑', style: style)),
          const SizedBox(width: 16),
          SizedBox(
            width: 52,
            child: Text('时长', textAlign: TextAlign.end, style: style),
          ),
        ],
      ),
    );
  }
}

class _LikedTrackRow extends StatefulWidget {
  const _LikedTrackRow({
    required this.index,
    required this.track,
    required this.desktop,
    required this.current,
    required this.onPlay,
    required this.onAddToQueue,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

  final int index;
  final PlaylistTrackSummary track;
  final bool desktop;
  final bool current;
  final VoidCallback onPlay;
  final VoidCallback onAddToQueue;
  final VoidCallback? onOpenAlbum;
  final VoidCallback? onOpenArtist;

  @override
  State<_LikedTrackRow> createState() => _LikedTrackRowState();
}

class _LikedTrackRowState extends State<_LikedTrackRow> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;

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
    final active = _hovered || _focusNode.hasFocus;
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
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
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
            child: AnimatedContainer(
              duration: MusicMotion.stateChange,
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
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Center(
            child: widget.current
                ? Icon(Icons.equalizer_rounded, size: 18, color: colors.primary)
                : active
                ? Icon(
                    Icons.play_arrow_rounded,
                    size: 19,
                    color: colors.primary,
                  )
                : Text(
                    '${widget.index}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              SizedBox.square(
                dimension: 40,
                child: _LikedTrackArtwork(uri: widget.track.artworkUri),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: widget.current ? colors.primary : colors.onSurface,
                    fontWeight: widget.current
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
              if (active)
                IconButton(
                  tooltip: '添加到队列',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onAddToQueue,
                  icon: const Icon(Icons.playlist_add_rounded, size: 19),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(flex: 2, child: _MetadataText(artists)),
        const SizedBox(width: 16),
        Expanded(flex: 2, child: _MetadataText(widget.track.albumTitle ?? '—')),
        const SizedBox(width: 16),
        SizedBox(
          width: 52,
          child: _MetadataText(
            _duration(widget.track.durationSeconds),
            alignment: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _compactContent(BuildContext context, String artists) => Row(
    children: [
      SizedBox(
        width: 26,
        child: widget.current
            ? Icon(
                Icons.equalizer_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              )
            : Text(
                '${widget.index}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
      ),
      const SizedBox(width: 8),
      SizedBox.square(
        dimension: 48,
        child: _LikedTrackArtwork(uri: widget.track.artworkUri),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: widget.current
                    ? Theme.of(context).colorScheme.primary
                    : null,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              widget.track.albumTitle == null
                  ? artists
                  : '$artists · ${widget.track.albumTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Text(
        _duration(widget.track.durationSeconds),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      IconButton(
        tooltip: '更多操作',
        onPressed: () => unawaited(_showCompactMenu(context)),
        icon: const Icon(Icons.more_horiz_rounded),
      ),
    ],
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

class _MetadataText extends StatelessWidget {
  const _MetadataText(this.value, {this.alignment});

  final String value;
  final TextAlign? alignment;

  @override
  Widget build(BuildContext context) => Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: alignment,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

class _LikedTrackArtwork extends StatelessWidget {
  const _LikedTrackArtwork({this.uri});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(Icons.music_note_rounded, color: colors.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
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

String _duration(int? seconds) {
  if (seconds == null) return '—';
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

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
