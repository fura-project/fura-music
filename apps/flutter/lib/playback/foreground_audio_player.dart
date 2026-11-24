import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

enum ForegroundAudioState { stopped, playing, paused, completed }

enum ForegroundAudioFailure { load, playback, coreUnavailable }

enum ForegroundAudioFormat { mp3, m4a, flac }

class ForegroundAudioException implements Exception {
  const ForegroundAudioException(this.failure);

  final ForegroundAudioFailure failure;

  @override
  String toString() => 'ForegroundAudioException(${failure.name})';
}

abstract interface class ForegroundAudioEngine {
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  });

  /// Releases engine-lifetime resources after the app playback host stops.
  /// Source replacement disposes only the returned session, never the engine.
  Future<void> dispose();
}

/// Audio focus is owned by audio_session.
abstract interface class ForegroundAudioFocusManager {
  Future<bool> setActive(bool active);
}

class AudioSessionForegroundAudioFocusManager
    implements ForegroundAudioFocusManager {
  const AudioSessionForegroundAudioFocusManager();

  @override
  Future<bool> setActive(bool active) async =>
      (await AudioSession.instance).setActive(active);
}

/// One engine-lifetime arbiter around the existing audio_session owner. A
/// caller deadline never cancels the platform Future: keep the raw operation
/// reserved until it settles (including compensation for a late activation).
/// Do not activate a new lease while old platform cleanup can still release it.
class ForegroundAudioFocusOwner {
  ForegroundAudioFocusOwner(
    this._manager, {
    this.timeout = const Duration(seconds: 5),
  });

  final ForegroundAudioFocusManager _manager;
  final Duration timeout;
  ForegroundAudioFocusLease? _owner;
  _FocusOperation? _operation;
  bool _uncertain = false;
  int _generation = 0;
  int _cycle = 0;

  ForegroundAudioFocusLease createLease() =>
      ForegroundAudioFocusLease._(this, ++_generation);

  Future<bool> _activate(ForegroundAudioFocusLease lease) {
    if (lease._closed || _uncertain) return _unavailable();
    final pending = _operation;
    if (pending != null) {
      if (identical(pending.lease, lease) &&
          pending.active &&
          !pending.cancelled) {
        return pending.result;
      }
      _log(lease, 'activate', 'pending_platform');
      return _unavailable();
    }
    if (identical(_owner, lease)) return Future.value(true);
    if (_owner != null) return _unavailable();
    return _start(lease, true).result;
  }

  Future<void> _release(ForegroundAudioFocusLease lease) async {
    if (_uncertain) {
      throw const ForegroundAudioException(
        ForegroundAudioFailure.coreUnavailable,
      );
    }
    final pending = _operation;
    if (pending != null && identical(pending.lease, lease)) {
      pending.cancelled = true;
      // Wait for raw activation + its compensation, not just the caller's
      // already timed-out result. This wait is bounded independently.
      await _bounded(pending, pending.settled);
      return;
    }
    if (!identical(_owner, lease)) return;
    await _start(lease, false).result;
  }

  _FocusOperation _start(ForegroundAudioFocusLease lease, bool active) {
    final operation = _FocusOperation(lease, active, ++_cycle);
    _operation = operation;
    operation.settled = _run(operation);
    operation.result = _bounded(operation, operation.settled);
    return operation;
  }

  Future<bool> _bounded(_FocusOperation operation, Future<bool> raw) =>
      raw.timeout(
        timeout,
        onTimeout: () {
          operation.cancelled = true;
          _log(operation.lease, operation.phase, 'timeout', operation);
          throw const ForegroundAudioException(
            ForegroundAudioFailure.coreUnavailable,
          );
        },
      );

  Future<bool> _run(_FocusOperation operation) async {
    final lease = operation.lease;
    if (operation.active) _log(lease, 'activate', 'started', operation);
    try {
      if (!operation.active) {
        await _releasePlatform(operation);
        return true;
      }
      bool activated;
      try {
        activated = await _manager.setActive(true);
      } on Object {
        // An exception does not prove the platform failed before activation.
        await _releasePlatform(operation);
        throw const ForegroundAudioException(
          ForegroundAudioFailure.coreUnavailable,
        );
      }
      if (!activated) {
        _log(lease, 'activate', 'rejected', operation);
        return false;
      }
      _owner = lease;
      if (operation.cancelled || lease._closed) {
        _log(lease, 'activate', 'late_cleanup', operation);
        await _releasePlatform(operation);
        throw const ForegroundAudioException(
          ForegroundAudioFailure.coreUnavailable,
        );
      }
      _log(lease, 'activate', 'success', operation);
      return true;
    } finally {
      if (identical(_operation, operation)) _operation = null;
    }
  }

