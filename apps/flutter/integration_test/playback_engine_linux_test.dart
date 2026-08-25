import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plays and disposes a generated local source', (_) async {
    final fixtureDirectory = await Directory.systemTemp.createTemp(
      'flutterustmusic-playback-',
    );
    final fixture = File('${fixtureDirectory.path}/probe.mp3');
    final player = AudioPlayer();

    try {
      await fixture.writeAsBytes(base64Decode(_silentMp3Base64), flush: true);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(0);
      await player.setSourceDeviceFile(fixture.path, mimeType: 'audio/mpeg');

      await player.resume();
      expect(player.state, PlayerState.playing);
      await player.pause();
      expect(player.state, PlayerState.paused);
      await player.resume();
      expect(player.state, PlayerState.playing);
      await player.stop();
      expect(player.state, PlayerState.stopped);
    } finally {
      await player.dispose();
      await fixtureDirectory.delete(recursive: true);
    }
  });
}

// 0.5 seconds of silent 8 kHz mono MP3 generated with FFmpeg 9.0. It lives in
// test code so no playback fixture is shipped in the application bundle.
const _silentMp3Base64 =
    'SUQzBAAAAAAAIlRTU0UAAAAOAAADTGF2ZjYzLjEuMTAwAAAAAAAAAAAAAAD/4zjAAAAAAAAAAAAASW5mbwAAAA8AAAAJAAADYABVVVVVVVVVVVVVVWpqampqampqampqgICAgICAgICAgICVlZWVlZWVlZWVlaqqqqqqqqqqqqqqwMDAwMDAwMDAwMDV1dXV1dXV1dXV1erq6urq6urq6urq//////////////8AAAAATGF2YzYzLjEuAAAAAAAAAAAAAAAAJAJgAAAAAAAAA2C8msofAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/4xjEAAAAA0gAAAAATEFNRTQuMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjEOwAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjEdgAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjEsQAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVU=';
