import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/authentication/qq_music_media_credential_cleanup.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';
import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await RustLib.init();

  final credentialVault = SerializedCredentialVault(PlatformCredentialVault());
  final authenticationGateway = RustQqMusicAuthenticationGateway(
    credentialVault: credentialVault,
  );
  final libraryGateway = RustUserLibraryGateway(
    credentialVault: credentialVault,
  );
  final playlistDetailGateway = RustPlaylistDetailGateway(
    credentialVault: credentialVault,
  );
  final settingsStore = AppSettingsStore();
  final settingsLoad = await settingsStore.load();
  final rustMediaResolutionGateway = RustMediaResolutionGateway(
    preferredQuality: switch (settingsLoad.settings.playbackQuality) {
      AppPlaybackQualityPreference.standard =>
        PlaybackAudioQualityPreference.standard,
      AppPlaybackQualityPreference.high => PlaybackAudioQualityPreference.high,
    },
  );
  final mediaResolutionGateway =
      QqMusicCredentialCleaningMediaResolutionGateway(
        rustMediaResolutionGateway,
        credentialVault: credentialVault,
      );
  final lyricGateway = RustLyricGateway(credentialVault: credentialVault);
  final credentialRestore = await authenticationGateway.restoreCredential();
  final systemPlaybackBinding = await initializeSystemPlaybackBinding();

  runApp(
    MusicApp(
      bootstrap: bootstrapStatus(),
      authenticationGateway: authenticationGateway,
      desktopQuickLoginEnabled:
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS,
      libraryGateway: libraryGateway,
      playlistDetailGateway: playlistDetailGateway,
      mediaResolutionGateway: mediaResolutionGateway,
      lyricGateway: lyricGateway,
      systemPlaybackBinding: systemPlaybackBinding,
      initialSettings: settingsLoad.settings,
      settingsStore: settingsStore,
      onPlaybackQualityChanged: (preference) {
        rustMediaResolutionGateway.updatePreferredQuality(switch (preference) {
          AppPlaybackQualityPreference.standard =>
            PlaybackAudioQualityPreference.standard,
          AppPlaybackQualityPreference.high =>
            PlaybackAudioQualityPreference.high,
        });
      },
      initialCredentialRestore: credentialRestore,
    ),
  );
}
