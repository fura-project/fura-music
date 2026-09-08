import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/paged_tracks_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_scroll_prefetch.dart';
import 'package:flutterustmusic/library/playlist_track_search_index.dart';
import 'package:flutterustmusic/library/recent_plays_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

class RecentPlaysPage extends StatefulWidget {
  const RecentPlaysPage({
    required this.gateway,
    required this.playback,
    required this.onSignInAgain,
    required this.active,
    this.onOpenAlbum,
    this.onOpenArtist,
    super.key,
  });

  /// Null means cloud history is not connected, never a successful empty result.
  final RecentPlaysGateway? gateway;
  final QueuePlaybackController playback;
  final VoidCallback onSignInAgain;
  final bool active;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<RecentPlaysPage> createState() => _RecentPlaysPageState();
}

class _RecentPlaysPageState extends State<RecentPlaysPage> {
  PagedTracksController? _controller;
  final _search = TextEditingController();
  final _index = PlaylistTrackSearchIndex();
  List<PlaylistTrackSummary>? _indexedTracks;
  String _query = '';
  bool _searchScheduled = false;

  @override
  void initState() {
    super.initState();
    _attachSource();
    _search.addListener(_updateSearch);
  }

  void _attachSource() {
    final source = widget.gateway;
    if (source == null) return;
    _controller = PagedTracksController(
      (offset, size) => source.beginLoad(offset: offset, size: size),
    )..addListener(_continueSearch);
    unawaited(_controller!.load());
  }

