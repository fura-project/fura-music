import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/adaptive_confirmation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/album/album_page.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/artist/artist_page.dart';
import 'package:flutterustmusic/authenticated_dependencies.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/discover/radar_controller.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/discover/new_song_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlists_page.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/discover/ranking_page.dart';
import 'package:flutterustmusic/home/home_controller.dart';
import 'package:flutterustmusic/home/home_page.dart';
import 'package:flutterustmusic/library/favorite_albums_page.dart';
import 'package:flutterustmusic/library/favorite_artists_page.dart';
import 'package:flutterustmusic/library/library_section_selector.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_collection_header.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_refresh_failure_banner.dart';
import 'package:flutterustmusic/library/liked_songs_page.dart';
import 'package:flutterustmusic/library/playlist_detail_page.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/navigation/authenticated_navigation_state.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_navigation.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_page.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/search/track_search_page.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

bool _radarRequiresSignIn(RadarFailure? failure) =>
    failure == RadarFailure.authenticationRequired ||
    failure == RadarFailure.credentialRejected ||
    failure == RadarFailure.credentialRejectedStorageCleanupFailed;

class UserLibraryPage extends StatefulWidget {
  const UserLibraryPage({
    required this.homeDependencies,
    required this.libraryDependencies,
    required this.discoveryDependencies,
    required this.playbackDependencies,
    required this.authenticated,
    required this.onRequestSignIn,
    required this.onSignInAgain,
    required this.onSignOut,
    super.key,
  });

  final AuthenticatedHomeDependencies homeDependencies;
  final AuthenticatedLibraryDependencies libraryDependencies;
  final AuthenticatedDiscoveryDependencies discoveryDependencies;
  final AuthenticatedPlaybackDependencies playbackDependencies;
  final bool authenticated;
  final VoidCallback onRequestSignIn;
  final VoidCallback onSignInAgain;
  final Future<CredentialSignOutResult> Function() onSignOut;

  @override
  State<UserLibraryPage> createState() => _UserLibraryPageState();
}

class _ExpandedNowPlayingRouteTransition extends StatefulWidget {
  const _ExpandedNowPlayingRouteTransition({
    required this.open,
    required this.base,
    required this.detail,
  });

  final bool open;
  final Widget base;
  final Widget detail;

  @override
  State<_ExpandedNowPlayingRouteTransition> createState() =>
      _ExpandedNowPlayingRouteTransitionState();
}

