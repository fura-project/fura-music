import 'dart:async';

import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/authentication/qq_session_continuation.dart';
import 'package:flutterustmusic/src/rust/api/netease_authentication.dart'
    as bridge;

typedef NeteaseRefreshPrepare =
    Future<bridge.NeteaseRefreshPreparation> Function();
typedef NeteaseRefreshVerify =
    Future<bridge.NeteaseRefreshVerification> Function({
      required int reservationId,
    });
typedef NeteaseRefreshCommit = bridge.NeteaseRefreshFailure? Function({
  required int reservationId,
});
typedef NeteaseRefreshAbort = bridge.NeteaseRefreshFailure? Function({
  required int reservationId,
});
typedef NeteaseStagedRecovery =
    Future<StagedCredentialRecoveryResult> Function();

/// App-lifetime durable-storage driver for the Rust-owned NetEase session.
///
/// All credential fields, account identity and refresh eligibility stay in
/// Rust. Flutter only acknowledges opaque stage/current vault writes.
class NeteaseSessionContinuationCoordinator
    implements SessionContinuationCoordinator {
  NeteaseSessionContinuationCoordinator(
    this._vault, {
    NeteaseRefreshPrepare? prepareAfterReadRejection,
    NeteaseRefreshPrepare? prepareCheckpoint,
    NeteaseRefreshVerify? verify,
    NeteaseRefreshCommit? commit,
    NeteaseRefreshAbort? abort,
    this.recoverStagedCredential,
  }) : _prepareAfterReadRejection =
           prepareAfterReadRejection ??
           bridge.prepareNeteaseRefreshAfterReadRejection,
       _prepareCheckpoint =
           prepareCheckpoint ?? bridge.prepareNeteaseRefreshCheckpoint,
       _verify = verify ?? bridge.verifyNeteaseStagedRefreshCandidate,
       _commit = commit ?? bridge.commitNeteaseStagedRefreshCandidate,
       _abort = abort ?? bridge.abortNeteaseCredentialRefresh;

  final CredentialRotationVault _vault;
  final NeteaseRefreshPrepare _prepareAfterReadRejection;
  final NeteaseRefreshPrepare _prepareCheckpoint;
  final NeteaseRefreshVerify _verify;
  final NeteaseRefreshCommit _commit;
  final NeteaseRefreshAbort _abort;
  final NeteaseStagedRecovery? recoverStagedCredential;
  Future<void> _tail = Future<void>.value();

  @override
  Future<QqSessionContinuationResult> continueAfterReadRejection() => _enqueue(
    () => _continue(_prepareAfterReadRejection, rejectionTrigger: true),
  );

  @override
  Future<QqSessionContinuationResult> checkpoint() => _enqueue(() async {
    final recover = recoverStagedCredential;
    if (recover != null) {
      final recovery = await recover();
      final result = switch (recovery) {
        StagedCredentialRecoveryResult.notNeeded => null,
        StagedCredentialRecoveryResult.recovered =>
          QqSessionContinuationResult.continued,
        StagedCredentialRecoveryResult.temporarilyUnavailable =>
          QqSessionContinuationResult.temporarilyUnavailable,
        StagedCredentialRecoveryResult.reauthenticationRequired =>
          QqSessionContinuationResult.reauthenticationRequired,
        StagedCredentialRecoveryResult.replaced =>
          QqSessionContinuationResult.replaced,
      };
      if (result != null) return result;
    }
    return _continue(_prepareCheckpoint, rejectionTrigger: false);
  });

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

  Future<QqSessionContinuationResult> _continue(
    NeteaseRefreshPrepare prepare, {
    required bool rejectionTrigger,
  }) async {
    final epoch = _vault.reserveRotation();
    bridge.NeteaseRefreshPreparation preparation;
    try {
      preparation = await prepare();
    } on Object {
      return QqSessionContinuationResult.temporarilyUnavailable;
    }
    if (preparation.reusedNewGeneration) {
      return QqSessionContinuationResult.continued;
    }
    final failure = preparation.failure;
    if (failure != null) {
      return _handlePreparationFailure(
        failure,
        epoch: epoch,
        rejectionTrigger: rejectionTrigger,
      );
    }
    final reservationId = preparation.reservationId;
    final stagedBytes = preparation.stagedSecretBytes;
    if (reservationId == null || stagedBytes == null) {
      return QqSessionContinuationResult.temporarilyUnavailable;
    }

    try {
      if (!await _vault.stageIfCurrent(epoch, stagedBytes)) {
        _abort(reservationId: reservationId);
        return QqSessionContinuationResult.replaced;
      }
    } on Object {
      _abort(reservationId: reservationId);
      return QqSessionContinuationResult.temporarilyUnavailable;
    } finally {
      stagedBytes.fillRange(0, stagedBytes.length, 0);
    }

    bridge.NeteaseRefreshVerification verification;
    try {
      verification = await _verify(reservationId: reservationId);
    } on Object {
      _abort(reservationId: reservationId);
      return QqSessionContinuationResult.temporarilyUnavailable;
    }
    final verificationFailure = verification.failure;
    if (verificationFailure != null) {
      return _handleVerificationFailure(verificationFailure, epoch: epoch);
    }
    final currentBytes = verification.currentSecretBytes;
    if (currentBytes == null) {
      _abort(reservationId: reservationId);
      return QqSessionContinuationResult.temporarilyUnavailable;
    }

    try {
      if (!await _vault.publishIfCurrent(epoch, currentBytes)) {
        _abort(reservationId: reservationId);
        return QqSessionContinuationResult.replaced;
      }
    } on Object {
      _abort(reservationId: reservationId);
      return QqSessionContinuationResult.temporarilyUnavailable;
    } finally {
      currentBytes.fillRange(0, currentBytes.length, 0);
    }

    final commitFailure = _commit(reservationId: reservationId);
    if (commitFailure != null) {
      return commitFailure == bridge.NeteaseRefreshFailure.replaced
          ? QqSessionContinuationResult.replaced
          : QqSessionContinuationResult.temporarilyUnavailable;
    }
    try {
      await _vault.deleteStageIfCurrent(epoch);
    } on Object {
      // Current and stage now describe the same verified candidate. Startup
      // recovery can safely converge this cleanup later.
    }
    return QqSessionContinuationResult.continued;
  }

  Future<QqSessionContinuationResult> _handlePreparationFailure(
    bridge.NeteaseRefreshFailure failure, {
    required int epoch,
    required bool rejectionTrigger,
  }) async {
    switch (failure) {
      case bridge.NeteaseRefreshFailure.notDue:
        return QqSessionContinuationResult.notNeeded;
      case bridge.NeteaseRefreshFailure.replaced:
        return QqSessionContinuationResult.replaced;
      case bridge.NeteaseRefreshFailure.productionGateDisabled:
      case bridge.NeteaseRefreshFailure.notRefreshable:
        if (!rejectionTrigger) return QqSessionContinuationResult.notNeeded;
        return _deleteRejectedTransaction(epoch);
      case bridge.NeteaseRefreshFailure.reauthenticationRequired:
      case bridge.NeteaseRefreshFailure.noCredential:
        return rejectionTrigger
            ? _deleteRejectedTransaction(epoch)
            : QqSessionContinuationResult.notNeeded;
      case bridge.NeteaseRefreshFailure.network:
      case bridge.NeteaseRefreshFailure.rateLimited:
      case bridge.NeteaseRefreshFailure.riskControl:
      case bridge.NeteaseRefreshFailure.secondaryVerificationRequired:
      case bridge.NeteaseRefreshFailure.serviceUnavailable:
      case bridge.NeteaseRefreshFailure.invalidResponse:
      case bridge.NeteaseRefreshFailure.storageUnavailable:
        return QqSessionContinuationResult.temporarilyUnavailable;
    }
  }

  Future<QqSessionContinuationResult> _handleVerificationFailure(
    bridge.NeteaseRefreshFailure failure, {
    required int epoch,
  }) {
    if (failure == bridge.NeteaseRefreshFailure.reauthenticationRequired) {
      return _deleteRejectedTransaction(epoch);
    }
    return Future<QqSessionContinuationResult>.value(
      failure == bridge.NeteaseRefreshFailure.replaced
          ? QqSessionContinuationResult.replaced
          : QqSessionContinuationResult.temporarilyUnavailable,
    );
  }

  Future<QqSessionContinuationResult> _deleteRejectedTransaction(
    int epoch,
  ) async {
    try {
      return await _vault.deleteTransactionIfCurrent(epoch)
          ? QqSessionContinuationResult.reauthenticationRequired
          : QqSessionContinuationResult.replaced;
    } on Object {
      return QqSessionContinuationResult.temporarilyUnavailable;
    }
  }
}
