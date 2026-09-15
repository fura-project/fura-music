import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/discover/new_song_controller.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/radar_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/home_controller.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

abstract final class _HomeGeometry {
  static const double compactBreakpoint = 600;
  static const double widePadding = 24;
  static const double compactPadding = 16;
  static const double sectionGap = 32;
  static const double itemGap = 16;
  static const double wideHeroHeight = 280;
  static const double compactHeroHeight = 256;
  static const double compactShelfWidth = 136;
  static const double wideShelfMinWidth = 136;
  static const double wideShelfMaxWidth = 164;
  static const double trackRowHeight = 60;
  static const double trackArtworkSize = 44;
  static const BorderRadius heroRadius = BorderRadius.all(Radius.circular(12));
  static const BorderRadius artworkRadius = BorderRadius.all(
    Radius.circular(8),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({
    required this.homeController,
    required this.recommendationController,
    required this.newSongController,
    required this.radarController,
    this.radarEnabled = true,
    this.dailyTracksEnabled = false,
    this.personalFmEnabled = false,
    required this.queuePlaybackController,
    required this.authenticated,
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onOpenRecommendation,
    this.providerDisplayName,
    this.lastOpenedRecommendation,
    this.recommendationReturnFocusNode,
    this.spotlightRotationInterval = const Duration(seconds: 12),
    this.active = true,
    this.refreshInterval = const Duration(minutes: 15),
    this.now,
    super.key,
  });

  final HomeController homeController;
  final RecommendedPlaylistController recommendationController;
  final NewSongController newSongController;
  final RadarController radarController;
  final bool radarEnabled;
  final bool dailyTracksEnabled;
  final bool personalFmEnabled;
  final QueuePlaybackController queuePlaybackController;
  final bool authenticated;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final ValueChanged<RecommendedPlaylistSummary> onOpenRecommendation;
  final String? providerDisplayName;
  final RecommendedPlaylistSummary? lastOpenedRecommendation;
  final FocusNode? recommendationReturnFocusNode;
  final Duration spotlightRotationInterval;
  final bool active;
  final Duration refreshInterval;
  final DateTime Function()? now;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Timer? _spotlightTimer;
  Timer? _spotlightProgressTimer;
  Timer? _freshnessTimer;
  final ValueNotifier<double> _spotlightProgress = ValueNotifier(0);
  Duration _spotlightProgressElapsed = Duration.zero;
  late DateTime _lastRefresh;
  bool _returnToShelf = false;
  bool _refreshing = false;
  bool _foreground = true;
  DateTime? _spotlightDay;
  String? _spotlightIdentity;
  int _spotlightMotionDirection = 1;
  bool _spotlightAutoPlaying = true;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _lastRefresh = _now;
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    widget.homeController.setActive(widget.active && _foreground);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeHome();
    });
    _freshnessTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshIfStale(),
    );
    _startSpotlightTimer();
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      widget.homeController.setActive(widget.active && _foreground);
      _restartSpotlightTimer();
      if (widget.active) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _resumeHome();
        });
      }
    }
    if (oldWidget.spotlightRotationInterval !=
        widget.spotlightRotationInterval) {
      _restartSpotlightTimer();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    if (_animationsDisabled == animationsDisabled) return;
    _animationsDisabled = animationsDisabled;
    _restartSpotlightTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _freshnessTimer?.cancel();
    _spotlightTimer?.cancel();
    _spotlightProgressTimer?.cancel();
    _spotlightProgress.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    widget.homeController.setActive(widget.active && _foreground);
    _restartSpotlightTimer();
    if (_foreground) _resumeHome();
  }

  void _resumeHome() {
    if (!mounted || !widget.active || !_foreground) return;
    _refreshIfStale();
    if (!_refreshing && widget.homeController.relatedSeed == null) {
      widget.homeController.refreshRelatedTracks();
    }
  }

  void _refreshIfStale() {
    if (mounted &&
        widget.active &&
        _foreground &&
        _now.difference(_lastRefresh) >= widget.refreshInterval) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh({bool manual = false}) async {
    if (!mounted || _refreshing) return;
    setState(() => _refreshing = true);
    // Re-entry and the timer share one request group, including after failures.
    _lastRefresh = _now;
    try {
      await Future.wait([
        widget.recommendationController.load(),
        widget.newSongController.load(),
        if (widget.authenticated) widget.homeController.refresh(),
        if (widget.authenticated && widget.radarEnabled)
          widget.radarController.load(),
      ]);
      if (!mounted) return;
      if (!widget.authenticated && widget.active && _foreground) {
        widget.homeController.refreshRelatedTracks();
      }
      if (manual && widget.active && _foreground) {
        final failed =
            widget.recommendationController.stage ==
                RecommendedPlaylistStage.error ||
            widget.newSongController.stage == NewSongStage.error ||
            (widget.authenticated &&
                (widget.homeController.refreshHasErrors ||
                    (widget.radarEnabled &&
                        widget.radarController.stage == RadarStage.error)));
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              failed
                  ? context.l10n.homeRefreshPartialFailure
                  : context.l10n.homeRefreshSuccess(
                      widget.providerDisplayName ??
                          context.l10n.providerQqMusic,
                    ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  List<RecommendedPlaylistSummary> get _spotlightCandidates =>
      widget.authenticated
      ? widget.homeController.personalizedPlaylists
      : widget.recommendationController.playlists;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  void _openFeatured(RecommendedPlaylistSummary playlist) {
    _returnToShelf = false;
    widget.onOpenRecommendation(playlist);
  }

  void _openShelf(RecommendedPlaylistSummary playlist) {
    _returnToShelf = true;
    widget.onOpenRecommendation(playlist);
  }

  RecommendedPlaylistSummary? _resolveSpotlight() {
    final playlists = _spotlightCandidates;
    if (playlists.isEmpty) {
      _spotlightIdentity = null;
      return null;
    }
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final selectedIndex = playlists.indexWhere(
      (playlist) => _recommendationIdentity(playlist) == _spotlightIdentity,
    );
    if (_spotlightDay != day || selectedIndex < 0) {
      // Preserve the account feed's ranking; only the public feed uses a daily rotation.
      final selected = widget.authenticated
          ? playlists.first
          : selectHomeSpotlightForDay(playlists, day);
      _spotlightDay = day;
      _spotlightIdentity = selected == null
          ? null
          : _recommendationIdentity(selected);
      return selected;
    }
    return playlists[selectedIndex];
  }

  void _startSpotlightTimer() {
    if (!_spotlightAutoPlaying ||
        !widget.active ||
        !_foreground ||
        _animationsDisabled ||
        widget.spotlightRotationInterval <= Duration.zero) {
      return;
    }
    _spotlightTimer = Timer.periodic(widget.spotlightRotationInterval, (_) {
      _moveSpotlight(1);
      _restartSpotlightProgressTimer();
    });
    _startSpotlightProgressTimer();
  }

  void _restartSpotlightTimer() {
    _spotlightTimer?.cancel();
    _spotlightTimer = null;
    _spotlightProgressTimer?.cancel();
    _spotlightProgressTimer = null;
    _spotlightProgressElapsed = Duration.zero;
    _spotlightProgress.value = 0;
    _startSpotlightTimer();
  }

  void _startSpotlightProgressTimer() {
    _spotlightProgressTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (!mounted || widget.spotlightRotationInterval <= Duration.zero) {
          return;
        }
        _spotlightProgressElapsed += const Duration(milliseconds: 100);
        final progress =
            _spotlightProgressElapsed.inMicroseconds /
            widget.spotlightRotationInterval.inMicroseconds;
        _spotlightProgress.value = progress.clamp(0, 1);
      },
    );
  }

  void _restartSpotlightProgressTimer() {
    _spotlightProgressTimer?.cancel();
    _spotlightProgressElapsed = Duration.zero;
    _spotlightProgress.value = 0;
    if (_spotlightTimer != null) _startSpotlightProgressTimer();
  }

  void _moveSpotlight(int offset, {bool restartTimer = false}) {
    if (!mounted) return;
    final playlists = _spotlightCandidates;
    if (playlists.length < 2) {
      return;
    }
    final current = _resolveSpotlight();
    final currentIndex = current == null ? 0 : playlists.indexOf(current);
    final nextIndex = (currentIndex + offset) % playlists.length;
    setState(() {
      _spotlightMotionDirection = offset < 0 ? -1 : 1;
      _spotlightIdentity = _recommendationIdentity(playlists[nextIndex]);
    });
    if (restartTimer) {
      _restartSpotlightTimer();
    }
  }

  void _toggleSpotlightAutoPlay() {
    setState(() {
      _spotlightAutoPlaying = !_spotlightAutoPlaying;
    });
    _restartSpotlightTimer();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.homeController,
      widget.recommendationController,
      widget.newSongController,
      widget.radarController,
      widget.queuePlaybackController.currentTrackListenable,
    ]),
    builder: (context, _) {
      final spotlightPlaylist = _resolveSpotlight();
      final provider =
          widget.providerDisplayName ?? context.l10n.providerQqMusic;
      return SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < _HomeGeometry.compactBreakpoint) {
              return _HomeCompactLayout(
                onRefresh: _refreshing
                    ? null
                    : () => unawaited(_refresh(manual: true)),
                homeController: widget.homeController,
                recommendationController: widget.recommendationController,
                newSongController: widget.newSongController,
                radarController: widget.radarController,
                radarEnabled: widget.radarEnabled,
                dailyTracksEnabled: widget.dailyTracksEnabled,
                personalFmEnabled: widget.personalFmEnabled,
                queuePlaybackController: widget.queuePlaybackController,
                authenticated: widget.authenticated,
                providerDisplayName: provider,
                spotlightPlaylist: spotlightPlaylist,
                onPreviousSpotlight: () =>
                    _moveSpotlight(-1, restartTimer: true),
                onNextSpotlight: () => _moveSpotlight(1, restartTimer: true),
                spotlightAutoPlaying:
                    _spotlightAutoPlaying && !_animationsDisabled,
                spotlightAutoPlayAvailable: !_animationsDisabled,
                spotlightMotionDirection: _spotlightMotionDirection,
                spotlightProgress: _spotlightProgress,
                onToggleSpotlightAutoPlay: _toggleSpotlightAutoPlay,
                onOpenDiscover: widget.onOpenDiscover,
                onOpenLibrary: widget.onOpenLibrary,
                onOpenRecommendation: _openShelf,
                onOpenFeatured: _openFeatured,
                featuredReturnFocusNode: _returnToShelf
                    ? null
                    : widget.recommendationReturnFocusNode,
                lastOpenedRecommendation: widget.lastOpenedRecommendation,
                recommendationReturnFocusNode: _returnToShelf
                    ? widget.recommendationReturnFocusNode
                    : null,
              );
            }
            return _HomeWideLayout(
              onRefresh: _refreshing
                  ? null
                  : () => unawaited(_refresh(manual: true)),
              homeController: widget.homeController,
              recommendationController: widget.recommendationController,
              newSongController: widget.newSongController,
              radarController: widget.radarController,
              radarEnabled: widget.radarEnabled,
              dailyTracksEnabled: widget.dailyTracksEnabled,
              personalFmEnabled: widget.personalFmEnabled,
              queuePlaybackController: widget.queuePlaybackController,
              authenticated: widget.authenticated,
              providerDisplayName: provider,
              spotlightPlaylist: spotlightPlaylist,
              onPreviousSpotlight: () => _moveSpotlight(-1, restartTimer: true),
              onNextSpotlight: () => _moveSpotlight(1, restartTimer: true),
              spotlightAutoPlaying:
                  _spotlightAutoPlaying && !_animationsDisabled,
              spotlightAutoPlayAvailable: !_animationsDisabled,
              spotlightMotionDirection: _spotlightMotionDirection,
              spotlightProgress: _spotlightProgress,
              onToggleSpotlightAutoPlay: _toggleSpotlightAutoPlay,
              onOpenDiscover: widget.onOpenDiscover,
              onOpenLibrary: widget.onOpenLibrary,
              onOpenRecommendation: _openShelf,
              onOpenFeatured: _openFeatured,
              featuredReturnFocusNode: _returnToShelf
                  ? null
                  : widget.recommendationReturnFocusNode,
              lastOpenedRecommendation: widget.lastOpenedRecommendation,
              recommendationReturnFocusNode: _returnToShelf
                  ? widget.recommendationReturnFocusNode
                  : null,
            );
          },
        ),
      );
    },
  );
}

