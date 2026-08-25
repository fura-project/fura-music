import 'dart:async';
import 'dart:typed_data';

import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart' as bridge;

enum LoginImageFormat { png, jpeg }

enum LoginProgress {
  waitingForScan,
  scannedAwaitingConfirmation,
  authenticated,
  expired,
  refused,
  timedOut,
}

enum LoginFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  rejected,
  cancelled,
  replaced,
  sessionClosed,
  sessionFinished,
  timedOut,
  tooManyNetworkFailures,
  advanceAlreadyInProgress,
}

enum CredentialPersistenceResult {
  stored,
  noAuthenticatedCredential,
  storageUnavailable,
}

enum CredentialRestoreResult {
  signedOut,
  verificationRequired,
  locallyExpired,
  invalidStoredCredential,
  unsupportedStoredCredential,
  storageUnavailable,
  coreUnavailable,
}

enum CredentialVerificationResult {
  authenticated,
  rejected,
  rejectedStorageCleanupFailed,
  network,
  serviceUnavailable,
  invalidResponse,
  noRestoredCredential,
  replaced,
  coreUnavailable,
}

typedef CredentialRestoreImporter = CredentialRestoreResult Function(
  Uint8List? secretBytes,
);

typedef CredentialVerificationOperationFactory =
    CredentialVerificationOperation Function();

class LoginChallenge {
  const LoginChallenge({required this.imageFormat, required this.imageBytes});

  final LoginImageFormat imageFormat;
  final Uint8List imageBytes;
}

class LoginUpdate {
  const LoginUpdate({this.progress, this.failure, required this.sessionActive});

  final LoginProgress? progress;
  final LoginFailure? failure;
  final bool sessionActive;
}

abstract interface class LoginSession {
  Future<LoginUpdate> advance();
  bool cancel();
  bool get isActive;
}

class LoginStart {
  const LoginStart({this.session, this.challenge, this.failure});

  final LoginSession? session;
  final LoginChallenge? challenge;
  final LoginFailure? failure;
}

abstract interface class QqMusicAuthenticationGateway {
  LoginStartOperation beginStart();
  bool get hasAuthenticatedCredential;
  Future<CredentialPersistenceResult> persistAuthenticatedCredential();
  Future<CredentialRestoreResult> restoreCredential();
  CredentialVerificationOperation beginCredentialVerification();
}

abstract interface class LoginStartOperation {
  Future<LoginStart> run();
  bool cancel();
}

abstract interface class CredentialVerificationOperation {
  Future<CredentialVerificationResult> run();
  bool cancel();
}

class RustQqMusicAuthenticationGateway implements QqMusicAuthenticationGateway {
  RustQqMusicAuthenticationGateway({
    CredentialVault? credentialVault,
    CredentialRestoreImporter? credentialImporter,
    CredentialVerificationOperationFactory? verificationOperationFactory,
  }) : _credentialVault = _SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       ),
       _credentialImporter =
           credentialImporter ?? _restoreQqMusicCredentialInRust,
       _verificationOperationFactory =
           verificationOperationFactory ?? _reserveRustCredentialVerification;

  final CredentialVault _credentialVault;
  final CredentialRestoreImporter _credentialImporter;
  final CredentialVerificationOperationFactory _verificationOperationFactory;

  @override
  bool get hasAuthenticatedCredential =>
      bridge.qqMusicHasAuthenticatedCredential();

  @override
  LoginStartOperation beginStart() =>
      _RustLoginStartOperation(bridge.reserveQqMusicWechatQrLoginStart());

  @override
  CredentialVerificationOperation beginCredentialVerification() =>
      _VaultCleaningCredentialVerificationOperation(
        _verificationOperationFactory(),
        _credentialVault,
      );

  @override
  Future<CredentialPersistenceResult> persistAuthenticatedCredential() async {
    final export = bridge.exportQqMusicCredentialForSecureStorage();
    final secretBytes = export.secretBytes;
    if (secretBytes == null) {
      return CredentialPersistenceResult.noAuthenticatedCredential;
    }

    try {
      await _credentialVault.write(secretBytes);
      return CredentialPersistenceResult.stored;
    } catch (_) {
      return CredentialPersistenceResult.storageUnavailable;
    } finally {
      secretBytes.fillRange(0, secretBytes.length, 0);
    }
  }

  @override
  Future<CredentialRestoreResult> restoreCredential() async {
    Uint8List? secretBytes;
    try {
      secretBytes = await _credentialVault.read();
    } on FormatException {
      return CredentialRestoreResult.invalidStoredCredential;
    } catch (_) {
      return CredentialRestoreResult.storageUnavailable;
    }

    try {
      return _credentialImporter(secretBytes);
    } catch (_) {
      return CredentialRestoreResult.coreUnavailable;
    } finally {
      secretBytes?.fillRange(0, secretBytes.length, 0);
    }
  }
}

