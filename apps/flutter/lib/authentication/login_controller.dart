import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';

enum LoginStage {
  idle,
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

class LoginController extends ChangeNotifier {
  LoginController(
    this._gateway, [
    this._networkRetryDelay = const Duration(seconds: 1),
  ]) {
    if (_gateway.hasAuthenticatedCredential) {
      _stage = LoginStage.authenticated;
    }
  }

  final QqMusicAuthenticationGateway _gateway;
  final Duration _networkRetryDelay;
  final Set<int> _pollingGenerations = <int>{};

  LoginStage _stage = LoginStage.idle;
  LoginSession? _session;
  LoginStartOperation? _startOperation;
  Uint8List? _qrImageBytes;
  LoginFailure? _failure;
  int _generation = 0;
  bool _disposed = false;

  LoginStage get stage => _stage;
  Uint8List? get qrImageBytes => _qrImageBytes;
  LoginFailure? get failure => _failure;

  bool get canCancel =>
      _stage == LoginStage.starting || (_session?.isActive ?? false);

  bool get canRetry =>
      _stage == LoginStage.error && (_session?.isActive ?? false);

  Future<void> start() async {
    final generation = ++_generation;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    _qrImageBytes = null;
    _failure = null;
    _stage = LoginStage.starting;
    _notify();

    final operation = _gateway.beginStart();
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
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    _qrImageBytes = null;
    _failure = null;
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
          if (_applyProgress(progress)) return;
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

  bool _applyProgress(LoginProgress progress) {
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
        _failure = null;
        _stage = LoginStage.authenticated;
        return true;
      case LoginProgress.expired:
        _stage = LoginStage.expired;
        _session = null;
        _failure = null;
        return true;
      case LoginProgress.refused:
        _stage = LoginStage.refused;
        _session = null;
        _failure = null;
        return true;
      case LoginProgress.timedOut:
        _stage = LoginStage.timedOut;
        _session = null;
        _failure = null;
        return true;
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    super.dispose();
  }
}