  Future<void> _releasePlatform(_FocusOperation operation) async {
    _log(operation.lease, 'release', 'started', operation);
    try {
      if (!await _manager.setActive(false)) {
        throw const ForegroundAudioException(
          ForegroundAudioFailure.coreUnavailable,
        );
      }
      _owner = null;
      _log(operation.lease, 'release', 'success', operation);
    } on Object {
      // No acknowledgement means ownership is unknown. Fail closed rather
      // than create a competing request or retry an unclassified side effect.
      _uncertain = true;
      _log(operation.lease, 'release', 'unconfirmed', operation);
      throw const ForegroundAudioException(
        ForegroundAudioFailure.coreUnavailable,
      );
    }
  }

  Future<bool> _unavailable() => Future.error(
    const ForegroundAudioException(ForegroundAudioFailure.coreUnavailable),
  );

  void _log(
    ForegroundAudioFocusLease lease,
    String phase,
    String outcome, [
    _FocusOperation? operation,
  ]) => debugPrint(
    'FURA_DIAGNOSTIC audio_focus generation=${lease.generation} '
    'cycle=${operation?.cycle ?? _cycle} phase=$phase '
    'elapsedMs=${operation?.elapsed.elapsedMilliseconds ?? 0} outcome=$outcome',
  );
}

class _FocusOperation {
  _FocusOperation(this.lease, this.active, this.cycle);
  final ForegroundAudioFocusLease lease;
  final bool active;
  final int cycle;
  final Stopwatch elapsed = Stopwatch()..start();
  bool cancelled = false;
  late final Future<bool> settled;
  late final Future<bool> result;
  String get phase => active ? 'activate' : 'release';
}

/// Per-source authority; stale releases are no-ops, including after replacement.
class ForegroundAudioFocusLease {
  ForegroundAudioFocusLease._(this._owner, this.generation);
  final ForegroundAudioFocusOwner _owner;
  final int generation;
  bool _closed = false;
  int _revision = 0;
  Future<void>? _quiescence;
  int get revision => _revision;
  bool get isActive =>
      !_closed &&
      !_owner._uncertain &&
      _owner._operation == null &&
      identical(_owner._owner, this);
  bool isCurrent(int revision) => isActive && revision == _revision;
  bool get isReleasing => _quiescence != null;

  Future<bool> activate() async {
    final revision = _revision;
    final quiescence = _quiescence;
    if (quiescence != null) {
      try {
        await quiescence.timeout(_owner.timeout);
      } on Object {
        // Waiting is bounded, but the raw control/release remains reserved.
        throw const ForegroundAudioException(
          ForegroundAudioFailure.coreUnavailable,
        );
      }
    }
    if (_closed || revision != _revision) {
      // Do not acquire on behalf of an intent revoked while awaiting pause.
      throw const ForegroundAudioException(
        ForegroundAudioFailure.coreUnavailable,
      );
    }
    return _owner._activate(this);
  }

  /// Pause/stop must settle AND abandon focus before a newer play acquires it.
  /// Revocation happens synchronously, not in a late native continuation.
  Future<void> releaseAfter(Future<void> Function() operation) {
    _revision += 1;
    final previous = _quiescence;
    final pending = () async {
      if (previous != null) await previous;
      try {
        await operation();
      } finally {
        await _owner._release(this);
      }
    }();
    _quiescence = pending;
    void clear() {
      if (identical(_quiescence, pending)) _quiescence = null;
    }

    // Attach the failure observer before callers can dispose or time out.
    pending.then<void>((_) => clear(), onError: (Object _) => clear());
    return pending;
  }

  Future<void> release() {
    ++_revision;
    return _owner._release(this);
  }

  Future<void> close() {
    _closed = true;
    return release();
  }
}

abstract interface class ForegroundAudioSession {
  Stream<ForegroundAudioState> get states;
  Stream<ForegroundAudioFailure> get failures;
  Stream<int> get positionMs;

  Future<void> play();
  Future<void> pause();
  Future<void> seekToMs(int positionMs);
  Future<void> setVolume(double volume);
  Future<void> stop();
  Future<void> dispose();
}

/// Optional focus handoff for engines that retain a source at EOF. The Queue
/// decides replay versus terminal completion before releasing audio focus.
abstract interface class ForegroundCompletionFocusSession {
  Future<void> releaseCompletionFocus();
}
