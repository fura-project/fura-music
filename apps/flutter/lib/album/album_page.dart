import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_controller.dart';
import 'package:flutterustmusic/album/album_details_controller.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({
    required this.album,
    required this.gateway,
    required this.detailsGateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onSignInAgain,
    this.backTooltip = 'Back to search results',
    super.key,
  });

  final AlbumSummary album;
  final AlbumTrackGateway gateway;
  final AlbumDetailsGateway detailsGateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final String backTooltip;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  late final AlbumController _controller;
  late final AlbumDetailsController _detailsController;

  @override
  void initState() {
    super.initState();
    _controller = AlbumController(widget.album, widget.gateway);
    _detailsController = AlbumDetailsController(
      widget.album,
      widget.detailsGateway,
    );
    unawaited(_controller.load());
    unawaited(_detailsController.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        key: const ValueKey('album-back'),
        tooltip: widget.backTooltip,
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Album'),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, _detailsController]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;
            return Column(
              children: [
                _AlbumHeader(
                  album: _detailsController.details?.album ?? widget.album,
                  details: _detailsController.details,
                  detailsStage: _detailsController.stage,
                  detailsFailure: _detailsController.failure,
                  canRetryDetails: _detailsController.canRetry,
                  onRetryDetails: _detailsController.retry,
                  onShowDescription: _showDescription,
                  total: _controller.stage == AlbumTrackStage.content
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
    AlbumTrackStage.loading => const Center(
      key: ValueKey('album-loading'),
      child: CircularProgressIndicator(),
    ),
    AlbumTrackStage.empty => const _AlbumMessage(
      key: ValueKey('album-empty'),
      icon: Icons.album_outlined,
      title: 'This Album has no available Tracks',
      detail: 'QQ Music returned an empty Album Track list.',
    ),
    AlbumTrackStage.error => _AlbumMessage(
      key: const ValueKey('album-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load this Album',
      detail: _failureCopy(_controller.failure),
      liveRegion: true,
      action: _controller.canRetry
          ? FilledButton.tonal(
              onPressed: _controller.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    AlbumTrackStage.content => _AlbumTracks(
      key: const ValueKey('album-content'),
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

  void _showDescription(String description) {
    final title = _detailsController.details?.album.title ?? widget.album.title;
    if (MediaQuery.sizeOf(context).width < 600) {
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => FractionallySizedBox(
            heightFactor: 0.72,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'About $title',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SelectableText(description),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('About $title'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(child: SelectableText(description)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.album,
    required this.details,
    required this.detailsStage,
    required this.detailsFailure,
    required this.canRetryDetails,
    required this.onRetryDetails,
    required this.onShowDescription,
    required this.total,
    required this.desktop,
  });

  final AlbumSummary album;
  final AlbumDetails? details;
  final AlbumDetailsStage detailsStage;
  final AlbumDetailsFailure? detailsFailure;
  final bool canRetryDetails;
  final VoidCallback onRetryDetails;
  final ValueChanged<String> onShowDescription;
  final int? total;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final artists = details?.artists.map((artist) => artist.name).join(' · ');
    final metadata = <String>[
      ?details?.releaseDate,
      ?details?.albumType,
      ?details?.genre,
      ?details?.language,
      ?details?.company,
    ];
    final artwork = SizedBox.square(
      dimension: desktop ? 132 : 92,
      child: _AlbumArtwork(uri: album.artworkUri),
    );
    final copy = Column(
      crossAxisAlignment: desktop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Semantics(
          header: true,
          child: Text(
            album.title,
            key: const ValueKey('album-title'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: desktop ? TextAlign.start : TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (details?.subtitle case final subtitle?) ...[
          const SizedBox(height: 5),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: desktop ? TextAlign.start : TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
        if (artists case final names? when names.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            names,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: desktop ? TextAlign.start : TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (total case final count?) ...[
          const SizedBox(height: 8),
          Text('$count ${count == 1 ? 'Track' : 'Tracks'}'),
        ],
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            metadata.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: desktop ? TextAlign.start : TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (details?.description case final description?) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            key: const ValueKey('album-about'),
            onPressed: () => onShowDescription(description),
            icon: const Icon(Icons.notes_rounded),
            label: const Text('About this Album'),
          ),
        ],
        if (detailsStage == AlbumDetailsStage.loading) ...[
          const SizedBox(height: 8),
          const SizedBox(
            width: 180,
            child: LinearProgressIndicator(
              key: ValueKey('album-details-loading'),
            ),
          ),
        ] else if (detailsStage == AlbumDetailsStage.error) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Wrap(
              alignment: desktop ? WrapAlignment.start : WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  _detailsFailureCopy(detailsFailure),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
                if (canRetryDetails)
                  TextButton(
                    key: const ValueKey('album-details-retry'),
                    onPressed: onRetryDetails,
                    child: const Text('Retry details'),
                  ),
              ],
            ),
          ),
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
                    artwork,
                    const SizedBox(width: 24),
                    Expanded(child: copy),
                  ],
                )
              : Column(children: [artwork, const SizedBox(height: 14), copy]),
        ),
      ),
    );
  }
}

class _AlbumTracks extends StatelessWidget {
  const _AlbumTracks({
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
  final AlbumTrackFailure? appendFailure;
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
        key: const PageStorageKey('album-tracks'),
        padding: EdgeInsets.fromLTRB(
          desktop ? 40 : 12,
          0,
          desktop ? 40 : 12,
          24,
        ),
        itemCount: tracks.length + 1,
        itemBuilder: (context, index) {
          if (index == tracks.length) {
            return _AlbumFooter(
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              appendFailure: appendFailure,
              onLoadMore: onLoadMore,
              onRetryMore: onRetryMore,
            );
          }
          final track = tracks[index];
          final artists = track.artistNames.isEmpty
              ? 'Unknown artist'
              : track.artistNames.join(' · ');
          return ListTile(
            key: ValueKey('album-track-$index'),
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
            subtitle: Text(
              artists,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onPlay(index),
            trailing: IconButton(
              key: ValueKey('album-queue-$index'),
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

class _AlbumArtwork extends StatelessWidget {
  const _AlbumArtwork({this.uri});

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
      child: Icon(Icons.album_rounded, color: colors.onPrimaryContainer),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
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

class _AlbumFooter extends StatelessWidget {
  const _AlbumFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final AlbumTrackFailure? appendFailure;
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
              key: const ValueKey('album-load-more'),
              onPressed: onLoadMore,
              child: const Text('Load more'),
            )
          : Text(
              'End of Album',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

class _AlbumMessage extends StatelessWidget {
  const _AlbumMessage({
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

String _failureCopy(AlbumTrackFailure? failure) => switch (failure) {
  AlbumTrackFailure.network => 'Check your connection and try again.',
  AlbumTrackFailure.serviceUnavailable =>
    'QQ Music Album browsing is temporarily unavailable.',
  AlbumTrackFailure.cancelled => 'The Album request was cancelled.',
  AlbumTrackFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  AlbumTrackFailure.invalidResponse ||
  AlbumTrackFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected Album response.',
};

String _detailsFailureCopy(AlbumDetailsFailure? failure) => switch (failure) {
  AlbumDetailsFailure.network => 'Album details are offline.',
  AlbumDetailsFailure.serviceUnavailable =>
    'Album details are temporarily unavailable.',
  AlbumDetailsFailure.cancelled => 'Album detail loading was cancelled.',
  AlbumDetailsFailure.coreUnavailable => 'Album details could not start.',
  AlbumDetailsFailure.invalidResponse ||
  AlbumDetailsFailure.alreadyRunning ||
  null => 'Album details could not be read.',
};
