import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/playback_stack_experiment.dart';
import 'package:flutterustmusic/startup_diagnostics.dart';

void main() {
  test('startup emitters use the stdout-capable diagnostic sink', () {
    final messages = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = previous);

    logStartupPhase(phase: 'run_app', outcome: 'started');
    logPlaybackStackSelected(
      selection: PlaybackStackSelection.resolve(
        audioEngineValue:
            PlaybackStackSelection.defaultRequestedAudioEngineValue,
        systemMediaValue:
            PlaybackStackSelection.defaultRequestedSystemMediaValue,
        platform: TargetPlatform.android,
      ),
      platform: TargetPlatform.android,
    );

    expect(messages, hasLength(2));
    expect(
      messages.first,
      'FURA_DIAGNOSTIC startup phase=run_app outcome=started',
    );
    expect(
      messages.last,
      startsWith('FURA_DIAGNOSTIC playback_stack_selected '),
    );
    expect(messages.last, contains('effectiveEngine=mediaKit'));
    expect(messages.last, contains('effectiveSystemEdge=flutterMediaSession'));
    expect(messages.join(), isNot(contains('http')));
    expect(messages.join(), isNot(contains('cookie')));
  });

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
