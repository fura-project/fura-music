import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class MusicApp extends StatelessWidget {
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
    SystemPlaybackBinding systemPlaybackBinding =
        const NoopSystemPlaybackBinding(),
    AppSettings initialSettings = AppSettings.defaults,
    CredentialRestoreResult initialCredentialRestore =
        CredentialRestoreResult.signedOut,
    Key? key,
  }) {
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
      mediaResolutionGateway ??=
          QqMusicCredentialCleaningMediaResolutionGateway(
            RustMediaResolutionGateway(
              preferredQuality: switch (initialSettings.playbackQuality) {
                AppPlaybackQualityPreference.standard =>
                  PlaybackAudioQualityPreference.standard,
                AppPlaybackQualityPreference.high =>
                  PlaybackAudioQualityPreference.high,
              },
            ),
            credentialVault: fallbackCredentialVault,
          );
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
      initialSettings: initialSettings,
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
    required this.initialSettings,
    required this.initialCredentialRestore,
    super.key,
  });

  final BootstrapStatus bootstrap;
  final QqMusicAuthenticationGateway authenticationGateway;
  final AuthenticatedHomeDependencies homeDependencies;
  final AuthenticatedLibraryDependencies libraryDependencies;
  final AuthenticatedDiscoveryDependencies discoveryDependencies;
  final AuthenticatedPlaybackDependencies playbackDependencies;
  final AppSettings initialSettings;
  final CredentialRestoreResult initialCredentialRestore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutterust Music',
      theme: MusicMaterialTheme.light(),
      darkTheme: MusicMaterialTheme.dark(),
      themeMode: initialSettings.theme.materialThemeMode,
      home: LoginPage(
        bootstrap: bootstrap,
        authenticationGateway: authenticationGateway,
        homeDependencies: homeDependencies,
        libraryDependencies: libraryDependencies,
        discoveryDependencies: discoveryDependencies,
        playbackDependencies: playbackDependencies,
        initialCredentialRestore: initialCredentialRestore,
      ),
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
    required this.initialCredentialRestore,
    super.key,
  });

  final BootstrapStatus bootstrap;
  final QqMusicAuthenticationGateway authenticationGateway;
  final AuthenticatedHomeDependencies homeDependencies;
  final AuthenticatedLibraryDependencies libraryDependencies;
  final AuthenticatedDiscoveryDependencies discoveryDependencies;
  final AuthenticatedPlaybackDependencies playbackDependencies;
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
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 720),
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

class _AuthenticationPanel extends StatefulWidget {
  const _AuthenticationPanel({required this.controller});

  final LoginController controller;

  @override
  State<_AuthenticationPanel> createState() => _AuthenticationPanelState();
}

class _AuthenticationPanelState extends State<_AuthenticationPanel> {
  final TextEditingController _countryCodeController = TextEditingController(
    text: '86',
  );
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _verificationCodeController =
      TextEditingController();
  bool _showPhoneForm = false;

  @override
  void dispose() {
    _countryCodeController.dispose();
    _phoneController.dispose();
    _verificationCodeController.dispose();
    super.dispose();
  }

  void _showPhone() => setState(() => _showPhoneForm = true);

  void _hidePhone() => setState(() => _showPhoneForm = false);

  void _sendPhoneCode() {
    widget.controller.sendPhoneCode(
      countryCode: _countryCodeController.text,
      phoneNumber: _phoneController.text,
    );
  }

