import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';

enum LoginStage {
  idle,
  verificationRequired,
  verifyingStoredCredential,
  credentialRejected,
  verificationError,
  signOutStorageCleanupFailed,
  storedCredentialExpired,
  restoreError,
  starting,
  waitingForScan,
  scannedAwaitingConfirmation,
  reconnecting,
  authenticated,
  expired,
  refused,
  timedOut,
  error,
}

enum CredentialSaveState { none, saving, saved, failed }

class LoginController extends ChangeNotifier {
  LoginController(
    this._gateway, {
    this._networkRetryDelay = const Duration(seconds: 1),
    CredentialRestoreResult initialCredentialRestore =
        CredentialRestoreResult.signedOut,
  }) : _credentialRestoreResult = initialCredentialRestore {
    if (_gateway.hasAuthenticatedCredential) {
      _stage = LoginStage.authenticated;
      return;
    }
    _stage = switch (initialCredentialRestore) {
      CredentialRestoreResult.signedOut => LoginStage.idle,
      CredentialRestoreResult.verificationRequired =>
        LoginStage.verificationRequired,
      CredentialRestoreResult.locallyExpired =>
        LoginStage.storedCredentialExpired,
      CredentialRestoreResult.invalidStoredCredential ||
      CredentialRestoreResult.unsupportedStoredCredential ||
      CredentialRestoreResult.storageUnavailable ||
      CredentialRestoreResult.coreUnavailable => LoginStage.restoreError,
    };
  }

  final QqMusicAuthenticationGateway _gateway;
  final Duration _networkRetryDelay;
  final Set<int> _pollingGenerations = <int>{};

  LoginStage _stage = LoginStage.idle;
  LoginSession? _session;
  LoginStartOperation? _startOperation;
  CredentialVerificationOperation? _verificationOperation;
  Uint8List? _qrImageBytes;
  LoginFailure? _failure;
  LoginQrChannel _qrChannel = LoginQrChannel.qq;
  CredentialSaveState _credentialSaveState = CredentialSaveState.none;
  CredentialRestoreResult _credentialRestoreResult;
  CredentialVerificationResult? _credentialVerificationResult;
  Future<CredentialSignOutResult>? _signOutOperation;
  int _generation = 0;
  bool _disposed = false;

  LoginStage get stage => _stage;
  Uint8List? get qrImageBytes => _qrImageBytes;
  LoginFailure? get failure => _failure;
  LoginQrChannel get qrChannel => _qrChannel;
  CredentialSaveState get credentialSaveState => _credentialSaveState;
  CredentialRestoreResult get credentialRestoreResult =>
      _credentialRestoreResult;
  CredentialVerificationResult? get credentialVerificationResult =>
      _credentialVerificationResult;

  bool get canCancel =>
      _stage == LoginStage.starting || (_session?.isActive ?? false);

  bool get canRetry =>
      _stage == LoginStage.error && (_session?.isActive ?? false);

  bool get canRetryCredentialVerification =>
      _stage == LoginStage.verificationError &&
      (_credentialVerificationResult == CredentialVerificationResult.network ||
          _credentialVerificationResult ==
              CredentialVerificationResult.serviceUnavailable ||
          _credentialVerificationResult ==
              CredentialVerificationResult.invalidResponse);

  bool get isSigningOut => _signOutOperation != null;

  bool get canRetrySignOut =>
      _stage == LoginStage.signOutStorageCleanupFailed && !isSigningOut;

  Future<CredentialSignOutResult> signOut() {
    final activeOperation = _signOutOperation;
    if (activeOperation != null) return activeOperation;

    final previousStage = _stage;
    if (previousStage != LoginStage.authenticated &&
        previousStage != LoginStage.signOutStorageCleanupFailed) {
      return Future.value(CredentialSignOutResult.coreUnavailable);
    }

    final generation = ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    final completer = Completer<CredentialSignOutResult>();
    final operation = completer.future;
    _signOutOperation = operation;
    _notify();
    unawaited(_finishSignOut(operation, completer, generation, previousStage));
    return operation;
  }

  Future<void> _finishSignOut(
    Future<CredentialSignOutResult> operation,
    Completer<CredentialSignOutResult> completer,
    int generation,
    LoginStage previousStage,
  ) async {
    CredentialSignOutResult result;
    try {
      result = await _gateway.signOut();
    } on Object {
      result = CredentialSignOutResult.coreUnavailable;
    }

    if (_isCurrent(generation)) {
      if (result == CredentialSignOutResult.coreUnavailable) {
        _stage = previousStage;
      } else {
        _qrImageBytes = null;
        _failure = null;
        _credentialSaveState = CredentialSaveState.none;
        _credentialRestoreResult = CredentialRestoreResult.signedOut;
        _credentialVerificationResult = null;
        _stage = result == CredentialSignOutResult.signedOut
            ? LoginStage.idle
            : LoginStage.signOutStorageCleanupFailed;
      }
    }

    if (identical(_signOutOperation, operation)) {
      _signOutOperation = null;
    }
    _notify();
    completer.complete(result);
  }

