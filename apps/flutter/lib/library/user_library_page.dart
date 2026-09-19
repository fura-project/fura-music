import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/adaptive_confirmation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/album/album_page.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/artist/artist_page.dart';
import 'package:flutterustmusic/catalog/music_collection_detail_layout.dart';
import 'package:flutterustmusic/authenticated_dependencies.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/catalog/partial_results_notice.dart';
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
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/library/favorite_albums_page.dart';
import 'package:flutterustmusic/library/favorite_artists_page.dart';
import 'package:flutterustmusic/library/library_section_selector.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_collection_header.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_refresh_failure_banner.dart';
import 'package:flutterustmusic/library/liked_songs_page.dart';
import 'package:flutterustmusic/library/recent_plays_page.dart';
import 'package:flutterustmusic/library/playlist_detail_page.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/navigation/authenticated_navigation_state.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_navigation.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_page.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/playback_quality.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/provider_presentation.dart';
import 'package:flutterustmusic/search/track_search_page.dart';
import 'package:flutterustmusic/search/track_search_suggestions.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/settings/settings_page.dart';
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
    required this.capabilities,
    required this.settings,
    required this.onSettingsChanged,
    required this.authenticated,
    required this.onRequestSignIn,
    required this.onSignInAgain,
    required this.onSignOut,
    this.systemLightColorScheme,
    this.systemDarkColorScheme,
    super.key,
  });

  final AuthenticatedHomeDependencies homeDependencies;
  final AuthenticatedLibraryDependencies libraryDependencies;
  final AuthenticatedDiscoveryDependencies discoveryDependencies;
  final AuthenticatedPlaybackDependencies playbackDependencies;
  final MusicProviderCapabilities capabilities;
  final AppSettings settings;
  final Future<AppSettingsWriteResult> Function(AppSettings settings)
  onSettingsChanged;
  final bool authenticated;
  final VoidCallback onRequestSignIn;
  final VoidCallback onSignInAgain;
  final Future<CredentialSignOutResult> Function() onSignOut;
  final ColorScheme? systemLightColorScheme;
  final ColorScheme? systemDarkColorScheme;

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

