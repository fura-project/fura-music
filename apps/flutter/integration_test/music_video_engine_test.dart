import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/music_video/track_music_video_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('project MV adapter decodes and controls a local MP4', (
    tester,
  ) async {
    final fixtureDirectory = await Directory.systemTemp.createTemp(
      'flutterustmusic-mv-',
    );
    final fixture = File('${fixtureDirectory.path}/probe.mp4');
    final session = const MediaKitTrackMusicVideoEngine(enableDiagnostics: true)
        .createSession();
    final stateTimeline = <String>[];
    var environment = <String>[];
    void recordState() {
      stateTimeline.add(
        'stage=${session.stage.name} '
        'position=${session.position.inMilliseconds}ms '
        'duration=${session.duration.inMilliseconds}ms',
      );
    }

    session.addListener(recordState);

    try {
      await fixture.writeAsBytes(base64Decode(_blackMp4Base64), flush: true);
      environment = await _readEnvironment(fixture);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: session.buildVideo(),
                ),
              ),
            ),
          ),
        ),
      );

      await session.open(fixture.uri.toString());
      await _waitFor(
        session,
        () => session.stage == TrackMusicVideoSessionStage.playing,
      );
      await _waitFor(session, () => session.duration > Duration.zero);
      expect(session.stage, TrackMusicVideoSessionStage.playing);
      expect(
        session.duration,
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
      await _waitFor(session, () => session.position > Duration.zero);

      await session.pause();
      await _waitFor(
        session,
        () => session.stage == TrackMusicVideoSessionStage.paused,
      );
      await session.seek(const Duration(milliseconds: 400));
      await _waitFor(
        session,
        () => session.position >= const Duration(milliseconds: 400),
      );
      await session.play();
      await _waitFor(
        session,
        () =>
            session.stage == TrackMusicVideoSessionStage.playing &&
            session.position > const Duration(milliseconds: 400),
      );
      expect(session.stage, isNot(TrackMusicVideoSessionStage.error));
    } catch (_) {
      // The fixture is synthetic and contains no account data. These details
      // make native playback failures actionable in CI without weakening the
      // decode, seek, pause, or resume assertions above.
      debugPrint(environment.join('\n'));
      debugPrint('MV session error: ${session.errorMessage ?? '<none>'}');
      debugPrint('MV state timeline:\n${stateTimeline.join('\n')}');
      debugPrint('MV/mpv diagnostics:\n${session.diagnosticLog.join('\n')}');
      rethrow;
    } finally {
      session.removeListener(recordState);
      session.dispose();
      await fixtureDirectory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);
}

Future<List<String>> _readEnvironment(File fixture) async {
  final environment = <String>[];
  final stat = await fixture.stat();
  environment.add(
    'MV fixture: uri=${fixture.uri} bytes=${stat.size} '
    'modified=${stat.modified.toUtc().toIso8601String()}',
  );
  environment.add(
    'MV display: DISPLAY=${Platform.environment['DISPLAY'] ?? '<unset>'} '
    'WAYLAND_DISPLAY=${Platform.environment['WAYLAND_DISPLAY'] ?? '<unset>'} '
    'GDK_BACKEND=${Platform.environment['GDK_BACKEND'] ?? '<unset>'} '
    'LIBGL_ALWAYS_SOFTWARE='
    '${Platform.environment['LIBGL_ALWAYS_SOFTWARE'] ?? '<unset>'}',
  );
  for (final command in <(String, List<String>)>[
    ('uname', ['-a']),
    ('pkg-config', ['--modversion', 'mpv']),
    ('dpkg-query', ['-W', '-f=\${Version}', 'libmpv2']),
    ('ldd', ['--version']),
  ]) {
    try {
      final result = await Process.run(command.$1, command.$2);
      final output = '${result.stdout}${result.stderr}'.trim();
      environment.add(
        'MV runtime ${command.$1}: exit=${result.exitCode} $output',
      );
    } on ProcessException catch (error) {
      environment.add('MV runtime ${command.$1}: unavailable ($error)');
    }
  }
  return environment;
}

Future<void> _waitFor(
  TrackMusicVideoSession session,
  bool Function() predicate,
) async {
  if (predicate()) return;
  final reached = Completer<void>();
  void listener() {
    if (reached.isCompleted) return;
    if (predicate()) {
      reached.complete();
    } else if (session.stage == TrackMusicVideoSessionStage.error) {
      reached.completeError(
        StateError(session.errorMessage ?? 'music video session failed'),
      );
    }
  }

  session.addListener(listener);
  try {
    await reached.future.timeout(const Duration(seconds: 8));
  } finally {
    session.removeListener(listener);
  }
}

