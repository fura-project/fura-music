import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_controller.dart';
import 'package:flutterustmusic/album/album_details_controller.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/catalog/music_collection_detail_layout.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/catalog/partial_results_notice.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/pagination/bounded_viewport_page_demand.dart';
import 'package:flutterustmusic/provider_presentation.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({
    required this.album,
    required this.gateway,
    required this.detailsGateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onSignInAgain,
    this.onOpenArtist,
    this.onHeaderCollapsedChanged,
    this.embedded = false,
    this.backTooltip,
    super.key,
  });

  final AlbumSummary album;
  final AlbumTrackGateway gateway;
  final AlbumDetailsGateway detailsGateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final ValueChanged<ArtistSummary>? onOpenArtist;
  final ValueChanged<bool>? onHeaderCollapsedChanged;
  final bool embedded;
  final String? backTooltip;

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
  Widget build(BuildContext context) {
    final backTooltip =
        widget.backTooltip ?? context.l10n.shellBackToSearchResults;
    final toolbar = AppBar(
      leading: IconButton(
        key: const ValueKey('album-back'),
        tooltip: backTooltip,
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: Text(context.l10n.albumType),
    );
    final body = SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, _detailsController]),
        builder: (context, _) => MusicCollectionDetailLayout(
          key: ValueKey('album-detail-layout-${widget.album.opaqueId}'),
          onHeaderCollapsedChanged: widget.onHeaderCollapsedChanged,
          headerBuilder: (context, desktop, progress) => _AlbumHeader(
            album: _detailsController.details?.album ?? widget.album,
            details: _detailsController.details,
            detailsStage: _detailsController.stage,
            detailsFailure: _detailsController.failure,
            canRetryDetails: _detailsController.canRetry,
            onRetryDetails: _detailsController.retry,
            onShowDescription: _showDescription,
            onOpenArtists: widget.onOpenArtist == null ? null : _openArtist,
            total: _controller.stage == AlbumTrackStage.content
                ? _controller.total
                : null,
            desktop: desktop,
            collapseProgress: progress,
            embedded: widget.embedded,
            onBack: widget.onBack,
            backTooltip: backTooltip,
          ),
          bodyBuilder: (context, desktop) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _body(desktop),
          ),
        ),
      ),
    );
    if (widget.embedded) {
      return ColoredBox(
        key: const ValueKey('embedded-album-detail'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: body,
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

  Widget _body(bool desktop) {
    final l10n = context.l10n;
    final providerName = builtInProviderDisplayName(
      widget.album.providerId,
      l10n,
    );
    return switch (_controller.stage) {
      AlbumTrackStage.loading => MusicLoadingPanel(
        key: const ValueKey('album-loading'),
        label: l10n.albumLoadingTracks,
      ),
      AlbumTrackStage.empty => MusicContentStatePanel(
        key: const ValueKey('album-empty'),
        icon: Icons.album_outlined,
        title: l10n.albumEmptyTitle,
        detail: l10n.albumEmptyDetail(providerName),
      ),
      AlbumTrackStage.error => MusicContentStatePanel(
        key: const ValueKey('album-error'),
        icon: Icons.cloud_off_rounded,
        title: l10n.albumFailureTitle,
        detail: _failureCopy(l10n, _controller.failure, providerName),
        liveRegion: true,
        action: _controller.canRetry
            ? FilledButton.tonal(
                onPressed: _controller.retry,
                child: Text(l10n.commonRetry),
              )
            : null,
      ),
      AlbumTrackStage.content => _AlbumTracks(
        key: const ValueKey('album-content'),
        tracks: _controller.tracks,
        omittedTrackCount: _controller.omittedTrackCount,
        partialResultRevision: _controller.partialResultRevision,
        hasMore: _controller.hasMore,
        isLoadingMore: _controller.isLoadingMore,
        appendFailure: _controller.appendFailure,
        onLoadMore: _controller.loadMore,
        onRetryMore: _controller.retryMore,
        onPlay: _play,
        onQueue: _queue,
        onOpenArtist: widget.onOpenArtist,
        current: widget.queuePlaybackController.current,
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
                      context.l10n.albumAboutTitle(title),
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
                      child: Text(context.l10n.commonClose),
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
          title: Text(context.l10n.albumAboutTitle(title)),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(child: SelectableText(description)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.commonClose),
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
              title: Text(context.l10n.albumChooseArtistTitle),
              content: _AlbumArtistSelection(artists: artists, compact: false),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.commonCancel),
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
    required this.collapseProgress,
    required this.embedded,
    required this.onBack,
    required this.backTooltip,
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
  final double collapseProgress;
  final bool embedded;
  final VoidCallback onBack;
  final String backTooltip;

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
    final descriptors = <String>[
      ?details?.subtitle,
      if (metadata.isNotEmpty) metadata.join(' · '),
    ];
    final summary = total != null
        ? context.l10n.albumTrackCount(total!)
        : context.l10n.albumProviderSummary(
            builtInProviderDisplayName(album.providerId, context.l10n),
          );
    return MusicCollectionDetailHeader(
      collapseProgress: collapseProgress,
      desktop: desktop,
      embedded: embedded,
      artwork: _AlbumArtwork(uri: album.artworkUri),
      eyebrow: context.l10n.albumType,
      title: album.title,
      titleKey: const ValueKey('album-title'),
      summary: summary,
      onBack: onBack,
      backKey: const ValueKey('album-back'),
      backTooltip: backTooltip,
      expandedHeight: desktop ? 244 : 248,
      expandedDetails: [
        if (descriptors.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            descriptors.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: desktop ? TextAlign.start : TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              label: Text(
                names,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: desktop ? TextAlign.start : TextAlign.center,
              ),
            ),
        ],
        if (details?.description case final description?) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            key: const ValueKey('album-about'),
            onPressed: () => onShowDescription(description),
            icon: const Icon(Icons.notes_rounded),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            label: Text(context.l10n.albumAboutAction),
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
                  _detailsFailureCopy(context.l10n, detailsFailure),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
                if (canRetryDetails)
                  TextButton(
                    key: const ValueKey('album-details-retry'),
                    onPressed: onRetryDetails,
                    child: Text(context.l10n.albumRetryDetails),
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
          ListTile(
            title: Text(context.l10n.albumChooseArtistTitle),
            subtitle: Text(context.l10n.albumMultipleArtistsDetail),
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

class _AlbumTracks extends StatefulWidget {
  const _AlbumTracks({
    required this.tracks,
    required this.omittedTrackCount,
    required this.partialResultRevision,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onPlay,
    required this.onQueue,
    required this.onOpenArtist,
    required this.current,
    required this.desktop,
    super.key,
  });

  final List<PlaylistTrackSummary> tracks;
  final int omittedTrackCount;
  final int partialResultRevision;
  final bool hasMore;
  final bool isLoadingMore;
  final AlbumTrackFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<int> onPlay;
  final ValueChanged<PlaylistTrackSummary> onQueue;
  final ValueChanged<ArtistSummary>? onOpenArtist;
  final PlaylistTrackSummary? current;
  final bool desktop;

  @override
  State<_AlbumTracks> createState() => _AlbumTracksState();
}

class _AlbumTracksState extends State<_AlbumTracks> {
  (String, String)? _hoveredTrack;
  final ScrollController _scrollController = ScrollController();
  int _hoverRevision = 0;
  int? _pendingHoverClearRevision;
  bool _hoverClearScheduled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleScroll(ScrollNotification notification) {
    if (_hoveredTrack != null && notification is ScrollUpdateNotification) {
      _scheduleHoverClear();
    }
    return false;
  }

  void _scheduleHoverClear() {
    _pendingHoverClearRevision = _hoverRevision;
    if (_hoverClearScheduled) return;
    _hoverClearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hoverClearScheduled = false;
      if (!mounted) return;
      final revision = _pendingHoverClearRevision;
      _pendingHoverClearRevision = null;
      if (_hoveredTrack != null && revision == _hoverRevision) {
        _hoverRevision += 1;
        setState(() => _hoveredTrack = null);
      }
    });
  }

  void _setHovered(PlaylistTrackSummary track, bool hovered) {
    final identity = (track.providerId, track.opaqueId);
    if (hovered && _hoveredTrack != identity) {
      _hoverRevision += 1;
      setState(() => _hoveredTrack = identity);
    } else if (!hovered && _hoveredTrack == identity) {
      _hoverRevision += 1;
      setState(() => _hoveredTrack = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.desktop ? 24.0 : 10.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(
          children: [
            if (widget.omittedTrackCount > 0)
              Padding(
                padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 8),
                child: PartialResultsNotice(
                  omittedCount: widget.omittedTrackCount,
                  resultRevision: widget.partialResultRevision,
                ),
              ),
            if (widget.desktop)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                child: MusicTrackTableHeader(
                  key: const ValueKey('album-track-table-header'),
                  titleLabel: context.l10n.tableTitle,
                  artistLabel: context.l10n.tableArtist,
                  albumLabel: context.l10n.tableAlbum,
                  durationLabel: context.l10n.tableDuration,
                ),
              ),
            Expanded(
              child: MusicTrackLocatorOverlay(
                controller: _scrollController,
                currentIndex: musicTrackIndexOf(widget.tracks, widget.current),
                desktop: widget.desktop,
                child: BoundedViewportPageDemand(
                  enabled:
                      widget.hasMore &&
                      !widget.isLoadingMore &&
                      widget.appendFailure == null,
                  onDemand: widget.onLoadMore,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScroll,
                    child: ListView.separated(
                      controller: _scrollController,
                      key: const PageStorageKey('album-tracks'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        0,
                        horizontal,
                        24,
                      ),
                      itemCount: widget.tracks.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 1),
                      itemBuilder: (context, index) {
                        if (index == widget.tracks.length) {
                          return _AlbumFooter(
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
                        return MusicTrackRowSurface(
                          key: ValueKey(
                            'album-track-state-${track.providerId}-${track.opaqueId}',
                          ),
                          itemKey: ValueKey('album-track-$index'),
                          desktop: widget.desktop,
                          current: selected,
                          hovered: _hoveredTrack == identity,
                          onHoverChanged: (hovered) =>
                              _setHovered(track, hovered),
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
                                onOpenArtist:
                                    widget.onOpenArtist == null ||
                                        track.artists.isEmpty
                                    ? null
                                    : () => _openArtist(track),
                                onMore: () =>
                                    unawaited(_showActions(track, index)),
                                showInlineQueueAction: hovered,
                                queueKey: ValueKey('album-queue-$index'),
                                moreKey: ValueKey('album-context-$index'),
                                artistTooltip: track.artists.length > 1
                                    ? context.l10n.commonChooseArtist
                                    : context.l10n.commonOpenArtist,
                              ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(PlaylistTrackSummary track, int index) async {
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
            if (widget.onOpenArtist != null && track.artists.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: Text(
                  track.artists.length > 1
                      ? context.l10n.commonChooseArtist
                      : context.l10n.commonOpenArtist,
                ),
                onTap: () =>
                    Navigator.pop(context, MusicTrackAction.openArtist),
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
      case MusicTrackAction.openArtist:
        _openArtist(track);
      case MusicTrackAction.openAlbum:
      case null:
        return;
    }
  }

  void _openArtist(PlaylistTrackSummary track) {
    unawaited(
      openMusicTrackArtists(
        context: context,
        artists: track.artists,
        onSelected: widget.onOpenArtist,
        itemKeyPrefix: 'album-track-artist',
      ),
    );
  }
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
              headers: musicArtworkRequestHeaders(uri!),
              fit: BoxFit.cover,
              errorBuilder: musicArtworkErrorBuilder(uri!, placeholder),
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
              child: Text(context.l10n.commonTryLoadingMoreAgain),
            )
          : hasMore
          ? FilledButton.tonal(
              key: const ValueKey('album-load-more'),
              onPressed: onLoadMore,
              child: Text(context.l10n.commonLoadMore),
            )
          : Text(
              context.l10n.albumEnd,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

String _failureCopy(
  AppLocalizations l10n,
  AlbumTrackFailure? failure,
  String providerName,
) => switch (failure) {
  AlbumTrackFailure.network => l10n.albumFailureNetwork,
  AlbumTrackFailure.serviceUnavailable => l10n.albumFailureService(
    providerName,
  ),
  AlbumTrackFailure.cancelled => l10n.albumFailureCancelled,
  AlbumTrackFailure.coreUnavailable => l10n.catalogFailureCore,
  AlbumTrackFailure.invalidResponse ||
  AlbumTrackFailure.alreadyRunning ||
  null => l10n.albumFailureUnexpected(providerName),
};

String _detailsFailureCopy(
  AppLocalizations l10n,
  AlbumDetailsFailure? failure,
) => switch (failure) {
  AlbumDetailsFailure.network => l10n.albumDetailsFailureNetwork,
  AlbumDetailsFailure.serviceUnavailable => l10n.albumDetailsFailureService,
  AlbumDetailsFailure.cancelled => l10n.albumDetailsFailureCancelled,
  AlbumDetailsFailure.coreUnavailable => l10n.albumDetailsFailureCore,
  AlbumDetailsFailure.invalidResponse ||
  AlbumDetailsFailure.alreadyRunning ||
  null => l10n.albumDetailsFailureGeneric,
};
