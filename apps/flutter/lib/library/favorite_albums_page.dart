import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/library/favorite_album_controller.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/library_collection_header.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class FavoriteAlbumsPage extends StatefulWidget {
  const FavoriteAlbumsPage({
    required this.gateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onOpenAlbum,
    required this.onSignInAgain,
    this.providerDisplayName = 'QQ Music',
    this.embedded = false,
    this.showHeader = true,
    this.filterQuery = '',
    super.key,
  });

  final FavoriteAlbumGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final ValueChanged<AlbumSummary> onOpenAlbum;
  final VoidCallback onSignInAgain;
  final String providerDisplayName;
  final bool embedded;
  final bool showHeader;
  final String filterQuery;

  @override
  State<FavoriteAlbumsPage> createState() => _FavoriteAlbumsPageState();
}

class _FavoriteAlbumsPageState extends State<FavoriteAlbumsPage> {
  late final FavoriteAlbumController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FavoriteAlbumController(widget.gateway);
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
              if (widget.showHeader)
                LibraryCollectionHeader(
                  key: const ValueKey('library-albums-header'),
                  title: context.l10n.favoriteAlbumsTitle,
                  subtitle: switch (_controller.stage) {
                    FavoriteAlbumStage.content ||
                    FavoriteAlbumStage.empty => context.l10n.favoriteSavedCount(
                      _controller.total,
                      widget.providerDisplayName,
                    ),
                    _ => context.l10n.favoriteSavedProvider(
                      widget.providerDisplayName,
                    ),
                  },
                  refreshKey: widget.embedded
                      ? const ValueKey('favorite-albums-refresh')
                      : null,
                  refreshTooltip: widget.embedded
                      ? _controller.isLoading
                            ? context.l10n.favoriteAlbumsRefreshing
                            : context.l10n.favoriteAlbumsRefresh
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
        title: Text(context.l10n.favoriteAlbumsTitle),
        actions: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => IconButton(
              tooltip: _controller.isLoading
                  ? context.l10n.favoriteAlbumsRefreshing
                  : context.l10n.favoriteAlbumsRefresh,
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

  List<AlbumSummary> get _visibleAlbums {
    final query = widget.filterQuery.trim().toLowerCase();
    if (query.isEmpty) return _controller.albums;
    return _controller.albums
        .where((album) => album.title.toLowerCase().contains(query))
        .toList(growable: false);
  }

  Widget _body(BuildContext context) => switch (_controller.stage) {
    FavoriteAlbumStage.loading => MusicLoadingPanel(
      key: const ValueKey('favorite-albums-loading'),
      label: context.l10n.favoriteAlbumsLoading,
    ),
    FavoriteAlbumStage.empty => MusicContentStatePanel(
      key: const ValueKey('favorite-albums-empty'),
      icon: Icons.album_outlined,
      title: context.l10n.favoriteAlbumsEmptyTitle,
      detail: context.l10n.favoriteAlbumsEmptyDetail(
        widget.providerDisplayName,
      ),
    ),
    FavoriteAlbumStage.content
        when _visibleAlbums.isEmpty && widget.filterQuery.trim().isNotEmpty =>
      MusicContentStatePanel(
        key: const ValueKey('favorite-albums-search-empty'),
        icon: Icons.search_off_rounded,
        title: context.l10n.favoriteAlbumsSearchEmptyTitle,
        detail: context.l10n.favoriteAlbumsSearchEmptyDetail,
      ),
    FavoriteAlbumStage.content => _AlbumCollection(
      key: const ValueKey('favorite-albums-content'),
      albums: _visibleAlbums,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      canLoadMore: _controller.canLoadMore,
      canRetryMore: _controller.canRetryMore,
      onOpenAlbum: widget.onOpenAlbum,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
      providerDisplayName: widget.providerDisplayName,
    ),
    FavoriteAlbumStage.error => MusicContentStatePanel(
      key: const ValueKey('favorite-albums-error'),
      icon: Icons.cloud_off_rounded,
      title: context.l10n.favoriteAlbumsFailureTitle,
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
    FavoriteAlbumStage.authenticationRequired => MusicContentStatePanel(
      key: const ValueKey('favorite-albums-authentication-required'),
      icon: Icons.lock_outline_rounded,
      title: context.l10n.favoriteAlbumsSignInTitle,
      detail: context.l10n.favoriteAlbumsSignInDetail,
      action: TextButton(
        onPressed: widget.onSignInAgain,
        child: Text(context.l10n.authSignInAgain),
      ),
      liveRegion: true,
    ),
    FavoriteAlbumStage.credentialRejected => MusicContentStatePanel(
      key: const ValueKey('favorite-albums-credential-rejected'),
      icon: Icons.lock_reset_rounded,
      title: context.l10n.favoriteSessionRejectedTitle(
        widget.providerDisplayName,
      ),
      detail:
          _controller.failure ==
              FavoriteAlbumFailure.credentialRejectedStorageCleanupFailed
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

class _AlbumCollection extends StatelessWidget {
  const _AlbumCollection({
    required this.albums,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.canLoadMore,
    required this.canRetryMore,
    required this.onOpenAlbum,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.providerDisplayName,
    super.key,
  });

  final List<AlbumSummary> albums;
  final bool isLoadingMore;
  final FavoriteAlbumFailure? appendFailure;
  final bool canLoadMore;
  final bool canRetryMore;
  final ValueChanged<AlbumSummary> onOpenAlbum;
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
          child: desktop
              ? GridView.builder(
                  key: const PageStorageKey<String>('favorite-album-grid'),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 255,
                    crossAxisSpacing: 24,
                    mainAxisSpacing: 28,
                  ),
                  itemCount: albums.length + 1,
                  itemBuilder: (context, index) => index == albums.length
                      ? footer
                      : _AlbumGridItem(
                          album: albums[index],
                          onTap: () => onOpenAlbum(albums[index]),
                        ),
                )
              : ListView.separated(
                  key: const PageStorageKey<String>('favorite-album-list'),
                  itemCount: albums.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => index == albums.length
                      ? footer
                      : _AlbumListItem(
                          album: albums[index],
                          onTap: () => onOpenAlbum(albums[index]),
                        ),
                ),
        );
      },
    );
  }
}

class _AlbumGridItem extends StatelessWidget {
  const _AlbumGridItem({required this.album, required this.onTap});

