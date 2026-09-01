import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/catalog/artist_artwork.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/navigation/music_section_selector.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/search/album_search_controller.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_controller.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_controller.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_controller.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';

class TrackSearchPage extends StatefulWidget {
  const TrackSearchPage({
    required this.gateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required this.onOpenPlaylist,
    required this.onSignInAgain,
    this.artistGateway,
    this.albumGateway,
    this.playlistGateway,
    this.embedded = false,
    super.key,
  });

  final TrackSearchGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final ValueChanged<AlbumSummary> onOpenAlbum;
  final ValueChanged<ArtistSummary> onOpenArtist;
  final ValueChanged<UserPlaylistSummary> onOpenPlaylist;
  final VoidCallback onSignInAgain;
  final ArtistSearchGateway? artistGateway;
  final AlbumSearchGateway? albumGateway;
  final PlaylistSearchGateway? playlistGateway;
  final bool embedded;

  @override
  State<TrackSearchPage> createState() => _TrackSearchPageState();
}

enum _SearchType { tracks, artists, albums, playlists }

class _TrackSearchPageState extends State<TrackSearchPage> {
  late final TrackSearchController _controller;
  late final ArtistSearchController _artistController;
  late final AlbumSearchController _albumController;
  late final PlaylistSearchController _playlistController;
  late final Listenable _controllers;
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocusNode = FocusNode(debugLabel: 'track search');
  final Set<_SearchType> _visitedTypes = {_SearchType.tracks};
  _SearchType _searchType = _SearchType.tracks;

  @override
  void initState() {
    super.initState();
    _controller = TrackSearchController(widget.gateway);
    _artistController = ArtistSearchController(
      widget.artistGateway ?? const RustArtistSearchGateway(),
    );
    _albumController = AlbumSearchController(
      widget.albumGateway ?? const RustAlbumSearchGateway(),
    );
    _playlistController = PlaylistSearchController(
      widget.playlistGateway ?? const RustPlaylistSearchGateway(),
    );
    _controllers = Listenable.merge([
      _controller,
      _artistController,
      _albumController,
      _playlistController,
    ]);
  }

