import 'package:flutter/foundation.dart';

enum MusicAudioEngineKind { audioplayers, mediaKit }

enum SystemMediaEdgeKind { audioService, flutterMediaSession }

/// Compile-time playback-stack selection for the reversible HD-033 bake-off.
///
/// A build without defines always selects the existing production baseline.
/// Unknown values also fail closed to that baseline, so a misspelled Release
/// define cannot accidentally enable an experimental implementation.
@immutable
class PlaybackStackSelection {
  const PlaybackStackSelection({
    required this.audioEngine,
    required this.systemMediaEdge,
    required this.requestedSystemMediaEdge,
    required this.usedFallback,
    required this.usesProjectLinuxMpris,
  });

  static const audioEngineDefine = 'FURA_AUDIO_ENGINE';
  static const systemMediaDefine = 'FURA_SYSTEM_MEDIA';

  static const baselineAudioEngineValue = 'audioplayers';
  static const mediaKitAudioEngineValue = 'media_kit';
  static const baselineSystemMediaValue = 'audio_service';
  static const flutterMediaSessionValue = 'flutter_media_session';

  final MusicAudioEngineKind audioEngine;
  final SystemMediaEdgeKind systemMediaEdge;
  final SystemMediaEdgeKind requestedSystemMediaEdge;
  final bool usedFallback;
  final bool usesProjectLinuxMpris;

  bool get isProductionBaseline =>
      audioEngine == MusicAudioEngineKind.audioplayers &&
      systemMediaEdge == SystemMediaEdgeKind.audioService;

  static PlaybackStackSelection current({TargetPlatform? platform}) => resolve(
    audioEngineValue: const String.fromEnvironment(
      audioEngineDefine,
      defaultValue: baselineAudioEngineValue,
    ),
    systemMediaValue: const String.fromEnvironment(
      systemMediaDefine,
      defaultValue: baselineSystemMediaValue,
    ),
    platform: platform ?? defaultTargetPlatform,
  );

  @visibleForTesting
  static PlaybackStackSelection resolve({
    required String audioEngineValue,
    required String systemMediaValue,
    required TargetPlatform platform,
  }) {
    final parsedAudio = switch (audioEngineValue) {
      baselineAudioEngineValue => MusicAudioEngineKind.audioplayers,
      mediaKitAudioEngineValue => MusicAudioEngineKind.mediaKit,
      _ => null,
    };
    final parsedSystem = switch (systemMediaValue) {
      baselineSystemMediaValue => SystemMediaEdgeKind.audioService,
      flutterMediaSessionValue => SystemMediaEdgeKind.flutterMediaSession,
      _ => null,
    };
    final requestedSystem = parsedSystem ?? SystemMediaEdgeKind.audioService;
    final linux = platform == TargetPlatform.linux;
    return PlaybackStackSelection(
      audioEngine: parsedAudio ?? MusicAudioEngineKind.audioplayers,
      // flutter_media_session 3.0.5 has no Linux plugin. Fura's project-owned
      // MPRIS implementation therefore remains the only Linux system edge.
      systemMediaEdge: linux
          ? SystemMediaEdgeKind.audioService
          : requestedSystem,
      requestedSystemMediaEdge: requestedSystem,
      usedFallback:
          parsedAudio == null ||
          parsedSystem == null ||
          (linux && parsedSystem == SystemMediaEdgeKind.flutterMediaSession),
      usesProjectLinuxMpris: linux,
    );
  }
}
