import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/l10n/app_locale.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authenticated_dependencies.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_controller.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/authentication/netease_official_web_login.dart';
import 'package:flutterustmusic/authentication/qq_music_media_credential_cleanup.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/home/daily_recommendation_gateway.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_track_gateway.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/home/recent_listening_gateway.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/recent_plays_gateway.dart';
import 'package:flutterustmusic/library/user_library_page.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_quality.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/provider_presentation.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_controller.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class MusicApp extends StatefulWidget {
  factory MusicApp({
    required BootstrapStatus bootstrap,
    QqMusicAuthenticationGateway? authenticationGateway,
    UserLibraryGateway? libraryGateway,
    PlaylistDetailGateway? playlistDetailGateway,
    RecentPlaysGateway? recentPlaysGateway,
    MediaResolutionGateway? mediaResolutionGateway,
    LyricGateway? lyricGateway,
    PlaybackQueueGateway? playbackQueueGateway,
    TrackSearchGateway? searchGateway,
    ArtistSearchGateway? artistSearchGateway,
    AlbumSearchGateway? albumSearchGateway,
    PlaylistSearchGateway? playlistSearchGateway,
    AlbumTrackGateway? albumTrackGateway,
    AlbumDetailsGateway? albumDetailsGateway,
    ArtistTrackGateway? artistTrackGateway,
    ArtistAlbumGateway? artistAlbumGateway,
    RecommendedPlaylistGateway? recommendedPlaylistGateway,
    NewAlbumGateway? newAlbumGateway,
    NewSongGateway? newSongGateway,
    RankingGateway? rankingGateway,
    RadarGateway? radarGateway,
    AccountSummaryGateway? accountSummaryGateway,
    DailyRecommendationGateway? dailyRecommendationGateway,
    PersonalizedPlaylistsGateway? personalizedPlaylistsGateway,
    PersonalizedTracksGateway? personalizedTracksGateway,
    RelatedTracksGateway? relatedTracksGateway,
    RecentListeningGateway Function()? recentListeningFactory,
    FavoriteAlbumGateway? favoriteAlbumGateway,
    FavoriteArtistGateway? favoriteArtistGateway,
    TrackCommentGateway? trackCommentGateway,
    ForegroundAudioEngine? audioEngine,
    bool desktopQuickLoginEnabled = false,
    AppPlaybackHost? playbackHost,
    AppSettings initialSettings = AppSettings.defaults,
    AppSettingsStore? settingsStore,
    BuiltInProviderDependencies? providerDependencies,
    ValueChanged<AppPlaybackQualityPreference>? onPlaybackQualityChanged,
    CredentialRestoreResult initialCredentialRestore =
        CredentialRestoreResult.signedOut,
    Key? key,
  }) {
    RustMediaResolutionGateway? defaultMediaResolutionGateway;
    if (authenticationGateway == null ||
        libraryGateway == null ||
        playlistDetailGateway == null ||
        mediaResolutionGateway == null ||
        lyricGateway == null ||
        radarGateway == null ||
        accountSummaryGateway == null ||
        dailyRecommendationGateway == null ||
        personalizedPlaylistsGateway == null ||
        personalizedTracksGateway == null ||
        favoriteAlbumGateway == null ||
        favoriteArtistGateway == null) {
      final fallbackCredentialVault = SerializedCredentialVault(
        PlatformCredentialVault(),
      );
      authenticationGateway ??= RustQqMusicAuthenticationGateway(
        credentialVault: fallbackCredentialVault,
      );
      libraryGateway ??= RustUserLibraryGateway(
        credentialVault: fallbackCredentialVault,
      );
      playlistDetailGateway ??= RustPlaylistDetailGateway(
        credentialVault: fallbackCredentialVault,
      );
      if (mediaResolutionGateway == null) {
        defaultMediaResolutionGateway = RustMediaResolutionGateway(
          preferredQuality: initialSettings.playbackQuality.audioPreference,
        );
        mediaResolutionGateway =
            QqMusicCredentialCleaningMediaResolutionGateway(
              defaultMediaResolutionGateway,
              credentialVault: fallbackCredentialVault,
            );
      }
      lyricGateway ??= RustLyricGateway(
        credentialVault: fallbackCredentialVault,
      );
      radarGateway ??= RustRadarGateway(
        credentialVault: fallbackCredentialVault,
      );
      accountSummaryGateway ??= RustAccountSummaryGateway(
        credentialVault: fallbackCredentialVault,
      );
      dailyRecommendationGateway ??= RustDailyRecommendationGateway(
        credentialVault: fallbackCredentialVault,
      );
      personalizedPlaylistsGateway ??= RustPersonalizedPlaylistsGateway(
        credentialVault: fallbackCredentialVault,
      );
      personalizedTracksGateway ??= RustPersonalizedTracksGateway(
        credentialVault: fallbackCredentialVault,
      );
      favoriteAlbumGateway ??= RustFavoriteAlbumGateway(
        credentialVault: fallbackCredentialVault,
      );
      favoriteArtistGateway ??= RustFavoriteArtistGateway(
        credentialVault: fallbackCredentialVault,
      );
    }
    final configuredProvider = MusicProviderDependencies(
      authenticationGateway: authenticationGateway,
      home: AuthenticatedHomeDependencies(
        recentListeningFactory: recentListeningFactory,
        accountSummaryGateway: accountSummaryGateway,
        dailyRecommendationGateway: dailyRecommendationGateway,
        personalizedPlaylistsGateway: personalizedPlaylistsGateway,
        personalizedTracksGateway: personalizedTracksGateway,
        relatedTracksGateway:
            relatedTracksGateway ?? const RustRelatedTracksGateway(),
      ),
      library: AuthenticatedLibraryDependencies(
        recentPlaysGateway: recentPlaysGateway,
        libraryGateway: libraryGateway,
        playlistDetailGateway: playlistDetailGateway,
        albumTrackGateway: albumTrackGateway ?? const RustAlbumTrackGateway(),
        albumDetailsGateway:
            albumDetailsGateway ?? const RustAlbumDetailsGateway(),
        artistTrackGateway:
            artistTrackGateway ?? const RustArtistTrackGateway(),
        artistAlbumGateway:
            artistAlbumGateway ?? const RustArtistAlbumGateway(),
        favoriteAlbumGateway: favoriteAlbumGateway,
        favoriteArtistGateway: favoriteArtistGateway,
      ),
      discovery: AuthenticatedDiscoveryDependencies(
        trackSearchGateway: searchGateway ?? const RustTrackSearchGateway(),
        artistSearchGateway:
            artistSearchGateway ?? const RustArtistSearchGateway(),
        albumSearchGateway:
            albumSearchGateway ?? const RustAlbumSearchGateway(),
        playlistSearchGateway:
            playlistSearchGateway ?? const RustPlaylistSearchGateway(),
        recommendedPlaylistGateway:
            recommendedPlaylistGateway ??
            const RustRecommendedPlaylistGateway(),
        newAlbumGateway: newAlbumGateway ?? const RustNewAlbumGateway(),
        newSongGateway: newSongGateway ?? const RustNewSongGateway(),
        rankingGateway: rankingGateway ?? const RustRankingGateway(),
        radarGateway: radarGateway,
      ),
      capabilities: MusicProviderCapabilities.qqMusic,
      desktopQuickLoginEnabled: desktopQuickLoginEnabled,
      initialCredentialRestore: initialCredentialRestore,
    );
    final resolvedPlaybackHost =
        playbackHost ??
        createForegroundAppPlaybackHost(
          playbackQueueGateway:
              playbackQueueGateway ?? RustPlaybackQueueGateway(),
          mediaResolutionGateway: mediaResolutionGateway,
          lyricGateway: lyricGateway,
          audioEngine: audioEngine ?? AudioplayersForegroundAudioEngine(),
        );
    return MusicApp._(
      bootstrap: bootstrap,
      providerDependencies:
          providerDependencies ??
          BuiltInProviderDependencies(
            qqMusic: configuredProvider,
            netEase: configuredProvider,
          ),
      playbackDependencies: AuthenticatedPlaybackDependencies(
        playbackHost: resolvedPlaybackHost,
        trackCommentGateway:
            trackCommentGateway ?? const RustTrackCommentGateway(),
      ),
      initialSettings: initialSettings,
      settingsStore: settingsStore,
      onPlaybackQualityChanged:
          onPlaybackQualityChanged ??
          (defaultMediaResolutionGateway == null
              ? null
              : (preference) => defaultMediaResolutionGateway!
                    .updatePreferredQuality(preference.audioPreference)),
      key: key,
    );
  }

  const MusicApp._({
    required this.bootstrap,
    required this.providerDependencies,
    required this.playbackDependencies,
    required this.initialSettings,
    required this.settingsStore,
    required this.onPlaybackQualityChanged,
    super.key,
  });

  final BootstrapStatus bootstrap;
  final BuiltInProviderDependencies providerDependencies;
  final AuthenticatedPlaybackDependencies playbackDependencies;
  final AppSettings initialSettings;
  final AppSettingsStore? settingsStore;
  final ValueChanged<AppPlaybackQualityPreference>? onPlaybackQualityChanged;

  @override
  State<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends State<MusicApp> {
  late final AppSettingsController _settingsController;

  @override
  void initState() {
    super.initState();
    _settingsController = AppSettingsController(
      widget.settingsStore,
      widget.onPlaybackQualityChanged,
      initialSettings: widget.initialSettings,
    )..addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<AppSettingsWriteResult> _updateSettings(AppSettings settings) =>
      _settingsController.update(settings);

  @override
  void dispose() {
    unawaited(widget.playbackDependencies.playbackHost.dispose());
    _settingsController
      ..removeListener(_onSettingsChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settingsController.settings;
    final provider = widget.providerDependencies.select(settings.musicProvider);
    Widget buildMaterialApp(
      ColorScheme? lightDynamic,
      ColorScheme? darkDynamic,
    ) {
      final useSystemColors =
          settings.colorSource == AppColorSourcePreference.system;
      final brandSeed = MusicMaterialTheme.brandSeedFor(settings.musicProvider);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => context.l10n.appTitle,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: materialLocaleForPreference(settings.localePreference),
        localeListResolutionCallback: resolveSupportedAppLocale,
        theme: MusicMaterialTheme.light(
          seed: brandSeed,
          colorScheme: useSystemColors ? lightDynamic : null,
        ),
        darkTheme: MusicMaterialTheme.dark(
          seed: brandSeed,
          colorScheme: useSystemColors ? darkDynamic : null,
        ),
        themeMode: settings.theme.materialThemeMode,
        home: LoginPage(
          bootstrap: widget.bootstrap,
          authenticationGateway: provider.authenticationGateway,
          homeDependencies: provider.home,
          libraryDependencies: provider.library,
          discoveryDependencies: provider.discovery,
          playbackDependencies: widget.playbackDependencies,
          capabilities: provider.capabilities,
          desktopQuickLoginEnabled: provider.desktopQuickLoginEnabled,
          settings: settings,
          onSettingsChanged: _updateSettings,
          initialCredentialRestore: provider.initialCredentialRestore,
        ),
      );
    }

    return DynamicColorBuilder(
      key: const ValueKey('app-dynamic-color-loader'),
      builder: buildMaterialApp,
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.bootstrap,
    required this.authenticationGateway,
    required this.homeDependencies,
    required this.libraryDependencies,
    required this.discoveryDependencies,
    required this.playbackDependencies,
    required this.capabilities,
    required this.desktopQuickLoginEnabled,
    required this.settings,
    required this.onSettingsChanged,
    required this.initialCredentialRestore,
    super.key,
  });

  final BootstrapStatus bootstrap;
  final QqMusicAuthenticationGateway authenticationGateway;
  final AuthenticatedHomeDependencies homeDependencies;
  final AuthenticatedLibraryDependencies libraryDependencies;
  final AuthenticatedDiscoveryDependencies discoveryDependencies;
  final AuthenticatedPlaybackDependencies playbackDependencies;
  final MusicProviderCapabilities capabilities;
  final bool desktopQuickLoginEnabled;
  final AppSettings settings;
  final Future<AppSettingsWriteResult> Function(AppSettings settings)
  onSettingsChanged;
  final CredentialRestoreResult initialCredentialRestore;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late LoginController _controller;
  bool _authenticationDialogOpen = false;
  LoginStage? _previousStage;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    _listenToController();
  }

  LoginController _createController() => LoginController(
    widget.authenticationGateway,
    desktopQuickLoginEnabled: widget.desktopQuickLoginEnabled,
    initialCredentialRestore: widget.initialCredentialRestore,
  );

  void _listenToController() {
    _previousStage = _controller.stage;
    _controller.addListener(_onAuthenticationChanged);
    if (widget.initialCredentialRestore ==
        CredentialRestoreResult.verificationRequired) {
      unawaited(_controller.verifyRestoredCredential());
    }
  }

  @override
  void didUpdateWidget(LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(
          oldWidget.authenticationGateway,
          widget.authenticationGateway,
        ) &&
        oldWidget.settings.musicProvider == widget.settings.musicProvider) {
      return;
    }

    final retiredController = _controller;
    retiredController.removeListener(_onAuthenticationChanged);
    final closeAuthenticationDialog = _authenticationDialogOpen;
    if (closeAuthenticationDialog) _authenticationDialogOpen = false;
    _controller = _createController();
    _listenToController();
    if (widget.initialCredentialRestore == CredentialRestoreResult.signedOut) {
      unawaited(_controller.restoreCredential());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      retiredController.cancel();
      if (mounted &&
          closeAuthenticationDialog &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      retiredController.dispose();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onAuthenticationChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onAuthenticationChanged() {
    final stage = _controller.stage;
    final shouldExplainSignOutCleanup =
        (stage == LoginStage.signOutStorageCleanupFailed ||
            stage == LoginStage.signOutBrowserCleanupFailed) &&
        stage != _previousStage;
    _previousStage = stage;
    if (shouldExplainSignOutCleanup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showAuthenticationDialog());
      });
    }
  }

  Future<void> _showAuthenticationDialog({bool reset = false}) async {
    if (_authenticationDialogOpen || !mounted) return;
    if (reset && _controller.stage != LoginStage.idle) {
      _controller.cancel();
    }
    final dialogController = _controller;
    _authenticationDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AuthenticationDialog(
        controller: dialogController,
        onClose: () {
          if (dialogController.stage != LoginStage.authenticated) {
            dialogController.cancel();
          }
          Navigator.of(context).pop();
        },
      ),
    );
    _authenticationDialogOpen = false;
  }

  void _requestSignIn() {
    unawaited(_showAuthenticationDialog());
  }

  void _requestSignInAgain() {
    unawaited(_showAuthenticationDialog(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final authenticated = _controller.stage == LoginStage.authenticated;
        return UserLibraryPage(
          key: const ValueKey('provider-library-shell'),
          homeDependencies: widget.homeDependencies,
          libraryDependencies: widget.libraryDependencies,
          discoveryDependencies: widget.discoveryDependencies,
          playbackDependencies: widget.playbackDependencies,
          capabilities: widget.capabilities,
          settings: widget.settings,
          onSettingsChanged: widget.onSettingsChanged,
          authenticated: authenticated,
          onRequestSignIn: _requestSignIn,
          onSignInAgain: _requestSignInAgain,
          onSignOut: _controller.signOut,
        );
      },
    );
  }
}