  @override
  void dispose() {
    _controller.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _playlistController.dispose();
    _queryController.dispose();
    _queryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: AnimatedBuilder(
        animation: _controllers,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;
            return Column(
              children: [
                _SearchField(
                  controller: _queryController,
                  focusNode: _queryFocusNode,
                  desktop: desktop,
                  loading: _isLoading,
                  hintText: switch (_searchType) {
                    _SearchType.tracks => 'Song, Artist, or Album name',
                    _SearchType.artists => 'Artist name',
                    _SearchType.albums => 'Album name',
                    _SearchType.playlists => 'Playlist name',
                  },
                  onSubmitted: _submit,
                  onClear: _clear,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    desktop ? 48 : 20,
                    0,
                    desktop ? 48 : 20,
                    14,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: MusicSectionSelector<_SearchType>(
                      controlKey: const ValueKey('search-types'),
                      label: 'Search type',
                      destinations: const [
                        MusicSectionDestination(
                          value: _SearchType.tracks,
                          icon: Icons.music_note_rounded,
                          label: 'Tracks',
                          itemKey: ValueKey('search-type-tracks'),
                        ),
                        MusicSectionDestination(
                          value: _SearchType.artists,
                          icon: Icons.person_rounded,
                          label: 'Artists',
                          itemKey: ValueKey('search-type-artists'),
                        ),
                        MusicSectionDestination(
                          value: _SearchType.albums,
                          icon: Icons.album_rounded,
                          label: 'Albums',
                          itemKey: ValueKey('search-type-albums'),
                        ),
                        MusicSectionDestination(
                          value: _SearchType.playlists,
                          icon: Icons.queue_music_rounded,
                          label: 'Playlists',
                          itemKey: ValueKey('search-type-playlists'),
                        ),
                      ],
                      selected: _searchType,
                      compact: constraints.maxWidth < 680,
                      onSelected: (value) => _selectSearchType({value}),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: switch (_searchType) {
                      _SearchType.tracks => _trackBody(desktop),
                      _SearchType.artists => _artistBody(desktop),
                      _SearchType.albums => _albumBody(desktop),
                      _SearchType.playlists => _playlistBody(desktop),
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('track-search-back'),
          tooltip: 'Back to your music',
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Search QQ Music'),
      ),
      body: body,
      bottomNavigationBar: NowPlayingBar(
        controller: widget.queuePlaybackController,
        onSignInAgain: widget.onSignInAgain,
      ),
    );
  }

  bool get _isLoading => switch (_searchType) {
    _SearchType.tracks => _controller.stage == TrackSearchStage.loading,
    _SearchType.artists => _artistController.stage == ArtistSearchStage.loading,
    _SearchType.albums => _albumController.stage == AlbumSearchStage.loading,
    _SearchType.playlists =>
      _playlistController.stage == PlaylistSearchStage.loading,
  };

  Widget _trackBody(bool desktop) => switch (_controller.stage) {
    TrackSearchStage.idle => const MusicContentStatePanel(
      key: ValueKey('track-search-idle'),
      icon: Icons.search_rounded,
      title: 'Find Tracks on QQ Music',
      detail: 'Search by song, Artist, or Album name.',
    ),
    TrackSearchStage.loading => const MusicLoadingPanel(
      key: ValueKey('track-search-loading'),
      label: 'Searching QQ Music Tracks',
    ),
    TrackSearchStage.empty => MusicContentStatePanel(
      key: const ValueKey('track-search-empty'),
      icon: Icons.search_off_rounded,
      title: 'No tracks found',
      detail: 'Try a different spelling or a broader search.',
      action: TextButton(
        onPressed: _focusQuery,
        child: const Text('Edit search'),
      ),
    ),
    TrackSearchStage.error => _searchFailure(
      key: const ValueKey('track-search-error'),
      detail: _trackFailureCopy(_controller.failure),
      canRetry: _controller.canRetry,
      onRetry: _controller.retry,
      onEdit: _focusQuery,
    ),
    TrackSearchStage.content => _SearchResults(
      key: const ValueKey('track-search-content'),
      query: _controller.query,
      items: _controller.items,
      total: _controller.total,
      hasMore: _controller.hasMore,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
      onPlay: _play,
      onQueue: _queue,
      onOpenAlbum: widget.onOpenAlbum,
      onOpenArtist: widget.onOpenArtist,
      desktop: desktop,
    ),
  };

  Widget _artistBody(bool desktop) => switch (_artistController.stage) {
    ArtistSearchStage.idle => const MusicContentStatePanel(
      key: ValueKey('artist-search-idle'),
      icon: Icons.person_search_rounded,
      title: 'Find Artists on QQ Music',
      detail: 'Search by an Artist or group name.',
    ),
    ArtistSearchStage.loading => const MusicLoadingPanel(
      key: ValueKey('artist-search-loading'),
      label: 'Searching QQ Music Artists',
    ),
    ArtistSearchStage.empty => MusicContentStatePanel(
      key: const ValueKey('artist-search-empty'),
      icon: Icons.person_off_outlined,
      title: 'No Artists found',
      detail: 'Try a different spelling or a broader search.',
      action: TextButton(
        onPressed: _focusQuery,
        child: const Text('Edit search'),
      ),
    ),
    ArtistSearchStage.error => _searchFailure(
      key: const ValueKey('artist-search-error'),
      detail: _artistFailureCopy(_artistController.failure),
      canRetry: _artistController.canRetry,
      onRetry: _artistController.retry,
      onEdit: _focusQuery,
    ),
    ArtistSearchStage.content => _ArtistSearchResults(
      key: const ValueKey('artist-search-content'),
      query: _artistController.query,
      artists: _artistController.artists,
      total: _artistController.total,
      hasMore: _artistController.hasMore,
      isLoadingMore: _artistController.isLoadingMore,
      appendFailure: _artistController.appendFailure != null,
      onLoadMore: _artistController.loadMore,
      onRetryMore: _artistController.retryMore,
      onOpenArtist: widget.onOpenArtist,
      desktop: desktop,
    ),
  };

  Widget _albumBody(bool desktop) => switch (_albumController.stage) {
    AlbumSearchStage.idle => const MusicContentStatePanel(
      key: ValueKey('album-search-idle'),
      icon: Icons.album_rounded,
      title: 'Find Albums on QQ Music',
      detail: 'Search by an Album name.',
    ),
    AlbumSearchStage.loading => const MusicLoadingPanel(
      key: ValueKey('album-search-loading'),
      label: 'Searching QQ Music Albums',
    ),
    AlbumSearchStage.empty => MusicContentStatePanel(
      key: const ValueKey('album-search-empty'),
      icon: Icons.album_outlined,
      title: 'No Albums found',
      detail: 'Try a different spelling or a broader search.',
      action: TextButton(
        onPressed: _focusQuery,
        child: const Text('Edit search'),
      ),
    ),
    AlbumSearchStage.error => _searchFailure(
      key: const ValueKey('album-search-error'),
      detail: _albumFailureCopy(_albumController.failure),
      canRetry: _albumController.canRetry,
      onRetry: _albumController.retry,
      onEdit: _focusQuery,
    ),
    AlbumSearchStage.content => _AlbumSearchResults(
      key: const ValueKey('album-search-content'),
      query: _albumController.query,
      albums: _albumController.albums,
      total: _albumController.total,
      hasMore: _albumController.hasMore,
      isLoadingMore: _albumController.isLoadingMore,
      appendFailure: _albumController.appendFailure != null,
      onLoadMore: _albumController.loadMore,
      onRetryMore: _albumController.retryMore,
      onOpenAlbum: widget.onOpenAlbum,
      desktop: desktop,
    ),
  };

  Widget _playlistBody(bool desktop) => switch (_playlistController.stage) {
    PlaylistSearchStage.idle => const MusicContentStatePanel(
      key: ValueKey('playlist-search-idle'),
      icon: Icons.queue_music_rounded,
      title: 'Find Playlists on QQ Music',
      detail: 'Search by a public Playlist name.',
    ),
    PlaylistSearchStage.loading => const MusicLoadingPanel(
      key: ValueKey('playlist-search-loading'),
      label: 'Searching QQ Music Playlists',
    ),
    PlaylistSearchStage.empty => MusicContentStatePanel(
      key: const ValueKey('playlist-search-empty'),
      icon: Icons.playlist_remove_rounded,
      title: 'No Playlists found',
      detail: 'Try a different spelling or a broader search.',
      action: TextButton(
        onPressed: _focusQuery,
        child: const Text('Edit search'),
      ),
    ),
    PlaylistSearchStage.error => _searchFailure(
      key: const ValueKey('playlist-search-error'),
      detail: _playlistFailureCopy(_playlistController.failure),
      canRetry: _playlistController.canRetry,
      onRetry: _playlistController.retry,
      onEdit: _focusQuery,
    ),
    PlaylistSearchStage.content => _PlaylistSearchResults(
      key: const ValueKey('playlist-search-content'),
      query: _playlistController.query,
      playlists: _playlistController.playlists,
      total: _playlistController.total,
      hasMore: _playlistController.hasMore,
      isLoadingMore: _playlistController.isLoadingMore,
      appendFailure: _playlistController.appendFailure != null,
      onLoadMore: _playlistController.loadMore,
      onRetryMore: _playlistController.retryMore,
      onOpenPlaylist: widget.onOpenPlaylist,
      desktop: desktop,
    ),
  };

  Widget _searchFailure({
    required Key key,
    required String detail,
    required bool canRetry,
    required VoidCallback onRetry,
    required VoidCallback onEdit,
  }) => MusicContentStatePanel(
    key: key,
    icon: Icons.cloud_off_rounded,
    title: 'Couldn’t search QQ Music',
    detail: detail,
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

  void _submit(String query) {
    switch (_searchType) {
      case _SearchType.tracks:
        unawaited(_controller.submit(query));
        break;
      case _SearchType.artists:
        unawaited(_artistController.submit(query));
        break;
      case _SearchType.albums:
        unawaited(_albumController.submit(query));
        break;
      case _SearchType.playlists:
        unawaited(_playlistController.submit(query));
        break;
    }
  }

  void _selectSearchType(Set<_SearchType> selection) {
    final next = selection.single;
    if (_searchType == next) return;
    final firstVisit = !_visitedTypes.contains(next);
    final currentText = _queryController.text.trim();
    setState(() {
      _searchType = next;
      _visitedTypes.add(next);
    });
    if (firstVisit) {
      _replaceQueryText(currentText);
      if (currentText.isNotEmpty) _submit(currentText);
      return;
    }
    _replaceQueryText(switch (next) {
      _SearchType.tracks => _controller.query,
      _SearchType.artists => _artistController.query,
      _SearchType.albums => _albumController.query,
      _SearchType.playlists => _playlistController.query,
    });
  }

  void _replaceQueryText(String value) {
    _queryController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _clear() {
    _queryController.clear();
    switch (_searchType) {
      case _SearchType.tracks:
        _controller.clear();
        break;
      case _SearchType.artists:
        _artistController.clear();
        break;
      case _SearchType.albums:
        _albumController.clear();
        break;
      case _SearchType.playlists:
        _playlistController.clear();
        break;
    }
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
    required this.hintText,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool desktop;
  final bool loading;
  final String hintText;
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
              hintText: hintText,
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
    required this.items,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onPlay,
    required this.onQueue,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required this.desktop,
    super.key,
  });

  final String query;
  final List<TrackSearchItem> items;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;
  final SearchFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<int> onPlay;
  final ValueChanged<PlaylistTrackSummary> onQueue;
  final ValueChanged<AlbumSummary> onOpenAlbum;
  final ValueChanged<ArtistSummary> onOpenArtist;
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
        itemCount: items.length + 2,
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
          if (index == items.length + 1) {
            return _SearchFooter(
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              appendFailure: appendFailure != null,
              onLoadMore: onLoadMore,
              onRetryMore: onRetryMore,
            );
          }
          final trackIndex = index - 1;
          final item = items[trackIndex];
          return _SearchTrackRow(
            track: item.track,
            album: item.album,
            artists: item.artists,
            index: trackIndex,
            desktop: desktop,
            onPlay: () => onPlay(trackIndex),
            onQueue: () => onQueue(item.track),
            onOpenAlbum: item.album == null
                ? null
                : () => onOpenAlbum(item.album!),
            onOpenArtist: onOpenArtist,
          );
        },
      ),
    ),
  );
}

class _ArtistSearchResults extends StatelessWidget {
  const _ArtistSearchResults({
    required this.query,
    required this.artists,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onOpenArtist,
    required this.desktop,
    super.key,
  });

