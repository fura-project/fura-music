import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/playback/playback_stack_experiment.dart';

@visibleForTesting
String startupPhaseDiagnostic({
  required String phase,
  required String outcome,
}) => 'FURA_DIAGNOSTIC startup phase=$phase outcome=$outcome';

void logStartupPhase({required String phase, required String outcome}) {
  // Android logcat must work without a DevTools/VM-service attachment, also
  // in Release. Emit only the existing coarse locally constructed fields.
  debugPrint(startupPhaseDiagnostic(phase: phase, outcome: outcome));
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
  debugPrint(
    playbackStackSelectedDiagnostic(selection: selection, platform: platform),
  );
}
