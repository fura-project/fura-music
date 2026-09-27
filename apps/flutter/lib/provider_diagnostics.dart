import 'package:flutter/foundation.dart';

const _providerDiagnosticSetting = String.fromEnvironment(
  'FURA_PROVIDER_DIAGNOSTIC',
);

/// Development-only, coarse Provider request-cost diagnostics.
///
/// Enable with `--dart-define=FURA_PROVIDER_DIAGNOSTIC=1` (or `true`). The
/// typed API deliberately has no identity, query, URL, credential or response
/// fields, so callers cannot accidentally include account or catalog content.
bool get providerDiagnosticsEnabled =>
    _providerDiagnosticSetting == '1' ||
    _providerDiagnosticSetting.toLowerCase() == 'true';

enum ProviderDiagnosticOperation {
  trackMembership,
  albumMembership,
  trackLikeMutation,
  albumFavoriteMutation,
}

enum ProviderDiagnosticPhase { resolve, preload, refresh, request, bridge }

enum ProviderDiagnosticCache { hit, miss }

enum ProviderDiagnosticOutcome {
  success,
  paused,
  confirmed,
  outcomeUnknown,
  definitiveFailure,
  unavailable,
  alreadyRunning,
}

enum ProviderDiagnosticGeneration { current, replaced }

@visibleForTesting
String formatProviderDiagnostic({
  required String providerId,
  required ProviderDiagnosticOperation operation,
  required ProviderDiagnosticPhase phase,
  ProviderDiagnosticCache? cache,
  bool? singleFlightJoin,
  int? networkRequests,
  ProviderDiagnosticOutcome? outcome,
  ProviderDiagnosticGeneration? generation,
}) {
  assert(networkRequests == null || networkRequests >= 0);
  final fields = <String>[
    'FURA_PROVIDER_DIAGNOSTIC',
    'provider=$providerId',
    'operation=${operation.name}',
    'phase=${phase.name}',
    if (cache != null) 'cache=${cache.name}',
    if (singleFlightJoin != null) 'single_flight_join=$singleFlightJoin',
    if (networkRequests != null) 'network_requests=$networkRequests',
    if (outcome != null) 'outcome=${outcome.name}',
    if (generation != null) 'generation=${generation.name}',
  ];
  return fields.join(' ');
}

void logProviderDiagnostic({
  required String providerId,
  required ProviderDiagnosticOperation operation,
  required ProviderDiagnosticPhase phase,
  ProviderDiagnosticCache? cache,
  bool? singleFlightJoin,
  int? networkRequests,
  ProviderDiagnosticOutcome? outcome,
  ProviderDiagnosticGeneration? generation,
}) {
  if (!providerDiagnosticsEnabled) return;
  debugPrint(
    formatProviderDiagnostic(
      providerId: providerId,
      operation: operation,
      phase: phase,
      cache: cache,
      singleFlightJoin: singleFlightJoin,
      networkRequests: networkRequests,
      outcome: outcome,
      generation: generation,
    ),
  );
}
