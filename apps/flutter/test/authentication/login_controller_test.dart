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

  test('external QR handoff keeps the active polling session alive', () async {
    final session = _FakeLoginSession();
    final confirmationUri = Uri.parse(
      'https://music.163.com/st/platform/scanlogin?'
      'codekey=synthetic-key&chainId=synthetic-chain&'
      'hdw_device=web&hdw_appid=web&hitExp=1',
    );
    final launched = <Uri>[];
    final controller = LoginController(
      _FakeGateway.immediate(
        _successfulStart(session, externalConfirmationUri: confirmationUri),
      ),
      externalLoginUriLauncher: (uri) async {
        launched.add(uri);
        return true;
      },
    );

    await controller.startQr(LoginQrChannel.qq);
    expect(controller.canOpenQrExternally, isTrue);

    expect(await controller.openQrChallengeExternally(), isTrue);

    expect(launched, [confirmationUri]);
    expect(session.cancelCalls, 0);
    expect(session.advanceCalls, 1);
    expect(controller.stage, LoginStage.waitingForScan);
    expect(controller.externalQrLaunchFailed, isFalse);
    controller.dispose();
  });

  test(
    'late external QR handoff cannot revive a cancelled challenge',
    () async {
      final session = _FakeLoginSession();
      final confirmationUri = Uri.parse(
        'https://music.163.com/st/platform/scanlogin?'
        'codekey=synthetic-key&chainId=synthetic-chain&'
        'hdw_device=web&hdw_appid=web&hitExp=1',
      );
      final launch = Completer<bool>();
      final controller = LoginController(
        _FakeGateway.immediate(
          _successfulStart(session, externalConfirmationUri: confirmationUri),
        ),
        externalLoginUriLauncher: (_) => launch.future,
      );

      await controller.startQr(LoginQrChannel.qq);
      final opening = controller.openQrChallengeExternally();
      expect(controller.openingQrExternally, isTrue);

      controller.cancel();
      launch.complete(true);
      expect(await opening, isTrue);

      expect(controller.stage, LoginStage.idle);
      expect(controller.openingQrExternally, isFalse);
      expect(controller.externalQrLaunchFailed, isFalse);
      controller.dispose();
    },
  );

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
    'paces QR polling for providers with immediate status endpoints',
    () async {
      final session = _FakeLoginSession();
      final gateway = _PacedFakeGateway(
        _successfulStart(session),
        const Duration(seconds: 2),
      );
      final delays = <Duration>[];
      final delayGates = <Completer<void>>[];
      final controller = LoginController(
        gateway,
        delay: (duration) {
          delays.add(duration);
          final gate = Completer<void>();
          delayGates.add(gate);
          return gate.future;
        },
      );

      await controller.start();
      expect(session.advanceCalls, 1);

      session.completeNext(
        const LoginUpdate(
          progress: LoginProgress.waitingForScan,
          sessionActive: true,
        ),
      );
      await pumpEventQueue();
      expect(delays, [const Duration(seconds: 2)]);
      expect(session.advanceCalls, 1);

      delayGates.single.complete();
      await pumpEventQueue();
      expect(session.advanceCalls, 2);

      controller.dispose();
    },
  );

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

  test('keeps provider security verification distinct and terminal', () async {
    final session = _FakeLoginSession();
    final gateway = _FakeGateway.immediate(_successfulStart(session));
    final controller = LoginController(
      gateway,
      networkRetryDelay: Duration.zero,
    );

    await controller.start();
    session.completeNext(
      const LoginUpdate(
        failure: LoginFailure.securityVerificationRequired,
        sessionActive: false,
      ),
    );
    await pumpEventQueue();

    expect(controller.stage, LoginStage.error);
    expect(controller.failure, LoginFailure.securityVerificationRequired);
    expect(controller.canRetry, isFalse);

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

  test(
    'sign out keeps a failed browser cleanup explicit and retryable',
    () async {
      final gateway = _FakeGateway.immediate(
        _successfulStart(_FakeLoginSession()),
        authenticated: true,
        signOutResults: [
          CredentialSignOutResult.browserCleanupFailed,
          CredentialSignOutResult.signedOut,
        ],
      );
      final controller = LoginController(gateway);

      expect(
        await controller.signOut(),
        CredentialSignOutResult.browserCleanupFailed,
      );
      expect(controller.stage, LoginStage.signOutBrowserCleanupFailed);
      expect(controller.canRetrySignOut, isTrue);

      expect(await controller.signOut(), CredentialSignOutResult.signedOut);
      expect(controller.stage, LoginStage.idle);
      expect(controller.canRetrySignOut, isFalse);
      expect(gateway.signOutCalls, 2);
    },
  );

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

  test(
    'phone-code authentication persists only after provider success',
    () async {
      final gateway = _SmsFakeGateway(
        codeRequestResults: const [SmsAuthenticationOutcome(success: true)],
        loginResults: const [SmsAuthenticationOutcome(success: true)],
      );
      final controller = LoginController(gateway);

      expect(controller.supportsSmsLogin, isTrue);
      controller.showSmsLogin();
      expect(controller.smsStage, SmsLoginStage.ready);

      await controller.requestSmsCode(countryCode: '86', phone: '00000000000');
      expect(gateway.phoneRequests, [('86', '00000000000')]);
      expect(controller.smsStage, SmsLoginStage.codeSent);
      expect(controller.smsCodeRequested, isTrue);
      expect(controller.stage, LoginStage.idle);

      await controller.authenticateSmsCode('000000');
      expect(gateway.codes, ['000000']);
      expect(controller.stage, LoginStage.authenticated);
      expect(controller.credentialSaveState, CredentialSaveState.saved);
      expect(gateway.persistCalls, 1);

      controller.dispose();
    },
  );

  test('a rejected phone code remains retryable in the same session', () async {
    final gateway = _SmsFakeGateway(
      codeRequestResults: const [SmsAuthenticationOutcome(success: true)],
      loginResults: const [
        SmsAuthenticationOutcome(
          success: false,
          failure: SmsAuthenticationFailure.codeRejected,
        ),
        SmsAuthenticationOutcome(success: true),
      ],
    );
    final controller = LoginController(gateway)..showSmsLogin();

    await controller.requestSmsCode(countryCode: '86', phone: '00000000000');
    await controller.authenticateSmsCode('000001');

    expect(controller.smsStage, SmsLoginStage.error);
    expect(controller.smsFailure, SmsAuthenticationFailure.codeRejected);
    expect(controller.smsCodeRequested, isTrue);
    expect(gateway.persistCalls, 0);

    await controller.authenticateSmsCode('000002');
    expect(gateway.codes, ['000001', '000002']);
    expect(controller.stage, LoginStage.authenticated);
    expect(gateway.persistCalls, 1);

    controller.dispose();
  });

  test('cancel clears a completed provider-owned phone code session', () async {
    final gateway = _SmsFakeGateway(
      codeRequestResults: const [SmsAuthenticationOutcome(success: true)],
    );
    final controller = LoginController(gateway)..showSmsLogin();

    await controller.requestSmsCode(countryCode: '86', phone: '00000000000');
    expect(controller.smsCodeRequested, isTrue);

    controller.cancel();

    expect(gateway.sessionCancelCalls, 1);
    expect(controller.smsStage, SmsLoginStage.hidden);
    expect(controller.smsCodeRequested, isFalse);
    controller.dispose();
    expect(gateway.sessionCancelCalls, 1);
  });

  test(
    'phone security verification is distinct and installs nothing',
    () async {
      final gateway = _SmsFakeGateway(
        codeRequestResults: const [
          SmsAuthenticationOutcome(
            success: false,
            failure: SmsAuthenticationFailure.securityVerificationRequired,
          ),
        ],
      );
      final controller = LoginController(gateway)..showSmsLogin();

      await controller.requestSmsCode(countryCode: '86', phone: '00000000000');

      expect(controller.smsStage, SmsLoginStage.error);
      expect(
        controller.smsFailure,
        SmsAuthenticationFailure.securityVerificationRequired,
      );
      expect(controller.smsCodeRequested, isFalse);
      expect(gateway.persistCalls, 0);

      controller.dispose();
    },
  );

  test('dispose cancels phone code request and ignores late success', () async {
    final pending = Completer<SmsAuthenticationOutcome>();
    final gateway = _SmsFakeGateway(codeRequestResults: [pending.future]);
    final controller = LoginController(gateway)..showSmsLogin();

    final request = controller.requestSmsCode(
      countryCode: '86',
      phone: '00000000000',
    );
    expect(controller.smsStage, SmsLoginStage.sendingCode);
    controller.dispose();
    expect(gateway.codeRequestOperations.single.cancelCalls, 1);

    pending.complete(const SmsAuthenticationOutcome(success: true));
    await request;
    expect(controller.smsStage, SmsLoginStage.hidden);
    expect(controller.stage, LoginStage.idle);
    expect(gateway.persistCalls, 0);
  });

  test('official website login persists only after verified success', () async {
    final gateway = _OfficialWebFakeGateway(
      outcomes: const [OfficialWebAuthenticationOutcome(authenticated: true)],
    );
    final controller = LoginController(gateway);

    expect(controller.supportsOfficialWebLogin, isTrue);
    final login = controller.startOfficialWebLogin();
    expect(controller.stage, LoginStage.officialWebLogin);
    await login;

    expect(controller.stage, LoginStage.authenticated);
    expect(controller.credentialSaveState, CredentialSaveState.saved);
    expect(gateway.persistCalls, 1);
    controller.dispose();
  });

  test('official website verification failure remains explicit', () async {
    final gateway = _OfficialWebFakeGateway(
      outcomes: const [
        OfficialWebAuthenticationOutcome(
          authenticated: false,
          failure: OfficialWebAuthenticationFailure.rejected,
        ),
      ],
    );
    final controller = LoginController(gateway);

    await controller.startOfficialWebLogin();

    expect(controller.stage, LoginStage.officialWebError);
    expect(
      controller.officialWebFailure,
      OfficialWebAuthenticationFailure.rejected,
    );
    expect(gateway.persistCalls, 0);
    controller.dispose();
  });

  test(
    'official website transient verification retries retained candidate',
    () async {
      final gateway = _OfficialWebFakeGateway(
        outcomes: const [
          OfficialWebAuthenticationOutcome(
            authenticated: false,
            failure: OfficialWebAuthenticationFailure.network,
          ),
        ],
      );
      final controller = LoginController(gateway);
      await controller.startOfficialWebLogin();

      expect(controller.canRetryOfficialWebVerification, isTrue);
      final retry = controller.retryOfficialWebVerification();
      expect(controller.stage, LoginStage.officialWebLogin);
      gateway.completeVerification(
        0,
        CredentialVerificationResult.authenticated,
      );
      await retry;

      expect(controller.stage, LoginStage.authenticated);
      expect(gateway.persistCalls, 1);
      expect(gateway.officialOperations, hasLength(1));
      controller.dispose();
    },
  );

  test('cancel suppresses a late official website login success', () async {
    final pending = Completer<OfficialWebAuthenticationOutcome>();
    final gateway = _OfficialWebFakeGateway(outcomes: [pending.future]);
    final controller = LoginController(gateway);

    final login = controller.startOfficialWebLogin();
    expect(controller.stage, LoginStage.officialWebLogin);
    controller.cancel();
    expect(gateway.officialOperations.single.cancelCalls, 1);
    pending.complete(
      const OfficialWebAuthenticationOutcome(authenticated: true),
    );
    await login;

    expect(controller.stage, LoginStage.idle);
    expect(gateway.persistCalls, 0);
    controller.dispose();
  });
}

LoginStart _successfulStart(
  _FakeLoginSession session, {
  Uri? externalConfirmationUri,
}) => LoginStart(
  session: session,
  challenge: LoginChallenge(
    imageFormat: LoginImageFormat.png,
    imageBytes: Uint8List.fromList(<int>[137, 80, 78, 71]),
    externalConfirmationUri: externalConfirmationUri,
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

class _PacedFakeGateway extends _FakeGateway implements QrLoginPollingPolicy {
  _PacedFakeGateway(super.result, this.minimumQrPollInterval)
    : super.immediate();

  @override
  final Duration minimumQrPollInterval;
}

class _SmsFakeGateway extends _FakeGateway implements SmsAuthenticationGateway {
  _SmsFakeGateway({
    List<FutureOr<SmsAuthenticationOutcome>> codeRequestResults = const [],
    List<FutureOr<SmsAuthenticationOutcome>> loginResults = const [],
  }) : _codeRequestResults = List.of(codeRequestResults),
       _loginResults = List.of(loginResults),
       super.immediate(_successfulStart(_FakeLoginSession()));

  final List<FutureOr<SmsAuthenticationOutcome>> _codeRequestResults;
  final List<FutureOr<SmsAuthenticationOutcome>> _loginResults;
  final List<(String, String)> phoneRequests = [];
  final List<String> codes = [];
  final List<_FakeSmsCodeRequestOperation> codeRequestOperations = [];
  final List<_FakeSmsLoginOperation> loginOperations = [];
  int sessionCancelCalls = 0;

  @override
  bool cancelSmsAuthentication() {
    sessionCancelCalls += 1;
    return true;
  }

  @override
  SmsCodeRequestOperation beginSmsCodeRequest({
    required String countryCode,
    required String phone,
  }) {
    phoneRequests.add((countryCode, phone));
    final operation = _FakeSmsCodeRequestOperation(
      Future<SmsAuthenticationOutcome>.value(_codeRequestResults.removeAt(0)),
    );
    codeRequestOperations.add(operation);
    return operation;
  }

  @override
  SmsLoginOperation beginSmsLogin({required String code}) {
    codes.add(code);
    final operation = _FakeSmsLoginOperation(
      Future<SmsAuthenticationOutcome>.value(_loginResults.removeAt(0)),
    );
    loginOperations.add(operation);
    return operation;
  }
}

class _OfficialWebFakeGateway extends _FakeGateway
    implements OfficialWebAuthenticationGateway {
  _OfficialWebFakeGateway({
    required List<FutureOr<OfficialWebAuthenticationOutcome>> outcomes,
  }) : _outcomes = List.of(outcomes),
       super.immediate(_successfulStart(_FakeLoginSession()));

  final List<FutureOr<OfficialWebAuthenticationOutcome>> _outcomes;
  final List<_FakeOfficialWebAuthenticationOperation> officialOperations = [];

  @override
  bool get supportsOfficialWebLogin => true;

  @override
  OfficialWebAuthenticationOperation beginOfficialWebLogin() {
    final operation = _FakeOfficialWebAuthenticationOperation(
      Future<OfficialWebAuthenticationOutcome>.value(_outcomes.removeAt(0)),
    );
    officialOperations.add(operation);
    return operation;
  }
}

class _FakeOfficialWebAuthenticationOperation
    implements OfficialWebAuthenticationOperation {
  _FakeOfficialWebAuthenticationOperation(this._result);

  final Future<OfficialWebAuthenticationOutcome> _result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<OfficialWebAuthenticationOutcome> run() => _result;
}

class _FakeSmsCodeRequestOperation implements SmsCodeRequestOperation {
  _FakeSmsCodeRequestOperation(this._result);

  final Future<SmsAuthenticationOutcome> _result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<SmsAuthenticationOutcome> run() => _result;
}

class _FakeSmsLoginOperation implements SmsLoginOperation {
  _FakeSmsLoginOperation(this._result);

  final Future<SmsAuthenticationOutcome> _result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<SmsAuthenticationOutcome> run() => _result;
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