  final String query;
  final List<ArtistSummary> artists;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;
  final bool appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<ArtistSummary> onOpenArtist;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: ListView.builder(
        key: const PageStorageKey('artist-search-results'),
        padding: EdgeInsets.fromLTRB(
          desktop ? 40 : 12,
          0,
          desktop ? 40 : 12,
          24,
        ),
        itemCount: artists.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
              child: Semantics(
                header: true,
                child: Text(
                  '$total ${total == 1 ? 'Artist' : 'Artists'} for “$query”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            );
          }
          if (index == artists.length + 1) {
            return _SearchFooter(
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              appendFailure: appendFailure,
              onLoadMore: onLoadMore,
              onRetryMore: onRetryMore,
            );
          }
          final artistIndex = index - 1;
          final artist = artists[artistIndex];
          return ListTile(
            key: ValueKey('artist-search-result-$artistIndex'),
            minTileHeight: desktop ? 68 : 72,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: SizedBox.square(
              dimension: desktop ? 48 : 52,
              child: ArtistArtwork(uri: artist.artworkUri, iconSize: 24),
            ),
            title: Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Artist'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onOpenArtist(artist),
          );
        },
      ),
    ),
  );
}

class _AlbumSearchResults extends StatelessWidget {
  const _AlbumSearchResults({
    required this.query,
    required this.albums,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onOpenAlbum,
    required this.desktop,
    super.key,
  });

