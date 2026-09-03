import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authenticated_dependencies.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_controller.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
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
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/user_library_page.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class MusicApp extends StatefulWidget {
  factory MusicApp({
    required BootstrapStatus bootstrap,
    QqMusicAuthenticationGateway? authenticationGateway,
    UserLibraryGateway? libraryGateway,
    PlaylistDetailGateway? playlistDetailGateway,
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
    FavoriteAlbumGateway? favoriteAlbumGateway,
    FavoriteArtistGateway? favoriteArtistGateway,
    TrackCommentGateway? trackCommentGateway,
    ForegroundAudioEngine? audioEngine,
    bool desktopQuickLoginEnabled = false,
    SystemPlaybackBinding systemPlaybackBinding =
        const NoopSystemPlaybackBinding(),
    AppSettings initialSettings = AppSettings.defaults,
    AppSettingsStore? settingsStore,
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
          preferredQuality: _playbackQuality(initialSettings.playbackQuality),
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
    return MusicApp._(
      bootstrap: bootstrap,
      authenticationGateway: authenticationGateway,
      homeDependencies: AuthenticatedHomeDependencies(
        accountSummaryGateway: accountSummaryGateway,
        dailyRecommendationGateway: dailyRecommendationGateway,
        personalizedPlaylistsGateway: personalizedPlaylistsGateway,
        personalizedTracksGateway: personalizedTracksGateway,
        relatedTracksGateway:
            relatedTracksGateway ?? const RustRelatedTracksGateway(),
      ),
      libraryDependencies: AuthenticatedLibraryDependencies(
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
      discoveryDependencies: AuthenticatedDiscoveryDependencies(
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
      playbackDependencies: AuthenticatedPlaybackDependencies(
        mediaResolutionGateway: mediaResolutionGateway,
        lyricGateway: lyricGateway,
        playbackQueueGateway:
            playbackQueueGateway ?? RustPlaybackQueueGateway(),
        trackCommentGateway:
            trackCommentGateway ?? const RustTrackCommentGateway(),
        audioEngine: audioEngine ?? AudioplayersForegroundAudioEngine(),
        systemPlaybackBinding: systemPlaybackBinding,
      ),
      desktopQuickLoginEnabled: desktopQuickLoginEnabled,
      initialSettings: initialSettings,
      settingsStore: settingsStore,
      onPlaybackQualityChanged:
          onPlaybackQualityChanged ??
          (defaultMediaResolutionGateway == null
              ? null
              : (preference) => defaultMediaResolutionGateway!
                    .updatePreferredQuality(_playbackQuality(preference))),
      initialCredentialRestore: initialCredentialRestore,
      key: key,
    );
  }

  const MusicApp._({
    required this.bootstrap,
    required this.authenticationGateway,
    required this.homeDependencies,
    required this.libraryDependencies,
    required this.discoveryDependencies,
    required this.playbackDependencies,
    required this.desktopQuickLoginEnabled,
    required this.initialSettings,
    required this.settingsStore,
    required this.onPlaybackQualityChanged,
    required this.initialCredentialRestore,
    super.key,
  });

  final BootstrapStatus bootstrap;
  final QqMusicAuthenticationGateway authenticationGateway;
  final AuthenticatedHomeDependencies homeDependencies;
  final AuthenticatedLibraryDependencies libraryDependencies;
  final AuthenticatedDiscoveryDependencies discoveryDependencies;
  final AuthenticatedPlaybackDependencies playbackDependencies;
  final bool desktopQuickLoginEnabled;
  final AppSettings initialSettings;
  final AppSettingsStore? settingsStore;
  final ValueChanged<AppPlaybackQualityPreference>? onPlaybackQualityChanged;
  final CredentialRestoreResult initialCredentialRestore;

  @override
  State<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends State<MusicApp> {
  late AppSettings _settings;
  AppSettingsStore? _settingsStore;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _settingsStore = widget.settingsStore;
  }

  Future<AppSettingsWriteResult> _updateSettings(AppSettings settings) async {
    if (settings == _settings) return AppSettingsWriteResult.saved;
    final previous = _settings;
    setState(() => _settings = settings);
    widget.onPlaybackQualityChanged?.call(settings.playbackQuality);
    var result = AppSettingsWriteResult.storageUnavailable;
    try {
      final store = _settingsStore ??= AppSettingsStore();
      result = await store.save(settings);
    } on Object {
      result = AppSettingsWriteResult.storageUnavailable;
    }
    if (result == AppSettingsWriteResult.storageUnavailable &&
        mounted &&
        _settings == settings) {
      setState(() => _settings = previous);
      widget.onPlaybackQualityChanged?.call(previous.playbackQuality);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'fura music',
    theme: MusicMaterialTheme.light(),
    darkTheme: MusicMaterialTheme.dark(),
    themeMode: _settings.theme.materialThemeMode,
    home: LoginPage(
      bootstrap: widget.bootstrap,
      authenticationGateway: widget.authenticationGateway,
      homeDependencies: widget.homeDependencies,
      libraryDependencies: widget.libraryDependencies,
      discoveryDependencies: widget.discoveryDependencies,
      playbackDependencies: widget.playbackDependencies,
      desktopQuickLoginEnabled: widget.desktopQuickLoginEnabled,
      settings: _settings,
      onSettingsChanged: _updateSettings,
      initialCredentialRestore: widget.initialCredentialRestore,
    ),
  );
}

PlaybackAudioQualityPreference _playbackQuality(
  AppPlaybackQualityPreference preference,
) => switch (preference) {
  AppPlaybackQualityPreference.standard =>
    PlaybackAudioQualityPreference.standard,
  AppPlaybackQualityPreference.high => PlaybackAudioQualityPreference.high,
};

class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.bootstrap,
    required this.authenticationGateway,
    required this.homeDependencies,
    required this.libraryDependencies,
    required this.discoveryDependencies,
    required this.playbackDependencies,
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
  final bool desktopQuickLoginEnabled;
  final AppSettings settings;
  final Future<AppSettingsWriteResult> Function(AppSettings settings)
  onSettingsChanged;
  final CredentialRestoreResult initialCredentialRestore;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final LoginController _controller;
  bool _authenticationDialogOpen = false;
  LoginStage? _previousStage;

  @override
  void initState() {
    super.initState();
    _controller = LoginController(
      widget.authenticationGateway,
      desktopQuickLoginEnabled: widget.desktopQuickLoginEnabled,
      initialCredentialRestore: widget.initialCredentialRestore,
    );
    _previousStage = _controller.stage;
    _controller.addListener(_onAuthenticationChanged);
    if (widget.initialCredentialRestore ==
        CredentialRestoreResult.verificationRequired) {
      unawaited(_controller.verifyRestoredCredential());
    }
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
        stage == LoginStage.signOutStorageCleanupFailed &&
        _previousStage != LoginStage.signOutStorageCleanupFailed;
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
    _authenticationDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AuthenticationDialog(
        controller: _controller,
        onClose: () {
          if (_controller.stage != LoginStage.authenticated) {
            _controller.cancel();
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
          key: ValueKey(
            authenticated ? 'user-library-page' : 'signed-out-main-page',
          ),
          homeDependencies: widget.homeDependencies,
          libraryDependencies: widget.libraryDependencies,
          discoveryDependencies: widget.discoveryDependencies,
          playbackDependencies: widget.playbackDependencies,
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
        _previousStage == LoginStage.signOutStorageCleanupFailed &&
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
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      key: const ValueKey('authentication-dialog'),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.controller.supportsDesktopQuickLogin ? 560 : 440,
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
                  tooltip: 'Close sign in',
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

  @override
  Widget build(BuildContext context) {
    final stage = controller.stage;
    if (stage == LoginStage.idle) {
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
        stage == LoginStage.signOutStorageCleanupFailed) {
      return _restoreTerminal(context);
    }
    if (stage == LoginStage.starting) return _starting(context);
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
      const _PanelIcon(icon: Icons.qr_code_2_rounded),
      const SizedBox(height: 24),
      Text(
        'Sign in to QQ Music',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Text(
        'Authorize with QQ or WeChat QR. Passwords are never collected.',
        style: _supportingStyle(context),
      ),
      const SizedBox(height: 28),
      FilledButton.icon(
        key: const ValueKey('start-qq-login-button'),
        onPressed: controller.supportsDesktopQuickLogin
            ? controller.startDesktopQqAuthorization
            : () => controller.startQr(LoginQrChannel.qq),
        icon: const Icon(Icons.qr_code_2_rounded),
        label: const Text('Scan with QQ'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        key: const ValueKey('start-wechat-login-button'),
        onPressed: () => controller.startQr(LoginQrChannel.wechat),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan with WeChat'),
      ),
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
        'Creating a secure code…',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 10),
      Text(
        controller.qrChannel == LoginQrChannel.qq
            ? 'Connecting directly to QQ authorization.'
            : 'Connecting directly to WeChat and QQ Music.',
        style: _supportingStyle(context),
      ),
      const SizedBox(height: 20),
      OutlinedButton(onPressed: controller.cancel, child: const Text('Cancel')),
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
          verifying ? 'Checking your saved session…' : 'Saved session found',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          verifying
              ? 'Confirming it directly with QQ Music before restoring access.'
              : 'It passed local checks but still needs QQ Music verification.',
          textAlign: TextAlign.center,
          style: _supportingStyle(context),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: controller.cancel,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('Choose a sign-in method'),
        ),
      ],
    );
  }

  Widget _restoreTerminal(BuildContext context) {
    final result = controller.credentialRestoreResult;
    final (title, detail) = switch (controller.stage) {
      LoginStage.signOutStorageCleanupFailed => (
        'Signed out, but saved session remains',
        'The active QQ Music session was cleared, but secure storage could not '
            'remove its saved copy. It may appear again after restart.',
      ),
      LoginStage.credentialRejected || LoginStage.verificationError =>
        _verificationTerminalCopy(controller.credentialVerificationResult),
      _ => switch (result) {
        CredentialRestoreResult.locallyExpired => (
          'Saved session expired',
          'QQ Music’s advertised lifetime has ended. Sign in again to continue.',
        ),
        CredentialRestoreResult.unsupportedStoredCredential => (
          'Saved session is from another version',
          'This build left it unchanged instead of guessing. You can replace it '
              'by signing in again.',
        ),
        CredentialRestoreResult.storageUnavailable => (
          'Secure storage is unavailable',
          'You can sign in for this run, but the session may not survive restart.',
        ),
        CredentialRestoreResult.coreUnavailable => (
          'The music core is unavailable',
          'The stored session could not be checked safely. Try again after restart.',
        ),
        CredentialRestoreResult.invalidStoredCredential ||
        CredentialRestoreResult.signedOut ||
        CredentialRestoreResult.verificationRequired => (
          'Saved session could not be read',
          'It was left unchanged instead of being treated as a valid login. '
              'You can replace it by signing in again.',
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
        if (controller.stage == LoginStage.signOutStorageCleanupFailed)
          FilledButton.tonal(
            key: const ValueKey('retry-sign-out-storage-cleanup'),
            onPressed: controller.canRetrySignOut
                ? () => controller.signOut()
                : null,
            child: Text(
              controller.isSigningOut
                  ? 'Removing saved session…'
                  : 'Try removing it again',
            ),
          )
        else if (controller.canRetryCredentialVerification)
          FilledButton.tonal(
            onPressed: controller.retryCredentialVerification,
            child: const Text('Try verification again'),
          ),
        TextButton.icon(
          onPressed: controller.start,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('Sign in again'),
        ),
      ],
    );
  }

  (String, String) _verificationTerminalCopy(
    CredentialVerificationResult? result,
  ) => switch (result) {
    CredentialVerificationResult.rejected => (
      'Saved session was rejected',
      'QQ Music no longer accepts it, so the stored session was removed.',
    ),
    CredentialVerificationResult.rejectedStorageCleanupFailed => (
      'Saved session was rejected',
      'QQ Music no longer accepts it, but secure storage could not remove it. '
          'It may appear again after restart.',
    ),
    CredentialVerificationResult.network => (
      'Couldn’t reach QQ Music',
      'The saved session is still available. Check your connection and try again.',
    ),
    CredentialVerificationResult.serviceUnavailable => (
      'QQ Music is unavailable',
      'The saved session was kept unchanged. Try verification again later.',
    ),
    CredentialVerificationResult.invalidResponse => (
      'QQ Music changed its response',
      'The saved session was kept instead of being treated as signed out.',
    ),
    CredentialVerificationResult.coreUnavailable => (
      'The music core is unavailable',
      'The saved session could not be verified safely. Try again after restart.',
    ),
    CredentialVerificationResult.noRestoredCredential ||
    CredentialVerificationResult.replaced ||
    CredentialVerificationResult.authenticated ||
    null => (
      'Saved session is no longer current',
      'Sign in again to continue.',
    ),
  };

  Widget _active(BuildContext context) {
    final image = controller.qrImageBytes;
    final scanned = controller.stage == LoginStage.scannedAwaitingConfirmation;
    final reconnecting = controller.stage == LoginStage.reconnecting;

    return Column(
      key: const ValueKey('login-active'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.supportsDesktopQuickLogin) ...[
          SegmentedButton<LoginQrChannel>(
            key: const ValueKey('desktop-login-channel-selector'),
            segments: const [
              ButtonSegment(
                value: LoginQrChannel.qq,
                icon: Icon(Icons.person_rounded),
                label: Text('QQ login'),
              ),
              ButtonSegment(
                value: LoginQrChannel.wechat,
                icon: Icon(Icons.qr_code_scanner_rounded),
                label: Text('WeChat login'),
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
        if (image != null)
          Semantics(
            label: controller.qrChannel == LoginQrChannel.qq
                ? 'QQ sign-in QR code'
                : 'WeChat sign-in QR code',
            image: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.memory(
                    image,
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
        if (controller.supportsDesktopQuickLogin &&
            controller.qrChannel == LoginQrChannel.qq) ...[
          const SizedBox(height: 20),
          _DesktopQuickLoginChoices(controller: controller),
        ],
        const SizedBox(height: 24),
        _announcedAuthenticationMessage(
          context,
          scanned
              ? 'Confirm on your phone'
              : reconnecting
              ? 'Reconnecting…'
              : controller.qrChannel == LoginQrChannel.qq
              ? 'Scan with QQ'
              : 'Scan with WeChat',
          scanned
              ? controller.qrChannel == LoginQrChannel.qq
                    ? 'The code was scanned. Approve the sign-in in QQ.'
                    : 'The code was scanned. Approve the sign-in in WeChat.'
              : reconnecting
              ? 'Your code is still active. We’ll retry the connection.'
              : controller.qrChannel == LoginQrChannel.qq
              ? 'Open QQ, choose Scan, then point your camera here.'
              : 'Open WeChat, choose Scan, then point your camera here.',
          spacing: 8,
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: controller.cancel,
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => controller.startQr(controller.qrChannel),
              child: const Text('New code'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _authenticated(BuildContext context) {
    final saveState = controller.credentialSaveState;
    final (icon, detail) = switch (saveState) {
      CredentialSaveState.saving => (
        Icons.lock_clock_outlined,
        'QQ Music accepted this session. Saving it to platform secure storage…',
      ),
      CredentialSaveState.saved => (
        Icons.lock_rounded,
        'This session is stored securely and ready for this run.',
      ),
      CredentialSaveState.failed => (
        Icons.warning_amber_rounded,
        'You’re signed in for this session, but secure storage was unavailable. '
            'You’ll need to sign in again after restart.',
      ),
      CredentialSaveState.none => (
        Icons.check_rounded,
        'QQ Music accepted this session. Secure storage has not been confirmed.',
      ),
    };

    return Column(
      key: const ValueKey('login-authenticated'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _PanelIcon(icon: icon),
        const SizedBox(height: 24),
        Text(
          'You’re signed in',
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
    final (title, detail) = _terminalCopy(controller.stage, controller.failure);

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
            child: const Text('Try again'),
          ),
        TextButton(
          onPressed: controller.cancel,
          child: const Text('Choose a sign-in method'),
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
    label: '$title. $detail',
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

  (String, String) _terminalCopy(LoginStage stage, LoginFailure? failure) {
    if (stage == LoginStage.expired || stage == LoginStage.timedOut) {
      return (
        'This code expired',
        'Create a fresh code to continue signing in.',
      );
    }
    if (stage == LoginStage.refused) {
      return (
        'Sign-in wasn’t approved',
        'Nothing changed on your account. You can try again.',
      );
    }

    return switch (failure) {
      LoginFailure.serviceUnavailable => (
        'QQ Music is unavailable',
        'The service did not accept this request. Try again in a moment.',
      ),
      LoginFailure.rejected => (
        'Sign-in was rejected',
        'The authorization was not accepted. Choose a method and try again.',
      ),
      LoginFailure.tooManyNetworkFailures => (
        'Connection keeps dropping',
        'Check your network, then create a fresh code.',
      ),
      LoginFailure.invalidResponse => (
        'QQ Music changed its response',
        'This client stopped safely instead of guessing. Try a new code later.',
      ),
      _ => (
        'Couldn’t continue sign-in',
        'Try this session again or create a new code.',
      ),
    };
  }
}

class _DesktopQuickLoginChoices extends StatelessWidget {
  const _DesktopQuickLoginChoices({required this.controller});

  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final stage = controller.desktopQuickStage;
    if (stage == DesktopQuickLoginStage.loading) {
      return const Row(
        key: ValueKey('desktop-quick-login-loading'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Flexible(child: Text('Checking desktop QQ…')),
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
        Text('Quick login', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Select an account already signed in to desktop QQ.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
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
            _desktopQuickFailureCopy(controller.desktopQuickFailure),
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
              ? 'Open and sign in to desktop QQ to use quick login.'
              : failure == null
              ? 'No signed-in desktop QQ account was found.'
              : _desktopQuickFailureCopy(failure),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ],
  );
}

String _desktopQuickFailureCopy(DesktopQuickLoginFailure? failure) =>
    switch (failure) {
      DesktopQuickLoginFailure.clientUnavailable =>
        'Desktop QQ is not available. Open QQ and try again.',
      DesktopQuickLoginFailure.network =>
        'Desktop QQ authorization could not reach QQ Music.',
      DesktopQuickLoginFailure.serviceUnavailable =>
        'QQ authorization is temporarily unavailable.',
      DesktopQuickLoginFailure.rejected =>
        'Desktop QQ did not approve this authorization.',
      DesktopQuickLoginFailure.invalidSelection ||
      DesktopQuickLoginFailure.invalidResponse =>
        'Desktop QQ returned a response this build could not verify.',
      DesktopQuickLoginFailure.cancelled ||
      DesktopQuickLoginFailure.replaced ||
      DesktopQuickLoginFailure.sessionFinished =>
        'This quick-login attempt is no longer active. Retry discovery.',
      DesktopQuickLoginFailure.alreadyRunning =>
        'Desktop QQ authorization is already in progress.',
      DesktopQuickLoginFailure.coreUnavailable =>
        'The music core could not start desktop QQ authorization.',
      null => 'Desktop QQ quick login is unavailable.',
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
