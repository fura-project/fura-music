import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/library/favorite_album_controller.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

class FavoriteAlbumsPage extends StatefulWidget {
  const FavoriteAlbumsPage({
    required this.gateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onOpenAlbum,
    required this.onSignInAgain,
    super.key,
  });

  final FavoriteAlbumGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final ValueChanged<AlbumSummary> onOpenAlbum;
  final VoidCallback onSignInAgain;

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back to playlists',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Favorite albums'),
      actions: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => IconButton(
            tooltip: _controller.isLoading
                ? 'Refreshing favorite albums'
                : 'Refresh favorite albums',
            onPressed: _controller.isLoading ? null : _controller.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: _body(context),
        ),
      ),
    ),
    bottomNavigationBar: NowPlayingBar(
      controller: widget.queuePlaybackController,
      onSignInAgain: widget.onSignInAgain,
    ),
  );

  Widget _body(BuildContext context) => switch (_controller.stage) {
    FavoriteAlbumStage.loading => const Center(
      key: ValueKey('favorite-albums-loading'),
      child: CircularProgressIndicator(),
    ),
    FavoriteAlbumStage.empty => const _EmptyState(
      key: ValueKey('favorite-albums-empty'),
    ),
    FavoriteAlbumStage.content => _AlbumCollection(
      key: const ValueKey('favorite-albums-content'),
      albums: _controller.albums,
      total: _controller.total,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      canLoadMore: _controller.canLoadMore,
      canRetryMore: _controller.canRetryMore,
      onOpenAlbum: widget.onOpenAlbum,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
    ),
    FavoriteAlbumStage.error => _FailureState(
      key: const ValueKey('favorite-albums-error'),
      message: _failureCopy(_controller.failure),
      actionLabel: _controller.canRetry ? 'Try again' : null,
      onAction: _controller.canRetry ? _controller.retry : null,
    ),
    FavoriteAlbumStage.authenticationRequired => _FailureState(
      key: const ValueKey('favorite-albums-authentication-required'),
      message: 'Sign in again to load your favorite albums.',
      actionLabel: 'Sign in again',
      onAction: widget.onSignInAgain,
    ),
    FavoriteAlbumStage.credentialRejected => _FailureState(
      key: const ValueKey('favorite-albums-credential-rejected'),
      message:
          _controller.failure ==
              FavoriteAlbumFailure.credentialRejectedStorageCleanupFailed
          ? 'QQ Music rejected this session, and its saved copy could not be removed.'
          : 'QQ Music no longer accepts this saved session.',
      actionLabel: 'Sign in again',
      onAction: widget.onSignInAgain,
    ),
  };
}

class _AlbumCollection extends StatelessWidget {
  const _AlbumCollection({
    required this.albums,
    required this.total,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.canLoadMore,
    required this.canRetryMore,
    required this.onOpenAlbum,
    required this.onLoadMore,
    required this.onRetryMore,
    super.key,
  });

  final List<AlbumSummary> albums;
  final int total;
  final bool isLoadingMore;
  final FavoriteAlbumFailure? appendFailure;
  final bool canLoadMore;
  final bool canRetryMore;
  final ValueChanged<AlbumSummary> onOpenAlbum;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(
            desktop ? 48 : 20,
            desktop ? 28 : 16,
            desktop ? 48 : 20,
            20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your favorite albums',
                style:
                    (desktop
                            ? theme.textTheme.headlineMedium
                            : theme.textTheme.headlineSmall)
                        ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '$total from QQ Music',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: desktop ? 28 : 20),
              Expanded(
                child: desktop
                    ? GridView.builder(
                        key: const PageStorageKey<String>(
                          'favorite-album-grid',
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
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
                        key: const PageStorageKey<String>(
                          'favorite-album-list',
                        ),
                        itemCount: albums.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => index == albums.length
                            ? footer
                            : _AlbumListItem(
                                album: albums[index],
                                onTap: () => onOpenAlbum(albums[index]),
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

class _AlbumGridItem extends StatelessWidget {
  const _AlbumGridItem({required this.album, required this.onTap});

  final AlbumSummary album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '${album.title}, Album',
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
      label: '${album.title}, Album',
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
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
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
  });

  final bool isLoading;
  final FavoriteAlbumFailure? failure;
  final bool canLoadMore;
  final bool canRetry;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

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
              Text(_failureCopy(failure)),
              if (canRetry)
                TextButton(onPressed: onRetry, child: const Text('Try again')),
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
            child: const Text('Load more'),
          ),
        ),
      );
    }
    return const SizedBox(height: 12);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.album_outlined, size: 48),
          SizedBox(height: 16),
          Text('No favorite albums yet.'),
        ],
      ),
    ),
  );
}

class _FailureState extends StatelessWidget {
  const _FailureState({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _failureCopy(FavoriteAlbumFailure? failure) => switch (failure) {
  FavoriteAlbumFailure.network =>
    'Couldn’t reach QQ Music. Check the connection and try again.',
  FavoriteAlbumFailure.serviceUnavailable =>
    'QQ Music could not load favorite albums right now.',
  FavoriteAlbumFailure.invalidResponse =>
    'QQ Music returned an unreadable favorite-album page.',
  FavoriteAlbumFailure.coreUnavailable =>
    'The music core is unavailable. Try again.',
  FavoriteAlbumFailure.alreadyRunning =>
    'A favorite-album request is already running.',
  FavoriteAlbumFailure.authenticationRequired ||
  FavoriteAlbumFailure.replaced ||
  FavoriteAlbumFailure.cancelled => 'Sign in again to continue.',
  FavoriteAlbumFailure.credentialRejected ||
  FavoriteAlbumFailure.credentialRejectedStorageCleanupFailed =>
    'QQ Music no longer accepts this saved session.',
  null => 'Couldn’t load favorite albums.',
};
