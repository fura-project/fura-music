import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_refresh_failure_banner.dart';
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
    super.key,
  });

  final UserPlaylistSummary playlist;
  final PlaylistDetailGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  late final PlaylistDetailController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PlaylistDetailController(widget.playlist, widget.gateway);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
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
      ),
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
      desktop: desktop,
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
      onRetry: _controller.retry,
      onSignInAgain: widget.onSignInAgain,
    ),
    PlaylistDetailStage.authenticationRequired ||
    PlaylistDetailStage.credentialRejected => _DetailFailure(
      key: const ValueKey('playlist-detail-authentication-error'),
      failure: _controller.failure,
      canRetry: false,
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

class _TrackCollection extends StatelessWidget {
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
    required this.desktop,
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
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(desktop ? 40 : 12, 0, desktop ? 40 : 12, 28),
      itemCount: tracks.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        if (index == tracks.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Text(
                  'Showing ${tracks.length} of $total tracks',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
                    onPressed: onLoadMore,
                    child: const Text('Load more'),
                  ),
                if (!hasMore && !isLoadingMore && appendFailure == null)
                  Text(
                    'End of playlist',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        }
        return _TrackRow(
          index: index + 1,
          track: tracks[index],
          desktop: desktop,
          onTap: () => onTrackSelected(index),
          onAddToQueue: () => onTrackQueued(tracks[index]),
        );
      },
    );
  }
}

class _TrackRow extends StatefulWidget {
  const _TrackRow({
    required this.index,
    required this.track,
    required this.desktop,
    required this.onTap,
    required this.onAddToQueue,
  });

  final int index;
  final PlaylistTrackSummary track;
  final bool desktop;
  final VoidCallback onTap;
  final VoidCallback onAddToQueue;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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
        excludeSemantics: true,
        onTap: widget.onTap,
        onLongPress: widget.desktop
            ? null
            : () => unawaited(_showMobileActions(context)),
        child: InkWell(
          key: ValueKey('playlist-track-row-${widget.index}'),
          focusNode: _focusNode,
          borderRadius: BorderRadius.circular(14),
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
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.desktop ? 8 : 4,
              vertical: 8,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: widget.desktop ? 40 : 28,
                  child: Text(
                    '${widget.index}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: widget.desktop ? 52 : 56,
                  child: _Artwork(uri: widget.track.artworkUri),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.desktop || widget.track.albumTitle == null
                            ? artists
                            : '$artists · ${widget.track.albumTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.desktop) ...[
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: Text(
                      widget.track.albumTitle ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 16),
                SizedBox(
                  width: 48,
                  child: Text(
                    _duration(widget.track.durationSeconds),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
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
      items: const [
        PopupMenuItem(
          value: _TrackAction.playFromHere,
          child: ListTile(
            leading: Icon(Icons.play_arrow_rounded),
            title: Text('Play from here'),
          ),
        ),
        PopupMenuItem(
          value: _TrackAction.addToQueue,
          child: ListTile(
            leading: Icon(Icons.playlist_add_rounded),
            title: Text('Add to queue'),
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
      case null:
        return;
    }
  }
}

enum _TrackAction { playFromHere, addToQueue }

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
    required this.onRetry,
    required this.onSignInAgain,
    super.key,
  });

  final UserLibraryFailure? failure;
  final bool canRetry;
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
      actions: [
        if (canRetry)
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
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
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(spacing: 8, children: actions),
          ],
        ],
      ),
    ),
  );
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

String _duration(int? seconds) {
  if (seconds == null || seconds <= 0) return '—';
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}
