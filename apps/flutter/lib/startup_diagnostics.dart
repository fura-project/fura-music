import 'package:flutter/foundation.dart';

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
