import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/adaptive_confirmation.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/album/album_page.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/artist/artist_page.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlists_page.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/discover/ranking_page.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/favorite_albums_page.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_refresh_failure_banner.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_page.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_navigation.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_page.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_page.dart';

class UserLibraryPage extends StatefulWidget {
  const UserLibraryPage({
    required this.gateway,
    required this.detailGateway,
    required this.mediaResolutionGateway,
    required this.lyricGateway,
    required this.playbackQueueGateway,
    required this.audioEngine,
    required this.onSignInAgain,
    required this.onSignOut,
    this.searchGateway,
    this.artistSearchGateway,
    this.albumSearchGateway,
    this.playlistSearchGateway,
    this.albumTrackGateway,
    this.albumDetailsGateway,
    this.artistTrackGateway,
    this.artistAlbumGateway,
    this.recommendedPlaylistGateway,
    this.newAlbumGateway,
    this.newSongGateway,
    this.rankingGateway,
    this.radarGateway,
    this.favoriteAlbumGateway,
    super.key,
  });

  final UserLibraryGateway gateway;
  final PlaylistDetailGateway detailGateway;
  final MediaResolutionGateway mediaResolutionGateway;
  final LyricGateway lyricGateway;
  final PlaybackQueueGateway playbackQueueGateway;
  final ForegroundAudioEngine audioEngine;
  final VoidCallback onSignInAgain;
  final Future<CredentialSignOutResult> Function() onSignOut;
  final TrackSearchGateway? searchGateway;
  final ArtistSearchGateway? artistSearchGateway;
  final AlbumSearchGateway? albumSearchGateway;
  final PlaylistSearchGateway? playlistSearchGateway;
  final AlbumTrackGateway? albumTrackGateway;
  final AlbumDetailsGateway? albumDetailsGateway;
  final ArtistTrackGateway? artistTrackGateway;
  final ArtistAlbumGateway? artistAlbumGateway;
  final RecommendedPlaylistGateway? recommendedPlaylistGateway;
  final NewAlbumGateway? newAlbumGateway;
  final NewSongGateway? newSongGateway;
  final RankingGateway? rankingGateway;
  final RadarGateway? radarGateway;
  final FavoriteAlbumGateway? favoriteAlbumGateway;

  @override
  State<UserLibraryPage> createState() => _UserLibraryPageState();
}

