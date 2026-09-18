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
  }) : _audioFocusManager =
           audioFocusManager ?? const AudioSessionForegroundAudioFocusManager(),
       _playerFactory = playerFactory ?? PlatformAudioplayersAudioPlayer.new {
    // AudioPlayerException includes player.source in its string form. QQ media
    // URIs can carry authorization, so plugin-owned logging is disabled before
    // any player exists. The adapter exposes only coarse project failures.
    audio.AudioLogger.logLevel = audio.AudioLogLevel.none;
  }

  final ForegroundAudioFocusManager _audioFocusManager;
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
      _audioFocusManager,
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

class _AudioplayersForegroundAudioSession implements ForegroundAudioSession {
  _AudioplayersForegroundAudioSession(this._player, this._audioFocusManager) {
    _stateSubscription = _player.states.listen((state) {
      if (_disposed) return;
      if (state == audio.PlayerState.stopped ||
          state == audio.PlayerState.completed) {
        unawaited(_deactivateFocus());
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
  final ForegroundAudioFocusManager _audioFocusManager;
  final StreamController<ForegroundAudioState> _states =
      StreamController.broadcast();
  final StreamController<ForegroundAudioFailure> _failures =
      StreamController.broadcast();
  final StreamController<int> _positions = StreamController.broadcast();
  late final StreamSubscription<audio.PlayerState> _stateSubscription;
  late final StreamSubscription<Object?> _eventSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  bool _disposed = false;
  bool _focusActive = false;

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
    try {
      activated = await _audioFocusManager.setActive(true);
      if (!activated) {
        _logEngineFailure(
          phase: 'focus_activate',
          failure: ForegroundAudioFailure.playback,
          errorType: 'FocusDenied',
        );
        throw const ForegroundAudioException(ForegroundAudioFailure.playback);
      }
      _focusActive = true;
      await _player.resume();
      _logEngineSuccess(phase: 'play');
    } on ForegroundAudioException {
      rethrow;
    } on Object catch (error) {
      _logEngineFailure(
        phase: activated ? 'play' : 'focus_activate',
        failure: ForegroundAudioFailure.playback,
        error: error,
      );
      if (activated) await _deactivateFocus();
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
    if (!_focusActive) return;
    _focusActive = false;
    try {
      await _audioFocusManager.setActive(false);
    } on Object catch (error) {
      _logEngineFailure(
        phase: 'focus_deactivate',
        failure: ForegroundAudioFailure.playback,
        error: error,
      );
    }
  }

  void _emitFailure(ForegroundAudioFailure failure) {
    if (!_disposed && !_failures.isClosed) {
      unawaited(_deactivateFocus());
      _failures.add(failure);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stateSubscription.cancel();
    await _eventSubscription.cancel();
    await _positionSubscription.cancel();
    await _deactivateFocus();
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
