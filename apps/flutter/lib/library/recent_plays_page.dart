import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutterustmusic/fura_toast.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/paged_tracks_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_scroll_prefetch.dart';
import 'package:flutterustmusic/library/playlist_track_search_index.dart';
import 'package:flutterustmusic/library/recent_plays_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class RecentPlaysPage extends StatefulWidget {
  const RecentPlaysPage({
    required this.gateway,
    required this.playback,
    required this.onSignInAgain,
    required this.active,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.onHeaderCollapsedChanged,
    this.collapsedHeaderActions,
    this.compactCollapsedTopBarInShell = false,
    this.collapseSuppressed = false,
    super.key,
  });

  /// Null means cloud history is not connected, never a successful empty result.
  final RecentPlaysGateway? gateway;
  final QueuePlaybackController playback;
  final VoidCallback onSignInAgain;
  final bool active;
  final ValueChanged<bool>? onHeaderCollapsedChanged;
  final Widget? collapsedHeaderActions;

  /// The compact Shell owns the collapsed title and account actions while the
  /// page keeps ownership of search, count, Play and Refresh below it.
  final bool compactCollapsedTopBarInShell;
  final bool collapseSuppressed;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<RecentPlaysPage> createState() => _RecentPlaysPageState();
}

class _RecentPlaysPageState extends State<RecentPlaysPage> {
  PagedTracksController? _controller;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  bool _headerCollapsed = false;
  bool _userReturningToHeader = false;
  bool? _pendingHeaderCollapsed;
  bool _headerUpdateScheduled = false;
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
      _controller?.cancelSearchScan();
      _controller?.cancelLoadAll();
    } else if (!oldWidget.active) {
      _continueSearch();
    }
  }

  bool _handleCollectionScroll(
    ScrollNotification notification, {
    required bool canCollapse,
  }) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (!widget.active) return false;
    if (!canCollapse) {
      _scheduleHeaderCollapsed(false);
      return false;
    }
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        _userReturningToHeader = true;
      } else if (notification.direction == ScrollDirection.reverse) {
        _userReturningToHeader = false;
      }
    }
    final effectiveCollapsed = _pendingHeaderCollapsed ?? _headerCollapsed;
    final returnedToHeader =
        effectiveCollapsed &&
        _userReturningToHeader &&
        notification.metrics.pixels <= 4;
    if (returnedToHeader) _userReturningToHeader = false;
    final collapse = effectiveCollapsed
        ? !returnedToHeader
        : notification.metrics.pixels > 56;
    _scheduleHeaderCollapsed(collapse);
    return false;
  }

  void _scheduleHeaderCollapsed(bool collapsed) {
    _pendingHeaderCollapsed = collapsed;
    if (_headerUpdateScheduled) return;
    _headerUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _headerUpdateScheduled = false;
      if (!mounted) return;
      final pending = _pendingHeaderCollapsed;
      _pendingHeaderCollapsed = null;
      if (pending != null) _setHeaderCollapsed(pending);
    });
  }

  void _setHeaderCollapsed(bool collapsed) {
    _pendingHeaderCollapsed = null;
    if (collapsed == _headerCollapsed) return;
    if (!collapsed) _userReturningToHeader = false;
    setState(() => _headerCollapsed = collapsed);
    widget.onHeaderCollapsedChanged?.call(collapsed);
  }

  void _updateSearch() {
    final query = normalizePlaylistSearchText(_search.text);
    if (_query == query) return;
    final previousQuery = _query;
    setState(() => _query = query);
    if (query.isEmpty) {
      _controller?.cancelSearchScan();
      _controller?.cancelLoadAll();
    } else {
      _controller?.cancelPrefetch();
      if (previousQuery.isEmpty ||
          _controller?.searchScanStage == CollectionSearchScanStage.idle) {
        _continueSearch();
      }
    }
  }

  void _continueSearch() {
    final controller = _controller;
    if (!mounted ||
        !widget.active ||
        _query.isEmpty ||
        controller == null ||
        controller.isRefreshing ||
        controller.searchScanStage != CollectionSearchScanStage.idle ||
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
        unawaited(_requestSearchCoverage());
      }
    });
  }

  Future<void> _requestSearchCoverage({bool retryInterrupted = false}) {
    final controller = _controller;
    if (controller == null || _query.isEmpty) return Future.value();
    return controller.requestSearchCoverage(retryInterrupted: retryInterrupted);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: AnimatedBuilder(
      animation: Listenable.merge([
        ?_controller,
        widget.playback.currentTrackListenable,
      ]),
      builder: (context, _) {
        final controller = _controller;
        final loaded = controller?.tracks ?? const <PlaylistTrackSummary>[];
        if (!identical(loaded, _indexedTracks)) {
          _index.update(
            loaded,
            collectionGeneration: controller?.snapshotGeneration,
          );
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
            final l10n = context.l10n;
            final desktop = constraints.maxWidth >= 820;
            final padding = desktop ? 28.0 : 16.0;
            final theme = Theme.of(context);
            final canCollapse = constraints.maxHeight >= 480;
            final header = _buildHeader(
              context: context,
              constraints: constraints,
              controller: controller,
              tracks: tracks,
              hasSnapshot: hasSnapshot,
              desktop: desktop,
              padding: padding,
              collapsed:
                  canCollapse && _headerCollapsed && !widget.collapseSuppressed,
            );
            final scrollView = CustomScrollView(
              key: const PageStorageKey('recent-plays-tracks'),
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padding, 20, padding, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.recentTitle,
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
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
                                    ? l10n.recentCloudNotConnectedShort
                                    : l10n.recentCloudSubtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Let controls scroll on short windows / with the soft keyboard.
                if (canCollapse)
                  PinnedHeaderSliver(child: header)
                else
                  SliverToBoxAdapter(child: header),
                _body(controller, tracks, desktop, padding),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: MusicTrackLocatorOverlay(
                    controller: _scroll,
                    currentIndex: hasSnapshot
                        ? musicTrackIndexOf(
                            tracks,
                            widget.playback.currentTrackListenable.value,
                          )
                        : null,
                    desktop: desktop,
                    leadingExtent: desktop ? 210 : 250,
                    itemExtent: musicTrackRowExtent(
                      desktop: desktop,
                      includesSeparator: false,
                    ),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) => _handleCollectionScroll(
                        notification,
                        canCollapse: canCollapse,
                      ),
                      child: controller == null
                          ? scrollView
                          : PlaylistScrollPrefetch(
                              controller: controller,
                              enabled: widget.active && _query.isEmpty,
                              child: scrollView,
                            ),
                    ),
                  ),
                ),
                if (hasSnapshot && desktop)
                  Padding(
                    padding: EdgeInsets.fromLTRB(padding, 8, padding, 12),
                    child: Text(
                      _processedStatus(
                        l10n,
                        controller!,
                        result.approximateMatchCount,
                      ),
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
    ),
  );

  Widget _buildHeader({
    required BuildContext context,
    required BoxConstraints constraints,
    required PagedTracksController? controller,
    required List<PlaylistTrackSummary> tracks,
    required bool hasSnapshot,
    required bool desktop,
    required double padding,
    required bool collapsed,
  }) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final countLabel = hasSnapshot
        ? controller!.totalIsExact
              ? l10n.recentSongsTab(controller.total)
              : l10n.recentSongsTabApproximate(controller.total)
        : l10n.recentSongsTabWithoutCount;
    final collapsedCountLabel = hasSnapshot && !controller!.totalIsExact
        ? l10n.recentSongsTabApproximate(controller.total)
        : countLabel;
    final processedLabel = hasSnapshot
        ? _processedStatus(l10n, controller!, 0)
        : null;
    final play = tracks.isEmpty ? null : () => _playRecent(tracks, 0);
    final playLabel = _query.isEmpty
        ? l10n.likedPlayAll
        : (controller?.hasMore ?? false)
        ? l10n.likedPlayFilteredSoFar(tracks.length)
        : l10n.recentPlayFiltered(tracks.length);
    final refresh = controller == null || controller.isLoading
        ? null
        : controller.refresh;
    return Material(
      key: const ValueKey('recent-plays-pinned-controls'),
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            key: const ValueKey('recent-plays-header-transition'),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
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
                    ? 'recent-plays-collapsed-header'
                    : 'recent-plays-expanded-controls',
              ),
              padding: EdgeInsets.fromLTRB(
                collapsed ? 12 : padding,
                collapsed && desktop
                    ? 4
                    : collapsed
                    ? 6
                    : 12,
                collapsed ? 12 : padding,
                collapsed && desktop
                    ? 4
                    : collapsed
                    ? 6
                    : 12,
              ),
              child: collapsed
                  ? _collapsedHeader(
                      context,
                      desktop: desktop,
                      countLabel: collapsedCountLabel,
                      hasSnapshot: hasSnapshot,
                      onPlay: play,
                      playLabel: playLabel,
                      onRefresh: refresh,
                    )
                  : _expandedControls(
                      context,
                      availableWidth: constraints.maxWidth,
                      desktop: desktop,
                      padding: padding,
                      countLabel: countLabel,
                      processedLabel: processedLabel,
                      hasSnapshot: hasSnapshot,
                      onPlay: play,
                      playLabel: playLabel,
                      onRefresh: refresh,
                    ),
            ),
          ),
          if (controller?.isRefreshing ?? false)
            const LinearProgressIndicator(
              key: ValueKey('recent-plays-refresh-progress'),
            ),
          if (controller?.refreshFailure != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.recentRefreshSnapshotFailure)),
                  TextButton(
                    onPressed: controller!.retryRefresh,
                    child: Text(l10n.commonRetry),
                  ),
                ],
              ),
            ),
          if (desktop && hasSnapshot)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: MusicTrackTableHeader(
                titleLabel: l10n.tableTitle,
                artistLabel: l10n.tableArtist,
                albumLabel: l10n.tableAlbum,
                durationLabel: l10n.tableDuration,
              ),
            ),
        ],
      ),
    );
  }

  Widget _expandedControls(
    BuildContext context, {
    required double availableWidth,
    required bool desktop,
    required double padding,
    required String countLabel,
    required String? processedLabel,
    required bool hasSnapshot,
    required VoidCallback? onPlay,
    required String playLabel,
    required VoidCallback? onRefresh,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              countLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            if (!desktop && processedLabel != null) ...[
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  processedLabel,
                  maxLines: 2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _recentPlayButton(onPressed: onPlay, label: playLabel),
            _recentRefreshButton(onPressed: onRefresh),
            SizedBox(
              width: desktop ? 300 : availableWidth - 2 * padding,
              child: _recentSearch(enabled: hasSnapshot),
            ),
          ],
        ),
      ],
    );
  }

  Widget _collapsedHeader(
    BuildContext context, {
    required bool desktop,
    required String countLabel,
    required bool hasSnapshot,
    required VoidCallback? onPlay,
    required String playLabel,
    required VoidCallback? onRefresh,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      // AnimatedSwitcher keeps its outgoing header alive while the window is
      // resized. Re-evaluate the retained child's *current* constraints so a
      // former desktop row cannot be laid out inside a newly narrow surface.
      // The 24 px adjustment is the collapsed header's two 12 px insets.
      final useSingleRow = desktop && constraints.maxWidth >= 820 - 24;
      if (useSingleRow) {
        return SizedBox(
          height: 48,
          child: Row(
            key: const ValueKey('recent-plays-collapsed-row'),
            children: [
              _collapsedTitle(context),
              const SizedBox(width: 16),
              _collapsedCount(context, countLabel),
              const Spacer(),
              _recentPlayButton(
                onPressed: onPlay,
                label: playLabel,
                compact: true,
              ),
              const SizedBox(width: 8),
              _recentRefreshButton(onPressed: onRefresh, compact: true),
              const SizedBox(width: 16),
              SizedBox(width: 220, child: _recentSearch(enabled: hasSnapshot)),
              if (widget.collapsedHeaderActions case final actions?) ...[
                const SizedBox(width: 12),
                actions,
              ],
            ],
          ),
        );
      }
      return Column(
        key: const ValueKey('recent-plays-collapsed-column'),
        children: [
          if (!widget.compactCollapsedTopBarInShell) ...[
            Row(
              children: [
                Flexible(child: _collapsedTitle(context)),
                const Spacer(),
                if (widget.collapsedHeaderActions case final actions?) ...[
                  const SizedBox(width: 12),
                  actions,
                ],
              ],
            ),
            const SizedBox(height: 8),
          ],
          _recentSearch(enabled: hasSnapshot),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                _collapsedCount(context, countLabel),
                const Spacer(),
                _recentPlayButton(
                  onPressed: onPlay,
                  label: playLabel,
                  compact: true,
                ),
                const SizedBox(width: 8),
                _recentRefreshButton(onPressed: onRefresh, compact: true),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _collapsedTitle(BuildContext context) => Semantics(
    header: true,
    child: Text(
      context.l10n.recentTitle,
      key: const ValueKey('recent-plays-collapsed-title'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _collapsedCount(BuildContext context, String label) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(
      label,
      key: const ValueKey('recent-plays-count-tab'),
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  Widget _recentPlayButton({
    required VoidCallback? onPressed,
    required String label,
    bool compact = false,
  }) {
    return compact
        ? IconButton.filled(
            key: const ValueKey('recent-plays-play'),
            tooltip: label,
            onPressed: onPressed,
            icon: const Icon(Icons.play_arrow_rounded),
          )
        : FilledButton.icon(
            key: const ValueKey('recent-plays-play'),
            onPressed: onPressed,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(label),
          );
  }

  Widget _recentRefreshButton({
    required VoidCallback? onPressed,
    bool compact = false,
  }) {
    final l10n = context.l10n;
    return compact
        ? IconButton.filledTonal(
            key: const ValueKey('recent-plays-refresh'),
            tooltip: l10n.recentRefreshTooltip,
            onPressed: onPressed,
            icon: const Icon(Icons.sync_rounded),
          )
        : FilledButton.tonalIcon(
            key: const ValueKey('recent-plays-refresh'),
            onPressed: onPressed,
            icon: const Icon(Icons.sync_rounded),
            label: Text(l10n.commonRefresh),
          );
  }

  Widget _recentSearch({required bool enabled}) => TextField(
    key: const ValueKey('recent-plays-search'),
    controller: _search,
    enabled: enabled,
    decoration: MusicMaterialTheme.searchDecoration(
      context,
      hintText: context.l10n.recentSearchHint,
      dense: true,
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              tooltip: context.l10n.commonClearSearch,
              onPressed: _search.clear,
              icon: const Icon(Icons.close_rounded),
            ),
    ),
  );

  String _processedStatus(
    AppLocalizations l10n,
    PagedTracksController controller,
    int approximateMatchCount,
  ) => l10n.recentProcessedStatus(
    _query.isEmpty ? l10n.recentLoadedAction : l10n.recentSearchedAction,
    approximateMatchCount > 0
        ? l10n.recentApproximatePart(approximateMatchCount)
        : '',
    controller.omittedTrackCount > 0
        ? l10n.recentOmittedPart(controller.omittedTrackCount)
        : '',
    controller.processedCount,
    controller.totalIsExact ? l10n.recentTotalPart(controller.total) : '',
  );

  Widget _body(
    PagedTracksController? controller,
    List<PlaylistTrackSummary> tracks,
    bool desktop,
    double padding,
  ) {
    if (controller == null) {
      return _messageSliver(
        _RecentMessage(
          icon: Icons.cloud_off_outlined,
          title: context.l10n.recentUnavailableTitle,
          detail: context.l10n.recentUnavailableDetail,
        ),
      );
    }
    switch (controller.stage) {
      case PlaylistDetailStage.loading:
        return _messageSliver(
          _RecentMessage(
            icon: Icons.history_rounded,
            title: context.l10n.recentLoadingTitle,
            loading: true,
          ),
        );
      case PlaylistDetailStage.authenticationRequired:
      case PlaylistDetailStage.credentialRejected:
        return _messageSliver(
          _RecentMessage(
            icon: Icons.login_rounded,
            title: context.l10n.recentSignInTitle,
            detail: context.l10n.recentSignInDetail,
            action: FilledButton(
              onPressed: widget.onSignInAgain,
              child: Text(context.l10n.authSignInAgain),
            ),
          ),
        );
      case PlaylistDetailStage.error:
        return _messageSliver(
          _RecentMessage(
            icon: Icons.cloud_off_outlined,
            title: context.l10n.recentUnavailableTemporaryTitle,
            detail: context.l10n.recentTryLater,
            action: controller.canRetry
                ? FilledButton.tonal(
                    onPressed: controller.retry,
                    child: Text(context.l10n.commonRetry),
                  )
                : null,
          ),
        );
      case PlaylistDetailStage.empty:
        return _messageSliver(
          _RecentMessage(
            icon: Icons.history_rounded,
            title: context.l10n.recentEmptyTitle,
            detail: context.l10n.recentEmptyDetail,
          ),
        );
      case PlaylistDetailStage.content:
        final current = widget.playback.currentTrackListenable.value;
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding,
            0,
            padding,
            24 +
                MusicViewportClearance.bottomOf(
                  context,
                  fallbackPlayerPresent: current != null,
                ),
          ),
          sliver: SliverList.builder(
            itemCount: tracks.length + 1,
            itemBuilder: (context, index) {
              if (index == tracks.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      if (_query.isNotEmpty && tracks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            controller.isScanningSearch ||
                                    (controller.hasMore &&
                                        controller.appendFailure == null &&
                                        controller.searchScanStage ==
                                            CollectionSearchScanStage.idle)
                                ? context.l10n.recentSearchingAll
                                : controller.appendFailure != null
                                ? context.l10n.recentSearchInterrupted
                                : controller.hasMore
                                ? context.l10n.recentSearchPaused(
                                    controller.processedCount,
                                  )
                                : context.l10n.recentNoMatch,
                          ),
                        ),
                      if (controller.isLoadingMore ||
                          controller.isScanningSearch)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                        )
                      else if (controller.appendFailure != null) ...[
                        Text(context.l10n.recentAppendFailure),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          onPressed: controller.canRetryMore
                              ? () => _query.isEmpty
                                    ? controller.retryMore()
                                    : unawaited(
                                        _requestSearchCoverage(
                                          retryInterrupted: true,
                                        ),
                                      )
                              : null,
                          child: Text(context.l10n.recentContinueLoading),
                        ),
                      ] else if (controller.hasMore)
                        FilledButton.tonal(
                          onPressed: _query.isEmpty
                              ? controller.loadMore
                              : _requestSearchCoverage,
                          child: Text(
                            _query.isEmpty
                                ? context.l10n.commonLoadMore
                                : context.l10n.likedContinueSearch,
                          ),
                        ),
                    ],
                  ),
                );
              }
              final track = tracks[index];
              final selected =
                  current?.providerId == track.providerId &&
                  current?.opaqueId == track.opaqueId;
              final artists = track.artistNames.isEmpty
                  ? context.l10n.trackUnknownArtist
                  : track.artistNames.join(' / ');
              return MusicTrackRowSurface(
                key: ValueKey(
                  'recent-track-state-${track.providerId}-${track.opaqueId}',
                ),
                itemKey: ValueKey('recent-plays-track-$index'),
                desktop: desktop,
                current: selected,
                semanticLabel: context.l10n.commonTrackSemantics(
                  artists,
                  track.title,
                ),
                onTap: () => _playRecent(tracks, index),
                onContextMenuRequested: (position) => unawaited(
                  _showTrackActions(
                    tracks: tracks,
                    index: index,
                    track: track,
                    desktop: desktop,
                    anchorPosition: position,
                  ),
                ),
                contentBuilder: (context, active, hovered) =>
                    MusicTrackRowContent(
                      index: index + 1,
                      track: track,
                      desktop: desktop,
                      current: selected,
                      active: active,
                      showInlineQueueAction: hovered,
                      artistNames: artists,
                      onPlay: () => _playRecent(tracks, index),
                      onAddToQueue: () => _queueRecent(track),
                      onOpenAlbum:
                          track.album == null || widget.onOpenAlbum == null
                          ? null
                          : () => widget.onOpenAlbum!(track.album!),
                      onOpenArtist:
                          widget.onOpenArtist == null || track.artists.isEmpty
                          ? null
                          : () => _openRecentArtist(track),
                      onMore: () => unawaited(
                        _showTrackActions(
                          tracks: tracks,
                          index: index,
                          track: track,
                          desktop: desktop,
                          anchorPosition: null,
                        ),
                      ),
                      onMoreAt: (position) => unawaited(
                        _showTrackActions(
                          tracks: tracks,
                          index: index,
                          track: track,
                          desktop: desktop,
                          anchorPosition: position,
                        ),
                      ),
                      addToQueueTooltip: context.l10n.recentAddToQueue,
                      moreTooltip: context.l10n.commonMoreActions,
                      playTooltip: context.l10n.commonPlayFromHere,
                      albumTooltip: context.l10n.commonOpenAlbum,
                      artistTooltip: track.artists.length > 1
                          ? context.l10n.commonChooseArtist
                          : context.l10n.commonOpenArtist,
                    ),
              );
            },
          ),
        );
    }
  }

  void _playRecent(List<PlaylistTrackSummary> tracks, int index) {
    final controller = _controller;
    if (_query.isEmpty && controller != null && tracks.isNotEmpty) {
      final providerId = tracks.first.providerId;
      unawaited(
        widget.playback.replaceAndPlayCollection(
          controller.collectionPlaybackSource(
            sourceId: 'recent:$providerId',
            providerId: providerId,
          ),
          index,
        ),
      );
      return;
    }
    unawaited(widget.playback.replaceAndPlay(tracks, index));
  }

  void _queueRecent(PlaylistTrackSummary track) {
    final playbackStart = widget.playback.push(track);
    if (!mounted) {
      unawaited(playbackStart);
      return;
    }
    final message = widget.playback.failure == null
        ? context.l10n.queueAddedMessage
        : context.l10n.queueUpdateFailureMessage;
    showFuraToast(context, message);
    unawaited(playbackStart);
  }

  void _openRecentArtist(PlaylistTrackSummary track) {
    unawaited(
      openMusicTrackArtists(
        context: context,
        artists: track.artists,
        onSelected: widget.onOpenArtist,
        title: context.l10n.trackChooseArtistTitle,
        detail: context.l10n.recentChooseArtistDetail,
        cancelLabel: context.l10n.commonCancel,
        itemKeyPrefix: 'recent-track-artist',
      ),
    );
  }

  Widget _messageSliver(Widget message) =>
      SliverFillRemaining(hasScrollBody: false, child: message);

  Future<void> _showTrackActions({
    required List<PlaylistTrackSummary> tracks,
    required int index,
    required PlaylistTrackSummary track,
    required bool desktop,
    required Offset? anchorPosition,
  }) async {
    final likeAction = await resolveMusicTrackLikeAction(context, track);
    if (!mounted) return;
    final canAddToPlaylist = canAddMusicTrackToPlaylist(context);
    final canOpenAlbum = track.album != null && widget.onOpenAlbum != null;
    final canOpenArtist =
        widget.onOpenArtist != null && track.artists.isNotEmpty;
    final action = await showAdaptiveMusicContextMenu<MusicTrackAction>(
      context: context,
      desktop: desktop,
      anchorPosition: anchorPosition,
      headerTitle: desktop ? null : track.title,
      entries: [
        MusicTrackMenuEntry(
          value: MusicTrackAction.play,
          icon: Icons.play_arrow_rounded,
          label: context.l10n.commonPlayFromHere,
        ),
        if (likeAction != null)
          MusicTrackMenuEntry(
            value: likeAction,
            icon: likeAction == MusicTrackAction.like
                ? Icons.favorite_border_rounded
                : Icons.favorite_rounded,
            label: likeAction == MusicTrackAction.like
                ? context.l10n.libraryLikeTrack
                : context.l10n.libraryUnlikeTrack,
          ),
        MusicTrackMenuEntry(
          value: MusicTrackAction.addToQueue,
          icon: Icons.queue_music_rounded,
          label: context.l10n.recentAddToQueue,
        ),
        if (canAddToPlaylist)
          MusicTrackMenuEntry(
            value: MusicTrackAction.addToPlaylist,
            icon: Icons.playlist_add_rounded,
            label: context.l10n.libraryAddTrackToPlaylist,
          ),
        if (canOpenAlbum)
          MusicTrackMenuEntry(
            value: MusicTrackAction.openAlbum,
            icon: Icons.album_rounded,
            label: context.l10n.commonOpenAlbum,
          ),
        if (canOpenArtist)
          MusicTrackMenuEntry(
            value: MusicTrackAction.openArtist,
            icon: Icons.person_rounded,
            label: track.artists.length > 1
                ? context.l10n.commonChooseArtist
                : context.l10n.commonOpenArtist,
          ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case MusicTrackAction.play:
        _playRecent(tracks, index);
      case MusicTrackAction.addToQueue:
        _queueRecent(track);
      case MusicTrackAction.addToPlaylist:
        await showAddTrackToPlaylist(context: context, track: track);
      case MusicTrackAction.openAlbum:
        widget.onOpenAlbum!(track.album!);
      case MusicTrackAction.openArtist:
        _openRecentArtist(track);
      case MusicTrackAction.like || MusicTrackAction.unlike:
        await runMusicTrackLikeAction(context, track, action!);
      case null:
        return;
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
  Widget build(BuildContext context) {
    if (loading) {
      return MusicLoadingPanel(label: title, detail: detail);
    }
    return MusicContentStatePanel(
      icon: icon,
      title: title,
      detail: detail,
      liveRegion: action != null,
      action: action,
    );
  }
}
