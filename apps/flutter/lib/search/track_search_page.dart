import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/search/track_search_controller.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';

class TrackSearchPage extends StatefulWidget {
  const TrackSearchPage({
    required this.gateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onSignInAgain,
    super.key,
  });

  final TrackSearchGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;

  @override
  State<TrackSearchPage> createState() => _TrackSearchPageState();
}

class _TrackSearchPageState extends State<TrackSearchPage> {
  late final TrackSearchController _controller;
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocusNode = FocusNode(debugLabel: 'track search');

  @override
  void initState() {
    super.initState();
    _controller = TrackSearchController(widget.gateway);
  }

  @override
  void dispose() {
    _controller.dispose();
    _queryController.dispose();
    _queryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        key: const ValueKey('track-search-back'),
        tooltip: 'Back to your music',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Search QQ Music'),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;
            return Column(
              children: [
                _SearchField(
                  controller: _queryController,
                  focusNode: _queryFocusNode,
                  desktop: desktop,
                  loading: _controller.stage == TrackSearchStage.loading,
                  onSubmitted: _controller.submit,
                  onClear: _clear,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
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

  Widget _body(bool desktop) => switch (_controller.stage) {
    TrackSearchStage.idle => const _SearchMessage(
      key: ValueKey('track-search-idle'),
      icon: Icons.search_rounded,
      title: 'Find music on QQ Music',
      detail: 'Search by song, artist, or album name.',
    ),
    TrackSearchStage.loading => const Center(
      key: ValueKey('track-search-loading'),
      child: CircularProgressIndicator(),
    ),
    TrackSearchStage.empty => _SearchMessage(
      key: const ValueKey('track-search-empty'),
      icon: Icons.search_off_rounded,
      title: 'No tracks found',
      detail: 'Try a different spelling or a broader search.',
      action: TextButton(
        onPressed: _focusQuery,
        child: const Text('Edit search'),
      ),
    ),
    TrackSearchStage.error => _SearchFailure(
      key: const ValueKey('track-search-error'),
      failure: _controller.failure,
      canRetry: _controller.canRetry,
      onRetry: _controller.retry,
      onEdit: _focusQuery,
    ),
    TrackSearchStage.content => _SearchResults(
      key: const ValueKey('track-search-content'),
      query: _controller.query,
      tracks: _controller.tracks,
      total: _controller.total,
      hasMore: _controller.hasMore,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
      onPlay: _play,
      onQueue: _queue,
      desktop: desktop,
    ),
  };

  void _clear() {
    _queryController.clear();
    _controller.clear();
    _focusQuery();
  }

  void _focusQuery() {
    _queryFocusNode.requestFocus();
    _queryController.selection = TextSelection.collapsed(
      offset: _queryController.text.length,
    );
  }

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
        ? 'Added to queue'
        : 'Couldn’t update the queue';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    unawaited(playbackStart);
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.desktop,
    required this.loading,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool desktop;
  final bool loading;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      desktop ? 48 : 20,
      desktop ? 20 : 12,
      desktop ? 48 : 20,
      16,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => TextField(
            key: const ValueKey('track-search-field'),
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: loading ? null : onSubmitted,
            decoration: InputDecoration(
              hintText: 'Songs, artists, or albums',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.tracks,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onPlay,
    required this.onQueue,
    required this.desktop,
    super.key,
  });

  final String query;
  final List<PlaylistTrackSummary> tracks;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;
  final TrackSearchFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<int> onPlay;
  final ValueChanged<PlaylistTrackSummary> onQueue;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120),
      child: ListView.builder(
        key: const PageStorageKey('track-search-results'),
        padding: EdgeInsets.fromLTRB(
          desktop ? 40 : 12,
          0,
          desktop ? 40 : 12,
          24,
        ),
        itemCount: tracks.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
              child: Semantics(
                header: true,
                child: Text(
                  '$total ${total == 1 ? 'result' : 'results'} for “$query”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            );
          }
          if (index == tracks.length + 1) {
            return _SearchFooter(
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              appendFailure: appendFailure,
              onLoadMore: onLoadMore,
              onRetryMore: onRetryMore,
            );
          }
          final trackIndex = index - 1;
          return _SearchTrackRow(
            track: tracks[trackIndex],
            index: trackIndex,
            desktop: desktop,
            onPlay: () => onPlay(trackIndex),
            onQueue: () => onQueue(tracks[trackIndex]),
          );
        },
      ),
    ),
  );
}

class _SearchTrackRow extends StatelessWidget {
  const _SearchTrackRow({
    required this.track,
    required this.index,
    required this.desktop,
    required this.onPlay,
    required this.onQueue,
  });

  final PlaylistTrackSummary track;
  final int index;
  final bool desktop;
  final VoidCallback onPlay;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artists = track.artistNames.isEmpty
        ? 'Unknown artist'
        : track.artistNames.join(' · ');
    final detail = [artists, ?track.albumTitle].join(' · ');
    return Semantics(
      container: true,
      child: ListTile(
        key: ValueKey('track-search-result-$index'),
        minTileHeight: desktop ? 68 : 72,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: SizedBox.square(
          dimension: desktop ? 48 : 52,
          child: _TrackArtwork(uri: track.artworkUri),
        ),
        title: Text(
          track.subtitle == null
              ? track.title
              : '${track.title} · ${track.subtitle}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onPlay,
        trailing: IconButton(
          key: ValueKey('track-search-queue-$index'),
          tooltip: 'Add ${track.title} to queue',
          onPressed: onQueue,
          icon: const Icon(Icons.playlist_add_rounded),
        ),
      ),
    );
  }
}

class _TrackArtwork extends StatelessWidget {
  const _TrackArtwork({this.uri});

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
      child: Icon(Icons.music_note_rounded, color: colors.onPrimaryContainer),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
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

class _SearchFooter extends StatelessWidget {
  const _SearchFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final TrackSearchFailure? appendFailure;
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
              key: const ValueKey('track-search-load-more'),
              onPressed: onLoadMore,
              child: const Text('Load more'),
            )
          : Text(
              'End of results',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

class _SearchFailure extends StatelessWidget {
  const _SearchFailure({
    required this.failure,
    required this.canRetry,
    required this.onRetry,
    required this.onEdit,
    super.key,
  });

  final TrackSearchFailure? failure;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => _SearchMessage(
    icon: Icons.cloud_off_rounded,
    title: 'Couldn’t search QQ Music',
    detail: _failureCopy(failure),
    liveRegion: true,
    action: Wrap(
      spacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (canRetry)
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        TextButton(onPressed: onEdit, child: const Text('Edit search')),
      ],
    ),
  );
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
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
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
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
  );
}

String _failureCopy(TrackSearchFailure? failure) => switch (failure) {
  TrackSearchFailure.network => 'Check your connection and try again.',
  TrackSearchFailure.serviceUnavailable =>
    'QQ Music search is temporarily unavailable.',
  TrackSearchFailure.cancelled => 'The search was cancelled.',
  TrackSearchFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  TrackSearchFailure.invalidResponse ||
  TrackSearchFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected search response.',
};
