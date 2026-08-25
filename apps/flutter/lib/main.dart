import 'package:flutter/material.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  final credentialVault = SerializedCredentialVault(PlatformCredentialVault());
  final authenticationGateway = RustQqMusicAuthenticationGateway(
    credentialVault: credentialVault,
  );
  final libraryGateway = RustUserLibraryGateway(
    credentialVault: credentialVault,
  );
  final credentialRestore = await authenticationGateway.restoreCredential();

  runApp(
    MusicApp(
      bootstrap: bootstrapStatus(),
      authenticationGateway: authenticationGateway,
      libraryGateway: libraryGateway,
      initialCredentialRestore: credentialRestore,
    ),
  );
}