  final String query;
  final List<AlbumSummary> albums;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;
  final bool appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<AlbumSummary> onOpenAlbum;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: ListView.builder(
        key: const PageStorageKey('album-search-results'),
        padding: EdgeInsets.fromLTRB(
          desktop ? 40 : 12,
          0,
          desktop ? 40 : 12,
          24,
        ),
        itemCount: albums.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
              child: Semantics(
                header: true,
                child: Text(
                  '$total ${total == 1 ? 'Album' : 'Albums'} for “$query”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            );
          }
          if (index == albums.length + 1) {
            return _SearchFooter(
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              appendFailure: appendFailure,
              onLoadMore: onLoadMore,
              onRetryMore: onRetryMore,
            );
          }
          final albumIndex = index - 1;
          final album = albums[albumIndex];
          return ListTile(
            key: ValueKey('album-search-result-$albumIndex'),
            minTileHeight: desktop ? 68 : 72,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: SizedBox.square(
              dimension: desktop ? 48 : 52,
              child: _TrackArtwork(uri: album.artworkUri),
            ),
            title: Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Album'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onOpenAlbum(album),
          );
        },
      ),
    ),
  );
}

class _PlaylistSearchResults extends StatelessWidget {
  const _PlaylistSearchResults({
    required this.query,
    required this.playlists,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onOpenPlaylist,
    required this.desktop,
    super.key,
  });