  Future<void> verifyRestoredCredential() async {
    if (_stage != LoginStage.verificationRequired &&
        _stage != LoginStage.verificationError) {
      return;
    }
    final generation = ++_generation;
    _verificationOperation?.cancel();
    final operation = _gateway.beginCredentialVerification();
    _verificationOperation = operation;
    _credentialVerificationResult = null;
    _stage = LoginStage.verifyingStoredCredential;
    _notify();

    final result = await operation.run();
    if (identical(_verificationOperation, operation)) {
      _verificationOperation = null;
    }
    if (!_isCurrent(generation)) return;

    _credentialVerificationResult = result;
    _stage = switch (result) {
      CredentialVerificationResult.authenticated => LoginStage.authenticated,
      CredentialVerificationResult.rejected ||
      CredentialVerificationResult.rejectedStorageCleanupFailed =>
        LoginStage.credentialRejected,
      CredentialVerificationResult.network ||
      CredentialVerificationResult.serviceUnavailable ||
      CredentialVerificationResult.invalidResponse ||
      CredentialVerificationResult.coreUnavailable =>
        LoginStage.verificationError,
      CredentialVerificationResult.noRestoredCredential ||
      CredentialVerificationResult.replaced => LoginStage.idle,
    };
    if (result == CredentialVerificationResult.authenticated) {
      _credentialSaveState = CredentialSaveState.saved;
    }
    if (result == CredentialVerificationResult.noRestoredCredential ||
        result == CredentialVerificationResult.replaced) {
      _credentialRestoreResult = CredentialRestoreResult.signedOut;
    }
    _notify();
  }

  void retryCredentialVerification() {
    if (!canRetryCredentialVerification) return;
    unawaited(verifyRestoredCredential());
  }

  Future<void> start() => startQr(LoginQrChannel.wechat);

  Future<void> startQr(LoginQrChannel channel) async {
    final generation = ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    _qrImageBytes = null;
    _failure = null;
    _qrChannel = channel;
    _credentialSaveState = CredentialSaveState.none;
    _credentialRestoreResult = CredentialRestoreResult.signedOut;
    _credentialVerificationResult = null;
    _stage = LoginStage.starting;
    _notify();

    final operation = _gateway is MultiMethodQqMusicAuthenticationGateway
        ? (_gateway as MultiMethodQqMusicAuthenticationGateway).beginQrStart(
            channel,
          )
        : _gateway.beginStart();
    _startOperation = operation;
    final result = await operation.run();
    if (identical(_startOperation, operation)) {
      _startOperation = null;
    }
    if (!_isCurrent(generation)) {
      result.session?.cancel();
      return;
    }

    final session = result.session;
    final challenge = result.challenge;
    if (session == null || challenge == null) {
      _failure = result.failure ?? LoginFailure.invalidResponse;
      _stage = LoginStage.error;
      _notify();
      return;
    }

    _session = session;
    _qrImageBytes = challenge.imageBytes;
    _stage = LoginStage.waitingForScan;
    _notify();
    unawaited(_poll(generation));
  }

  void retry() {
    if (!canRetry) return;
    _failure = null;
    _stage = LoginStage.waitingForScan;
    _notify();
    unawaited(_poll(_generation));
  }

  void cancel() {
    ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    _qrImageBytes = null;
    _failure = null;
    _credentialSaveState = CredentialSaveState.none;
    _credentialRestoreResult = CredentialRestoreResult.signedOut;
    _credentialVerificationResult = null;
    _stage = LoginStage.idle;
    _notify();
  }

  Future<void> _poll(int generation) async {
    if (!_pollingGenerations.add(generation)) return;
    try {
      while (_isCurrent(generation)) {
        final session = _session;
        if (session == null || !session.isActive) return;

        final update = await session.advance();
        if (!_isCurrent(generation)) return;

        final progress = update.progress;
        if (progress != null) {
          if (await _applyProgress(progress, generation)) return;
          _notify();
          continue;
        }

        final failure = update.failure ?? LoginFailure.invalidResponse;
        if (failure == LoginFailure.network && update.sessionActive) {
          _failure = failure;
          _stage = LoginStage.reconnecting;
          _notify();
          await Future<void>.delayed(_networkRetryDelay);
          continue;
        }

        _failure = failure;
        _stage = failure == LoginFailure.timedOut
            ? LoginStage.timedOut
            : LoginStage.error;
        if (!update.sessionActive) {
          _session = null;
          _qrImageBytes = null;
        }
        _notify();
        return;
      }
    } finally {
      _pollingGenerations.remove(generation);
    }
  }

  Future<bool> _applyProgress(LoginProgress progress, int generation) async {
    switch (progress) {
      case LoginProgress.waitingForScan:
        _failure = null;
        _stage = LoginStage.waitingForScan;
        return false;
      case LoginProgress.scannedAwaitingConfirmation:
        _failure = null;
        _stage = LoginStage.scannedAwaitingConfirmation;
        return false;
      case LoginProgress.authenticated:
        _session = null;
        _qrImageBytes = null;
        await _finishAuthentication(generation);
        return true;
      case LoginProgress.expired:
        _stage = LoginStage.expired;
        _session = null;
        _failure = null;
        _notify();
        return true;
      case LoginProgress.refused:
        _stage = LoginStage.refused;
        _session = null;
        _failure = null;
        _notify();
        return true;
      case LoginProgress.timedOut:
        _stage = LoginStage.timedOut;
        _session = null;
        _failure = null;
        _notify();
        return true;
    }
  }

  Future<void> _finishAuthentication(int generation) async {
    _failure = null;
    _stage = LoginStage.authenticated;
    _credentialSaveState = CredentialSaveState.saving;
    _notify();
    final result = await _gateway.persistAuthenticatedCredential();
    if (!_isCurrent(generation)) return;
    _credentialSaveState = result == CredentialPersistenceResult.stored
        ? CredentialSaveState.saved
        : CredentialSaveState.failed;
    _notify();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    super.dispose();
  }
}
