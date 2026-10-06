import 'dart:async';
import 'dart:developer' as developer;

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

/// Audio focus remains owned by audio_session. The audioplayers Android
/// implementation is configured not to create a competing focus request.
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
  int get revision => _revision;
  bool get isActive =>
      !_closed &&
      !_owner._uncertain &&
      _owner._operation == null &&
      identical(_owner._owner, this);
  bool isCurrent(int revision) => isActive && revision == _revision;
  Future<bool> activate() => _owner._activate(this);
  Future<void> release() {
    ++_revision;
    return _owner._release(this);
  }

  Future<void> close() {
    _closed = true;
    return release();
  }
}

@visibleForTesting
final projectAudioplayersAudioContext = audio.AudioContext(
  android: const audio.AudioContextAndroid(
    audioFocus: audio.AndroidAudioFocus.none,
  ),
);

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

/// Narrow testable seam around one audioplayers source-lifetime AudioPlayer.
///
/// The production wrapper is intentionally mechanical. This seam lets both
/// music engines run the same behavioral contract without exposing either
/// plugin type to Queue or controller tests.
abstract interface class AudioplayersAudioPlayer {
  Stream<audio.PlayerState> get states;
  Stream<Object?> get events;
  Stream<Duration> get positions;

  Future<void> setAudioContext(audio.AudioContext context);
  Future<void> setReleaseMode(audio.ReleaseMode mode);
  Future<void> setSourceUrl(String source, {required String mimeType});
  Future<void> resume();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> stop();
  Future<void> dispose();
}

class PlatformAudioplayersAudioPlayer implements AudioplayersAudioPlayer {
  PlatformAudioplayersAudioPlayer() : _player = audio.AudioPlayer();

  final audio.AudioPlayer _player;

  @override
  Stream<audio.PlayerState> get states => _player.onPlayerStateChanged;

  @override
  Stream<Object?> get events => _player.eventStream;

  @override
  Stream<Duration> get positions => _player.onPositionChanged;

  @override
  Future<void> setAudioContext(audio.AudioContext context) =>
      _player.setAudioContext(context);

  @override
  Future<void> setReleaseMode(audio.ReleaseMode mode) =>
      _player.setReleaseMode(mode);

  @override
  Future<void> setSourceUrl(String source, {required String mimeType}) =>
      _player.setSourceUrl(source, mimeType: mimeType);

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

class AudioplayersForegroundAudioEngine implements ForegroundAudioEngine {
  AudioplayersForegroundAudioEngine({
    ForegroundAudioFocusManager? audioFocusManager,
    AudioplayersAudioPlayer Function()? playerFactory,
    Duration focusTimeout = const Duration(seconds: 5),
  }) : _audioFocusOwner = ForegroundAudioFocusOwner(
         audioFocusManager ?? const AudioSessionForegroundAudioFocusManager(),
         timeout: focusTimeout,
       ),
       _playerFactory = playerFactory ?? PlatformAudioplayersAudioPlayer.new {
    // AudioPlayerException includes player.source in its string form. QQ media
    // URIs can carry authorization, so plugin-owned logging is disabled before
    // any player exists. The adapter exposes only coarse project failures.
    audio.AudioLogger.logLevel = audio.AudioLogLevel.none;
  }

  final ForegroundAudioFocusOwner _audioFocusOwner;
  final AudioplayersAudioPlayer Function() _playerFactory;

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) async {
    if ((source.scheme != 'http' && source.scheme != 'https') ||
        !source.hasAuthority) {
      throw const ForegroundAudioException(ForegroundAudioFailure.load);
    }

    final session = _AudioplayersForegroundAudioSession(
      _playerFactory(),
      _audioFocusOwner.createLease(),
    );
    try {
      await session.prepare(source, format);
      _logEngineSuccess(phase: 'prepare');
      return session;
    } on Object {
      await session.dispose();
      throw const ForegroundAudioException(ForegroundAudioFailure.load);
    }
  }

  @override
  Future<void> dispose() async {
    // audioplayers sessions own their individual plugin players. Keeping this
    // engine-level hook a no-op preserves the production baseline while giving
    // long-lived candidate engines one explicit terminal lifecycle boundary.
  }
}

