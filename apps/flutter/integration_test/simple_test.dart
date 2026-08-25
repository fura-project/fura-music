import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('loads typed provider status from Rust', (tester) async {
    final status = bootstrapStatus();

    expect(status.provider.id, 'qq-music');
    expect(status.provider.implementedCapabilities, ['Authentication']);
    expect(qqMusicHasAuthenticatedCredential(), isFalse);
    final unusedStart = reserveQqMusicWechatQrLoginStart();
    expect(cancelQqMusicWechatQrLoginStart(attemptId: unusedStart), isFalse);

    await tester.pumpWidget(MusicApp(bootstrap: status));
    expect(find.text('QQ Music connected'), findsOneWidget);
  });
}