  void _authorizePhone() {
    widget.controller.authorizePhone(_verificationCodeController.text);
  }

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
          animation: widget.controller,
          builder: (context, _) => AnimatedSwitcher(
            duration: MusicMotion.stateChange,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _AuthenticationContent(
              key: ValueKey((widget.controller.stage, _showPhoneForm)),
              controller: widget.controller,
              showPhoneForm: _showPhoneForm,
              countryCodeController: _countryCodeController,
              phoneController: _phoneController,
              verificationCodeController: _verificationCodeController,
              onShowPhone: _showPhone,
              onHidePhone: _hidePhone,
              onSendPhoneCode: _sendPhoneCode,
              onAuthorizePhone: _authorizePhone,
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthenticationContent extends StatelessWidget {
  const _AuthenticationContent({
    required this.controller,
    required this.showPhoneForm,
    required this.countryCodeController,
    required this.phoneController,
    required this.verificationCodeController,
    required this.onShowPhone,
    required this.onHidePhone,
    required this.onSendPhoneCode,
    required this.onAuthorizePhone,
    super.key,
  });

  final LoginController controller;
  final bool showPhoneForm;
  final TextEditingController countryCodeController;
  final TextEditingController phoneController;
  final TextEditingController verificationCodeController;
  final VoidCallback onShowPhone;
  final VoidCallback onHidePhone;
  final VoidCallback onSendPhoneCode;
  final VoidCallback onAuthorizePhone;

  @override
  Widget build(BuildContext context) {
    final stage = controller.stage;
    if (stage == LoginStage.idle) {
      return showPhoneForm ? _phoneEntry(context) : _idle(context);
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
    if (stage == LoginStage.sendingPhoneCode ||
        stage == LoginStage.phoneCodeSent ||
        stage == LoginStage.phoneCaptchaRequired ||
        stage == LoginStage.phoneRateLimited ||
        stage == LoginStage.authorizingPhone) {
      return _phoneAuthorization(context);
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
      const _PanelIcon(icon: Icons.qr_code_2_rounded),
      const SizedBox(height: 24),
      Text(
        'Sign in to QQ Music',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Text(
        'Authorize with QQ or WeChat QR. An experimental one-time SMS option is also available; passwords are never collected.',
        style: _supportingStyle(context),
      ),
      const SizedBox(height: 28),
      FilledButton.icon(
        key: const ValueKey('start-qq-login-button'),
        onPressed: () => controller.startQr(LoginQrChannel.qq),
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
      TextButton.icon(
        key: const ValueKey('show-phone-login-button'),
        onPressed: onShowPhone,
        icon: const Icon(Icons.sms_outlined),
        label: const Text('Use phone and SMS code (experimental)'),
      ),
    ],
  );

  Widget _phoneEntry(BuildContext context) => AutofillGroup(
    child: Column(
      key: const ValueKey('phone-login-entry'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PanelIcon(icon: Icons.sms_outlined),
        const SizedBox(height: 20),
        Text(
          'Sign in with a one-time code',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'This experimental option uses QQ Music\'s private client protocol and has not yet passed a real-account login check. This app never asks for or stores your QQ password.',
          style: _supportingStyle(context),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: TextField(
                key: const ValueKey('phone-country-code-field'),
                controller: countryCodeController,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Country',
                  prefixText: '+',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('phone-number-field'),
                controller: phoneController,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Phone number'),
                onSubmitted: (_) => onSendPhoneCode(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('send-phone-code-button'),
          onPressed: onSendPhoneCode,
          icon: const Icon(Icons.send_rounded),
          label: const Text('Send code'),
        ),
        TextButton(onPressed: onHidePhone, child: const Text('Other methods')),
      ],
    ),
  );

  Widget _phoneAuthorization(BuildContext context) {
    final stage = controller.stage;
    if (stage == LoginStage.sendingPhoneCode ||
        stage == LoginStage.authorizingPhone) {
      return Column(
        key: const ValueKey('phone-login-progress'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 42,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 20),
          Text(
            stage == LoginStage.sendingPhoneCode
                ? 'Requesting your code…'
                : 'Authorizing with QQ Music…',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: controller.cancel,
            child: const Text('Cancel'),
          ),
        ],
      );
    }
    if (stage == LoginStage.phoneCaptchaRequired ||
        stage == LoginStage.phoneRateLimited) {
      final captcha = stage == LoginStage.phoneCaptchaRequired;
      final url = controller.phoneSecurityUrl;
      return Column(
        key: const ValueKey('phone-login-blocked'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _PanelIcon(
            icon: captcha
                ? Icons.verified_user_outlined
                : Icons.hourglass_top_rounded,
          ),
          const SizedBox(height: 20),
          _announcedAuthenticationMessage(
            context,
            captcha ? 'Verification required' : 'Too many requests',
            captcha
                ? 'QQ Music requires a security check before another SMS can be sent.'
                : 'QQ Music has temporarily limited SMS requests. Try again later.',
          ),
          if (captcha && url != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              url,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          TextButton(
            onPressed: () {
              controller.cancel();
              onHidePhone();
            },
            child: const Text('Choose another method'),
          ),
        ],
      );
    }

    return Column(
      key: const ValueKey('phone-code-entry'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PanelIcon(icon: Icons.mark_email_read_outlined),
        const SizedBox(height: 20),
        Text(
          'Enter the SMS code',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Use the six-digit code sent by QQ Music.',
          style: _supportingStyle(context),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('phone-verification-code-field'),
          controller: verificationCodeController,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: const InputDecoration(labelText: 'Verification code'),
          onSubmitted: (_) => onAuthorizePhone(),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('authorize-phone-button'),
          onPressed: onAuthorizePhone,
          icon: const Icon(Icons.login_rounded),
          label: const Text('Authorize'),
        ),
        TextButton(
          onPressed: () {
            controller.cancel();
            onHidePhone();
          },
          child: const Text('Choose another method'),
        ),
      ],
    );
  }

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