class _SerializedCredentialVault implements CredentialVault {
  _SerializedCredentialVault(this._inner);

  final CredentialVault _inner;
  Future<void> _tail = Future<void>.value();

  @override
  Future<void> delete() => _enqueue(_inner.delete);

  @override
  Future<Uint8List?> read() => _enqueue(_inner.read);

  @override
  Future<void> write(Uint8List secretBytes) =>
      _enqueue(() => _inner.write(secretBytes));

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

CredentialVerificationOperation _reserveRustCredentialVerification() {
  final attemptId = bridge.reserveQqMusicCredentialVerification();
  return attemptId == null
      ? const _ImmediateCredentialVerificationOperation(
          CredentialVerificationResult.noRestoredCredential,
        )
      : _RustCredentialVerificationOperation(attemptId);
}

class _RustCredentialVerificationOperation
    implements CredentialVerificationOperation {
  const _RustCredentialVerificationOperation(this._attemptId);

  final int _attemptId;

  @override
  bool cancel() =>
      bridge.cancelQqMusicCredentialVerification(attemptId: _attemptId);

  @override
  Future<CredentialVerificationResult> run() async {
    try {
      final outcome = await bridge.verifyRestoredQqMusicCredential(
        attemptId: _attemptId,
      );
      final state = outcome.state;
      if (state != null) {
        return switch (state) {
          bridge.QqMusicCredentialVerificationState.authenticated =>
            CredentialVerificationResult.authenticated,
          bridge.QqMusicCredentialVerificationState.rejected =>
            CredentialVerificationResult.rejected,
        };
      }
      return switch (outcome.failure) {
        bridge.QqMusicCredentialVerificationFailure.network =>
          CredentialVerificationResult.network,
        bridge.QqMusicCredentialVerificationFailure.serviceUnavailable =>
          CredentialVerificationResult.serviceUnavailable,
        bridge.QqMusicCredentialVerificationFailure.invalidResponse =>
          CredentialVerificationResult.invalidResponse,
        bridge.QqMusicCredentialVerificationFailure.noRestoredCredential =>
          CredentialVerificationResult.noRestoredCredential,
        bridge.QqMusicCredentialVerificationFailure.replaced =>
          CredentialVerificationResult.replaced,
        bridge.QqMusicCredentialVerificationFailure.coreUnavailable ||
        null => CredentialVerificationResult.coreUnavailable,
      };
    } catch (_) {
      return CredentialVerificationResult.coreUnavailable;
    }
  }
}

class _ImmediateCredentialVerificationOperation
    implements CredentialVerificationOperation {
  const _ImmediateCredentialVerificationOperation(this._result);

  final CredentialVerificationResult _result;

  @override
  bool cancel() => false;

  @override
  Future<CredentialVerificationResult> run() async => _result;
}

class _VaultCleaningCredentialVerificationOperation
    implements CredentialVerificationOperation {
  const _VaultCleaningCredentialVerificationOperation(
    this._inner,
    this._credentialVault,
  );

  final CredentialVerificationOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<CredentialVerificationResult> run() async {
    final result = await _inner.run();
    if (result != CredentialVerificationResult.rejected) return result;
    try {
      await _credentialVault.delete();
      return result;
    } catch (_) {
      return CredentialVerificationResult.rejectedStorageCleanupFailed;
    }
  }
}

CredentialRestoreResult _restoreQqMusicCredentialInRust(
  Uint8List? secretBytes,
) {
  final outcome = bridge.restoreQqMusicCredentialFromSecureStorage(
    secretBytes: secretBytes,
  );
  final state = outcome.state;
  if (state != null) {
    return switch (state) {
      bridge.QqMusicCredentialRestoreState.signedOut =>
        CredentialRestoreResult.signedOut,
      bridge.QqMusicCredentialRestoreState.verificationRequired =>
        CredentialRestoreResult.verificationRequired,
      bridge.QqMusicCredentialRestoreState.locallyExpired =>
        CredentialRestoreResult.locallyExpired,
    };
  }

  return switch (outcome.failure) {
    bridge.QqMusicCredentialRestoreFailure.invalidDocument ||
    bridge.QqMusicCredentialRestoreFailure.invalidCredential =>
      CredentialRestoreResult.invalidStoredCredential,
    bridge.QqMusicCredentialRestoreFailure.unsupportedVersion =>
      CredentialRestoreResult.unsupportedStoredCredential,
    bridge.QqMusicCredentialRestoreFailure.coreUnavailable ||
    null => CredentialRestoreResult.coreUnavailable,
  };
}

class _RustLoginStartOperation implements LoginStartOperation {
  const _RustLoginStartOperation(this._attemptId);

