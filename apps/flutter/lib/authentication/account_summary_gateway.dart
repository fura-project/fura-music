import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
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
    CredentialVault? credentialVault,
    AccountSummaryLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final AccountSummaryLoadOperationFactory _operationFactory;

  @override
  AccountSummaryLoadOperation beginLoad() =>
      _VaultCleaningAccountSummaryLoadOperation(
        _operationFactory(),
        _credentialVault,
      );
}

AccountSummaryLoadOperation _beginRustLoad() =>
    _RustAccountSummaryLoadOperation(bridge.beginQqMusicAccountSummaryLoad());

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

class _VaultCleaningAccountSummaryLoadOperation
    implements AccountSummaryLoadOperation {
  const _VaultCleaningAccountSummaryLoadOperation(
    this._inner,
    this._credentialVault,
  );

  final AccountSummaryLoadOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<AccountSummaryLoadResult> run() async {
    final result = await _inner.run();
    if (result.failure != AccountSummaryFailure.credentialRejected) {
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
