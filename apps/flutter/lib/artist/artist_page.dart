import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/artist/artist_controller.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

class ArtistPage extends StatefulWidget {
  const ArtistPage({
    required this.artist,
    required this.gateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onSignInAgain,
    super.key,
  });

  final ArtistSummary artist;
  final ArtistTrackGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  late final ArtistController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ArtistController(widget.artist, widget.gateway);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        key: const ValueKey('artist-back'),
        tooltip: 'Back to search results',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Artist'),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;
            return Column(
              children: [
                _ArtistHeader(
                  artist: widget.artist,
                  total: _controller.stage == ArtistTrackStage.content
                      ? _controller.total
                      : null,
                  desktop: desktop,
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
    ArtistTrackStage.loading => const Center(
      key: ValueKey('artist-loading'),
      child: CircularProgressIndicator(),
    ),
    ArtistTrackStage.empty => const _ArtistMessage(
      key: ValueKey('artist-empty'),
      icon: Icons.person_off_outlined,
      title: 'This Artist has no available Tracks',
      detail: 'QQ Music returned an empty Artist Track list.',
    ),
    ArtistTrackStage.error => _ArtistMessage(
      key: const ValueKey('artist-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load this Artist',
      detail: _failureCopy(_controller.failure),
      liveRegion: true,
      action: _controller.canRetry
          ? FilledButton.tonal(
              onPressed: _controller.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    ArtistTrackStage.content => _ArtistTracks(
      key: const ValueKey('artist-content'),
      tracks: _controller.tracks,
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

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({
    required this.artist,
    required this.total,
    required this.desktop,
  });

  final ArtistSummary artist;
  final int? total;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final portrait = SizedBox.square(
      dimension: desktop ? 132 : 92,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [colors.primaryContainer, colors.tertiaryContainer],
          ),
        ),
        child: Icon(
          Icons.person_rounded,
          size: desktop ? 68 : 48,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
    final copy = Column(
      crossAxisAlignment: desktop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Semantics(
          header: true,
          child: Text(
            artist.name,
            key: const ValueKey('artist-name'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: desktop ? TextAlign.start : TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (total case final count?) ...[
          const SizedBox(height: 8),
          Text('$count ${count == 1 ? 'Track' : 'Tracks'}'),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 48 : 20,
        desktop ? 20 : 12,
        desktop ? 48 : 20,
        20,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: desktop
              ? Row(
                  children: [
                    portrait,
                    const SizedBox(width: 24),
                    Expanded(child: copy),
                  ],
                )
              : Column(children: [portrait, const SizedBox(height: 14), copy]),
        ),
      ),
    );
  }
}

class _ArtistTracks extends StatelessWidget {
  const _ArtistTracks({
    required this.tracks,
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

  final List<PlaylistTrackSummary> tracks;
  final bool hasMore;
  final bool isLoadingMore;
  final ArtistTrackFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<int> onPlay;
  final ValueChanged<PlaylistTrackSummary> onQueue;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1040),
      child: ListView.builder(
        key: const PageStorageKey('artist-tracks'),
        padding: EdgeInsets.fromLTRB(
          desktop ? 40 : 12,
          0,
          desktop ? 40 : 12,
          24,
        ),
        itemCount: tracks.length + 1,
        itemBuilder: (context, index) {
          if (index == tracks.length) {
            return _ArtistFooter(
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              appendFailure: appendFailure,
              onLoadMore: onLoadMore,
              onRetryMore: onRetryMore,
            );
          }
          final track = tracks[index];
          final detail = [
            if (track.artistNames.isNotEmpty) track.artistNames.join(' · '),
            ?track.albumTitle,
          ].join(' · ');
          return ListTile(
            key: ValueKey('artist-track-$index'),
            minTileHeight: desktop ? 64 : 72,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: SizedBox(
              width: 36,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            title: Text(
              track.subtitle == null
                  ? track.title
                  : '${track.title} · ${track.subtitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: detail.isEmpty
                ? null
                : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => onPlay(index),
            trailing: IconButton(
              key: ValueKey('artist-queue-$index'),
              tooltip: 'Add ${track.title} to queue',
              onPressed: () => onQueue(track),
              icon: const Icon(Icons.playlist_add_rounded),
            ),
          );
        },
      ),
    ),
  );
}

class _ArtistFooter extends StatelessWidget {
  const _ArtistFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final ArtistTrackFailure? appendFailure;
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
              key: const ValueKey('artist-load-more'),
              onPressed: onLoadMore,
              child: const Text('Load more'),
            )
          : Text(
              'End of Artist Tracks',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

class _ArtistMessage extends StatelessWidget {
  const _ArtistMessage({
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

String _failureCopy(ArtistTrackFailure? failure) => switch (failure) {
  ArtistTrackFailure.network => 'Check your connection and try again.',
  ArtistTrackFailure.serviceUnavailable =>
    'QQ Music Artist browsing is temporarily unavailable.',
  ArtistTrackFailure.cancelled => 'The Artist request was cancelled.',
  ArtistTrackFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  ArtistTrackFailure.invalidResponse ||
  ArtistTrackFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected Artist response.',
};