@visibleForTesting
RecommendedPlaylistSummary? selectHomeSpotlightForDay(
  List<RecommendedPlaylistSummary> playlists,
  DateTime day,
) {
  if (playlists.isEmpty) return null;
  final ordered = [...playlists]
    ..sort(
      (left, right) =>
          _recommendationIdentity(left)
              .compareTo(_recommendationIdentity(right)),
    );
  final normalizedDay = DateTime.utc(day.year, day.month, day.day);
  final dayNumber =
      normalizedDay.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  return ordered[dayNumber % ordered.length];
}

String _recommendationIdentity(RecommendedPlaylistSummary playlist) =>
    '${playlist.providerId}\u0000${playlist.opaqueId}';

class _HomeWideLayout extends StatelessWidget {
  const _HomeWideLayout({
    required this.onOpenFeatured,
    required this.featuredReturnFocusNode,
    required this.onRefresh,
    required this.homeController,
    required this.recommendationController,
    required this.newSongController,
    required this.radarController,
    required this.radarEnabled,
    required this.dailyTracksEnabled,
    required this.personalFmEnabled,
    required this.queuePlaybackController,
    required this.authenticated,
    required this.providerDisplayName,
    required this.spotlightPlaylist,
    required this.onPreviousSpotlight,
    required this.onNextSpotlight,
    required this.spotlightAutoPlaying,
    required this.spotlightAutoPlayAvailable,
    required this.spotlightMotionDirection,
    required this.spotlightProgress,
    required this.onToggleSpotlightAutoPlay,
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onOpenRecommendation,
    required this.lastOpenedRecommendation,
    required this.recommendationReturnFocusNode,
  });

  final HomeController homeController;
  final VoidCallback? onRefresh;
  final ValueChanged<RecommendedPlaylistSummary> onOpenFeatured;
  final FocusNode? featuredReturnFocusNode;
  final RecommendedPlaylistController recommendationController;
  final NewSongController newSongController;
  final RadarController radarController;
  final bool radarEnabled;
  final bool dailyTracksEnabled;
  final bool personalFmEnabled;
  final QueuePlaybackController queuePlaybackController;
  final bool authenticated;
  final String providerDisplayName;
  final RecommendedPlaylistSummary? spotlightPlaylist;
  final VoidCallback onPreviousSpotlight;
  final VoidCallback onNextSpotlight;
  final bool spotlightAutoPlaying;
  final bool spotlightAutoPlayAvailable;
  final int spotlightMotionDirection;
  final ValueListenable<double> spotlightProgress;
  final VoidCallback onToggleSpotlightAutoPlay;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final ValueChanged<RecommendedPlaylistSummary> onOpenRecommendation;
  final RecommendedPlaylistSummary? lastOpenedRecommendation;
  final FocusNode? recommendationReturnFocusNode;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const PageStorageKey('home-scroll'),
    padding: const EdgeInsets.fromLTRB(
      _HomeGeometry.widePadding,
      _HomeGeometry.widePadding,
      _HomeGeometry.widePadding,
      128,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HomeSemanticHeading(),
        _DailyRecommendationSection(
          homeController: homeController,
          controller: recommendationController,
          newSongController: newSongController,
          radarController: radarController,
          radarEnabled: radarEnabled,
          dailyTracksEnabled: dailyTracksEnabled,
          providerDisplayName: providerDisplayName,
          queueController: queuePlaybackController,
          authenticated: authenticated,
          spotlightPlaylist: spotlightPlaylist,
          onPreviousSpotlight: onPreviousSpotlight,
          onNextSpotlight: onNextSpotlight,
          spotlightAutoPlaying: spotlightAutoPlaying,
          spotlightAutoPlayAvailable: spotlightAutoPlayAvailable,
          spotlightMotionDirection: spotlightMotionDirection,
          spotlightProgress: spotlightProgress,
          onToggleSpotlightAutoPlay: onToggleSpotlightAutoPlay,
          compact: false,
          onSelected: onOpenFeatured,
          lastOpened: lastOpenedRecommendation,
          returnFocusNode: featuredReturnFocusNode,
        ),
        const SizedBox(height: _HomeGeometry.sectionGap),
        _HomeSectionHeader(
          titleKey: const ValueKey('home-library-heading'),
          title: authenticated
              ? context.l10n.homePlaylistTreasures
              : context.l10n.homePopularPlaylists,
          actionKey: const ValueKey('home-refresh-recommendations'),
          actionLabel: onRefresh == null
              ? context.l10n.homeRefreshing
              : context.l10n.commonRefresh,
          onAction: onRefresh,
        ),
        const SizedBox(height: _HomeGeometry.itemGap),
        if (authenticated)
          _PersonalizedPlaylistSection(
            controller: homeController,
            compact: false,
            providerDisplayName: providerDisplayName,
            onSelected: onOpenRecommendation,
            lastOpened: lastOpenedRecommendation,
            returnFocusNode: recommendationReturnFocusNode,
          )
        else
          _GuestPlaylistSection(
            controller: recommendationController,
            spotlightPlaylist: spotlightPlaylist,
            compact: false,
            onSelected: onOpenRecommendation,
            lastOpened: lastOpenedRecommendation,
            returnFocusNode: recommendationReturnFocusNode,
            providerDisplayName: providerDisplayName,
          ),
        const SizedBox(height: _HomeGeometry.sectionGap),
        _HomeSectionHeader(
          titleKey: const ValueKey('home-listening-one-heading'),
          title: authenticated
              ? personalFmEnabled
                    ? context.l10n.homePersonalFm
                    : context.l10n.homeSongsPickedForYou
              : context.l10n.homeNewSongs,
        ),
        const SizedBox(height: _HomeGeometry.itemGap),
        if (authenticated)
          _PersonalizedTrackSection(
            controller: homeController,
            queueController: queuePlaybackController,
            compact: false,
            personalFm: personalFmEnabled,
          )
        else
          _NewSongSection(
            controller: newSongController,
            queueController: queuePlaybackController,
            compact: false,
            authenticated: false,
            providerDisplayName: providerDisplayName,
          ),
        if (authenticated) ...[
          const SizedBox(height: _HomeGeometry.sectionGap),
          _HomeSectionHeader(
            titleKey: const ValueKey('home-new-songs-heading'),
            title: context.l10n.homeFreshReleases,
          ),
          const SizedBox(height: _HomeGeometry.itemGap),
          _NewSongSection(
            controller: newSongController,
            queueController: queuePlaybackController,
            compact: false,
            authenticated: true,
            providerDisplayName: providerDisplayName,
          ),
          const SizedBox(height: _HomeGeometry.sectionGap),
          _HomeSectionHeader(
            titleKey: const ValueKey('home-recommended-playlists-heading'),
            title: context.l10n.homePublicPlaylists,
            actionKey: const ValueKey('home-open-more-recommendations'),
            actionLabel: context.l10n.commonSeeAll,
            onAction: onOpenDiscover,
          ),
          const SizedBox(height: _HomeGeometry.itemGap),
          _MoreRecommendationsSection(
            controller: recommendationController,
            spotlightPlaylist: spotlightPlaylist,
            compact: false,
            onSelected: onOpenRecommendation,
            lastOpened: lastOpenedRecommendation,
            returnFocusNode: recommendationReturnFocusNode,
          ),
        ],
        const SizedBox(height: _HomeGeometry.sectionGap),
        _HomeSectionHeader(
          titleKey: const ValueKey('home-listening-two-heading'),
          title: context.l10n.homeMoreFromListening,
          actionKey: const ValueKey('home-refresh-related'),
          actionLabel: context.l10n.homeChangePicks,
          onAction:
              homeController.relatedSeed == null ||
                  homeController.relatedTracksStage == HomeResourceStage.loading
              ? null
              : homeController.refreshRelatedTracks,
        ),
        const SizedBox(height: _HomeGeometry.itemGap),
        _RelatedTrackSection(
          controller: homeController,
          queueController: queuePlaybackController,
          compact: false,
        ),
      ],
    ),
  );
}

