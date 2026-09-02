import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/linux_mpris_audio_service.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initializes the host system media session', (tester) async {
    final binding = await initializeSystemPlaybackBinding();

    expect(binding, isA<AudioServiceSystemPlaybackBinding>());

    final client = DBusClient.session();
    final remote = DBusRemoteObject(
      client,
      name: projectMprisServiceName('dev.axiaobo.flutterustmusic.playback'),
      path: DBusObjectPath(projectMprisObjectPath),
    );
    expect(
      (await remote.getProperty(
        'org.mpris.MediaPlayer2',
        'Identity',
        signature: DBusSignature('s'),
      )).asString(),
      'fura music playback',
    );
    expect(
      (await remote.getProperty(
        projectMprisPlayerInterface,
        'Position',
        signature: DBusSignature('x'),
      )).asInt64(),
      0,
    );
    final playerProperties = await remote.getAllProperties(
      projectMprisPlayerInterface,
    );
    expect(
      playerProperties.keys,
      containsAll(['Position', 'LoopStatus', 'Shuffle', 'CanSeek']),
    );

    await remote.setProperty(
      projectMprisPlayerInterface,
      'LoopStatus',
      const DBusString('Track'),
    );
    await remote.setProperty(
      projectMprisPlayerInterface,
      'Shuffle',
      const DBusBoolean(true),
    );
    expect(
      (await remote.getProperty(
        projectMprisPlayerInterface,
        'LoopStatus',
      )).asString(),
      'Track',
    );
    expect(
      (await remote.getProperty(
        projectMprisPlayerInterface,
        'Shuffle',
      )).asBoolean(),
      isTrue,
    );

    await (binding as AudioServiceSystemPlaybackBinding).dispose();
    await client.close();
  });
}
