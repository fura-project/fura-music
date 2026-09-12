import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_controller.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_controller.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/catalog/artist_artwork.dart';
import 'package:flutterustmusic/catalog/music_catalog_header.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/provider_presentation.dart';

class ArtistPage extends StatefulWidget {
  const ArtistPage({
    required this.artist,
    required this.gateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onSignInAgain,
    this.albumGateway,
    this.onOpenAlbum,
    this.backTooltip,
    this.embedded = false,
    super.key,
  });

  final ArtistSummary artist;
  final ArtistTrackGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final ArtistAlbumGateway? albumGateway;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final String? backTooltip;
  final bool embedded;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

enum _ArtistSection { tracks, albums }

class _ArtistPageState extends State<ArtistPage> {
  late final ArtistController _controller;
  late final ArtistAlbumController _albumController;
  late final Listenable _controllers;
  _ArtistSection _section = _ArtistSection.tracks;

  @override
  void initState() {
    super.initState();
    _controller = ArtistController(widget.artist, widget.gateway);
    _albumController = ArtistAlbumController(
      widget.artist,
      widget.albumGateway ?? const RustArtistAlbumGateway(),
    );
    _controllers = Listenable.merge([_controller, _albumController]);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _albumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backTooltip = widget.backTooltip ?? context.l10n.commonBack;
    final body = SafeArea(
      child: AnimatedBuilder(
        animation: _controllers,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;
            return Column(
              children: [
                _ArtistHeader(
                  artist: widget.artist,
                  total: _visibleTotal,
                  section: _section,
                  desktop: desktop,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    desktop ? 48 : 20,
                    0,
                    desktop ? 48 : 20,
                    16,
                  ),
                  child: SegmentedButton<_ArtistSection>(
                    key: const ValueKey('artist-sections'),
                    segments: [
                      ButtonSegment(
                        value: _ArtistSection.tracks,
                        icon: const Icon(Icons.music_note_rounded),
                        label: Text(context.l10n.artistTracksSection),
                      ),
                      ButtonSegment(
                        value: _ArtistSection.albums,
                        icon: const Icon(Icons.album_rounded),
                        label: Text(context.l10n.artistAlbumsSection),
                      ),
                    ],
                    selected: {_section},
                    onSelectionChanged: _selectSection,
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _section == _ArtistSection.tracks
                        ? _trackBody(desktop)
                        : _albumBody(desktop),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (widget.embedded) {
      return Material(
        key: const ValueKey('embedded-artist-detail'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            SizedBox(
              height: kToolbarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('artist-back'),
                      tooltip: backTooltip,
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.artistType,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('artist-back'),
          tooltip: backTooltip,
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(context.l10n.artistType),
      ),
      body: body,
      bottomNavigationBar: NowPlayingBar(
        controller: widget.queuePlaybackController,
        onSignInAgain: widget.onSignInAgain,
      ),
    );
  }

  int? get _visibleTotal => switch (_section) {
    _ArtistSection.tracks =>
      _controller.stage == ArtistTrackStage.content ? _controller.total : null,
    _ArtistSection.albums =>
      _albumController.stage == ArtistAlbumStage.content
          ? _albumController.total
          : null,
  };

  void _selectSection(Set<_ArtistSection> selected) {
    final section = selected.single;
    if (_section == section) return;
    setState(() => _section = section);
    if (section == _ArtistSection.albums) {
      unawaited(_albumController.load());
    }
  }

  Widget _trackBody(bool desktop) {
    final l10n = context.l10n;
    final providerName = builtInProviderDisplayName(
      widget.artist.providerId,
      l10n,
    );
    return switch (_controller.stage) {
      ArtistTrackStage.loading => MusicLoadingPanel(
        key: const ValueKey('artist-loading'),
        label: l10n.artistLoadingTracks,
      ),
      ArtistTrackStage.empty => MusicContentStatePanel(
        key: const ValueKey('artist-empty'),
        icon: Icons.person_off_outlined,
        title: l10n.artistEmptyTracksTitle,
        detail: l10n.artistEmptyTracksDetail(providerName),
      ),
      ArtistTrackStage.error => MusicContentStatePanel(
        key: const ValueKey('artist-error'),
        icon: Icons.cloud_off_rounded,
        title: l10n.artistFailureTitle,
        detail: _failureCopy(l10n, _controller.failure, providerName),
        liveRegion: true,
        action: _controller.canRetry
            ? FilledButton.tonal(
                onPressed: _controller.retry,
                child: Text(l10n.commonRetry),
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
        onOpenAlbum: widget.onOpenAlbum,
        current: widget.queuePlaybackController.current,
        desktop: desktop,
      ),
    };
  }

  Widget _albumBody(bool desktop) {
    final l10n = context.l10n;
    final providerName = builtInProviderDisplayName(
      widget.artist.providerId,
      l10n,
    );
    return switch (_albumController.stage) {
      ArtistAlbumStage.loading => MusicLoadingPanel(
        key: const ValueKey('artist-albums-loading'),
        label: l10n.artistLoadingAlbums,
      ),
      ArtistAlbumStage.empty => MusicContentStatePanel(
        key: const ValueKey('artist-albums-empty'),
        icon: Icons.album_outlined,
        title: l10n.artistEmptyAlbumsTitle,
        detail: l10n.artistEmptyAlbumsDetail(providerName),
      ),
      ArtistAlbumStage.error => MusicContentStatePanel(
        key: const ValueKey('artist-albums-error'),
        icon: Icons.cloud_off_rounded,
        title: l10n.artistAlbumsFailureTitle,
        detail: _albumFailureCopy(l10n, _albumController.failure, providerName),
        liveRegion: true,
        action: _albumController.canRetry
            ? FilledButton.tonal(
                onPressed: _albumController.retry,
                child: Text(l10n.commonRetry),
              )
            : null,
      ),
      ArtistAlbumStage.content => _ArtistAlbums(
        key: const ValueKey('artist-albums-content'),
        albums: _albumController.albums,
        hasMore: _albumController.hasMore,
        isLoadingMore: _albumController.isLoadingMore,
        appendFailure: _albumController.appendFailure,
        onLoadMore: _albumController.loadMore,
        onRetryMore: _albumController.retryMore,
        onOpen: widget.onOpenAlbum,
        desktop: desktop,
      ),
    };
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
        ? context.l10n.queueAddedMessage
        : context.l10n.queueUpdateFailureMessage;
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
    required this.section,
    required this.desktop,
  });

  final ArtistSummary artist;
  final int? total;
  final _ArtistSection section;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final portrait = ArtistArtwork(
      uri: artist.artworkUri,
      iconSize: desktop ? 68 : 48,
    );
    return MusicCatalogHeader(
      artwork: portrait,
      eyebrow: context.l10n.artistType,
      title: artist.name,
      titleKey: const ValueKey('artist-name'),
      desktop: desktop,
      children: [
        if (total case final count?) ...[
          const SizedBox(height: 8),
          Text(
            section == _ArtistSection.tracks
                ? context.l10n.artistTrackCount(count)
                : context.l10n.artistAlbumCount(count),
          ),
        ],
      ],
    );
  }
}

class _ArtistAlbums extends StatelessWidget {
  const _ArtistAlbums({
    required this.albums,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onOpen,
    required this.desktop,
    super.key,
  });

  final List<AlbumSummary> albums;
  final bool hasMore;
  final bool isLoadingMore;
  final ArtistAlbumFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<AlbumSummary>? onOpen;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120),
      child: CustomScrollView(
        key: const PageStorageKey('artist-albums'),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              desktop ? 40 : 12,
              0,
              desktop ? 40 : 12,
              8,
            ),
            sliver: desktop
                ? SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisExtent: 262,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                        ),
                    itemCount: albums.length,
                    itemBuilder: (context, index) => _ArtistAlbumCard(
                      key: ValueKey('artist-album-$index'),
                      album: albums[index],
                      onOpen: onOpen,
                    ),
                  )
                : SliverList.builder(
                    itemCount: albums.length,
                    itemBuilder: (context, index) => _ArtistAlbumTile(
                      key: ValueKey('artist-album-$index'),
                      album: albums[index],
                      onOpen: onOpen,
                    ),
                  ),
          ),
          SliverToBoxAdapter(
            child: _ArtistAlbumFooter(
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              appendFailure: appendFailure,
              onLoadMore: onLoadMore,
              onRetryMore: onRetryMore,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ArtistAlbumTile extends StatelessWidget {
  const _ArtistAlbumTile({
    required this.album,
    required this.onOpen,
    super.key,
  });

  final AlbumSummary album;
  final ValueChanged<AlbumSummary>? onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 78,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    leading: SizedBox.square(
      dimension: 56,
      child: _ArtistAlbumArtwork(uri: album.artworkUri),
    ),
    title: Text(album.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(context.l10n.albumType),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onOpen == null ? null : () => onOpen!(album),
  );
}

class _ArtistAlbumCard extends StatelessWidget {
  const _ArtistAlbumCard({
    required this.album,
    required this.onOpen,
    super.key,
  });

  final AlbumSummary album;
  final ValueChanged<AlbumSummary>? onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onOpen == null ? null : () => onOpen!(album),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: _ArtistAlbumArtwork(uri: album.artworkUri),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            album.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.albumType,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ArtistAlbumArtwork extends StatelessWidget {
  const _ArtistAlbumArtwork({required this.uri});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Icon(Icons.album_rounded, color: colors.onSecondaryContainer),
    );
    final artwork = uri == null
        ? fallback
        : Image.network(
            uri!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: artwork);
  }
}

class _ArtistAlbumFooter extends StatelessWidget {
  const _ArtistAlbumFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final ArtistAlbumFailure? appendFailure;
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
              key: const ValueKey('artist-albums-retry-more'),
              onPressed: onRetryMore,
              child: Text(context.l10n.commonTryLoadingMoreAgain),
            )
          : hasMore
          ? FilledButton.tonal(
              key: const ValueKey('artist-albums-load-more'),
              onPressed: onLoadMore,
              child: Text(context.l10n.commonLoadMore),
            )
          : Text(
              context.l10n.artistEndAlbums,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

class _ArtistTracks extends StatefulWidget {
  const _ArtistTracks({
    required this.tracks,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onPlay,
    required this.onQueue,
    required this.onOpenAlbum,
    required this.current,
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
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final PlaylistTrackSummary? current;
  final bool desktop;

  @override
  State<_ArtistTracks> createState() => _ArtistTracksState();
}

class _ArtistTracksState extends State<_ArtistTracks> {
  (String, String)? _hoveredTrack;

  void _setHovered(PlaylistTrackSummary track, bool hovered) {
    final identity = (track.providerId, track.opaqueId);
    if (hovered && _hoveredTrack != identity) {
      setState(() => _hoveredTrack = identity);
    } else if (!hovered && _hoveredTrack == identity) {
      setState(() => _hoveredTrack = null);
    }
  }

  bool _handleScroll(ScrollNotification notification) {
    if (_hoveredTrack != null && notification is ScrollUpdateNotification) {
      setState(() => _hoveredTrack = null);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.desktop ? 24.0 : 10.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(
          children: [
            if (widget.desktop)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                child: MusicTrackTableHeader(
                  key: const ValueKey('artist-track-table-header'),
                  titleLabel: context.l10n.tableTitle,
                  artistLabel: context.l10n.tableArtist,
                  albumLabel: context.l10n.tableAlbum,
                  durationLabel: context.l10n.tableDuration,
                ),
              ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScroll,
                child: ListView.separated(
                  key: const PageStorageKey('artist-tracks'),
                  padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 24),
                  itemCount: widget.tracks.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 1),
                  itemBuilder: (context, index) {
                    if (index == widget.tracks.length) {
                      return _ArtistFooter(
                        hasMore: widget.hasMore,
                        isLoadingMore: widget.isLoadingMore,
                        appendFailure: widget.appendFailure,
                        onLoadMore: widget.onLoadMore,
                        onRetryMore: widget.onRetryMore,
                      );
                    }
                    final track = widget.tracks[index];
                    final identity = (track.providerId, track.opaqueId);
                    final selected =
                        widget.current?.providerId == track.providerId &&
                        widget.current?.opaqueId == track.opaqueId;
                    final artists = track.artistNames.isEmpty
                        ? context.l10n.trackUnknownArtist
                        : track.artistNames.join(' / ');
                    final canOpenAlbum =
                        widget.onOpenAlbum != null && track.album != null;
                    return MusicTrackRowSurface(
                      key: ValueKey(
                        'artist-track-state-${track.providerId}-${track.opaqueId}',
                      ),
                      itemKey: ValueKey('artist-track-$index'),
                      desktop: widget.desktop,
                      current: selected,
                      hovered: _hoveredTrack == identity,
                      onHoverChanged: (hovered) => _setHovered(track, hovered),
                      semanticLabel: context.l10n.commonTrackSemantics(
                        artists,
                        track.title,
                      ),
                      onTap: () => widget.onPlay(index),
                      onContextMenuRequested: (_) =>
                          unawaited(_showActions(track, index)),
                      contentBuilder: (context, active, hovered) =>
                          MusicTrackRowContent(
                            index: index + 1,
                            track: track,
                            desktop: widget.desktop,
                            current: selected,
                            active: active,
                            artistNames: artists,
                            onPlay: () => widget.onPlay(index),
                            onAddToQueue: () => widget.onQueue(track),
                            onOpenAlbum: canOpenAlbum
                                ? () => widget.onOpenAlbum!(track.album!)
                                : null,
                            onMore: () => unawaited(_showActions(track, index)),
                            showInlineQueueAction: hovered,
                            queueKey: ValueKey('artist-queue-$index'),
                            moreKey: ValueKey('artist-context-$index'),
                          ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(PlaylistTrackSummary track, int index) async {
    final canOpenAlbum = widget.onOpenAlbum != null && track.album != null;
    final action = await showModalBottomSheet<MusicTrackAction>(
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
              onTap: () => Navigator.pop(context, MusicTrackAction.play),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(context.l10n.commonAddToQueue),
              onTap: () => Navigator.pop(context, MusicTrackAction.addToQueue),
            ),
            if (canOpenAlbum)
              ListTile(
                leading: const Icon(Icons.album_rounded),
                title: Text(context.l10n.commonOpenAlbum),
                onTap: () => Navigator.pop(context, MusicTrackAction.openAlbum),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (action) {
      case MusicTrackAction.play:
        widget.onPlay(index);
      case MusicTrackAction.addToQueue:
        widget.onQueue(track);
      case MusicTrackAction.openAlbum:
        widget.onOpenAlbum!(track.album!);
      case MusicTrackAction.openArtist:
      case null:
        return;
    }
  }
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
              child: Text(context.l10n.commonTryLoadingMoreAgain),
            )
          : hasMore
          ? FilledButton.tonal(
              key: const ValueKey('artist-load-more'),
              onPressed: onLoadMore,
              child: Text(context.l10n.commonLoadMore),
            )
          : Text(
              context.l10n.artistEndTracks,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

String _failureCopy(
  AppLocalizations l10n,
  ArtistTrackFailure? failure,
  String providerName,
) => switch (failure) {
  ArtistTrackFailure.network => l10n.albumFailureNetwork,
  ArtistTrackFailure.serviceUnavailable => l10n.artistFailureService(
    providerName,
  ),
  ArtistTrackFailure.cancelled => l10n.artistFailureCancelled,
  ArtistTrackFailure.coreUnavailable => l10n.catalogFailureCore,
  ArtistTrackFailure.invalidResponse ||
  ArtistTrackFailure.alreadyRunning ||
  null => l10n.artistFailureUnexpected(providerName),
};

String _albumFailureCopy(
  AppLocalizations l10n,
  ArtistAlbumFailure? failure,
  String providerName,
) => switch (failure) {
  ArtistAlbumFailure.network => l10n.albumFailureNetwork,
  ArtistAlbumFailure.serviceUnavailable => l10n.artistAlbumsFailureService(
    providerName,
  ),
  ArtistAlbumFailure.cancelled => l10n.artistAlbumsFailureCancelled,
  ArtistAlbumFailure.coreUnavailable => l10n.catalogFailureCore,
  ArtistAlbumFailure.invalidResponse ||
  ArtistAlbumFailure.alreadyRunning ||
  null => l10n.artistAlbumsFailureUnexpected(providerName),
};
