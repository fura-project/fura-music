import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/login_controller.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';

void main() {
  test('maps waiting, scanned, and authenticated updates in order', () async {
    final session = _FakeLoginSession();
    final gateway = _FakeGateway.immediate(_successfulStart(session));
    final controller = LoginController(gateway, Duration.zero);

    await controller.start();
    expect(controller.stage, LoginStage.waitingForScan);
    expect(session.advanceCalls, 1);

    session.completeNext(
      const LoginUpdate(
        progress: LoginProgress.waitingForScan,
        sessionActive: true,
      ),
    );
    await pumpEventQueue();
    expect(controller.stage, LoginStage.waitingForScan);
    expect(session.advanceCalls, 2);

    session.completeNext(
      const LoginUpdate(
        progress: LoginProgress.scannedAwaitingConfirmation,
        sessionActive: true,
      ),
    );
    await pumpEventQueue();
    expect(controller.stage, LoginStage.scannedAwaitingConfirmation);
    expect(session.advanceCalls, 3);

    session.completeNext(
      const LoginUpdate(
        progress: LoginProgress.authenticated,
        sessionActive: false,
      ),
    );
    await pumpEventQueue();
    expect(controller.stage, LoginStage.authenticated);
    expect(controller.qrImageBytes, isNull);

    controller.dispose();
  });

  test(
    'dispose cancels an active session and suppresses its late result',
    () async {
      final session = _FakeLoginSession();
      final gateway = _FakeGateway.immediate(_successfulStart(session));
      final controller = LoginController(gateway, Duration.zero);

      await controller.start();
      expect(session.advanceCalls, 1);

      controller.dispose();
      expect(session.cancelCalls, 1);

      session.completeNext(
        const LoginUpdate(
          progress: LoginProgress.authenticated,
          sessionActive: false,
        ),
      );
      await pumpEventQueue();
      expect(controller.stage, LoginStage.waitingForScan);
    },
  );

  test(
    'restart cancels a late session returned by the superseded start',
    () async {
      final gateway = _FakeGateway.pending();
      final controller = LoginController(gateway, Duration.zero);
      final firstSession = _FakeLoginSession();
      final secondSession = _FakeLoginSession();

      final first = controller.start();
      final second = controller.start();
      expect(gateway.operations.first.cancelCalls, 1);
      gateway.completeStart(1, _successfulStart(secondSession));
      await second;
      expect(controller.stage, LoginStage.waitingForScan);

      gateway.completeStart(0, _successfulStart(firstSession));
      await first;
      expect(firstSession.cancelCalls, 1);
      expect(secondSession.cancelCalls, 0);

      controller.dispose();
      expect(secondSession.cancelCalls, 1);
    },
  );

  test(
    'dispose cancels QR creation and cancels a late returned session',
    () async {
      final gateway = _FakeGateway.pending();
      final controller = LoginController(gateway, Duration.zero);
      final lateSession = _FakeLoginSession();

      final start = controller.start();
      controller.dispose();
      expect(gateway.operations.single.cancelCalls, 1);

      gateway.completeStart(0, _successfulStart(lateSession));
      await start;
      expect(lateSession.cancelCalls, 1);
    },
  );
}

LoginStart _successfulStart(_FakeLoginSession session) => LoginStart(
  session: session,
  challenge: LoginChallenge(
    imageFormat: LoginImageFormat.png,
    imageBytes: Uint8List.fromList(<int>[137, 80, 78, 71]),
  ),
);

class _FakeGateway implements QqMusicAuthenticationGateway {
  _FakeGateway.immediate(LoginStart result)
    : _immediateResult = result,
      _pendingStarts = null;

  _FakeGateway.pending()
    : _immediateResult = null,
      _pendingStarts = <Completer<LoginStart>>[];

  final LoginStart? _immediateResult;
  final List<Completer<LoginStart>>? _pendingStarts;
  final List<_FakeStartOperation> operations = <_FakeStartOperation>[];

  @override
  bool get hasAuthenticatedCredential => false;

  @override
  LoginStartOperation beginStart() {
    final immediateResult = _immediateResult;
    if (immediateResult != null) {
      final operation = _FakeStartOperation(
        Future<LoginStart>.value(immediateResult),
      );
      operations.add(operation);
      return operation;
    }
    final completer = Completer<LoginStart>();
    _pendingStarts!.add(completer);
    final operation = _FakeStartOperation(completer.future);
    operations.add(operation);
    return operation;
  }

  void completeStart(int index, LoginStart result) {
    _pendingStarts![index].complete(result);
  }
}

class _FakeStartOperation implements LoginStartOperation {
  _FakeStartOperation(this._result);

  final Future<LoginStart> _result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<LoginStart> run() => _result;
}

class _FakeLoginSession implements LoginSession {
  final List<Completer<LoginUpdate>> _advances = <Completer<LoginUpdate>>[];

  int advanceCalls = 0;
  int cancelCalls = 0;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  Future<LoginUpdate> advance() {
    advanceCalls += 1;
    final completer = Completer<LoginUpdate>();
    _advances.add(completer);
    return completer.future.then((update) {
      _active = update.sessionActive;
      return update;
    });
  }

  @override
  bool cancel() {
    cancelCalls += 1;
    final wasActive = _active;
    _active = false;
    return wasActive;
  }

  void completeNext(LoginUpdate update) {
    _advances.firstWhere((advance) => !advance.isCompleted).complete(update);
  }
}
