import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/login_controller.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';

void main() {
  test('forwards the selected QQ QR channel', () async {
    final session = _FakeLoginSession();
    final gateway = _FakeGateway.immediate(_successfulStart(session));
    final controller = LoginController(gateway);

    await controller.startQr(LoginQrChannel.qq);

    expect(gateway.qrChannels, [LoginQrChannel.qq]);
    expect(controller.qrChannel, LoginQrChannel.qq);
    expect(controller.stage, LoginStage.waitingForScan);
    controller.dispose();
  });

  test('discovers masked desktop QQ accounts only when enabled', () async {
    final quickSession = _FakeDesktopQuickLoginSession();
    final gateway = _FakeGateway.immediate(
      _successfulStart(_FakeLoginSession()),
      desktopQuickStart: DesktopQuickLoginStart(
        session: quickSession,
        accounts: const [
          DesktopQuickLoginAccount(
            selectionId: 0,
            displayName: 'Synthetic listener',
            accountHint: '21••••90',
          ),
        ],
      ),
    );
    final controller = LoginController(gateway, desktopQuickLoginEnabled: true);

    await controller.loadDesktopQuickAccounts();

    expect(controller.desktopQuickStage, DesktopQuickLoginStage.ready);
    expect(controller.desktopQuickAccounts.single.accountHint, '21••••90');
    expect(controller.canAuthorizeDesktopQuickAccount, isTrue);
    controller.dispose();
    expect(quickSession.cancelCalls, 1);
  });

  test(
    'desktop QQ quick authorization persists the installed credential',
    () async {
      final quickSession = _FakeDesktopQuickLoginSession(
        updates: const [
          DesktopQuickLoginUpdate(authenticated: true, sessionActive: false),
        ],
      );
      final gateway = _FakeGateway.immediate(
        _successfulStart(_FakeLoginSession()),
        desktopQuickStart: DesktopQuickLoginStart(
          session: quickSession,
          accounts: const [
            DesktopQuickLoginAccount(
              selectionId: 3,
              displayName: 'Synthetic listener',
              accountHint: '21••••90',
            ),
          ],
        ),
      );
      final controller = LoginController(
        gateway,
        desktopQuickLoginEnabled: true,
      );
      await controller.loadDesktopQuickAccounts();

      await controller.authorizeDesktopQuickAccount(3);

      expect(quickSession.selections, [3]);
      expect(controller.stage, LoginStage.authenticated);
      expect(controller.credentialSaveState, CredentialSaveState.saved);
      expect(gateway.persistCalls, 1);
      controller.dispose();
    },
  );

  test(
    'desktop QQ discovery keeps unavailable client separate from QR login',
    () async {
      final gateway = _FakeGateway.immediate(
        _successfulStart(_FakeLoginSession()),
        desktopQuickStart: const DesktopQuickLoginStart(
          failure: DesktopQuickLoginFailure.clientUnavailable,
        ),
      );
      final controller = LoginController(
        gateway,
        desktopQuickLoginEnabled: true,
      );

      await controller.loadDesktopQuickAccounts();

      expect(controller.desktopQuickStage, DesktopQuickLoginStage.error);
      expect(
        controller.desktopQuickFailure,
        DesktopQuickLoginFailure.clientUnavailable,
      );
      expect(controller.stage, LoginStage.idle);
      controller.dispose();
    },
  );

  test('maps waiting, scanned, and authenticated updates in order', () async {
    final session = _FakeLoginSession();
    final gateway = _FakeGateway.immediate(_successfulStart(session));
    final controller = LoginController(
      gateway,
      networkRetryDelay: Duration.zero,
    );

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
    expect(controller.credentialSaveState, CredentialSaveState.saved);
    expect(gateway.persistCalls, 1);

    controller.dispose();
  });

  test(
    'dispose cancels an active session and suppresses its late result',
    () async {
      final session = _FakeLoginSession();
      final gateway = _FakeGateway.immediate(_successfulStart(session));
      final controller = LoginController(
        gateway,
        networkRetryDelay: Duration.zero,
      );

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

  test('keeps the session authenticated when secure storage fails', () async {
    final session = _FakeLoginSession();
    final gateway = _FakeGateway.immediate(
      _successfulStart(session),
      persistenceResult: CredentialPersistenceResult.storageUnavailable,
    );
    final controller = LoginController(
      gateway,
      networkRetryDelay: Duration.zero,
    );

    await controller.start();
    session.completeNext(
      const LoginUpdate(
        progress: LoginProgress.authenticated,
        sessionActive: false,
      ),
    );
    await pumpEventQueue();

    expect(controller.stage, LoginStage.authenticated);
    expect(controller.credentialSaveState, CredentialSaveState.failed);
    expect(gateway.persistCalls, 1);

    controller.dispose();
  });

  test('notifies listeners when a session reaches a terminal state', () async {
    final session = _FakeLoginSession();
    final gateway = _FakeGateway.immediate(_successfulStart(session));
    final controller = LoginController(
      gateway,
      networkRetryDelay: Duration.zero,
    );
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    await controller.start();
    final beforeTerminalUpdate = notifications;
    session.completeNext(
      const LoginUpdate(progress: LoginProgress.expired, sessionActive: false),
    );
    await pumpEventQueue();

    expect(controller.stage, LoginStage.expired);
    expect(notifications, greaterThan(beforeTerminalUpdate));

    controller.dispose();
  });

  test(
    'restart cancels a late session returned by the superseded start',
    () async {
      final gateway = _FakeGateway.pending();
      final controller = LoginController(
        gateway,
        networkRetryDelay: Duration.zero,
      );
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
      final controller = LoginController(
        gateway,
        networkRetryDelay: Duration.zero,
      );
      final lateSession = _FakeLoginSession();

      final start = controller.start();
      controller.dispose();
      expect(gateway.operations.single.cancelCalls, 1);

      gateway.completeStart(0, _successfulStart(lateSession));
      await start;
      expect(lateSession.cancelCalls, 1);
    },
  );

  test('maps each non-authenticated startup restore outcome truthfully', () {
    final cases = <CredentialRestoreResult, LoginStage>{
      CredentialRestoreResult.signedOut: LoginStage.idle,
      CredentialRestoreResult.verificationRequired:
          LoginStage.verificationRequired,
      CredentialRestoreResult.locallyExpired:
          LoginStage.storedCredentialExpired,
      CredentialRestoreResult.invalidStoredCredential: LoginStage.restoreError,
      CredentialRestoreResult.unsupportedStoredCredential:
          LoginStage.restoreError,
      CredentialRestoreResult.storageUnavailable: LoginStage.restoreError,
      CredentialRestoreResult.coreUnavailable: LoginStage.restoreError,
    };

    for (final MapEntry(key: result, value: expectedStage) in cases.entries) {
      final session = _FakeLoginSession();
      final gateway = _FakeGateway.immediate(_successfulStart(session));
      final controller = LoginController(
        gateway,
        networkRetryDelay: Duration.zero,
        initialCredentialRestore: result,
      );

      expect(controller.stage, expectedStage, reason: result.name);
      expect(controller.credentialRestoreResult, result);

      controller.dispose();
    }
  });

  test('promotes a server-verified restored credential', () async {
    final session = _FakeLoginSession();
    final gateway = _FakeGateway.immediate(_successfulStart(session));
    final controller = LoginController(
      gateway,
      networkRetryDelay: Duration.zero,
      initialCredentialRestore: CredentialRestoreResult.verificationRequired,
    );

    final verification = controller.verifyRestoredCredential();
    expect(controller.stage, LoginStage.verifyingStoredCredential);
    gateway.completeVerification(0, CredentialVerificationResult.authenticated);
    await verification;

    expect(controller.stage, LoginStage.authenticated);
    expect(controller.credentialSaveState, CredentialSaveState.saved);
    expect(
      controller.credentialVerificationResult,
      CredentialVerificationResult.authenticated,
    );

    controller.dispose();
  });

  test('keeps a transient verification failure retryable', () async {
    final session = _FakeLoginSession();
    final gateway = _FakeGateway.immediate(_successfulStart(session));
    final controller = LoginController(
      gateway,
      networkRetryDelay: Duration.zero,
      initialCredentialRestore: CredentialRestoreResult.verificationRequired,
    );

    final first = controller.verifyRestoredCredential();
    gateway.completeVerification(0, CredentialVerificationResult.network);
    await first;
    expect(controller.stage, LoginStage.verificationError);
    expect(controller.canRetryCredentialVerification, isTrue);
    expect(
      controller.credentialRestoreResult,
      CredentialRestoreResult.verificationRequired,
    );

    final retry = controller.verifyRestoredCredential();
    gateway.completeVerification(1, CredentialVerificationResult.authenticated);
    await retry;
    expect(controller.stage, LoginStage.authenticated);

    controller.dispose();
  });

  test('maps an explicitly rejected restored credential separately', () async {
    final session = _FakeLoginSession();
    final gateway = _FakeGateway.immediate(_successfulStart(session));
    final controller = LoginController(
      gateway,
      networkRetryDelay: Duration.zero,
      initialCredentialRestore: CredentialRestoreResult.verificationRequired,
    );

    final verification = controller.verifyRestoredCredential();
    gateway.completeVerification(0, CredentialVerificationResult.rejected);
    await verification;

    expect(controller.stage, LoginStage.credentialRejected);
    expect(controller.canRetryCredentialVerification, isFalse);

    controller.dispose();
  });

  test('starting QR login cancels and suppresses late verification', () async {
    final session = _FakeLoginSession();
    final gateway = _FakeGateway.immediate(_successfulStart(session));
    final controller = LoginController(
      gateway,
      networkRetryDelay: Duration.zero,
      initialCredentialRestore: CredentialRestoreResult.verificationRequired,
    );

    final verification = controller.verifyRestoredCredential();
    await controller.start();
    expect(gateway.verificationOperations.single.cancelCalls, 1);
    expect(controller.stage, LoginStage.waitingForScan);

    gateway.completeVerification(0, CredentialVerificationResult.authenticated);
    await verification;
    expect(controller.stage, LoginStage.waitingForScan);

    controller.dispose();
  });

  test('dispose cancels and suppresses late credential verification', () async {
    final session = _FakeLoginSession();
    final gateway = _FakeGateway.immediate(_successfulStart(session));
    final controller = LoginController(
      gateway,
      networkRetryDelay: Duration.zero,
      initialCredentialRestore: CredentialRestoreResult.verificationRequired,
    );

    final verification = controller.verifyRestoredCredential();
    controller.dispose();
    expect(gateway.verificationOperations.single.cancelCalls, 1);

    gateway.completeVerification(0, CredentialVerificationResult.authenticated);
    await verification;
    expect(controller.stage, LoginStage.verifyingStoredCredential);
  });

  test('sign out reaches idle only after core and vault success', () async {
    final gateway = _FakeGateway.immediate(
      _successfulStart(_FakeLoginSession()),
      authenticated: true,
    );
    final controller = LoginController(gateway);

    expect(controller.stage, LoginStage.authenticated);
    expect(await controller.signOut(), CredentialSignOutResult.signedOut);
    expect(controller.stage, LoginStage.idle);
    expect(gateway.signOutCalls, 1);
  });

  test('sign out keeps a failed vault cleanup retryable', () async {
    final gateway = _FakeGateway.immediate(
      _successfulStart(_FakeLoginSession()),
      authenticated: true,
      signOutResults: [
        CredentialSignOutResult.storageCleanupFailed,
        CredentialSignOutResult.signedOut,
      ],
    );
    final controller = LoginController(gateway);

    expect(
      await controller.signOut(),
      CredentialSignOutResult.storageCleanupFailed,
    );
    expect(controller.stage, LoginStage.signOutStorageCleanupFailed);
    expect(controller.canRetrySignOut, isTrue);

    expect(await controller.signOut(), CredentialSignOutResult.signedOut);
    expect(controller.stage, LoginStage.idle);
    expect(controller.canRetrySignOut, isFalse);
    expect(gateway.signOutCalls, 2);
  });

  test('core sign-out failure keeps the authenticated surface', () async {
    final gateway = _FakeGateway.immediate(
      _successfulStart(_FakeLoginSession()),
      authenticated: true,
      signOutResults: [CredentialSignOutResult.coreUnavailable],
    );
    final controller = LoginController(gateway);

    expect(await controller.signOut(), CredentialSignOutResult.coreUnavailable);
    expect(controller.stage, LoginStage.authenticated);
    expect(gateway.signOutCalls, 1);
  });

  test('concurrent sign out callers share one in-flight operation', () async {
    final pending = Completer<CredentialSignOutResult>();
    final gateway = _FakeGateway.immediate(
      _successfulStart(_FakeLoginSession()),
      authenticated: true,
      signOutResults: [pending.future],
    );
    final controller = LoginController(gateway);

    final first = controller.signOut();
    final second = controller.signOut();
    expect(identical(first, second), isTrue);
    expect(controller.isSigningOut, isTrue);
    expect(gateway.signOutCalls, 1);

    pending.complete(CredentialSignOutResult.storageCleanupFailed);
    expect(await first, CredentialSignOutResult.storageCleanupFailed);
    expect(controller.isSigningOut, isFalse);
    expect(controller.canRetrySignOut, isTrue);
  });

  test(
    'unexpected gateway sign-out failure restores authenticated state',
    () async {
      final pending = Completer<CredentialSignOutResult>();
      final gateway = _FakeGateway.immediate(
        _successfulStart(_FakeLoginSession()),
        authenticated: true,
        signOutResults: [pending.future],
      );
      final controller = LoginController(gateway);

      final signOut = controller.signOut();
      pending.completeError(StateError('synthetic gateway failure'));

      expect(await signOut, CredentialSignOutResult.coreUnavailable);
      expect(controller.stage, LoginStage.authenticated);
      expect(controller.isSigningOut, isFalse);
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

class _FakeGateway
    implements
        QqMusicAuthenticationGateway,
        MultiMethodQqMusicAuthenticationGateway,
        DesktopQuickQqMusicAuthenticationGateway {
  _FakeGateway.immediate(
    LoginStart result, {
    this.persistenceResult = CredentialPersistenceResult.stored,
    this.authenticated = false,
    this.desktopQuickStart = const DesktopQuickLoginStart(
      failure: DesktopQuickLoginFailure.clientUnavailable,
    ),
    List<FutureOr<CredentialSignOutResult>> signOutResults = const [
      CredentialSignOutResult.signedOut,
    ],
  }) : _immediateResult = result,
       _pendingStarts = null,
       _signOutResults = List.of(signOutResults);

  _FakeGateway.pending()
    : persistenceResult = CredentialPersistenceResult.stored,
      authenticated = false,
      desktopQuickStart = const DesktopQuickLoginStart(
        failure: DesktopQuickLoginFailure.clientUnavailable,
      ),
      _immediateResult = null,
      _pendingStarts = <Completer<LoginStart>>[],
      _signOutResults = [CredentialSignOutResult.signedOut];

  final LoginStart? _immediateResult;
  final List<Completer<LoginStart>>? _pendingStarts;
  final CredentialPersistenceResult persistenceResult;
  bool authenticated;
  final DesktopQuickLoginStart desktopQuickStart;
  final List<FutureOr<CredentialSignOutResult>> _signOutResults;
  final List<_FakeStartOperation> operations = <_FakeStartOperation>[];
  final List<Completer<CredentialVerificationResult>> _pendingVerifications =
      <Completer<CredentialVerificationResult>>[];
  final List<_FakeVerificationOperation> verificationOperations =
      <_FakeVerificationOperation>[];
  final List<LoginQrChannel> qrChannels = <LoginQrChannel>[];
  int persistCalls = 0;
  int signOutCalls = 0;

  @override
  DesktopQuickLoginStartOperation beginDesktopQuickLoginStart() =>
      _FakeDesktopQuickLoginStartOperation(desktopQuickStart);

  @override
  bool get hasAuthenticatedCredential => authenticated;

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

  @override
  LoginStartOperation beginQrStart(LoginQrChannel channel) {
    qrChannels.add(channel);
    return beginStart();
  }

  @override
  CredentialVerificationOperation beginCredentialVerification() {
    final completer = Completer<CredentialVerificationResult>();
    _pendingVerifications.add(completer);
    final operation = _FakeVerificationOperation(completer.future);
    verificationOperations.add(operation);
    return operation;
  }

  @override
  Future<CredentialPersistenceResult> persistAuthenticatedCredential() async {
    persistCalls += 1;
    return persistenceResult;
  }

  @override
  Future<CredentialRestoreResult> restoreCredential() async =>
      CredentialRestoreResult.signedOut;

  @override
  Future<CredentialSignOutResult> signOut() async {
    final result = await _signOutResults[signOutCalls++];
    if (result != CredentialSignOutResult.coreUnavailable) {
      authenticated = false;
    }
    return result;
  }

  void completeStart(int index, LoginStart result) {
    _pendingStarts![index].complete(result);
  }

  void completeVerification(int index, CredentialVerificationResult result) {
    _pendingVerifications[index].complete(result);
  }
}

class _FakeDesktopQuickLoginStartOperation
    implements DesktopQuickLoginStartOperation {
  _FakeDesktopQuickLoginStartOperation(this.result);

  final DesktopQuickLoginStart result;
  bool active = true;

  @override
  bool cancel() {
    final wasActive = active;
    active = false;
    return wasActive;
  }

  @override
  Future<DesktopQuickLoginStart> run() async => result;
}

class _FakeDesktopQuickLoginSession implements DesktopQuickLoginSession {
  _FakeDesktopQuickLoginSession({
    List<DesktopQuickLoginUpdate> updates = const [],
  }) : _updates = List.of(updates);

  final List<DesktopQuickLoginUpdate> _updates;
  final List<int> selections = [];
  int cancelCalls = 0;
  bool active = true;

  @override
  Future<DesktopQuickLoginUpdate> authorize(int selectionId) async {
    selections.add(selectionId);
    final update = _updates.isEmpty
        ? const DesktopQuickLoginUpdate(
            authenticated: false,
            failure: DesktopQuickLoginFailure.invalidResponse,
            sessionActive: false,
          )
        : _updates.removeAt(0);
    active = update.sessionActive;
    return update;
  }

  @override
  bool cancel() {
    cancelCalls += 1;
    final wasActive = active;
    active = false;
    return wasActive;
  }

  @override
  bool get isActive => active;
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

class _FakeVerificationOperation implements CredentialVerificationOperation {
  _FakeVerificationOperation(this._result);

  final Future<CredentialVerificationResult> _result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<CredentialVerificationResult> run() => _result;
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