  final String query;
  final List<UserPlaylistSummary> playlists;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;
  final bool appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<UserPlaylistSummary> onOpenPlaylist;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: ListView.builder(
        key: const PageStorageKey('playlist-search-results'),
        padding: EdgeInsets.fromLTRB(
          desktop ? 40 : 12,
          0,
          desktop ? 40 : 12,
          24,
        ),
        itemCount: playlists.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
              child: Semantics(
                header: true,
                child: Text(
                  '$total ${total == 1 ? 'Playlist' : 'Playlists'} for “$query”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            );
          }
          if (index == playlists.length + 1) {
            return _SearchFooter(
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              appendFailure: appendFailure,
              onLoadMore: onLoadMore,
              onRetryMore: onRetryMore,
            );
          }
          final playlistIndex = index - 1;
          final playlist = playlists[playlistIndex];
          return ListTile(
            key: ValueKey('playlist-search-result-$playlistIndex'),
            minTileHeight: desktop ? 68 : 72,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: SizedBox.square(
              dimension: desktop ? 48 : 52,
              child: _PlaylistArtwork(uri: playlist.artworkUri),
            ),
            title: Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: playlist.trackCount == null
                ? const Text('Playlist')
                : Text('${playlist.trackCount} Tracks'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onOpenPlaylist(playlist),
          );
        },
      ),
    ),
  );
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({this.uri});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.secondaryContainer, colors.primaryContainer],
        ),
      ),
      child: Icon(
        Icons.queue_music_rounded,
        color: colors.onSecondaryContainer,
      ),
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

class _SearchTrackRow extends StatelessWidget {
  const _SearchTrackRow({
    required this.track,
    required this.album,
    required this.artists,
    required this.index,
    required this.desktop,
    required this.onPlay,
    required this.onQueue,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

  final PlaylistTrackSummary track;
  final AlbumSummary? album;
  final List<ArtistSummary> artists;
  final int index;
  final bool desktop;
  final VoidCallback onPlay;
  final VoidCallback onQueue;
  final VoidCallback? onOpenAlbum;
  final ValueChanged<ArtistSummary> onOpenArtist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artistCopy = track.artistNames.isEmpty
        ? 'Unknown artist'
        : track.artistNames.join(' · ');
    final detail = [artistCopy, ?track.albumTitle].join(' · ');
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
        trailing: Wrap(
          spacing: 2,
          children: [
            if (artists.isNotEmpty)
              PopupMenuButton<ArtistSummary>(
                key: ValueKey('track-search-artist-$index'),
                tooltip: 'Browse credited Artists',
                onSelected: onOpenArtist,
                itemBuilder: (context) => [
                  for (
                    var artistIndex = 0;
                    artistIndex < artists.length;
                    artistIndex++
                  )
                    PopupMenuItem<ArtistSummary>(
                      key: ValueKey('track-search-artist-$index-$artistIndex'),
                      value: artists[artistIndex],
                      child: Text(artists[artistIndex].name),
                    ),
                ],
                icon: const Icon(Icons.person_rounded),
              ),
            if (album != null)
              IconButton(
                key: ValueKey('track-search-album-$index'),
                tooltip: 'Open ${album!.title}',
                onPressed: onOpenAlbum,
                icon: const Icon(Icons.album_rounded),
              ),
            IconButton(
              key: ValueKey('track-search-queue-$index'),
              tooltip: 'Add ${track.title} to queue',
              onPressed: onQueue,
              icon: const Icon(Icons.playlist_add_rounded),
            ),
          ],
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
  final bool appendFailure;
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
          : appendFailure
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

String _trackFailureCopy(SearchFailure? failure) => switch (failure) {
  SearchFailure.network => 'Check your connection and try again.',
  SearchFailure.serviceUnavailable =>
    'QQ Music search is temporarily unavailable.',
  SearchFailure.cancelled => 'The search was cancelled.',
  SearchFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  SearchFailure.invalidResponse ||
  SearchFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected search response.',
};

String _artistFailureCopy(SearchFailure? failure) => switch (failure) {
  SearchFailure.network => 'Check your connection and try again.',
  SearchFailure.serviceUnavailable =>
    'QQ Music Artist search is temporarily unavailable.',
  SearchFailure.cancelled => 'The Artist search was cancelled.',
  SearchFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  SearchFailure.invalidResponse ||
  SearchFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected Artist search response.',
};

String _albumFailureCopy(SearchFailure? failure) => switch (failure) {
  SearchFailure.network => 'Check your connection and try again.',
  SearchFailure.serviceUnavailable =>
    'QQ Music Album search is temporarily unavailable.',
  SearchFailure.cancelled => 'The Album search was cancelled.',
  SearchFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  SearchFailure.invalidResponse ||
  SearchFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected Album search response.',
};

String _playlistFailureCopy(SearchFailure? failure) => switch (failure) {
  SearchFailure.network => 'Check your connection and try again.',
  SearchFailure.serviceUnavailable =>
    'QQ Music Playlist search is temporarily unavailable.',
  SearchFailure.cancelled => 'The Playlist search was cancelled.',
  SearchFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  SearchFailure.invalidResponse ||
  SearchFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected Playlist search response.',
};
