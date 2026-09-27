import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/provider_diagnostics.dart';

void main() {
  test('provider diagnostic vocabulary is coarse and content-free', () {
    final line = formatProviderDiagnostic(
      providerId: 'qq-music',
      operation: ProviderDiagnosticOperation.trackMembership,
      phase: ProviderDiagnosticPhase.resolve,
      cache: ProviderDiagnosticCache.hit,
      singleFlightJoin: false,
      networkRequests: 0,
      outcome: ProviderDiagnosticOutcome.success,
      generation: ProviderDiagnosticGeneration.current,
    );

    expect(
      line,
      'FURA_PROVIDER_DIAGNOSTIC provider=qq-music '
      'operation=trackMembership phase=resolve cache=hit '
      'single_flight_join=false network_requests=0 outcome=success '
      'generation=current',
    );
    for (final forbidden in [
      'track_id',
      'album_id',
      'playlist_id',
      'query',
      'title',
      'url',
      'vkey',
      'cookie',
      'token',
      'credential',
    ]) {
      expect(line.toLowerCase(), isNot(contains(forbidden)));
    }
  });
}