class _ExpandedNowPlayingRouteTransitionState
    extends State<_ExpandedNowPlayingRouteTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: widget.open ? 1 : 0,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 280),
    );
    _position = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: Easing.emphasizedDecelerate,
            reverseCurve: Easing.emphasizedAccelerate,
          ),
        );
  }

  @override
  void didUpdateWidget(_ExpandedNowPlayingRouteTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    if (widget.open) {
      unawaited(_controller.forward());
    } else {
      unawaited(_controller.reverse());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    key: const ValueKey('expanded-now-playing-transition'),
    animation: _controller,
    builder: (context, _) {
      final detailVisible = !_controller.isDismissed;
      final baseCovered = _controller.isCompleted;
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          Offstage(
            offstage: baseCovered,
            child: ExcludeSemantics(
              excluding: widget.open,
              child: ExcludeFocus(
                excluding: widget.open,
                child: IgnorePointer(ignoring: widget.open, child: widget.base),
              ),
            ),
          ),
          if (detailVisible)
            ExcludeSemantics(
              excluding: !widget.open,
              child: ExcludeFocus(
                excluding: !widget.open,
                child: IgnorePointer(
                  ignoring: !widget.open,
                  child: SlideTransition(
                    key: const ValueKey('expanded-now-playing-transition-page'),
                    position: _position,
                    child: widget.detail,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _UserLibraryPageState extends State<UserLibraryPage> {
  late final UserLibraryController _controller;
  late final HomeController _homeController;
  late final QueuePlaybackController _queuePlaybackController;
  late final ArtworkColorSchemeCache _expandedNowPlayingPalette;
  late final RecommendedPlaylistController _recommendedPlaylistController;
  late final NewSongController _guestNewSongController;
  late final RadarController _homeRadarController;
  final FocusNode _playlistReturnFocusNode = FocusNode(
    debugLabel: 'last opened playlist',
  );
  final FocusNode _searchReturnFocusNode = FocusNode(
    debugLabel: 'search entry',
  );
  final FocusNode _recommendationsReturnFocusNode = FocusNode(
    debugLabel: 'recommendations entry',
  );
  final FocusNode _homeRecommendationReturnFocusNode = FocusNode(
    debugLabel: 'last Home recommendation',
  );
  final FocusScopeNode _librarySectionFocusScopeNode = FocusScopeNode(
    debugLabel: 'library section selector',
  );
  final FocusNode _backShortcutFallbackFocusNode = FocusNode(
    debugLabel: 'authenticated back shortcut fallback',
  );
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  final AuthenticatedNavigationState _navigation =
      AuthenticatedNavigationState();
  UserPlaylistSummary? _lastOpenedPlaylist;
  RecommendedPlaylistSummary? _lastOpenedHomeRecommendation;
  bool _handledLyricCredentialRejection = false;
  bool _handledHomeCredentialRejection = false;
  bool _signingOut = false;
  bool _overlayPageActive = false;
  String? _prefetchedArtworkUri;
  Brightness? _prefetchedArtworkBrightness;

  @override
  void initState() {
    super.initState();
    _controller = UserLibraryController(_library.libraryGateway);
    _homeController = HomeController(
      _home.accountSummaryGateway,
      _home.dailyRecommendationGateway,
      _home.personalizedPlaylistsGateway,
      _home.personalizedTracksGateway,
      _home.relatedTracksGateway,
    );
    _recommendedPlaylistController = RecommendedPlaylistController(
      _discovery.recommendedPlaylistGateway,
    );
    _guestNewSongController = NewSongController(_discovery.newSongGateway);
    _homeRadarController = RadarController(_discovery.radarGateway);
    _queuePlaybackController = QueuePlaybackController(
      _playback.playbackQueueGateway,
      TrackPlaybackController(
        _playback.mediaResolutionGateway,
        ForegroundPlaybackController(_playback.audioEngine),
      ),
      lyrics: LyricController(_playback.lyricGateway),
    );
    _expandedNowPlayingPalette = ArtworkColorSchemeCache();
    _playback.systemPlaybackBinding.attach(_queuePlaybackController);
    _queuePlaybackController.addListener(_onQueuePlaybackChanged);
    _homeController.updateRelatedSeed(_queuePlaybackController.current);
    _homeController.addListener(_onHomeChanged);
    _homeRadarController.addListener(_onHomeChanged);
    unawaited(_recommendedPlaylistController.load());
    if (!widget.authenticated) {
      unawaited(_guestNewSongController.load());
    }
    if (widget.authenticated) {
      unawaited(_controller.load());
      unawaited(_homeController.load());
      unawaited(_homeRadarController.load());
    }
  }

  AuthenticatedHomeDependencies get _home => widget.homeDependencies;
  AuthenticatedLibraryDependencies get _library => widget.libraryDependencies;
  AuthenticatedDiscoveryDependencies get _discovery =>
      widget.discoveryDependencies;
  AuthenticatedPlaybackDependencies get _playback =>
      widget.playbackDependencies;

  void _onQueuePlaybackChanged() {
    if (!mounted) return;
    _prefetchExpandedNowPlayingPalette();
    _homeController.updateRelatedSeed(_queuePlaybackController.current);
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prefetchExpandedNowPlayingPalette();
  }

  void _prefetchExpandedNowPlayingPalette() {
    if (!mounted) return;
    final artworkUri = _queuePlaybackController.current?.artworkUri;
    if (artworkUri == null) {
      _prefetchedArtworkUri = null;
      _prefetchedArtworkBrightness = null;
      return;
    }
    final brightness = Theme.of(context).brightness;
    if (_prefetchedArtworkUri == artworkUri &&
        _prefetchedArtworkBrightness == brightness) {
      return;
    }
    _prefetchedArtworkUri = artworkUri;
    _prefetchedArtworkBrightness = brightness;
    unawaited(
      _expandedNowPlayingPalette.resolve(
        artworkUri: artworkUri,
        brightness: brightness,
      ),
    );
  }

  void _onHomeChanged() {
    if (!mounted) return;
    if (!_homeController.requiresSignIn &&
        !_radarRequiresSignIn(_homeRadarController.failure)) {
      _handledHomeCredentialRejection = false;
      return;
    }
    if (_handledHomeCredentialRejection) return;
    _handledHomeCredentialRejection = true;
    widget.onSignInAgain();
  }

  @override
  void dispose() {
    _controller.dispose();
    _homeController.removeListener(_onHomeChanged);
    _homeController.dispose();
    _recommendedPlaylistController.dispose();
    _guestNewSongController.dispose();
    _homeRadarController.removeListener(_onHomeChanged);
    _homeRadarController.dispose();
    _queuePlaybackController.removeListener(_onQueuePlaybackChanged);
    _playback.systemPlaybackBinding.detach(_queuePlaybackController);
    _queuePlaybackController.dispose();
    _playlistReturnFocusNode.dispose();
    _searchReturnFocusNode.dispose();
    _recommendationsReturnFocusNode.dispose();
    _homeRecommendationReturnFocusNode.dispose();
    _librarySectionFocusScopeNode.dispose();
    _backShortcutFallbackFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routes = _navigation.routes;
    final expandedNowPlayingOpen =
        routes.isNotEmpty && routes.last is ExpandedNowPlayingLocalRoute;
    final retainedRoutes = expandedNowPlayingOpen
        ? routes.sublist(0, routes.length - 1)
        : routes;
    final nowPlayingRouteIndex = retainedRoutes.indexWhere(_isNowPlayingRoute);
    final catalogRoutes = nowPlayingRouteIndex < 0
        ? retainedRoutes
        : retainedRoutes.sublist(0, nowPlayingRouteIndex);
    final nowPlayingRoutes = nowPlayingRouteIndex < 0
        ? const <AuthenticatedLocalRoute>[]
        : retainedRoutes.sublist(nowPlayingRouteIndex);
    final catalogPages = <Widget>[
      _primaryScaffold(),
      ...catalogRoutes.map(_buildLocalRoute),
    ];
    final catalogRoutePage = IndexedStack(
      index: catalogPages.length - 1,
      children: catalogPages,
    );
    final nowPlayingPages = <Widget>[
      NowPlayingCatalogNavigation(
        onOpenAlbum: _openNowPlayingAlbum,
        onOpenArtist: _openNowPlayingArtist,
        child: catalogRoutePage,
      ),
      ...nowPlayingRoutes.map(_buildLocalRoute),
    ];
    final retainedRoutePage = IndexedStack(
      index: nowPlayingPages.length - 1,
      children: nowPlayingPages,
    );
    final retainedRouteSurface = ExpandedNowPlayingNavigation(
      onOpen: _openExpandedNowPlaying,
      child: retainedRoutePage,
    );
    final expandedNowPlayingPage = _ExpandedNowPlayingRouteTransition(
      open: expandedNowPlayingOpen,
      base: retainedRouteSurface,
      detail: ExpandedNowPlayingPage(
        controller: _queuePlaybackController,
        onBack: _closeExpandedNowPlaying,
        onSignInAgain: widget.onSignInAgain,
        commentsGateway: _playback.trackCommentGateway,
        artworkColorSchemeCache: _expandedNowPlayingPalette,
      ),
    );
    final hasOverlayPage = _hasOverlayPage;
    final hasLibrarySubsection = _hasLibrarySubsection;
    final hasPrimaryPeer =
        _primaryDestination != AuthenticatedPrimaryDestination.home;
    final hasLocalPage =
        hasOverlayPage || hasLibrarySubsection || hasPrimaryPeer;
    if (hasOverlayPage && !_overlayPageActive) {
      WidgetsBinding.instance.addPostFrameCallback(
        _restoreBackShortcutFallbackFocus,
      );
    }
    _overlayPageActive = hasOverlayPage;
    final shortcutPage = PlaybackShortcuts(
      controller: _queuePlaybackController,
      child: Focus(
        focusNode: _backShortcutFallbackFocusNode,
        skipTraversal: true,
        onKeyEvent: _handleBackKey,
        child: expandedNowPlayingPage,
      ),
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

  Widget _buildLocalRoute(AuthenticatedLocalRoute route) => switch (route) {
    PlaylistLocalRoute() => PlaylistDetailPage(
      key: ValueKey(_playlistRouteKey(route)),
      playlist: route.playlist,
      gateway: _library.playlistDetailGateway,
      queuePlaybackController: _queuePlaybackController,
      onBack: _returnFromTopRoute,
      onOpenAlbum: _openTrackContextAlbum,
      onOpenArtist: _openTrackContextArtist,
      onSignInAgain: widget.onSignInAgain,
    ),
    RankingLocalRoute() => RankingPage(
      key: ValueKey('ranking-detail-${route.ranking.opaqueId}'),
      ranking: route.ranking,
      gateway: _discovery.rankingGateway,
      queuePlaybackController: _queuePlaybackController,
      onBack: _returnFromTopRoute,
      onOpenAlbum: _openTrackContextAlbum,
      onOpenArtist: _openTrackContextArtist,
      onSignInAgain: widget.onSignInAgain,
    ),
    ArtistLocalRoute() => ArtistPage(
      key: ValueKey(_artistRouteKey(route)),
      artist: route.artist,
      gateway: _library.artistTrackGateway,
      albumGateway: _library.artistAlbumGateway,
      queuePlaybackController: _queuePlaybackController,
      onBack: _returnFromTopRoute,
      onOpenAlbum: (album) => _openAlbumFromArtist(route.origin, album),
      backTooltip: _artistBackTooltip(route.origin),
      onSignInAgain: widget.onSignInAgain,
    ),
    AlbumLocalRoute() => AlbumPage(
      key: ValueKey(_albumRouteKey(route)),
      album: route.album,
      gateway: _library.albumTrackGateway,
      detailsGateway: _library.albumDetailsGateway,
      queuePlaybackController: _queuePlaybackController,
      onBack: _returnFromTopRoute,
      onOpenArtist: _albumCanOpenArtist(route.origin)
          ? _openAlbumContextArtist
          : null,
      backTooltip: _albumBackTooltip(route.origin),
      onSignInAgain: widget.onSignInAgain,
    ),
    ExpandedNowPlayingLocalRoute() => const SizedBox.shrink(),
  };

  bool _isNowPlayingRoute(AuthenticatedLocalRoute route) => switch (route) {
    ArtistLocalRoute(origin: ArtistRouteOrigin.nowPlaying) => true,
    AlbumLocalRoute(
      origin: AlbumRouteOrigin.nowPlaying || AlbumRouteOrigin.nowPlayingArtist,
    ) =>
      true,
    _ => false,
  };

  String _playlistRouteKey(PlaylistLocalRoute route) => switch (route.origin) {
    PlaylistRouteOrigin.search =>
      'search-playlist-detail-${route.playlist.opaqueId}',
    PlaylistRouteOrigin.discover || PlaylistRouteOrigin.homeRecommendation =>
      'recommended-playlist-detail-${route.playlist.opaqueId}',
    PlaylistRouteOrigin.library || PlaylistRouteOrigin.homeLibrary =>
      'playlist-detail-${route.playlist.opaqueId}',
  };

  String _artistRouteKey(ArtistLocalRoute route) => switch (route.origin) {
    ArtistRouteOrigin.search => 'artist-page-${route.artist.opaqueId}',
    ArtistRouteOrigin.favoriteArtists =>
      'favorite-artist-detail-${route.artist.opaqueId}',
    ArtistRouteOrigin.trackContext =>
      'track-context-artist-${route.artist.opaqueId}',
    ArtistRouteOrigin.album => 'album-context-artist-${route.artist.opaqueId}',
    ArtistRouteOrigin.nowPlaying =>
      'now-playing-artist-${route.artist.opaqueId}',
  };

  String _artistBackTooltip(ArtistRouteOrigin origin) => switch (origin) {
    ArtistRouteOrigin.search => 'Back',
    ArtistRouteOrigin.favoriteArtists => 'Back to favorite artists',
    ArtistRouteOrigin.trackContext => 'Back to playlist',
    ArtistRouteOrigin.album => 'Back to Album',
    ArtistRouteOrigin.nowPlaying => 'Back to previous page',
  };

  String _albumRouteKey(AlbumLocalRoute route) => switch (route.origin) {
    AlbumRouteOrigin.search ||
    AlbumRouteOrigin.searchArtist => 'album-page-${route.album.opaqueId}',
    AlbumRouteOrigin.discover => 'new-album-detail-${route.album.opaqueId}',
    AlbumRouteOrigin.favoriteAlbums =>
      'favorite-album-detail-${route.album.opaqueId}',
    AlbumRouteOrigin.favoriteArtist =>
      'favorite-artist-album-${route.album.opaqueId}',
    AlbumRouteOrigin.trackContext || AlbumRouteOrigin.trackContextArtist =>
      'track-context-album-${route.album.opaqueId}',
    AlbumRouteOrigin.albumArtist =>
      'album-artist-context-album-${route.album.opaqueId}',
    AlbumRouteOrigin.nowPlaying || AlbumRouteOrigin.nowPlayingArtist =>
      'now-playing-album-${route.album.opaqueId}',
  };

  String _albumBackTooltip(AlbumRouteOrigin origin) => switch (origin) {
    AlbumRouteOrigin.search => 'Back to search results',
    AlbumRouteOrigin.searchArtist ||
    AlbumRouteOrigin.favoriteArtist ||
    AlbumRouteOrigin.trackContextArtist ||
    AlbumRouteOrigin.albumArtist ||
    AlbumRouteOrigin.nowPlayingArtist => 'Back to Artist',
    AlbumRouteOrigin.discover => 'Back to new albums',
    AlbumRouteOrigin.favoriteAlbums => 'Back to favorite albums',
    AlbumRouteOrigin.trackContext => 'Back to playlist',
    AlbumRouteOrigin.nowPlaying => 'Back to previous page',
  };

  bool _albumCanOpenArtist(AlbumRouteOrigin origin) =>
      origin != AlbumRouteOrigin.albumArtist &&
      origin != AlbumRouteOrigin.nowPlaying &&
      origin != AlbumRouteOrigin.nowPlayingArtist;

  void _returnFromLocalPage() {
    if (!_navigation.canGoBack) return;
    final previousPrimary = _primaryDestination;
    late final AuthenticatedBackResult result;
    setState(() => result = _navigation.goBack());
    _restoreFocusAfterBack(result, previousPrimary: previousPrimary);
  }

  void _returnFromTopRoute() {
    if (!_navigation.hasLocalRoute) return;
    final previousPrimary = _primaryDestination;
    late final AuthenticatedLocalRoute route;
    setState(() => route = _navigation.popRoute()!);
    _restoreFocusAfterBack(
      AuthenticatedBackResult.localRoute(route),
      previousPrimary: previousPrimary,
    );
  }

  void _restoreFocusAfterBack(
    AuthenticatedBackResult result, {
    required AuthenticatedPrimaryDestination previousPrimary,
  }) {
    switch (result.target) {
      case AuthenticatedBackTarget.none:
        return;
      case AuthenticatedBackTarget.libraryPlaylists:
        _restoreLibrarySectionFocus();
        return;
      case AuthenticatedBackTarget.home:
        final focusNode = switch (previousPrimary) {
          AuthenticatedPrimaryDestination.search => _searchReturnFocusNode,
          AuthenticatedPrimaryDestination.discover =>
            _recommendationsReturnFocusNode,
          _ => null,
        };
        if (focusNode != null) _restoreFocusNode(focusNode);
        return;
      case AuthenticatedBackTarget.localRoute:
        final focusNode = switch (result.route) {
          PlaylistLocalRoute(origin: PlaylistRouteOrigin.library) =>
            _playlistReturnFocusNode,
          PlaylistLocalRoute(origin: PlaylistRouteOrigin.homeLibrary) =>
            _playlistReturnFocusNode,
          PlaylistLocalRoute(origin: PlaylistRouteOrigin.homeRecommendation) =>
            _homeRecommendationReturnFocusNode,
          _ => null,
        };
        if (focusNode != null) _restoreFocusNode(focusNode);
        return;
    }
  }

  void _restoreFocusNode(FocusNode focusNode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && focusNode.context != null) focusNode.requestFocus();
    });
  }

  bool get _hasOverlayPage => _navigation.hasLocalRoute;

  bool get _hasLibrarySubsection => _navigation.hasLibrarySubsection;

  void _restoreBackShortcutFallbackFocus(Duration _) {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        !_hasOverlayPage) {
      return;
    }
    _backShortcutFallbackFocusNode.requestFocus();
  }

  KeyEventResult _handleBackKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final isBack = event.logicalKey == LogicalKeyboardKey.browserBack;
    final isAltLeft =
        event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isShiftPressed;
    if (!isBack && !isAltLeft) return KeyEventResult.ignored;
    if (_hasOverlayPage) {
      _returnFromLocalPage();
      return KeyEventResult.handled;
    }
    if (_hasLibrarySubsection) {
      _selectLibrarySection(LibrarySection.playlists);
      return KeyEventResult.handled;
    }
    if (_primaryDestination != AuthenticatedPrimaryDestination.home) {
      _selectPrimaryDestination(AuthenticatedPrimaryDestination.home);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  AuthenticatedPrimaryDestination get _primaryDestination =>
      _navigation.primaryDestination;

  bool get _searchOpen =>
      _primaryDestination == AuthenticatedPrimaryDestination.search;

  bool get _recommendationsOpen =>
      _primaryDestination == AuthenticatedPrimaryDestination.discover;

  void _selectPrimaryDestination(AuthenticatedPrimaryDestination destination) {
    if (_navigation.hasLocalRoute || _primaryDestination == destination) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _navigation.selectPrimaryDestination(destination));
  }

  LibrarySection get _librarySection => _navigation.librarySection;

  void _selectLibrarySection(LibrarySection section) {
    if (_navigation.hasLocalRoute ||
        _primaryDestination != AuthenticatedPrimaryDestination.library ||
        _librarySection == section) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _navigation.selectLibrarySection(section));
    if (section == LibrarySection.playlists) {
      _restoreLibrarySectionFocus();
    }
  }

  void _openLikedSongs() {
    if (_navigation.hasLocalRoute) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _navigation.selectPrimaryDestination(
        AuthenticatedPrimaryDestination.library,
      );
      _navigation.selectLibrarySection(LibrarySection.likedSongs);
    });
  }

  void _openLibraryPlaylists() {
    if (_navigation.hasLocalRoute) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _navigation.selectPrimaryDestination(
        AuthenticatedPrimaryDestination.library,
      );
      _navigation.selectLibrarySection(LibrarySection.playlists);
    });
  }

  void _restoreLibrarySectionFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _primaryDestination != AuthenticatedPrimaryDestination.library ||
          _librarySection != LibrarySection.playlists) {
        return;
      }
      final previousChild = _librarySectionFocusScopeNode.focusedChild;
      if (previousChild?.context != null) {
        previousChild!.requestFocus();
      } else {
        _librarySectionFocusScopeNode.nextFocus();
      }
    });
  }

  void _openTrackContextAlbum(AlbumSummary album) {
    final topRoute = _navigation.topRoute;
    final origin =
        topRoute is ArtistLocalRoute &&
            topRoute.origin == ArtistRouteOrigin.trackContext
        ? AlbumRouteOrigin.trackContextArtist
        : AlbumRouteOrigin.trackContext;
    _pushLocalRoute(AlbumLocalRoute(album: album, origin: origin));
  }

  void _openTrackContextArtist(ArtistSummary artist) {
    _pushLocalRoute(
      ArtistLocalRoute(artist: artist, origin: ArtistRouteOrigin.trackContext),
    );
  }

  void _openAlbumContextArtist(ArtistSummary artist) {
    _pushLocalRoute(
      ArtistLocalRoute(artist: artist, origin: ArtistRouteOrigin.album),
    );
  }

  void _openAlbumFromArtist(
    ArtistRouteOrigin artistOrigin,
    AlbumSummary album,
  ) {
    final albumOrigin = switch (artistOrigin) {
      ArtistRouteOrigin.search => AlbumRouteOrigin.searchArtist,
      ArtistRouteOrigin.favoriteArtists => AlbumRouteOrigin.favoriteArtist,
      ArtistRouteOrigin.trackContext => AlbumRouteOrigin.trackContextArtist,
      ArtistRouteOrigin.album => AlbumRouteOrigin.albumArtist,
      ArtistRouteOrigin.nowPlaying => AlbumRouteOrigin.nowPlayingArtist,
    };
    _pushLocalRoute(AlbumLocalRoute(album: album, origin: albumOrigin));
  }

  void _openNowPlayingAlbum(AlbumSummary album) {
    _pushLocalRoute(
      AlbumLocalRoute(album: album, origin: AlbumRouteOrigin.nowPlaying),
    );
  }

  void _openNowPlayingArtist(ArtistSummary artist) {
    _pushLocalRoute(
      ArtistLocalRoute(artist: artist, origin: ArtistRouteOrigin.nowPlaying),
    );
  }

  void _openExpandedNowPlaying() {
    if (_navigation.topRoute is ExpandedNowPlayingLocalRoute ||
        _queuePlaybackController.current == null) {
      return;
    }
    _pushLocalRoute(const ExpandedNowPlayingLocalRoute());
  }

  void _closeExpandedNowPlaying() {
    if (_navigation.topRoute is! ExpandedNowPlayingLocalRoute) return;
    _returnFromTopRoute();
  }

  void _openFavoriteArtist(ArtistSummary artist) {
    if (_librarySection != LibrarySection.artists ||
        _navigation.hasLocalRoute) {
      return;
    }
    _pushLocalRoute(
      ArtistLocalRoute(
        artist: artist,
        origin: ArtistRouteOrigin.favoriteArtists,
      ),
    );
  }

  void _openFavoriteAlbum(AlbumSummary album) {
    if (_librarySection != LibrarySection.albums || _navigation.hasLocalRoute) {
      return;
    }
    _pushLocalRoute(
      AlbumLocalRoute(album: album, origin: AlbumRouteOrigin.favoriteAlbums),
    );
  }

  void _openRecommendedPlaylist(RecommendedPlaylistSummary playlist) {
    if (!_recommendationsOpen || _navigation.hasLocalRoute) {
      return;
    }
    _pushLocalRoute(
      PlaylistLocalRoute(
        playlist: playlist.toPlaylistSummary(),
        origin: PlaylistRouteOrigin.discover,
      ),
    );
  }

  void _openRanking(RankingSummary ranking) {
    if (!_recommendationsOpen || _navigation.hasLocalRoute) {
      return;
    }
    _pushLocalRoute(RankingLocalRoute(ranking));
  }

  void _openRecommendedAlbum(AlbumSummary album) {
    if (!_recommendationsOpen || _navigation.hasLocalRoute) {
      return;
    }
    _pushLocalRoute(
      AlbumLocalRoute(album: album, origin: AlbumRouteOrigin.discover),
    );
  }

  void _openAlbum(AlbumSummary album) {
    if (!_searchOpen || _navigation.hasLocalRoute) return;
    _pushLocalRoute(
      AlbumLocalRoute(album: album, origin: AlbumRouteOrigin.search),
    );
  }

  void _openArtist(ArtistSummary artist) {
    if (!_searchOpen || _navigation.hasLocalRoute) return;
    _pushLocalRoute(
      ArtistLocalRoute(artist: artist, origin: ArtistRouteOrigin.search),
    );
  }

  void _openSearchPlaylist(UserPlaylistSummary playlist) {
    if (!_searchOpen || _navigation.hasLocalRoute) return;
    _pushLocalRoute(
      PlaylistLocalRoute(
        playlist: playlist,
        origin: PlaylistRouteOrigin.search,
      ),
    );
  }

  void _openPlaylist(UserPlaylistSummary playlist) {
    if (_navigation.hasLocalRoute) return;
    _lastOpenedPlaylist = playlist;
    _pushLocalRoute(
      PlaylistLocalRoute(
        playlist: playlist,
        origin: PlaylistRouteOrigin.library,
      ),
    );
  }

  void _openHomeRecommendation(RecommendedPlaylistSummary playlist) {
    if (_primaryDestination != AuthenticatedPrimaryDestination.home ||
        _navigation.hasLocalRoute) {
      return;
    }
    _lastOpenedHomeRecommendation = playlist;
    _pushLocalRoute(
      PlaylistLocalRoute(
        playlist: playlist.toPlaylistSummary(),
        origin: PlaylistRouteOrigin.homeRecommendation,
      ),
    );
  }

  void _pushLocalRoute(AuthenticatedLocalRoute route) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _navigation.push(route));
  }

  Widget _libraryDestinationBody() {
    if (!widget.authenticated) {
      return Column(
        children: [
          FocusScope(
            node: _librarySectionFocusScopeNode,
            child: LibrarySectionSelector(
              selected: _librarySection,
              onSelected: _selectLibrarySection,
            ),
          ),
          Expanded(child: _signedOutLibraryBody()),
        ],
      );
    }
    return Column(
      children: [
        if (_librarySection != LibrarySection.likedSongs)
          FocusScope(
            node: _librarySectionFocusScopeNode,
            child: LibrarySectionSelector(
              selected: _librarySection,
              onSelected: _selectLibrarySection,
            ),
          ),
        if (_librarySection == LibrarySection.playlists)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => LibraryCollectionHeader(
              key: const ValueKey('library-playlists-header'),
              title: 'Your playlists',
              subtitle: switch (_controller.stage) {
                UserLibraryStage.content || UserLibraryStage.empty =>
                  '${_controller.playlists.length} saved on QQ Music',
                _ => 'Saved on QQ Music',
              },
              refreshKey: const ValueKey('user-playlists-refresh'),
              refreshTooltip: _controller.isRefreshing
                  ? 'Refreshing playlists'
                  : 'Refresh playlists',
              onRefresh: _controller.isLoading ? null : _controller.refresh,
            ),
          ),
        Expanded(
          child: IndexedStack(
            index: _librarySection.index,
            children: [
              _libraryBody(),
              if (_navigation.visitedLibrarySection(LibrarySection.albums))
                FavoriteAlbumsPage(
                  key: const ValueKey('favorite-albums-page'),
                  gateway: _library.favoriteAlbumGateway,
                  queuePlaybackController: _queuePlaybackController,
                  onBack: _returnFromLocalPage,
                  onOpenAlbum: _openFavoriteAlbum,
                  onSignInAgain: widget.onSignInAgain,
                  embedded: true,
                )
              else
                const SizedBox.shrink(),
              if (_navigation.visitedLibrarySection(LibrarySection.artists))
                FavoriteArtistsPage(
                  key: const ValueKey('favorite-artists-page'),
                  gateway: _library.favoriteArtistGateway,
                  queuePlaybackController: _queuePlaybackController,
                  onBack: _returnFromLocalPage,
                  onOpenArtist: _openFavoriteArtist,
                  onSignInAgain: widget.onSignInAgain,
                  embedded: true,
                )
              else
                const SizedBox.shrink(),
              if (_navigation.visitedLibrarySection(LibrarySection.likedSongs))
                _likedSongsBody()
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _likedSongsBody() {
    final playlist = _controller.likedSongsPlaylist;
    if (playlist != null) {
      return LikedSongsPage(
        key: ValueKey('liked-songs-${playlist.providerId}'),
        playlist: playlist,
        playlists: _controller.playlists,
        gateway: _library.playlistDetailGateway,
        favoriteAlbumGateway: _library.favoriteAlbumGateway,
        queuePlaybackController: _queuePlaybackController,
        onOpenPlaylist: _openPlaylist,
        onOpenAlbum: _openTrackContextAlbum,
        onOpenArtist: _openTrackContextArtist,
        onSignInAgain: widget.onSignInAgain,
      );
    }
    return switch (_controller.stage) {
      UserLibraryStage.loading => const _LibraryLoading(),
      UserLibraryStage.content ||
      UserLibraryStage.empty => const _CenteredLibraryMessage(
        icon: Icons.favorite_border_rounded,
        title: '暂时无法找到喜欢歌单',
        detail: 'QQ Music 未返回内建喜欢歌单，不会用其他歌单代替。',
        actions: [],
      ),
      UserLibraryStage.error ||
      UserLibraryStage.authenticationRequired ||
      UserLibraryStage.credentialRejected => _libraryBody(),
    };
  }

  Widget _primaryScaffold() => LayoutBuilder(
    builder: (context, constraints) {
      final destination = _primaryDestination;
      final wide = constraints.maxWidth >= 840;
      final extendedSidebar = constraints.maxWidth >= 1100;
      final compactActions = constraints.maxWidth < 520;
      final likedSongsOpen =
          destination == AuthenticatedPrimaryDestination.library &&
          _librarySection == LibrarySection.likedSongs;
      final primaryContent = IndexedStack(
        index: destination.index,
        children: [
          HomePage(
            key: const ValueKey('home-page'),
            homeController: _homeController,
            recommendationController: _recommendedPlaylistController,
            guestNewSongController: _guestNewSongController,
            radarController: _homeRadarController,
            queuePlaybackController: _queuePlaybackController,
            authenticated: widget.authenticated,
            onOpenDiscover: () => _selectPrimaryDestination(
              AuthenticatedPrimaryDestination.discover,
            ),
            onOpenLibrary: () => _selectPrimaryDestination(
              AuthenticatedPrimaryDestination.library,
            ),
            onAccountAction: widget.authenticated
                ? _confirmSignOut
                : widget.onRequestSignIn,
            onOpenRecommendation: _openHomeRecommendation,
            lastOpenedRecommendation: _lastOpenedHomeRecommendation,
            recommendationReturnFocusNode: _homeRecommendationReturnFocusNode,
          ),
          if (_navigation.visitedDestination(
            AuthenticatedPrimaryDestination.discover,
          ))
            RecommendedPlaylistsPage(
              key: const ValueKey('recommended-playlists-page'),
              gateway: _discovery.recommendedPlaylistGateway,
              controller: _recommendedPlaylistController,
              newAlbumGateway: _discovery.newAlbumGateway,
              newSongGateway: _discovery.newSongGateway,
              rankingGateway: _discovery.rankingGateway,
              radarGateway: _discovery.radarGateway,
              queuePlaybackController: _queuePlaybackController,
              onBack: _returnFromLocalPage,
              onOpenPlaylist: _openRecommendedPlaylist,
              onOpenRanking: _openRanking,
              onOpenAlbum: _openRecommendedAlbum,
              onOpenTrackAlbum: _openTrackContextAlbum,
              onOpenTrackArtist: _openTrackContextArtist,
              onSignInAgain: widget.onSignInAgain,
              embedded: true,
            )
          else
            const SizedBox.shrink(),
          if (_navigation.visitedDestination(
            AuthenticatedPrimaryDestination.search,
          ))
            TrackSearchPage(
              key: const ValueKey('track-search-page'),
              gateway: _discovery.trackSearchGateway,
              artistGateway: _discovery.artistSearchGateway,
              albumGateway: _discovery.albumSearchGateway,
              playlistGateway: _discovery.playlistSearchGateway,
              queuePlaybackController: _queuePlaybackController,
              onBack: _returnFromLocalPage,
              onOpenAlbum: _openAlbum,
              onOpenArtist: _openArtist,
              onOpenPlaylist: _openSearchPlaylist,
              onSignInAgain: widget.onSignInAgain,
              embedded: true,
            )
          else
            const SizedBox.shrink(),
          _libraryDestinationBody(),
        ],
      );
      final mainBody = AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => !widget.authenticated
            ? primaryContent
            : switch (_controller.stage) {
                UserLibraryStage.authenticationRequired ||
                UserLibraryStage.credentialRejected => _libraryBody(),
                _ => primaryContent,
              },
      );
      final mainAppBar = AppBar(
        title: _PrimaryShellTitle(
          title: switch (destination) {
            AuthenticatedPrimaryDestination.home => 'Home',
            AuthenticatedPrimaryDestination.discover => 'Discover',
            AuthenticatedPrimaryDestination.search => 'Search QQ Music',
            AuthenticatedPrimaryDestination.library => 'Your music',
          },
          compact: compactActions,
          showTitle:
              !likedSongsOpen &&
              (destination != AuthenticatedPrimaryDestination.home ||
                  !extendedSidebar),
          showSearchShortcut:
              extendedSidebar &&
              destination != AuthenticatedPrimaryDestination.search,
          onOpenSearch: () =>
              _selectPrimaryDestination(AuthenticatedPrimaryDestination.search),
        ),
        titleSpacing: compactActions ? 8 : 16,
        actions: _primaryActions(compactActions: compactActions),
      );
      return Scaffold(
        key: const ValueKey('authenticated-primary-shell'),
        body: Row(
          children: [
            if (extendedSidebar)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => _DesktopMusicSidebar(
                  destination: destination,
                  librarySection: _librarySection,
                  homeController: _homeController,
                  libraryController: _controller,
                  authenticated: widget.authenticated,
                  recommendationsFocusNode: _recommendationsReturnFocusNode,
                  searchFocusNode: _searchReturnFocusNode,
                  onRequestSignIn: widget.onRequestSignIn,
                  onDestinationSelected: _selectPrimaryDestination,
                  onOpenLikedSongs: _openLikedSongs,
                  onOpenLibrary: _openLibraryPlaylists,
                  onOpenPlaylist: (playlist) {
                    _selectPrimaryDestination(
                      AuthenticatedPrimaryDestination.library,
                    );
                    _openPlaylist(playlist);
                  },
                ),
              )
            else if (wide)
              NavigationRail(
                selectedIndex: destination.index,
                labelType: NavigationRailLabelType.all,
                minWidth: MusicSizes.desktopRail,
                minExtendedWidth: MusicSizes.desktopSidebar,
                leading: const _MusicSidebarBrand(expanded: false),
                onDestinationSelected: _selectPrimaryDestinationByIndex,
                destinations: _navigationRailDestinations(),
              )
            else
              const SizedBox.shrink(),
            if (wide) const VerticalDivider(width: 1),
            if (!wide) const SizedBox.shrink(),
            Expanded(
              child: Scaffold(
                appBar:
                    compactActions &&
                        destination == AuthenticatedPrimaryDestination.home
                    ? null
                    : mainAppBar,
                body: mainBody,
                bottomNavigationBar: wide
                    ? NowPlayingBar(
                        controller: _queuePlaybackController,
                        onSignInAgain: widget.onSignInAgain,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (destination ==
                                  AuthenticatedPrimaryDestination.home ||
                              likedSongsOpen)
                            NowPlayingBar.compact(
                              controller: _queuePlaybackController,
                              onSignInAgain: widget.onSignInAgain,
                            )
                          else
                            NowPlayingBar(
                              controller: _queuePlaybackController,
                              onSignInAgain: widget.onSignInAgain,
                            ),
                          NavigationBar(
                            height:
                                destination ==
                                        AuthenticatedPrimaryDestination.home ||
                                    likedSongsOpen
                                ? 64
                                : null,
                            selectedIndex: destination.index,
                            onDestinationSelected:
                                _selectPrimaryDestinationByIndex,
                            destinations: _navigationBarDestinations(),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      );
    },
  );

  void _selectPrimaryDestinationByIndex(int index) {
    _selectPrimaryDestination(AuthenticatedPrimaryDestination.values[index]);
  }

  List<NavigationRailDestination> _navigationRailDestinations() => [
    const NavigationRailDestination(
      icon: Icon(
        Icons.home_outlined,
        key: ValueKey('primary-home-destination'),
      ),
      selectedIcon: Icon(Icons.home_rounded),
      label: Text('Home'),
    ),
    NavigationRailDestination(
      icon: _destinationFocusIcon(
        key: const ValueKey('open-recommendations'),
        focusNode: _recommendationsReturnFocusNode,
        destination: AuthenticatedPrimaryDestination.discover,
        icon: Icons.explore_outlined,
      ),
      label: const Text('Discover'),
    ),
    NavigationRailDestination(
      icon: _destinationFocusIcon(
        key: const ValueKey('open-track-search'),
        focusNode: _searchReturnFocusNode,
        destination: AuthenticatedPrimaryDestination.search,
        icon: Icons.search_rounded,
      ),
      label: const Text('Search'),
    ),
    const NavigationRailDestination(
      icon: Icon(
        Icons.library_music_outlined,
        key: ValueKey('primary-library-destination'),
      ),
      selectedIcon: Icon(Icons.library_music_rounded),
      label: Text('Library'),
    ),
  ];

  List<NavigationDestination> _navigationBarDestinations() => [
    const NavigationDestination(
      icon: Icon(
        Icons.home_outlined,
        key: ValueKey('primary-home-destination'),
      ),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: _destinationFocusIcon(
        key: const ValueKey('open-recommendations'),
        focusNode: _recommendationsReturnFocusNode,
        destination: AuthenticatedPrimaryDestination.discover,
        icon: Icons.explore_outlined,
      ),
      label: 'Discover',
    ),
    NavigationDestination(
      icon: _destinationFocusIcon(
        key: const ValueKey('open-track-search'),
        focusNode: _searchReturnFocusNode,
        destination: AuthenticatedPrimaryDestination.search,
        icon: Icons.search_rounded,
      ),
      label: 'Search',
    ),
    const NavigationDestination(
      icon: Icon(
        Icons.library_music_outlined,
        key: ValueKey('primary-library-destination'),
      ),
      selectedIcon: Icon(Icons.library_music_rounded),
      label: 'Library',
    ),
  ];

  Widget _destinationFocusIcon({
    required Key key,
    required FocusNode focusNode,
    required AuthenticatedPrimaryDestination destination,
    required IconData icon,
  }) => Focus(
    key: key,
    focusNode: focusNode,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space)) {
        _selectPrimaryDestination(destination);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Icon(icon),
  );

  List<Widget> _primaryActions({required bool compactActions}) => [
    IconButton(
      key: ValueKey(widget.authenticated ? 'sign-out' : 'sign-in'),
      tooltip: widget.authenticated ? 'Sign out' : 'Sign in to QQ Music',
      onPressed: widget.authenticated
          ? (_signingOut ? null : _confirmSignOut)
          : widget.onRequestSignIn,
      icon: Icon(
        widget.authenticated ? Icons.logout_rounded : Icons.login_rounded,
      ),
    ),
    if (!compactActions) const SizedBox(width: 8),
  ];

  Widget _libraryBody() => SafeArea(
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
              duration: MusicMotion.stateChange,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _body(context),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _signedOutLibraryBody() => _CenteredLibraryMessage(
    key: const ValueKey('signed-out-library'),
    icon: switch (_librarySection) {
      LibrarySection.playlists => Icons.library_music_outlined,
      LibrarySection.albums => Icons.album_outlined,
      LibrarySection.artists => Icons.person_outline_rounded,
      LibrarySection.likedSongs => Icons.favorite_border_rounded,
    },
    title: 'Sign in to see your music',
    detail: 'Your QQ Music playlists, liked songs, albums, and artists will appear here.',
    actions: [
      FilledButton.icon(
        key: const ValueKey('signed-out-library-sign-in'),
        onPressed: widget.onRequestSignIn,
        icon: const Icon(Icons.login_rounded),
        label: const Text('Sign in'),
      ),
    ],
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

class _DesktopMusicSidebar extends StatelessWidget {
  const _DesktopMusicSidebar({
    required this.destination,
    required this.librarySection,
    required this.homeController,
    required this.libraryController,
    required this.authenticated,
    required this.recommendationsFocusNode,
    required this.searchFocusNode,
    required this.onRequestSignIn,
    required this.onDestinationSelected,
    required this.onOpenLikedSongs,
    required this.onOpenLibrary,
    required this.onOpenPlaylist,
  });

  final AuthenticatedPrimaryDestination destination;
  final LibrarySection librarySection;
  final HomeController homeController;
  final UserLibraryController libraryController;
  final bool authenticated;
  final FocusNode recommendationsFocusNode;
  final FocusNode searchFocusNode;
  final VoidCallback onRequestSignIn;
  final ValueChanged<AuthenticatedPrimaryDestination> onDestinationSelected;
  final VoidCallback onOpenLikedSongs;
  final VoidCallback onOpenLibrary;
  final ValueChanged<UserPlaylistSummary> onOpenPlaylist;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('desktop-music-sidebar'),
    width: MusicSizes.desktopSidebar,
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            const _MusicSidebarBrand(expanded: true),
            AnimatedBuilder(
              animation: homeController,
              builder: (context, _) => _SidebarAccount(
                authenticated: authenticated,
                displayName: homeController.account?.displayName,
                avatarUri: homeController.account?.avatarUri,
                onRequestSignIn: onRequestSignIn,
              ),
            ),
            const Divider(height: MusicSpacing.section),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  const _SidebarSectionLabel('ONLINE MUSIC'),
                  _SidebarDestinationTile(
                    key: const ValueKey('primary-home-destination'),
                    selected:
                        destination == AuthenticatedPrimaryDestination.home,
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    label: 'Home',
                    onTap: () => onDestinationSelected(
                      AuthenticatedPrimaryDestination.home,
                    ),
                  ),
                  _SidebarDestinationTile(
                    key: const ValueKey('open-recommendations'),
                    selected:
                        destination == AuthenticatedPrimaryDestination.discover,
                    icon: Icons.explore_outlined,
                    selectedIcon: Icons.explore_rounded,
                    label: 'Discover',
                    focusNode: recommendationsFocusNode,
                    onTap: () => onDestinationSelected(
                      AuthenticatedPrimaryDestination.discover,
                    ),
                  ),
                  _SidebarDestinationTile(
                    key: const ValueKey('open-track-search'),
                    selected:
                        destination == AuthenticatedPrimaryDestination.search,
                    icon: Icons.search_rounded,
                    selectedIcon: Icons.search_rounded,
                    label: 'Search',
                    focusNode: searchFocusNode,
                    onTap: () => onDestinationSelected(
                      AuthenticatedPrimaryDestination.search,
                    ),
                  ),
                  const SizedBox(height: MusicSpacing.contentGap),
                  const _SidebarSectionLabel('MY MUSIC'),
                  _SidebarDestinationTile(
                    key: const ValueKey('open-liked-songs'),
                    selected:
                        destination ==
                            AuthenticatedPrimaryDestination.library &&
                        librarySection == LibrarySection.likedSongs,
                    icon: Icons.favorite_border_rounded,
                    selectedIcon: Icons.favorite_rounded,
                    label: '喜欢',
                    onTap: onOpenLikedSongs,
                  ),
                  _SidebarDestinationTile(
                    key: const ValueKey('primary-library-destination'),
                    selected:
                        destination ==
                            AuthenticatedPrimaryDestination.library &&
                        librarySection != LibrarySection.likedSongs,
                    icon: Icons.library_music_outlined,
                    selectedIcon: Icons.library_music_rounded,
                    label: 'Library',
                    onTap: onOpenLibrary,
                  ),
                  if (libraryController.stage == UserLibraryStage.content &&
                      libraryController.playlists.isNotEmpty) ...[
                    const SizedBox(height: MusicSpacing.contentGap),
                    const _SidebarSectionLabel('YOUR PLAYLISTS'),
                    for (final playlist
                        in libraryController.playlists
                            .where((playlist) => !playlist.isLikedSongs)
                            .take(7))
                      ListTile(
                        dense: true,
                        minTileHeight: 44,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                        ),
                        leading: SizedBox.square(
                          dimension: 32,
                          child: _PlaylistArtwork(playlist: playlist),
                        ),
                        title: Text(
                          playlist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onOpenPlaylist(playlist),
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

class _SidebarAccount extends StatelessWidget {
  const _SidebarAccount({
    required this.authenticated,
    required this.displayName,
    required this.avatarUri,
    required this.onRequestSignIn,
  });

  final bool authenticated;
  final String? displayName;
  final String? avatarUri;
  final VoidCallback onRequestSignIn;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colors.primaryContainer,
      child: Icon(Icons.person_rounded, color: colors.onPrimaryContainer),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        key: const ValueKey('sidebar-account'),
        onTap: authenticated ? null : onRequestSignIn,
        borderRadius: MusicRadii.control,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 40,
                child: ClipOval(
                  child: avatarUri == null
                      ? fallback
                      : Image.network(
                          avatarUri!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => fallback,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authenticated
                          ? displayName ?? 'QQ Music listener'
                          : 'Not signed in',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      authenticated
                          ? displayName == null
                                ? 'Loading account…'
                                : 'QQ Music'
                          : 'Sign in to QQ Music',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (!authenticated) ...[
                const SizedBox(width: 8),
                Icon(Icons.login_rounded, color: colors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _SidebarDestinationTile extends StatelessWidget {
  const _SidebarDestinationTile({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
    this.focusNode,
    super.key,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => ListTile(
    selected: selected,
    dense: true,
    minTileHeight: 44,
    shape: const StadiumBorder(),
    selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
    selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
    leading: Icon(selected ? selectedIcon : icon),
    title: Text(label),
    focusNode: focusNode,
    onTap: onTap,
  );
}

class _MusicSidebarBrand extends StatelessWidget {
  const _MusicSidebarBrand({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mark = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: MusicRadii.control,
      ),
      child: Icon(Icons.graphic_eq_rounded, color: colors.onPrimary),
    );
    return SizedBox(
      width: expanded ? MusicSizes.desktopSidebar : MusicSizes.desktopRail,
      child: Padding(
        key: const ValueKey('music-sidebar-brand'),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: expanded
            ? Row(
                children: [
                  mark,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Music',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'QQ Music client',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Tooltip(message: 'QQ Music client', child: mark),
      ),
    );
  }
}

class _PrimaryShellTitle extends StatelessWidget {
  const _PrimaryShellTitle({
    required this.title,
    required this.compact,
    required this.showTitle,
    required this.showSearchShortcut,
    required this.onOpenSearch,
  });

  final String title;
  final bool compact;
  final bool showTitle;
  final bool showSearchShortcut;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final titleText = showTitle
        ? Text(
            title,
            style: compact ? Theme.of(context).textTheme.titleMedium : null,
          )
        : null;
    if (!showSearchShortcut) return titleText ?? const SizedBox.shrink();
    return Row(
      children: [
        if (titleText != null) ...[
          titleText,
          const SizedBox(width: MusicSpacing.pageWide),
        ],
        Expanded(
          child: Align(
            alignment: titleText == null
                ? Alignment.center
                : Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: SearchBar(
                key: const ValueKey('top-search-shortcut'),
                onTap: onOpenSearch,
                hintText: 'Search QQ Music',
                leading: const Icon(Icons.search_rounded),
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.surfaceContainerHigh,
                ),
                constraints: const BoxConstraints(minHeight: 40),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 760;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            desktop ? MusicSpacing.pageWide : MusicSpacing.pageCompact,
            0,
            desktop ? MusicSpacing.pageWide : MusicSpacing.pageCompact,
            MusicSpacing.pageCompact,
          ),
          child: desktop
              ? _DesktopPlaylistList(
                  playlists: playlists,
                  onSelected: onSelected,
                  focusNodeFor: _focusNodeFor,
                )
              : ListView.separated(
                  key: const PageStorageKey<String>('user-playlist-list'),
                  itemCount: playlists.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: MusicSpacing.itemGap),
                  itemBuilder: (context, index) => _PlaylistListItem(
                    playlist: playlists[index],
                    onTap: () => onSelected(playlists[index]),
                    focusNode: _focusNodeFor(playlists[index]),
                  ),
                ),
        );
      },
    );
  }
}

class _DesktopPlaylistList extends StatelessWidget {
  const _DesktopPlaylistList({
    required this.playlists,
    required this.onSelected,
    required this.focusNodeFor,
  });

  final List<UserPlaylistSummary> playlists;
  final ValueChanged<UserPlaylistSummary> onSelected;
  final FocusNode? Function(UserPlaylistSummary playlist) focusNodeFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      children: [
        Padding(
          key: const ValueKey('user-playlist-table-header'),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 16, 12),
          child: Row(
            children: [
              const SizedBox(width: 64),
              Expanded(child: Text('Playlist', style: mutedStyle)),
              SizedBox(width: 104, child: Text('Tracks', style: mutedStyle)),
              const SizedBox(width: 40),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.separated(
            key: const PageStorageKey<String>('user-playlist-list-desktop'),
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return _PlaylistListItem(
                playlist: playlist,
                onTap: () => onSelected(playlist),
                focusNode: focusNodeFor(playlist),
                desktop: true,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlaylistListItem extends StatelessWidget {
  const _PlaylistListItem({
    required this.playlist,
    required this.onTap,
    required this.focusNode,
    this.desktop = false,
  });

  final UserPlaylistSummary playlist;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = playlist.trackCount;
    return Semantics(
      label: _semanticLabel(playlist),
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        focusNode: focusNode,
        borderRadius: MusicRadii.content,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: desktop ? 4 : 6),
          child: Row(
            children: [
              SizedBox.square(
                dimension: desktop ? 56 : 72,
                child: _PlaylistArtwork(playlist: playlist),
              ),
              const SizedBox(width: MusicSpacing.contentGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.title,
                      maxLines: desktop ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!desktop && count != null) ...[
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
              SizedBox(
                width: desktop ? 104 : 0,
                child: desktop && count != null
                    ? Text(
                        '$count tracks',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : null,
              ),
              if (desktop)
                const SizedBox(
                  width: 40,
                  child: Icon(Icons.chevron_right_rounded),
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
      borderRadius: MusicRadii.content,
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
    super.key,
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