class _RetainedPrimaryDestinationTransition extends StatefulWidget {
  const _RetainedPrimaryDestinationTransition({
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<_RetainedPrimaryDestinationTransition> createState() =>
      _RetainedPrimaryDestinationTransitionState();
}

class _RetainedPrimaryDestinationTransitionState
    extends State<_RetainedPrimaryDestinationTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _currentIndex;
  int? _previousIndex;
  double _direction = 1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 300),
    )..addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(_RetainedPrimaryDestinationTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == _currentIndex) return;
    _previousIndex = _currentIndex;
    _direction = widget.index > _currentIndex ? 1 : -1;
    _currentIndex = widget.index;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1;
      _previousIndex = null;
    } else {
      unawaited(_controller.forward(from: 0));
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _previousIndex != null) {
      setState(() => _previousIndex = null);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    key: const ValueKey('primary-destination-transition'),
    animation: _controller,
    builder: (context, _) {
      final eased = Easing.emphasizedDecelerate.transform(_controller.value);
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          for (var index = 0; index < widget.children.length; index++)
            _destination(index, eased),
        ],
      );
    },
  );

  Widget _destination(int index, double animationValue) {
    final current = index == _currentIndex;
    final previous = index == _previousIndex;
    final active = current || previous;
    final offset = current
        ? Offset((1 - animationValue) * 18 * _direction, 0)
        : Offset(-animationValue * 8 * _direction, 0);
    final opacity = current ? 0.72 + animationValue * 0.28 : 1 - animationValue;
    return Offstage(
      offstage: !active,
      child: TickerMode(
        enabled: current,
        child: ExcludeSemantics(
          excluding: !current,
          child: ExcludeFocus(
            excluding: !current,
            child: IgnorePointer(
              ignoring: !current,
              child: Transform.translate(
                offset: offset,
                child: Opacity(
                  opacity: opacity.clamp(0, 1),
                  child: widget.children[index],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellDetailTransition extends StatefulWidget {
  const _ShellDetailTransition({
    required this.open,
    required this.opaqueSurfaceKey,
    required this.base,
    required this.detail,
  });

  final bool open;
  final Key? opaqueSurfaceKey;
  final Widget base;
  final Widget detail;

  @override
  State<_ShellDetailTransition> createState() => _ShellDetailTransitionState();
}

class _ShellDetailTransitionState extends State<_ShellDetailTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Widget _retainedDetail;
  Key? _retainedOpaqueSurfaceKey;

  @override
  void initState() {
    super.initState();
    _retainedDetail = widget.detail;
    _retainedOpaqueSurfaceKey = widget.opaqueSurfaceKey;
    _controller = AnimationController(
      vsync: this,
      value: widget.open ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 240),
    );
  }

  @override
  void didUpdateWidget(_ShellDetailTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open) {
      _retainedDetail = widget.detail;
      _retainedOpaqueSurfaceKey = widget.opaqueSurfaceKey;
    }
    if (widget.open == oldWidget.open) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = widget.open ? 1 : 0;
    } else if (widget.open) {
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
    key: const ValueKey('shell-detail-transition'),
    animation: _controller,
    builder: (context, _) {
      final value = Easing.emphasizedDecelerate.transform(_controller.value);
      final detailVisible = !_controller.isDismissed;
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          Offstage(
            offstage: _controller.isCompleted,
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
                  child: Transform.translate(
                    offset: Offset((1 - value) * 40, 0),
                    child: _retainedOpaqueSurfaceKey != null
                        ? Material(
                            key: _retainedOpaqueSurfaceKey,
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: Opacity(
                              opacity: (0.7 + value * 0.3).clamp(0, 1),
                              child: _retainedDetail,
                            ),
                          )
                        : Opacity(
                            opacity: (0.7 + value * 0.3).clamp(0, 1),
                            child: _retainedDetail,
                          ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _SettingsShellNavigationTransition extends StatefulWidget {
  const _SettingsShellNavigationTransition({
    required this.open,
    required this.base,
    required this.settings,
    required this.width,
  });

  final bool open;
  final Widget base;
  final Widget settings;
  final double width;

  @override
  State<_SettingsShellNavigationTransition> createState() =>
      _SettingsShellNavigationTransitionState();
}

class _SettingsShellNavigationTransitionState
    extends State<_SettingsShellNavigationTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: widget.open ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 240),
    );
  }

  @override
  void didUpdateWidget(_SettingsShellNavigationTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = widget.open ? 1 : 0;
    } else if (widget.open) {
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
  // Keep sidebar/rail traversal together instead of interleaving destinations
  // with content rows at the same vertical position.
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: SizedBox(
      key: const ValueKey('settings-navigation-transition'),
      width: widget.width,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final value = Easing.emphasizedDecelerate.transform(
            _controller.value,
          );
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: _controller.isCompleted,
                  child: ExcludeSemantics(
                    excluding: widget.open,
                    child: ExcludeFocus(
                      excluding: widget.open,
                      child: IgnorePointer(
                        ignoring: widget.open,
                        child: Transform.translate(
                          key: const ValueKey(
                            'music-navigation-transition-page',
                          ),
                          offset: Offset(-32 * value, 0),
                          child: Opacity(
                            opacity: (1 - value).clamp(0, 1),
                            child: widget.base,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_controller.isDismissed)
                  ExcludeSemantics(
                    excluding: !widget.open,
                    child: ExcludeFocus(
                      excluding: !widget.open,
                      child: IgnorePointer(
                        ignoring: !widget.open,
                        child: Transform.translate(
                          key: const ValueKey(
                            'settings-navigation-transition-page',
                          ),
                          offset: Offset((1 - value) * 32, 0),
                          child: Opacity(
                            opacity: value.clamp(0, 1),
                            child: widget.settings,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _UserLibraryPageState extends State<UserLibraryPage> {
  late UserLibraryController _controller;
  late HomeController _homeController;
  late final QueuePlaybackController _queuePlaybackController;
  late final ArtworkColorSchemeCache _expandedNowPlayingPalette;
  late RecommendedPlaylistController _recommendedPlaylistController;
  late NewSongController _homeNewSongController;
  late RadarController _homeRadarController;
  late TrackSearchSuggestionController _topSearchSuggestionController;
  final DiscoverNavigationController _discoverNavigationController =
      DiscoverNavigationController();
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
  final FocusNode _settingsReturnFocusNode = FocusNode(
    debugLabel: 'settings entry',
  );
  final FocusScopeNode _librarySectionFocusScopeNode = FocusScopeNode(
    debugLabel: 'library section selector',
  );
  final FocusNode _backShortcutFallbackFocusNode = FocusNode(
    debugLabel: 'authenticated back shortcut fallback',
  );
  PageStorageBucket _pageStorageBucket = PageStorageBucket();
  GlobalKey<TrackSearchPageState> _trackSearchPageKey =
      GlobalKey<TrackSearchPageState>(debugLabel: 'primary track search');
  final TextEditingController _topSearchController = TextEditingController();
  final TextEditingController _settingsSearchController =
      TextEditingController();
  AuthenticatedNavigationState _navigation = AuthenticatedNavigationState();
  UserPlaylistSummary? _lastOpenedPlaylist;
  RecommendedPlaylistSummary? _lastOpenedHomeRecommendation;
  bool _handledLyricCredentialRejection = false;
  bool _handledHomeCredentialRejection = false;
  bool _signingOut = false;
  bool _overlayPageActive = false;
  SettingsSection _settingsSection = SettingsSection.appearance;
  bool _compactSettingsSectionOpen = false;
  String _settingsSearchQuery = '';
  bool _likedHeaderCollapsed = false;
  bool _recentHeaderCollapsed = false;
  bool _topSearchFocused = false;
  bool _discoverHeaderCollapsed = false;
  bool _collectionDetailHeaderCollapsed = false;
  final Map<String, bool> _collectionDetailCollapsedByRoute = {};
  final Map<String, CollectionDetailActions> _collectionShellActions = {};
  String? _prefetchedArtworkUri;
  Brightness? _prefetchedArtworkBrightness;
  Timer? _playbackNoticeTimer;
  String? _playbackNoticeMessage;
  bool _playbackNoticeError = false;
  int _playbackNoticeRevision = 0;

  String get _providerDisplayName => builtInProviderDisplayName(
    widget.settings.musicProvider.providerId,
    context.l10n,
  );

  @override
  void initState() {
    super.initState();
    _initializeProviderControllers();
    _queuePlaybackController = _playback.playbackHost.controller;
    _expandedNowPlayingPalette = ArtworkColorSchemeCache();
    _queuePlaybackController.addListener(_onQueuePlaybackChanged);
    _loadProviderRoot();
  }

  void _initializeProviderControllers() {
    _controller = UserLibraryController(_library.libraryGateway);
    _homeController = HomeController(
      _home.accountSummaryGateway,
      _home.dailyRecommendationGateway,
      _home.personalizedPlaylistsGateway,
      _home.personalizedTracksGateway,
      _home.relatedTracksGateway,
      recentListening: _home.recentListeningFactory?.call(),
    );
    _recommendedPlaylistController = RecommendedPlaylistController(
      _discovery.recommendedPlaylistGateway,
    );
    _homeNewSongController = NewSongController(_discovery.newSongGateway);
    _homeRadarController = RadarController(_discovery.radarGateway);
    _topSearchSuggestionController = TrackSearchSuggestionController(
      _discovery.trackSuggestionGateway,
    );
    _homeController.addListener(_onHomeChanged);
    _homeRadarController.addListener(_onHomeChanged);
  }

  void _loadProviderRoot() {
    unawaited(_recommendedPlaylistController.load());
    unawaited(_homeNewSongController.load());
    if (widget.authenticated) {
      unawaited(_controller.load());
      unawaited(_homeController.load());
      if (widget.capabilities.radar) {
        unawaited(_homeRadarController.load());
      }
    }
  }

  void _disposeProviderControllers() {
    _controller.dispose();
    _homeController.removeListener(_onHomeChanged);
    _homeController.dispose();
    _recommendedPlaylistController.dispose();
    _homeNewSongController.dispose();
    _homeRadarController.removeListener(_onHomeChanged);
    _homeRadarController.dispose();
    _topSearchSuggestionController.dispose();
  }

  @override
  void didUpdateWidget(UserLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final providerChanged =
        oldWidget.settings.musicProvider != widget.settings.musicProvider;
    final authenticationChanged =
        oldWidget.authenticated != widget.authenticated;
    if (!providerChanged && !authenticationChanged) return;

    _queuePlaybackController.invalidateCollectionSource();

    _disposeProviderControllers();
    _navigation = AuthenticatedNavigationState();
    _pageStorageBucket = PageStorageBucket();
    _trackSearchPageKey = GlobalKey<TrackSearchPageState>(
      debugLabel: 'primary track search',
    );
    _topSearchController.clear();
    _settingsSearchController.clear();
    _lastOpenedPlaylist = null;
    _lastOpenedHomeRecommendation = null;
    _handledLyricCredentialRejection = false;
    _handledHomeCredentialRejection = false;
    _overlayPageActive = false;
    _settingsSection = SettingsSection.appearance;
    _compactSettingsSectionOpen = false;
    _settingsSearchQuery = '';
    _likedHeaderCollapsed = false;
    _recentHeaderCollapsed = false;
    _topSearchFocused = false;
    _discoverHeaderCollapsed = false;
    _collectionDetailHeaderCollapsed = false;
    _collectionDetailCollapsedByRoute.clear();
    _collectionShellActions.clear();
    _initializeProviderControllers();
    _loadProviderRoot();
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
    final playback = _queuePlaybackController.playback;
    _homeController.observePlayback(
      playback.track,
      playback.positionMs,
      playback.stage == TrackPlaybackStage.playing,
    );
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
    _playbackNoticeTimer?.cancel();
    _disposeProviderControllers();
    _queuePlaybackController.removeListener(_onQueuePlaybackChanged);
    _playlistReturnFocusNode.dispose();
    _searchReturnFocusNode.dispose();
    _recommendationsReturnFocusNode.dispose();
    _homeRecommendationReturnFocusNode.dispose();
    _settingsReturnFocusNode.dispose();
    _librarySectionFocusScopeNode.dispose();
    _backShortcutFallbackFocusNode.dispose();
    _topSearchController.dispose();
    _settingsSearchController.dispose();
    _discoverNavigationController.dispose();
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
    final catalogRoutes = retainedRoutes;
    var embeddedRouteCount = 0;
    while (embeddedRouteCount < catalogRoutes.length &&
        _usesPrimaryShell(catalogRoutes[embeddedRouteCount])) {
      embeddedRouteCount++;
    }
    final embeddedShellRoutes = catalogRoutes.sublist(0, embeddedRouteCount);
    final overlayCatalogRoutes = catalogRoutes.sublist(embeddedRouteCount);
    final catalogPages = <Widget>[
      _primaryScaffold(embeddedShellRoutes: embeddedShellRoutes),
      ...overlayCatalogRoutes.map(_buildLocalRoute),
    ];
    final catalogRoutePage = IndexedStack(
      index: catalogPages.length - 1,
      children: catalogPages,
    );
    final retainedRoutePage = NowPlayingCatalogNavigation(
      onOpenAlbum: _openNowPlayingAlbum,
      onOpenArtist: _openNowPlayingArtist,
      child: catalogRoutePage,
    );
    final retainedRouteSurface = ExpandedNowPlayingNavigation(
      onOpen: _openExpandedNowPlaying,
      child: retainedRoutePage,
    );
    final expandedNowPlayingPage = _ExpandedNowPlayingRouteTransition(
      open: expandedNowPlayingOpen,
      base: retainedRouteSurface,
      detail: NowPlayingCatalogNavigation(
        onOpenAlbum: _openNowPlayingAlbum,
        onOpenArtist: _openNowPlayingArtist,
        child: ExpandedNowPlayingPage(
          controller: _queuePlaybackController,
          onBack: _closeExpandedNowPlaying,
          onSignInAgain: widget.onSignInAgain,
          qualityPreference: widget.settings.playbackQuality,
          onQualityPreferenceChanged: _changePlaybackQuality,
          lyricAuxiliaryMode: widget.settings.lyricAuxiliaryMode,
          onLyricAuxiliaryModeChanged: _changeLyricAuxiliaryMode,
          commentsGateway: _playback.trackCommentGateway,
          artworkColorSchemeCache: _expandedNowPlayingPalette,
        ),
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
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final pageWithNotice = Stack(
      fit: StackFit.expand,
      children: [
        shortcutPage,
        PositionedDirectional(
          start: 16,
          end: 16,
          bottom: viewportWidth >= 840 ? 100 : 164,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSwitcher(
                key: const ValueKey('playback-transient-notice-transition'),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                switchInCurve: Easing.emphasizedDecelerate,
                switchOutCurve: Easing.emphasizedAccelerate,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.16),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: switch (_playbackNoticeMessage) {
                  final message? => _PlaybackTransientNotice(
                    key: ValueKey(
                      'playback-transient-notice-$_playbackNoticeRevision',
                    ),
                    message: message,
                    error: _playbackNoticeError,
                  ),
                  null => const SizedBox.shrink(
                    key: ValueKey('playback-transient-notice-empty'),
                  ),
                },
              ),
            ),
          ),
        ),
      ],
    );
    return KeyedSubtree(
      key: ValueKey(
        widget.authenticated ? 'user-library-page' : 'signed-out-main-page',
      ),
      child: PageStorage(
        bucket: _pageStorageBucket,
        child: PopScope<void>(
          canPop: !hasLocalPage,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && hasLocalPage) {
              _returnFromLocalPage();
            }
          },
          child: pageWithNotice,
        ),
      ),
    );
  }

  Widget _buildLocalRoute(AuthenticatedLocalRoute route) => switch (route) {
    PlaylistLocalRoute() => _buildPlaylistRoute(route),
    RankingLocalRoute() => _buildRankingRoute(route),
    ArtistLocalRoute() => _buildArtistRoute(route),
    AlbumLocalRoute() => _buildAlbumRoute(route),
    ExpandedNowPlayingLocalRoute() => const SizedBox.shrink(),
    SettingsLocalRoute() => _buildSettingsRoute(),
  };

  bool _usesPrimaryShell(AuthenticatedLocalRoute route) =>
      route is PlaylistLocalRoute ||
      route is AlbumLocalRoute ||
      route is RankingLocalRoute ||
      route is ArtistLocalRoute ||
      route is SettingsLocalRoute;

  Widget _buildSettingsRoute({
    bool embedded = false,
    bool showToolbar = true,
    bool compactHierarchy = false,
  }) => SettingsPage(
    key: const ValueKey('settings-page'),
    settings: widget.settings,
    onSettingsChanged: widget.onSettingsChanged,
    onBack: _returnFromSettings,
    onCompactSectionSelected: _openCompactSettingsSection,
    selectedSection: _settingsSection,
    compactSectionOpen: _compactSettingsSectionOpen,
    compactHierarchy: compactHierarchy,
    searchQuery: _settingsSearchQuery,
    embedded: embedded,
    showToolbar: showToolbar,
    systemLightColorScheme: widget.systemLightColorScheme,
    systemDarkColorScheme: widget.systemDarkColorScheme,
  );

  Widget _buildPlaylistRoute(
    PlaylistLocalRoute route, {
    bool embedded = false,
  }) => PlaylistDetailPage(
    key: ValueKey(_playlistRouteKey(route)),
    playlist: route.playlist,
    gateway: _library.playlistDetailGateway,
    queuePlaybackController: _queuePlaybackController,
    onBack: _returnFromTopRoute,
    onOpenAlbum: _openTrackContextAlbum,
    onOpenArtist: _openTrackContextArtist,
    onSignInAgain: widget.onSignInAgain,
    onHeaderCollapsedChanged: embedded
        ? (collapsed) =>
              _updateCollectionDetailHeaderCollapsed(route, collapsed)
        : null,
    onShellActionChanged: embedded
        ? (actions) => _updateCollectionShellActions(route, actions)
        : null,
    embedded: embedded,
  );

  Widget _buildAlbumRoute(AlbumLocalRoute route, {bool embedded = false}) =>
      AlbumPage(
        key: ValueKey(_albumRouteKey(route)),
        album: route.album,
        gateway: _library.albumTrackGateway,
        detailsGateway: _library.albumDetailsGateway,
        queuePlaybackController: _queuePlaybackController,
        onBack: _returnFromTopRoute,
        onOpenArtist: _albumCanOpenArtist(route.origin)
            ? _openAlbumContextArtist
            : null,
        onHeaderCollapsedChanged: embedded
            ? (collapsed) =>
                  _updateCollectionDetailHeaderCollapsed(route, collapsed)
            : null,
        onShellActionsChanged: embedded
            ? (actions) => _updateCollectionShellActions(route, actions)
            : null,
        embedded: embedded,
        backTooltip: _albumBackTooltip(route.origin),
        onSignInAgain: widget.onSignInAgain,
      );

  Widget _buildRankingRoute(RankingLocalRoute route, {bool embedded = false}) =>
      RankingPage(
        key: ValueKey('ranking-detail-${route.ranking.opaqueId}'),
        ranking: route.ranking,
        gateway: _discovery.rankingGateway,
        queuePlaybackController: _queuePlaybackController,
        onBack: _returnFromTopRoute,
        onOpenAlbum: _openTrackContextAlbum,
        onOpenArtist: _openTrackContextArtist,
        onHeaderCollapsedChanged: embedded
            ? (collapsed) =>
                  _updateCollectionDetailHeaderCollapsed(route, collapsed)
            : null,
        onShellActionsChanged: embedded
            ? (actions) => _updateCollectionShellActions(route, actions)
            : null,
        embedded: embedded,
        onSignInAgain: widget.onSignInAgain,
      );

  Widget _buildArtistRoute(ArtistLocalRoute route, {bool embedded = false}) =>
      ArtistPage(
        key: ValueKey(_artistRouteKey(route)),
        artist: route.artist,
        gateway: _library.artistTrackGateway,
        albumGateway: _library.artistAlbumGateway,
        queuePlaybackController: _queuePlaybackController,
        onBack: _returnFromTopRoute,
        onOpenAlbum: (album) => _openAlbumFromArtist(route.origin, album),
        backTooltip: _artistBackTooltip(route.origin),
        onSignInAgain: widget.onSignInAgain,
        onHeaderCollapsedChanged: embedded
            ? (collapsed) =>
                  _updateCollectionDetailHeaderCollapsed(route, collapsed)
            : null,
        onShellActionsChanged: embedded
            ? (actions) => _updateCollectionShellActions(route, actions)
            : null,
        embedded: embedded,
      );

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
    ArtistRouteOrigin.search => context.l10n.commonBack,
    ArtistRouteOrigin.favoriteArtists =>
      context.l10n.shellBackToFavoriteArtists,
    ArtistRouteOrigin.trackContext => context.l10n.shellBackToPlaylist,
    ArtistRouteOrigin.album => context.l10n.shellBackToAlbum,
    ArtistRouteOrigin.nowPlaying => context.l10n.shellBackToPreviousPage,
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
    AlbumRouteOrigin.search => context.l10n.shellBackToSearchResults,
    AlbumRouteOrigin.searchArtist ||
    AlbumRouteOrigin.favoriteArtist ||
    AlbumRouteOrigin.trackContextArtist ||
    AlbumRouteOrigin.albumArtist ||
    AlbumRouteOrigin.nowPlayingArtist => context.l10n.shellBackToArtist,
    AlbumRouteOrigin.discover => context.l10n.shellBackToNewAlbums,
    AlbumRouteOrigin.favoriteAlbums => context.l10n.shellBackToFavoriteAlbums,
    AlbumRouteOrigin.trackContext => context.l10n.shellBackToPlaylist,
    AlbumRouteOrigin.nowPlaying => context.l10n.shellBackToPreviousPage,
  };

  bool _albumCanOpenArtist(AlbumRouteOrigin origin) =>
      origin != AlbumRouteOrigin.albumArtist &&
      origin != AlbumRouteOrigin.nowPlaying &&
      origin != AlbumRouteOrigin.nowPlayingArtist;

  void _returnFromLocalPage() {
    if (_navigation.topRoute is SettingsLocalRoute &&
        _compactSettingsSectionOpen &&
        MediaQuery.sizeOf(context).width < 840) {
      setState(() => _compactSettingsSectionOpen = false);
      return;
    }
    if (!_navigation.canGoBack) return;
    final previousPrimary = _primaryDestination;
    late final AuthenticatedBackResult result;
    setState(() {
      result = _navigation.goBack();
      _collectionDetailCollapsedByRoute.remove(
        _collectionRouteIdentity(result.route),
      );
      _collectionShellActions.remove(_collectionRouteIdentity(result.route));
      _collectionDetailHeaderCollapsed = _currentCollectionCollapsed;
    });
    _restoreFocusAfterBack(result, previousPrimary: previousPrimary);
  }

  void _returnFromTopRoute() {
    if (!_navigation.hasLocalRoute) return;
    final previousPrimary = _primaryDestination;
    late final AuthenticatedLocalRoute route;
    setState(() {
      route = _navigation.popRoute()!;
      _collectionDetailCollapsedByRoute.remove(_collectionRouteIdentity(route));
      _collectionShellActions.remove(_collectionRouteIdentity(route));
      _collectionDetailHeaderCollapsed = _currentCollectionCollapsed;
    });
    _restoreFocusAfterBack(
      AuthenticatedBackResult.localRoute(route),
      previousPrimary: previousPrimary,
    );
  }

  void _returnFromSettings() {
    if (_compactSettingsSectionOpen && MediaQuery.sizeOf(context).width < 840) {
      setState(() => _compactSettingsSectionOpen = false);
      return;
    }
    _returnFromTopRoute();
  }

  void _restoreFocusAfterBack(
    AuthenticatedBackResult result, {
    required AuthenticatedPrimaryDestination previousPrimary,
  }) {
    switch (result.target) {
      case AuthenticatedBackTarget.none:
        return;
      case AuthenticatedBackTarget.likedRoot:
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
          SettingsLocalRoute() => _settingsReturnFocusNode,
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
      _selectLibrarySection(LibrarySection.likedSongs);
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

  bool get _canDismissShellDetail =>
      _navigation.routes.length == 1 &&
      (_navigation.routes.single is PlaylistLocalRoute ||
          _navigation.routes.single is AlbumLocalRoute ||
          _navigation.routes.single is RankingLocalRoute ||
          _navigation.routes.single is ArtistLocalRoute ||
          _navigation.routes.single is SettingsLocalRoute);

  void _selectPrimaryDestination(AuthenticatedPrimaryDestination destination) {
    if (destination == AuthenticatedPrimaryDestination.recentPlays &&
        !widget.capabilities.recentHistory) {
      return;
    }
    if (!widget.authenticated &&
        (destination == AuthenticatedPrimaryDestination.library ||
            destination == AuthenticatedPrimaryDestination.recentPlays)) {
      widget.onRequestSignIn();
      return;
    }
    if (_navigation.hasLocalRoute && !_canDismissShellDetail) return;
    final needsLikedRootReset =
        destination == AuthenticatedPrimaryDestination.library &&
        _librarySection != LibrarySection.likedSongs;
    if (!_navigation.hasLocalRoute &&
        _primaryDestination == destination &&
        !needsLikedRootReset) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (_canDismissShellDetail) {
        _navigation.popRoute();
        _collectionDetailHeaderCollapsed = false;
      }
      if (_primaryDestination != destination) {
        _navigation.selectPrimaryDestination(destination);
      }
      if (destination == AuthenticatedPrimaryDestination.library) {
        _navigation.selectLibrarySection(LibrarySection.likedSongs);
      }
    });
  }

  void _submitTopSearch(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    _topSearchSuggestionController.dismiss();
    _selectPrimaryDestination(AuthenticatedPrimaryDestination.search);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_searchOpen) return;
      _trackSearchPageKey.currentState?.submitTrackQuery(normalized);
    });
  }

  void _updateSettingsSearch(String query) {
    if (_settingsSearchQuery == query) return;
    setState(() => _settingsSearchQuery = query);
  }

  void _selectSettingsSection(SettingsSection section) {
    if (_settingsSection == section && _settingsSearchQuery.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _settingsSearchController.clear();
    setState(() {
      _settingsSearchQuery = '';
      _settingsSection = section;
    });
  }

  Future<void> _changePlaybackQuality(
    AppPlaybackQualityPreference preference,
  ) async {
    if (preference == widget.settings.playbackQuality) return;
    final wasActive =
        _queuePlaybackController.playback.stage == TrackPlaybackStage.playing ||
        _queuePlaybackController.playback.stage == TrackPlaybackStage.paused;
    final result = await widget.onSettingsChanged(
      widget.settings.copyWith(playbackQuality: preference),
    );
    if (!mounted) return;
    if (result != AppSettingsWriteResult.saved) {
      _showPlaybackNotice(context.l10n.libraryQualitySaveFailure, error: true);
      return;
    }

    if (wasActive) await _queuePlaybackController.reloadCurrentSource();
    if (!mounted) return;
    final actual = _queuePlaybackController.playback.resolvedQuality;
    _showPlaybackNotice(
      preference.localizedSelectionMessage(context.l10n, actual),
    );
  }

  void _showPlaybackNotice(String message, {bool error = false}) {
    _playbackNoticeTimer?.cancel();
    setState(() {
      _playbackNoticeMessage = message;
      _playbackNoticeError = error;
      _playbackNoticeRevision++;
    });
    _playbackNoticeTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _playbackNoticeMessage = null);
    });
  }

  Future<bool> _changeLyricAuxiliaryMode(LyricAuxiliaryMode mode) async {
    if (mode == widget.settings.lyricAuxiliaryMode) return true;
    final result = await widget.onSettingsChanged(
      widget.settings.copyWith(lyricAuxiliaryMode: mode),
    );
    if (!mounted) return result == AppSettingsWriteResult.saved;
    if (result != AppSettingsWriteResult.saved) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.settingsSaveFailure)));
      return false;
    }
    return true;
  }

  void _openCompactSettingsSection(SettingsSection section) {
    FocusManager.instance.primaryFocus?.unfocus();
    _settingsSearchController.clear();
    setState(() {
      _settingsSearchQuery = '';
      _settingsSection = section;
      _compactSettingsSectionOpen = true;
    });
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
    _selectPrimaryDestination(AuthenticatedPrimaryDestination.library);
  }

  void _openSettings() {
    if (_navigation.topRoute is SettingsLocalRoute) return;
    if (_navigation.hasLocalRoute && !_canDismissShellDetail) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _settingsSearchController.clear();
    setState(() {
      if (_canDismissShellDetail) {
        _navigation.popRoute();
        _collectionDetailHeaderCollapsed = false;
      }
      _settingsSection = SettingsSection.appearance;
      _compactSettingsSectionOpen = false;
      _settingsSearchQuery = '';
      _navigation.push(const SettingsLocalRoute());
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
    if (_navigation.topRoute is ExpandedNowPlayingLocalRoute) {
      _navigation.popRoute();
    }
    _pushLocalRoute(
      AlbumLocalRoute(album: album, origin: AlbumRouteOrigin.nowPlaying),
    );
  }

  void _openNowPlayingArtist(ArtistSummary artist) {
    if (_navigation.topRoute is ExpandedNowPlayingLocalRoute) {
      _navigation.popRoute();
    }
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
    if ((_librarySection != LibrarySection.albums &&
            _librarySection != LibrarySection.likedSongs) ||
        _navigation.hasLocalRoute) {
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
    setState(() {
      _collectionDetailHeaderCollapsed = false;
      final identity = _collectionRouteIdentity(route);
      if (identity != null) _collectionDetailCollapsedByRoute[identity] = false;
      _navigation.push(route);
    });
  }

  Widget _libraryDestinationBody({Widget? likedCollapsedHeaderActions}) {
    if (!widget.authenticated) {
      return _signedOutLibraryBody();
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
              title: context.l10n.libraryYourPlaylists,
              subtitle: switch (_controller.stage) {
                UserLibraryStage.content || UserLibraryStage.empty =>
                  context.l10n.libraryPlaylistsSavedCount(
                    _controller.playlists.length,
                    _providerDisplayName,
                  ),
                _ => context.l10n.libraryPlaylistsSavedProvider(
                  _providerDisplayName,
                ),
              },
              refreshKey: const ValueKey('user-playlists-refresh'),
              refreshTooltip: _controller.isRefreshing
                  ? context.l10n.libraryRefreshingPlaylists
                  : context.l10n.libraryRefreshPlaylists,
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
                  providerDisplayName: _providerDisplayName,
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
                  providerDisplayName: _providerDisplayName,
                )
              else
                const SizedBox.shrink(),
              if (_navigation.visitedLibrarySection(LibrarySection.likedSongs))
                _likedSongsBody(
                  collapsedHeaderActions: likedCollapsedHeaderActions,
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _likedSongsBody({Widget? collapsedHeaderActions}) {
    final playlist = _controller.likedSongsPlaylist;
    return switch (_controller.stage) {
      UserLibraryStage.loading => const _LibraryLoading(),
      UserLibraryStage.error ||
      UserLibraryStage.authenticationRequired ||
      UserLibraryStage.credentialRejected => _libraryBody(),
      UserLibraryStage.content || UserLibraryStage.empty => LikedSongsPage(
        key: ValueKey(
          'liked-songs-${playlist?.providerId ?? 'shell-unavailable'}',
        ),
        playlist: playlist,
        playlists: _controller.playlists,
        gateway: _library.playlistDetailGateway,
        favoriteAlbumGateway: _library.favoriteAlbumGateway,
        queuePlaybackController: _queuePlaybackController,
        onOpenPlaylist: _openPlaylist,
        lastOpenedPlaylist: _lastOpenedPlaylist,
        playlistReturnFocusNode: _playlistReturnFocusNode,
        onOpenAlbum: _openTrackContextAlbum,
        onOpenFavoriteAlbum: _openFavoriteAlbum,
        onOpenArtist: _openTrackContextArtist,
        onSignInAgain: widget.onSignInAgain,
        onHeaderCollapsedChanged: _updateLikedHeaderCollapsed,
        collapsedHeaderActions: collapsedHeaderActions,
        providerDisplayName: _providerDisplayName,
      ),
    };
  }

  void _updateLikedHeaderCollapsed(bool collapsed) {
    if (!mounted || collapsed == _likedHeaderCollapsed) return;
    setState(() => _likedHeaderCollapsed = collapsed);
  }

  void _updateRecentHeaderCollapsed(bool collapsed) {
    if (!mounted || collapsed == _recentHeaderCollapsed) return;
    setState(() => _recentHeaderCollapsed = collapsed);
  }

  void _updateTopSearchFocus(bool focused) {
    if (!mounted || focused == _topSearchFocused) return;
    setState(() => _topSearchFocused = focused);
  }

  void _selectTopSearchSuggestion(String query) {
    _topSearchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _submitTopSearch(query);
  }

  void _updateDiscoverHeaderCollapsed(bool collapsed) {
    if (!mounted || collapsed == _discoverHeaderCollapsed) return;
    setState(() => _discoverHeaderCollapsed = collapsed);
  }

  String? _collectionRouteIdentity(AuthenticatedLocalRoute? route) =>
      switch (route) {
        PlaylistLocalRoute(:final playlist) =>
          'playlist:${playlist.providerId}:${playlist.opaqueId}',
        AlbumLocalRoute(:final album) =>
          'album:${album.providerId}:${album.opaqueId}',
        RankingLocalRoute(:final ranking) =>
          'ranking:${ranking.providerId}:${ranking.opaqueId}',
        ArtistLocalRoute(:final artist) =>
          'artist:${artist.providerId}:${artist.opaqueId}',
        _ => null,
      };

  void _updateCollectionShellActions(
    AuthenticatedLocalRoute route,
    CollectionDetailActions? actions,
  ) {
    if (!mounted) return;
    final identity = _collectionRouteIdentity(route);
    if (identity == null ||
        _collectionRouteIdentity(_navigation.topRoute) != identity) {
      return;
    }
    final previous = _collectionShellActions[identity];
    if (actions == null) {
      if (previous == null) return;
      setState(() => _collectionShellActions.remove(identity));
      return;
    }
    if (previous?.playing == actions.playing &&
        previous?.refreshing == actions.refreshing &&
        previous?.playAllLabel == actions.playAllLabel &&
        previous?.refreshLabel == actions.refreshLabel &&
        (previous?.onPlayAll == null) == (actions.onPlayAll == null) &&
        (previous?.onRefresh == null) == (actions.onRefresh == null)) {
      return;
    }
    setState(() => _collectionShellActions[identity] = actions);
  }

  bool get _currentCollectionCollapsed {
    final identity = _collectionRouteIdentity(_navigation.topRoute);
    return identity == null
        ? false
        : _collectionDetailCollapsedByRoute[identity] ?? false;
  }

  void _updateCollectionDetailHeaderCollapsed(
    AuthenticatedLocalRoute route,
    bool collapsed,
  ) {
    if (!mounted) return;
    final identity = _collectionRouteIdentity(route);
    if (identity == null) return;
    final isCurrent =
        _collectionRouteIdentity(_navigation.topRoute) == identity;
    if (_collectionDetailCollapsedByRoute[identity] == collapsed &&
        (!isCurrent || _collectionDetailHeaderCollapsed == collapsed)) {
      return;
    }
    setState(() {
      _collectionDetailCollapsedByRoute[identity] = collapsed;
      if (isCurrent) _collectionDetailHeaderCollapsed = collapsed;
    });
  }

  Widget _primaryScaffold({
    List<AuthenticatedLocalRoute> embeddedShellRoutes = const [],
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final embeddedShellRoute = embeddedShellRoutes.isEmpty
          ? null
          : embeddedShellRoutes.last;
      final destination = _primaryDestination;
      final wide = constraints.maxWidth >= 840;
      final extendedSidebar = constraints.maxWidth >= 1100;
      final compactActions = constraints.maxWidth < 520;
      final likedSongsOpen =
          destination == AuthenticatedPrimaryDestination.library &&
          _librarySection == LibrarySection.likedSongs;
      final settingsOpen = embeddedShellRoute is SettingsLocalRoute;
      final collectionDetailOpen =
          embeddedShellRoute is PlaylistLocalRoute ||
          embeddedShellRoute is AlbumLocalRoute ||
          embeddedShellRoute is RankingLocalRoute ||
          embeddedShellRoute is ArtistLocalRoute;
      final catalogDetailOpen = collectionDetailOpen;
      final collectionDetailTitle = switch (embeddedShellRoute) {
        PlaylistLocalRoute(:final playlist) => playlist.title,
        AlbumLocalRoute(:final album) => album.title,
        RankingLocalRoute(:final ranking) => ranking.title,
        ArtistLocalRoute(:final artist) => artist.name,
        _ => null,
      };
      final collectionIdentity = _collectionRouteIdentity(embeddedShellRoute);
      final collectionShellActions =
          _collectionShellActions[collectionIdentity];
      final likedHeaderOwnsTopBar =
          likedSongsOpen && embeddedShellRoute == null && _likedHeaderCollapsed;
      final recentCollapsed =
          destination == AuthenticatedPrimaryDestination.recentPlays &&
          embeddedShellRoute == null &&
          _recentHeaderCollapsed &&
          constraints.maxHeight >= 480 &&
          !_topSearchFocused;
      final compactRecentShellOwnsTopBar = recentCollapsed && compactActions;
      final recentHeaderOwnsTopBar = recentCollapsed && !compactActions;
      final discoverRootOpen =
          destination == AuthenticatedPrimaryDestination.discover &&
          embeddedShellRoute == null;
      final primaryContent = _RetainedPrimaryDestinationTransition(
        index: destination.index,
        children: [
          HomePage(
            key: const ValueKey('home-page'),
            homeController: _homeController,
            recommendationController: _recommendedPlaylistController,
            newSongController: _homeNewSongController,
            radarController: _homeRadarController,
            radarEnabled: widget.capabilities.radar,
            dailyTracksEnabled: widget.capabilities.dailyTracks,
            personalFmEnabled: widget.capabilities.personalFm,
            queuePlaybackController: _queuePlaybackController,
            authenticated: widget.authenticated,
            providerDisplayName: _providerDisplayName,
            active:
                destination == AuthenticatedPrimaryDestination.home &&
                embeddedShellRoute == null &&
                !_overlayPageActive,
            onOpenDiscover: () {
              _discoverNavigationController.show(DiscoverDestination.playlists);
              _selectPrimaryDestination(
                AuthenticatedPrimaryDestination.discover,
              );
            },
            onOpenLibrary: _openLikedSongs,
            onOpenRecommendation: _openHomeRecommendation,
            onOpenTrackAlbum: _openTrackContextAlbum,
            onOpenTrackArtist: _openTrackContextArtist,
            lastOpenedRecommendation: _lastOpenedHomeRecommendation,
            recommendationReturnFocusNode: _homeRecommendationReturnFocusNode,
          ),
          if (_navigation.visitedDestination(
            AuthenticatedPrimaryDestination.discover,
          ))
            KeyedSubtree(
              key: const ValueKey('recommended-playlists-page'),
              child: RecommendedPlaylistsPage(
                key: ValueKey(
                  'recommended-playlists-page-${widget.settings.musicProvider.providerId}',
                ),
                gateway: _discovery.recommendedPlaylistGateway,
                newAlbumGateway: _discovery.newAlbumGateway,
                newSongGateway: _discovery.newSongGateway,
                rankingGateway: _discovery.rankingGateway,
                radarGateway: _discovery.radarGateway,
                radarEnabled: widget.capabilities.radar,
                supportedNewAlbumRegions:
                    widget.capabilities.supportedNewAlbumRegions,
                supportedNewSongCategories:
                    widget.capabilities.supportedNewSongCategories,
                queuePlaybackController: _queuePlaybackController,
                onBack: _returnFromLocalPage,
                onOpenPlaylist: _openRecommendedPlaylist,
                onOpenRanking: _openRanking,
                onOpenAlbum: _openRecommendedAlbum,
                onOpenTrackAlbum: _openTrackContextAlbum,
                onOpenTrackArtist: _openTrackContextArtist,
                onSignInAgain: widget.onSignInAgain,
                providerDisplayName: _providerDisplayName,
                onHeaderCollapsedChanged: _updateDiscoverHeaderCollapsed,
                navigationController: _discoverNavigationController,
                embedded: true,
              ),
            )
          else
            const SizedBox.shrink(),
          if (_navigation.visitedDestination(
            AuthenticatedPrimaryDestination.search,
          ))
            TrackSearchPage(
              key: _trackSearchPageKey,
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
              providerDisplayName: _providerDisplayName,
              suggestionGateway: _discovery.trackSuggestionGateway,
              embedded: true,
            )
          else
            const SizedBox.shrink(),
          _libraryDestinationBody(
            likedCollapsedHeaderActions: Row(
              mainAxisSize: MainAxisSize.min,
              children: _primaryActions(
                compactActions: compactActions,
                showSettings: !wide,
                showAccount: !extendedSidebar,
                settingsSelected: false,
              ),
            ),
          ),
          if (widget.authenticated &&
              widget.capabilities.recentHistory &&
              _navigation.visitedDestination(
                AuthenticatedPrimaryDestination.recentPlays,
              ))
            RecentPlaysPage(
              key: const ValueKey('recent-plays-page'),
              gateway: _library.recentPlaysGateway,
              onHeaderCollapsedChanged: _updateRecentHeaderCollapsed,
              collapseSuppressed: _topSearchFocused,
              compactCollapsedTopBarInShell: compactRecentShellOwnsTopBar,
              collapsedHeaderActions: compactActions
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _primaryActions(
                        compactActions: compactActions,
                        showSettings: !wide,
                        showAccount: !extendedSidebar,
                        settingsSelected: false,
                      ),
                    ),
              playback: _queuePlaybackController,
              onSignInAgain: widget.onSignInAgain,
              onOpenAlbum: _openTrackContextAlbum,
              onOpenArtist: _openTrackContextArtist,
              active:
                  destination == AuthenticatedPrimaryDestination.recentPlays &&
                  embeddedShellRoute == null &&
                  !_overlayPageActive,
            )
          else
            const SizedBox.shrink(),
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
      final disableAnimations =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      final showCollectionShellControls =
          collectionDetailOpen && _collectionDetailHeaderCollapsed;
      final collectionRefreshAction =
          showCollectionShellControls &&
              collectionShellActions?.refreshLabel != null
          ? IconButton(
              key: const ValueKey('collection-detail-shell-refresh'),
              tooltip: collectionShellActions!.refreshLabel,
              onPressed: collectionShellActions.refreshing
                  ? null
                  : collectionShellActions.onRefresh,
              icon: collectionShellActions.refreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.refresh_rounded),
            )
          : null;
      final collectionPlayAction =
          showCollectionShellControls && collectionShellActions != null
          ? IconButton(
              key: const ValueKey('collection-detail-shell-play-all'),
              tooltip: collectionShellActions.playAllLabel,
              onPressed: collectionShellActions.playing
                  ? null
                  : collectionShellActions.onPlayAll,
              icon: collectionShellActions.playing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.play_arrow_rounded),
            )
          : null;
      final mainAppBar = AppBar(
        automaticallyImplyLeading: false,
        title: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: showCollectionShellControls ? kToolbarHeight : 0,
            minHeight: showCollectionShellControls ? kToolbarHeight : 0,
          ),
          child: Stack(
            key: const ValueKey('shell-top-bar-transition'),
            fit: StackFit.passthrough,
            children: [
              _PrimaryShellTitle(
                key: const ValueKey('primary-shell-top-bar'),
                onSearchFocusChanged: settingsOpen
                    ? null
                    : _updateTopSearchFocus,
                title: settingsOpen
                    ? context.l10n.settingsTitle
                    : collectionDetailTitle ??
                          switch (destination) {
                            AuthenticatedPrimaryDestination.home =>
                              context.l10n.navHome,
                            AuthenticatedPrimaryDestination.discover =>
                              context.l10n.navDiscover,
                            AuthenticatedPrimaryDestination.search =>
                              context.l10n.navSearch,
                            AuthenticatedPrimaryDestination.library =>
                              context.l10n.navLiked,
                            AuthenticatedPrimaryDestination.recentPlays =>
                              context.l10n.navRecentPlays,
                          },
                compact: compactActions,
                showTitle: settingsOpen
                    ? false
                    : catalogDetailOpen
                    ? false
                    : discoverRootOpen
                    ? _discoverHeaderCollapsed
                    : !likedSongsOpen &&
                          (destination !=
                                  AuthenticatedPrimaryDestination.recentPlays ||
                              compactRecentShellOwnsTopBar) &&
                          (destination !=
                                  AuthenticatedPrimaryDestination.home ||
                              !extendedSidebar),
                showSearchShortcut: settingsOpen
                    ? wide
                    : extendedSidebar &&
                          destination != AuthenticatedPrimaryDestination.search,
                searchKey: settingsOpen
                    ? const ValueKey('settings-search')
                    : const ValueKey('top-search-shortcut'),
                searchHint: settingsOpen
                    ? context.l10n.settingsSearchLabel
                    : context.l10n.shellSearchProvider(_providerDisplayName),
                searchController: settingsOpen
                    ? _settingsSearchController
                    : _topSearchController,
                onSearchChanged: settingsOpen ? _updateSettingsSearch : null,
                onSearchSubmitted: settingsOpen
                    ? _updateSettingsSearch
                    : _submitTopSearch,
                searchSuggestions: settingsOpen
                    ? null
                    : _topSearchSuggestionController,
                onSearchSuggestionSelected: settingsOpen
                    ? null
                    : _selectTopSearchSuggestion,
                searchEndInset:
                    (collectionPlayAction == null ? 0 : 48) +
                    (collectionRefreshAction == null ? 0 : 48),
              ),
              if (showCollectionShellControls)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      key: const ValueKey('collection-detail-shell-back'),
                      tooltip: context.l10n.commonBack,
                      onPressed: _returnFromTopRoute,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                ),
            ],
          ),
        ),
        titleSpacing: compactActions ? 8 : 16,
        actions: extendedSidebar
            ? [
                ?collectionPlayAction,
                ?collectionRefreshAction,
                SizedBox(
                  key: ValueKey(
                    settingsOpen
                        ? 'settings-shell-actions'
                        : 'music-shell-actions',
                  ),
                  width: 8,
                ),
              ]
            : [
                ?collectionPlayAction,
                ?collectionRefreshAction,
                AnimatedSwitcher(
                  key: const ValueKey('shell-account-actions-transition'),
                  duration: disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Easing.emphasizedDecelerate,
                  switchOutCurve: Easing.emphasizedAccelerate,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.12, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: settingsOpen
                      ? const SizedBox(
                          key: ValueKey('settings-shell-actions'),
                          width: 8,
                        )
                      : Row(
                          key: const ValueKey('music-shell-actions'),
                          mainAxisSize: MainAxisSize.min,
                          children: _primaryActions(
                            compactActions: compactActions,
                            showSettings: !wide,
                            showAccount: !extendedSidebar,
                            settingsSelected: false,
                          ),
                        ),
                ),
              ],
      );
      final musicSidebar = AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _DesktopMusicSidebar(
          destination: destination,
          librarySection: _librarySection,
          activePlaylist: switch (embeddedShellRoute) {
            PlaylistLocalRoute(:final playlist) => playlist,
            _ => null,
          },
          homeController: _homeController,
          libraryController: _controller,
          authenticated: widget.authenticated,
          providerDisplayName: _providerDisplayName,
          supportsRecentHistory: widget.capabilities.recentHistory,
          recommendationsFocusNode: _recommendationsReturnFocusNode,
          searchFocusNode: _searchReturnFocusNode,
          settingsSelected: settingsOpen,
          settingsFocusNode: _settingsReturnFocusNode,
          onRequestSignIn: widget.onRequestSignIn,
          onRequestSignOut: _signingOut ? null : _confirmSignOut,
          onDestinationSelected: _selectPrimaryDestination,
          onOpenLikedSongs: _openLikedSongs,
          onOpenSettings: _openSettings,
          onOpenPlaylist: (playlist) {
            _selectPrimaryDestination(AuthenticatedPrimaryDestination.library);
            _openPlaylist(playlist);
          },
        ),
      );
      final settingsUsesOwnToolbar = settingsOpen && !wide;
      final compactCatalogUsesOwnToolbar = compactActions && catalogDetailOpen;
      return Scaffold(
        key: const ValueKey('authenticated-primary-shell'),
        body: Row(
          children: [
            if (extendedSidebar)
              _SettingsShellNavigationTransition(
                open: settingsOpen,
                width: MusicSizes.desktopSidebar,
                base: musicSidebar,
                settings: _DesktopSettingsSidebar(
                  selectedSection: _settingsSection,
                  onBack: _returnFromTopRoute,
                  onSectionSelected: _selectSettingsSection,
                ),
              )
            else if (wide)
              _SettingsShellNavigationTransition(
                open: settingsOpen,
                width: MusicSizes.desktopRail,
                base: Column(
                  key: const ValueKey('music-navigation-rail-shell'),
                  children: [
                    Expanded(
                      child: NavigationRail(
                        key: const ValueKey('music-navigation-rail'),
                        selectedIndex: destination.index,
                        labelType: NavigationRailLabelType.all,
                        minWidth: MusicSizes.desktopRail,
                        minExtendedWidth: MusicSizes.desktopSidebar,
                        leading: _MusicSidebarBrand(
                          expanded: false,
                          providerDisplayName: _providerDisplayName,
                        ),
                        onDestinationSelected: _selectPrimaryDestinationByIndex,
                        destinations: _navigationRailDestinations(),
                      ),
                    ),
                    SizedBox(
                      height: 88,
                      child: NavigationRail(
                        key: const ValueKey('settings-entry-navigation-rail'),
                        selectedIndex: settingsOpen ? 0 : null,
                        labelType: NavigationRailLabelType.all,
                        minWidth: MusicSizes.desktopRail,
                        groupAlignment: 0,
                        onDestinationSelected: (_) => _openSettings(),
                        destinations: [
                          NavigationRailDestination(
                            icon: Focus(
                              key: const ValueKey('open-settings'),
                              focusNode: _settingsReturnFocusNode,
                              onKeyEvent: (_, event) {
                                if (event is KeyDownEvent &&
                                    (event.logicalKey ==
                                            LogicalKeyboardKey.enter ||
                                        event.logicalKey ==
                                            LogicalKeyboardKey.space)) {
                                  _openSettings();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: const Icon(Icons.settings_outlined),
                            ),
                            selectedIcon: const Icon(Icons.settings_rounded),
                            label: Text(context.l10n.settingsTitle),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                settings: _SettingsNavigationRail(
                  selectedSection: _settingsSection,
                  onBack: _returnFromTopRoute,
                  onSectionSelected: _selectSettingsSection,
                ),
              )
            else
              const SizedBox.shrink(),
            if (wide) const VerticalDivider(width: 1),
            if (!wide) const SizedBox.shrink(),
            Expanded(
              child: Scaffold(
                key: const ValueKey('authenticated-content-shell'),
                appBar:
                    settingsUsesOwnToolbar ||
                        compactCatalogUsesOwnToolbar ||
                        likedHeaderOwnsTopBar ||
                        recentHeaderOwnsTopBar
                    ? null
                    : mainAppBar,
                body: _CompactPlayerOverlay(
                  enabled: constraints.maxWidth < 640,
                  applyBottomSafeArea: settingsOpen,
                  player: NowPlayingBar(
                    controller: _queuePlaybackController,
                    onSignInAgain: widget.onSignInAgain,
                    qualityPreference: widget.settings.playbackQuality,
                    onQualityPreferenceChanged: _changePlaybackQuality,
                    lyricAuxiliaryMode: widget.settings.lyricAuxiliaryMode,
                    onLyricAuxiliaryModeChanged: _changeLyricAuxiliaryMode,
                  ),
                  child: _ShellDetailTransition(
                    open: embeddedShellRoute != null,
                    opaqueSurfaceKey: switch (embeddedShellRoute) {
                      PlaylistLocalRoute() ||
                      AlbumLocalRoute() ||
                      RankingLocalRoute() ||
                      ArtistLocalRoute() => const ValueKey(
                        'collection-detail-opaque-surface',
                      ),
                      SettingsLocalRoute() => const ValueKey(
                        'settings-detail-opaque-surface',
                      ),
                      _ => null,
                    },
                    base: Padding(
                      padding: EdgeInsets.only(
                        top: settingsUsesOwnToolbar ? kToolbarHeight : 0,
                      ),
                      child: mainBody,
                    ),
                    detail: IndexedStack(
                      index: embeddedShellRoutes.isEmpty
                          ? 0
                          : embeddedShellRoutes.length - 1,
                      children: embeddedShellRoutes.isEmpty
                          ? const [SizedBox.shrink()]
                          : [
                              for (final route in embeddedShellRoutes)
                                switch (route) {
                                  PlaylistLocalRoute() => _buildPlaylistRoute(
                                    route,
                                    embedded: true,
                                  ),
                                  AlbumLocalRoute() => _buildAlbumRoute(
                                    route,
                                    embedded: true,
                                  ),
                                  RankingLocalRoute() => _buildRankingRoute(
                                    route,
                                    embedded: true,
                                  ),
                                  ArtistLocalRoute() => _buildArtistRoute(
                                    route,
                                    embedded: true,
                                  ),
                                  SettingsLocalRoute() => _buildSettingsRoute(
                                    embedded: true,
                                    showToolbar: !wide,
                                    compactHierarchy: !wide,
                                  ),
                                  _ => const SizedBox.shrink(),
                                },
                            ],
                    ),
                  ),
                ),
                bottomNavigationBar: wide
                    ? NowPlayingBar(
                        controller: _queuePlaybackController,
                        onSignInAgain: widget.onSignInAgain,
                        qualityPreference: widget.settings.playbackQuality,
                        onQualityPreferenceChanged: _changePlaybackQuality,
                        lyricAuxiliaryMode: widget.settings.lyricAuxiliaryMode,
                        onLyricAuxiliaryModeChanged: _changeLyricAuxiliaryMode,
                      )
                    : constraints.maxWidth < 640
                    ? settingsOpen
                          ? null
                          : NavigationBar(
                              height: 72,
                              selectedIndex: destination.index,
                              onDestinationSelected:
                                  _selectPrimaryDestinationByIndex,
                              destinations: _navigationBarDestinations(),
                            )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NowPlayingBar(
                            controller: _queuePlaybackController,
                            onSignInAgain: widget.onSignInAgain,
                            qualityPreference: widget.settings.playbackQuality,
                            onQualityPreferenceChanged: _changePlaybackQuality,
                            lyricAuxiliaryMode:
                                widget.settings.lyricAuxiliaryMode,
                            onLyricAuxiliaryModeChanged:
                                _changeLyricAuxiliaryMode,
                          ),
                          if (!settingsOpen)
                            NavigationBar(
                              height: 72,
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
    NavigationRailDestination(
      icon: const Icon(
        Icons.home_outlined,
        key: ValueKey('primary-home-destination'),
      ),
      selectedIcon: const Icon(Icons.home_rounded),
      label: Text(context.l10n.navHome),
    ),
    NavigationRailDestination(
      icon: _destinationFocusIcon(
        key: const ValueKey('open-recommendations'),
        focusNode: _recommendationsReturnFocusNode,
        destination: AuthenticatedPrimaryDestination.discover,
        icon: Icons.explore_outlined,
      ),
      label: Text(context.l10n.navDiscover),
    ),
    NavigationRailDestination(
      icon: _destinationFocusIcon(
        key: const ValueKey('open-track-search'),
        focusNode: _searchReturnFocusNode,
        destination: AuthenticatedPrimaryDestination.search,
        icon: Icons.search_rounded,
      ),
      label: Text(context.l10n.navSearch),
    ),
    if (widget.authenticated)
      NavigationRailDestination(
        icon: const Icon(
          Icons.favorite_border_rounded,
          key: ValueKey('primary-library-destination'),
        ),
        selectedIcon: const Icon(Icons.favorite_rounded),
        label: Text(context.l10n.navLiked),
      ),
    if (widget.authenticated && widget.capabilities.recentHistory)
      NavigationRailDestination(
        icon: const Icon(
          Icons.history_rounded,
          key: ValueKey('open-recent-plays'),
        ),
        label: Text(context.l10n.navRecentPlays),
      ),
  ];

  List<NavigationDestination> _navigationBarDestinations() => [
    NavigationDestination(
      icon: const Icon(
        Icons.home_outlined,
        key: ValueKey('primary-home-destination'),
      ),
      selectedIcon: const Icon(Icons.home_rounded),
      label: context.l10n.navHome,
    ),
    NavigationDestination(
      icon: _destinationFocusIcon(
        key: const ValueKey('open-recommendations'),
        focusNode: _recommendationsReturnFocusNode,
        destination: AuthenticatedPrimaryDestination.discover,
        icon: Icons.explore_outlined,
      ),
      label: context.l10n.navDiscover,
    ),
    NavigationDestination(
      icon: _destinationFocusIcon(
        key: const ValueKey('open-track-search'),
        focusNode: _searchReturnFocusNode,
        destination: AuthenticatedPrimaryDestination.search,
        icon: Icons.search_rounded,
      ),
      label: context.l10n.navSearch,
    ),
    if (widget.authenticated)
      NavigationDestination(
        icon: const Icon(
          Icons.favorite_border_rounded,
          key: ValueKey('primary-library-destination'),
        ),
        selectedIcon: const Icon(Icons.favorite_rounded),
        label: context.l10n.navLiked,
      ),
    if (widget.authenticated && widget.capabilities.recentHistory)
      NavigationDestination(
        icon: const Icon(
          Icons.history_rounded,
          key: ValueKey('open-recent-plays'),
        ),
        label: context.l10n.navRecentPlays,
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

  List<Widget> _primaryActions({
    required bool compactActions,
    required bool showSettings,
    required bool showAccount,
    required bool settingsSelected,
  }) => [
    if (showSettings)
      IconButton(
        key: const ValueKey('open-settings'),
        tooltip: context.l10n.settingsTitle,
        isSelected: settingsSelected,
        onPressed: _openSettings,
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings_rounded),
      ),
    if (showAccount)
      IconButton(
        key: ValueKey(widget.authenticated ? 'sign-out' : 'sign-in'),
        tooltip: widget.authenticated
            ? context.l10n.shellSignOut
            : context.l10n.shellSignInToProvider(_providerDisplayName),
        onPressed: widget.authenticated
            ? (_signingOut ? null : _confirmSignOut)
            : widget.onRequestSignIn,
        icon: Icon(
          widget.authenticated ? Icons.logout_rounded : Icons.login_rounded,
        ),
      ),
    if (!compactActions && (showSettings || showAccount))
      const SizedBox(width: 8),
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
              message: _refreshFailureCopy(
                context.l10n,
                failure,
                _providerDisplayName,
              ),
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
    title: context.l10n.librarySignInTitle,
    detail: context.l10n.librarySignInDetail(_providerDisplayName),
    actions: [
      FilledButton.icon(
        key: const ValueKey('signed-out-library-sign-in'),
        onPressed: widget.onRequestSignIn,
        icon: const Icon(Icons.login_rounded),
        label: Text(context.l10n.shellSignIn),
      ),
    ],
  );

  Future<void> _confirmSignOut() async {
    final confirmed = await showAdaptiveConfirmation(
      context,
      title: context.l10n.librarySignOutConfirmTitle,
      message: context.l10n.librarySignOutConfirmDetail(_providerDisplayName),
      confirmLabel: context.l10n.shellSignOut,
      cancelKey: const ValueKey('sign-out-cancel'),
      confirmKey: const ValueKey('sign-out-confirm'),
      sheetKey: const ValueKey('sign-out-confirmation-sheet'),
      dialogKey: const ValueKey('sign-out-confirmation-dialog'),
      wrapper: (child) =>
          PlaybackShortcuts(controller: _queuePlaybackController, child: child),
    );
    if (!confirmed || !mounted) return;

    setState(() => _signingOut = true);
    _queuePlaybackController.invalidateCollectionSource();
    final signOut = widget.onSignOut();
    await _queuePlaybackController.stop();
    final result = await signOut;
    if (!mounted) return;
    setState(() => _signingOut = false);
    if (result == CredentialSignOutResult.coreUnavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.librarySignOutFailure)),
      );
    }
  }

  Widget _body(BuildContext context) => switch (_controller.stage) {
    UserLibraryStage.loading => const _LibraryLoading(
      key: ValueKey('user-library-loading'),
    ),
    UserLibraryStage.content => Column(
      key: const ValueKey('user-library-content'),
      children: [
        if (_controller.omittedPlaylistCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: PartialResultsNotice(
              omittedCount: _controller.omittedPlaylistCount,
              resultRevision: _controller.partialResultRevision,
            ),
          ),
        Expanded(
          child: _PlaylistCollection(
            key: const ValueKey('user-library-playlist-collection'),
            playlists: _controller.playlists,
            onSelected: _openPlaylist,
            returnFocusPlaylist: _lastOpenedPlaylist,
            returnFocusNode: _playlistReturnFocusNode,
          ),
        ),
      ],
    ),
    UserLibraryStage.empty => _LibraryEmpty(
      key: const ValueKey('user-library-empty'),
      providerDisplayName: _providerDisplayName,
    ),
    UserLibraryStage.error => _LibraryFailure(
      key: const ValueKey('user-library-error'),
      failure: _controller.failure,
      canRetry: _controller.canRetry,
      showSignInAgain: false,
      onRetry: _controller.retry,
      onSignInAgain: widget.onSignInAgain,
      providerDisplayName: _providerDisplayName,
    ),
    UserLibraryStage.authenticationRequired ||
    UserLibraryStage.credentialRejected => _LibraryFailure(
      key: const ValueKey('user-library-authentication-error'),
      failure: _controller.failure,
      canRetry: false,
      showSignInAgain: true,
      onRetry: _controller.retry,
      onSignInAgain: widget.onSignInAgain,
      providerDisplayName: _providerDisplayName,
    ),
  };
}

class _DesktopSettingsSidebar extends StatelessWidget {
  const _DesktopSettingsSidebar({
    required this.selectedSection,
    required this.onBack,
    required this.onSectionSelected,
  });

  final SettingsSection selectedSection;
  final VoidCallback onBack;
  final ValueChanged<SettingsSection> onSectionSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('desktop-settings-sidebar'),
    width: MusicSizes.desktopSidebar,
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: SizedBox(
                height: 60,
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('settings-sidebar-back'),
                      tooltip: context.l10n.shellBackToMusic,
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.settingsTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                key: const ValueKey('settings-sidebar-options'),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                children: [
                  _SidebarSectionLabel(context.l10n.navSettingsSection),
                  for (final section in SettingsSection.values)
                    _SidebarDestinationTile(
                      key: ValueKey('settings-nav-${section.name}'),
                      selected: selectedSection == section,
                      icon: section.icon,
                      selectedIcon: section.icon,
                      label: section.label(context.l10n),
                      onTap: () => onSectionSelected(section),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SettingsNavigationRail extends StatelessWidget {
  const _SettingsNavigationRail({
    required this.selectedSection,
    required this.onBack,
    required this.onSectionSelected,
  });

  final SettingsSection selectedSection;
  final VoidCallback onBack;
  final ValueChanged<SettingsSection> onSectionSelected;

  @override
  Widget build(BuildContext context) => NavigationRail(
    key: const ValueKey('settings-navigation-rail'),
    selectedIndex: selectedSection.index,
    labelType: NavigationRailLabelType.all,
    minWidth: MusicSizes.desktopRail,
    leading: Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: IconButton(
        key: const ValueKey('settings-rail-back'),
        tooltip: context.l10n.shellBackToMusic,
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    onDestinationSelected: (index) =>
        onSectionSelected(SettingsSection.values[index]),
    destinations: [
      for (final section in SettingsSection.values)
        NavigationRailDestination(
          icon: Icon(
            section.icon,
            key: ValueKey('settings-nav-${section.name}'),
          ),
          selectedIcon: Icon(section.icon),
          label: Text(section.label(context.l10n)),
        ),
    ],
  );
}

class _DesktopMusicSidebar extends StatelessWidget {
  const _DesktopMusicSidebar({
    required this.destination,
    required this.librarySection,
    required this.activePlaylist,
    required this.homeController,
    required this.libraryController,
    required this.authenticated,
    required this.providerDisplayName,
    required this.supportsRecentHistory,
    required this.recommendationsFocusNode,
    required this.searchFocusNode,
    required this.settingsSelected,
    required this.settingsFocusNode,
    required this.onRequestSignIn,
    required this.onRequestSignOut,
    required this.onDestinationSelected,
    required this.onOpenLikedSongs,
    required this.onOpenSettings,
    required this.onOpenPlaylist,
  });

  final AuthenticatedPrimaryDestination destination;
  final LibrarySection librarySection;
  final UserPlaylistSummary? activePlaylist;
  final HomeController homeController;
  final UserLibraryController libraryController;
  final bool authenticated;
  final String providerDisplayName;
  final bool supportsRecentHistory;
  final FocusNode recommendationsFocusNode;
  final FocusNode searchFocusNode;
  final bool settingsSelected;
  final FocusNode settingsFocusNode;
  final VoidCallback onRequestSignIn;
  final VoidCallback? onRequestSignOut;
  final ValueChanged<AuthenticatedPrimaryDestination> onDestinationSelected;
  final VoidCallback onOpenLikedSongs;
  final VoidCallback onOpenSettings;
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
            AnimatedBuilder(
              animation: homeController,
              builder: (context, _) => _SidebarIdentity(
                authenticated: authenticated,
                displayName: homeController.account?.displayName,
                avatarUri: homeController.account?.avatarUri,
                providerDisplayName: providerDisplayName,
                onRequestSignIn: onRequestSignIn,
                onRequestSignOut: onRequestSignOut,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Material(
                key: const ValueKey('sidebar-scroll-clip'),
                type: MaterialType.transparency,
                clipBehavior: Clip.hardEdge,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  children: [
                    _SidebarSectionLabel(context.l10n.navOnlineMusicSection),
                    _SidebarDestinationTile(
                      key: const ValueKey('primary-home-destination'),
                      selected:
                          destination == AuthenticatedPrimaryDestination.home,
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home_rounded,
                      label: context.l10n.navHome,
                      onTap: () => onDestinationSelected(
                        AuthenticatedPrimaryDestination.home,
                      ),
                    ),
                    _SidebarDestinationTile(
                      key: const ValueKey('open-recommendations'),
                      selected:
                          destination ==
                          AuthenticatedPrimaryDestination.discover,
                      icon: Icons.explore_outlined,
                      selectedIcon: Icons.explore_rounded,
                      label: context.l10n.navDiscover,
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
                      label: context.l10n.navSearch,
                      focusNode: searchFocusNode,
                      onTap: () => onDestinationSelected(
                        AuthenticatedPrimaryDestination.search,
                      ),
                    ),
                    if (authenticated) ...[
                      const SizedBox(height: MusicSpacing.contentGap),
                      _SidebarSectionLabel(context.l10n.navMyMusicSection),
                      _SidebarDestinationTile(
                        key: const ValueKey('open-liked-songs'),
                        selected:
                            destination ==
                                AuthenticatedPrimaryDestination.library &&
                            librarySection == LibrarySection.likedSongs &&
                            activePlaylist == null,
                        icon: Icons.favorite_border_rounded,
                        selectedIcon: Icons.favorite_rounded,
                        label: context.l10n.navLiked,
                        onTap: onOpenLikedSongs,
                      ),
                      if (supportsRecentHistory)
                        _SidebarDestinationTile(
                          key: const ValueKey('open-recent-plays'),
                          selected:
                              destination ==
                              AuthenticatedPrimaryDestination.recentPlays,
                          icon: Icons.history_rounded,
                          selectedIcon: Icons.history_rounded,
                          label: context.l10n.navRecentPlays,
                          onTap: () => onDestinationSelected(
                            AuthenticatedPrimaryDestination.recentPlays,
                          ),
                        ),
                      if (libraryController.stage == UserLibraryStage.content &&
                          libraryController.playlists.isNotEmpty) ...[
                        const SizedBox(height: MusicSpacing.contentGap),
                        _SidebarSectionLabel(
                          context.l10n.navYourPlaylistsSection,
                        ),
                        for (final playlist
                            in libraryController.playlists.where(
                              (playlist) => !playlist.isLikedSongs,
                            ))
                          ListTile(
                            key: ValueKey(
                              'sidebar-playlist-${playlist.opaqueId}',
                            ),
                            selected:
                                activePlaylist?.providerId ==
                                    playlist.providerId &&
                                activePlaylist?.opaqueId == playlist.opaqueId,
                            dense: true,
                            minTileHeight: 44,
                            shape: const StadiumBorder(),
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            selectedColor: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            leading: SizedBox.square(
                              dimension: 32,
                              child: _PlaylistArtwork(playlist: playlist),
                            ),
                            title: Tooltip(
                              message: playlist.title,
                              child: Text(
                                playlist.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onTap: () => onOpenPlaylist(playlist),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: _SidebarDestinationTile(
                key: const ValueKey('open-settings'),
                selected: settingsSelected,
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                label: context.l10n.settingsTitle,
                focusNode: settingsFocusNode,
                onTap: onOpenSettings,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SidebarIdentity extends StatelessWidget {
  const _SidebarIdentity({
    required this.authenticated,
    required this.displayName,
    required this.avatarUri,
    required this.providerDisplayName,
    required this.onRequestSignIn,
    required this.onRequestSignOut,
  });

  final bool authenticated;
  final String? displayName;
  final String? avatarUri;
  final String providerDisplayName;
  final VoidCallback onRequestSignIn;
  final VoidCallback? onRequestSignOut;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brandFallback = ColoredBox(
      key: const ValueKey('music-sidebar-brand'),
      color: colors.primary,
      child: Icon(Icons.graphic_eq_rounded, color: colors.onPrimary),
    );
    final action = authenticated ? onRequestSignOut : onRequestSignIn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Tooltip(
        message: authenticated
            ? context.l10n.shellSignOut
            : context.l10n.shellSignInToProvider(providerDisplayName),
        child: InkWell(
          key: const ValueKey('sidebar-account'),
          onTap: action,
          borderRadius: MusicRadii.control,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 44,
                  child: ClipOval(
                    child: !authenticated || avatarUri == null
                        ? brandFallback
                        : Image.network(
                            avatarUri!,
                            headers: musicArtworkRequestHeaders(avatarUri!),
                            fit: BoxFit.cover,
                            errorBuilder: musicArtworkErrorBuilder(
                              avatarUri!,
                              brandFallback,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'fura music',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        authenticated
                            ? displayName ??
                                  context.l10n.shellLoadingProviderAccount(
                                    providerDisplayName,
                                  )
                            : context.l10n.shellSignInToProvider(
                                providerDisplayName,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  authenticated ? Icons.logout_rounded : Icons.login_rounded,
                  key: ValueKey(authenticated ? 'sign-out' : 'sign-in'),
                  color: action == null
                      ? colors.onSurfaceVariant
                      : colors.primary,
                ),
              ],
            ),
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
  const _MusicSidebarBrand({
    required this.expanded,
    required this.providerDisplayName,
  });

  final bool expanded;
  final String providerDisplayName;

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
                          'fura music',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          context.l10n.shellProviderClient(providerDisplayName),
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
            : Tooltip(message: 'fura music', child: mark),
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
    required this.searchKey,
    required this.searchHint,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    this.searchEndInset = 0,
    this.onSearchFocusChanged,
    this.searchSuggestions,
    this.onSearchSuggestionSelected,
    super.key,
  });

  final String title;
  final bool compact;
  final bool showTitle;
  final bool showSearchShortcut;
  final Key searchKey;
  final String searchHint;
  final TextEditingController searchController;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final double searchEndInset;
  final ValueChanged<bool>? onSearchFocusChanged;
  final TrackSearchSuggestionController? searchSuggestions;
  final ValueChanged<String>? onSearchSuggestionSelected;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final transitionDuration = disableAnimations
        ? Duration.zero
        : MusicMotion.stateChange;
    final titleContent = AnimatedSwitcher(
      key: const ValueKey('shell-top-bar-title-transition'),
      duration: transitionDuration,
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.08, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: showTitle
          ? Semantics(
              key: const ValueKey('shell-top-bar-title-visible'),
              header: true,
              child: Text(
                title,
                key: ValueKey('shell-top-bar-title-$title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('shell-top-bar-title-hidden')),
    );
    final titleTransition = disableAnimations
        ? titleContent
        : AnimatedSize(
            duration: transitionDuration,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            child: titleContent,
          );
    if (!showSearchShortcut) return titleTransition;
    final search = _ShellSearchField(
      searchKey: searchKey,
      controller: searchController,
      hintText: searchHint,
      onChanged: onSearchChanged,
      onSubmitted: onSearchSubmitted,
      onFocusChanged: onSearchFocusChanged,
      suggestions: searchSuggestions,
      onSuggestionSelected: onSearchSuggestionSelected,
    );
    return Row(
      children: [
        titleTransition,
        TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: showTitle ? MusicSpacing.pageWide : 0,
            end: showTitle ? MusicSpacing.pageWide : 0,
          ),
          duration: transitionDuration,
          curve: Curves.easeInOutCubic,
          builder: (context, width, _) => SizedBox(width: width),
        ),
        Expanded(
          child: AnimatedAlign(
            alignment: !showTitle ? Alignment.center : Alignment.centerRight,
            duration: transitionDuration,
            curve: Curves.easeInOutCubic,
            child: Transform.translate(
              offset: Offset(
                Directionality.of(context) == TextDirection.ltr
                    ? searchEndInset / 2
                    : -searchEndInset / 2,
                0,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448),
                child: search,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShellSearchField extends StatefulWidget {
  const _ShellSearchField({
    required this.searchKey,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onSubmitted,
    required this.onFocusChanged,
    required this.suggestions,
    required this.onSuggestionSelected,
  });

  final Key searchKey;
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<bool>? onFocusChanged;
  final TrackSearchSuggestionController? suggestions;
  final ValueChanged<String>? onSuggestionSelected;

  @override
  State<_ShellSearchField> createState() => _ShellSearchFieldState();
}

class _ShellSearchFieldState extends State<_ShellSearchField> {
  late final FocusNode _focusNode;
  final MenuController _menuController = MenuController();

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'shell search');
    _focusNode.addListener(_handleFocus);
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    widget.suggestions?.addListener(_handleSuggestions);
  }

  @override
  void didUpdateWidget(_ShellSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.suggestions != widget.suggestions) {
      oldWidget.suggestions?.removeListener(_handleSuggestions);
      widget.suggestions?.addListener(_handleSuggestions);
    }
  }

  @override
  void dispose() {
    widget.suggestions?.removeListener(_handleSuggestions);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    super.dispose();
  }

  void _handleFocus() {
    widget.onFocusChanged?.call(_focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      widget.suggestions?.updateQuery(widget.controller.text);
    } else if (!_menuController.isOpen) {
      widget.suggestions?.dismiss();
    }
  }

  void _handleChanged(String value) {
    widget.onChanged?.call(value);
    widget.suggestions?.updateQuery(value);
  }

  void _handleSuggestions() {
    if (!mounted) return;
    final shouldOpen =
        _focusNode.hasFocus && (widget.suggestions?.visible ?? false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shouldOpen && !_menuController.isOpen) {
        _menuController.open();
      } else if (!shouldOpen && _menuController.isOpen) {
        _menuController.close();
      }
      setState(() {});
    });
  }

  void _selectSuggestion(String query) {
    _menuController.close();
    widget.suggestions?.dismiss();
    widget.onSuggestionSelected?.call(query);
  }

  void _handleMenuClosed() {
    final suggestions = widget.suggestions;
    if (suggestions?.visible ?? false) suggestions?.dismiss();
  }

  KeyEventResult _handleSuggestionKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final suggestions = widget.suggestions;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      return (suggestions?.moveHighlight(1) ?? false)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return (suggestions?.moveHighlight(-1) ?? false)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final query = suggestions?.highlightedQuery;
      if (query == null) return KeyEventResult.ignored;
      _selectSuggestion(query);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        (suggestions?.visible ?? false)) {
      _menuController.close();
      suggestions?.dismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    return _focusNode.hasFocus &&
        _handleSuggestionKeyEvent(_focusNode, event) == KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.suggestions;
    final search = SearchBar(
      key: widget.searchKey,
      controller: widget.controller,
      focusNode: _focusNode,
      onChanged: _handleChanged,
      onSubmitted: (query) {
        _menuController.close();
        suggestions?.dismiss();
        widget.onSubmitted(query);
      },
      textInputAction: TextInputAction.search,
      hintText: widget.hintText,
      leading: const Icon(Icons.search_rounded),
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(
        Theme.of(context).colorScheme.surfaceContainerHigh,
      ),
      constraints: const BoxConstraints(minHeight: 40),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
    );
    if (suggestions == null || !suggestions.enabled) return search;
    return LayoutBuilder(
      builder: (context, constraints) => MenuAnchor(
        controller: _menuController,
        childFocusNode: _focusNode,
        style: MenuStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          fixedSize: WidgetStatePropertyAll(
            Size.fromWidth(constraints.maxWidth),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
        ),
        alignmentOffset: const Offset(0, 8),
        crossAxisUnconstrained: false,
        consumeOutsideTap: false,
        onClose: _handleMenuClosed,
        menuChildren: [
          TrackSearchSuggestionsPanel(
            controller: suggestions,
            popup: true,
            onSelected: _selectSuggestion,
          ),
        ],
        builder: (context, controller, _) => search,
      ),
    );
  }
}

class _CompactPlayerOverlay extends StatelessWidget {
  const _CompactPlayerOverlay({
    required this.enabled,
    required this.applyBottomSafeArea,
    required this.player,
    required this.child,
  });

  final bool enabled;
  final bool applyBottomSafeArea;
  final Widget player;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final overlayPlayer = applyBottomSafeArea
        ? SafeArea(top: false, child: player)
        : player;
    return Stack(
      key: const ValueKey('compact-player-overlay-shell'),
      fit: StackFit.expand,
      children: [
        child,
        if (enabled)
          Align(alignment: Alignment.bottomCenter, child: overlayPlayer),
      ],
    );
  }
}

class _PlaybackTransientNotice extends StatelessWidget {
  const _PlaybackTransientNotice({
    required this.message,
    required this.error,
    super.key,
  });

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Material(
          key: const ValueKey('playback-transient-notice'),
          elevation: 6,
          color: error ? colors.errorContainer : colors.inverseSurface,
          shadowColor: colors.shadow.withValues(alpha: 0.22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: error
                    ? colors.onErrorContainer
                    : colors.onInverseSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
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
              Expanded(
                child: Text(
                  context.l10n.libraryPlaylistType,
                  style: mutedStyle,
                ),
              ),
              SizedBox(
                width: 104,
                child: Text(
                  context.l10n.libraryTrackCountColumn,
                  style: mutedStyle,
                ),
              ),
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
      label: _semanticLabel(context.l10n, playlist),
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
                        context.l10n.libraryPlaylistCount(count),
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
                        context.l10n.libraryPlaylistCount(count),
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
              headers: musicArtworkRequestHeaders(uri),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: musicArtworkErrorBuilder(
                uri,
                const _ArtworkPlaceholder(),
              ),
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
          context.l10n.libraryLoadingPlaylists,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({required this.providerDisplayName, super.key});

  final String providerDisplayName;

  @override
  Widget build(BuildContext context) => _CenteredLibraryMessage(
    icon: Icons.library_music_outlined,
    title: context.l10n.libraryNoPlaylistsTitle,
    detail: context.l10n.libraryNoPlaylistsDetail(providerDisplayName),
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
    required this.providerDisplayName,
    super.key,
  });

  final UserLibraryFailure? failure;
  final bool canRetry;
  final bool showSignInAgain;
  final VoidCallback onRetry;
  final VoidCallback onSignInAgain;
  final String providerDisplayName;

  @override
  Widget build(BuildContext context) {
    final (title, detail) = _failureCopy(
      context.l10n,
      failure,
      providerDisplayName,
    );
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
            child: Text(context.l10n.commonRetry),
          ),
        if (showSignInAgain)
          TextButton(
            onPressed: onSignInAgain,
            child: Text(context.l10n.authSignInAgain),
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
                  label: context.l10n.commonAnnouncement(detail, title),
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

(String, String) _failureCopy(
  AppLocalizations l10n,
  UserLibraryFailure? failure,
  String providerDisplayName,
) => switch (failure) {
  UserLibraryFailure.network => (
    l10n.libraryFailureReachTitle(providerDisplayName),
    l10n.libraryFailureReachCollectionDetail,
  ),
  UserLibraryFailure.serviceUnavailable => (
    l10n.libraryFailureUnavailableTitle(providerDisplayName),
    l10n.libraryFailureServiceCollectionDetail,
  ),
  UserLibraryFailure.invalidResponse => (
    l10n.libraryFailureCompleteTitle,
    l10n.libraryFailureCompleteDetail(providerDisplayName),
  ),
  UserLibraryFailure.credentialRejected => (
    l10n.libraryFailureRejectedTitle,
    l10n.libraryFailureRejectedDetail(providerDisplayName),
  ),
  UserLibraryFailure.credentialRejectedStorageCleanupFailed => (
    l10n.libraryFailureRejectedTitle,
    l10n.authSavedSessionRejectedCleanupDetail(providerDisplayName),
  ),
  UserLibraryFailure.authenticationRequired ||
  UserLibraryFailure.replaced ||
  UserLibraryFailure.cancelled => (
    l10n.libraryFailureSignInPlaylistsTitle,
    l10n.libraryFailureRequestChangedDetail,
  ),
  UserLibraryFailure.coreUnavailable => (
    l10n.libraryFailureCoreTitle,
    l10n.libraryFailureCoreCollectionDetail,
  ),
  UserLibraryFailure.alreadyRunning => (
    l10n.libraryFailureRunningCollectionTitle,
    l10n.libraryFailureRunningDetail,
  ),
  null => (
    l10n.libraryFailureGenericCollectionTitle,
    l10n.libraryFailureGenericCollectionDetail(providerDisplayName),
  ),
};

String _refreshFailureCopy(
  AppLocalizations l10n,
  UserLibraryFailure failure,
  String providerDisplayName,
) => l10n.libraryRefreshFailure;

String _semanticLabel(AppLocalizations l10n, UserPlaylistSummary playlist) {
  final count = playlist.trackCount;
  return count == null
      ? playlist.title
      : '${playlist.title}, ${l10n.libraryPlaylistCount(count)}';
}
