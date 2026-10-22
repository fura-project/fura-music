import 'dart:async';

import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart' as bridge;

enum QqSessionContinuationResult {
  continued,
  notNeeded,
  temporarilyUnavailable,
  reauthenticationRequired,
  replaced,
}

typedef QqRefreshPrepare = Future<bridge.QqMusicRefreshPreparation> Function();
typedef QqRefreshVerify = Future<bridge.QqMusicRefreshVerification> Function({
  required int reservationId,
});
typedef QqRefreshCommit = bridge.QqMusicRefreshFailure? Function({
  required int reservationId,
});
typedef QqRefreshAbort = bridge.QqMusicRefreshFailure? Function({
  required int reservationId,
});
typedef QqStagedRecovery = Future<StagedCredentialRecoveryResult> Function();

/// App-lifetime platform driver for the Rust-owned QQ refresh reservation.
///
/// It owns no credential fields or session truth. Its only authority is to
/// await durable opaque-byte storage acknowledgement between Rust phases.
class QqSessionContinuationCoordinator {
  QqSessionContinuationCoordinator(
    this._vault, {
    QqRefreshPrepare? prepareAfterReadRejection,
    QqRefreshPrepare? prepareCheckpoint,
    QqRefreshVerify? verify,
    QqRefreshCommit? commit,
    QqRefreshAbort? abort,
    this.recoverStagedCredential,
  }) : _prepareAfterReadRejection =
           prepareAfterReadRejection ??
           bridge.prepareQqMusicRefreshAfterReadRejection,
       _prepareCheckpoint =
           prepareCheckpoint ?? bridge.prepareQqMusicRefreshCheckpoint,
       _verify = verify ?? bridge.verifyQqMusicStagedRefreshCandidate,
       _commit = commit ?? bridge.commitQqMusicStagedRefreshCandidate,
       _abort = abort ?? bridge.abortQqMusicCredentialRefresh;

  final CredentialRotationVault _vault;
  final QqRefreshPrepare _prepareAfterReadRejection;
  final QqRefreshPrepare _prepareCheckpoint;
  final QqRefreshVerify _verify;
  final QqRefreshCommit _commit;
  final QqRefreshAbort _abort;
  final QqStagedRecovery? recoverStagedCredential;
  Future<void> _tail = Future<void>.value();

  Future<QqSessionContinuationResult> continueAfterReadRejection() => _enqueue(
    () => _continue(_prepareAfterReadRejection, rejectionTrigger: true),
  );

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
    QqRefreshPrepare prepare, {
    required bool rejectionTrigger,
  }) async {
    final epoch = _vault.reserveRotation();
    bridge.QqMusicRefreshPreparation preparation;
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
      final staged = await _vault.stageIfCurrent(epoch, stagedBytes);
      if (!staged) {
        _abort(reservationId: reservationId);
        return QqSessionContinuationResult.replaced;
      }
    } on Object {
      _abort(reservationId: reservationId);
      return QqSessionContinuationResult.temporarilyUnavailable;
    } finally {
      stagedBytes.fillRange(0, stagedBytes.length, 0);
    }

    bridge.QqMusicRefreshVerification verification;
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
      final published = await _vault.publishIfCurrent(epoch, currentBytes);
      if (!published) {
        _abort(reservationId: reservationId);
        return QqSessionContinuationResult.replaced;
      }
    } on Object {
      _abort(reservationId: reservationId);
      // The durable stage remains the crash-recovery source of truth.
      return QqSessionContinuationResult.temporarilyUnavailable;
    } finally {
      currentBytes.fillRange(0, currentBytes.length, 0);
    }

    final commitFailure = _commit(reservationId: reservationId);
    if (commitFailure != null) {
      // Current and stage intentionally remain. Startup recovery can converge
      // even when a logout/account switch made this in-process commit stale.
      return commitFailure == bridge.QqMusicRefreshFailure.replaced
          ? QqSessionContinuationResult.replaced
          : QqSessionContinuationResult.temporarilyUnavailable;
    }
    try {
      await _vault.deleteStageIfCurrent(epoch);
    } on Object {
      // current == candidate and stage == candidate is a recoverable committed
      // checkpoint; cleanup can be retried on startup/resume.
    }
    return QqSessionContinuationResult.continued;
  }

  Future<QqSessionContinuationResult> _handlePreparationFailure(
    bridge.QqMusicRefreshFailure failure, {
    required int epoch,
    required bool rejectionTrigger,
  }) async {
    switch (failure) {
      case bridge.QqMusicRefreshFailure.notDue:
        return QqSessionContinuationResult.notNeeded;
      case bridge.QqMusicRefreshFailure.replaced:
        return QqSessionContinuationResult.replaced;
      case bridge.QqMusicRefreshFailure.productionGateDisabled:
      case bridge.QqMusicRefreshFailure.notRefreshable:
      case bridge.QqMusicRefreshFailure.unsupportedLoginType:
        if (!rejectionTrigger) {
          return QqSessionContinuationResult.notNeeded;
        }
        try {
          await _vault.deleteTransactionIfCurrent(epoch);
        } on Object {
          return QqSessionContinuationResult.temporarilyUnavailable;
        }
        return QqSessionContinuationResult.reauthenticationRequired;
      case bridge.QqMusicRefreshFailure.reauthenticationRequired:
        return _deleteRejectedTransaction(epoch);
      case bridge.QqMusicRefreshFailure.noCredential:
        return rejectionTrigger
            ? _deleteRejectedTransaction(epoch)
            : QqSessionContinuationResult.notNeeded;
      case bridge.QqMusicRefreshFailure.network:
      case bridge.QqMusicRefreshFailure.rateLimited:
      case bridge.QqMusicRefreshFailure.serviceUnavailable:
      case bridge.QqMusicRefreshFailure.invalidResponse:
      case bridge.QqMusicRefreshFailure.storageUnavailable:
        return QqSessionContinuationResult.temporarilyUnavailable;
    }
  }

  Future<QqSessionContinuationResult> _handleVerificationFailure(
    bridge.QqMusicRefreshFailure failure, {
    required int epoch,
  }) async {
    if (failure == bridge.QqMusicRefreshFailure.reauthenticationRequired) {
      return _deleteRejectedTransaction(epoch);
    }
    return failure == bridge.QqMusicRefreshFailure.replaced
        ? QqSessionContinuationResult.replaced
        : QqSessionContinuationResult.temporarilyUnavailable;
  }

  Future<QqSessionContinuationResult> _deleteRejectedTransaction(
    int epoch,
  ) async {
    try {
      final deleted = await _vault.deleteTransactionIfCurrent(epoch);
      return deleted
          ? QqSessionContinuationResult.reauthenticationRequired
          : QqSessionContinuationResult.replaced;
    } on Object {
      return QqSessionContinuationResult.temporarilyUnavailable;
    }
  }
}
