import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
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

  testWidgets('project adapter plays a loopback remote MP3', (_) async {
    final fixture = base64Decode(_silentMp3Base64);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) {
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.contentLength = fixture.length;
      request.response.add(fixture);
      unawaited(request.response.close());
    });
    final engine = AudioplayersForegroundAudioEngine();
    ForegroundAudioSession? session;

    try {
      session = await engine.loadRemote(
        Uri.parse(
          'http://${server.address.address}:${server.port}/probe.mp3'
          '?vkey=must-not-leak',
        ),
      );
      await _expectStateAfter(
        session,
        ForegroundAudioState.playing,
        session.play,
      );
      await _expectStateAfter(
        session,
        ForegroundAudioState.paused,
        session.pause,
      );
      await _expectStateAfter(
        session,
        ForegroundAudioState.playing,
        session.play,
      );
      await _expectStateAfter(
        session,
        ForegroundAudioState.stopped,
        session.stop,
      );
    } finally {
      await session?.dispose();
      await requests.cancel();
      await server.close(force: true);
    }
  });
}

Future<void> _expectStateAfter(
  ForegroundAudioSession session,
  ForegroundAudioState expected,
  Future<void> Function() operation,
) async {
  final reached = session.states.firstWhere((state) => state == expected);
  await operation();
  await reached.timeout(const Duration(seconds: 5));
}

// 0.5 seconds of silent 8 kHz mono MP3 generated with FFmpeg 9.0. It lives in
// test code so no playback fixture is shipped in the application bundle.
const _silentMp3Base64 =
    'SUQzBAAAAAAAIlRTU0UAAAAOAAADTGF2ZjYzLjEuMTAwAAAAAAAAAAAAAAD/4zjAAAAAAAAAAAAASW5mbwAAAA8AAAAJAAADYABVVVVVVVVVVVVVVWpqampqampqampqgICAgICAgICAgICVlZWVlZWVlZWVlaqqqqqqqqqqqqqqwMDAwMDAwMDAwMDV1dXV1dXV1dXV1erq6urq6urq6urq//////////////8AAAAATGF2YzYzLjEuAAAAAAAAAAAAAAAAJAJgAAAAAAAAA2C8msofAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/4xjEAAAAA0gAAAAATEFNRTQuMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjEOwAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjEdgAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjEsQAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVU=';
