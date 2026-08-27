import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_controller.dart';
import 'package:flutterustmusic/album/album_details_controller.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/catalog/music_catalog_header.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/music_track_tile.dart';
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
    this.onOpenArtist,
    this.backTooltip = 'Back to search results',
    super.key,
  });

  final AlbumSummary album;
  final AlbumTrackGateway gateway;
  final AlbumDetailsGateway detailsGateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final ValueChanged<ArtistSummary>? onOpenArtist;
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
                  onOpenArtists: widget.onOpenArtist == null
                      ? null
                      : _openArtist,
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
    AlbumTrackStage.loading => const MusicLoadingPanel(
      key: ValueKey('album-loading'),
      label: 'Loading Album Tracks',
    ),
    AlbumTrackStage.empty => const MusicContentStatePanel(
      key: ValueKey('album-empty'),
      icon: Icons.album_outlined,
      title: 'This Album has no available Tracks',
      detail: 'QQ Music returned an empty Album Track list.',
    ),
    AlbumTrackStage.error => MusicContentStatePanel(
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
      onOpenArtist: widget.onOpenArtist,
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

  Future<void> _openArtist(List<ArtistSummary> artists) async {
    final onOpenArtist = widget.onOpenArtist;
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
                _AlbumArtistSelection(artists: artists, compact: true),
          )
        : await showDialog<ArtistSummary>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Choose an Artist'),
              content: _AlbumArtistSelection(artists: artists, compact: false),
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

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.album,
    required this.details,
    required this.detailsStage,
    required this.detailsFailure,
    required this.canRetryDetails,
    required this.onRetryDetails,
    required this.onShowDescription,
    required this.onOpenArtists,
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
  final ValueChanged<List<ArtistSummary>>? onOpenArtists;
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
    return MusicCatalogHeader(
      artwork: _AlbumArtwork(uri: album.artworkUri),
      eyebrow: 'ALBUM',
      title: album.title,
      titleKey: const ValueKey('album-title'),
      desktop: desktop,
      children: [
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
          if (onOpenArtists == null)
            Text(
              names,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: desktop ? TextAlign.start : TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            TextButton.icon(
              key: const ValueKey('album-open-artist'),
              onPressed: () => onOpenArtists!(details!.artists),
              icon: const Icon(Icons.person_rounded),
              label: Text(
                names,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: desktop ? TextAlign.start : TextAlign.center,
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
  }
}

class _AlbumArtistSelection extends StatelessWidget {
  const _AlbumArtistSelection({required this.artists, required this.compact});

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
            subtitle: Text('This Album credits more than one Artist.'),
          ),
        for (var index = 0; index < artists.length; index++)
          ListTile(
            key: ValueKey('album-artist-$index'),
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
    required this.onOpenArtist,
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
  final ValueChanged<ArtistSummary>? onOpenArtist;
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
          return MusicTrackTile(
            itemKey: ValueKey('album-track-$index'),
            queueKey: ValueKey('album-queue-$index'),
            contextKey: ValueKey('album-context-$index'),
            track: track,
            position: index + 1,
            desktop: desktop,
            onPlay: () => onPlay(index),
            onQueue: () => onQueue(track),
            onOpenArtist: onOpenArtist,
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