class _AuthenticationDialog extends StatefulWidget {
  const _AuthenticationDialog({
    required this.controller,
    required this.onClose,
  });

  final LoginController controller;
  final VoidCallback onClose;

  @override
  State<_AuthenticationDialog> createState() => _AuthenticationDialogState();
}

class _AuthenticationDialogState extends State<_AuthenticationDialog> {
  late LoginStage _previousStage;

  @override
  void initState() {
    super.initState();
    _previousStage = widget.controller.stage;
    widget.controller.addListener(_closeAfterAuthentication);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_closeAfterAuthentication);
    super.dispose();
  }

  void _closeAfterAuthentication() {
    final stage = widget.controller.stage;
    final completedStorageCleanup =
        (_previousStage == LoginStage.signOutStorageCleanupFailed ||
            _previousStage == LoginStage.signOutBrowserCleanupFailed) &&
        stage == LoginStage.idle;
    _previousStage = stage;
    if ((stage != LoginStage.authenticated && !completedStorageCleanup) ||
        !mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (widget.controller.stage == LoginStage.officialWebLogin &&
          widget.controller.officialWebPresentationListenable != null) {
        return _OfficialWebAuthenticationDialog(
          controller: widget.controller,
          onClose: widget.onClose,
        );
      }
      return PopScope(
        canPop: false,
        child: Dialog(
          key: const ValueKey('authentication-dialog'),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.controller.supportsDesktopQuickLogin ? 720 : 440,
              maxHeight: 720,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      key: const ValueKey('close-authentication-dialog'),
                      onPressed: widget.onClose,
                      tooltip: context.l10n.authCloseTooltip,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                  _AuthenticationPanel(controller: widget.controller),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _OfficialWebAuthenticationDialog extends StatelessWidget {
  const _OfficialWebAuthenticationDialog({
    required this.controller,
    required this.onClose,
  });

  final LoginController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final presentation = controller.officialWebPresentationListenable!;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Dialog.fullscreen(
        key: const ValueKey('authentication-dialog'),
        child: SafeArea(
          child: Column(
            children: [
              Material(
                color: colors.surfaceContainerLow,
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey('close-authentication-dialog'),
                        onPressed: onClose,
                        tooltip: context.l10n.authCloseTooltip,
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.authOfficialWebTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 20,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'music.163.com',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: colors.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: presentation,
                  builder: (context, _) {
                    final view = controller.officialWebLoginView;
                    final stage = controller.officialWebPresentationStage;
                    if (view != null &&
                        stage ==
                            OfficialWebLoginPresentationStage
                                .waitingForSignIn) {
                      return Column(
                        children: [
                          Material(
                            color: colors.secondaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    color: colors.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      context.l10n.authOfficialWebWaiting,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: colors.onSecondaryContainer,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: ColoredBox(
                              key: const ValueKey('official-web-login-surface'),
                              color: colors.surface,
                              child: view,
                            ),
                          ),
                        ],
                      );
                    }
                    final verifying =
                        stage == OfficialWebLoginPresentationStage.finishing;
                    final waitingInSystemBrowser =
                        view == null &&
                        stage ==
                            OfficialWebLoginPresentationStage.waitingForSignIn;
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (waitingInSystemBrowser)
                              Icon(
                                Icons.open_in_browser_rounded,
                                size: 48,
                                color: colors.primary,
                              )
                            else
                              const CircularProgressIndicator(),
                            const SizedBox(height: 20),
                            Text(
                              waitingInSystemBrowser
                                  ? context
                                        .l10n
                                        .authOfficialWebSystemBrowserWaiting
                                  : verifying
                                  ? context.l10n.authOfficialWebVerifying
                                  : context.l10n.authOfficialWebLoading,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (waitingInSystemBrowser) ...[
                              const SizedBox(height: 20),
                              const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthenticationPanel extends StatelessWidget {
  const _AuthenticationPanel({required this.controller});

  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: MusicRadii.panel,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(MusicSpacing.panel),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => AnimatedSwitcher(
            duration: MusicMotion.stateChange,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _AuthenticationContent(
              key: ValueKey(controller.stage),
              controller: controller,
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthenticationContent extends StatelessWidget {
  const _AuthenticationContent({required this.controller, super.key});

  final LoginController controller;

  String _providerName(BuildContext context) =>
      builtInProviderDisplayName(controller.providerId, context.l10n);

  String _qrActionLabel(BuildContext context) =>
      controller.providerId == 'qq-music'
      ? context.l10n.authScanWithQq
      : context.l10n.authScanWithProvider(_providerName(context));

  @override
  Widget build(BuildContext context) {
    final stage = controller.stage;
    if (stage == LoginStage.idle) {
      if (controller.showingSmsLogin) {
        return _SmsAuthenticationMethod(
          key: const ValueKey('sms-login-method'),
          controller: controller,
        );
      }
      return _idle(context);
    }
    if (stage == LoginStage.verificationRequired ||
        stage == LoginStage.verifyingStoredCredential) {
      return _verificationRequired(context);
    }
    if (stage == LoginStage.storedCredentialExpired ||
        stage == LoginStage.restoreError ||
        stage == LoginStage.credentialRejected ||
        stage == LoginStage.verificationError ||
        stage == LoginStage.signOutStorageCleanupFailed ||
        stage == LoginStage.signOutBrowserCleanupFailed) {
      return _restoreTerminal(context);
    }
    if (stage == LoginStage.starting) return _starting(context);
    if (stage == LoginStage.officialWebLogin) {
      return _officialWebLogin(context);
    }
    if (stage == LoginStage.officialWebError) {
      return _officialWebError(context);
    }
    if (stage == LoginStage.authenticated) return _authenticated(context);
    if (stage == LoginStage.waitingForScan ||
        stage == LoginStage.scannedAwaitingConfirmation ||
        stage == LoginStage.reconnecting) {
      return _active(context);
    }
    return _terminal(context);
  }

  Widget _idle(BuildContext context) => Column(
    key: const ValueKey('login-idle'),
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      _PanelIcon(
        icon: controller.usesOfficialWebOnly
            ? Icons.open_in_browser_rounded
            : Icons.qr_code_2_rounded,
      ),
      const SizedBox(height: 24),
      Text(
        controller.usesOfficialWebOnly
            ? context.l10n.authOfficialWebTitle
            : context.l10n.authSignInTitle(_providerName(context)),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Text(
        controller.usesOfficialWebOnly
            ? context.l10n.authOfficialWebDetail
            : controller.supportsMultipleQrMethods
            ? context.l10n.authIntroductionMultiple
            : context.l10n.authIntroductionSingle(_providerName(context)),
        style: _supportingStyle(context),
      ),
      const SizedBox(height: 28),
      if (controller.usesOfficialWebOnly)
        FilledButton.icon(
          key: const ValueKey('start-official-web-login-button'),
          onPressed: controller.supportsOfficialWebLogin
              ? controller.startOfficialWebLogin
              : null,
          icon: const Icon(Icons.open_in_browser_rounded),
          label: Text(context.l10n.authUseOfficialWebsite),
        )
      else
        FilledButton.icon(
          key: const ValueKey('start-qq-login-button'),
          onPressed: controller.supportsDesktopQuickLogin
              ? controller.startDesktopQqAuthorization
              : controller.supportsMultipleQrMethods
              ? () => controller.startQr(LoginQrChannel.qq)
              : controller.start,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: Text(_qrActionLabel(context)),
        ),
      if (!controller.usesOfficialWebOnly &&
          controller.supportsMultipleQrMethods) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('start-wechat-login-button'),
          onPressed: () => controller.startQr(LoginQrChannel.wechat),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: Text(context.l10n.authScanWithWechat),
        ),
      ],
      if (!controller.usesOfficialWebOnly && controller.supportsSmsLogin) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('show-sms-login-button'),
          onPressed: controller.showSmsLogin,
          icon: const Icon(Icons.sms_outlined),
          label: Text(context.l10n.authUsePhoneCode),
        ),
      ],
      if (!controller.usesOfficialWebOnly &&
          controller.supportsOfficialWebLogin) ...[
        const SizedBox(height: 10),
        TextButton.icon(
          key: const ValueKey('start-official-web-login-button'),
          onPressed: controller.startOfficialWebLogin,
          icon: const Icon(Icons.open_in_browser_rounded),
          label: Text(context.l10n.authUseOfficialWebsite),
        ),
      ],
    ],
  );

  Widget _starting(BuildContext context) => Column(
    key: const ValueKey('login-starting'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox.square(
        dimension: 42,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
      const SizedBox(height: 24),
      Text(
        context.l10n.authCreatingCodeTitle,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 10),
      Text(
        !controller.supportsMultipleQrMethods
            ? context.l10n.authConnectingProvider(_providerName(context))
            : controller.qrChannel == LoginQrChannel.qq
            ? context.l10n.authConnectingQq
            : context.l10n.authConnectingWechat,
        style: _supportingStyle(context),
      ),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: controller.cancel,
        child: Text(context.l10n.commonCancel),
      ),
    ],
  );

  Widget _verificationRequired(BuildContext context) {
    final verifying = controller.stage == LoginStage.verifyingStoredCredential;
    return Column(
      key: const ValueKey('credential-verification-required'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (verifying)
          const SizedBox.square(
            dimension: 42,
            child: CircularProgressIndicator(strokeWidth: 3),
          )
        else
          const _PanelIcon(icon: Icons.verified_user_outlined),
        const SizedBox(height: 24),
        Text(
          verifying
              ? context.l10n.authCheckingSavedSession
              : context.l10n.authSavedSessionFound,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          verifying
              ? context.l10n.authConfirmingSavedSession(_providerName(context))
              : context.l10n.authSavedSessionNeedsVerification(
                  _providerName(context),
                ),
          textAlign: TextAlign.center,
          style: _supportingStyle(context),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: controller.cancel,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: Text(context.l10n.authChooseMethod),
        ),
      ],
    );
  }

  Widget _officialWebLogin(BuildContext context) => Column(
    key: const ValueKey('official-web-login-active'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox.square(
        dimension: 42,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
      const SizedBox(height: 24),
      Text(
        context.l10n.authOfficialWebTitle,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 10),
      Text(
        context.l10n.authOfficialWebDetail,
        textAlign: TextAlign.center,
        style: _supportingStyle(context),
      ),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: controller.cancel,
        child: Text(context.l10n.commonCancel),
      ),
    ],
  );

  Widget _officialWebError(BuildContext context) {
    final detail = switch (controller.officialWebFailure) {
      OfficialWebAuthenticationFailure.unavailable =>
        context.l10n.authOfficialWebUnavailable,
      OfficialWebAuthenticationFailure.rejected =>
        context.l10n.authOfficialWebRejected,
      OfficialWebAuthenticationFailure.network =>
        context.l10n.authOfficialWebNetwork,
      OfficialWebAuthenticationFailure.serviceUnavailable =>
        context.l10n.authOfficialWebServiceUnavailable,
      OfficialWebAuthenticationFailure.invalidCredential ||
      OfficialWebAuthenticationFailure.invalidResponse =>
        context.l10n.authOfficialWebInvalidCredential,
      OfficialWebAuthenticationFailure.alreadyRunning =>
        context.l10n.authOfficialWebAlreadyRunning,
      OfficialWebAuthenticationFailure.timedOut =>
        context.l10n.authOfficialWebTimedOut,
      OfficialWebAuthenticationFailure.cleanupFailed =>
        context.l10n.authOfficialWebCleanupFailed,
      OfficialWebAuthenticationFailure.cancelled ||
      OfficialWebAuthenticationFailure.replaced ||
      OfficialWebAuthenticationFailure.coreUnavailable ||
      null => context.l10n.authOfficialWebFailed,
    };
    return Column(
      key: const ValueKey('official-web-login-error'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PanelIcon(icon: Icons.error_outline_rounded),
        const SizedBox(height: 24),
        _announcedAuthenticationMessage(
          context,
          context.l10n.authOfficialWebErrorTitle,
          detail,
        ),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          onPressed: controller.canRetryOfficialWebVerification
              ? controller.retryOfficialWebVerification
              : controller.startOfficialWebLogin,
          icon: const Icon(Icons.open_in_browser_rounded),
          label: Text(context.l10n.commonRetry),
        ),
        TextButton(
          onPressed: controller.cancel,
          child: Text(context.l10n.authChooseMethod),
        ),
      ],
    );
  }

  Widget _restoreTerminal(BuildContext context) {
    final result = controller.credentialRestoreResult;
    final l10n = context.l10n;
    final providerName = _providerName(context);
    final (title, detail) = switch (controller.stage) {
      LoginStage.signOutStorageCleanupFailed => (
        l10n.authSignedOutStorageTitle,
        l10n.authSignedOutStorageDetail(providerName),
      ),
      LoginStage.signOutBrowserCleanupFailed => (
        l10n.authSignedOutWebCleanupTitle,
        l10n.authSignedOutWebCleanupDetail(providerName),
      ),
      LoginStage.credentialRejected ||
      LoginStage.verificationError => _verificationTerminalCopy(
        controller.credentialVerificationResult,
        providerName,
        l10n,
      ),
      _ => switch (result) {
        CredentialRestoreResult.locallyExpired => (
          l10n.authSavedSessionExpiredTitle,
          l10n.authSavedSessionExpiredDetail(providerName),
        ),
        CredentialRestoreResult.unsupportedStoredCredential => (
          l10n.authSavedSessionOtherVersionTitle,
          l10n.authSavedSessionOtherVersionDetail,
        ),
        CredentialRestoreResult.storageUnavailable => (
          l10n.authStorageUnavailableTitle,
          l10n.authStorageUnavailableDetail,
        ),
        CredentialRestoreResult.coreUnavailable => (
          l10n.authCoreUnavailableTitle,
          l10n.authRestoreCoreUnavailableDetail,
        ),
        CredentialRestoreResult.invalidStoredCredential ||
        CredentialRestoreResult.signedOut ||
        CredentialRestoreResult.verificationRequired => (
          l10n.authSavedSessionUnreadableTitle,
          l10n.authSavedSessionUnreadableDetail,
        ),
      },
    };

    return Column(
      key: const ValueKey('credential-restore-terminal'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PanelIcon(icon: Icons.lock_reset_rounded),
        const SizedBox(height: 24),
        _announcedAuthenticationMessage(context, title, detail),
        const SizedBox(height: 24),
        if (controller.stage == LoginStage.signOutStorageCleanupFailed ||
            controller.stage == LoginStage.signOutBrowserCleanupFailed)
          FilledButton.tonal(
            key: const ValueKey('retry-sign-out-storage-cleanup'),
            onPressed: controller.canRetrySignOut
                ? () => controller.signOut()
                : null,
            child: Text(
              controller.isSigningOut
                  ? l10n.authRemovingSavedSession
                  : l10n.authRemoveSavedSessionAgain,
            ),
          )
        else if (controller.canRetryCredentialVerification)
          FilledButton.tonal(
            onPressed: controller.retryCredentialVerification,
            child: Text(l10n.authTryVerificationAgain),
          ),
        TextButton.icon(
          onPressed: controller.start,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: Text(l10n.authSignInAgain),
        ),
      ],
    );
  }

  (String, String) _verificationTerminalCopy(
    CredentialVerificationResult? result,
    String providerName,
    AppLocalizations l10n,
  ) => switch (result) {
    CredentialVerificationResult.rejected => (
      l10n.authSavedSessionRejectedTitle,
      l10n.authSavedSessionRejectedDetail(providerName),
    ),
    CredentialVerificationResult.rejectedStorageCleanupFailed => (
      l10n.authSavedSessionRejectedTitle,
      l10n.authSavedSessionRejectedCleanupDetail(providerName),
    ),
    CredentialVerificationResult.network => (
      l10n.authCouldNotReachProviderTitle(providerName),
      l10n.authSavedSessionNetworkDetail,
    ),
    CredentialVerificationResult.serviceUnavailable => (
      l10n.authProviderUnavailableTitle(providerName),
      l10n.authSavedSessionServiceDetail,
    ),
    CredentialVerificationResult.invalidResponse => (
      l10n.authProviderChangedResponseTitle(providerName),
      l10n.authSavedSessionInvalidResponseDetail,
    ),
    CredentialVerificationResult.coreUnavailable => (
      l10n.authCoreUnavailableTitle,
      l10n.authSavedSessionVerifyCoreDetail,
    ),
    CredentialVerificationResult.noRestoredCredential ||
    CredentialVerificationResult.replaced ||
    CredentialVerificationResult.authenticated ||
    null => (l10n.authSavedSessionNotCurrentTitle, l10n.authSignInAgainDetail),
  };

  Widget _active(BuildContext context) {
    final image = controller.qrImageBytes;
    final scanned = controller.stage == LoginStage.scannedAwaitingConfirmation;
    final reconnecting = controller.stage == LoginStage.reconnecting;
    final qrTitle = scanned
        ? context.l10n.authConfirmPhoneTitle
        : reconnecting
        ? context.l10n.authReconnectingTitle
        : !controller.supportsMultipleQrMethods
        ? _qrActionLabel(context)
        : controller.qrChannel == LoginQrChannel.qq
        ? context.l10n.authScanWithQq
        : context.l10n.authScanWithWechat;
    final qrDetail = scanned
        ? !controller.supportsMultipleQrMethods
              ? context.l10n.authCodeScannedProviderDetail
              : controller.qrChannel == LoginQrChannel.qq
              ? context.l10n.authCodeScannedQqDetail
              : context.l10n.authCodeScannedWechatDetail
        : reconnecting
        ? context.l10n.authReconnectingDetail
        : !controller.supportsMultipleQrMethods
        ? context.l10n.authOpenProviderScanDetail(_providerName(context))
        : controller.qrChannel == LoginQrChannel.qq
        ? context.l10n.authOpenQqScanDetail
        : context.l10n.authOpenWechatScanDetail;
    final qrMethod = _QrAuthenticationMethod(
      image: image,
      semanticLabel: !controller.supportsMultipleQrMethods
          ? context.l10n.authProviderQrSemantics(_providerName(context))
          : controller.qrChannel == LoginQrChannel.qq
          ? context.l10n.authQqQrSemantics
          : context.l10n.authWechatQrSemantics,
      title: qrTitle,
      detail: qrDetail,
    );
    final showQuickLogin =
        controller.supportsDesktopQuickLogin &&
        controller.qrChannel == LoginQrChannel.qq;

    return Column(
      key: const ValueKey('login-active'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.supportsDesktopQuickLogin) ...[
          SegmentedButton<LoginQrChannel>(
            key: const ValueKey('desktop-login-channel-selector'),
            segments: [
              ButtonSegment(
                value: LoginQrChannel.qq,
                icon: const Icon(Icons.person_rounded),
                label: Text(context.l10n.authQqLogin),
              ),
              ButtonSegment(
                value: LoginQrChannel.wechat,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(context.l10n.authWechatLogin),
              ),
            ],
            selected: {controller.qrChannel},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                unawaited(
                  selection.first == LoginQrChannel.qq
                      ? controller.startDesktopQqAuthorization()
                      : controller.startQr(selection.first),
                );
              }
            },
          ),
          const SizedBox(height: 24),
        ],
        if (showQuickLogin)
          LayoutBuilder(
            builder: (context, constraints) {
              final quickMethod = _AuthenticationMethodSection(
                key: const ValueKey('desktop-quick-login-method'),
                icon: Icons.desktop_windows_outlined,
                title: context.l10n.authQuickLoginTitle,
                detail: context.l10n.authQuickLoginDetail,
                child: _DesktopQuickLoginChoices(controller: controller),
              );
              if (constraints.maxWidth < 540) {
                return Column(
                  children: [quickMethod, const SizedBox(height: 28), qrMethod],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: quickMethod),
                    const SizedBox(width: 20),
                    VerticalDivider(
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    const SizedBox(width: 20),
                    Expanded(child: qrMethod),
                  ],
                ),
              );
            },
          )
        else
          qrMethod,
        if (controller.canOpenQrExternally ||
            controller.openingQrExternally ||
            controller.externalQrLaunchFailed) ...[
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            key: const ValueKey('open-netease-qr-externally'),
            onPressed: controller.canOpenQrExternally
                ? () => unawaited(controller.openQrChallengeExternally())
                : null,
            icon: controller.openingQrExternally
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new_rounded),
            label: Text(
              controller.openingQrExternally
                  ? context.l10n.authOpeningQrExternally
                  : context.l10n.authOpenQrExternally,
            ),
          ),
          if (controller.externalQrLaunchFailed) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.authOpenQrExternallyFailed,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: controller.cancel,
              child: Text(context.l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => controller.startQr(controller.qrChannel),
              child: Text(context.l10n.authNewCode),
            ),
          ],
        ),
      ],
    );
  }

  Widget _authenticated(BuildContext context) {
    final saveState = controller.credentialSaveState;
    final l10n = context.l10n;
    final providerName = _providerName(context);
    final (icon, detail) = switch (saveState) {
      CredentialSaveState.saving => (
        Icons.lock_clock_outlined,
        l10n.authSavingSessionDetail(providerName),
      ),
      CredentialSaveState.saved => (
        Icons.lock_rounded,
        l10n.authSavedSessionReadyDetail,
      ),
      CredentialSaveState.failed => (
        Icons.warning_amber_rounded,
        l10n.authSessionOnlyDetail,
      ),
      CredentialSaveState.none => (
        Icons.check_rounded,
        l10n.authStorageNotConfirmedDetail(providerName),
      ),
    };

    return Column(
      key: const ValueKey('login-authenticated'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _PanelIcon(icon: icon),
        const SizedBox(height: 24),
        Text(
          l10n.authSignedInTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: _supportingStyle(context),
        ),
      ],
    );
  }

  Widget _terminal(BuildContext context) {
    final (title, detail) = _terminalCopy(
      controller.stage,
      controller.failure,
      _providerName(context),
      context.l10n,
    );

    return Column(
      key: const ValueKey('login-terminal'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PanelIcon(icon: Icons.error_outline_rounded),
        const SizedBox(height: 24),
        _announcedAuthenticationMessage(context, title, detail),
        const SizedBox(height: 24),
        if (controller.canRetry)
          FilledButton.tonal(
            onPressed: controller.retry,
            child: Text(context.l10n.commonRetry),
          ),
        if (controller.supportsOfficialWebLogin &&
            (controller.failure == LoginFailure.securityVerificationRequired ||
                controller.failure ==
                    LoginFailure.secondaryVerificationRequired))
          FilledButton.tonalIcon(
            key: const ValueKey('continue-official-web-login-button'),
            onPressed: controller.startOfficialWebLogin,
            icon: const Icon(Icons.open_in_browser_rounded),
            label: Text(context.l10n.authUseOfficialWebsite),
          ),
        TextButton(
          onPressed: controller.cancel,
          child: Text(context.l10n.authChooseMethod),
        ),
      ],
    );
  }

  Widget _announcedAuthenticationMessage(
    BuildContext context,
    String title,
    String detail, {
    double spacing = 10,
  }) => Semantics(
    container: true,
    liveRegion: true,
    label: context.l10n.authAnnouncementSemantics(detail, title),
    excludeSemantics: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: spacing),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: _supportingStyle(context),
        ),
      ],
    ),
  );

  TextStyle? _supportingStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .bodyMedium
      ?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.45,
      );

  (String, String) _terminalCopy(
    LoginStage stage,
    LoginFailure? failure,
    String providerName,
    AppLocalizations l10n,
  ) {
    if (stage == LoginStage.expired || stage == LoginStage.timedOut) {
      return (l10n.authCodeExpiredTitle, l10n.authCodeExpiredDetail);
    }
    if (stage == LoginStage.refused) {
      return (l10n.authNotApprovedTitle, l10n.authNotApprovedDetail);
    }

    return switch (failure) {
      LoginFailure.securityVerificationRequired => (
        l10n.authSecurityVerificationTitle(providerName),
        l10n.authSecurityVerificationDetail,
      ),
      LoginFailure.secondaryVerificationRequired => (
        l10n.authSecondaryVerificationTitle(providerName),
        l10n.authSecondaryVerificationDetail,
      ),
      LoginFailure.serviceUnavailable => (
        l10n.authProviderUnavailableTitle(providerName),
        l10n.authServiceRejectedDetail,
      ),
      LoginFailure.rejected => (
        l10n.authRejectedTitle,
        l10n.authRejectedDetail,
      ),
      LoginFailure.tooManyNetworkFailures => (
        l10n.authNetworkFailuresTitle,
        l10n.authNetworkFailuresDetail,
      ),
      LoginFailure.invalidResponse => (
        l10n.authProviderChangedResponseTitle(providerName),
        l10n.authInvalidResponseDetail,
      ),
      _ => (l10n.authCouldNotContinueTitle, l10n.authCouldNotContinueDetail),
    };
  }
}

