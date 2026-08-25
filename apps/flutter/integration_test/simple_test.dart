import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/src/rust/api/library.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('loads typed provider status from Rust', (tester) async {
    final status = bootstrapStatus();

    expect(status.provider.id, 'qq-music');
    expect(status.provider.implementedCapabilities, [
      'Authentication',
      'UserLibrary',
    ]);
    final restore = restoreQqMusicCredentialFromSecureStorage();
    expect(restore.state, QqMusicCredentialRestoreState.signedOut);
    expect(restore.failure, isNull);
    expect(qqMusicHasAuthenticatedCredential(), isFalse);
    final unusedStart = reserveQqMusicWechatQrLoginStart();
    expect(cancelQqMusicWechatQrLoginStart(attemptId: unusedStart), isFalse);
    final unusedLibraryLoad = beginQqMusicUserPlaylistLoad();
    expect(unusedLibraryLoad.isActive, isTrue);
    expect(unusedLibraryLoad.cancel(), isTrue);
    final cancelledLibraryLoad = await unusedLibraryLoad.run();
    expect(
      cancelledLibraryLoad.failure,
      QqMusicUserPlaylistLoadFailure.cancelled,
    );
    final unusedTrackPageLoad = beginQqMusicPlaylistTrackPageLoad(
      providerId: 'qq-music',
      opaquePlaylistId: 'favorite:8001',
      offset: 0,
      size: 100,
    );
    expect(unusedTrackPageLoad.isActive, isTrue);
    expect(unusedTrackPageLoad.cancel(), isTrue);
    final cancelledTrackPageLoad = await unusedTrackPageLoad.run();
    expect(
      cancelledTrackPageLoad.failure,
      QqMusicPlaylistTrackPageLoadFailure.cancelled,
    );

    await tester.pumpWidget(MusicApp(bootstrap: status));
    expect(find.text('QQ Music connected'), findsOneWidget);
  });
}
