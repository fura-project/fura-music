import 'dart:typed_data';

import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart' as bridge;

enum LoginImageFormat { png, jpeg }

enum LoginQrChannel { qq, wechat }

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

enum CredentialSignOutResult {
  signedOut,
  storageCleanupFailed,
  coreUnavailable,
}

typedef CredentialRestoreImporter = CredentialRestoreResult Function(
  Uint8List? secretBytes,
);

typedef CredentialVerificationOperationFactory =
    CredentialVerificationOperation Function();

typedef CredentialSignOutCore = bool Function();

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
  Future<CredentialSignOutResult> signOut();
}

abstract interface class MultiMethodQqMusicAuthenticationGateway {
  LoginStartOperation beginQrStart(LoginQrChannel channel);
  PhoneLoginStartOperation beginPhoneStart({
    required String countryCode,
    required String phoneNumber,
  });
}

enum PhoneCodeState { sent, captchaRequired, rateLimited }

class PhoneLoginStart {
  const PhoneLoginStart({
    this.session,
    this.state,
    this.securityUrl,
    this.failure,
  });

  final PhoneLoginSession? session;
  final PhoneCodeState? state;
  final String? securityUrl;
  final LoginFailure? failure;
}

abstract interface class PhoneLoginSession {
  Future<LoginFailure?> authorize(String verificationCode);
  bool cancel();
  bool get isActive;
}

abstract interface class PhoneLoginStartOperation {
  Future<PhoneLoginStart> run();
  bool cancel();
}

abstract interface class LoginStartOperation {
  Future<LoginStart> run();
  bool cancel();
}

abstract interface class CredentialVerificationOperation {
  Future<CredentialVerificationResult> run();
  bool cancel();
}

class RustQqMusicAuthenticationGateway
    implements
        QqMusicAuthenticationGateway,
        MultiMethodQqMusicAuthenticationGateway {
  RustQqMusicAuthenticationGateway({
    CredentialVault? credentialVault,
    CredentialRestoreImporter? credentialImporter,
    CredentialVerificationOperationFactory? verificationOperationFactory,
    CredentialSignOutCore? credentialSignOutCore,
  }) : _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       ),
       _credentialImporter =
           credentialImporter ?? _restoreQqMusicCredentialInRust,
       _verificationOperationFactory =
           verificationOperationFactory ?? _reserveRustCredentialVerification,
       _credentialSignOutCore = credentialSignOutCore ?? bridge.signOutQqMusic;

  final CredentialVault _credentialVault;
  final CredentialRestoreImporter _credentialImporter;
  final CredentialVerificationOperationFactory _verificationOperationFactory;
  final CredentialSignOutCore _credentialSignOutCore;

  @override
  bool get hasAuthenticatedCredential =>
      bridge.qqMusicHasAuthenticatedCredential();

  @override
  LoginStartOperation beginStart() => beginQrStart(LoginQrChannel.wechat);

  @override
  LoginStartOperation beginQrStart(LoginQrChannel channel) =>
      _RustLoginStartOperation(bridge.reserveQqMusicQrLoginStart(), channel);

  @override
  PhoneLoginStartOperation beginPhoneStart({
    required String countryCode,
    required String phoneNumber,
  }) => _RustPhoneLoginStartOperation(
    bridge.reserveQqMusicPhoneLoginStart(),
    countryCode,
    phoneNumber,
  );

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

  @override
  Future<CredentialSignOutResult> signOut() async {
    try {
      if (!_credentialSignOutCore()) {
        return CredentialSignOutResult.coreUnavailable;
      }
    } catch (_) {
      return CredentialSignOutResult.coreUnavailable;
    }

    try {
      await _credentialVault.delete();
      return CredentialSignOutResult.signedOut;
    } catch (_) {
      return CredentialSignOutResult.storageCleanupFailed;
    }
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
  const _RustLoginStartOperation(this._attemptId, this._channel);

  final int _attemptId;
  final LoginQrChannel _channel;

  @override
  bool cancel() => bridge.cancelQqMusicQrLoginStart(attemptId: _attemptId);

  @override
  Future<LoginStart> run() async {
    final outcome = await bridge.startQqMusicQrLogin(
      attemptId: _attemptId,
      channel: switch (_channel) {
        LoginQrChannel.qq => bridge.QqMusicQrLoginChannel.qq,
        LoginQrChannel.wechat => bridge.QqMusicQrLoginChannel.wechat,
      },
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

class _RustPhoneLoginStartOperation implements PhoneLoginStartOperation {
  const _RustPhoneLoginStartOperation(
    this._attemptId,
    this._countryCode,
    this._phoneNumber,
  );

  final int _attemptId;
  final String _countryCode;
  final String _phoneNumber;

  @override
  bool cancel() => bridge.cancelQqMusicPhoneLoginStart(attemptId: _attemptId);

  @override
  Future<PhoneLoginStart> run() async {
    final outcome = await bridge.startQqMusicPhoneLogin(
      attemptId: _attemptId,
      countryCode: _countryCode,
      phoneNumber: _phoneNumber,
    );
    return PhoneLoginStart(
      session: outcome.session == null
          ? null
          : _RustPhoneLoginSession(outcome.session!),
      state: switch (outcome.state) {
        bridge.QqMusicPhoneCodeState.sent => PhoneCodeState.sent,
        bridge.QqMusicPhoneCodeState.captchaRequired =>
          PhoneCodeState.captchaRequired,
        bridge.QqMusicPhoneCodeState.rateLimited => PhoneCodeState.rateLimited,
        null => null,
      },
      securityUrl: outcome.securityUrl,
      failure: outcome.failure == null ? null : _mapFailure(outcome.failure!),
    );
  }
}

class _RustPhoneLoginSession implements PhoneLoginSession {
  const _RustPhoneLoginSession(this._inner);

  final bridge.QqMusicPhoneLoginSessionHandle _inner;

  @override
  bool cancel() => _inner.cancel();

  @override
  bool get isActive => _inner.isActive;

  @override
  Future<LoginFailure?> authorize(String verificationCode) async {
    final result = await _inner.authorize(verificationCode: verificationCode);
    if (result.authenticated) return null;
    return result.failure == null
        ? LoginFailure.invalidResponse
        : _mapFailure(result.failure!);
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