  final int _attemptId;

  @override
  bool cancel() =>
      bridge.cancelQqMusicWechatQrLoginStart(attemptId: _attemptId);

  @override
  Future<LoginStart> run() async {
    final outcome = await bridge.startQqMusicWechatQrLogin(
      attemptId: _attemptId,
    );
    final session = outcome.session;
    final challenge = outcome.challenge;
    final failure = outcome.failure;

    if (session == null || challenge == null) {
      return LoginStart(
        failure: failure == null
            ? LoginFailure.invalidResponse
            : _mapFailure(failure),
      );
    }

    return LoginStart(
      session: _RustLoginSession(session),
      challenge: LoginChallenge(
        imageFormat: switch (challenge.imageFormat) {
          bridge.QqMusicQrImageFormat.png => LoginImageFormat.png,
          bridge.QqMusicQrImageFormat.jpeg => LoginImageFormat.jpeg,
        },
        imageBytes: challenge.imageBytes,
      ),
    );
  }
}

class _RustLoginSession implements LoginSession {
  const _RustLoginSession(this._inner);

  final bridge.QqMusicQrLoginSessionHandle _inner;

  @override
  bool cancel() => _inner.cancel();

  @override
  bool get isActive => _inner.isActive;

  @override
  Future<LoginUpdate> advance() async {
    final update = await _inner.advance();
    return LoginUpdate(
      progress: update.state == null ? null : _mapProgress(update.state!),
      failure: update.failure == null ? null : _mapFailure(update.failure!),
      sessionActive: update.sessionActive,
    );
  }
}

LoginProgress _mapProgress(bridge.QqMusicQrLoginState state) => switch (state) {
  bridge.QqMusicQrLoginState.waitingForScan => LoginProgress.waitingForScan,
  bridge.QqMusicQrLoginState.scannedAwaitingConfirmation =>
    LoginProgress.scannedAwaitingConfirmation,
  bridge.QqMusicQrLoginState.authenticated => LoginProgress.authenticated,
  bridge.QqMusicQrLoginState.expired => LoginProgress.expired,
  bridge.QqMusicQrLoginState.refused => LoginProgress.refused,
  bridge.QqMusicQrLoginState.timedOut => LoginProgress.timedOut,
};

LoginFailure _mapFailure(
  bridge.QqMusicQrLoginFailure failure,
) => switch (failure) {
  bridge.QqMusicQrLoginFailure.coreUnavailable => LoginFailure.coreUnavailable,
  bridge.QqMusicQrLoginFailure.network => LoginFailure.network,
  bridge.QqMusicQrLoginFailure.serviceUnavailable =>
    LoginFailure.serviceUnavailable,
  bridge.QqMusicQrLoginFailure.invalidResponse => LoginFailure.invalidResponse,
  bridge.QqMusicQrLoginFailure.rejected => LoginFailure.rejected,
  bridge.QqMusicQrLoginFailure.cancelled => LoginFailure.cancelled,
  bridge.QqMusicQrLoginFailure.replaced => LoginFailure.replaced,
  bridge.QqMusicQrLoginFailure.sessionClosed => LoginFailure.sessionClosed,
  bridge.QqMusicQrLoginFailure.sessionFinished => LoginFailure.sessionFinished,
  bridge.QqMusicQrLoginFailure.timedOut => LoginFailure.timedOut,
  bridge.QqMusicQrLoginFailure.tooManyNetworkFailures =>
    LoginFailure.tooManyNetworkFailures,
  bridge.QqMusicQrLoginFailure.advanceAlreadyInProgress =>
    LoginFailure.advanceAlreadyInProgress,
};
