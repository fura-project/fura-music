import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/catalog/artist_artwork.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/partial_results_notice.dart';
import 'package:flutterustmusic/library/favorite_artist_controller.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';
import 'package:flutterustmusic/library/library_collection_header.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/pagination/bounded_viewport_page_demand.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class FavoriteArtistsPage extends StatefulWidget {
  const FavoriteArtistsPage({
    required this.gateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onOpenArtist,
    required this.onSignInAgain,
    this.providerDisplayName = 'QQ Music',
    this.embedded = false,
    super.key,
  });

  final FavoriteArtistGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final ValueChanged<ArtistSummary> onOpenArtist;
  final VoidCallback onSignInAgain;
  final String providerDisplayName;
  final bool embedded;

  @override
  State<FavoriteArtistsPage> createState() => _FavoriteArtistsPageState();
}

class _FavoriteArtistsPageState extends State<FavoriteArtistsPage> {
  late final FavoriteArtistController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FavoriteArtistController(widget.gateway);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final body = AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: _body(context),
          );
          return Column(
            children: [
              LibraryCollectionHeader(
                key: const ValueKey('library-artists-header'),
                title: context.l10n.favoriteArtistsTitle,
                subtitle: switch (_controller.stage) {
                  FavoriteArtistStage.content ||
                  FavoriteArtistStage.empty => context.l10n.favoriteSavedCount(
                    _controller.total,
                    widget.providerDisplayName,
                  ),
                  _ => context.l10n.favoriteSavedProvider(
                    widget.providerDisplayName,
                  ),
                },
                refreshKey: widget.embedded
                    ? const ValueKey('favorite-artists-refresh')
                    : null,
                refreshTooltip: widget.embedded
                    ? _controller.isLoading
                          ? context.l10n.favoriteArtistsRefreshing
                          : context.l10n.favoriteArtistsRefresh
                    : null,
                onRefresh: widget.embedded && !_controller.isLoading
                    ? _controller.load
                    : null,
              ),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.libraryBackToPlaylists,
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(context.l10n.favoriteArtistsTitle),
        actions: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => IconButton(
              tooltip: _controller.isLoading
                  ? context.l10n.favoriteArtistsRefreshing
                  : context.l10n.favoriteArtistsRefresh,
              onPressed: _controller.isLoading ? null : _controller.load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: content,
      bottomNavigationBar: NowPlayingBar(
        controller: widget.queuePlaybackController,
        onSignInAgain: widget.onSignInAgain,
      ),
    );
  }

  Widget _body(BuildContext context) => switch (_controller.stage) {
    FavoriteArtistStage.loading => MusicLoadingPanel(
      key: const ValueKey('favorite-artists-loading'),
      label: context.l10n.favoriteArtistsLoading,
    ),
    FavoriteArtistStage.empty => MusicContentStatePanel(
      key: const ValueKey('favorite-artists-empty'),
      icon: Icons.person_outline_rounded,
      title: context.l10n.favoriteArtistsEmptyTitle,
      detail: context.l10n.favoriteArtistsEmptyDetail(
        widget.providerDisplayName,
      ),
    ),
    FavoriteArtistStage.content => _ArtistCollection(
      key: const ValueKey('favorite-artists-content'),
      artists: _controller.artists,
      omittedArtistCount: _controller.omittedArtistCount,
      partialResultRevision: _controller.partialResultRevision,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      canLoadMore: _controller.canLoadMore,
      canRetryMore: _controller.canRetryMore,
      onOpenArtist: widget.onOpenArtist,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
      providerDisplayName: widget.providerDisplayName,
    ),
    FavoriteArtistStage.error => MusicContentStatePanel(
      key: const ValueKey('favorite-artists-error'),
      icon: Icons.cloud_off_rounded,
      title: context.l10n.favoriteArtistsFailureTitle,
      detail: _failureCopy(
        context.l10n,
        _controller.failure,
        widget.providerDisplayName,
      ),
      action: _controller.canRetry
          ? FilledButton.tonal(
              onPressed: _controller.retry,
              child: Text(context.l10n.commonRetry),
            )
          : null,
      liveRegion: true,
    ),
    FavoriteArtistStage.authenticationRequired => MusicContentStatePanel(
      key: const ValueKey('favorite-artists-authentication-required'),
      icon: Icons.lock_outline_rounded,
      title: context.l10n.favoriteArtistsSignInTitle,
      detail: context.l10n.favoriteArtistsSignInDetail,
      action: TextButton(
        onPressed: widget.onSignInAgain,
        child: Text(context.l10n.authSignInAgain),
      ),
      liveRegion: true,
    ),
    FavoriteArtistStage.credentialRejected => MusicContentStatePanel(
      key: const ValueKey('favorite-artists-credential-rejected'),
      icon: Icons.lock_reset_rounded,
      title: context.l10n.favoriteSessionRejectedTitle(
        widget.providerDisplayName,
      ),
      detail:
          _controller.failure ==
              FavoriteArtistFailure.credentialRejectedStorageCleanupFailed
          ? context.l10n.favoriteSessionRejectedCleanupDetail(
              widget.providerDisplayName,
            )
          : context.l10n.favoriteSessionRejectedDetail(
              widget.providerDisplayName,
            ),
      action: TextButton(
        onPressed: widget.onSignInAgain,
        child: Text(context.l10n.authSignInAgain),
      ),
      liveRegion: true,
    ),
  };
}

