import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';

void main() {
  testWidgets('renders truthful bootstrap state', (tester) async {
    const bootstrap = BootstrapStatus(
      coreVersion: '0.1.0-test',
      provider: ProviderStatus(
        id: 'qq-music',
        displayName: 'QQ Music',
        implementedCapabilities: [],
      ),
    );

    await tester.pumpWidget(const MusicApp(bootstrap: bootstrap));

    expect(find.text('QQ Music core connected'), findsOneWidget);
    expect(find.text('qq-music'), findsOneWidget);
    expect(find.text('0.1.0-test'), findsOneWidget);
    expect(
      find.textContaining('no account capability is exposed'),
      findsOneWidget,
    );
  });
}
