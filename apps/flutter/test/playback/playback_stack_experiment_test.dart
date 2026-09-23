import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/playback_stack_experiment.dart';

void main() {
  PlaybackStackSelection resolveDefault(
    TargetPlatform platform,
  ) => PlaybackStackSelection.resolve(
    audioEngineValue: PlaybackStackSelection.defaultRequestedAudioEngineValue,
    systemMediaValue: PlaybackStackSelection.defaultRequestedSystemMediaValue,
    platform: platform,
  );

  test('no-define defaults request D on every shipping platform', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.iOS,
    ]) {
      final selection = resolveDefault(platform);
      expect(
        selection.requestedAudioEngine,
        MusicAudioEngineKind.mediaKit,
        reason: platform.name,
      );
      expect(
        selection.requestedSystemMediaEdge,
        SystemMediaEdgeKind.flutterMediaSession,
        reason: platform.name,
      );
    }
  });

  test('Android Windows and macOS default request is effective D', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    ]) {
      final selection = resolveDefault(platform);
      expect(selection.effectiveAudioEngine, MusicAudioEngineKind.mediaKit);
      expect(
        selection.effectiveSystemMediaEdge,
        SystemMediaEdgeKind.flutterMediaSession,
      );
      expect(selection.usedFallback, isFalse);
      expect(selection.fallbackReason, PlaybackStackFallbackReason.none);
    }
  });

  test('Linux default request D resolves to MediaKit plus Fura MPRIS', () {
    final selection = resolveDefault(TargetPlatform.linux);

    expect(selection.effectiveAudioEngine, MusicAudioEngineKind.mediaKit);
    expect(selection.effectiveSystemMediaEdge, SystemMediaEdgeKind.furaMpris);
    expect(selection.usesProjectLinuxMpris, isTrue);
    expect(selection.usedFallback, isTrue);
    expect(
      selection.fallbackReason,
      PlaybackStackFallbackReason.flutterMediaSessionUnsupportedOnLinux,
    );
  });

  test('iOS default request D resolves to MediaKit plus audio_service', () {
    final selection = resolveDefault(TargetPlatform.iOS);

    expect(selection.effectiveAudioEngine, MusicAudioEngineKind.mediaKit);
    expect(
      selection.effectiveSystemMediaEdge,
      SystemMediaEdgeKind.audioService,
    );
    expect(selection.usedFallback, isTrue);
    expect(
      selection.fallbackReason,
      PlaybackStackFallbackReason.flutterMediaSessionIosAudioSessionConflict,
    );
  });

  test('all four Android combinations remain explicitly selectable', () {
    final combinations =
        <(String, String, MusicAudioEngineKind, SystemMediaEdgeKind)>[
          (
            PlaybackStackSelection.rollbackAudioEngineValue,
            PlaybackStackSelection.rollbackSystemMediaValue,
            MusicAudioEngineKind.audioplayers,
            SystemMediaEdgeKind.audioService,
          ),
          (
            PlaybackStackSelection.defaultRequestedAudioEngineValue,
            PlaybackStackSelection.rollbackSystemMediaValue,
            MusicAudioEngineKind.mediaKit,
            SystemMediaEdgeKind.audioService,
          ),
          (
            PlaybackStackSelection.rollbackAudioEngineValue,
            PlaybackStackSelection.defaultRequestedSystemMediaValue,
            MusicAudioEngineKind.audioplayers,
            SystemMediaEdgeKind.flutterMediaSession,
          ),
          (
            PlaybackStackSelection.defaultRequestedAudioEngineValue,
            PlaybackStackSelection.defaultRequestedSystemMediaValue,
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
      expect(selection.requestedAudioEngine, combination.$3);
      expect(selection.requestedSystemMediaEdge, combination.$4);
      expect(selection.effectiveAudioEngine, combination.$3);
      expect(selection.effectiveSystemMediaEdge, combination.$4);
      expect(selection.usedFallback, isFalse);
    }
  });

  test('invalid engine fails the complete request closed to rollback A', () {
    final selection = PlaybackStackSelection.resolve(
      audioEngineValue: 'unknown-player',
      systemMediaValue: PlaybackStackSelection.defaultRequestedSystemMediaValue,
      platform: TargetPlatform.android,
    );

    expect(selection.requestedAudioEngine, MusicAudioEngineKind.audioplayers);
    expect(
      selection.requestedSystemMediaEdge,
      SystemMediaEdgeKind.audioService,
    );
    expect(selection.effectiveAudioEngine, MusicAudioEngineKind.audioplayers);
    expect(
      selection.effectiveSystemMediaEdge,
      SystemMediaEdgeKind.audioService,
    );
    expect(selection.isRollbackBaseline, isTrue);
    expect(selection.fallbackReason, PlaybackStackFallbackReason.invalidDefine);
  });

  test(
    'invalid system edge fails the complete request closed to rollback A',
    () {
      final selection = PlaybackStackSelection.resolve(
        audioEngineValue:
            PlaybackStackSelection.defaultRequestedAudioEngineValue,
        systemMediaValue: 'unknown-session',
        platform: TargetPlatform.windows,
      );

      expect(selection.requestedAudioEngine, MusicAudioEngineKind.audioplayers);
      expect(
        selection.requestedSystemMediaEdge,
        SystemMediaEdgeKind.audioService,
      );
      expect(selection.effectiveAudioEngine, MusicAudioEngineKind.audioplayers);
      expect(
        selection.effectiveSystemMediaEdge,
        SystemMediaEdgeKind.audioService,
      );
      expect(
        selection.fallbackReason,
        PlaybackStackFallbackReason.invalidDefine,
      );
    },
  );

  test(
    'diagnostics distinguish platform fallback from runtime edge failure',
    () {
      final linux = resolveDefault(TargetPlatform.linux);
      expect(
        linux.diagnosticLine(
          platform: TargetPlatform.linux,
          systemControlsAvailable: true,
        ),
        allOf(
          contains('requestedEngine=mediaKit'),
          contains('requestedSystemEdge=flutterMediaSession'),
          contains('effectiveEngine=mediaKit'),
          contains('effectiveSystemEdge=furaMpris'),
          contains('fallback=true'),
          contains('fallbackReason=flutter_media_session_unsupported_on_linux'),
        ),
      );

      final android = resolveDefault(TargetPlatform.android);
      expect(
        android.diagnosticLine(
          platform: TargetPlatform.android,
          systemControlsAvailable: false,
        ),
        allOf(
          contains('effectiveSystemEdge=unavailable'),
          contains('fallback=true'),
          contains('fallbackReason=system_edge_initialization_failed'),
          contains('systemEdgeInit=failed'),
          contains('effectiveSystemControls=unavailable'),
        ),
      );
    },
  );
}
