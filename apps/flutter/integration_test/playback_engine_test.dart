import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/media_kit_foreground_audio_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

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
      (request) => unawaited(
        _serveFixture(request, fixture, ContentType('audio', 'mpeg')),
      ),
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
      await engine.dispose();
      await requests.cancel();
      await server.close(force: true);
    }
  }, skip: !Platform.isLinux);

  testWidgets('project adapter decodes the selected low M4A fallback', (
    tester,
  ) async {
    final fixture = base64Decode(_silentM4aBase64);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen(
      (request) => unawaited(
        _serveFixture(request, fixture, ContentType('audio', 'mp4')),
      ),
    );
    final engine = AudioplayersForegroundAudioEngine();
    ForegroundAudioSession? session;

    try {
      session = await engine.loadRemote(
        Uri.parse(
          'http://${server.address.address}:${server.port}/probe.m4a'
          '?vkey=must-not-leak',
        ),
        format: ForegroundAudioFormat.m4a,
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
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        await progressed.timeout(const Duration(seconds: 5)),
        greaterThan(0),
      );
      await _expectStateAfter(
        session,
        ForegroundAudioState.stopped,
        session.stop,
      );
    } finally {
      await session?.dispose();
      await engine.dispose();
      await requests.cancel();
      await server.close(force: true);
    }
  }, skip: !Platform.isLinux);

  testWidgets('project adapter decodes the selected SQ FLAC source', (
    tester,
  ) async {
    final fixture = base64Decode(_silentFlacBase64);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen(
      (request) => unawaited(
        _serveFixture(request, fixture, ContentType('audio', 'flac')),
      ),
    );
    final engine = AudioplayersForegroundAudioEngine();
    ForegroundAudioSession? session;

    try {
      session = await engine.loadRemote(
        Uri.parse(
          'http://${server.address.address}:${server.port}/probe.flac'
          '?vkey=must-not-leak',
        ),
        format: ForegroundAudioFormat.flac,
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
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        await progressed.timeout(const Duration(seconds: 5)),
        greaterThan(0),
      );
      await _expectStateAfter(
        session,
        ForegroundAudioState.stopped,
        session.stop,
      );
    } finally {
      await session?.dispose();
      await engine.dispose();
      await requests.cancel();
      await server.close(force: true);
    }
  }, skip: !Platform.isLinux);

  testWidgets('media_kit candidate reuses one Player across remote sources', (
    tester,
  ) async {
    final fixture = base64Decode(_silentMp3Base64);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen(
      (request) => unawaited(
        _serveFixture(request, fixture, ContentType('audio', 'mpeg')),
      ),
    );
    final engine = MediaKitForegroundAudioEngine();
    final enginePlayer = engine.debugPlayer;
    ForegroundAudioSession? session;

    try {
      await _recordSoakMetrics(0);
      for (var replacement = 0; replacement < 100; replacement++) {
        final path = 'synthetic-$replacement.mp3';
        session = await engine.loadRemote(
          Uri.parse(
            'http://${server.address.address}:${server.port}/$path'
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
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          await progressed.timeout(const Duration(seconds: 5)),
          greaterThan(0),
        );
        await session.stop();
        await session.dispose();
        session = null;
        expect(engine.debugPlayer, same(enginePlayer));
        if ([9, 19, 49, 99].contains(replacement)) {
          await _recordSoakMetrics(replacement + 1);
        }
      }
    } finally {
      await session?.dispose();
      await engine.dispose();
      await requests.cancel();
      await server.close(force: true);
    }
  }, skip: !Platform.isLinux);

  testWidgets('media_kit EOF replay retains the cached synthetic remote source', (
    tester,
  ) async {
    final fixture = base64Decode(_silentMp3Base64);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requestCount = 0;
    final requests = server.listen((request) {
      requestCount++;
      unawaited(_serveFixture(request, fixture, ContentType('audio', 'mpeg')));
    });
    final engine = MediaKitForegroundAudioEngine();
    ForegroundAudioSession? session;
    try {
      session = await engine.loadRemote(
        Uri.parse('http://${server.address.address}:${server.port}/repeat.mp3'),
      );
      await session.setVolume(0);
      var completed = session.states.firstWhere(
        (state) => state == ForegroundAudioState.completed,
      );
      await session.play();
      await completed.timeout(const Duration(seconds: 10));
      final initialRequests = requestCount;
      expect(initialRequests, greaterThan(0));
      for (var cycle = 0; cycle < 100; cycle++) {
        completed = session.states.firstWhere(
          (state) => state == ForegroundAudioState.completed,
        );
        final progressed = session.positionMs.firstWhere(
          (position) => position > 0,
        );
        await session.seekToMs(0);
        await session.play();
        await progressed.timeout(const Duration(seconds: 5));
        await completed.timeout(const Duration(seconds: 10));
        expect(
          requestCount,
          initialRequests,
          reason: 'EOF replay must not reopen the synthetic HTTP source',
        );
      }
      debugPrint(
        'FURA_DIAGNOSTIC synthetic_eof_soak completions=100 '
        'extraHttpRequests=${requestCount - initialRequests} activeMusicPlayers=1',
      );
    } finally {
      await session?.dispose();
      await engine.dispose();
      await requests.cancel();
      await server.close(force: true);
    }
  }, skip: !Platform.isLinux);
}

