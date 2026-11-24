import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(messages, hasLength(1));
    expect(
      messages.first,
      'FURA_DIAGNOSTIC startup phase=run_app outcome=started',
    );
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
}
