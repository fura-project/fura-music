import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;

enum ForegroundAudioState { stopped, playing, paused, completed }

enum ForegroundAudioFailure { load, playback, coreUnavailable }

class ForegroundAudioException implements Exception {
  const ForegroundAudioException(this.failure);

  final ForegroundAudioFailure failure;

  @override
  String toString() => 'ForegroundAudioException(${failure.name})';
}

abstract interface class ForegroundAudioEngine {
  Future<ForegroundAudioSession> loadRemote(Uri source);
}

abstract interface class ForegroundAudioSession {
  Stream<ForegroundAudioState> get states;
  Stream<ForegroundAudioFailure> get failures;
  Stream<int> get positionMs;

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}

class AudioplayersForegroundAudioEngine implements ForegroundAudioEngine {
  AudioplayersForegroundAudioEngine() {
    // AudioPlayerException includes player.source in its string form. QQ media
    // URIs can carry authorization, so plugin-owned logging is disabled before
    // any player exists. The adapter exposes only coarse project failures.
    audio.AudioLogger.logLevel = audio.AudioLogLevel.none;
  }

  @override
  Future<ForegroundAudioSession> loadRemote(Uri source) async {
    if ((source.scheme != 'http' && source.scheme != 'https') ||
        !source.hasAuthority) {
      throw const ForegroundAudioException(ForegroundAudioFailure.load);
    }

    final session = _AudioplayersForegroundAudioSession(audio.AudioPlayer());
    try {
      await session.prepare(source);
      return session;
    } on Object {
      await session.dispose();
      throw const ForegroundAudioException(ForegroundAudioFailure.load);
    }
  }
}

class _AudioplayersForegroundAudioSession implements ForegroundAudioSession {
  _AudioplayersForegroundAudioSession(this._player) {
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (_disposed) return;
      _states.add(switch (state) {
        audio.PlayerState.stopped => ForegroundAudioState.stopped,
        audio.PlayerState.playing => ForegroundAudioState.playing,
        audio.PlayerState.paused => ForegroundAudioState.paused,
        audio.PlayerState.completed => ForegroundAudioState.completed,
        audio.PlayerState.disposed => ForegroundAudioState.stopped,
      });
    }, onError: (Object _) => _emitFailure(ForegroundAudioFailure.playback));
    _eventSubscription = _player.eventStream.listen(
      (_) {},
      onError: (Object _) => _emitFailure(ForegroundAudioFailure.playback),
    );
    _positionSubscription = _player.onPositionChanged.listen((position) {
      if (_disposed || position.isNegative) return;
      _positions.add(position.inMilliseconds);
    }, onError: (Object _) => _emitFailure(ForegroundAudioFailure.playback));
  }

  final audio.AudioPlayer _player;
  final StreamController<ForegroundAudioState> _states =
      StreamController.broadcast();
  final StreamController<ForegroundAudioFailure> _failures =
      StreamController.broadcast();
  final StreamController<int> _positions = StreamController.broadcast();
  late final StreamSubscription<audio.PlayerState> _stateSubscription;
  late final StreamSubscription<audio.AudioEvent> _eventSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  bool _disposed = false;

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  Future<void> prepare(Uri source) => _invoke(() async {
    await _player.setReleaseMode(audio.ReleaseMode.stop);
    await _player.setSourceUrl(source.toString(), mimeType: 'audio/mpeg');
  }, ForegroundAudioFailure.load);

  @override
  Future<void> play() =>
      _invoke(_player.resume, ForegroundAudioFailure.playback);

  @override
  Future<void> pause() =>
      _invoke(_player.pause, ForegroundAudioFailure.playback);

  @override
  Future<void> stop() => _invoke(_player.stop, ForegroundAudioFailure.playback);

  Future<void> _invoke(
    Future<void> Function() operation,
    ForegroundAudioFailure failure,
  ) async {
    if (_disposed) {
      throw const ForegroundAudioException(
        ForegroundAudioFailure.coreUnavailable,
      );
    }
    try {
      await operation();
    } on Object {
      throw ForegroundAudioException(failure);
    }
  }

  void _emitFailure(ForegroundAudioFailure failure) {
    if (!_disposed && !_failures.isClosed) _failures.add(failure);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stateSubscription.cancel();
    await _eventSubscription.cancel();
    await _positionSubscription.cancel();
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