class _AuthenticationMethodSection extends StatelessWidget {
  const _AuthenticationMethodSection({
    required this.icon,
    required this.title,
    required this.detail,
    required this.child,
    this.announce = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget child;
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (announce)
          Semantics(
            container: true,
            liveRegion: true,
            label: context.l10n.authAnnouncementSemantics(detail, title),
            excludeSemantics: true,
            child: heading,
          )
        else
          heading,
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _SmsAuthenticationMethod extends StatefulWidget {
  const _SmsAuthenticationMethod({required this.controller, super.key});

  final LoginController controller;

  @override
  State<_SmsAuthenticationMethod> createState() =>
      _SmsAuthenticationMethodState();
}

class _SmsAuthenticationMethodState extends State<_SmsAuthenticationMethod> {
  static final RegExp _digits = RegExp(r'^\d+$');

  final TextEditingController _countryCode = TextEditingController(text: '86');
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;
  bool _showPhoneValidation = false;
  bool _showCodeValidation = false;
  bool _lastCodeRequested = false;

  @override
  void initState() {
    super.initState();
    _countryCode.addListener(_inputChanged);
    _phone.addListener(_inputChanged);
    _code.addListener(_inputChanged);
    widget.controller.addListener(_controllerChanged);
    _lastCodeRequested = widget.controller.smsCodeRequested;
  }

  @override
  void didUpdateWidget(_SmsAuthenticationMethod oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_controllerChanged);
    widget.controller.addListener(_controllerChanged);
    _lastCodeRequested = widget.controller.smsCodeRequested;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _cooldownTimer?.cancel();
    _countryCode.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _validCountryCode {
    final value = _countryCode.text;
    return value.length <= 4 && value.isNotEmpty && _digits.hasMatch(value);
  }

  bool get _validPhone {
    final value = _phone.text;
    return value.length >= 5 && value.length <= 15 && _digits.hasMatch(value);
  }

  bool get _validCode {
    final value = _code.text;
    return value.length >= 4 && value.length <= 8 && _digits.hasMatch(value);
  }

  bool get _busy =>
      widget.controller.smsStage == SmsLoginStage.sendingCode ||
      widget.controller.smsStage == SmsLoginStage.authenticating;

  void _inputChanged() {
    if (!mounted) return;
    setState(() {
      if (_validCountryCode && _validPhone) _showPhoneValidation = false;
      if (_validCode) _showCodeValidation = false;
    });
  }

  void _controllerChanged() {
    final codeRequested = widget.controller.smsCodeRequested;
    if (codeRequested && !_lastCodeRequested) _startCooldown();
    _lastCodeRequested = codeRequested;
    if (mounted) setState(() {});
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownSeconds = 60;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownSeconds -= 1;
        if (_cooldownSeconds <= 0) timer.cancel();
      });
    });
  }

  void _requestCode() {
    if (_busy || _cooldownSeconds > 0) return;
    setState(() => _showPhoneValidation = true);
    if (!_validCountryCode || !_validPhone) return;
    unawaited(
      widget.controller.requestSmsCode(
        countryCode: _countryCode.text,
        phone: _phone.text,
      ),
    );
  }

  void _signIn() {
    if (_busy || !widget.controller.smsCodeRequested) return;
    setState(() => _showCodeValidation = true);
    if (!_validCode) return;
    unawaited(widget.controller.authenticateSmsCode(_code.text));
  }

  String? _failureText(
    BuildContext context,
  ) => switch (widget.controller.smsFailure) {
    SmsAuthenticationFailure.invalidInput => context.l10n.authSmsInvalidInput,
    SmsAuthenticationFailure.codeRejected => context.l10n.authSmsCodeRejected,
    SmsAuthenticationFailure.rateLimited => context.l10n.authSmsRateLimited,
    SmsAuthenticationFailure.securityVerificationRequired =>
      context.l10n.authSmsSecurityVerification,
    SmsAuthenticationFailure.secondaryVerificationRequired =>
      context.l10n.authSmsSecondaryVerification,
    SmsAuthenticationFailure.network => context.l10n.authSmsNetworkFailure,
    SmsAuthenticationFailure.serviceUnavailable =>
      context.l10n.authSmsServiceUnavailable,
    SmsAuthenticationFailure.invalidResponse =>
      context.l10n.authSmsInvalidResponse,
    SmsAuthenticationFailure.alreadyRunning =>
      context.l10n.authSmsAlreadyRunning,
    SmsAuthenticationFailure.replaced => context.l10n.authSmsAttemptReplaced,
    SmsAuthenticationFailure.coreUnavailable =>
      context.l10n.authSmsCoreUnavailable,
    null => null,
  };

  Widget _phoneFields(BuildContext context) {
    final countryCode = TextField(
      key: const ValueKey('sms-country-code-field'),
      controller: _countryCode,
      enabled: !_busy,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(
        labelText: context.l10n.authCountryCode,
        prefixText: '+',
      ),
    );
    final phone = TextField(
      key: const ValueKey('sms-phone-field'),
      controller: _phone,
      enabled: !_busy,
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumber],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(15),
      ],
      decoration: InputDecoration(labelText: context.l10n.authPhoneNumber),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: constraints.maxWidth.clamp(0, 180).toDouble(),
                  child: countryCode,
                ),
              ),
              const SizedBox(height: 12),
              phone,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: countryCode),
            const SizedBox(width: 12),
            Expanded(child: phone),
          ],
        );
      },
    );
  }

  Widget _actions(
    BuildContext context, {
    required bool sending,
    required bool authenticating,
  }) {
    final qr = TextButton.icon(
      key: const ValueKey('show-qr-login-button'),
      onPressed: _busy ? null : widget.controller.showQrLogin,
      icon: const Icon(Icons.qr_code_2_rounded),
      label: Text(context.l10n.authUseQrCode),
    );
    final officialWeb = TextButton.icon(
      key: const ValueKey('sms-official-web-login-button'),
      onPressed: _busy || !widget.controller.supportsOfficialWebLogin
          ? null
          : widget.controller.startOfficialWebLogin,
      icon: const Icon(Icons.open_in_browser_rounded),
      label: Text(context.l10n.authUseOfficialWebsite),
    );
    final request = OutlinedButton(
      key: const ValueKey('request-sms-code-button'),
      onPressed: _busy || _cooldownSeconds > 0 ? null : _requestCode,
      child: Text(
        sending
            ? context.l10n.authSendingCode
            : _cooldownSeconds > 0
            ? context.l10n.authResendCodeIn(_cooldownSeconds)
            : widget.controller.smsCodeRequested
            ? context.l10n.authResendCode
            : context.l10n.authSendCode,
      ),
    );
    final submit = FilledButton(
      key: const ValueKey('submit-sms-login-button'),
      onPressed: _busy || !widget.controller.smsCodeRequested || !_validCode
          ? null
          : _signIn,
      child: Text(
        authenticating
            ? context.l10n.authCheckingSmsCode
            : context.l10n.authSmsSignIn,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              request,
              const SizedBox(height: 8),
              submit,
              const SizedBox(height: 4),
              if (widget.controller.supportsOfficialWebLogin) officialWeb,
              if (widget.controller.supportsOfficialWebLogin)
                const SizedBox(height: 4),
              qr,
            ],
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            qr,
            if (widget.controller.supportsOfficialWebLogin) officialWeb,
            request,
            submit,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sending = widget.controller.smsStage == SmsLoginStage.sendingCode;
    final authenticating =
        widget.controller.smsStage == SmsLoginStage.authenticating;
    final failure = _failureText(context);
    final phoneValidation =
        _showPhoneValidation && (!_validCountryCode || !_validPhone);
    final codeValidation = _showCodeValidation && !_validCode;

    return _AuthenticationMethodSection(
      icon: Icons.sms_outlined,
      title: context.l10n.authPhoneCodeTitle,
      detail: context.l10n.authPhoneCodeDetail,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _phoneFields(context),
            if (phoneValidation) ...[
              const SizedBox(height: 6),
              Text(
                context.l10n.authSmsInvalidInput,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('sms-code-field'),
              controller: _code,
              enabled: widget.controller.smsCodeRequested && !authenticating,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              onSubmitted: (_) => _signIn(),
              decoration: InputDecoration(
                labelText: context.l10n.authSmsCode,
                errorText: codeValidation
                    ? context.l10n.authSmsInvalidInput
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.controller.smsCodeRequested && failure == null)
              Text(
                context.l10n.authCodeSent,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                ),
              ),
            if (failure != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  failure,
                  key: const ValueKey('sms-authentication-error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: MusicRadii.content,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.authSmsRiskWarning,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _actions(context, sending: sending, authenticating: authenticating),
          ],
        ),
      ),
    );
  }
}