class _HomeCompactLayout extends StatelessWidget {
  const _HomeCompactLayout({
    required this.onOpenFeatured,
    required this.featuredReturnFocusNode,
    required this.onRefresh,
    required this.homeController,
    required this.recommendationController,
    required this.newSongController,
    required this.radarController,
    required this.radarEnabled,
    required this.dailyTracksEnabled,
    required this.personalFmEnabled,
    required this.queuePlaybackController,
    required this.authenticated,
    required this.providerDisplayName,
    required this.spotlightPlaylist,
    required this.onPreviousSpotlight,
    required this.onNextSpotlight,
    required this.spotlightAutoPlaying,
    required this.spotlightAutoPlayAvailable,
    required this.spotlightMotionDirection,
    required this.spotlightProgress,
    required this.onToggleSpotlightAutoPlay,
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onOpenRecommendation,
    required this.lastOpenedRecommendation,
    required this.recommendationReturnFocusNode,
  });

  final HomeController homeController;
  final VoidCallback? onRefresh;
  final ValueChanged<RecommendedPlaylistSummary> onOpenFeatured;
  final FocusNode? featuredReturnFocusNode;
  final RecommendedPlaylistController recommendationController;
  final NewSongController newSongController;
  final RadarController radarController;
  final bool radarEnabled;
  final bool dailyTracksEnabled;
  final bool personalFmEnabled;
  final QueuePlaybackController queuePlaybackController;
  final bool authenticated;
  final String providerDisplayName;
  final RecommendedPlaylistSummary? spotlightPlaylist;
  final VoidCallback onPreviousSpotlight;
  final VoidCallback onNextSpotlight;
  final bool spotlightAutoPlaying;
  final bool spotlightAutoPlayAvailable;
  final int spotlightMotionDirection;
  final ValueListenable<double> spotlightProgress;
  final VoidCallback onToggleSpotlightAutoPlay;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final ValueChanged<RecommendedPlaylistSummary> onOpenRecommendation;
  final RecommendedPlaylistSummary? lastOpenedRecommendation;
  final FocusNode? recommendationReturnFocusNode;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const PageStorageKey('home-scroll'),
    padding: const EdgeInsets.only(bottom: 140),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            _HomeGeometry.compactPadding,
            _HomeGeometry.itemGap,
            _HomeGeometry.compactPadding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _HomeSemanticHeading(),
              _DailyRecommendationSection(
                homeController: homeController,
                controller: recommendationController,
                newSongController: newSongController,
                radarController: radarController,
                radarEnabled: radarEnabled,
                dailyTracksEnabled: dailyTracksEnabled,
                providerDisplayName: providerDisplayName,
                queueController: queuePlaybackController,
                authenticated: authenticated,
                spotlightPlaylist: spotlightPlaylist,
                onPreviousSpotlight: onPreviousSpotlight,
                onNextSpotlight: onNextSpotlight,
                spotlightAutoPlaying: spotlightAutoPlaying,
                spotlightAutoPlayAvailable: spotlightAutoPlayAvailable,
                spotlightMotionDirection: spotlightMotionDirection,
                spotlightProgress: spotlightProgress,
                onToggleSpotlightAutoPlay: onToggleSpotlightAutoPlay,
                compact: true,
                onSelected: onOpenFeatured,
                lastOpened: lastOpenedRecommendation,
                returnFocusNode: featuredReturnFocusNode,
              ),
              const SizedBox(height: _HomeGeometry.sectionGap),
              _HomeSectionHeader(
                titleKey: const ValueKey('home-library-heading'),
                title: authenticated
                    ? context.l10n.homePlaylistTreasures
                    : context.l10n.homePopularPlaylists,
                actionKey: const ValueKey('home-refresh-recommendations'),
                actionLabel: onRefresh == null
                    ? context.l10n.homeRefreshing
                    : context.l10n.commonRefresh,
                onAction: onRefresh,
                compact: true,
              ),
              const SizedBox(height: _HomeGeometry.itemGap),
              if (authenticated)
                _PersonalizedPlaylistSection(
                  controller: homeController,
                  compact: true,
                  providerDisplayName: providerDisplayName,
                  onSelected: onOpenRecommendation,
                  lastOpened: lastOpenedRecommendation,
                  returnFocusNode: recommendationReturnFocusNode,
                )
              else
                _GuestPlaylistSection(
                  controller: recommendationController,
                  spotlightPlaylist: spotlightPlaylist,
                  compact: true,
                  onSelected: onOpenRecommendation,
                  lastOpened: lastOpenedRecommendation,
                  returnFocusNode: recommendationReturnFocusNode,
                  providerDisplayName: providerDisplayName,
                ),
              const SizedBox(height: _HomeGeometry.sectionGap),
              _HomeSectionHeader(
                titleKey: const ValueKey('home-listening-one-heading'),
                title: authenticated
                    ? personalFmEnabled
                          ? context.l10n.homePersonalFm
                          : context.l10n.homeSongsPickedForYou
                    : context.l10n.homeNewSongs,
                compact: true,
              ),
              const SizedBox(height: _HomeGeometry.itemGap),
              if (authenticated)
                _PersonalizedTrackSection(
                  controller: homeController,
                  queueController: queuePlaybackController,
                  compact: true,
                  personalFm: personalFmEnabled,
                )
              else
                _NewSongSection(
                  controller: newSongController,
                  queueController: queuePlaybackController,
                  compact: true,
                  authenticated: false,
                  providerDisplayName: providerDisplayName,
                ),
              if (authenticated) ...[
                const SizedBox(height: _HomeGeometry.sectionGap),
                _HomeSectionHeader(
                  titleKey: const ValueKey('home-new-songs-heading'),
                  title: context.l10n.homeFreshReleases,
                  compact: true,
                ),
                const SizedBox(height: _HomeGeometry.itemGap),
                _NewSongSection(
                  controller: newSongController,
                  queueController: queuePlaybackController,
                  compact: true,
                  authenticated: true,
                  providerDisplayName: providerDisplayName,
                ),
                const SizedBox(height: _HomeGeometry.sectionGap),
                _HomeSectionHeader(
                  titleKey: const ValueKey(
                    'home-recommended-playlists-heading',
                  ),
                  title: context.l10n.homePublicPlaylists,
                  actionKey: const ValueKey('home-open-more-recommendations'),
                  actionLabel: context.l10n.commonSeeAll,
                  onAction: onOpenDiscover,
                  compact: true,
                ),
                const SizedBox(height: _HomeGeometry.itemGap),
                _MoreRecommendationsSection(
                  controller: recommendationController,
                  spotlightPlaylist: spotlightPlaylist,
                  compact: true,
                  onSelected: onOpenRecommendation,
                  lastOpened: lastOpenedRecommendation,
                  returnFocusNode: recommendationReturnFocusNode,
                ),
              ],
              const SizedBox(height: _HomeGeometry.sectionGap),
              _HomeSectionHeader(
                titleKey: const ValueKey('home-listening-two-heading'),
                title: context.l10n.homeMoreFromListening,
                compact: true,
                actionKey: const ValueKey('home-refresh-related'),
                actionLabel: context.l10n.homeChangePicks,
                onAction:
                    homeController.relatedSeed == null ||
                        homeController.relatedTracksStage ==
                            HomeResourceStage.loading
                    ? null
                    : homeController.refreshRelatedTracks,
              ),
              const SizedBox(height: _HomeGeometry.itemGap),
              _RelatedTrackSection(
                controller: homeController,
                queueController: queuePlaybackController,
                compact: true,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HomeSemanticHeading extends StatelessWidget {
  const _HomeSemanticHeading();

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('home-heading'),
    header: true,
    label: context.l10n.homeRecommendationsSemantics,
    child: const SizedBox.shrink(),
  );
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    required this.titleKey,
    required this.title,
    this.compact = false,
    this.actionKey,
    this.actionLabel,
    this.onAction,
  });

  final Key titleKey;
  final String title;
  final bool compact;
  final Key? actionKey;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(
            title,
            key: titleKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: compact
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ),
      if (onAction != null) ...[
        const SizedBox(width: MusicSpacing.itemGap),
        TextButton(
          key: actionKey,
          onPressed: onAction,
          child: Text(actionLabel!),
        ),
      ],
    ],
  );
}

class _DailyRecommendationSection extends StatelessWidget {
  const _DailyRecommendationSection({
    required this.homeController,
    required this.controller,
    required this.newSongController,
    required this.radarController,
    required this.radarEnabled,
    required this.dailyTracksEnabled,
    required this.providerDisplayName,
    required this.queueController,
    required this.authenticated,
    required this.spotlightPlaylist,
    required this.onPreviousSpotlight,
    required this.onNextSpotlight,
    required this.spotlightAutoPlaying,
    required this.spotlightAutoPlayAvailable,
    required this.spotlightMotionDirection,
    required this.spotlightProgress,
    required this.onToggleSpotlightAutoPlay,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
  });

  final HomeController homeController;
  final RecommendedPlaylistController controller;
  final NewSongController newSongController;
  final RadarController radarController;
  final bool radarEnabled;
  final bool dailyTracksEnabled;
  final String providerDisplayName;
  final QueuePlaybackController queueController;
  final bool authenticated;
  final RecommendedPlaylistSummary? spotlightPlaylist;
  final VoidCallback onPreviousSpotlight;
  final VoidCallback onNextSpotlight;
  final bool spotlightAutoPlaying;
  final bool spotlightAutoPlayAvailable;
  final int spotlightMotionDirection;
  final ValueListenable<double> spotlightProgress;
  final VoidCallback onToggleSpotlightAutoPlay;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;

