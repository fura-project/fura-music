import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/qq_session_continuation.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart' as bridge;

enum AccountSummaryFailure {
  coreUnavailable,
  authenticationRequired,
  credentialRejected,
  credentialRejectedStorageCleanupFailed,
  network,
  serviceUnavailable,
  invalidResponse,
  replaced,
  cancelled,
  alreadyRunning,
}

@immutable
class AuthenticatedAccountSummary {
  const AuthenticatedAccountSummary({
    required this.displayName,
    this.avatarUri,
  });

  final String displayName;
  final String? avatarUri;
}

@immutable
class AccountSummaryLoadResult {
  const AccountSummaryLoadResult({this.summary, this.failure});

  final AuthenticatedAccountSummary? summary;
  final AccountSummaryFailure? failure;
}

abstract interface class AccountSummaryGateway {
  AccountSummaryLoadOperation beginLoad();
}

abstract interface class AccountSummaryLoadOperation {
  Future<AccountSummaryLoadResult> run();
  bool cancel();
}

typedef AccountSummaryLoadOperationFactory =
    AccountSummaryLoadOperation Function();

class RustAccountSummaryGateway implements AccountSummaryGateway {
  RustAccountSummaryGateway({
    this.providerId = 'qq-music',
    CredentialVault? credentialVault,
    this.operationFactory,
    this.sessionContinuation,
  }) : _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final String providerId;
  final AccountSummaryLoadOperationFactory? operationFactory;
  final QqSessionContinuationCoordinator? sessionContinuation;

  @override
  AccountSummaryLoadOperation beginLoad() => _ContinuingAccountSummaryOperation(
    () => operationFactory?.call() ?? _beginRustLoad(providerId),
    _credentialVault,
    providerId == 'qq-music' ? sessionContinuation : null,
  );
}

AccountSummaryLoadOperation _beginRustLoad(String providerId) =>
    _RustAccountSummaryLoadOperation(
      bridge.beginQqMusicAccountSummaryLoad(providerId: providerId),
    );

class _RustAccountSummaryLoadOperation implements AccountSummaryLoadOperation {
  const _RustAccountSummaryLoadOperation(this._handle);

  final bridge.QqMusicAccountSummaryLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<AccountSummaryLoadResult> run() async {
    try {
      return mapBridgeAccountSummaryLoad(await _handle.run());
    } on Object {
      return const AccountSummaryLoadResult(
        failure: AccountSummaryFailure.coreUnavailable,
      );
    }
  }
}

class _ContinuingAccountSummaryOperation
    implements AccountSummaryLoadOperation {
  _ContinuingAccountSummaryOperation(
    this._factory,
    this._credentialVault,
    this._continuation,
  ) : _active = _factory();

  final AccountSummaryLoadOperationFactory _factory;
  final CredentialVault _credentialVault;
  final QqSessionContinuationCoordinator? _continuation;
  AccountSummaryLoadOperation _active;
  bool _cancelled = false;

  @override
  bool cancel() {
    _cancelled = true;
    return _active.cancel();
  }

  @override
  Future<AccountSummaryLoadResult> run() async {
    var result = await _active.run();
    if (result.failure != AccountSummaryFailure.credentialRejected) {
      return result;
    }
    final continuation = _continuation;
    if (continuation != null) {
      final outcome = await continuation.continueAfterReadRejection();
      if (outcome == QqSessionContinuationResult.continued && !_cancelled) {
        _active = _factory();
        result = await _active.run();
        return result;
      }
      if (outcome != QqSessionContinuationResult.reauthenticationRequired) {
        return const AccountSummaryLoadResult(
          failure: AccountSummaryFailure.serviceUnavailable,
        );
      }
      return result;
    }
    try {
      await _credentialVault.delete();
      return result;
    } on Object {
      return const AccountSummaryLoadResult(
        failure: AccountSummaryFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}

@visibleForTesting
AccountSummaryLoadResult mapBridgeAccountSummaryLoad(
  bridge.QqMusicAccountSummaryLoad result,
) {
  final failure = result.failure;
  final summary = result.summary;
  if (failure != null) {
    if (summary != null) {
      return const AccountSummaryLoadResult(
        failure: AccountSummaryFailure.invalidResponse,
      );
    }
    return AccountSummaryLoadResult(
      failure: mapBridgeAccountSummaryFailure(failure),
    );
  }
  if (summary == null ||
      summary.displayName.trim().isEmpty ||
      (summary.avatarUri?.trim().isEmpty ?? false)) {
    return const AccountSummaryLoadResult(
      failure: AccountSummaryFailure.invalidResponse,
    );
  }
  return AccountSummaryLoadResult(
    summary: AuthenticatedAccountSummary(
      displayName: summary.displayName,
      avatarUri: summary.avatarUri,
    ),
  );
}

@visibleForTesting
AccountSummaryFailure mapBridgeAccountSummaryFailure(
  bridge.QqMusicAccountSummaryFailure failure,
) => switch (failure) {
  bridge.QqMusicAccountSummaryFailure.coreUnavailable =>
    AccountSummaryFailure.coreUnavailable,
  bridge.QqMusicAccountSummaryFailure.authenticationRequired =>
    AccountSummaryFailure.authenticationRequired,
  bridge.QqMusicAccountSummaryFailure.credentialRejected =>
    AccountSummaryFailure.credentialRejected,
  bridge.QqMusicAccountSummaryFailure.network => AccountSummaryFailure.network,
  bridge.QqMusicAccountSummaryFailure.serviceUnavailable =>
    AccountSummaryFailure.serviceUnavailable,
  bridge.QqMusicAccountSummaryFailure.invalidResponse =>
    AccountSummaryFailure.invalidResponse,
  bridge.QqMusicAccountSummaryFailure.replaced =>
    AccountSummaryFailure.replaced,
  bridge.QqMusicAccountSummaryFailure.cancelled =>
    AccountSummaryFailure.cancelled,
  bridge.QqMusicAccountSummaryFailure.alreadyRunning =>
    AccountSummaryFailure.alreadyRunning,
};