  final AlbumSummary album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: context.l10n.favoriteAlbumSemantics(album.title),
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: ValueKey('favorite-album-${album.opaqueId}'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _AlbumArtwork(album: album)),
            const SizedBox(height: 12),
            Text(
              album.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumListItem extends StatelessWidget {
  const _AlbumListItem({required this.album, required this.onTap});

  final AlbumSummary album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: context.l10n.favoriteAlbumSemantics(album.title),
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: ValueKey('favorite-album-${album.opaqueId}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 72,
                child: _AlbumArtwork(album: album),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  album.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumArtwork extends StatelessWidget {
  const _AlbumArtwork({required this.album});

  final AlbumSummary album;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: 40,
          color: colors.onSecondaryContainer,
        ),
      ),
    );
    final uri = album.artworkUri;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: uri == null
          ? fallback
          : Image.network(
              uri,
              headers: musicArtworkRequestHeaders(uri),
              fit: BoxFit.cover,
              errorBuilder: musicArtworkErrorBuilder(uri, fallback),
            ),
    );
  }
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
  final FavoriteAlbumFailure? failure;
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
            key: const ValueKey('favorite-albums-load-more'),
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
  FavoriteAlbumFailure? failure,
  String providerDisplayName,
) => switch (failure) {
  FavoriteAlbumFailure.network => l10n.favoriteFailureNetwork(
    providerDisplayName,
  ),
  FavoriteAlbumFailure.serviceUnavailable => l10n.favoriteAlbumsFailureService(
    providerDisplayName,
  ),
  FavoriteAlbumFailure.invalidResponse => l10n.favoriteAlbumsFailureInvalid(
    providerDisplayName,
  ),
  FavoriteAlbumFailure.coreUnavailable => l10n.favoriteFailureCore,
  FavoriteAlbumFailure.alreadyRunning => l10n.favoriteAlbumsFailureRunning,
  FavoriteAlbumFailure.authenticationRequired ||
  FavoriteAlbumFailure.replaced ||
  FavoriteAlbumFailure.cancelled => l10n.favoriteFailureSignIn,
  FavoriteAlbumFailure.credentialRejected ||
  FavoriteAlbumFailure.credentialRejectedStorageCleanupFailed =>
    l10n.favoriteSessionRejectedDetail(providerDisplayName),
  null => l10n.favoriteAlbumsFailureTitle,
};