  @override
  void didUpdateWidget(RecentPlaysPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway) {
      _controller?.dispose();
      _controller = null;
      _search.clear();
      _attachSource();
    }
    if (!widget.active) {
      _controller?.cancelPrefetch();
      _controller?.cancelLoadAll();
    } else if (!oldWidget.active) {
      _continueSearch();
    }
  }

  void _updateSearch() {
    final query = normalizePlaylistSearchText(_search.text);
    if (_query == query) return;
    setState(() => _query = query);
    if (query.isEmpty) {
      _controller?.cancelLoadAll();
    } else {
      _controller?.cancelPrefetch();
      _continueSearch();
    }
  }

  void _continueSearch() {
    final controller = _controller;
    if (!mounted ||
        !widget.active ||
        _query.isEmpty ||
        controller == null ||
        controller.isRefreshing ||
        controller.isLoadingAll ||
        controller.stage != PlaylistDetailStage.content ||
        !controller.hasMore ||
        controller.appendFailure != null ||
        _searchScheduled) {
      return;
    }
    _searchScheduled = true;
    scheduleMicrotask(() {
      _searchScheduled = false;
      if (mounted &&
          widget.active &&
          _query.isNotEmpty &&
          identical(controller, _controller)) {
        unawaited(controller.loadAll());
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      ?_controller,
      widget.playback.currentTrackListenable,
    ]),
    builder: (context, _) {
      final controller = _controller;
      final loaded = controller?.tracks ?? const <PlaylistTrackSummary>[];
      if (!identical(loaded, _indexedTracks)) {
        _index.update(loaded);
        _indexedTracks = loaded;
      }
      final result = _query.isEmpty
          ? PlaylistTrackSearchResult(
              tracks: loaded,
              exactMatchCount: loaded.length,
            )
          : _index.search(_query);
      final tracks = result.tracks;
      final hasSnapshot =
          controller?.stage == PlaylistDetailStage.content ||
          controller?.stage == PlaylistDetailStage.empty;
      return LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 820;
          final padding = desktop ? 28.0 : 16.0;
          final theme = Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(padding, 20, padding, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '最近播放',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          controller == null
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_queue_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            controller == null
                                ? 'QQ 音乐云端记录尚未接通'
                                : 'QQ 音乐账号的播放记录 · 最近播放优先',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          hasSnapshot
                              ? controller!.totalIsExact
                                    ? '歌曲 ${controller.total}'
                                    : '歌曲（已知至少 ${controller.total} 首）'
                              : '歌曲',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        if (!desktop && hasSnapshot) ...[
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              controller!.totalIsExact
                                  ? '${_query.isEmpty ? '已加载' : '已搜索'} ${controller.processedCount} / ${controller.total} 首'
                                  : '${_query.isEmpty ? '已加载' : '已搜索'} ${controller.processedCount} 首',
                              maxLines: 2,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 32,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const SizedBox(height: 3),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('recent-plays-play'),
                          onPressed: tracks.isEmpty
                              ? null
                              : () => unawaited(
                                  widget.playback.replaceAndPlay(tracks, 0),
                                ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('播放'),
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey('recent-plays-refresh'),
                          onPressed: controller == null || controller.isLoading
                              ? null
                              : controller.refresh,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('刷新'),
                        ),
                        SizedBox(
                          width: desktop
                              ? 300
                              : constraints.maxWidth - 2 * padding,
                          child: TextField(
                            key: const ValueKey('recent-plays-search'),
                            controller: _search,
                            enabled: hasSnapshot,
                            decoration: InputDecoration(
                              hintText: '搜索最近播放',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: '清除搜索',
                                      onPressed: _search.clear,
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                              isDense: true,
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(28),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (controller?.isRefreshing ?? false)
                const LinearProgressIndicator(),
              if (controller?.refreshFailure != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: Row(
                    children: [
                      const Expanded(child: Text('刷新失败，仍显示上次读取的记录。')),
                      TextButton(
                        onPressed: controller!.retryRefresh,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              if (desktop && hasSnapshot)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: const MusicTrackTableHeader(
                    titleLabel: '歌曲',
                    artistLabel: '歌手',
                    albumLabel: '专辑',
                    durationLabel: '时长',
                  ),
                ),
              Expanded(child: _body(controller, tracks, desktop, padding)),
              if (hasSnapshot && desktop)
                Padding(
                  padding: EdgeInsets.fromLTRB(padding, 8, padding, 12),
                  child: Text(
                    '${_query.isEmpty ? '已加载' : '已搜索'} ${controller!.processedCount}'
                    '${controller.totalIsExact ? ' / ${controller.total}' : ''} 首'
                    '${result.approximateMatchCount > 0 ? ' · ${result.approximateMatchCount} 个近似匹配' : ''}'
                    '${controller.omittedTrackCount > 0 ? ' · ${controller.omittedTrackCount} 首暂不可显示' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          );
        },
      );
    },
  );

  Widget _body(
    PagedTracksController? controller,
    List<PlaylistTrackSummary> tracks,
    bool desktop,
    double padding,
  ) {
    if (controller == null) {
      return const _RecentMessage(
        icon: Icons.cloud_off_outlined,
        title: '暂时无法读取跨设备播放记录',
        detail: '当前版本尚未接通 QQ 音乐的云端最近播放。\n接通后，你可以在这里查看同一账号的播放记录。',
      );
    }
    switch (controller.stage) {
      case PlaylistDetailStage.loading:
        return const _RecentMessage(
          icon: Icons.history_rounded,
          title: '正在读取最近播放…',
          loading: true,
        );
      case PlaylistDetailStage.authenticationRequired:
      case PlaylistDetailStage.credentialRejected:
        return _RecentMessage(
          icon: Icons.login_rounded,
          title: '请重新登录 QQ 音乐',
          detail: '登录同一账号后再读取云端播放记录。',
          action: FilledButton(
            onPressed: widget.onSignInAgain,
            child: const Text('重新登录'),
          ),
        );
      case PlaylistDetailStage.error:
        return _RecentMessage(
          icon: Icons.cloud_off_outlined,
          title: '暂时无法读取最近播放',
          detail: '请稍后重试。',
          action: controller.canRetry
              ? FilledButton.tonal(
                  onPressed: controller.retry,
                  child: const Text('重试'),
                )
              : null,
        );
      case PlaylistDetailStage.empty:
        return const _RecentMessage(
          icon: Icons.history_rounded,
          title: '还没有云端播放记录',
          detail: '刷新可以重新读取 QQ 音乐返回的记录。',
        );
      case PlaylistDetailStage.content:
        return PlaylistScrollPrefetch(
          controller: controller,
          enabled: widget.active && _query.isEmpty,
          child: ListView.builder(
            key: const PageStorageKey('recent-plays-tracks'),
            padding: EdgeInsets.fromLTRB(
              padding,
              0,
              padding,
              desktop ? 24 : 112,
            ),
            itemCount: tracks.length + 1,
            itemBuilder: (context, index) {
              if (index == tracks.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      if (tracks.isEmpty)
                        Text(
                          controller.isLoadingAll ? '正在搜索整个播放记录…' : '未找到匹配的歌曲',
                        ),
                      if (controller.isLoadingMore || controller.isLoadingAll)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: LinearProgressIndicator(),
                        )
                      else if (controller.appendFailure != null) ...[
                        const Text('后续记录加载失败，已加载的歌曲仍可播放。'),
                        TextButton(
                          onPressed: controller.canRetryMore
                              ? () => _query.isEmpty
                                    ? controller.retryMore()
                                    : unawaited(controller.loadAll())
                              : null,
                          child: const Text('继续加载'),
                        ),
                      ] else if (controller.hasMore)
                        TextButton(
                          onPressed: controller.loadMore,
                          child: const Text('加载更多'),
                        ),
                    ],
                  ),
                );
              }
              final track = tracks[index];
              final current = widget.playback.currentTrackListenable.value;
              return CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.contextMenu): () =>
                      unawaited(_showTrackActions(track)),
                  const SingleActivator(
                    LogicalKeyboardKey.f10,
                    shift: true,
                  ): () =>
                      unawaited(_showTrackActions(track)),
                },
                child: Material(
                  color: index.isEven
                      ? Theme.of(context).colorScheme.surfaceContainerLow
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    key: ValueKey('recent-plays-track-$index'),
                    borderRadius: BorderRadius.circular(10),
                    onSecondaryTap: () => unawaited(_showTrackActions(track)),
                    onTap: () => unawaited(
                      widget.playback.replaceAndPlay(tracks, index),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: MusicTrackRowContent(
                        index: index + 1,
                        track: track,
                        desktop: desktop,
                        current:
                            current?.providerId == track.providerId &&
                            current?.opaqueId == track.opaqueId,
                        active: false,
                        showInlineQueueAction: true,
                        artistNames: track.artistNames.join(' / '),
                        onAddToQueue: () =>
                            unawaited(widget.playback.push(track)),
                        onMore: () => _showTrackActions(track),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
    }
  }

  Future<void> _showTrackActions(PlaylistTrackSummary track) async {
    Widget actions(BuildContext context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('加入播放队列'),
              onTap: () {
                Navigator.pop(context);
                unawaited(widget.playback.push(track));
              },
            ),
            if (track.album != null && widget.onOpenAlbum != null)
              ListTile(
                leading: const Icon(Icons.album_outlined),
                title: const Text('查看专辑'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenAlbum!(track.album!);
                },
              ),
            if (widget.onOpenArtist != null)
              for (final artist in track.artists)
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(artist.name),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onOpenArtist!(artist);
                  },
                ),
          ],
        ),
      ),
    );
    if (MediaQuery.sizeOf(context).width >= 840) {
      await showDialog<void>(
        context: context,
        builder: (context) =>
            Dialog(child: SizedBox(width: 420, child: actions(context))),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: actions,
      );
    }
  }
}

class _RecentMessage extends StatelessWidget {
  const _RecentMessage({
    required this.icon,
    required this.title,
    this.detail,
    this.loading = false,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? detail;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator()
            else
              Icon(
                icon,
                size: 44,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail!, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    ),
  );
}