Future<void> _recordSoakMetrics(int replacements) async {
  // Linux-only synthetic integration evidence. Never log the source or the
  // rest of /proc/self/status; Player count is the identity assertion above,
  // not a claim that an SDK-retired mpv handle is already destroyed.
  final status = await File('/proc/self/status').readAsLines();
  int value(String field) => int.parse(
    status
        .firstWhere((line) => line.startsWith('$field:'))
        .split(RegExp(r'\s+'))[1],
  );
  debugPrint(
    'FURA_DIAGNOSTIC synthetic_media_soak replacements=$replacements '
    'activeMusicPlayers=1 rssMiB=${value('VmRSS') ~/ 1024} threads=${value('Threads')}',
  );
}

Future<void> _serveFixture(
  HttpRequest request,
  List<int> fixture,
  ContentType contentType,
) async {
  final response = request.response;
  response.headers.contentType = contentType;
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

// 0.5 seconds of silent 8 kHz mono AAC in an M4A container generated with
// FFmpeg 9.0. It verifies the C200 playback format without network or account
// data and is not shipped in the application bundle.
const _silentM4aBase64 =
    'AAAAHGZ0eXBNNEEgAAACAE00QSBpc29taXNvMgAAAw5tb292AAAAbG12aGQAAAAAAAAAAAAAAAAAAB9AAAAPoAABAAABAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAACOXRyYWsAAABcdGtoZAAAAAMAAAAAAAAAAAAAAAEAAAAAAAAPoAAAAAAAAAAAAAAAAQEAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAACRlZHRzAAAAHGVsc3QAAAAAAAAAAQAAD6AAAAQAAAEAAAAAAbFtZGlhAAAAIG1kaGQAAAAAAAAAAAAAAAAAAB9AAAAToFXEAAAAAAAtaGRscgAAAAAAAAAAc291bgAAAAAAAAAAAAAAAFNvdW5kSGFuZGxlcgAAAAFcbWluZgAAABBzbWhkAAAAAAAAAAAAAAAkZGluZgAAABxkcmVmAAAAAAAAAAEAAAAMdXJsIAAAAAEAAAEgc3RibAAAAGpzdHNkAAAAAAAAAAEAAABabXA0YQAAAAAAAAABAAAAAAAAAAAAAQAQAAAAAB9AAAAAAAA2ZXNkcwAAAAADgICAJQABAASAgIAXQBUAAAAAALuAAAABvQWAgIAFFYhW5QAGgICAAQIAAAAgc3R0cwAAAAAAAAACAAAABAAABAAAAAABAAADoAAAABxzdHNjAAAAAAAAAAEAAAABAAAABQAAAAEAAAAoc3RzegAAAAAAAAAAAAAABQAAABMAAAAEAAAABAAAAAQAAAAEAAAAFHN0Y28AAAAAAAAAAQAAAzoAAAAac2dwZAEAAAByb2xsAAAAAgAAAAH//wAAABxzYmdwAAAAAHJvbGwAAAABAAAABQAAAAEAAABhdWR0YQAAAFltZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGlyYXBwbAAAAAAAAAAAAAAAACxpbHN0AAAAJKl0b28AAAAcZGF0YQAAAAEAAAAATGF2ZjYzLjEuMTAxAAAACGZyZWUAAAArbWRhdNwATGF2YzYzLjEuMTAxAAIwQA4BGCAHARggBwEYIAcBGCAH';

// 0.5 seconds of silent 8 kHz mono FLAC generated with libFLAC 1.5.0.
// It verifies the F000 playback format without network or account data.
const _silentFlacBase64 =
    'ZkxhQwAAACIQABAAAAANAAANAfQA8AAAD6BYEBJJx2tzW9dM5TArAJMXhAAAKCAAAAByZWZlcmVuY2UgbGliRkxBQyAxLjUuMCAyMDI1MDIxMQAAAAD/+HQIAA+fggAAAFLj';

// 0.5 seconds of silent 8 kHz mono MP3 generated with FFmpeg 9.0. It lives in
// test code so no playback fixture is shipped in the application bundle.
const _silentMp3Base64 =
    'SUQzBAAAAAAAIlRTU0UAAAAOAAADTGF2ZjYzLjEuMTAwAAAAAAAAAAAAAAD/4zjAAAAAAAAAAAAASW5mbwAAAA8AAAAJAAADYABVVVVVVVVVVVVVVWpqampqampqampqgICAgICAgICAgICVlZWVlZWVlZWVlaqqqqqqqqqqqqqqwMDAwMDAwMDAwMDV1dXV1dXV1dXV1erq6urq6urq6urq//////////////8AAAAATGF2YzYzLjEuAAAAAAAAAAAAAAAAJAJgAAAAAAAAA2C8msofAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/4xjEAAAAA0gAAAAATEFNRTQuMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjEOwAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjEdgAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjEsQAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/4xjExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVU=';
