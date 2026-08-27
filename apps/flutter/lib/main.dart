import 'package:flutter/material.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
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
  final mediaResolutionGateway = RustMediaResolutionGateway(
    credentialVault: credentialVault,
  );
  final lyricGateway = RustLyricGateway(credentialVault: credentialVault);
  final settingsLoad = await AppSettingsStore().load();
  final credentialRestore = await authenticationGateway.restoreCredential();

  runApp(
    MusicApp(
      bootstrap: bootstrapStatus(),
      authenticationGateway: authenticationGateway,
      libraryGateway: libraryGateway,
      playlistDetailGateway: playlistDetailGateway,
      mediaResolutionGateway: mediaResolutionGateway,
      lyricGateway: lyricGateway,
      initialSettings: settingsLoad.settings,
      initialCredentialRestore: credentialRestore,
    ),
  );
}