// Two seconds of black 16x16 yuv420p H.264 video generated with Ubuntu 24.04's
// FFmpeg 6.1. It lives in test code so no video fixture is shipped in the app.
const _blackMp4Base64 =
    'AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAQhbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAB9AAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAA0t0cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAB9AAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAABAAAAAQAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAAfQAAAIAAABAAAAAALDbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAAAoAAAAUABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAACbm1pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAi5zdGJsAAAAvnN0c2QAAAAAAAAAAQAAAK5hdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAABAAEABIAAAASAAAAAAAAAABFUxhdmM2MC4zMS4xMDIgbGlieDI2NAAAAAAAAAAAAAAAGP//AAAANGF2Y0MBZAAK/+EAF2dkAAqs2V7ARAAAAwAEAAADAFA8SJZYAQAGaOvjyyLA/fj4AAAAABBwYXNwAAAAAQAAAAEAAAAUYnRydAAAAAAAAA8kAAAPJAAAABhzdHRzAAAAAAAAAAEAAAAUAAAEAAAAABRzdHNzAAAAAAAAAAEAAAABAAAAqGN0dHMAAAAAAAAAEwAAAAEAAAgAAAAAAQAAFAAAAAABAAAIAAAAAAEAAAAAAAAAAQAABAAAAAABAAAUAAAAAAEAAAgAAAAAAQAAAAAAAAABAAAEAAAAAAEAABQAAAAAAQAACAAAAAABAAAAAAAAAAEAAAQAAAAAAQAAFAAAAAABAAAIAAAAAAEAAAAAAAAAAQAABAAAAAABAAAQAAAAAAIAAAQAAAAAHHN0c2MAAAAAAAAAAQAAAAEAAAAUAAAAAQAAAGRzdHN6AAAAAAAAAAAAAAAUAAACxQAAAAwAAAAMAAAADAAAAAwAAAASAAAADgAAAAwAAAAMAAAAEgAAAA4AAAAMAAAADAAAABIAAAAOAAAADAAAAAwAAAASAAAADgAAAAwAAAAUc3RjbwAAAAAAAAABAAAEUQAAAGJ1ZHRhAAAAWm1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAG1kaXJhcHBsAAAAAAAAAAAAAAAALWlsc3QAAAAlqXRvbwAAAB1kYXRhAAAAAQAAAABMYXZmNjAuMTYuMTAwAAAACGZyZWUAAAPRbWRhdAAAAq4GBf//qtxF6b3m2Ui3lizYINkj7u94MjY0IC0gY29yZSAxNjQgcjMxMDggMzFlMTlmOSAtIEguMjY0L01QRUctNCBBVkMgY29kZWMgLSBDb3B5bGVmdCAyMDAzLTIwMjMgLSBodHRwOi8vd3d3LnZpZGVvbGFuLm9yZy94MjY0Lmh0bWwgLSBvcHRpb25zOiBjYWJhYz0xIHJlZj0zIGRlYmxvY2s9MTowOjAgYW5hbHlzZT0weDM6MHgxMTMgbWU9aGV4IHN1Ym1lPTcgcHN5PTEgcHN5X3JkPTEuMDA6MC4wMCBtaXhlZF9yZWY9MSBtZV9yYW5nZT0xNiBjaHJvbWFfbWU9MSB0cmVsbGlzPTEgOHg4ZGN0PTEgY3FtPTAgZGVhZHpvbmU9MjEsMTEgZmFzdF9wc2tpcD0xIGNocm9tYV9xcF9vZmZzZXQ9LTIgdGhyZWFkcz0xIGxvb2thaGVhZF90aHJlYWRzPTEgc2xpY2VkX3RocmVhZHM9MCBucj0wIGRlY2ltYXRlPTEgaW50ZXJsYWNlZD0wIGJsdXJheV9jb21wYXQ9MCBjb25zdHJhaW5lZF9pbnRyYT0wIGJmcmFtZXM9MyBiX3B5cmFtaWQ9MiBiX2FkYXB0PTEgYl9iaWFzPTAgZGlyZWN0PTEgd2VpZ2h0Yj0xIG9wZW5fZ29wPTAgd2VpZ2h0cD0yIGtleWludD0yNTAga2V5aW50X21pbj0xMCBzY2VuZWN1dD00MCBpbnRyYV9yZWZyZXNoPTAgcmNfbG9va2FoZWFkPTQwIHJjPWNyZiBtYnRyZWU9MSBjcmY9MjMuMCBxY29tcD0wLjYwIHFwbWluPTAgcXBtYXg9NjkgcXBzdGVwPTQgaXBfcmF0aW89MS40MCBhcT0xOjEuMDAAgAAAAA9liIQAEf/+94gfMstvnHkAAAAIQZokbEEf/uAAAAAIQZ5CeId/t4EAAAAIAZ5hdEN/uoAAAAAIAZ5jakN/uoEAAAAOQZpoSahBaJlMCCP//uEAAAAKQZ6GRREsO/+3gQAAAAgBnqV0Q3+6gQAAAAgBnqdqQ3+6gAAAAA5BmqxJqEFsmUwIIf/+4AAAAApBnspFFSw7/7eBAAAACAGe6XRDf7qAAAAACAGe62pDf7qAAAAADkGa8EmoQWyZTAh///7hAAAACkGfDkUVLDv/t4EAAAAIAZ8tdEN/uoEAAAAIAZ8vakN/uoAAAAAOQZszSahBbJlMCG///uAAAAAKQZ9RRRUsN/+6gQAAAAgBn3JqQ3+6gA==';