class _AudioplayersForegroundAudioSession
    implements ForegroundAudioSession, ForegroundCompletionFocusSession {
  _AudioplayersForegroundAudioSession(this._player, this._focus) {
    _stateSubscription = _player.states.listen((state) {
      if (_disposed) return;
      if (state == audio.PlayerState.stopped) {
        unawaited(_releaseFocusBestEffort());
      }
      _states.add(switch (state) {
        audio.PlayerState.stopped => ForegroundAudioState.stopped,
        audio.PlayerState.playing => ForegroundAudioState.playing,
        audio.PlayerState.paused => ForegroundAudioState.paused,
        audio.PlayerState.completed => ForegroundAudioState.completed,
        audio.PlayerState.disposed => ForegroundAudioState.stopped,
      });
    }, onError: (Object _) => _emitFailure(ForegroundAudioFailure.playback));
    _eventSubscription = _player.events.listen(
      (_) {},
      onError: (Object _) => _emitFailure(ForegroundAudioFailure.playback),
    );
    _positionSubscription = _player.positions.listen((position) {
      if (_disposed || position.isNegative) return;
      _positions.add(position.inMilliseconds);
    }, onError: (Object _) => _emitFailure(ForegroundAudioFailure.playback));
  }

  final AudioplayersAudioPlayer _player;
  final ForegroundAudioFocusLease _focus;
  final StreamController<ForegroundAudioState> _states =
      StreamController.broadcast();
  final StreamController<ForegroundAudioFailure> _failures =
      StreamController.broadcast();
  final StreamController<int> _positions = StreamController.broadcast();
  late final StreamSubscription<audio.PlayerState> _stateSubscription;
  late final StreamSubscription<Object?> _eventSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  bool _disposed = false;

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  Future<void> prepare(Uri source, ForegroundAudioFormat format) => _invoke(
    () async {
      // audioplayers_android defaults to AUDIOFOCUS_GAIN. Fura has one
      // audio_session focus owner, so disable the plugin-local request before
      // the source is loaded and before playback can begin.
      await _player.setAudioContext(projectAudioplayersAudioContext);
      await _player.setReleaseMode(audio.ReleaseMode.stop);
      await _player.setSourceUrl(
        source.toString(),
        mimeType: switch (format) {
          ForegroundAudioFormat.mp3 => 'audio/mpeg',
          ForegroundAudioFormat.m4a => 'audio/mp4',
          ForegroundAudioFormat.flac => 'audio/flac',
        },
      );
    },
    ForegroundAudioFailure.load,
    phase: 'prepare',
  );

  @override
  Future<void> play() async {
    if (_disposed) {
      throw const ForegroundAudioException(
        ForegroundAudioFailure.coreUnavailable,
      );
    }
    var activated = false;
    final focusRevision = _focus.revision;
    try {
      activated = await _focus.activate();
      if (!activated) {
        _logEngineFailure(
          phase: 'focus_activate',
          failure: ForegroundAudioFailure.playback,
          errorType: 'FocusDenied',
        );
        throw const ForegroundAudioException(ForegroundAudioFailure.playback);
      }
      if (_disposed || !_focus.isCurrent(focusRevision)) {
        throw const ForegroundAudioException(
          ForegroundAudioFailure.coreUnavailable,
        );
      }
      await _player.resume();
      _logEngineSuccess(phase: 'play');
    } on ForegroundAudioException {
      if (activated && _focus.revision == focusRevision) {
        await _releaseFocusBestEffort();
      }
      rethrow;
    } on Object catch (error) {
      _logEngineFailure(
        phase: activated ? 'play' : 'focus_activate',
        failure: ForegroundAudioFailure.playback,
        error: error,
      );
      if (activated && _focus.revision == focusRevision) {
        await _releaseFocusBestEffort();
      }
      throw const ForegroundAudioException(ForegroundAudioFailure.playback);
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _invoke(
        _player.pause,
        ForegroundAudioFailure.playback,
        phase: 'pause',
      );
    } finally {
      await _deactivateFocus();
    }
  }

  @override
  Future<void> seekToMs(int positionMs) async {
    if (positionMs < 0) {
      throw const ForegroundAudioException(ForegroundAudioFailure.playback);
    }
    await _invoke(
      () => _player.seek(Duration(milliseconds: positionMs)),
      ForegroundAudioFailure.playback,
      phase: 'seek',
    );
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw const ForegroundAudioException(ForegroundAudioFailure.playback);
    }
    await _invoke(
      () => _player.setVolume(volume),
      ForegroundAudioFailure.playback,
      phase: 'volume',
    );
  }

  @override
  Future<void> stop() async {
    try {
      await _invoke(
        _player.stop,
        ForegroundAudioFailure.playback,
        phase: 'stop',
      );
    } finally {
      await _deactivateFocus();
    }
  }

  Future<void> _invoke(
    Future<void> Function() operation,
    ForegroundAudioFailure failure, {
    required String phase,
  }) async {
    if (_disposed) {
      throw const ForegroundAudioException(
        ForegroundAudioFailure.coreUnavailable,
      );
    }
    try {
      await operation();
    } on Object catch (error) {
      _logEngineFailure(phase: phase, failure: failure, error: error);
      throw ForegroundAudioException(failure);
    }
  }

  Future<void> _deactivateFocus() async {
    await _focus.release();
  }

  Future<void> _releaseFocusBestEffort() async {
    try {
      await _deactivateFocus();
    } on Object catch (error) {
      _logEngineFailure(
        phase: 'focus_deactivate',
        failure: ForegroundAudioFailure.playback,
        error: error,
      );
    }
  }

  @override
  Future<void> releaseCompletionFocus() => _deactivateFocus();

  void _emitFailure(ForegroundAudioFailure failure) {
    if (!_disposed && !_failures.isClosed) {
      unawaited(_releaseFocusBestEffort());
      _failures.add(failure);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final release = _focus.close();
    // Attach an error handler before cancelling subscriptions.
    final cleanup = release.then<void>((_) {}, onError: (Object _) {});
    await _stateSubscription.cancel();
    await _eventSubscription.cancel();
    await _positionSubscription.cancel();
    await cleanup;
    try {
      await _player.dispose();
    } on Object {
      // Disposal is terminal. Do not expose an upstream exception whose
      // string form may contain the source URI.
    } finally {
      await _states.close();
      await _failures.close();
      await _positions.close();
    }
  }
}

void _logEngineSuccess({required String phase}) {
  developer.log(
    'FURA_DIAGNOSTIC playback_engine phase=$phase outcome=success',
    name: 'fura_music.playback',
  );
}

void _logEngineFailure({
  required String phase,
  required ForegroundAudioFailure failure,
  Object? error,
  String? errorType,
}) {
  final platformCode = error is PlatformException
      ? _safePlatformCode(error.code)
      : 'none';
  developer.log(
    'FURA_DIAGNOSTIC playback_engine phase=$phase outcome=failure '
    'failure=${failure.name} errorType=${errorType ?? error?.runtimeType ?? 'none'} '
    'platformCode=$platformCode',
    name: 'fura_music.playback',
    level: 1000,
  );
}

String _safePlatformCode(String value) =>
    RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(value) ? value : 'unrecognized';