class _UserLibraryPageState extends State<UserLibraryPage> {
  late final UserLibraryController _controller;
  late final QueuePlaybackController _queuePlaybackController;
  late final TrackSearchGateway _searchGateway;
  late final ArtistSearchGateway _artistSearchGateway;
  late final AlbumSearchGateway _albumSearchGateway;
  late final PlaylistSearchGateway _playlistSearchGateway;
  late final AlbumTrackGateway _albumTrackGateway;
  late final AlbumDetailsGateway _albumDetailsGateway;
  late final ArtistTrackGateway _artistTrackGateway;
  late final ArtistAlbumGateway _artistAlbumGateway;
  late final RecommendedPlaylistGateway _recommendedPlaylistGateway;
  late final NewAlbumGateway _newAlbumGateway;
  late final NewSongGateway _newSongGateway;
  late final RankingGateway _rankingGateway;
  late final RadarGateway _radarGateway;
  late final FavoriteAlbumGateway _favoriteAlbumGateway;
  final FocusNode _playlistReturnFocusNode = FocusNode(
    debugLabel: 'last opened playlist',
  );
  final FocusNode _searchReturnFocusNode = FocusNode(
    debugLabel: 'search entry',
  );
  final FocusNode _recommendationsReturnFocusNode = FocusNode(
    debugLabel: 'recommendations entry',
  );
  final FocusNode _favoriteAlbumsReturnFocusNode = FocusNode(
    debugLabel: 'favorite albums entry',
  );
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  UserPlaylistSummary? _selectedPlaylist;
  AlbumSummary? _selectedAlbum;
  AlbumSummary? _trackContextAlbum;
  ArtistSummary? _trackContextArtist;
  ArtistSummary? _albumContextArtist;
  AlbumSummary? _albumArtistContextAlbum;
  ArtistSummary? _nowPlayingContextArtist;
  AlbumSummary? _nowPlayingContextAlbum;
  ArtistSummary? _selectedArtist;
  UserPlaylistSummary? _selectedSearchPlaylist;
  RecommendedPlaylistSummary? _selectedRecommendedPlaylist;
  RankingSummary? _selectedRanking;
  UserPlaylistSummary? _lastOpenedPlaylist;
  bool _searchOpen = false;
  bool _recommendationsOpen = false;
  bool _favoriteAlbumsOpen = false;
  bool _expandedNowPlayingOpen = false;
  bool _handledLyricCredentialRejection = false;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _controller = UserLibraryController(widget.gateway);
    _searchGateway = widget.searchGateway ?? const RustTrackSearchGateway();
    _artistSearchGateway =
        widget.artistSearchGateway ?? const RustArtistSearchGateway();
    _albumSearchGateway =
        widget.albumSearchGateway ?? const RustAlbumSearchGateway();
    _playlistSearchGateway =
        widget.playlistSearchGateway ?? const RustPlaylistSearchGateway();
    _albumTrackGateway =
        widget.albumTrackGateway ?? const RustAlbumTrackGateway();
    _albumDetailsGateway =
        widget.albumDetailsGateway ?? const RustAlbumDetailsGateway();
    _artistTrackGateway =
        widget.artistTrackGateway ?? const RustArtistTrackGateway();
    _artistAlbumGateway =
        widget.artistAlbumGateway ?? const RustArtistAlbumGateway();
    _recommendedPlaylistGateway =
        widget.recommendedPlaylistGateway ??
        const RustRecommendedPlaylistGateway();
    _newAlbumGateway = widget.newAlbumGateway ?? const RustNewAlbumGateway();
    _newSongGateway = widget.newSongGateway ?? const RustNewSongGateway();
    _rankingGateway = widget.rankingGateway ?? const RustRankingGateway();
    _radarGateway = widget.radarGateway ?? RustRadarGateway();
    _favoriteAlbumGateway =
        widget.favoriteAlbumGateway ?? RustFavoriteAlbumGateway();
    _queuePlaybackController = QueuePlaybackController(
      widget.playbackQueueGateway,
      TrackPlaybackController(
        widget.mediaResolutionGateway,
        ForegroundPlaybackController(widget.audioEngine),
      ),
      lyrics: LyricController(widget.lyricGateway),
    );
    _queuePlaybackController.addListener(_onQueuePlaybackChanged);
    unawaited(_controller.load());
  }

  void _onQueuePlaybackChanged() {
    if (!mounted) return;
    if (_queuePlaybackController.lyrics?.stage !=
        LyricStage.credentialRejected) {
      _handledLyricCredentialRejection = false;
      return;
    }
    if (_handledLyricCredentialRejection) return;
    _handledLyricCredentialRejection = true;
    widget.onSignInAgain();
  }

  @override
  void dispose() {
    _controller.dispose();
    _queuePlaybackController.removeListener(_onQueuePlaybackChanged);
    _queuePlaybackController.dispose();
    _playlistReturnFocusNode.dispose();
    _searchReturnFocusNode.dispose();
    _recommendationsReturnFocusNode.dispose();
    _favoriteAlbumsReturnFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlaylist = _selectedPlaylist;
    final selectedAlbum = _selectedAlbum;
    final selectedArtist = _selectedArtist;
    final selectedSearchPlaylist = _selectedSearchPlaylist;
    final selectedRecommendedPlaylist = _selectedRecommendedPlaylist;
    final selectedRanking = _selectedRanking;
    final page = _favoriteAlbumsOpen
        ? IndexedStack(
            index: selectedAlbum == null ? 0 : 1,
            children: [
              FavoriteAlbumsPage(
                key: const ValueKey('favorite-albums-page'),
                gateway: _favoriteAlbumGateway,
                queuePlaybackController: _queuePlaybackController,
                onBack: _closeFavoriteAlbums,
                onOpenAlbum: _openFavoriteAlbum,
                onSignInAgain: widget.onSignInAgain,
              ),
              if (selectedAlbum == null)
                const SizedBox.shrink()
              else
                AlbumPage(
                  key: ValueKey(
                    'favorite-album-detail-${selectedAlbum.opaqueId}',
                  ),
                  album: selectedAlbum,
                  gateway: _albumTrackGateway,
                  detailsGateway: _albumDetailsGateway,
                  queuePlaybackController: _queuePlaybackController,
                  onBack: _returnFromFavoriteAlbum,
                  onOpenArtist: _openAlbumContextArtist,
                  backTooltip: 'Back to favorite albums',
                  onSignInAgain: widget.onSignInAgain,
                ),
            ],
          )
        : _recommendationsOpen
        ? IndexedStack(
            index: selectedRecommendedPlaylist != null
                ? 1
                : selectedRanking != null
                ? 2
                : selectedAlbum != null
                ? 3
                : 0,
            children: [
              RecommendedPlaylistsPage(
                key: const ValueKey('recommended-playlists-page'),
                gateway: _recommendedPlaylistGateway,
                newAlbumGateway: _newAlbumGateway,
                newSongGateway: _newSongGateway,
                rankingGateway: _rankingGateway,
                radarGateway: _radarGateway,
                queuePlaybackController: _queuePlaybackController,
                onBack: _closeRecommendations,
                onOpenPlaylist: _openRecommendedPlaylist,
                onOpenRanking: _openRanking,
                onOpenAlbum: _openRecommendedAlbum,
                onSignInAgain: widget.onSignInAgain,
              ),
              if (selectedRecommendedPlaylist == null)
                const SizedBox.shrink()
              else
                PlaylistDetailPage(
                  key: ValueKey(
                    'recommended-playlist-detail-'
                    '${selectedRecommendedPlaylist.opaqueId}',
                  ),
                  playlist: selectedRecommendedPlaylist.toPlaylistSummary(),
                  gateway: widget.detailGateway,
                  queuePlaybackController: _queuePlaybackController,
                  onBack: _returnToRecommendations,
                  onOpenAlbum: _openTrackContextAlbum,
                  onOpenArtist: _openTrackContextArtist,
                  onSignInAgain: widget.onSignInAgain,
                ),
              if (selectedRanking == null)
                const SizedBox.shrink()
              else
                RankingPage(
                  key: ValueKey('ranking-detail-${selectedRanking.opaqueId}'),
                  ranking: selectedRanking,
                  gateway: _rankingGateway,
                  queuePlaybackController: _queuePlaybackController,
                  onBack: _returnFromRanking,
                  onSignInAgain: widget.onSignInAgain,
                ),
              if (selectedAlbum == null)
                const SizedBox.shrink()
              else
                AlbumPage(
                  key: ValueKey('new-album-detail-${selectedAlbum.opaqueId}'),
                  album: selectedAlbum,
                  gateway: _albumTrackGateway,
                  detailsGateway: _albumDetailsGateway,
                  queuePlaybackController: _queuePlaybackController,
                  onBack: _returnFromRecommendedAlbum,
                  onOpenArtist: _openAlbumContextArtist,
                  backTooltip: 'Back to new albums',
                  onSignInAgain: widget.onSignInAgain,
                ),
            ],
          )
        : _searchOpen
        ? IndexedStack(
            index: selectedAlbum != null
                ? 1
                : selectedArtist != null
                ? 2
                : selectedSearchPlaylist != null
                ? 3
                : 0,
            children: [
              TrackSearchPage(
                key: const ValueKey('track-search-page'),
                gateway: _searchGateway,
                artistGateway: _artistSearchGateway,
                albumGateway: _albumSearchGateway,
                playlistGateway: _playlistSearchGateway,
                queuePlaybackController: _queuePlaybackController,
                onBack: _closeSearch,
                onOpenAlbum: _openAlbum,
                onOpenArtist: _openArtist,
                onOpenPlaylist: _openSearchPlaylist,
                onSignInAgain: widget.onSignInAgain,
              ),
              if (selectedAlbum == null)
                const SizedBox.shrink()
              else
                AlbumPage(
                  key: ValueKey('album-page-${selectedAlbum.opaqueId}'),
                  album: selectedAlbum,
                  gateway: _albumTrackGateway,
                  detailsGateway: _albumDetailsGateway,
                  queuePlaybackController: _queuePlaybackController,
                  onBack: _returnFromAlbum,
                  onOpenArtist: _openAlbumContextArtist,
                  backTooltip: selectedArtist == null
                      ? 'Back to search results'
                      : 'Back to Artist',
                  onSignInAgain: widget.onSignInAgain,
                ),
              if (selectedArtist == null)
                const SizedBox.shrink()
              else
                ArtistPage(
                  key: ValueKey('artist-page-${selectedArtist.opaqueId}'),
                  artist: selectedArtist,
                  gateway: _artistTrackGateway,
                  albumGateway: _artistAlbumGateway,
                  queuePlaybackController: _queuePlaybackController,
                  onBack: _returnToSearch,
                  onOpenAlbum: _openAlbum,
                  onSignInAgain: widget.onSignInAgain,
                ),
              if (selectedSearchPlaylist == null)
                const SizedBox.shrink()
              else
                PlaylistDetailPage(
                  key: ValueKey(
                    'search-playlist-detail-${selectedSearchPlaylist.opaqueId}',
                  ),
                  playlist: selectedSearchPlaylist,
                  gateway: widget.detailGateway,
                  queuePlaybackController: _queuePlaybackController,
                  onBack: _returnToSearch,
                  onOpenAlbum: _openTrackContextAlbum,
                  onOpenArtist: _openTrackContextArtist,
                  onSignInAgain: widget.onSignInAgain,
                ),
            ],
          )
        : selectedPlaylist != null
        ? PlaylistDetailPage(
            key: ValueKey('playlist-detail-${selectedPlaylist.opaqueId}'),
            playlist: selectedPlaylist,
            gateway: widget.detailGateway,
            queuePlaybackController: _queuePlaybackController,
            onBack: _returnToLibrary,
            onOpenAlbum: _openTrackContextAlbum,
            onOpenArtist: _openTrackContextArtist,
            onSignInAgain: widget.onSignInAgain,
          )
        : _libraryScaffold();
    final trackContextAlbum = _trackContextAlbum;
    final trackContextArtist = _trackContextArtist;
    final routedPage = IndexedStack(
      index: trackContextAlbum != null
          ? 2
          : trackContextArtist != null
          ? 1
          : 0,
      children: [
        page,
        if (trackContextArtist == null)
          const SizedBox.shrink()
        else
          ArtistPage(
            key: ValueKey(
              'track-context-artist-${trackContextArtist.opaqueId}',
            ),
            artist: trackContextArtist,
            gateway: _artistTrackGateway,
            albumGateway: _artistAlbumGateway,
            queuePlaybackController: _queuePlaybackController,
            onBack: _returnFromTrackContextArtist,
            onOpenAlbum: _openTrackContextAlbum,
            backTooltip: 'Back to playlist',
            onSignInAgain: widget.onSignInAgain,
          ),
        if (trackContextAlbum == null)
          const SizedBox.shrink()
        else
          AlbumPage(
            key: ValueKey('track-context-album-${trackContextAlbum.opaqueId}'),
            album: trackContextAlbum,
            gateway: _albumTrackGateway,
            detailsGateway: _albumDetailsGateway,
            queuePlaybackController: _queuePlaybackController,
            onBack: _returnFromTrackContextAlbum,
            onOpenArtist: _openAlbumContextArtist,
            backTooltip: trackContextArtist == null
                ? 'Back to playlist'
                : 'Back to Artist',
            onSignInAgain: widget.onSignInAgain,
          ),
      ],
    );
    final albumContextArtist = _albumContextArtist;
    final albumArtistContextAlbum = _albumArtistContextAlbum;
    final albumArtistRoutedPage = IndexedStack(
      index: albumArtistContextAlbum != null
          ? 2
          : albumContextArtist != null
          ? 1
          : 0,
      children: [
        routedPage,
        if (albumContextArtist == null)
          const SizedBox.shrink()
        else
          ArtistPage(
            key: ValueKey(
              'album-context-artist-${albumContextArtist.opaqueId}',
            ),
            artist: albumContextArtist,
            gateway: _artistTrackGateway,
            albumGateway: _artistAlbumGateway,
            queuePlaybackController: _queuePlaybackController,
            onBack: _returnFromAlbumContextArtist,
            onOpenAlbum: _openAlbumArtistContextAlbum,
            backTooltip: 'Back to Album',
            onSignInAgain: widget.onSignInAgain,
          ),
        if (albumArtistContextAlbum == null)
          const SizedBox.shrink()
        else
          AlbumPage(
            key: ValueKey(
              'album-artist-context-album-'
              '${albumArtistContextAlbum.opaqueId}',
            ),
            album: albumArtistContextAlbum,
            gateway: _albumTrackGateway,
            detailsGateway: _albumDetailsGateway,
            queuePlaybackController: _queuePlaybackController,
            onBack: _returnFromAlbumArtistContextAlbum,
            backTooltip: 'Back to Artist',
            onSignInAgain: widget.onSignInAgain,
          ),
      ],
    );
    final nowPlayingContextArtist = _nowPlayingContextArtist;
    final nowPlayingContextAlbum = _nowPlayingContextAlbum;
    final nowPlayingRoutedPage = IndexedStack(
      index: nowPlayingContextAlbum != null
          ? 2
          : nowPlayingContextArtist != null
          ? 1
          : 0,
      children: [
        NowPlayingCatalogNavigation(
          onOpenAlbum: _openNowPlayingAlbum,
          onOpenArtist: _openNowPlayingArtist,
          child: albumArtistRoutedPage,
        ),
        if (nowPlayingContextArtist == null)
          const SizedBox.shrink()
        else
          ArtistPage(
            key: ValueKey(
              'now-playing-artist-${nowPlayingContextArtist.opaqueId}',
            ),
            artist: nowPlayingContextArtist,
            gateway: _artistTrackGateway,
            albumGateway: _artistAlbumGateway,
            queuePlaybackController: _queuePlaybackController,
            onBack: _returnFromNowPlayingArtist,
            onOpenAlbum: _openNowPlayingArtistAlbum,
            backTooltip: 'Back to previous page',
            onSignInAgain: widget.onSignInAgain,
          ),
        if (nowPlayingContextAlbum == null)
          const SizedBox.shrink()
        else
          AlbumPage(
            key: ValueKey(
              'now-playing-album-${nowPlayingContextAlbum.opaqueId}',
            ),
            album: nowPlayingContextAlbum,
            gateway: _albumTrackGateway,
            detailsGateway: _albumDetailsGateway,
            queuePlaybackController: _queuePlaybackController,
            onBack: _returnFromNowPlayingAlbum,
            backTooltip: nowPlayingContextArtist == null
                ? 'Back to previous page'
                : 'Back to Artist',
            onSignInAgain: widget.onSignInAgain,
          ),
      ],
    );
    final expandedNowPlayingOpen = _expandedNowPlayingOpen;
    final expandedNowPlayingPage = IndexedStack(
      index: expandedNowPlayingOpen ? 1 : 0,
      children: [
        ExpandedNowPlayingNavigation(
          onOpen: _openExpandedNowPlaying,
          child: nowPlayingRoutedPage,
        ),
        if (!expandedNowPlayingOpen)
          const SizedBox.shrink()
        else
          ExpandedNowPlayingPage(
            controller: _queuePlaybackController,
            onBack: _closeExpandedNowPlaying,
            onSignInAgain: widget.onSignInAgain,
          ),
      ],
    );
    final playbackPage = PlaybackShortcuts(
      controller: _queuePlaybackController,
      child: expandedNowPlayingPage,
    );
    final hasLocalPage =
        expandedNowPlayingOpen ||
        nowPlayingContextAlbum != null ||
        nowPlayingContextArtist != null ||
        selectedPlaylist != null ||
        trackContextAlbum != null ||
        trackContextArtist != null ||
        albumContextArtist != null ||
        albumArtistContextAlbum != null ||
        _favoriteAlbumsOpen ||
        _recommendationsOpen ||
        selectedRecommendedPlaylist != null ||
        selectedRanking != null ||
        _searchOpen ||
        selectedAlbum != null ||
        selectedArtist != null ||
        selectedSearchPlaylist != null;
    final shortcutPage = !hasLocalPage
        ? playbackPage
        : CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
                  _returnFromLocalPage,
              const SingleActivator(LogicalKeyboardKey.browserBack):
                  _returnFromLocalPage,
            },
            child: playbackPage,
          );
    return PageStorage(
      bucket: _pageStorageBucket,
      child: PopScope<void>(
        canPop: !hasLocalPage,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && hasLocalPage) {
            _returnFromLocalPage();
          }
        },
        child: shortcutPage,
      ),
    );
  }

  void _returnToLibrary() {
    if (_selectedPlaylist == null) return;
    setState(() => _selectedPlaylist = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _selectedPlaylist != null ||
          _playlistReturnFocusNode.context == null) {
        return;
      }
      _playlistReturnFocusNode.requestFocus();
    });
  }

  void _returnFromLocalPage() {
    if (_expandedNowPlayingOpen) {
      _closeExpandedNowPlaying();
    } else if (_nowPlayingContextAlbum != null) {
      _returnFromNowPlayingAlbum();
    } else if (_nowPlayingContextArtist != null) {
      _returnFromNowPlayingArtist();
    } else if (_albumArtistContextAlbum != null) {
      _returnFromAlbumArtistContextAlbum();
    } else if (_albumContextArtist != null) {
      _returnFromAlbumContextArtist();
    } else if (_trackContextAlbum != null) {
      _returnFromTrackContextAlbum();
    } else if (_trackContextArtist != null) {
      _returnFromTrackContextArtist();
    } else if (_favoriteAlbumsOpen && _selectedAlbum != null) {
      _returnFromFavoriteAlbum();
    } else if (_favoriteAlbumsOpen) {
      _closeFavoriteAlbums();
    } else if (_selectedRecommendedPlaylist != null) {
      _returnToRecommendations();
    } else if (_selectedRanking != null) {
      _returnFromRanking();
    } else if (_recommendationsOpen && _selectedAlbum != null) {
      _returnFromRecommendedAlbum();
    } else if (_recommendationsOpen) {
      _closeRecommendations();
    } else if (_selectedSearchPlaylist != null) {
      _returnToSearch();
    } else if (_selectedAlbum != null) {
      _returnFromAlbum();
    } else if (_selectedArtist != null) {
      _returnToSearch();
    } else if (_searchOpen) {
      _closeSearch();
    } else {
      _returnToLibrary();
    }
  }

  void _openSearch() {
    if (_searchOpen ||
        _recommendationsOpen ||
        _favoriteAlbumsOpen ||
        _selectedPlaylist != null) {
      return;
    }
    setState(() => _searchOpen = true);
  }

  void _openRecommendations() {
    if (_recommendationsOpen ||
        _searchOpen ||
        _favoriteAlbumsOpen ||
        _selectedPlaylist != null) {
      return;
    }
    setState(() => _recommendationsOpen = true);
  }

  void _openFavoriteAlbums() {
    if (_favoriteAlbumsOpen ||
        _recommendationsOpen ||
        _searchOpen ||
        _selectedPlaylist != null) {
      return;
    }
    setState(() => _favoriteAlbumsOpen = true);
  }

  void _openTrackContextAlbum(AlbumSummary album) {
    if (_trackContextAlbum != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _trackContextAlbum = album);
  }

  void _openTrackContextArtist(ArtistSummary artist) {
    if (_trackContextAlbum != null || _trackContextArtist != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _trackContextArtist = artist);
  }

  void _returnFromTrackContextArtist() {
    if (_trackContextArtist == null) return;
    setState(() => _trackContextArtist = null);
  }

  void _returnFromTrackContextAlbum() {
    if (_trackContextAlbum == null) return;
    setState(() => _trackContextAlbum = null);
  }

  void _openAlbumContextArtist(ArtistSummary artist) {
    if (_albumContextArtist != null || _albumArtistContextAlbum != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _albumContextArtist = artist);
  }

  void _returnFromAlbumContextArtist() {
    if (_albumContextArtist == null || _albumArtistContextAlbum != null) return;
    setState(() => _albumContextArtist = null);
  }

  void _openAlbumArtistContextAlbum(AlbumSummary album) {
    if (_albumContextArtist == null || _albumArtistContextAlbum != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _albumArtistContextAlbum = album);
  }

  void _returnFromAlbumArtistContextAlbum() {
    if (_albumArtistContextAlbum == null) return;
    setState(() => _albumArtistContextAlbum = null);
  }

  void _openNowPlayingAlbum(AlbumSummary album) {
    if (_nowPlayingContextAlbum != null || _nowPlayingContextArtist != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _nowPlayingContextAlbum = album);
  }

  void _openNowPlayingArtist(ArtistSummary artist) {
    if (_nowPlayingContextAlbum != null || _nowPlayingContextArtist != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _nowPlayingContextArtist = artist);
  }

  void _openNowPlayingArtistAlbum(AlbumSummary album) {
    if (_nowPlayingContextArtist == null || _nowPlayingContextAlbum != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _nowPlayingContextAlbum = album);
  }

  void _returnFromNowPlayingAlbum() {
    if (_nowPlayingContextAlbum == null) return;
    setState(() => _nowPlayingContextAlbum = null);
  }

  void _returnFromNowPlayingArtist() {
    if (_nowPlayingContextArtist == null || _nowPlayingContextAlbum != null) {
      return;
    }
    setState(() => _nowPlayingContextArtist = null);
  }

  void _openExpandedNowPlaying() {
    if (_expandedNowPlayingOpen || _queuePlaybackController.current == null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _expandedNowPlayingOpen = true);
  }

  void _closeExpandedNowPlaying() {
    if (!_expandedNowPlayingOpen) return;
    setState(() => _expandedNowPlayingOpen = false);
  }

  void _closeFavoriteAlbums() {
    if (!_favoriteAlbumsOpen) return;
    setState(() {
      _selectedAlbum = null;
      _favoriteAlbumsOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_favoriteAlbumsOpen &&
          _favoriteAlbumsReturnFocusNode.context != null) {
        _favoriteAlbumsReturnFocusNode.requestFocus();
      }
    });
  }

  void _openFavoriteAlbum(AlbumSummary album) {
    if (!_favoriteAlbumsOpen || _selectedAlbum != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedAlbum = album);
  }

  void _returnFromFavoriteAlbum() {
    if (!_favoriteAlbumsOpen || _selectedAlbum == null) return;
    setState(() => _selectedAlbum = null);
  }

  void _closeRecommendations() {
    if (!_recommendationsOpen) return;
    setState(() {
      _selectedRecommendedPlaylist = null;
      _selectedRanking = null;
      _selectedAlbum = null;
      _recommendationsOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_recommendationsOpen &&
          _recommendationsReturnFocusNode.context != null) {
        _recommendationsReturnFocusNode.requestFocus();
      }
    });
  }

  void _openRecommendedPlaylist(RecommendedPlaylistSummary playlist) {
    if (!_recommendationsOpen ||
        _selectedRecommendedPlaylist != null ||
        _selectedRanking != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedRecommendedPlaylist = playlist);
  }

  void _returnToRecommendations() {
    if (_selectedRecommendedPlaylist == null) return;
    setState(() => _selectedRecommendedPlaylist = null);
  }

  void _openRanking(RankingSummary ranking) {
    if (!_recommendationsOpen ||
        _selectedRecommendedPlaylist != null ||
        _selectedRanking != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedRanking = ranking);
  }

  void _returnFromRanking() {
    if (_selectedRanking == null) return;
    setState(() => _selectedRanking = null);
  }

  void _openRecommendedAlbum(AlbumSummary album) {
    if (!_recommendationsOpen ||
        _selectedRecommendedPlaylist != null ||
        _selectedRanking != null ||
        _selectedAlbum != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedAlbum = album);
  }

  void _returnFromRecommendedAlbum() {
    if (!_recommendationsOpen || _selectedAlbum == null) return;
    setState(() => _selectedAlbum = null);
  }

  void _closeSearch() {
    if (!_searchOpen) return;
    setState(() {
      _selectedAlbum = null;
      _selectedArtist = null;
      _selectedSearchPlaylist = null;
      _searchOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_searchOpen && _searchReturnFocusNode.context != null) {
        _searchReturnFocusNode.requestFocus();
      }
    });
  }

  void _openAlbum(AlbumSummary album) {
    if (!_searchOpen ||
        _selectedAlbum != null ||
        _selectedSearchPlaylist != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedAlbum = album);
  }

  void _returnFromAlbum() {
    if (_selectedAlbum == null) return;
    if (_selectedArtist != null) {
      setState(() => _selectedAlbum = null);
    } else {
      _returnToSearch();
    }
  }

  void _openArtist(ArtistSummary artist) {
    if (!_searchOpen ||
        _selectedAlbum != null ||
        _selectedArtist != null ||
        _selectedSearchPlaylist != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedArtist = artist);
  }

  void _returnToSearch() {
    if (_selectedAlbum == null &&
        _selectedArtist == null &&
        _selectedSearchPlaylist == null) {
      return;
    }
    setState(() {
      _selectedAlbum = null;
      _selectedArtist = null;
      _selectedSearchPlaylist = null;
    });
  }

  void _openSearchPlaylist(UserPlaylistSummary playlist) {
    if (!_searchOpen ||
        _selectedAlbum != null ||
        _selectedArtist != null ||
        _selectedSearchPlaylist != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedSearchPlaylist = playlist);
  }

  void _openPlaylist(UserPlaylistSummary playlist) {
    setState(() {
      _lastOpenedPlaylist = playlist;
      _selectedPlaylist = playlist;
    });
  }

  Widget _libraryScaffold() => Scaffold(
    appBar: AppBar(
      title: const Text('Your music'),
      actions: [
        IconButton(
          key: const ValueKey('open-favorite-albums'),
          focusNode: _favoriteAlbumsReturnFocusNode,
          tooltip: 'Open favorite albums',
          onPressed: _openFavoriteAlbums,
          icon: const Icon(Icons.album_rounded),
        ),
        IconButton(
          key: const ValueKey('open-recommendations'),
          focusNode: _recommendationsReturnFocusNode,
          tooltip: 'Discover QQ Music playlists',
          onPressed: _openRecommendations,
          icon: const Icon(Icons.explore_rounded),
        ),
        IconButton(
          key: const ValueKey('open-track-search'),
          focusNode: _searchReturnFocusNode,
          tooltip: 'Search QQ Music',
          onPressed: _openSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => IconButton(
            tooltip: _controller.isRefreshing
                ? 'Refreshing playlists'
                : 'Refresh playlists',
            onPressed: _controller.isLoading ? null : _controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        IconButton(
          key: const ValueKey('sign-out'),
          tooltip: 'Sign out',
          onPressed: _signingOut ? null : _confirmSignOut,
          icon: const Icon(Icons.logout_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Column(
          children: [
            if (_controller.isRefreshing)
              const LinearProgressIndicator(
                key: ValueKey('user-library-refresh-progress'),
              ),
            if (_controller.refreshFailure case final failure?)
              LibraryRefreshFailureBanner(
                key: const ValueKey('user-library-refresh-failure'),
                message: _refreshFailureCopy(failure),
                canRetry: _controller.canRetryRefresh,
                onRetry: _controller.retryRefresh,
                onDismiss: _controller.dismissRefreshFailure,
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _body(context),
              ),
            ),
          ],
        ),
      ),
    ),
    bottomNavigationBar: NowPlayingBar(
      controller: _queuePlaybackController,
      onSignInAgain: widget.onSignInAgain,
    ),
  );

  Future<void> _confirmSignOut() async {
    final confirmed = await showAdaptiveConfirmation(
      context,
      title: 'Sign out on this device?',
      message:
          'This will stop playback and remove the saved QQ Music session '
          'from this device.',
      confirmLabel: 'Sign out',
      cancelKey: const ValueKey('sign-out-cancel'),
      confirmKey: const ValueKey('sign-out-confirm'),
      sheetKey: const ValueKey('sign-out-confirmation-sheet'),
      dialogKey: const ValueKey('sign-out-confirmation-dialog'),
      wrapper: (child) =>
          PlaybackShortcuts(controller: _queuePlaybackController, child: child),
    );
    if (!confirmed || !mounted) return;

    setState(() => _signingOut = true);
    final signOut = widget.onSignOut();
    await _queuePlaybackController.playback.stop();
    final result = await signOut;
    if (!mounted) return;
    setState(() => _signingOut = false);
    if (result == CredentialSignOutResult.coreUnavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t sign out. Your local session is unchanged.'),
        ),
      );
    }
  }

  Widget _body(BuildContext context) => switch (_controller.stage) {
    UserLibraryStage.loading => const _LibraryLoading(
      key: ValueKey('user-library-loading'),
    ),
    UserLibraryStage.content => _PlaylistCollection(
      key: const ValueKey('user-library-content'),
      playlists: _controller.playlists,
      onSelected: _openPlaylist,
      returnFocusPlaylist: _lastOpenedPlaylist,
      returnFocusNode: _playlistReturnFocusNode,
    ),
    UserLibraryStage.empty => const _LibraryEmpty(
      key: ValueKey('user-library-empty'),
    ),
    UserLibraryStage.error => _LibraryFailure(
      key: const ValueKey('user-library-error'),
      failure: _controller.failure,
      canRetry: _controller.canRetry,
      showSignInAgain: false,
      onRetry: _controller.retry,
      onSignInAgain: widget.onSignInAgain,
    ),
    UserLibraryStage.authenticationRequired ||
    UserLibraryStage.credentialRejected => _LibraryFailure(
      key: const ValueKey('user-library-authentication-error'),
      failure: _controller.failure,
      canRetry: false,
      showSignInAgain: true,
      onRetry: _controller.retry,
      onSignInAgain: widget.onSignInAgain,
    ),
  };
}

