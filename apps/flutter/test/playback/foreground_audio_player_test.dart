import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';

void main() {
  test('engine disables plugin diagnostics before any player exists', () {
    final previous = AudioLogger.logLevel;
    final printed = <String>[];
    try {
      AudioLogger.logLevel = AudioLogLevel.error;
      AudioplayersForegroundAudioEngine();
      runZoned(
        () => AudioLogger.error(
          'https://audio.example.test/source.mp3?vkey=must-not-leak',
        ),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, message) => printed.add(message),
        ),
      );
      expect(AudioLogger.logLevel, AudioLogLevel.none);
      expect(printed, isEmpty);
    } finally {
      AudioLogger.logLevel = previous;
    }
  });

  test('invalid remote identity fails before a plugin player is created', () {
    final engine = AudioplayersForegroundAudioEngine();

    expect(
      engine.loadRemote(Uri.parse('file:///tmp/private.mp3')),
      throwsA(
        isA<ForegroundAudioException>().having(
          (error) => error.failure,
          'failure',
          ForegroundAudioFailure.load,
        ),
      ),
    );
  });
}
