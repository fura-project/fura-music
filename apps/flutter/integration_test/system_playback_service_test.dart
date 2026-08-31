import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initializes the host system media session', (tester) async {
    final binding = await initializeSystemPlaybackBinding();

    expect(binding, isA<AudioServiceSystemPlaybackBinding>());

    await (binding as AudioServiceSystemPlaybackBinding).dispose();
  });
}