  @override
  Widget build(BuildContext context) {
    final daily = homeController.dailyPlaylist;
    final dailyTracks = homeController.dailyTracks;
    final publicPlaylists = controller.stage == RecommendedPlaylistStage.content
        ? controller.playlists
        : const <RecommendedPlaylistSummary>[];
    final supportingPlaylist = publicPlaylists
        .where(
          (playlist) =>
              _recommendationIdentity(playlist) !=
              (spotlightPlaylist == null
                  ? null
                  : _recommendationIdentity(spotlightPlaylist!)),
        )
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (authenticated &&
            homeController.refreshHasErrors &&
            (homeController.personalizedPlaylists.isNotEmpty ||
                daily != null ||
                dailyTracks.isNotEmpty ||
                homeController.personalizedTracks.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              context.l10n.homeRefreshWarning,
              key: const ValueKey('home-refresh-warning'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        _DailyRecommendationContent(
          key: const ValueKey('home-recommendations-section'),
          featuredPlaylist: spotlightPlaylist,
          guestPopularPlaylist: supportingPlaylist,
          publicStage: controller.stage,
          featuredCount: authenticated
              ? homeController.personalizedPlaylists.length
              : publicPlaylists.length,
          featuredStage: authenticated
              ? homeController.personalizedPlaylistsStage
              : switch (controller.stage) {
                  RecommendedPlaylistStage.loading => HomeResourceStage.loading,
                  RecommendedPlaylistStage.content => HomeResourceStage.content,
                  RecommendedPlaylistStage.empty => HomeResourceStage.empty,
                  RecommendedPlaylistStage.error => HomeResourceStage.error,
                },
          onRetryFeatured: authenticated
              ? homeController.retryPersonalizedPlaylists
              : controller.retry,
          newSongController: newSongController,
          dailyPlaylist: daily,
          dailyTracks: dailyTracks,
          dailyTracksEnabled: dailyTracksEnabled,
          providerDisplayName: providerDisplayName,
          dailyStage: homeController.dailyStage,
          radarController: radarController,
          radarEnabled: radarEnabled,
          queueController: queueController,
          authenticated: authenticated,
          compact: compact,
          onSelected: onSelected,
          onRetryPublic: controller.retry,
          onRetryDaily: homeController.retryDaily,
          onPreviousSpotlight: onPreviousSpotlight,
          onNextSpotlight: onNextSpotlight,
          spotlightAutoPlaying: spotlightAutoPlaying,
          spotlightAutoPlayAvailable: spotlightAutoPlayAvailable,
          spotlightMotionDirection: spotlightMotionDirection,
          spotlightProgress: spotlightProgress,
          onToggleSpotlightAutoPlay: onToggleSpotlightAutoPlay,
          lastOpened: lastOpened,
          returnFocusNode: returnFocusNode,
        ),
      ],
    );
  }
}

class _DailyRecommendationContent extends StatelessWidget {
  const _DailyRecommendationContent({
    required this.featuredCount,
    required this.featuredStage,
    required this.onRetryFeatured,
    required this.featuredPlaylist,
    required this.guestPopularPlaylist,
    required this.publicStage,
    required this.newSongController,
    required this.dailyPlaylist,
    required this.dailyTracks,
    required this.dailyTracksEnabled,
    required this.providerDisplayName,
    required this.dailyStage,
    required this.radarController,
    required this.radarEnabled,
    required this.queueController,
    required this.authenticated,
    required this.compact,
    required this.onSelected,
    required this.onRetryPublic,
    required this.onRetryDaily,
    required this.onPreviousSpotlight,
    required this.onNextSpotlight,
    required this.spotlightAutoPlaying,
    required this.spotlightAutoPlayAvailable,
    required this.spotlightMotionDirection,
    required this.spotlightProgress,
    required this.onToggleSpotlightAutoPlay,
    required this.lastOpened,
    required this.returnFocusNode,
    super.key,
  });

  final RecommendedPlaylistSummary? featuredPlaylist;
  final int featuredCount;
  final HomeResourceStage featuredStage;
  final VoidCallback onRetryFeatured;
  final RecommendedPlaylistSummary? guestPopularPlaylist;
  final RecommendedPlaylistStage publicStage;
  final NewSongController newSongController;
  final RecommendedPlaylistSummary? dailyPlaylist;
  final List<PlaylistTrackSummary> dailyTracks;
  final bool dailyTracksEnabled;
  final String providerDisplayName;
  final HomeResourceStage dailyStage;
  final RadarController radarController;
  final bool radarEnabled;
  final QueuePlaybackController queueController;
  final bool authenticated;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final VoidCallback onRetryPublic;
  final VoidCallback onRetryDaily;
  final VoidCallback onPreviousSpotlight;
  final VoidCallback onNextSpotlight;
  final bool spotlightAutoPlaying;
  final bool spotlightAutoPlayAvailable;
  final int spotlightMotionDirection;
  final ValueListenable<double> spotlightProgress;
  final VoidCallback onToggleSpotlightAutoPlay;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;

  bool _focusMatches(RecommendedPlaylistSummary playlist) =>
      lastOpened?.providerId == playlist.providerId &&
      lastOpened?.opaqueId == playlist.opaqueId;

  Widget _featuredSlot(BuildContext context) {
    final playlist = featuredPlaylist;
    if (playlist != null) {
      return _FeaturedRecommendationCard(
        playlist: playlist,
        eyebrow: authenticated
            ? context.l10n.homeForYouEyebrow
            : context.l10n.homePublicSpotlightEyebrow,
        height: compact ? _HomeGeometry.compactHeroHeight : null,
        itemKey: const ValueKey('home-recommendation-0'),
        onSelected: onSelected,
        focusNode: _focusMatches(playlist) ? returnFocusNode : null,
        showCarouselControls: featuredCount > 1,
        onPrevious: onPreviousSpotlight,
        onNext: onNextSpotlight,
        autoPlaying: spotlightAutoPlaying,
        autoPlayAvailable: spotlightAutoPlayAvailable,
        motionDirection: spotlightMotionDirection,
        rotationProgress: spotlightProgress,
        onToggleAutoPlay: onToggleSpotlightAutoPlay,
      );
    }
    return _RecommendationSlotState(
      key: const ValueKey('home-recommendation-hero-state'),
      title: authenticated
          ? context.l10n.homeSelectedForYou
          : context.l10n.homeTodaysPick,
      detail: switch (featuredStage) {
        HomeResourceStage.loading => context.l10n.homeLoadingRecommendations,
        HomeResourceStage.error => context.l10n.homeRecommendationsUnavailable,
        _ => context.l10n.homeNoRecommendations,
      },
      loading: featuredStage == HomeResourceStage.loading,
      onRetry: featuredStage == HomeResourceStage.error
          ? onRetryFeatured
          : null,
      compact: compact,
      featured: true,
    );
  }

  Widget _dailySlot(BuildContext context) {
    if (!authenticated) {
      final playlist = guestPopularPlaylist;
      if (playlist != null) {
        return compact
            ? _CompactRecommendationCard(
                playlist: playlist,
                eyebrow: context.l10n.homePopularPlaylist,
                eyebrowKey: const ValueKey('home-guest-popular-heading'),
                itemKey: const ValueKey('home-guest-popular-playlist'),
                onSelected: onSelected,
                focusNode: _focusMatches(playlist) ? returnFocusNode : null,
              )
            : _WideRecommendationCard(
                playlist: playlist,
                eyebrow: context.l10n.homePopularPlaylist,
                eyebrowKey: const ValueKey('home-guest-popular-heading'),
                itemKey: const ValueKey('home-guest-popular-playlist'),
                onSelected: onSelected,
                focusNode: _focusMatches(playlist) ? returnFocusNode : null,
              );
      }
      return _RecommendationSlotState(
        key: const ValueKey('home-guest-popular-state'),
        headingKey: const ValueKey('home-guest-popular-heading'),
        title: context.l10n.homePopularPlaylist,
        detail: _publicStateDetail(
          context.l10n,
          publicStage,
          providerDisplayName: providerDisplayName,
        ),
        loading: publicStage == RecommendedPlaylistStage.loading,
        onRetry: publicStage == RecommendedPlaylistStage.error
            ? onRetryPublic
            : null,
        compact: compact,
      );
    }
    final playlist = dailyPlaylist;
    final dailyLabel = dailyTracksEnabled
        ? context.l10n.homeDailyTracks
        : context.l10n.homeDailyRecommendation;
    if (playlist != null) {
      return compact
          ? _CompactRecommendationCard(
              playlist: playlist,
              eyebrow: dailyLabel,
              eyebrowKey: const ValueKey('home-daily-heading'),
              itemKey: const ValueKey('home-daily-recommendation'),
              onSelected: onSelected,
              focusNode: _focusMatches(playlist) ? returnFocusNode : null,
            )
          : _WideRecommendationCard(
              playlist: playlist,
              eyebrow: dailyLabel,
              eyebrowKey: const ValueKey('home-daily-heading'),
              itemKey: const ValueKey('home-daily-recommendation'),
              onSelected: onSelected,
              focusNode: _focusMatches(playlist) ? returnFocusNode : null,
            );
    }
    if (dailyTracks.isNotEmpty) {
      return _TrackRecommendationCard(
        track: dailyTracks.first,
        label: context.l10n.homeDailyTracks,
        itemKey: const ValueKey('home-daily-tracks'),
        placeholderIcon: Icons.today_rounded,
        compact: compact,
        onPlay: () => unawaited(queueController.replaceAndPlay(dailyTracks, 0)),
      );
    }
    return _RecommendationSlotState(
      key: const ValueKey('home-daily-recommendation-state'),
      headingKey: const ValueKey('home-daily-heading'),
      title: dailyLabel,
      detail: _dailyStateDetail(
        context.l10n,
        dailyStage,
        dailyTracks: dailyTracksEnabled,
      ),
      loading: dailyStage == HomeResourceStage.loading,
      onRetry: dailyStage == HomeResourceStage.error ? onRetryDaily : null,
      compact: compact,
    );
  }

