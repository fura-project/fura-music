import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/playback_stack_experiment.dart';
import 'package:flutterustmusic/startup_diagnostics.dart';

void main() {
  test('startup phase diagnostics remain coarse and source-free', () {
    expect(
      startupPhaseDiagnostic(
        phase: 'media_kit_global_init',
        outcome: 'started',
      ),
      'FURA_DIAGNOSTIC startup '
      'phase=media_kit_global_init outcome=started',
    );
  });

  test('selected-stack diagnostic precedes runtime construction details', () {
    final selection = PlaybackStackSelection.resolve(
      audioEngineValue: PlaybackStackSelection.defaultRequestedAudioEngineValue,
      systemMediaValue: PlaybackStackSelection.defaultRequestedSystemMediaValue,
      platform: TargetPlatform.android,
    );

    final diagnostic = playbackStackSelectedDiagnostic(
      selection: selection,
      platform: TargetPlatform.android,
    );

    expect(diagnostic, contains('requestedEngine=mediaKit'));
    expect(diagnostic, contains('requestedSystemEdge=flutterMediaSession'));
    expect(diagnostic, contains('effectiveEngine=mediaKit'));
    expect(diagnostic, contains('effectiveSystemEdge=flutterMediaSession'));
    expect(diagnostic, contains('platform=android'));
    expect(diagnostic, contains('fallback=false'));
    expect(diagnostic, contains('fallbackReason=none'));
    expect(diagnostic, isNot(contains('http')));
    expect(diagnostic, isNot(contains('cookie')));
    expect(diagnostic, isNot(contains('track')));
  });
}
