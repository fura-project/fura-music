import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authenticated_dependencies.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/authentication/netease_session_continuation.dart';
import 'package:flutterustmusic/authentication/qq_music_media_credential_cleanup.dart';
import 'package:flutterustmusic/authentication/qq_session_continuation.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/daily_recommendation_gateway.dart';
import 'package:flutterustmusic/home/official_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_track_gateway.dart';
import 'package:flutterustmusic/home/recent_listening_gateway.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';
import 'package:flutterustmusic/library/album_favorite_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_creation_gateway.dart';
import 'package:flutterustmusic/library/playlist_deletion_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_track_gateway.dart';
import 'package:flutterustmusic/library/recent_plays_gateway.dart';
import 'package:flutterustmusic/library/track_like_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/media_kit_foreground_audio_engine.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_quality.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';
import 'package:flutterustmusic/startup_diagnostics.dart';
import 'package:media_kit/media_kit.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  logStartupPhase(phase: 'flutter_binding', outcome: 'success');
  installMusicNetworkHttpPolicy();
  logStartupPhase(phase: 'media_kit_global_init', outcome: 'started');
  try {
    MediaKit.ensureInitialized();
    logStartupPhase(phase: 'media_kit_global_init', outcome: 'success');
  } on Object catch (error, stackTrace) {
    logStartupPhase(phase: 'media_kit_global_init', outcome: 'failed');
    Error.throwWithStackTrace(error, stackTrace);
  }
  final settingsStore = AppSettingsStore();
  final settingsLoad = await settingsStore.load();
  logStartupPhase(phase: 'rust_init', outcome: 'started');
  try {
    await RustLib.init();
    logStartupPhase(phase: 'rust_init', outcome: 'success');
  } on Object catch (error, stackTrace) {
    logStartupPhase(phase: 'rust_init', outcome: 'failed');
    Error.throwWithStackTrace(error, stackTrace);
  }
  final bootstrap = bootstrapStatus();

  final qqCredentialVault = SerializedCredentialVault(
    PlatformCredentialVault(),
    stagedVault: PlatformCredentialVault(
      credentialKey: PlatformCredentialVault.qqMusicStagedCredentialKey,
    ),
  );
  final netEaseCredentialVault = SerializedCredentialVault(
    PlatformCredentialVault(
      credentialKey: PlatformCredentialVault.netEaseCredentialKey,
    ),
    stagedVault: PlatformCredentialVault(
      credentialKey: PlatformCredentialVault.netEaseStagedCredentialKey,
    ),
  );
  final qqAuthenticationGateway = RustQqMusicAuthenticationGateway(
    credentialVault: qqCredentialVault,
  );
  final qqSessionContinuation = QqSessionContinuationCoordinator(
    qqCredentialVault,
    recoverStagedCredential:
        qqAuthenticationGateway.recoverStagedCredentialIfPresent,
  );
  final netEaseAuthenticationGateway = RustNeteaseAuthenticationGateway(
    credentialVault: netEaseCredentialVault,
    installationIdentityVault: PlatformCredentialVault(
      credentialKey: PlatformCredentialVault.netEaseInstallationIdentityKey,
    ),
  );
  final netEaseSessionContinuation = NeteaseSessionContinuationCoordinator(
    netEaseCredentialVault,
    recoverStagedCredential:
        netEaseAuthenticationGateway.recoverStagedCredentialIfPresent,
  );
  final rustMediaResolutionGateway = RustMediaResolutionGateway(
    preferredQuality: settingsLoad.settings.playbackQuality.audioPreference,
  );
  final mediaResolutionGateway =
      ProviderCredentialCleaningMediaResolutionGateway(
        rustMediaResolutionGateway,
        credentialVaults: {
          AppMusicProvider.qqMusic.providerId: qqCredentialVault,
          AppMusicProvider.netEaseCloudMusic.providerId: netEaseCredentialVault,
        },
        sessionContinuations: {
          AppMusicProvider.qqMusic.providerId: qqSessionContinuation,
          AppMusicProvider.netEaseCloudMusic.providerId:
              netEaseSessionContinuation,
        },
      );
  final lyricGateway = RustLyricGateway(
    credentialVaults: {
      AppMusicProvider.qqMusic.providerId: qqCredentialVault,
      AppMusicProvider.netEaseCloudMusic.providerId: netEaseCredentialVault,
    },
    sessionContinuations: {
      AppMusicProvider.qqMusic.providerId: qqSessionContinuation,
      AppMusicProvider.netEaseCloudMusic.providerId: netEaseSessionContinuation,
    },
  );
  logStartupPhase(phase: 'audio_engine_construct', outcome: 'started');
  late final ForegroundAudioEngine audioEngine;
  try {
    audioEngine = MediaKitForegroundAudioEngine();
    logStartupPhase(phase: 'audio_engine_construct', outcome: 'success');
  } on Object catch (error, stackTrace) {
    logStartupPhase(phase: 'audio_engine_construct', outcome: 'failed');
    Error.throwWithStackTrace(error, stackTrace);
  }

  logStartupPhase(phase: 'system_edge_init', outcome: 'started');
  late final AppPlaybackHost playbackHost;
  try {
    playbackHost = await initializeAppPlaybackHost(
      playbackQueueGateway: RustPlaybackQueueGateway(),
      mediaResolutionGateway: mediaResolutionGateway,
      lyricGateway: lyricGateway,
      audioEngine: audioEngine,
      relatedTracksGateway: const RustRelatedTracksGateway(),
    );
    logStartupPhase(
      phase: 'system_edge_init',
      outcome: playbackHost.systemControlsAvailable ? 'success' : 'failed',
    );
  } on Object catch (error, stackTrace) {
    logStartupPhase(phase: 'system_edge_init', outcome: 'failed');
    Error.throwWithStackTrace(error, stackTrace);
  }

  // Establish the app-lifetime playback owner before credential verification
  // so navigation and account restoration do not own system media.
  var qqRestore = CredentialRestoreResult.signedOut;
  var netEaseRestore = CredentialRestoreResult.signedOut;
  switch (settingsLoad.settings.musicProvider) {
    case AppMusicProvider.qqMusic:
      qqRestore = await qqAuthenticationGateway.restoreCredential();
      if (qqRestore == CredentialRestoreResult.locallyExpired) {
        final continuation = await qqSessionContinuation.checkpoint();
        if (continuation == QqSessionContinuationResult.continued) {
          qqRestore = CredentialRestoreResult.verificationRequired;
        }
      }
    case AppMusicProvider.netEaseCloudMusic:
      netEaseRestore = await netEaseAuthenticationGateway.restoreCredential();
  }
  final providerDependencies = BuiltInProviderDependencies(
    qqMusic: _buildProviderDependencies(
      provider: AppMusicProvider.qqMusic,
      authenticationGateway: qqAuthenticationGateway,
      credentialVault: qqCredentialVault,
      initialCredentialRestore: qqRestore,
      implementedCapabilities: _implementedCapabilities(
        bootstrap,
        AppMusicProvider.qqMusic.providerId,
      ),
      desktopQuickLoginEnabled: _desktopQuickLoginSupported,
      sessionContinuation: qqSessionContinuation,
    ),
    netEase: _buildProviderDependencies(
      provider: AppMusicProvider.netEaseCloudMusic,
      authenticationGateway: netEaseAuthenticationGateway,
      credentialVault: netEaseCredentialVault,
      initialCredentialRestore: netEaseRestore,
      implementedCapabilities: _implementedCapabilities(
        bootstrap,
        AppMusicProvider.netEaseCloudMusic.providerId,
      ),
      sessionContinuation: netEaseSessionContinuation,
    ),
  );

  logStartupPhase(phase: 'run_app', outcome: 'started');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    logStartupPhase(phase: 'first_frame', outcome: 'success');
  });
  runApp(
    MusicApp(
      bootstrap: bootstrap,
      providerDependencies: providerDependencies,
      mediaResolutionGateway: mediaResolutionGateway,
      lyricGateway: lyricGateway,
      playbackHost: playbackHost,
      initialSettings: settingsLoad.settings,
      settingsStore: settingsStore,
      qqSessionContinuation: qqSessionContinuation,
      neteaseSessionContinuation: netEaseSessionContinuation,
      onPlaybackQualityChanged: (preference) {
        rustMediaResolutionGateway.updatePreferredQuality(
          preference.audioPreference,
        );
      },
    ),
  );
}

