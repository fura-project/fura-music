import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/playback_stack_experiment.dart';

void main() {
  test('no defines resolve to the unchanged production baseline', () {
    final selection = PlaybackStackSelection.resolve(
      audioEngineValue: PlaybackStackSelection.baselineAudioEngineValue,
      systemMediaValue: PlaybackStackSelection.baselineSystemMediaValue,
      platform: TargetPlatform.android,
    );

    expect(selection.audioEngine, MusicAudioEngineKind.audioplayers);
    expect(selection.systemMediaEdge, SystemMediaEdgeKind.audioService);
    expect(selection.isProductionBaseline, isTrue);
    expect(selection.usedFallback, isFalse);
  });

  test('all four Android combinations remain independently selectable', () {
    final combinations =
        <(String, String, MusicAudioEngineKind, SystemMediaEdgeKind)>[
          (
            'audioplayers',
            'audio_service',
            MusicAudioEngineKind.audioplayers,
            SystemMediaEdgeKind.audioService,
          ),
          (
            'media_kit',
            'audio_service',
            MusicAudioEngineKind.mediaKit,
            SystemMediaEdgeKind.audioService,
          ),
          (
            'audioplayers',
            'flutter_media_session',
            MusicAudioEngineKind.audioplayers,
            SystemMediaEdgeKind.flutterMediaSession,
          ),
          (
            'media_kit',
            'flutter_media_session',
            MusicAudioEngineKind.mediaKit,
            SystemMediaEdgeKind.flutterMediaSession,
          ),
        ];

    for (final combination in combinations) {
      final selection = PlaybackStackSelection.resolve(
        audioEngineValue: combination.$1,
        systemMediaValue: combination.$2,
        platform: TargetPlatform.android,
      );
      expect(selection.audioEngine, combination.$3);
      expect(selection.systemMediaEdge, combination.$4);
      expect(selection.usedFallback, isFalse);
    }
  });

  test('unknown values fail closed to baseline implementations', () {
    final selection = PlaybackStackSelection.resolve(
      audioEngineValue: 'unknown-player',
      systemMediaValue: 'unknown-session',
      platform: TargetPlatform.android,
    );

    expect(selection.audioEngine, MusicAudioEngineKind.audioplayers);
    expect(selection.systemMediaEdge, SystemMediaEdgeKind.audioService);
    expect(selection.usedFallback, isTrue);
  });

  test('Linux always retains the project-owned MPRIS system edge', () {
    final selection = PlaybackStackSelection.resolve(
      audioEngineValue: 'media_kit',
      systemMediaValue: 'flutter_media_session',
      platform: TargetPlatform.linux,
    );

    expect(selection.audioEngine, MusicAudioEngineKind.mediaKit);
    expect(
      selection.requestedSystemMediaEdge,
      SystemMediaEdgeKind.flutterMediaSession,
    );
    expect(selection.systemMediaEdge, SystemMediaEdgeKind.audioService);
    expect(selection.usesProjectLinuxMpris, isTrue);
    expect(selection.usedFallback, isTrue);
  });
}
