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
    final session = const MediaKitTrackMusicVideoEngine().createSession();

    try {
      await fixture.writeAsBytes(base64Decode(_blackMp4Base64), flush: true);
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

      await session.pause();
      await _waitFor(
        session,
        () => session.stage == TrackMusicVideoSessionStage.paused,
      );
      await session.seek(const Duration(milliseconds: 400));
      await session.play();
      await _waitFor(
        session,
        () => session.stage == TrackMusicVideoSessionStage.playing,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(session.stage, isNot(TrackMusicVideoSessionStage.error));
    } finally {
      session.dispose();
      await fixtureDirectory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);
}

Future<void> _waitFor(
  TrackMusicVideoSession session,
  bool Function() predicate,
) async {
  if (predicate()) return;
  final reached = Completer<void>();
  void listener() {
    if (predicate() && !reached.isCompleted) reached.complete();
  }

  session.addListener(listener);
  try {
    await reached.future.timeout(const Duration(seconds: 8));
  } finally {
    session.removeListener(listener);
  }
}

// Two seconds of black 16x16 H.264 video generated with FFmpeg 9.0. It lives
// in test code so no video fixture is shipped in the application bundle.
const _blackMp4Base64 =
    'AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAANgbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAD6AAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAot0cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAD6AAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAABAAAAAQAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAA+gAACAAAABAAAAAAIDbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAABAAAABAABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABrm1pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAW5zdGJsAAAAvnN0c2QAAAAAAAAAAQAAAK5hdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAABAAEABIAAAASAAAAAAAAAABFExhdmM2My4xLjEwMCBsaWJ4MjY0AAAAAAAAAAAAAAAAGP//AAAANGF2Y0MBZAAK/+EAF2dkAAqs2V7ARAAAAwAEAAADAAg8SJZYAQAGaOvjyyLA/fj4AAAAABBwYXNwAAAAAQAAAAEAAAAUYnRydAAAAAAAAAXSAAAAAAAAABhzdHRzAAAAAAAAAAEAAAAEAABAAAAAABRzdHNzAAAAAAAAAAEAAAABAAAAKGN0dHMAAAAAAAAAAwAAAAEAAIAAAAAAAQABAAAAAAACAABAAAAAABxzdHNjAAAAAAAAAAEAAAABAAAABAAAAAEAAAAkc3RzegAAAAAAAAAAAAAABAAAAsUAAAAMAAAADAAAAAwAAAAUc3RjbwAAAAAAAAABAAADkAAAAGF1ZHRhAAAAWW1ZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGlyYXBwbAAAAAAAAAAAAAAAACxpbHN0AAAAJKl0b28AAAAcZGF0YQAAAAEAAAAATGF2ZjYzLjEuMTAwAAAACGZyZWUAAALxbWRhdAAAAq0GBf//qdxF6b3m2Ui3lizYINkj7u94MjY0IC0gY29yZSAxNjUgLXIyMjIyIGIzNTYwNWEgLSBILjI2NC9NUEVHLTQgQVZDIGNvZGVjIC0gQ29weWxlZnQgMjAwMy0yMDI1IC0gaHR0cDovL3d3dy52aWRlb2xhbi5vcmcveDI2NC5odG1sIC0gb3B0aW9uczogY2FiYWM9MSByZWY9MyBkZWJsb2NrPTE6MDowIGFuYWx5c2U9MHgzOjB4MTEzIG1lPWhleCBzdWJtZT03IHBzeT0xIHBzeV9yZD0xLjAwOjAuMDAgbWl4ZWRfcmVmPTEgbWVfcmFuZ2U9MTYgY2hyb21hX21lPTEgdHJlbGxpcz0xIDh4OGRjdD0xIGNxbT0wIGRlYWR6b25lPTIxLDExIGZhc3RfcHNraXA9MSBjaHJvbWFfcXBfb2Zmc2V0PS0yIHRocmVhZHM9MSBsb29rYWhlYWRfdGhyZWFkcz0xIHNsaWNlZF90aHJlYWRzPTAgbnI9MCBkZWNpbWF0ZT0xIGludGVybGFjZWQ9MCBibHVyYXlfY29tcGF0PTAgY29uc3RyYWluZWRfaW50cmE9MCBiZnJhbWVzPTMgYl9weXJhbWlkPTIgYl9hZGFwdD0xIGJfYmlhcz0wIGRpcmVjdD0xIHdlaWdodGI9MSBvcGVuX2dvcD0wIHdlaWdodHA9MiBrZXlpbnQ9MjUwIGtleWludF9taW49MSBzY2VuZWN1dD00MCBpbnRyYV9yZWZyZXNoPTAgcmNfbG9va2FoZWFkPTQwIHJjPWNyZiBtYnRyZWU9MSBjcmY9MjMuMCBxY29tcD0wLjYwIHFwbWluPTAgcXBtYXg9NjkgcXBzdGVwPTQgaXBfcmF0aW89MS40MCBhcT0xOjEuMDAAgAAAABBliIQAaf++99S3zLLuByOBAAAACgGaI2xBX/7wAAAAAQZ5BeIK/koEAAAACAGeYmpBX5KA=';
