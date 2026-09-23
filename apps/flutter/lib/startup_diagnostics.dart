import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/playback/playback_stack_experiment.dart';

const _startupLogName = 'fura_music.startup';

@visibleForTesting
String startupPhaseDiagnostic({
  required String phase,
  required String outcome,
}) => 'FURA_DIAGNOSTIC startup phase=$phase outcome=$outcome';

void logStartupPhase({required String phase, required String outcome}) {
  developer.log(
    startupPhaseDiagnostic(phase: phase, outcome: outcome),
    name: _startupLogName,
  );
}

@visibleForTesting
String playbackStackSelectedDiagnostic({
  required PlaybackStackSelection selection,
  required TargetPlatform platform,
}) =>
    'FURA_DIAGNOSTIC playback_stack_selected '
    'requestedEngine=${selection.requestedAudioEngine.name} '
    'requestedSystemEdge=${selection.requestedSystemMediaEdge.name} '
    'effectiveEngine=${selection.effectiveAudioEngine.name} '
    'effectiveSystemEdge=${selection.effectiveSystemMediaEdge.name} '
    'platform=${platform.name} '
    'fallback=${selection.usedFallback} '
    'fallbackReason=${selection.fallbackReason.diagnosticValue}';

void logPlaybackStackSelected({
  required PlaybackStackSelection selection,
  required TargetPlatform platform,
}) {
  developer.log(
    playbackStackSelectedDiagnostic(selection: selection, platform: platform),
    name: _startupLogName,
  );
}
