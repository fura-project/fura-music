import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_controller.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/user_library_page.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';

const _qqGreen = Color(0xFF24B86A);

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
    ArtistTrackGateway? artistTrackGateway,
    ArtistAlbumGateway? artistAlbumGateway,
    RecommendedPlaylistGateway? recommendedPlaylistGateway,
    RankingGateway? rankingGateway,
    ForegroundAudioEngine? audioEngine,
    CredentialRestoreResult initialCredentialRestore =
        CredentialRestoreResult.signedOut,
    Key? key,
  }) {
    if (authenticationGateway == null ||
        libraryGateway == null ||
        playlistDetailGateway == null ||
        mediaResolutionGateway == null ||
        lyricGateway == null) {
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
      mediaResolutionGateway ??= RustMediaResolutionGateway(
        credentialVault: fallbackCredentialVault,
      );
      lyricGateway ??= RustLyricGateway(
        credentialVault: fallbackCredentialVault,
      );
    }
    return MusicApp._(
      bootstrap: bootstrap,
      authenticationGateway: authenticationGateway,
      libraryGateway: libraryGateway,
      playlistDetailGateway: playlistDetailGateway,
      mediaResolutionGateway: mediaResolutionGateway,
      lyricGateway: lyricGateway,
      playbackQueueGateway: playbackQueueGateway ?? RustPlaybackQueueGateway(),
      searchGateway: searchGateway ?? const RustTrackSearchGateway(),
      artistSearchGateway:
          artistSearchGateway ?? const RustArtistSearchGateway(),
      albumSearchGateway: albumSearchGateway ?? const RustAlbumSearchGateway(),
      playlistSearchGateway:
          playlistSearchGateway ?? const RustPlaylistSearchGateway(),
      albumTrackGateway: albumTrackGateway ?? const RustAlbumTrackGateway(),
      artistTrackGateway: artistTrackGateway ?? const RustArtistTrackGateway(),
      artistAlbumGateway: artistAlbumGateway ?? const RustArtistAlbumGateway(),
      recommendedPlaylistGateway:
          recommendedPlaylistGateway ?? const RustRecommendedPlaylistGateway(),
      rankingGateway: rankingGateway ?? const RustRankingGateway(),
      audioEngine: audioEngine ?? AudioplayersForegroundAudioEngine(),
      initialCredentialRestore: initialCredentialRestore,
      key: key,
    );
  }

  const MusicApp._({
    required this.bootstrap,
    required this.authenticationGateway,
    required this.libraryGateway,
    required this.playlistDetailGateway,
    required this.mediaResolutionGateway,
    required this.lyricGateway,
    required this.playbackQueueGateway,
    required this.searchGateway,
    required this.artistSearchGateway,
    required this.albumSearchGateway,
    required this.playlistSearchGateway,
    required this.albumTrackGateway,
    required this.artistTrackGateway,
    required this.artistAlbumGateway,
    required this.recommendedPlaylistGateway,
    required this.rankingGateway,
    required this.audioEngine,
    required this.initialCredentialRestore,
    super.key,
  });

  final BootstrapStatus bootstrap;
  final QqMusicAuthenticationGateway authenticationGateway;
  final UserLibraryGateway libraryGateway;
  final PlaylistDetailGateway playlistDetailGateway;
  final MediaResolutionGateway mediaResolutionGateway;
  final LyricGateway lyricGateway;
  final PlaybackQueueGateway playbackQueueGateway;
  final TrackSearchGateway searchGateway;
  final ArtistSearchGateway artistSearchGateway;
  final AlbumSearchGateway albumSearchGateway;
  final PlaylistSearchGateway playlistSearchGateway;
  final AlbumTrackGateway albumTrackGateway;
  final ArtistTrackGateway artistTrackGateway;
  final ArtistAlbumGateway artistAlbumGateway;
  final RecommendedPlaylistGateway recommendedPlaylistGateway;
  final RankingGateway rankingGateway;
  final ForegroundAudioEngine audioEngine;
  final CredentialRestoreResult initialCredentialRestore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutterust Music',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: LoginPage(
        bootstrap: bootstrap,
        authenticationGateway: authenticationGateway,
        libraryGateway: libraryGateway,
        playlistDetailGateway: playlistDetailGateway,
        mediaResolutionGateway: mediaResolutionGateway,
        lyricGateway: lyricGateway,
        playbackQueueGateway: playbackQueueGateway,
        searchGateway: searchGateway,
        artistSearchGateway: artistSearchGateway,
        albumSearchGateway: albumSearchGateway,
        playlistSearchGateway: playlistSearchGateway,
        albumTrackGateway: albumTrackGateway,
        artistTrackGateway: artistTrackGateway,
        artistAlbumGateway: artistAlbumGateway,
        recommendedPlaylistGateway: recommendedPlaylistGateway,
        rankingGateway: rankingGateway,
        audioEngine: audioEngine,
        initialCredentialRestore: initialCredentialRestore,
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _qqGreen,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.bootstrap,
    required this.authenticationGateway,
    required this.libraryGateway,
    required this.playlistDetailGateway,
    required this.mediaResolutionGateway,
    required this.lyricGateway,
    required this.playbackQueueGateway,
    required this.searchGateway,
    required this.artistSearchGateway,
    required this.albumSearchGateway,
    required this.playlistSearchGateway,
    required this.albumTrackGateway,
    required this.artistTrackGateway,
    required this.artistAlbumGateway,
    required this.recommendedPlaylistGateway,
    required this.rankingGateway,
    required this.audioEngine,
    required this.initialCredentialRestore,
    super.key,
  });

  final BootstrapStatus bootstrap;
  final QqMusicAuthenticationGateway authenticationGateway;
  final UserLibraryGateway libraryGateway;
  final PlaylistDetailGateway playlistDetailGateway;
  final MediaResolutionGateway mediaResolutionGateway;
  final LyricGateway lyricGateway;
  final PlaybackQueueGateway playbackQueueGateway;
  final TrackSearchGateway searchGateway;
  final ArtistSearchGateway artistSearchGateway;
  final AlbumSearchGateway albumSearchGateway;
  final PlaylistSearchGateway playlistSearchGateway;
  final AlbumTrackGateway albumTrackGateway;
  final ArtistTrackGateway artistTrackGateway;
  final ArtistAlbumGateway artistAlbumGateway;
  final RecommendedPlaylistGateway recommendedPlaylistGateway;
  final RankingGateway rankingGateway;
  final ForegroundAudioEngine audioEngine;
  final CredentialRestoreResult initialCredentialRestore;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final LoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LoginController(
      widget.authenticationGateway,
      initialCredentialRestore: widget.initialCredentialRestore,
    );
    if (widget.initialCredentialRestore ==
        CredentialRestoreResult.verificationRequired) {
      unawaited(_controller.verifyRestoredCredential());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.stage == LoginStage.authenticated) {
          return UserLibraryPage(
            key: const ValueKey('user-library-page'),
            gateway: widget.libraryGateway,
            detailGateway: widget.playlistDetailGateway,
            mediaResolutionGateway: widget.mediaResolutionGateway,
            lyricGateway: widget.lyricGateway,
            playbackQueueGateway: widget.playbackQueueGateway,
            searchGateway: widget.searchGateway,
            artistSearchGateway: widget.artistSearchGateway,
            albumSearchGateway: widget.albumSearchGateway,
            playlistSearchGateway: widget.playlistSearchGateway,
            albumTrackGateway: widget.albumTrackGateway,
            artistTrackGateway: widget.artistTrackGateway,
            artistAlbumGateway: widget.artistAlbumGateway,
            recommendedPlaylistGateway: widget.recommendedPlaylistGateway,
            rankingGateway: widget.rankingGateway,
            audioEngine: widget.audioEngine,
            onSignInAgain: _controller.cancel,
            onSignOut: _controller.signOut,
          );
        }
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 860;
                final content = wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _ProductIntro(bootstrap: widget.bootstrap),
                          ),
                          const SizedBox(width: 64),
                          SizedBox(
                            width: 400,
                            child: _AuthenticationPanel(
                              controller: _controller,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ProductIntro(
                            bootstrap: widget.bootstrap,
                            compact: true,
                          ),
                          const SizedBox(height: 36),
                          _AuthenticationPanel(controller: _controller),
                        ],
                      );

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 56 : 24,
                    vertical: wide ? 48 : 28,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: content,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ProductIntro extends StatelessWidget {
  const _ProductIntro({required this.bootstrap, this.compact = false});

  final BootstrapStatus bootstrap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = bootstrap.provider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusLabel(providerName: provider.displayName),
        SizedBox(height: compact ? 24 : 36),
        Text(
          'Your QQ Music library,\nwithout the browser frame.',
          style:
              (compact
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.displayMedium)
                  ?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.04,
                    letterSpacing: -1.4,
                  ),
        ),
        const SizedBox(height: 20),
        Text(
          'A focused, open client with a native Rust core and a modern '
          'adaptive Flutter experience.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _BuildFact(
              icon: Icons.hub_outlined,
              label: 'Provider',
              value: provider.id,
            ),
            _BuildFact(
              icon: Icons.memory_outlined,
              label: 'Rust core',
              value: bootstrap.coreVersion,
            ),
          ],
        ),
      ],
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
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
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
    if (stage == LoginStage.idle) return _idle(context);
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
        'Use WeChat to scan a short-lived code. Account keys stay inside the Rust core.',
        style: _supportingStyle(context),
      ),
      const SizedBox(height: 28),
      FilledButton.icon(
        key: const ValueKey('start-login-button'),
        onPressed: controller.start,
        icon: const Icon(Icons.login_rounded),
        label: const Text('Continue with WeChat'),
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
        'Connecting directly to WeChat and QQ Music.',
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
          onPressed: controller.start,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('Use a new code'),
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
            label: 'WeChat sign-in QR code',
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
              : 'Scan with WeChat',
          scanned
              ? 'The code was scanned. Approve the sign-in in WeChat.'
              : reconnecting
              ? 'Your code is still active. We’ll retry the connection.'
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
              onPressed: controller.start,
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
          onPressed: controller.start,
          child: const Text('Get a new code'),
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
        'Create a new code and approve it again in WeChat.',
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
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: colors.onPrimaryContainer, size: 30),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.providerName});

  final String providerName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              '$providerName connected',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: colors.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildFact extends StatelessWidget {
  const _BuildFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