class _PlaylistCollection extends StatelessWidget {
  const _PlaylistCollection({
    required this.playlists,
    required this.onSelected,
    required this.returnFocusPlaylist,
    required this.returnFocusNode,
    super.key,
  });

  final List<UserPlaylistSummary> playlists;
  final ValueChanged<UserPlaylistSummary> onSelected;
  final UserPlaylistSummary? returnFocusPlaylist;
  final FocusNode returnFocusNode;

  FocusNode? _focusNodeFor(UserPlaylistSummary playlist) {
    final target = returnFocusPlaylist;
    if (target == null ||
        target.providerId != playlist.providerId ||
        target.opaqueId != playlist.opaqueId) {
      return null;
    }
    return returnFocusNode;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 760;
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
                'Your playlists',
                style:
                    (desktop
                            ? theme.textTheme.headlineMedium
                            : theme.textTheme.headlineSmall)
                        ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${playlists.length} from QQ Music',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: desktop ? 28 : 20),
              Expanded(
                child: desktop
                    ? GridView.builder(
                        key: const PageStorageKey<String>('user-playlist-grid'),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisExtent: 270,
                              crossAxisSpacing: 24,
                              mainAxisSpacing: 28,
                            ),
                        itemCount: playlists.length,
                        itemBuilder: (context, index) => _PlaylistGridItem(
                          playlist: playlists[index],
                          onTap: () => onSelected(playlists[index]),
                          focusNode: _focusNodeFor(playlists[index]),
                        ),
                      )
                    : ListView.separated(
                        key: const PageStorageKey<String>('user-playlist-list'),
                        itemCount: playlists.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _PlaylistListItem(
                          playlist: playlists[index],
                          onTap: () => onSelected(playlists[index]),
                          focusNode: _focusNodeFor(playlists[index]),
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

class _PlaylistGridItem extends StatelessWidget {
  const _PlaylistGridItem({
    required this.playlist,
    required this.onTap,
    required this.focusNode,
  });

  final UserPlaylistSummary playlist;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: _semanticLabel(playlist),
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        focusNode: focusNode,
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _PlaylistArtwork(playlist: playlist)),
            const SizedBox(height: 12),
            Text(
              playlist.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            if (playlist.trackCount case final count?) ...[
              const SizedBox(height: 4),
              Text(
                '$count tracks',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlaylistListItem extends StatelessWidget {
  const _PlaylistListItem({
    required this.playlist,
    required this.onTap,
    required this.focusNode,
  });

  final UserPlaylistSummary playlist;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: _semanticLabel(playlist),
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        focusNode: focusNode,
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 72,
                child: _PlaylistArtwork(playlist: playlist),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (playlist.trackCount case final count?) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$count tracks',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({required this.playlist});

  final UserPlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final uri = playlist.artworkUri;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: uri == null
          ? const _ArtworkPlaceholder()
          : Image.network(
              uri,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => const _ArtworkPlaceholder(),
            ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: colors.onPrimaryContainer,
          size: 38,
        ),
      ),
    );
  }
}

class _LibraryLoading extends StatelessWidget {
  const _LibraryLoading({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 44,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 20),
        Text(
          'Loading your playlists…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({super.key});

  @override
  Widget build(BuildContext context) => _CenteredLibraryMessage(
    icon: Icons.library_music_outlined,
    title: 'No playlists yet',
    detail: 'Playlists you create or save in QQ Music will appear here.',
    actions: const [],
  );
}

class _LibraryFailure extends StatelessWidget {
  const _LibraryFailure({
    required this.failure,
    required this.canRetry,
    required this.showSignInAgain,
    required this.onRetry,
    required this.onSignInAgain,
    super.key,
  });

  final UserLibraryFailure? failure;
  final bool canRetry;
  final bool showSignInAgain;
  final VoidCallback onRetry;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final (title, detail) = _failureCopy(failure);
    return _CenteredLibraryMessage(
      icon:
          failure == UserLibraryFailure.credentialRejected ||
              failure ==
                  UserLibraryFailure.credentialRejectedStorageCleanupFailed
          ? Icons.lock_reset_rounded
          : Icons.cloud_off_rounded,
      title: title,
      detail: detail,
      announce: true,
      actions: [
        if (canRetry)
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        if (showSignInAgain)
          TextButton(
            onPressed: onSignInAgain,
            child: const Text('Sign in again'),
          ),
      ],
    );
  }
}

class _CenteredLibraryMessage extends StatelessWidget {
  const _CenteredLibraryMessage({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actions,
    this.announce = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final List<Widget> actions;
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(
            icon,
            color: theme.colorScheme.onPrimaryContainer,
            size: 32,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (announce)
                Semantics(
                  container: true,
                  liveRegion: true,
                  label: '$title. $detail',
                  excludeSemantics: true,
                  child: message,
                )
              else
                message,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

(String, String) _failureCopy(UserLibraryFailure? failure) => switch (failure) {
  UserLibraryFailure.network => (
    'Couldn’t reach QQ Music',
    'Your session is still active. Check your connection and try again.',
  ),
  UserLibraryFailure.serviceUnavailable => (
    'QQ Music is unavailable',
    'Your session was kept unchanged. Try loading your playlists again later.',
  ),
  UserLibraryFailure.invalidResponse => (
    'Couldn’t read the complete library',
    'QQ Music returned a collection this build could not safely finish. '
        'No partial list is shown.',
  ),
  UserLibraryFailure.credentialRejected => (
    'Your saved session was rejected',
    'QQ Music no longer accepts it, so the stored session was removed.',
  ),
  UserLibraryFailure.credentialRejectedStorageCleanupFailed => (
    'Your saved session was rejected',
    'QQ Music no longer accepts it, but secure storage could not remove it.',
  ),
  UserLibraryFailure.authenticationRequired ||
  UserLibraryFailure.replaced ||
  UserLibraryFailure.cancelled => (
    'Sign in to load your playlists',
    'The account state changed before this library request finished.',
  ),
  UserLibraryFailure.coreUnavailable => (
    'The music core is unavailable',
    'Your library could not be loaded safely. Try again after restarting.',
  ),
  UserLibraryFailure.alreadyRunning => (
    'A library request is already running',
    'Wait for it to finish, then try again.',
  ),
  null => (
    'Couldn’t load your playlists',
    'Try again or sign in with a fresh QQ Music session.',
  ),
};

String _refreshFailureCopy(UserLibraryFailure failure) => switch (failure) {
  UserLibraryFailure.network =>
    'Couldn’t refresh playlists. Check your connection; the previous results '
        'are still shown.',
  UserLibraryFailure.serviceUnavailable =>
    'QQ Music couldn’t refresh playlists. The previous results are still '
        'shown.',
  UserLibraryFailure.invalidResponse =>
    'QQ Music returned an incomplete refresh. The previous complete results '
        'are still shown.',
  UserLibraryFailure.coreUnavailable =>
    'The music core couldn’t refresh playlists. The previous results are '
        'still shown.',
  _ => 'Couldn’t refresh playlists. The previous results are still shown.',
};

String _semanticLabel(UserPlaylistSummary playlist) {
  final count = playlist.trackCount;
  return count == null ? playlist.title : '${playlist.title}, $count tracks';
}
