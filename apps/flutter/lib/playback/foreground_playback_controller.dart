import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';

enum ForegroundPlaybackStage {
  idle,
  loading,
  playing,
  paused,
  stopped,
  completed,
  error,
}

class ForegroundPlaybackController extends ChangeNotifier {
  ForegroundPlaybackController(this._engine);

  final ForegroundAudioEngine _engine;

  ForegroundPlaybackStage _stage = ForegroundPlaybackStage.idle;
  ForegroundAudioFailure? _failure;
  ForegroundAudioSession? _session;
  StreamSubscription<ForegroundAudioState>? _stateSubscription;
  StreamSubscription<ForegroundAudioFailure>? _failureSubscription;
  int _generation = 0;
  bool _disposed = false;

  ForegroundPlaybackStage get stage => _stage;
  ForegroundAudioFailure? get failure => _failure;
  bool get canPause => _stage == ForegroundPlaybackStage.playing;
  bool get canResume => _stage == ForegroundPlaybackStage.paused;

  Future<void> playRemote(Uri source) async {
    final generation = ++_generation;
    final previous = _detachSession();
    _failure = null;
    _setStage(ForegroundPlaybackStage.loading);
    await _stopAndDispose(previous);
    if (!_isCurrent(generation)) return;

    late final ForegroundAudioSession session;
    try {
      session = await _engine.loadRemote(source);
    } on ForegroundAudioException catch (error) {
      _fail(generation, error.failure);
      return;
    } on Object {
      _fail(generation, ForegroundAudioFailure.coreUnavailable);
      return;
    }
    if (!_isCurrent(generation)) {
      await session.dispose();
      return;
    }

    _session = session;
    _stateSubscription = session.states.listen(
      (state) => _onState(generation, session, state),
      onError: (Object _) =>
          _onFailure(generation, session, ForegroundAudioFailure.playback),
    );
    _failureSubscription = session.failures.listen(
      (failure) => _onFailure(generation, session, failure),
      onError: (Object _) =>
          _onFailure(generation, session, ForegroundAudioFailure.playback),
    );

    try {
      await session.play();
      if (_isSessionCurrent(generation, session)) {
        _setStage(ForegroundPlaybackStage.playing);
      }
    } on ForegroundAudioException catch (error) {
      _failSession(generation, session, error.failure);
    } on Object {
      _failSession(generation, session, ForegroundAudioFailure.coreUnavailable);
    }
  }

  Future<void> pause() async {
    final session = _session;
    final generation = _generation;
    if (session == null || !canPause) return;
    try {
      await session.pause();
      if (_isSessionCurrent(generation, session)) {
        _setStage(ForegroundPlaybackStage.paused);
      }
    } on ForegroundAudioException catch (error) {
      _failSession(generation, session, error.failure);
    } on Object {
      _failSession(generation, session, ForegroundAudioFailure.coreUnavailable);
    }
  }

  Future<void> resume() async {
    final session = _session;
    final generation = _generation;
    if (session == null || !canResume) return;
    try {
      await session.play();
      if (_isSessionCurrent(generation, session)) {
        _setStage(ForegroundPlaybackStage.playing);
      }
    } on ForegroundAudioException catch (error) {
      _failSession(generation, session, error.failure);
    } on Object {
      _failSession(generation, session, ForegroundAudioFailure.coreUnavailable);
    }
  }

  Future<void> stop() async {
    ++_generation;
    final session = _detachSession();
    _failure = null;
    _setStage(ForegroundPlaybackStage.stopped);
    await _stopAndDispose(session);
  }

  void _onState(
    int generation,
    ForegroundAudioSession session,
    ForegroundAudioState state,
  ) {
    if (!_isSessionCurrent(generation, session)) return;
    _setStage(switch (state) {
      ForegroundAudioState.stopped => ForegroundPlaybackStage.stopped,
      ForegroundAudioState.playing => ForegroundPlaybackStage.playing,
      ForegroundAudioState.paused => ForegroundPlaybackStage.paused,
      ForegroundAudioState.completed => ForegroundPlaybackStage.completed,
    });
  }

  void _onFailure(
    int generation,
    ForegroundAudioSession session,
    ForegroundAudioFailure failure,
  ) {
    if (_isSessionCurrent(generation, session)) {
      _failSession(generation, session, failure);
    }
  }

  void _fail(int generation, ForegroundAudioFailure failure) {
    if (!_isCurrent(generation)) return;
    _failure = failure;
    _setStage(ForegroundPlaybackStage.error);
  }

  void _failSession(
    int generation,
    ForegroundAudioSession session,
    ForegroundAudioFailure failure,
  ) {
    if (!_isSessionCurrent(generation, session)) return;
    ++_generation;
    final failed = _detachSession();
    _failure = failure;
    _setStage(ForegroundPlaybackStage.error);
    unawaited(_stopAndDispose(failed));
  }

  ForegroundAudioSession? _detachSession() {
    final session = _session;
    _session = null;
    unawaited(_stateSubscription?.cancel());
    unawaited(_failureSubscription?.cancel());
    _stateSubscription = null;
    _failureSubscription = null;
    return session;
  }

  Future<void> _stopAndDispose(ForegroundAudioSession? session) async {
    if (session == null) return;
    try {
      await session.stop();
    } on Object {
      // Replacement/terminal cleanup must continue through disposal. There is
      // no active presentation generation to receive this old failure.
    }
    try {
      await session.dispose();
    } on Object {
      // Disposal is terminal for an already detached session. Its failure
      // cannot be allowed to revive or block a replacement source.
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _isSessionCurrent(int generation, ForegroundAudioSession session) =>
      _isCurrent(generation) && identical(_session, session);

  void _setStage(ForegroundPlaybackStage stage) {
    if (_disposed || _stage == stage) return;
    _stage = stage;
    notifyListeners();
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      ++_generation;
      final session = _detachSession();
      unawaited(_stopAndDispose(session));
    }
    super.dispose();
  }
}
