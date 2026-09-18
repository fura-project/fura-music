import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:media_kit/media_kit.dart';

/// Narrow seam around media_kit's app-lifetime [Player].
///
/// It deliberately exposes no playlist operations: Rust remains the only
/// canonical Queue owner, and each [open] replaces the one current source.
abstract interface class MediaKitAudioPlayer {
  Stream<bool> get playing;
  Stream<bool> get completed;
  Stream<Duration> get position;
  Stream<String> get errors;

  Future<void> open(Uri source);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double percent);
  Future<void> dispose();
}

class PlatformMediaKitAudioPlayer implements MediaKitAudioPlayer {
  PlatformMediaKitAudioPlayer()
    : _player = Player(
        configuration: const PlayerConfiguration(
          vo: 'null',
          title: 'fura music',
          logLevel: MPVLogLevel.error,
        ),
      );

  final Player _player;

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<bool> get completed => _player.stream.completed;

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Future<void> open(Uri source) =>
      _player.open(Media(source.toString()), play: false);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double percent) => _player.setVolume(percent);

  @override
  Future<void> dispose() => _player.dispose();
}

/// Experimental music engine backed by one engine-lifetime media_kit Player.
///
/// Source replacement reuses that Player through [MediaKitAudioPlayer.open]. A
/// per-source session owns only subscriptions and audio-focus activation; its
/// disposal never destroys the shared Player. The Player is destroyed exactly
/// once when this engine reaches terminal disposal.
class MediaKitForegroundAudioEngine implements ForegroundAudioEngine {
  MediaKitForegroundAudioEngine({
    MediaKitAudioPlayer? player,
    ForegroundAudioFocusManager? audioFocusManager,
  }) : _player = player ?? PlatformMediaKitAudioPlayer(),
       _audioFocusManager =
           audioFocusManager ?? const AudioSessionForegroundAudioFocusManager();

  final MediaKitAudioPlayer _player;
  final ForegroundAudioFocusManager _audioFocusManager;
  Future<void> _operationTail = Future<void>.value();
  bool _disposed = false;

  @visibleForTesting
  MediaKitAudioPlayer get debugPlayer => _player;

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) async {
    if (_disposed ||
        (source.scheme != 'http' && source.scheme != 'https') ||
        !source.hasAuthority) {
      throw const ForegroundAudioException(ForegroundAudioFailure.load);
    }
    try {
      await _serialize(() => _player.open(source));
      if (_disposed) {
        throw const ForegroundAudioException(
          ForegroundAudioFailure.coreUnavailable,
        );
      }
      return _MediaKitForegroundAudioSession(
        _player,
        _audioFocusManager,
        _serialize,
      );
    } on ForegroundAudioException {
      rethrow;
    } on Object {
      // media_kit error strings may contain the source. Keep the adapter's
      // outward failure typed and coarse, and never log the upstream cause.
      throw const ForegroundAudioException(ForegroundAudioFailure.load);
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _operationTail.then((_) {
      if (_disposed) {
        throw const ForegroundAudioException(
          ForegroundAudioFailure.coreUnavailable,
        );
      }
      return operation();
    });
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _operationTail;
    try {
      await _player.dispose();
    } on Object {
      // Terminal cleanup cannot expose media_kit's source-bearing error text.
    }
  }
}

class _MediaKitForegroundAudioSession implements ForegroundAudioSession {
  _MediaKitForegroundAudioSession(
    this._player,
    this._audioFocusManager,
    this._serialize,
  ) {
    _subscriptions.addAll([
      _player.playing.listen((playing) {
        if (_disposed) return;
        if (playing) {
          _states.add(ForegroundAudioState.playing);
        } else if (_lastState == ForegroundAudioState.playing) {
          _states.add(ForegroundAudioState.paused);
        }
        _lastState = playing
            ? ForegroundAudioState.playing
            : ForegroundAudioState.paused;
      }, onError: (Object _) => _emitFailure()),
      _player.completed.listen((completed) {
        if (!completed || _disposed) return;
        _lastState = ForegroundAudioState.completed;
        unawaited(_deactivateFocus());
        _states.add(ForegroundAudioState.completed);
      }, onError: (Object _) => _emitFailure()),
      _player.position.listen((position) {
        if (_disposed || position.isNegative) return;
        _positions.add(position.inMilliseconds);
      }, onError: (Object _) => _emitFailure()),
      _player.errors.listen(
        (_) => _emitFailure(),
        onError: (Object _) => _emitFailure(),
      ),
    ]);
  }

  final MediaKitAudioPlayer _player;
  final ForegroundAudioFocusManager _audioFocusManager;
  final Future<void> Function(Future<void> Function()) _serialize;
  final StreamController<ForegroundAudioState> _states =
      StreamController.broadcast();
  final StreamController<ForegroundAudioFailure> _failures =
      StreamController.broadcast();
  final StreamController<int> _positions = StreamController.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  ForegroundAudioState _lastState = ForegroundAudioState.stopped;
  bool _focusActive = false;
  bool _disposed = false;

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> play() async {
    _ensureActive();
    var activated = false;
    try {
      activated = await _audioFocusManager.setActive(true);
      if (!activated) {
        throw const ForegroundAudioException(ForegroundAudioFailure.playback);
      }
      _focusActive = true;
      await _serialize(_player.play);
    } on ForegroundAudioException {
      rethrow;
    } on Object {
      if (activated) await _deactivateFocus();
      throw const ForegroundAudioException(ForegroundAudioFailure.playback);
    }
  }

  @override
  Future<void> pause() async {
    _ensureActive();
    try {
      await _serialize(_player.pause);
    } on ForegroundAudioException {
      rethrow;
    } on Object {
      throw const ForegroundAudioException(ForegroundAudioFailure.playback);
    } finally {
      await _deactivateFocus();
    }
  }

  @override
  Future<void> seekToMs(int positionMs) async {
    _ensureActive();
    if (positionMs < 0) {
      throw const ForegroundAudioException(ForegroundAudioFailure.playback);
    }
    try {
      await _serialize(() => _player.seek(Duration(milliseconds: positionMs)));
    } on ForegroundAudioException {
      rethrow;
    } on Object {
      throw const ForegroundAudioException(ForegroundAudioFailure.playback);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _ensureActive();
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw const ForegroundAudioException(ForegroundAudioFailure.playback);
    }
    try {
      await _serialize(() => _player.setVolume(volume * 100));
    } on ForegroundAudioException {
      rethrow;
    } on Object {
      throw const ForegroundAudioException(ForegroundAudioFailure.playback);
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    try {
      await _serialize(_player.stop);
      if (!_disposed) {
        _lastState = ForegroundAudioState.stopped;
        _states.add(ForegroundAudioState.stopped);
      }
    } on ForegroundAudioException {
      rethrow;
    } on Object {
      throw const ForegroundAudioException(ForegroundAudioFailure.playback);
    } finally {
      await _deactivateFocus();
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw const ForegroundAudioException(
        ForegroundAudioFailure.coreUnavailable,
      );
    }
  }

  void _emitFailure() {
    if (_disposed || _failures.isClosed) return;
    unawaited(_deactivateFocus());
    _failures.add(ForegroundAudioFailure.playback);
  }

  Future<void> _deactivateFocus() async {
    if (!_focusActive) return;
    _focusActive = false;
    try {
      await _audioFocusManager.setActive(false);
    } on Object {
      // Focus release is best effort and remains secret-free.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _deactivateFocus();
    await _states.close();
    await _failures.close();
    await _positions.close();
  }
}