  Widget _radarSlot(BuildContext context) {
    if (!authenticated) {
      if (newSongController.stage == NewSongStage.content &&
          newSongController.tracks.isNotEmpty) {
        final tracks = newSongController.tracks;
        return _TrackRecommendationCard(
          track: tracks.first,
          label: context.l10n.homeNewSongs,
          itemKey: const ValueKey('home-guest-new-song-recommendation'),
          placeholderIcon: Icons.new_releases_outlined,
          compact: compact,
          onPlay: () => unawaited(queueController.replaceAndPlay(tracks, 0)),
        );
      }
      return _RecommendationSlotState(
        key: const ValueKey('home-guest-new-song-state'),
        title: context.l10n.homeNewSongs,
        detail: _newSongStateDetail(
          context.l10n,
          newSongController.stage,
          providerDisplayName: providerDisplayName,
        ),
        loading: newSongController.stage == NewSongStage.loading,
        onRetry: newSongController.canRetry ? newSongController.retry : null,
        compact: compact,
      );
    }
    if (radarController.stage == RadarStage.content &&
        radarController.tracks.isNotEmpty) {
      final tracks = radarController.tracks;
      return _TrackRecommendationCard(
        track: tracks.first,
        label: context.l10n.homeRadar,
        itemKey: const ValueKey('home-radar-recommendation'),
        placeholderIcon: Icons.radar_rounded,
        compact: compact,
        onPlay: () => unawaited(queueController.replaceAndPlay(tracks, 0)),
      );
    }
    return _RecommendationSlotState(
      key: const ValueKey('home-radar-state'),
      title: context.l10n.homeRadar,
      detail: _radarStateDetail(context.l10n, radarController.stage),
      loading: radarController.stage == RadarStage.loading,
      onRetry: radarController.canRetry ? radarController.retry : null,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _featuredSlot(context),
          const SizedBox(height: _HomeGeometry.itemGap),
          if (radarEnabled)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _dailySlot(context)),
                const SizedBox(width: _HomeGeometry.itemGap),
                Expanded(child: _radarSlot(context)),
              ],
            )
          else
            _dailySlot(context),
        ],
      );
    }

    return SizedBox(
      height: _HomeGeometry.wideHeroHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: _featuredSlot(context)),
          const SizedBox(width: _HomeGeometry.itemGap),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _dailySlot(context)),
                if (radarEnabled) ...[
                  const SizedBox(height: _HomeGeometry.itemGap),
                  Expanded(child: _radarSlot(context)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackRecommendationCard extends StatelessWidget {
  const _TrackRecommendationCard({
    required this.track,
    required this.label,
    required this.itemKey,
    required this.placeholderIcon,
    required this.compact,
    required this.onPlay,
  });

  final PlaylistTrackSummary track;
  final String label;
  final Key itemKey;
  final IconData placeholderIcon;
  final bool compact;
  final VoidCallback onPlay;

  String _artists(AppLocalizations l10n) => track.artistNames.isEmpty
      ? l10n.homeMusicService
      : track.artistNames.join(' · ');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final artists = _artists(context.l10n);
    final semanticsLabel = context.l10n.homeTrackPlaySemantics(
      artists,
      label,
      track.title,
    );
    if (compact) {
      return Semantics(
        button: true,
        label: semanticsLabel,
        onTap: onPlay,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _HomeArtwork(
                    uri: track.artworkUri,
                    placeholderIcon: placeholderIcon,
                    radius: _HomeGeometry.heroRadius,
                  ),
                  Positioned.fill(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: itemKey,
                        borderRadius: _HomeGeometry.heroRadius,
                        onTap: onPlay,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onPlay,
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: _HomeGeometry.heroRadius,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: _HomeArtwork(
                      uri: track.artworkUri,
                      placeholderIcon: placeholderIcon,
                      radius: _HomeGeometry.artworkRadius,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          artists,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.play_arrow_rounded, color: colors.primary),
                ],
              ),
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(key: itemKey, onTap: onPlay),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedRecommendationCard extends StatelessWidget {
  const _FeaturedRecommendationCard({
    required this.playlist,
    required this.eyebrow,
    required this.itemKey,
    required this.onSelected,
    required this.focusNode,
    required this.showCarouselControls,
    required this.onPrevious,
    required this.onNext,
    required this.autoPlaying,
    required this.autoPlayAvailable,
    required this.motionDirection,
    required this.rotationProgress,
    required this.onToggleAutoPlay,
    this.height,
  });

  final RecommendedPlaylistSummary playlist;
  final String eyebrow;
  final Key itemKey;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final FocusNode? focusNode;
  final bool showCarouselControls;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool autoPlaying;
  final bool autoPlayAvailable;
  final int motionDirection;
  final ValueListenable<double> rotationProgress;
  final VoidCallback onToggleAutoPlay;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sceneKey = ValueKey(_recommendationIdentity(playlist));
    return SizedBox(
      height: height,
      child: Semantics(
        button: true,
        label: _recommendationSemanticLabel(context.l10n, playlist),
        onTap: () => onSelected(playlist),
        child: Material(
          color: colors.surfaceContainerHigh,
          borderRadius: _HomeGeometry.heroRadius,
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                key: const ValueKey('home-spotlight-scene-switcher'),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                switchInCurve: Easing.emphasizedDecelerate,
                switchOutCurve: Easing.emphasizedAccelerate,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  children: [...previousChildren, ?currentChild],
                ),
                transitionBuilder: (child, animation) {
                  final incoming = child.key == sceneKey;
                  final direction = motionDirection < 0 ? -1.0 : 1.0;
                  final begin = incoming
                      ? Offset(0.08 * direction, 0)
                      : Offset(-0.08 * direction, 0);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: begin,
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _FeaturedRecommendationScene(
                  key: sceneKey,
                  playlist: playlist,
                  eyebrow: eyebrow,
                ),
              ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: itemKey,
                    focusNode: focusNode,
                    onTap: () => onSelected(playlist),
                  ),
                ),
              ),
              if (showCarouselControls)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    color: colors.scrim.withValues(alpha: 0.56),
                    borderRadius: BorderRadius.circular(24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const ValueKey('home-spotlight-previous'),
                          tooltip: context.l10n.homePreviousSpotlight,
                          onPressed: onPrevious,
                          color: Colors.white,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        if (autoPlayAvailable)
                          IconButton(
                            key: const ValueKey('home-spotlight-auto-play'),
                            tooltip: autoPlaying
                                ? context.l10n.homePauseSpotlight
                                : context.l10n.homeResumeSpotlight,
                            onPressed: onToggleAutoPlay,
                            color: Colors.white,
                            icon: Icon(
                              autoPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        IconButton(
                          key: const ValueKey('home-spotlight-next'),
                          tooltip: context.l10n.homeNextSpotlight,
                          onPressed: onNext,
                          color: Colors.white,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              if (showCarouselControls && autoPlayAvailable)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ExcludeSemantics(
                    child: ValueListenableBuilder<double>(
                      valueListenable: rotationProgress,
                      builder: (context, progress, _) =>
                          LinearProgressIndicator(
                            key: const ValueKey('home-spotlight-progress'),
                            value: progress,
                            minHeight: 3,
                            color: colors.primary,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.24,
                            ),
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedRecommendationScene extends StatelessWidget {
  const _FeaturedRecommendationScene({
    required this.playlist,
    required this.eyebrow,
    super.key,
  });

  final RecommendedPlaylistSummary playlist;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        _HomeArtwork(
          uri: playlist.artworkUri,
          placeholderIcon: Icons.auto_awesome_rounded,
          radius: BorderRadius.zero,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.scrim.withValues(alpha: 0.04),
                colors.scrim.withValues(alpha: 0.78),
              ],
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 24,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      eyebrow,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.inversePrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      playlist.title,
                      key: const ValueKey('home-spotlight-title'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _recommendationDetail(context.l10n, playlist),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: colors.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WideRecommendationCard extends StatelessWidget {
  const _WideRecommendationCard({
    required this.playlist,
    required this.itemKey,
    required this.onSelected,
    required this.focusNode,
    this.eyebrow,
    this.eyebrowKey,
  });

  final RecommendedPlaylistSummary playlist;
  final Key itemKey;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final FocusNode? focusNode;
  final String? eyebrow;
  final Key? eyebrowKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: _recommendationSemanticLabel(context.l10n, playlist),
      onTap: () => onSelected(playlist),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: _HomeGeometry.heroRadius,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: _HomeArtwork(
                      uri: playlist.artworkUri,
                      placeholderIcon: Icons.queue_music_rounded,
                      radius: _HomeGeometry.artworkRadius,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null) ...[
                          Text(
                            eyebrow!,
                            key: eyebrowKey,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          playlist.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _recommendationDetail(context.l10n, playlist),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: itemKey,
                  focusNode: focusNode,
                  onTap: () => onSelected(playlist),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactRecommendationCard extends StatelessWidget {
  const _CompactRecommendationCard({
    required this.playlist,
    required this.itemKey,
    required this.onSelected,
    required this.focusNode,
    this.eyebrow,
    this.eyebrowKey,
  });

  final RecommendedPlaylistSummary playlist;
  final Key itemKey;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final FocusNode? focusNode;
  final String? eyebrow;
  final Key? eyebrowKey;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _recommendationSemanticLabel(context.l10n, playlist),
    onTap: () => onSelected(playlist),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _HomeArtwork(
                uri: playlist.artworkUri,
                placeholderIcon: Icons.queue_music_rounded,
                radius: _HomeGeometry.heroRadius,
              ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: itemKey,
                    focusNode: focusNode,
                    borderRadius: _HomeGeometry.heroRadius,
                    onTap: () => onSelected(playlist),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            key: eyebrowKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
        ],
        Text(
          playlist.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    ),
  );
}

class _RecommendationSlotState extends StatelessWidget {
  const _RecommendationSlotState({
    required this.title,
    required this.detail,
    required this.loading,
    required this.onRetry,
    required this.compact,
    this.featured = false,
    this.headingKey,
    super.key,
  });

  final String title;
  final String detail;
  final bool loading;
  final VoidCallback? onRetry;
  final bool compact;
  final bool featured;
  final Key? headingKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = Icon(
      loading
          ? Icons.hourglass_top_rounded
          : onRetry == null
          ? Icons.music_off_outlined
          : Icons.cloud_off_rounded,
      color: colors.onSurfaceVariant,
    );
    final action = onRetry == null
        ? null
        : IconButton(
            tooltip: context.l10n.homeRetrySection(title),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          );

    if (compact && !featured) {
      return Semantics(
        label: context.l10n.commonAnnouncement(detail, title),
        liveRegion: onRetry != null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Material(
                color: colors.surfaceContainerLow,
                borderRadius: _HomeGeometry.heroRadius,
                child: Center(child: action ?? icon),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              key: headingKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final content = Material(
      color: featured
          ? colors.surfaceContainerHigh
          : colors.surfaceContainerLow,
      borderRadius: _HomeGeometry.heroRadius,
      child: Padding(
        padding: const EdgeInsets.all(_HomeGeometry.itemGap),
        child: Row(
          children: [
            SizedBox.square(
              dimension: featured ? 48 : 44,
              child: Center(child: icon),
            ),
            const SizedBox(width: _HomeGeometry.itemGap),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    key: headingKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: featured
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
    return Semantics(
      label: context.l10n.commonAnnouncement(detail, title),
      liveRegion: onRetry != null,
      child: compact && featured
          ? SizedBox(height: _HomeGeometry.compactHeroHeight, child: content)
          : content,
    );
  }
}

class _GuestPlaylistSection extends StatelessWidget {
  const _GuestPlaylistSection({
    required this.controller,
    required this.spotlightPlaylist,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
    required this.providerDisplayName,
  });

  final RecommendedPlaylistController controller;
  final RecommendedPlaylistSummary? spotlightPlaylist;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;
  final String providerDisplayName;

  @override
  Widget build(BuildContext context) {
    return switch (controller.stage) {
      RecommendedPlaylistStage.loading => _HomeLoadingShelf(
        key: const ValueKey('home-guest-playlists-loading'),
        compact: compact,
        semanticLabel: context.l10n.homeLoadingPublicPlaylists,
      ),
      RecommendedPlaylistStage.empty => _HomeInlineState(
        key: const ValueKey('home-guest-playlists-empty'),
        icon: Icons.queue_music_outlined,
        title: context.l10n.homeNoPublicPlaylists,
        detail: context.l10n.homeNoPublicPlaylistsDetail(providerDisplayName),
      ),
      RecommendedPlaylistStage.error => _HomeInlineState(
        key: const ValueKey('home-guest-playlists-error'),
        icon: Icons.cloud_off_outlined,
        title: context.l10n.homePublicPlaylistsFailure,
        detail: _publicStateDetail(
          context.l10n,
          controller.stage,
          providerDisplayName: providerDisplayName,
        ),
        liveRegion: true,
        action: controller.canRetry
            ? FilledButton.tonal(
                onPressed: controller.retry,
                child: Text(context.l10n.commonRetry),
              )
            : null,
      ),
      RecommendedPlaylistStage.content => _guestPlaylistContent(context),
    };
  }

  Widget _guestPlaylistContent(BuildContext context) {
    final spotlightIdentity = spotlightPlaylist == null
        ? null
        : _recommendationIdentity(spotlightPlaylist!);
    final publicItems = controller.playlists
        .where(
          (playlist) => _recommendationIdentity(playlist) != spotlightIdentity,
        )
        .toList(growable: false);
    final items = publicItems.skip(1).take(6).toList(growable: false);
    if (items.isEmpty) {
      return _HomeInlineState(
        key: const ValueKey('home-guest-playlists-empty'),
        icon: Icons.queue_music_outlined,
        title: context.l10n.homeNoAdditionalPublicPlaylists,
        detail: context.l10n.homeAvailablePublicShown,
      );
    }
    return _PlaylistShelf<RecommendedPlaylistSummary>(
      key: const ValueKey('home-guest-playlists-section'),
      layoutKey: const ValueKey('home-guest-playlists-shelf'),
      items: items,
      compact: compact,
      title: (playlist) => playlist.title,
      artworkUri: (playlist) => playlist.artworkUri,
      semanticLabel: (playlist) =>
          _recommendationSemanticLabel(context.l10n, playlist),
      itemKey: (index) => ValueKey('home-guest-playlist-${index + 1}'),
      onSelected: onSelected,
      focusNode: (playlist) =>
          lastOpened?.providerId == playlist.providerId &&
              lastOpened?.opaqueId == playlist.opaqueId
          ? returnFocusNode
          : null,
      placeholderIcon: Icons.queue_music_rounded,
    );
  }
}

class _NewSongSection extends StatelessWidget {
  const _NewSongSection({
    required this.controller,
    required this.queueController,
    required this.compact,
    required this.authenticated,
    required this.providerDisplayName,
  });

  final NewSongController controller;
  final QueuePlaybackController queueController;
  final bool compact;
  final bool authenticated;
  final String providerDisplayName;

  @override
  Widget build(BuildContext context) {
    return switch (controller.stage) {
      NewSongStage.loading => _HomeTrackLoading(
        compact: compact,
        semanticLabel: context.l10n.homeLoadingPublicNewSongs,
      ),
      NewSongStage.empty => _HomeInlineState(
        key: ValueKey(
          authenticated ? 'home-new-songs-empty' : 'home-guest-new-songs-empty',
        ),
        icon: Icons.new_releases_outlined,
        title: context.l10n.homeNoNewSongs,
        detail: context.l10n.homeNoNewSongsDetail(providerDisplayName),
      ),
      NewSongStage.error => _HomeInlineState(
        key: ValueKey(
          authenticated ? 'home-new-songs-error' : 'home-guest-new-songs-error',
        ),
        icon: Icons.cloud_off_outlined,
        title: context.l10n.homeNewSongsFailure,
        detail: _newSongFailureDetail(
          context.l10n,
          controller.failure,
          providerDisplayName: providerDisplayName,
        ),
        liveRegion: true,
        action: controller.canRetry
            ? FilledButton.tonal(
                onPressed: controller.retry,
                child: Text(context.l10n.commonRetry),
              )
            : null,
      ),
      NewSongStage.content => _HomeTrackContent(
        tracks: controller.tracks.take(6).toList(growable: false),
        queueController: queueController,
        compact: compact,
        sectionKey: ValueKey(
          authenticated ? 'home-new-songs' : 'home-guest-new-songs',
        ),
        itemKeyPrefix: authenticated ? 'home-new-song' : 'home-guest-new-song',
      ),
    };
  }
}

class _PersonalizedPlaylistSection extends StatelessWidget {
  const _PersonalizedPlaylistSection({
    required this.controller,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
    required this.providerDisplayName,
  });

  final HomeController controller;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;
  final String providerDisplayName;

  @override
  Widget build(BuildContext context) {
    return switch (controller.personalizedPlaylistsStage) {
      HomeResourceStage.loading => _HomeLoadingShelf(
        key: const ValueKey('home-library-loading'),
        compact: compact,
        semanticLabel: context.l10n.homeLoadingYourPlaylists,
      ),
      HomeResourceStage.empty => _HomeInlineState(
        key: const ValueKey('home-library-empty'),
        icon: Icons.library_music_outlined,
        title: context.l10n.homeNoPersonalizedPlaylists,
        detail: context.l10n.homeNoPersonalizedPlaylistsDetail,
        compactFootprint: true,
      ),
      HomeResourceStage.error => _HomeInlineState(
        key: const ValueKey('home-library-error'),
        icon: Icons.cloud_off_rounded,
        title: _personalizedPlaylistFailureTitle(
          context.l10n,
          controller.personalizedPlaylistsFailure,
        ),
        detail: _personalizedPlaylistFailureDetail(
          context.l10n,
          controller.personalizedPlaylistsFailure,
          providerDisplayName: providerDisplayName,
        ),
        liveRegion: true,
        compactFootprint: true,
        action: FilledButton.tonal(
          onPressed: controller.retryPersonalizedPlaylists,
          child: Text(context.l10n.commonRetry),
        ),
      ),
      HomeResourceStage.content => _PlaylistShelf<RecommendedPlaylistSummary>(
        key: const ValueKey('home-library-section'),
        layoutKey: const ValueKey('home-library-shelf'),
        items: controller.personalizedPlaylists,
        compact: compact,
        title: (playlist) => playlist.title,
        artworkUri: (playlist) => playlist.artworkUri,
        semanticLabel: (playlist) => playlist.trackCount == null
            ? context.l10n.homePersonalizedPlaylistSemantics(playlist.title)
            : '${playlist.title}, ${context.l10n.trackCount(playlist.trackCount!)}',
        itemKey: (index) => ValueKey('home-library-playlist-$index'),
        onSelected: onSelected,
        focusNode: (playlist) =>
            lastOpened?.providerId == playlist.providerId &&
                lastOpened?.opaqueId == playlist.opaqueId
            ? returnFocusNode
            : null,
        placeholderIcon: Icons.auto_awesome_rounded,
      ),
    };
  }
}

class _PersonalizedTrackSection extends StatelessWidget {
  const _PersonalizedTrackSection({
    required this.controller,
    required this.queueController,
    required this.compact,
    required this.personalFm,
  });

  final HomeController controller;
  final QueuePlaybackController queueController;
  final bool compact;
  final bool personalFm;

  @override
  Widget build(BuildContext context) {
    return switch (controller.personalizedTracksStage) {
      HomeResourceStage.loading => _HomeTrackLoading(
        compact: compact,
        semanticLabel: personalFm
            ? context.l10n.homeLoadingPersonalFm
            : context.l10n.homeLoadingPersonalizedSongs,
      ),
      HomeResourceStage.empty => _HomeInlineState(
        key: const ValueKey('home-personalized-tracks-empty'),
        icon: Icons.music_note_outlined,
        title: personalFm
            ? context.l10n.homePersonalFmEmpty
            : context.l10n.homePersonalizedSongsEmpty,
        detail: context.l10n.homePersonalizedSongsEmptyDetail,
        compactFootprint: true,
      ),
      HomeResourceStage.error => _HomeInlineState(
        key: const ValueKey('home-personalized-tracks-error'),
        icon: Icons.cloud_off_rounded,
        title: personalFm
            ? context.l10n.homePersonalFmFailure
            : context.l10n.homePersonalizedSongsFailure,
        detail: context.l10n.homeOtherSectionsAvailable,
        liveRegion: true,
        compactFootprint: true,
        action: FilledButton.tonal(
          onPressed: controller.retryPersonalizedTracks,
          child: Text(context.l10n.commonRetry),
        ),
      ),
      HomeResourceStage.content => _HomeTrackContent(
        tracks: controller.personalizedTracks.take(6).toList(growable: false),
        queueController: queueController,
        compact: compact,
        sectionKey: const ValueKey('home-personalized-tracks'),
        itemKeyPrefix: 'home-personalized-track',
      ),
    };
  }
}

class _RelatedTrackSection extends StatelessWidget {
  const _RelatedTrackSection({
    required this.controller,
    required this.queueController,
    required this.compact,
  });

  final HomeController controller;
  final QueuePlaybackController queueController;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final seed = controller.relatedSeed;
    return switch (controller.relatedTracksStage) {
      HomeResourceStage.loading => _HomeTrackLoading(
        compact: compact,
        semanticLabel: context.l10n.homeLoadingRelatedSongs(
          seed?.title ?? context.l10n.homeRecentListening,
        ),
      ),
      HomeResourceStage.empty when seed == null => _HomeInlineState(
        key: const ValueKey('home-related-tracks-no-seed'),
        icon: Icons.music_note_outlined,
        title: context.l10n.homeStartListeningTitle,
        detail: context.l10n.homeStartListeningDetail,
        compactFootprint: true,
      ),
      HomeResourceStage.empty => _HomeInlineState(
        key: const ValueKey('home-related-tracks-empty'),
        icon: Icons.music_note_outlined,
        title: context.l10n.homeNoRelatedSongs,
        detail: context.l10n.homeNoRelatedSongsDetail(seed!.title),
        compactFootprint: true,
      ),
      HomeResourceStage.error => _HomeInlineState(
        key: const ValueKey('home-related-tracks-error'),
        icon: Icons.cloud_off_rounded,
        title: _relatedTracksFailureTitle(
          context.l10n,
          controller.relatedTracksFailure,
        ),
        detail: _relatedTracksFailureDetail(
          context.l10n,
          controller.relatedTracksFailure,
          seed,
        ),
        liveRegion: true,
        compactFootprint: true,
        action: seed == null
            ? null
            : FilledButton.tonal(
                onPressed: controller.retryRelatedTracks,
                child: Text(context.l10n.commonRetry),
              ),
      ),
      HomeResourceStage.content => Column(
        key: const ValueKey('home-related-tracks-section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.homeBecauseListened(
              seed?.title ?? context.l10n.homeRecentSong,
            ),
            key: const ValueKey('home-related-tracks-seed'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _HomeTrackContent(
            tracks: controller.relatedTracks.take(6).toList(growable: false),
            queueController: queueController,
            compact: compact,
            sectionKey: const ValueKey('home-related-tracks'),
            itemKeyPrefix: 'home-related-track',
          ),
        ],
      ),
    };
  }
}

class _HomeTrackContent extends StatelessWidget {
  const _HomeTrackContent({
    required this.tracks,
    required this.queueController,
    required this.compact,
    required this.sectionKey,
    required this.itemKeyPrefix,
  });

  final List<PlaylistTrackSummary> tracks;
  final QueuePlaybackController queueController;
  final bool compact;
  final Key sectionKey;
  final String itemKeyPrefix;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = compact ? 1 : 2;
      final width = columns == 1
          ? constraints.maxWidth
          : (constraints.maxWidth - _HomeGeometry.itemGap) / 2;
      return Wrap(
        key: sectionKey,
        spacing: _HomeGeometry.itemGap,
        runSpacing: 0,
        children: [
          for (var index = 0; index < tracks.length; index++)
            SizedBox(
              width: width,
              child: _HomeTrackTile(
                itemKey: ValueKey('$itemKeyPrefix-${index + 1}'),
                queueKey: ValueKey('$itemKeyPrefix-queue-${index + 1}'),
                track: tracks[index],
                position: index + 1,
                compact: compact,
                playing: _sameTrack(queueController.current, tracks[index]),
                onPlay: () => queueController.replaceAndPlay(tracks, index),
                onQueue: () => queueController.push(tracks[index]),
              ),
            ),
        ],
      );
    },
  );
}

class _HomeTrackTile extends StatelessWidget {
  const _HomeTrackTile({
    required this.itemKey,
    required this.queueKey,
    required this.track,
    required this.position,
    required this.compact,
    required this.playing,
    required this.onPlay,
    required this.onQueue,
  });

  final Key itemKey;
  final Key queueKey;
  final PlaylistTrackSummary track;
  final int position;
  final bool compact;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final artists = track.artistNames.isEmpty
        ? context.l10n.trackUnknownArtist
        : track.artistNames.join(' · ');
    return SizedBox(
      height: _HomeGeometry.trackRowHeight,
      child: Semantics(
        button: true,
        label: context.l10n.commonTrackSemantics(artists, track.title),
        onTap: onPlay,
        child: Material(
          color: playing ? colors.secondaryContainer : Colors.transparent,
          borderRadius: _HomeGeometry.artworkRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: itemKey,
            onTap: onPlay,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: _HomeGeometry.trackArtworkSize,
                    child: _HomeArtwork(
                      uri: track.artworkUri,
                      placeholderIcon: playing
                          ? Icons.graphic_eq_rounded
                          : Icons.music_note_rounded,
                      radius: const BorderRadius.all(Radius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: playing
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: playing
                                    ? colors.onSecondaryContainer
                                    : null,
                              ),
                        ),
                        Text(
                          artists,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: playing
                                    ? colors.onSecondaryContainer.withValues(
                                        alpha: 0.78,
                                      )
                                    : colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (!compact && track.durationSeconds != null) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        _durationLabel(track.durationSeconds!),
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                  IconButton(
                    key: queueKey,
                    onPressed: onQueue,
                    tooltip: context.l10n.homeAddTrackToQueue(track.title),
                    icon: const Icon(Icons.playlist_add_rounded),
                    iconSize: 20,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTrackLoading extends StatelessWidget {
  const _HomeTrackLoading({required this.compact, required this.semanticLabel});

  final bool compact;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - _HomeGeometry.itemGap) / 2;
        return Wrap(
          spacing: _HomeGeometry.itemGap,
          children: [
            for (var index = 0; index < 6; index++)
              Container(
                width: width,
                height: _HomeGeometry.trackRowHeight,
                margin: const EdgeInsets.only(bottom: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: _HomeGeometry.artworkRadius,
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _MoreRecommendationsSection extends StatelessWidget {
  const _MoreRecommendationsSection({
    required this.controller,
    required this.spotlightPlaylist,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
  });

  final RecommendedPlaylistController controller;
  final RecommendedPlaylistSummary? spotlightPlaylist;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;

  @override
  Widget build(BuildContext context) {
    if (controller.stage != RecommendedPlaylistStage.content) {
      return _HomeInlineState(
        key: const ValueKey('home-more-recommendations-unavailable'),
        icon: Icons.queue_music_outlined,
        title: context.l10n.homeMoreRecommendationsUnavailable,
        detail: context.l10n.homePrimaryRecommendationShown,
      );
    }
    final spotlightIdentity = spotlightPlaylist == null
        ? null
        : _recommendationIdentity(spotlightPlaylist!);
    final items = controller.playlists
        .where(
          (playlist) => _recommendationIdentity(playlist) != spotlightIdentity,
        )
        .take(6)
        .toList(growable: false);
    if (items.isEmpty) {
      return _HomeInlineState(
        key: const ValueKey('home-more-recommendations-empty'),
        icon: Icons.queue_music_outlined,
        title: context.l10n.homeNoAdditionalPublicPlaylists,
        detail: context.l10n.homeAvailablePublicShown,
      );
    }
    return _PlaylistShelf<RecommendedPlaylistSummary>(
      key: const ValueKey('home-public-playlists-section'),
      layoutKey: const ValueKey('home-public-playlists-shelf'),
      items: items,
      compact: compact,
      title: (playlist) => playlist.title,
      artworkUri: (playlist) => playlist.artworkUri,
      semanticLabel: (playlist) =>
          _recommendationSemanticLabel(context.l10n, playlist),
      itemKey: (index) => ValueKey('home-recommendation-${index + 1}'),
      onSelected: onSelected,
      focusNode: (playlist) =>
          lastOpened?.providerId == playlist.providerId &&
              lastOpened?.opaqueId == playlist.opaqueId
          ? returnFocusNode
          : null,
      placeholderIcon: Icons.queue_music_rounded,
    );
  }
}

class _PlaylistShelf<T> extends StatefulWidget {
  const _PlaylistShelf({
    required this.layoutKey,
    required this.items,
    required this.compact,
    required this.title,
    required this.artworkUri,
    required this.semanticLabel,
    required this.itemKey,
    required this.onSelected,
    required this.focusNode,
    required this.placeholderIcon,
    super.key,
  });

  final Key layoutKey;
  final List<T> items;
  final bool compact;
  final String Function(T item) title;
  final String? Function(T item) artworkUri;
  final String Function(T item) semanticLabel;
  final Key Function(int index) itemKey;
  final ValueChanged<T> onSelected;
  final FocusNode? Function(T item) focusNode;
  final IconData placeholderIcon;

  @override
  State<_PlaylistShelf<T>> createState() => _PlaylistShelfState<T>();
}

class _PlaylistShelfState<T> extends State<_PlaylistShelf<T>> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _move(double distance) {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final target = (_scroll.offset + distance).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      unawaited(
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableColumns =
          ((constraints.maxWidth + _HomeGeometry.itemGap) /
                  (_HomeGeometry.wideShelfMinWidth + _HomeGeometry.itemGap))
              .floor()
              .clamp(1, 6);
      final fittedWidth =
          (constraints.maxWidth -
              _HomeGeometry.itemGap * (availableColumns - 1)) /
          availableColumns;
      final cardWidth = widget.compact
          ? _HomeGeometry.compactShelfWidth
          : fittedWidth > _HomeGeometry.wideShelfMaxWidth
          ? _HomeGeometry.wideShelfMaxWidth
          : fittedWidth;
      final overflowing =
          (cardWidth + _HomeGeometry.itemGap) * widget.items.length -
              _HomeGeometry.itemGap >
          constraints.maxWidth + 0.5;
      return Column(
        key: widget.layoutKey,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            height: cardWidth + MediaQuery.textScalerOf(context).scale(48) + 12,
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
                return false;
              },
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: overflowing && !widget.compact,
                  child: ListView.separated(
                    key: PageStorageKey(widget.layoutKey),
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: _HomeGeometry.itemGap),
                    itemBuilder: (context, index) => _PlaylistArtworkCard<T>(
                      width: cardWidth,
                      item: widget.items[index],
                      itemKey: widget.itemKey(index),
                      title: widget.title,
                      artworkUri: widget.artworkUri,
                      semanticLabel: widget.semanticLabel,
                      placeholderIcon: widget.placeholderIcon,
                      onSelected: widget.onSelected,
                      focusNode: widget.focusNode(widget.items[index]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (overflowing && !widget.compact)
            ListenableBuilder(
              listenable: _scroll,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: context.l10n.homePreviousPlaylists,
                    onPressed: _scroll.hasClients && _scroll.offset > 0.5
                        ? () => _move(-constraints.maxWidth * 0.8)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  IconButton(
                    tooltip: context.l10n.homeNextPlaylists,
                    onPressed:
                        !_scroll.hasClients ||
                            !_scroll.position.hasContentDimensions ||
                            _scroll.offset <
                                _scroll.position.maxScrollExtent - 0.5
                        ? () => _move(constraints.maxWidth * 0.8)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class _PlaylistArtworkCard<T> extends StatelessWidget {
  const _PlaylistArtworkCard({
    required this.item,
    required this.itemKey,
    required this.title,
    required this.artworkUri,
    required this.semanticLabel,
    required this.placeholderIcon,
    required this.onSelected,
    required this.focusNode,
    this.width,
  });

  final double? width;
  final T item;
  final Key itemKey;
  final String Function(T item) title;
  final String? Function(T item) artworkUri;
  final String Function(T item) semanticLabel;
  final IconData placeholderIcon;
  final ValueChanged<T> onSelected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Semantics(
      button: true,
      label: semanticLabel(item),
      onTap: () => onSelected(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _HomeArtwork(
                  uri: artworkUri(item),
                  placeholderIcon: placeholderIcon,
                  radius: _HomeGeometry.artworkRadius,
                ),
                Positioned.fill(
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: itemKey,
                      focusNode: focusNode,
                      borderRadius: _HomeGeometry.artworkRadius,
                      onTap: () => onSelected(item),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title(item),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
          ),
        ],
      ),
    ),
  );
}

class _HomeArtwork extends StatelessWidget {
  const _HomeArtwork({
    required this.uri,
    required this.placeholderIcon,
    this.radius = _HomeGeometry.artworkRadius,
  });

  final String? uri;
  final IconData placeholderIcon;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: radius,
      ),
      child: Icon(
        placeholderIcon,
        color: colors.onSecondaryContainer,
        size: 38,
      ),
    );
    return ClipRRect(
      borderRadius: radius,
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

class _HomeLoadingShelf extends StatelessWidget {
  const _HomeLoadingShelf({
    required this.compact,
    required this.semanticLabel,
    super.key,
  });

  final bool compact;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: compact
        ? SizedBox(
            height: _HomeGeometry.compactShelfWidth + 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: _HomeGeometry.itemGap),
              itemBuilder: (_, _) => Container(
                width: _HomeGeometry.compactShelfWidth,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: _HomeGeometry.artworkRadius,
                ),
              ),
            ),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  (constraints.maxWidth - _HomeGeometry.itemGap * 5) / 6;
              return SizedBox(
                height: width + 44,
                child: Row(
                  children: [
                    for (var index = 0; index < 6; index++) ...[
                      if (index > 0)
                        const SizedBox(width: _HomeGeometry.itemGap),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            borderRadius: _HomeGeometry.artworkRadius,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
  );
}

class _HomeInlineState extends StatelessWidget {
  const _HomeInlineState({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
    this.liveRegion = false,
    this.compactFootprint = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  final bool liveRegion;
  final bool compactFootprint;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: liveRegion,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: compactFootprint ? null : double.infinity,
        constraints: compactFootprint
            ? const BoxConstraints(maxWidth: 680)
            : null,
        padding: const EdgeInsets.all(_HomeGeometry.itemGap),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: _HomeGeometry.heroRadius,
        ),
        child: Wrap(
          spacing: _HomeGeometry.itemGap,
          runSpacing: MusicSpacing.itemGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ?action,
          ],
        ),
      ),
    ),
  );
}

String _personalizedPlaylistFailureTitle(
  AppLocalizations l10n,
  PersonalizedPlaylistsFailure? failure,
) => switch (failure) {
  PersonalizedPlaylistsFailure.invalidResponse =>
    l10n.homePersonalizedInvalidTitle,
  PersonalizedPlaylistsFailure.network => l10n.homePersonalizedOfflineTitle,
  PersonalizedPlaylistsFailure.serviceUnavailable =>
    l10n.homePersonalizedUnavailableTitle,
  PersonalizedPlaylistsFailure.replaced => l10n.homePersonalizedReplacedTitle,
  PersonalizedPlaylistsFailure.cancelled => l10n.homePersonalizedCancelledTitle,
  PersonalizedPlaylistsFailure.alreadyRunning =>
    l10n.homePersonalizedRunningTitle,
  _ => l10n.homePersonalizedFailureTitle,
};

String _personalizedPlaylistFailureDetail(
  AppLocalizations l10n,
  PersonalizedPlaylistsFailure? failure, {
  required String providerDisplayName,
}) => switch (failure) {
  PersonalizedPlaylistsFailure.invalidResponse =>
    l10n.homePersonalizedInvalidDetail(providerDisplayName),
  PersonalizedPlaylistsFailure.network => l10n.homeNetworkRetryDetail,
  PersonalizedPlaylistsFailure.serviceUnavailable =>
    l10n.homePersonalizedServiceDetail(providerDisplayName),
  PersonalizedPlaylistsFailure.replaced => l10n.homePersonalizedReplacedDetail,
  PersonalizedPlaylistsFailure.cancelled =>
    l10n.homePersonalizedCancelledDetail,
  PersonalizedPlaylistsFailure.alreadyRunning =>
    l10n.homePersonalizedRunningDetail,
  _ => l10n.homePublicAndSearchAvailable,
};

String _relatedTracksFailureTitle(
  AppLocalizations l10n,
  RelatedTracksFailure? failure,
) => switch (failure) {
  RelatedTracksFailure.invalidTrack => l10n.homeRelatedInvalidTitle,
  RelatedTracksFailure.network => l10n.homeRelatedOfflineTitle,
  RelatedTracksFailure.serviceUnavailable => l10n.homeRelatedUnavailableTitle,
  RelatedTracksFailure.invalidResponse => l10n.homeRelatedInvalidResponseTitle,
  RelatedTracksFailure.cancelled => l10n.homeRelatedCancelledTitle,
  RelatedTracksFailure.alreadyRunning => l10n.homeRelatedRunningTitle,
  _ => l10n.homeRelatedFailureTitle,
};

String _relatedTracksFailureDetail(
  AppLocalizations l10n,
  RelatedTracksFailure? failure,
  PlaylistTrackSummary? seed,
) => switch (failure) {
  RelatedTracksFailure.invalidTrack => l10n.homeRelatedInvalidTrackDetail(
    seed?.title ?? l10n.homeThisSong,
  ),
  RelatedTracksFailure.network => l10n.homeNetworkRetryDetail,
  RelatedTracksFailure.serviceUnavailable => l10n.homeRelatedServiceDetail,
  RelatedTracksFailure.invalidResponse => l10n.homeRelatedInvalidResponseDetail,
  RelatedTracksFailure.cancelled => l10n.homeRelatedCancelledDetail,
  RelatedTracksFailure.alreadyRunning => l10n.homeRelatedRunningDetail,
  _ => l10n.homeRelatedCoreDetail,
};

String _publicStateDetail(
  AppLocalizations l10n,
  RecommendedPlaylistStage stage, {
  required String providerDisplayName,
}) => switch (stage) {
  RecommendedPlaylistStage.loading => l10n.homePublicLoading,
  RecommendedPlaylistStage.content => l10n.homePublicNoAdditional,
  RecommendedPlaylistStage.empty => l10n.homePublicEmpty(providerDisplayName),
  RecommendedPlaylistStage.error => l10n.homePublicFailure,
};

String _dailyStateDetail(
  AppLocalizations l10n,
  HomeResourceStage stage, {
  required bool dailyTracks,
}) => switch (stage) {
  HomeResourceStage.loading =>
    dailyTracks ? l10n.homeLoadingDailyTracks : l10n.homeLoadingDaily30,
  HomeResourceStage.content || HomeResourceStage.empty =>
    dailyTracks ? l10n.homeDailyTracksUnavailable : l10n.homeDaily30Unavailable,
  HomeResourceStage.error =>
    dailyTracks ? l10n.homeDailyTracksFailure : l10n.homeDaily30Failure,
};

String _radarStateDetail(AppLocalizations l10n, RadarStage stage) =>
    switch (stage) {
      RadarStage.loading => l10n.homeRadarLoading,
      RadarStage.content => l10n.homeRadarUnavailable,
      RadarStage.empty => l10n.homeRadarEmpty,
      RadarStage.error => l10n.homeRadarFailure,
    };

String _newSongStateDetail(
  AppLocalizations l10n,
  NewSongStage stage, {
  required String providerDisplayName,
}) => switch (stage) {
  NewSongStage.loading => l10n.homePublicNewSongsLoading,
  NewSongStage.content => l10n.homePublicNewSongsUnavailable,
  NewSongStage.empty => l10n.homePublicNewSongsEmpty(providerDisplayName),
  NewSongStage.error => l10n.homePublicNewSongsFailure,
};

String _newSongFailureDetail(
  AppLocalizations l10n,
  NewSongFailure? failure, {
  required String providerDisplayName,
}) => switch (failure) {
  NewSongFailure.network => l10n.commonNetworkFailure,
  NewSongFailure.serviceUnavailable => l10n.homeNewSongsServiceFailure(
    providerDisplayName,
  ),
  NewSongFailure.cancelled => l10n.discoverNewSongCancelled,
  NewSongFailure.coreUnavailable => l10n.commonCoreUnavailable,
  NewSongFailure.invalidResponse => l10n.homeNewSongsInvalidResponse(
    providerDisplayName,
  ),
  NewSongFailure.alreadyRunning => l10n.homeNewSongsRunning,
  null => l10n.homePublicNewSongsFailure,
};

String _recommendationDetail(
  AppLocalizations l10n,
  RecommendedPlaylistSummary playlist,
) => playlist.trackCount == null
    ? l10n.homeMusicPlaylist
    : l10n.trackCount(playlist.trackCount!);

String _recommendationSemanticLabel(
  AppLocalizations l10n,
  RecommendedPlaylistSummary playlist,
) => playlist.trackCount == null
    ? l10n.homeMusicPlaylistSemantics(playlist.title)
    : '${playlist.title}, ${l10n.trackCount(playlist.trackCount!)}';

String _durationLabel(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

bool _sameTrack(PlaylistTrackSummary? track, PlaylistTrackSummary other) =>
    track != null &&
    track.providerId == other.providerId &&
    track.opaqueId == other.opaqueId;
