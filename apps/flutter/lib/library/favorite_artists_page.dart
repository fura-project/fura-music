import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/catalog/artist_artwork.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/library/favorite_artist_controller.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';
import 'package:flutterustmusic/library/library_collection_header.dart';
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
    this.embedded = false,
    super.key,
  });

  final FavoriteArtistGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final ValueChanged<ArtistSummary> onOpenArtist;
  final VoidCallback onSignInAgain;
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
                title: 'Your favorite artists',
                subtitle: switch (_controller.stage) {
                  FavoriteArtistStage.content || FavoriteArtistStage.empty =>
                    '${_controller.total} saved on QQ Music',
                  _ => 'Saved on QQ Music',
                },
                refreshKey: widget.embedded
                    ? const ValueKey('favorite-artists-refresh')
                    : null,
                refreshTooltip: widget.embedded
                    ? _controller.isLoading
                          ? 'Refreshing favorite artists'
                          : 'Refresh favorite artists'
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
          tooltip: 'Back to playlists',
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Favorite artists'),
        actions: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => IconButton(
              tooltip: _controller.isLoading
                  ? 'Refreshing favorite artists'
                  : 'Refresh favorite artists',
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
    FavoriteArtistStage.loading => const MusicLoadingPanel(
      key: ValueKey('favorite-artists-loading'),
      label: 'Loading Favorite Artists',
    ),
    FavoriteArtistStage.empty => const MusicContentStatePanel(
      key: ValueKey('favorite-artists-empty'),
      icon: Icons.person_outline_rounded,
      title: 'No favorite artists yet',
      detail: 'Artists you follow in QQ Music will appear here.',
    ),
    FavoriteArtistStage.content => _ArtistCollection(
      key: const ValueKey('favorite-artists-content'),
      artists: _controller.artists,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      canLoadMore: _controller.canLoadMore,
      canRetryMore: _controller.canRetryMore,
      onOpenArtist: widget.onOpenArtist,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
    ),
    FavoriteArtistStage.error => MusicContentStatePanel(
      key: const ValueKey('favorite-artists-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load favorite artists',
      detail: _failureCopy(_controller.failure),
      action: _controller.canRetry
          ? FilledButton.tonal(
              onPressed: _controller.retry,
              child: const Text('Try again'),
            )
          : null,
      liveRegion: true,
    ),
    FavoriteArtistStage.authenticationRequired => MusicContentStatePanel(
      key: const ValueKey('favorite-artists-authentication-required'),
      icon: Icons.lock_outline_rounded,
      title: 'Sign in to see favorite artists',
      detail: 'Sign in again to load your favorite artists.',
      action: TextButton(
        onPressed: widget.onSignInAgain,
        child: const Text('Sign in again'),
      ),
      liveRegion: true,
    ),
    FavoriteArtistStage.credentialRejected => MusicContentStatePanel(
      key: const ValueKey('favorite-artists-credential-rejected'),
      icon: Icons.lock_reset_rounded,
      title: 'QQ Music session rejected',
      detail:
          _controller.failure ==
              FavoriteArtistFailure.credentialRejectedStorageCleanupFailed
          ? 'QQ Music rejected this session, and its saved copy could not be removed.'
          : 'QQ Music no longer accepts this saved session.',
      action: TextButton(
        onPressed: widget.onSignInAgain,
        child: const Text('Sign in again'),
      ),
      liveRegion: true,
    ),
  };
}

class _ArtistCollection extends StatelessWidget {
  const _ArtistCollection({
    required this.artists,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.canLoadMore,
    required this.canRetryMore,
    required this.onOpenArtist,
    required this.onLoadMore,
    required this.onRetryMore,
    super.key,
  });

  final List<ArtistSummary> artists;
  final bool isLoadingMore;
  final FavoriteArtistFailure? appendFailure;
  final bool canLoadMore;
  final bool canRetryMore;
  final ValueChanged<ArtistSummary> onOpenArtist;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;

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
                  key: const PageStorageKey<String>('favorite-artist-grid'),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 210,
                    crossAxisSpacing: 24,
                    mainAxisSpacing: 28,
                  ),
                  itemCount: artists.length + 1,
                  itemBuilder: (context, index) => index == artists.length
                      ? footer
                      : _ArtistGridItem(
                          index: index,
                          artist: artists[index],
                          onTap: () => onOpenArtist(artists[index]),
                        ),
                )
              : ListView.separated(
                  key: const PageStorageKey<String>('favorite-artist-list'),
                  itemCount: artists.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => index == artists.length
                      ? footer
                      : _ArtistListItem(
                          index: index,
                          artist: artists[index],
                          onTap: () => onOpenArtist(artists[index]),
                        ),
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
    label: '${artist.name}, Artist',
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
    label: '${artist.name}, Artist',
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
  });

  final bool isLoading;
  final FavoriteArtistFailure? failure;
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
            key: const ValueKey('favorite-artists-load-more'),
            onPressed: onLoadMore,
            child: const Text('Load more'),
          ),
        ),
      );
    }
    return const SizedBox(height: 12);
  }
}

String _failureCopy(FavoriteArtistFailure? failure) => switch (failure) {
  FavoriteArtistFailure.network =>
    'Couldn’t reach QQ Music. Check the connection and try again.',
  FavoriteArtistFailure.serviceUnavailable =>
    'QQ Music could not load favorite artists right now.',
  FavoriteArtistFailure.invalidResponse =>
    'QQ Music returned an unreadable favorite-Artist page.',
  FavoriteArtistFailure.coreUnavailable =>
    'The music core is unavailable. Try again.',
  FavoriteArtistFailure.alreadyRunning =>
    'A favorite-Artist request is already running.',
  FavoriteArtistFailure.authenticationRequired ||
  FavoriteArtistFailure.replaced ||
  FavoriteArtistFailure.cancelled => 'Sign in again to continue.',
  FavoriteArtistFailure.credentialRejected ||
  FavoriteArtistFailure.credentialRejectedStorageCleanupFailed =>
    'QQ Music no longer accepts this saved session.',
  null => 'Couldn’t load favorite artists.',
};
