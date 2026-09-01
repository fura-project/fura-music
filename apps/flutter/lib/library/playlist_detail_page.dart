import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_refresh_failure_banner.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    required this.playlist,
    required this.gateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onSignInAgain,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.embedded = false,
    super.key,
  });

  final UserPlaylistSummary playlist;
  final PlaylistDetailGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;
  final bool embedded;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  late final PlaylistDetailController _controller;
  late final Listenable _pageListenable;

  @override
  void initState() {
    super.initState();
    _controller = PlaylistDetailController(widget.playlist, widget.gateway);
    _pageListenable = Listenable.merge([
      _controller,
      widget.queuePlaybackController,
    ]);
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
      key: const ValueKey('playlist-detail-toolbar'),
      leading: IconButton(
        key: const ValueKey('playlist-detail-back'),
        tooltip: 'Back to playlists',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: Text(widget.playlist.title),
      actions: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => IconButton(
            tooltip: _controller.isRefreshing
                ? 'Refreshing playlist'
                : 'Refresh playlist',
            onPressed: _controller.isLoading ? null : _controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
    final body = SafeArea(
      child: AnimatedBuilder(
        animation: _pageListenable,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;
            return Column(
              children: [
                _PlaylistHeader(
                  playlist: widget.playlist,
                  trackCount:
                      _controller.stage == PlaylistDetailStage.content ||
                          _controller.stage == PlaylistDetailStage.empty
                      ? _controller.total
                      : widget.playlist.trackCount,
                  desktop: desktop,
                ),
                if (_controller.isRefreshing)
                  const LinearProgressIndicator(
                    key: ValueKey('playlist-detail-refresh-progress'),
                  ),
                if (_controller.refreshFailure case final failure?)
                  LibraryRefreshFailureBanner(
                    key: const ValueKey('playlist-detail-refresh-failure'),
                    message: _refreshFailureCopy(failure),
                    canRetry: _controller.canRetryRefresh,
                    onRetry: _controller.retryRefresh,
                    onDismiss: _controller.dismissRefreshFailure,
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: _body(desktop),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (widget.embedded) {
      return Column(
        key: const ValueKey('embedded-playlist-detail'),
        children: [
          SizedBox(height: kToolbarHeight, child: toolbar),
          Expanded(child: body),
        ],
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
    PlaylistDetailStage.loading => const Center(
      key: ValueKey('playlist-detail-loading'),
      child: CircularProgressIndicator(),
    ),
    PlaylistDetailStage.content => _TrackCollection(
      key: const ValueKey('playlist-detail-content'),
      tracks: _controller.tracks,
      total: _controller.total,
      hasMore: _controller.hasMore,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
      onTrackSelected: (index) => unawaited(
        widget.queuePlaybackController.replaceAndPlay(
          _controller.tracks,
          index,
        ),
      ),
      onTrackQueued: _addToQueue,
      onOpenAlbum: widget.onOpenAlbum,
      onOpenArtist: widget.onOpenArtist,
      desktop: desktop,
      current: widget.queuePlaybackController.current,
    ),
    PlaylistDetailStage.empty => const _DetailMessage(
      key: ValueKey('playlist-detail-empty'),
      icon: Icons.music_off_outlined,
      title: 'This playlist is empty',
      detail: 'Tracks added in QQ Music will appear here.',
    ),
    PlaylistDetailStage.error => _DetailFailure(
      key: const ValueKey('playlist-detail-error'),
      failure: _controller.failure,
      canRetry: _controller.canRetry,
      showSignInAgain: false,
      onRetry: _controller.retry,
      onSignInAgain: widget.onSignInAgain,
    ),
    PlaylistDetailStage.authenticationRequired ||
    PlaylistDetailStage.credentialRejected => _DetailFailure(
      key: const ValueKey('playlist-detail-authentication-error'),
      failure: _controller.failure,
      canRetry: false,
      showSignInAgain: true,
      onRetry: _controller.retry,
      onSignInAgain: widget.onSignInAgain,
    ),
  };

  void _addToQueue(PlaylistTrackSummary track) {
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

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({
    required this.playlist,
    required this.trackCount,
    required this.desktop,
  });

  final UserPlaylistSummary playlist;
  final int? trackCount;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artworkSize = desktop ? 156.0 : 92.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 48 : 20,
        desktop ? 24 : 12,
        desktop ? 48 : 20,
        desktop ? 28 : 18,
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: artworkSize,
            child: _Artwork(uri: playlist.artworkUri, playlist: true),
          ),
          SizedBox(width: desktop ? 28 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PLAYLIST',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  playlist.title,
                  maxLines: desktop ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (desktop
                              ? theme.textTheme.headlineLarge
                              : theme.textTheme.titleLarge)
                          ?.copyWith(fontWeight: FontWeight.w700, height: 1.08),
                ),
                const SizedBox(height: 10),
                Text(
                  trackCount == null
                      ? 'QQ Music'
                      : '$trackCount tracks · QQ Music',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackCollection extends StatefulWidget {
  const _TrackCollection({
    required this.tracks,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onTrackSelected,
    required this.onTrackQueued,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required this.desktop,
    required this.current,
    super.key,
  });

  final List<PlaylistTrackSummary> tracks;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;
  final UserLibraryFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<int> onTrackSelected;
  final ValueChanged<PlaylistTrackSummary> onTrackQueued;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;
  final bool desktop;
  final PlaylistTrackSummary? current;

  @override
  State<_TrackCollection> createState() => _TrackCollectionState();
}

class _TrackCollectionState extends State<_TrackCollection> {
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
    final horizontal = widget.desktop ? 24.0 : 10.0;
    return Column(
      children: [
        if (widget.desktop)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: const MusicTrackTableHeader(
              key: ValueKey('playlist-detail-table-header'),
              titleLabel: 'Title',
              artistLabel: 'Artist',
              albumLabel: 'Album',
              durationLabel: 'Duration',
            ),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _clearHoverOnScroll,
            child: ListView.separated(
              key: const PageStorageKey<String>('playlist-detail-track-list'),
              padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 20),
              itemCount: widget.tracks.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 1),
              itemBuilder: (context, index) {
                if (index == widget.tracks.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Text(
                          'Showing ${widget.tracks.length} of ${widget.total} tracks',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        if (widget.isLoadingMore)
                          const SizedBox.square(
                            dimension: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        else if (widget.appendFailure != null)
                          FilledButton.tonal(
                            onPressed: widget.onRetryMore,
                            child: const Text('Try loading more again'),
                          )
                        else if (widget.hasMore)
                          FilledButton.tonal(
                            onPressed: widget.onLoadMore,
                            child: const Text('Load more'),
                          ),
                        if (!widget.hasMore &&
                            !widget.isLoadingMore &&
                            widget.appendFailure == null)
                          Text(
                            'End of playlist',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  );
                }
                final track = widget.tracks[index];
                final identity = (track.providerId, track.opaqueId);
                return _TrackRow(
                  index: index + 1,
                  track: track,
                  desktop: widget.desktop,
                  current: _sameTrack(widget.current, track),
                  hovered: _hoveredTrack == identity,
                  onHoverChanged: (hovered) => _setHovered(track, hovered),
                  onTap: () => widget.onTrackSelected(index),
                  onAddToQueue: () => widget.onTrackQueued(track),
                  onOpenAlbum: widget.onOpenAlbum == null || track.album == null
                      ? null
                      : () => widget.onOpenAlbum!(track.album!),
                  onOpenArtist: widget.onOpenArtist,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

bool _sameTrack(PlaylistTrackSummary? left, PlaylistTrackSummary right) =>
    left != null &&
    left.providerId == right.providerId &&
    left.opaqueId == right.opaqueId;

class _TrackRow extends StatefulWidget {
  const _TrackRow({
    required this.index,
    required this.track,
    required this.desktop,
    required this.current,
    required this.hovered,
    required this.onHoverChanged,
    required this.onTap,
    required this.onAddToQueue,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

  final int index;
  final PlaylistTrackSummary track;
  final bool desktop;
  final bool current;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;
  final VoidCallback onAddToQueue;
  final VoidCallback? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
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
        ? 'Unknown artist'
        : widget.track.artistNames.join(' · ');
    final title = widget.track.subtitle == null
        ? widget.track.title
        : '${widget.track.title} · ${widget.track.subtitle}';
    final active = widget.hovered || _focusNode.hasFocus;
    final background = widget.current
        ? theme.colorScheme.surfaceContainerHigh
        : active
        ? theme.colorScheme.surfaceContainerLow
        : Colors.transparent;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.contextMenu): () =>
            _showKeyboardActions(context),
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
            _showKeyboardActions(context),
      },
      child: Semantics(
        label: '$title, $artists',
        container: true,
        button: true,
        selected: widget.current,
        excludeSemantics: true,
        onTap: widget.onTap,
        onLongPress: widget.desktop
            ? null
            : () => unawaited(_showMobileActions(context)),
        child: MouseRegion(
          onEnter: (_) => widget.onHoverChanged(true),
          onExit: (_) => widget.onHoverChanged(false),
          child: InkWell(
            key: ValueKey('playlist-track-row-${widget.index}'),
            focusNode: _focusNode,
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              _focusNode.requestFocus();
              widget.onTap();
            },
            onSecondaryTapDown: widget.desktop
                ? (details) {
                    _focusNode.requestFocus();
                    unawaited(
                      _showDesktopActions(context, details.globalPosition),
                    );
                  }
                : null,
            onLongPress: widget.desktop
                ? null
                : () => unawaited(_showMobileActions(context)),
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
              child: MusicTrackRowContent(
                index: widget.index,
                track: widget.track,
                title: title,
                desktop: widget.desktop,
                current: widget.current,
                active: active,
                artistNames: artists,
                onAddToQueue: widget.onAddToQueue,
                onMore: () => unawaited(_showMobileActions(context)),
                showInlineQueueAction: widget.hovered,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showKeyboardActions(BuildContext context) {
    if (!widget.desktop) {
      unawaited(_showMobileActions(context));
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final position = box.localToGlobal(box.size.center(Offset.zero));
    unawaited(_showDesktopActions(context, position));
  }

  Future<void> _showDesktopActions(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final action = await showMenu<_TrackAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      ),
      items: [
        const PopupMenuItem(
          value: _TrackAction.playFromHere,
          child: ListTile(
            leading: Icon(Icons.play_arrow_rounded),
            title: Text('Play from here'),
          ),
        ),
        const PopupMenuItem(
          value: _TrackAction.addToQueue,
          child: ListTile(
            leading: Icon(Icons.playlist_add_rounded),
            title: Text('Add to queue'),
          ),
        ),
        if (widget.onOpenAlbum != null)
          const PopupMenuItem(
            key: ValueKey('playlist-track-open-album-action'),
            value: _TrackAction.openAlbum,
            child: ListTile(
              leading: Icon(Icons.album_rounded),
              title: Text('Open album'),
            ),
          ),
        if (widget.onOpenArtist != null && widget.track.artists.isNotEmpty)
          const PopupMenuItem(
            key: ValueKey('playlist-track-open-artist-action'),
            value: _TrackAction.openArtist,
            child: ListTile(
              leading: Icon(Icons.person_rounded),
              title: Text('Open artist'),
            ),
          ),
      ],
    );
    _runAction(action);
  }

  Future<void> _showMobileActions(BuildContext context) async {
    final action = await showModalBottomSheet<_TrackAction>(
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
              onTap: () => Navigator.pop(context, _TrackAction.playFromHere),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Add to queue'),
              onTap: () => Navigator.pop(context, _TrackAction.addToQueue),
            ),
            if (widget.onOpenAlbum != null)
              ListTile(
                key: const ValueKey('playlist-track-open-album-action'),
                leading: const Icon(Icons.album_rounded),
                title: const Text('Open album'),
                onTap: () => Navigator.pop(context, _TrackAction.openAlbum),
              ),
            if (widget.onOpenArtist != null && widget.track.artists.isNotEmpty)
              ListTile(
                key: const ValueKey('playlist-track-open-artist-action'),
                leading: const Icon(Icons.person_rounded),
                title: const Text('Open artist'),
                onTap: () => Navigator.pop(context, _TrackAction.openArtist),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    _runAction(action);
  }

  void _runAction(_TrackAction? action) {
    switch (action) {
      case _TrackAction.playFromHere:
        widget.onTap();
        return;
      case _TrackAction.addToQueue:
        widget.onAddToQueue();
        return;
      case _TrackAction.openAlbum:
        widget.onOpenAlbum?.call();
        return;
      case _TrackAction.openArtist:
        unawaited(_openArtist());
        return;
      case null:
        return;
    }
  }

  Future<void> _openArtist() async {
    final onOpenArtist = widget.onOpenArtist;
    final artists = widget.track.artists;
    if (onOpenArtist == null || artists.isEmpty) return;
    if (artists.length == 1) {
      onOpenArtist(artists.single);
      return;
    }
    final compact = MediaQuery.sizeOf(context).width < 600;
    final selected = compact
        ? await showModalBottomSheet<ArtistSummary>(
            context: context,
            showDragHandle: true,
            builder: (context) =>
                _ArtistSelection(artists: artists, compact: true),
          )
        : await showDialog<ArtistSummary>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Choose an Artist'),
              content: _ArtistSelection(artists: artists, compact: false),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
    if (!mounted || selected == null) return;
    onOpenArtist(selected);
  }
}

enum _TrackAction { playFromHere, addToQueue, openAlbum, openArtist }

class _ArtistSelection extends StatelessWidget {
  const _ArtistSelection({required this.artists, required this.compact});

  final List<ArtistSummary> artists;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      shrinkWrap: compact,
      padding: EdgeInsets.fromLTRB(8, compact ? 0 : 4, 8, compact ? 16 : 4),
      children: [
        if (compact)
          const ListTile(
            title: Text('Choose an Artist'),
            subtitle: Text('This Track credits more than one Artist.'),
          ),
        for (var index = 0; index < artists.length; index++)
          ListTile(
            key: ValueKey('playlist-track-artist-$index'),
            leading: const Icon(Icons.person_rounded),
            title: Text(artists[index].name),
            onTap: () => Navigator.pop(context, artists[index]),
          ),
      ],
    );
    return SafeArea(
      top: !compact,
      child: compact
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
              child: list,
            )
          : SizedBox(
              width: 360,
              height: (artists.length * 56.0).clamp(56.0, 336.0),
              child: list,
            ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({this.uri, this.playlist = false});
  final String? uri;
  final bool playlist;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      child: Icon(
        playlist ? Icons.queue_music_rounded : Icons.music_note_rounded,
        color: colors.onPrimaryContainer,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(playlist ? 22 : 10),
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

class _DetailFailure extends StatelessWidget {
  const _DetailFailure({
    required this.failure,
    required this.canRetry,
    required this.showSignInAgain,
    required this.onRetry,
    required this.onSignInAgain,
    super.key,
  });

  final UserLibraryFailure? failure;
  final bool canRetry;
  final bool showSignInAgain;
  final VoidCallback onRetry;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final (title, detail) = _failureCopy(failure);
    return _DetailMessage(
      icon: failure == UserLibraryFailure.credentialRejected
          ? Icons.lock_reset_rounded
          : Icons.cloud_off_rounded,
      title: title,
      detail: detail,
      announce: true,
      actions: [
        if (canRetry)
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        if (showSignInAgain)
          TextButton(
            onPressed: onSignInAgain,
            child: const Text('Sign in again'),
          ),
      ],
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.actions = const [],
    this.announce = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final List<Widget> actions;
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final message = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 18),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(detail, textAlign: TextAlign.center),
      ],
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (announce)
              Semantics(
                container: true,
                liveRegion: true,
                label: '$title. $detail',
                excludeSemantics: true,
                child: message,
              )
            else
              message,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(spacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

(String, String) _failureCopy(UserLibraryFailure? failure) => switch (failure) {
  UserLibraryFailure.network => (
    'Couldn’t reach QQ Music',
    'Your session is still active. Check your connection and try again.',
  ),
  UserLibraryFailure.serviceUnavailable => (
    'QQ Music is unavailable',
    'The playlist could not be loaded right now. Your session was kept.',
  ),
  UserLibraryFailure.invalidResponse => (
    'Couldn’t read this playlist',
    'QQ Music returned data this build could not safely present.',
  ),
  UserLibraryFailure.credentialRejected => (
    'Your saved session was rejected',
    'QQ Music no longer accepts it, so the stored session was removed.',
  ),
  UserLibraryFailure.credentialRejectedStorageCleanupFailed => (
    'Your saved session was rejected',
    'QQ Music rejected it, but secure storage could not remove it.',
  ),
  UserLibraryFailure.authenticationRequired ||
  UserLibraryFailure.replaced ||
  UserLibraryFailure.cancelled => (
    'Sign in to open this playlist',
    'The account state changed before the request finished.',
  ),
  UserLibraryFailure.coreUnavailable => (
    'The music core is unavailable',
    'This playlist could not be loaded safely.',
  ),
  UserLibraryFailure.alreadyRunning => (
    'A playlist request is already running',
    'Wait for it to finish, then try again.',
  ),
  null => ('Couldn’t load this playlist', 'Try again or sign in again.'),
};

String _refreshFailureCopy(UserLibraryFailure failure) => switch (failure) {
  UserLibraryFailure.network =>
    'Couldn’t refresh this playlist. Check your connection; the previous '
        'tracks are still shown.',
  UserLibraryFailure.serviceUnavailable =>
    'QQ Music couldn’t refresh this playlist. The previous tracks are still '
        'shown.',
  UserLibraryFailure.invalidResponse =>
    'QQ Music returned an incomplete refresh. The previous complete tracks '
        'are still shown.',
  UserLibraryFailure.coreUnavailable =>
    'The music core couldn’t refresh this playlist. The previous tracks are '
        'still shown.',
  _ => 'Couldn’t refresh this playlist. The previous tracks are still shown.',
};
