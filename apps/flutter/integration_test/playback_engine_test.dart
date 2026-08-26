import 'dart:async';
import 'dart:convert';
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

  testWidgets('project adapter plays a loopback remote MP3', (tester) async {
    final fixture = base64Decode(_silentMp3Base64);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen(
      (request) => unawaited(_serveFixture(request, fixture)),
    );
    final engine = AudioplayersForegroundAudioEngine();
    ForegroundAudioSession? session;

    try {
      session = await engine.loadRemote(
        Uri.parse(
          'http://${server.address.address}:${server.port}/probe.mp3'
          '?vkey=must-not-leak',
        ),
      );
      await session.setVolume(0);
      final progressed = session.positionMs.firstWhere(
        (positionMs) => positionMs > 0,
      );
      await _expectStateAfter(
        session,
        ForegroundAudioState.playing,
        session.play,
      );
      // audioplayers uses a frame-driven position updater by default. Pump a
      // frame after native playback has started so this integration test
      // observes the same callback path as the running Flutter surface.
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        await progressed.timeout(const Duration(seconds: 5)),
        greaterThan(0),
      );
      final sought = session.positionMs.firstWhere(
        (positionMs) => positionMs >= 50 && positionMs <= 450,
      );
      await session.seekToMs(100);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        await sought.timeout(const Duration(seconds: 5)),
        inInclusiveRange(50, 450),
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
  }, skip: !Platform.isLinux);
}

Future<void> _serveFixture(HttpRequest request, List<int> fixture) async {
  final response = request.response;
  response.headers.contentType = ContentType('audio', 'mpeg');
  response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  final range = request.headers.value(HttpHeaders.rangeHeader);
  if (range == null) {
    response.contentLength = fixture.length;
    response.add(fixture);
    await response.close();
    return;
  }

  final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
  final start = match == null ? null : int.tryParse(match.group(1)!);
  final requestedEnd = match == null || match.group(2)!.isEmpty
      ? null
      : int.tryParse(match.group(2)!);
  if (start == null ||
      start < 0 ||
      start >= fixture.length ||
      (requestedEnd != null && requestedEnd < start)) {
    response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes */${fixture.length}',
    );
    await response.close();
    return;
  }

  final end = requestedEnd == null || requestedEnd >= fixture.length
      ? fixture.length - 1
      : requestedEnd;
  response.statusCode = HttpStatus.partialContent;
  response.headers.set(
    HttpHeaders.contentRangeHeader,
    'bytes $start-$end/${fixture.length}',
  );
  response.contentLength = end - start + 1;
  response.add(fixture.sublist(start, end + 1));
  await response.close();
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