class _ArtistCollection extends StatelessWidget {
  const _ArtistCollection({
    required this.artists,
    required this.omittedArtistCount,
    required this.partialResultRevision,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.canLoadMore,
    required this.canRetryMore,
    required this.onOpenArtist,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.providerDisplayName,
    super.key,
  });

  final List<ArtistSummary> artists;
  final int omittedArtistCount;
  final int partialResultRevision;
  final bool isLoadingMore;
  final FavoriteArtistFailure? appendFailure;
  final bool canLoadMore;
  final bool canRetryMore;
  final ValueChanged<ArtistSummary> onOpenArtist;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final String providerDisplayName;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 760;
        final footer = _CollectionFooter(
          isLoading: isLoadingMore,
          failure: appendFailure,
          canLoadMore: canLoadMore,
          canRetry: canRetryMore,
          onLoadMore: onLoadMore,
          onRetry: onRetryMore,
          providerDisplayName: providerDisplayName,
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(
            desktop ? MusicSpacing.pageWide : MusicSpacing.pageCompact,
            0,
            desktop ? MusicSpacing.pageWide : MusicSpacing.pageCompact,
            MusicSpacing.pageCompact,
          ),
          child: Column(
            children: [
              if (omittedArtistCount > 0) ...[
                PartialResultsNotice(
                  omittedCount: omittedArtistCount,
                  resultRevision: partialResultRevision,
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: BoundedViewportPageDemand(
                  enabled: canLoadMore,
                  onDemand: onLoadMore,
                  child: desktop
                      ? GridView.builder(
                          key: const PageStorageKey<String>(
                            'favorite-artist-grid',
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                mainAxisExtent: 210,
                                crossAxisSpacing: 24,
                                mainAxisSpacing: 28,
                              ),
                          itemCount: artists.length + 1,
                          itemBuilder: (context, index) =>
                              index == artists.length
                              ? footer
                              : _ArtistGridItem(
                                  index: index,
                                  artist: artists[index],
                                  onTap: () => onOpenArtist(artists[index]),
                                ),
                        )
                      : ListView.separated(
                          key: const PageStorageKey<String>(
                            'favorite-artist-list',
                          ),
                          itemCount: artists.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) =>
                              index == artists.length
                              ? footer
                              : _ArtistListItem(
                                  index: index,
                                  artist: artists[index],
                                  onTap: () => onOpenArtist(artists[index]),
                                ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArtistGridItem extends StatelessWidget {
  const _ArtistGridItem({
    required this.index,
    required this.artist,
    required this.onTap,
  });

  final int index;
  final ArtistSummary artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.favoriteArtistSemantics(artist.name),
    button: true,
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      key: ValueKey('favorite-artist-$index'),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Column(
        children: [
          Expanded(child: ArtistArtwork(uri: artist.artworkUri)),
          const SizedBox(height: 12),
          Text(
            artist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _ArtistListItem extends StatelessWidget {
  const _ArtistListItem({
    required this.index,
    required this.artist,
    required this.onTap,
  });

  final int index;
  final ArtistSummary artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.favoriteArtistSemantics(artist.name),
    button: true,
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      key: ValueKey('favorite-artist-$index'),
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 72,
              child: ArtistArtwork(uri: artist.artworkUri),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                artist.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

class _CollectionFooter extends StatelessWidget {
  const _CollectionFooter({
    required this.isLoading,
    required this.failure,
    required this.canLoadMore,
    required this.canRetry,
    required this.onLoadMore,
    required this.onRetry,
    required this.providerDisplayName,
  });

  final bool isLoading;
  final FavoriteArtistFailure? failure;
  final bool canLoadMore;
  final bool canRetry;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final String providerDisplayName;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (failure != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_failureCopy(context.l10n, failure, providerDisplayName)),
              if (canRetry)
                TextButton(
                  onPressed: onRetry,
                  child: Text(context.l10n.commonRetry),
                ),
            ],
          ),
        ),
      );
    }
    if (canLoadMore) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton(
            key: const ValueKey('favorite-artists-load-more'),
            onPressed: onLoadMore,
            child: Text(context.l10n.commonLoadMore),
          ),
        ),
      );
    }
    return const SizedBox(height: 12);
  }
}

String _failureCopy(
  AppLocalizations l10n,
  FavoriteArtistFailure? failure,
  String providerDisplayName,
) => switch (failure) {
  FavoriteArtistFailure.network => l10n.favoriteFailureNetwork(
    providerDisplayName,
  ),
  FavoriteArtistFailure.serviceUnavailable =>
    l10n.favoriteArtistsFailureService(providerDisplayName),
  FavoriteArtistFailure.invalidResponse => l10n.favoriteArtistsFailureInvalid(
    providerDisplayName,
  ),
  FavoriteArtistFailure.coreUnavailable => l10n.favoriteFailureCore,
  FavoriteArtistFailure.alreadyRunning => l10n.favoriteArtistsFailureRunning,
  FavoriteArtistFailure.authenticationRequired ||
  FavoriteArtistFailure.replaced ||
  FavoriteArtistFailure.cancelled => l10n.favoriteFailureSignIn,
  FavoriteArtistFailure.credentialRejected ||
  FavoriteArtistFailure.credentialRejectedStorageCleanupFailed =>
    l10n.favoriteSessionRejectedDetail(providerDisplayName),
  null => l10n.favoriteArtistsFailureTitle,
};
