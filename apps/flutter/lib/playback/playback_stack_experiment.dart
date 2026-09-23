import 'package:flutter/foundation.dart';

enum MusicAudioEngineKind { audioplayers, mediaKit }

enum SystemMediaEdgeKind { audioService, flutterMediaSession, furaMpris }

enum PlaybackStackFallbackReason {
  none,
  invalidDefine,
  flutterMediaSessionUnsupportedOnLinux,
  flutterMediaSessionIosAudioSessionConflict,
  flutterMediaSessionUnsupportedOnPlatform,
  systemEdgeInitializationFailed,
}

extension PlaybackStackFallbackReasonDiagnostic on PlaybackStackFallbackReason {
  String get diagnosticValue => switch (this) {
    PlaybackStackFallbackReason.none => 'none',
    PlaybackStackFallbackReason.invalidDefine => 'invalid_define',
    PlaybackStackFallbackReason.flutterMediaSessionUnsupportedOnLinux =>
      'flutter_media_session_unsupported_on_linux',
    PlaybackStackFallbackReason.flutterMediaSessionIosAudioSessionConflict =>
      'flutter_media_session_ios_audio_session_conflict',
    PlaybackStackFallbackReason.flutterMediaSessionUnsupportedOnPlatform =>
      'flutter_media_session_unsupported_on_platform',
    PlaybackStackFallbackReason.systemEdgeInitializationFailed =>
      'system_edge_initialization_failed',
  };
}

/// Compile-time playback-stack selection for the reversible HD-033 bake-off.
///
/// A is retained as the explicit rollback baseline. During the current Human
/// test phase, a build without defines requests D. Unsupported platform edges
/// are resolved explicitly so diagnostics never confuse requested and
/// effective stacks. Any invalid define fails closed to the complete A pair.
@immutable
class PlaybackStackSelection {
  const PlaybackStackSelection({
    required this.requestedAudioEngine,
    required this.requestedSystemMediaEdge,
    required this.effectiveAudioEngine,
    required this.effectiveSystemMediaEdge,
    required this.fallbackReason,
  });

  static const audioEngineDefine = 'FURA_AUDIO_ENGINE';
  static const systemMediaDefine = 'FURA_SYSTEM_MEDIA';

  static const rollbackAudioEngineValue = 'audioplayers';
  static const defaultRequestedAudioEngineValue = 'media_kit';
  static const rollbackSystemMediaValue = 'audio_service';
  static const defaultRequestedSystemMediaValue = 'flutter_media_session';

  final MusicAudioEngineKind requestedAudioEngine;
  final SystemMediaEdgeKind requestedSystemMediaEdge;
  final MusicAudioEngineKind effectiveAudioEngine;
  final SystemMediaEdgeKind effectiveSystemMediaEdge;
  final PlaybackStackFallbackReason fallbackReason;

  bool get usedFallback => fallbackReason != PlaybackStackFallbackReason.none;

  bool get isRollbackBaseline =>
      requestedAudioEngine == MusicAudioEngineKind.audioplayers &&
      requestedSystemMediaEdge == SystemMediaEdgeKind.audioService;

  bool get usesProjectLinuxMpris =>
      effectiveSystemMediaEdge == SystemMediaEdgeKind.furaMpris;

  String diagnosticLine({
    required TargetPlatform platform,
    required bool systemControlsAvailable,
  }) {
    final runtimeFallback = !systemControlsAvailable;
    final reason = runtimeFallback
        ? PlaybackStackFallbackReason.systemEdgeInitializationFailed
        : fallbackReason;
    final effectiveSystemEdgeName = runtimeFallback
        ? 'unavailable'
        : effectiveSystemMediaEdge.name;
    return 'requestedEngine=${requestedAudioEngine.name} '
        'requestedSystemEdge=${requestedSystemMediaEdge.name} '
        'effectiveEngine=${effectiveAudioEngine.name} '
        'effectiveSystemEdge=$effectiveSystemEdgeName '
        'platform=${platform.name} '
        'fallback=${usedFallback || runtimeFallback} '
        'fallbackReason=${reason.diagnosticValue} '
        'systemEdgeInit=${runtimeFallback ? 'failed' : 'success'} '
        'effectiveSystemControls='
        '${runtimeFallback ? 'unavailable' : 'available'}';
  }

  static PlaybackStackSelection current({TargetPlatform? platform}) => resolve(
    audioEngineValue: const String.fromEnvironment(
      audioEngineDefine,
      defaultValue: defaultRequestedAudioEngineValue,
    ),
    systemMediaValue: const String.fromEnvironment(
      systemMediaDefine,
      defaultValue: defaultRequestedSystemMediaValue,
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
      rollbackAudioEngineValue => MusicAudioEngineKind.audioplayers,
      defaultRequestedAudioEngineValue => MusicAudioEngineKind.mediaKit,
      _ => null,
    };
    final parsedSystem = switch (systemMediaValue) {
      rollbackSystemMediaValue => SystemMediaEdgeKind.audioService,
      defaultRequestedSystemMediaValue =>
        SystemMediaEdgeKind.flutterMediaSession,
      _ => null,
    };

    if (parsedAudio == null || parsedSystem == null) {
      return PlaybackStackSelection(
        requestedAudioEngine: MusicAudioEngineKind.audioplayers,
        requestedSystemMediaEdge: SystemMediaEdgeKind.audioService,
        effectiveAudioEngine: MusicAudioEngineKind.audioplayers,
        effectiveSystemMediaEdge: platform == TargetPlatform.linux
            ? SystemMediaEdgeKind.furaMpris
            : SystemMediaEdgeKind.audioService,
        fallbackReason: PlaybackStackFallbackReason.invalidDefine,
      );
    }

    final (effectiveSystemEdge, fallbackReason) = switch ((
      platform,
      parsedSystem,
    )) {
      (TargetPlatform.linux, SystemMediaEdgeKind.flutterMediaSession) => (
        SystemMediaEdgeKind.furaMpris,
        PlaybackStackFallbackReason.flutterMediaSessionUnsupportedOnLinux,
      ),
      (TargetPlatform.linux, SystemMediaEdgeKind.audioService) => (
        SystemMediaEdgeKind.furaMpris,
        PlaybackStackFallbackReason.none,
      ),
      (TargetPlatform.iOS, SystemMediaEdgeKind.flutterMediaSession) => (
        SystemMediaEdgeKind.audioService,
        PlaybackStackFallbackReason.flutterMediaSessionIosAudioSessionConflict,
      ),
      (TargetPlatform.fuchsia, SystemMediaEdgeKind.flutterMediaSession) => (
        SystemMediaEdgeKind.audioService,
        PlaybackStackFallbackReason.flutterMediaSessionUnsupportedOnPlatform,
      ),
      _ => (parsedSystem, PlaybackStackFallbackReason.none),
    };

    return PlaybackStackSelection(
      requestedAudioEngine: parsedAudio,
      requestedSystemMediaEdge: parsedSystem,
      effectiveAudioEngine: parsedAudio,
      effectiveSystemMediaEdge: effectiveSystemEdge,
      fallbackReason: fallbackReason,
    );
  }
}