bool get _desktopQuickLoginSupported =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS;

MusicProviderDependencies _buildProviderDependencies({
  required AppMusicProvider provider,
  required QqMusicAuthenticationGateway authenticationGateway,
  required CredentialVault credentialVault,
  required CredentialRestoreResult initialCredentialRestore,
  required Iterable<String> implementedCapabilities,
  bool desktopQuickLoginEnabled = false,
  SessionContinuationCoordinator? sessionContinuation,
}) {
  final providerId = provider.providerId;
  final qqMusic = provider == AppMusicProvider.qqMusic;
  final continueSession = sessionContinuation != null
      ? () async {
          await sessionContinuation.continueAfterReadRejection();
        }
      : null;
  final trackSearchGateway = RustTrackSearchGateway(providerId: providerId);
  return MusicProviderDependencies(
    authenticationGateway: authenticationGateway,
    home: AuthenticatedHomeDependencies(
      accountSummaryGateway: RustAccountSummaryGateway(
        providerId: providerId,
        credentialVault: credentialVault,
        sessionContinuation: sessionContinuation,
      ),
      dailyRecommendationGateway: RustDailyRecommendationGateway(
        providerId: providerId,
        credentialVault: credentialVault,
        sessionContinuation: sessionContinuation,
      ),
      officialPlaylistGateway: qqMusic
          ? RustOfficialPlaylistGateway(providerId: providerId)
          : const UnsupportedOfficialPlaylistGateway(),
      personalizedPlaylistsGateway: RustPersonalizedPlaylistsGateway(
        providerId: providerId,
        credentialVault: credentialVault,
        sessionContinuation: sessionContinuation,
      ),
      personalizedTracksGateway: RustPersonalizedTracksGateway(
        providerId: providerId,
        credentialVault: credentialVault,
        sessionContinuation: sessionContinuation,
      ),
      relatedTracksGateway: const RustRelatedTracksGateway(),
      recentListeningFactory: RustRecentListeningGateway.new,
    ),
    library: AuthenticatedLibraryDependencies(
      libraryGateway: RustUserLibraryGateway(
        providerId: providerId,
        credentialVault: credentialVault,
        sessionContinuation: sessionContinuation,
      ),
      playlistDetailGateway: RustPlaylistDetailGateway(
        credentialVault: credentialVault,
        sessionContinuation: sessionContinuation,
      ),
      albumTrackGateway: const RustAlbumTrackGateway(),
      albumDetailsGateway: const RustAlbumDetailsGateway(),
      artistTrackGateway: const RustArtistTrackGateway(),
      artistAlbumGateway: const RustArtistAlbumGateway(),
      favoriteAlbumGateway: RustFavoriteAlbumGateway(
        providerId: providerId,
        credentialVault: credentialVault,
        sessionContinuation: sessionContinuation,
      ),
      favoriteArtistGateway: RustFavoriteArtistGateway(
        providerId: providerId,
        credentialVault: credentialVault,
        sessionContinuation: sessionContinuation,
      ),
      recentPlaysGateway: RustRecentPlaysGateway(
        providerId: providerId,
        credentialVault: credentialVault,
        sessionContinuation: sessionContinuation,
      ),
      trackLikeGateway: RustTrackLikeGateway(
        credentialVault: qqMusic ? credentialVault : null,
        netEaseCredentialVault: qqMusic ? null : credentialVault,
        qqSessionContinuation: qqMusic ? continueSession : null,
        neteaseSessionContinuation: qqMusic ? null : continueSession,
      ),
      albumFavoriteGateway: qqMusic
          ? RustAlbumFavoriteGateway(
              credentialVault: credentialVault,
              qqSessionContinuation: continueSession,
            )
          : null,
      playlistTrackGateway: RustPlaylistTrackGateway(
        credentialVault: credentialVault,
        sessionContinuation: continueSession,
      ),
      playlistCreationGateway: RustPlaylistCreationGateway(
        providerId: providerId,
        credentialVault: credentialVault,
        sessionContinuation: continueSession,
      ),
      playlistDeletionGateway: qqMusic
          ? RustPlaylistDeletionGateway(
              credentialVault: credentialVault,
              sessionContinuation: continueSession,
            )
          : null,
    ),
    discovery: AuthenticatedDiscoveryDependencies(
      trackSearchGateway: trackSearchGateway,
      trackSuggestionGateway: trackSearchGateway,
      artistSearchGateway: RustArtistSearchGateway(providerId: providerId),
      albumSearchGateway: RustAlbumSearchGateway(providerId: providerId),
      playlistSearchGateway: RustPlaylistSearchGateway(providerId: providerId),
      recommendedPlaylistGateway: RustRecommendedPlaylistGateway(
        providerId: providerId,
      ),
      newAlbumGateway: RustNewAlbumGateway(providerId: providerId),
      newSongGateway: RustNewSongGateway(providerId: providerId),
      rankingGateway: RustRankingGateway(providerId: providerId),
      radarGateway: qqMusic
          ? RustRadarGateway(
              credentialVault: credentialVault,
              sessionContinuation: sessionContinuation,
            )
          : const UnsupportedRadarGateway(),
    ),
    capabilities:
        (qqMusic
                ? MusicProviderCapabilities.qqMusic
                : MusicProviderCapabilities.netEaseCloudMusic)
            .constrainedByCore(implementedCapabilities),
    initialCredentialRestore: initialCredentialRestore,
    desktopQuickLoginEnabled: desktopQuickLoginEnabled,
  );
}

Iterable<String> _implementedCapabilities(
  BootstrapStatus bootstrap,
  String providerId,
) sync* {
  for (final provider in bootstrap.providers) {
    if (provider.id == providerId) {
      yield* provider.implementedCapabilities;
      return;
    }
  }
}