class _QrAuthenticationMethod extends StatelessWidget {
  const _QrAuthenticationMethod({
    required this.image,
    required this.semanticLabel,
    required this.title,
    required this.detail,
  });

  final Uint8List? image;
  final String semanticLabel;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => _AuthenticationMethodSection(
    key: const ValueKey('qr-login-method'),
    icon: Icons.qr_code_2_rounded,
    title: title,
    detail: detail,
    announce: true,
    child: Center(
      child: image == null
          ? const SizedBox.square(
              dimension: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          : Semantics(
              label: semanticLabel,
              image: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Image.memory(
                      image!,
                      width: 220,
                      height: 220,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const SizedBox.square(
                        dimension: 220,
                        child: Icon(Icons.broken_image_outlined, size: 48),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}

class _DesktopQuickLoginChoices extends StatelessWidget {
  const _DesktopQuickLoginChoices({required this.controller});

  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final stage = controller.desktopQuickStage;
    if (stage == DesktopQuickLoginStage.loading) {
      return Row(
        key: ValueKey('desktop-quick-login-loading'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(context.l10n.authCheckingDesktopQq)),
        ],
      );
    }

    final accounts = controller.desktopQuickAccounts;
    if (stage == DesktopQuickLoginStage.noAccounts ||
        (stage == DesktopQuickLoginStage.error && accounts.isEmpty)) {
      return _DesktopQuickLoginUnavailable(
        failure: controller.desktopQuickFailure,
        onRetry: controller.loadDesktopQuickAccounts,
      );
    }
    if (accounts.isEmpty) return const SizedBox.shrink();

    final authorizing = stage == DesktopQuickLoginStage.authorizing;
    return Column(
      key: const ValueKey('desktop-quick-login-accounts'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final account in accounts)
                SizedBox(
                  width: 128,
                  child: OutlinedButton(
                    key: ValueKey(
                      'desktop-quick-account-${account.selectionId}',
                    ),
                    onPressed:
                        !authorizing &&
                            controller.canAuthorizeDesktopQuickAccount
                        ? () => controller.authorizeDesktopQuickAccount(
                            account.selectionId,
                          )
                        : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          child:
                              authorizing &&
                                  controller.desktopQuickSelectionId ==
                                      account.selectionId
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.person_rounded),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          account.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          account.accountHint,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (stage == DesktopQuickLoginStage.error) ...[
          const SizedBox(height: 10),
          Text(
            _desktopQuickFailureCopy(
              controller.desktopQuickFailure,
              context.l10n,
            ),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _DesktopQuickLoginUnavailable extends StatelessWidget {
  const _DesktopQuickLoginUnavailable({
    required this.failure,
    required this.onRetry,
  });

  final DesktopQuickLoginFailure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('desktop-quick-login-unavailable'),
    children: [
      Icon(
        Icons.desktop_windows_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          failure == DesktopQuickLoginFailure.clientUnavailable
              ? context.l10n.authOpenDesktopQqDetail
              : failure == null
              ? context.l10n.authNoDesktopAccount
              : _desktopQuickFailureCopy(failure, context.l10n),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      TextButton(onPressed: onRetry, child: Text(context.l10n.commonRetry)),
    ],
  );
}

String _desktopQuickFailureCopy(
  DesktopQuickLoginFailure? failure,
  AppLocalizations l10n,
) => switch (failure) {
  DesktopQuickLoginFailure.clientUnavailable =>
    l10n.authDesktopClientUnavailable,
  DesktopQuickLoginFailure.network => l10n.authDesktopNetworkFailure,
  DesktopQuickLoginFailure.serviceUnavailable =>
    l10n.authDesktopServiceUnavailable,
  DesktopQuickLoginFailure.rejected => l10n.authDesktopRejected,
  DesktopQuickLoginFailure.invalidSelection ||
  DesktopQuickLoginFailure.invalidResponse => l10n.authDesktopInvalidResponse,
  DesktopQuickLoginFailure.cancelled ||
  DesktopQuickLoginFailure.replaced ||
  DesktopQuickLoginFailure.sessionFinished => l10n.authDesktopAttemptInactive,
  DesktopQuickLoginFailure.alreadyRunning => l10n.authDesktopAlreadyRunning,
  DesktopQuickLoginFailure.coreUnavailable => l10n.authDesktopCoreUnavailable,
  null => l10n.authDesktopUnavailable,
};

class _PanelIcon extends StatelessWidget {
  const _PanelIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: MusicRadii.content,
      ),
      child: Icon(icon, color: colors.onPrimaryContainer, size: 30),
    );
  }
}
