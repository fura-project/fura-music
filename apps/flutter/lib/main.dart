import 'dart:developer' as developer;

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
import 'package:flutterustmusic/authentication/qq_music_media_credential_cleanup.dart';
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
import 'package:flutterustmusic/playback/playback_stack_experiment.dart';
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

  final playbackStack = PlaybackStackSelection.current();
  logPlaybackStackSelected(
    selection: playbackStack,
    platform: defaultTargetPlatform,
  );

  final qqCredentialVault = SerializedCredentialVault(
    PlatformCredentialVault(),
  );
  final netEaseCredentialVault = SerializedCredentialVault(
    PlatformCredentialVault(
      credentialKey: PlatformCredentialVault.netEaseCredentialKey,
    ),
  );
  final qqAuthenticationGateway = RustQqMusicAuthenticationGateway(
    credentialVault: qqCredentialVault,
  );
  final netEaseAuthenticationGateway = RustNeteaseAuthenticationGateway(
    credentialVault: netEaseCredentialVault,
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
      );
  final lyricGateway = RustLyricGateway(
    credentialVaults: {
      AppMusicProvider.qqMusic.providerId: qqCredentialVault,
      AppMusicProvider.netEaseCloudMusic.providerId: netEaseCredentialVault,
    },
  );
  logStartupPhase(phase: 'audio_engine_construct', outcome: 'started');
  late final ForegroundAudioEngine audioEngine;
  try {
    audioEngine = switch (playbackStack.effectiveAudioEngine) {
      MusicAudioEngineKind.audioplayers => AudioplayersForegroundAudioEngine(),
      MusicAudioEngineKind.mediaKit => MediaKitForegroundAudioEngine(),
    };
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
      systemMediaEdge: playbackStack.effectiveSystemMediaEdge,
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
  developer.log(
    'FURA_DIAGNOSTIC playback_stack '
    '${playbackStack.diagnosticLine(platform: defaultTargetPlatform, systemControlsAvailable: playbackHost.systemControlsAvailable)}',
    name: 'fura_music.playback',
  );

  // Keep the selected system-media edge initialization ahead of account
  // restoration. Android can launch the shared Flutter engine from a media
  // control while no Activity is attached, so the app-lifetime playback owner
  // must exist before any potentially slow credential verification.
  var qqRestore = CredentialRestoreResult.signedOut;
  var netEaseRestore = CredentialRestoreResult.signedOut;
  switch (settingsLoad.settings.musicProvider) {
    case AppMusicProvider.qqMusic:
      qqRestore = await qqAuthenticationGateway.restoreCredential();
    case AppMusicProvider.netEaseCloudMusic:
      netEaseRestore = await netEaseAuthenticationGateway.restoreCredential();
  }
  final providerDependencies = BuiltInProviderDependencies(
    qqMusic: _buildProviderDependencies(
      provider: AppMusicProvider.qqMusic,
      authenticationGateway: qqAuthenticationGateway,
      credentialVault: qqCredentialVault,
      initialCredentialRestore: qqRestore,
      desktopQuickLoginEnabled: _desktopQuickLoginSupported,
    ),
    netEase: _buildProviderDependencies(
      provider: AppMusicProvider.netEaseCloudMusic,
      authenticationGateway: netEaseAuthenticationGateway,
      credentialVault: netEaseCredentialVault,
      initialCredentialRestore: netEaseRestore,
    ),
  );

  logStartupPhase(phase: 'run_app', outcome: 'started');
  runApp(
    MusicApp(
      bootstrap: bootstrapStatus(),
      providerDependencies: providerDependencies,
      mediaResolutionGateway: mediaResolutionGateway,
      lyricGateway: lyricGateway,
      playbackHost: playbackHost,
      initialSettings: settingsLoad.settings,
      settingsStore: settingsStore,
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
  bool desktopQuickLoginEnabled = false,
}) {
  final providerId = provider.providerId;
  final qqMusic = provider == AppMusicProvider.qqMusic;
  final trackSearchGateway = RustTrackSearchGateway(providerId: providerId);
  return MusicProviderDependencies(
    authenticationGateway: authenticationGateway,
    home: AuthenticatedHomeDependencies(
      accountSummaryGateway: RustAccountSummaryGateway(
        providerId: providerId,
        credentialVault: credentialVault,
      ),
      dailyRecommendationGateway: RustDailyRecommendationGateway(
        providerId: providerId,
        credentialVault: credentialVault,
      ),
      officialPlaylistGateway: qqMusic
          ? RustOfficialPlaylistGateway(providerId: providerId)
          : const UnsupportedOfficialPlaylistGateway(),
      personalizedPlaylistsGateway: RustPersonalizedPlaylistsGateway(
        providerId: providerId,
        credentialVault: credentialVault,
      ),
      personalizedTracksGateway: RustPersonalizedTracksGateway(
        providerId: providerId,
        credentialVault: credentialVault,
      ),
      relatedTracksGateway: const RustRelatedTracksGateway(),
      recentListeningFactory: RustRecentListeningGateway.new,
    ),
    library: AuthenticatedLibraryDependencies(
      libraryGateway: RustUserLibraryGateway(
        providerId: providerId,
        credentialVault: credentialVault,
      ),
      playlistDetailGateway: RustPlaylistDetailGateway(
        credentialVault: credentialVault,
      ),
      albumTrackGateway: const RustAlbumTrackGateway(),
      albumDetailsGateway: const RustAlbumDetailsGateway(),
      artistTrackGateway: const RustArtistTrackGateway(),
      artistAlbumGateway: const RustArtistAlbumGateway(),
      favoriteAlbumGateway: RustFavoriteAlbumGateway(
        providerId: providerId,
        credentialVault: credentialVault,
      ),
      favoriteArtistGateway: RustFavoriteArtistGateway(
        providerId: providerId,
        credentialVault: credentialVault,
      ),
      recentPlaysGateway: RustRecentPlaysGateway(
        providerId: providerId,
        credentialVault: credentialVault,
      ),
      trackLikeGateway: RustTrackLikeGateway(credentialVault: credentialVault),
      albumFavoriteGateway: qqMusic
          ? RustAlbumFavoriteGateway(credentialVault: credentialVault)
          : null,
      playlistTrackGateway: RustPlaylistTrackGateway(
        credentialVault: credentialVault,
      ),
      playlistCreationGateway: RustPlaylistCreationGateway(
        providerId: providerId,
        credentialVault: credentialVault,
      ),
      playlistDeletionGateway: qqMusic
          ? RustPlaylistDeletionGateway(credentialVault: credentialVault)
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
          ? RustRadarGateway(credentialVault: credentialVault)
          : const UnsupportedRadarGateway(),
    ),
    capabilities: qqMusic
        ? MusicProviderCapabilities.qqMusic
        : MusicProviderCapabilities.netEaseCloudMusic,
    initialCredentialRestore: initialCredentialRestore,
    desktopQuickLoginEnabled: desktopQuickLoginEnabled,
  );
}
