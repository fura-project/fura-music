import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:media_kit/media_kit.dart';

/// Current-source packet cache, not persistent/offline media storage. A
/// bounded memory cache avoids mpv's disk-cache metadata-only byte limits.
const sourceLifetimeCacheProperties = <String, String>{
  'cache': 'yes',
  'cache-on-disk': 'no',
  'demuxer-seekable-cache': 'yes',
  'demuxer-max-bytes': '67108864',
  'demuxer-max-back-bytes': '67108864',
  'demuxer-readahead-secs': '600',
  'keep-open': 'yes',
};

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
  bool _cacheConfigured = false;

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<bool> get completed => _player.stream.completed;

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Future<void> open(Uri source) async {
    if (!_cacheConfigured) {
      final native = _player.platform;
      if (native is! NativePlayer) {
        throw const ForegroundAudioException(ForegroundAudioFailure.load);
      }
      for (final entry in sourceLifetimeCacheProperties.entries) {
        await native.setProperty(entry.key, entry.value);
      }
      _cacheConfigured = true;
    }
    await _player.open(Media(source.toString()), play: false);
  }

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
  Future<void> dispose() async {
    // A stalled plugin operation may hold NativePlayer's synchronization lock.
    // Terminal retirement must not wait for that same lock again.
    final native = _player.platform;
    if (native is NativePlayer) {
      await native.dispose(synchronized: false);
    } else {
      await _player.dispose();
    }
  }
}

/// Experimental music engine backed by one engine-lifetime media_kit Player.
///
/// Source replacement reuses that Player through [MediaKitAudioPlayer.open]. A
/// per-source session owns only subscriptions and audio-focus activation; its
/// disposal never destroys the shared Player. A stalled generation may be
/// retired once and replaced on an explicit subsequent load; normal Track
/// replacement and replay never construct another Player.
class MediaKitForegroundAudioEngine implements ForegroundAudioEngine {
  MediaKitForegroundAudioEngine({
    MediaKitAudioPlayer? player,
    MediaKitAudioPlayer Function()? playerFactory,
    ForegroundAudioFocusManager? audioFocusManager,
    this.openTimeout = const Duration(seconds: 15),
    this.controlTimeout = const Duration(seconds: 5),
  }) : _playerFactory = playerFactory ?? PlatformMediaKitAudioPlayer.new,
       _player = player ?? (playerFactory ?? PlatformMediaKitAudioPlayer.new)(),
       _audioFocusManager =
           audioFocusManager ?? const AudioSessionForegroundAudioFocusManager();

  final MediaKitAudioPlayer Function() _playerFactory;
  MediaKitAudioPlayer _player;
  final ForegroundAudioFocusManager _audioFocusManager;
  final Duration openTimeout;
  final Duration controlTimeout;
  Future<void> _operationTail = Future<void>.value();
  Future<void>? _recovery;
  Future<void>? _playerRetirement;
  int _playerGeneration = 0;
  int _cycle = 0;
  int _rebuildCount = 0;
  bool _stalled = false;
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
      if (_stalled) {
        await _recoverPlayer();
      }
      final generation = _playerGeneration;
      final player = _player;
      await _serialize('open', generation, () => player.open(source));
      if (_disposed || generation != _playerGeneration) {
        throw const ForegroundAudioException(
          ForegroundAudioFailure.coreUnavailable,
        );
      }
      return _MediaKitForegroundAudioSession(
        player,
        _audioFocusManager,
        (phase, operation) => _serialize(phase, generation, operation),
      );
    } on ForegroundAudioException {
      rethrow;
    } on Object {
      // media_kit error strings may contain the source. Keep the adapter's
      // outward failure typed and coarse, and never log the upstream cause.
      throw const ForegroundAudioException(ForegroundAudioFailure.load);
    }
  }

  Future<void> _serialize(
    String phase,
    int generation,
    Future<void> Function() operation,
  ) {
    final cycle = ++_cycle;
    final result = _operationTail.then((_) async {
      if (_disposed || _stalled || generation != _playerGeneration) {
        throw const ForegroundAudioException(
          ForegroundAudioFailure.coreUnavailable,
        );
      }
      final elapsed = Stopwatch()..start();
      _logMediaKit(
        'media_operation generation=$generation cycle=$cycle phase=$phase '
        'elapsedMs=0 outcome=started',
      );
      try {
        await operation().timeout(
          phase == 'open' ? openTimeout : controlTimeout,
        );
        if (_disposed || generation != _playerGeneration) {
          throw const ForegroundAudioException(
            ForegroundAudioFailure.coreUnavailable,
          );
        }
        _logMediaKit(
          'media_operation generation=$generation cycle=$cycle phase=$phase '
          'elapsedMs=${elapsed.elapsedMilliseconds} outcome=success',
        );
      } on TimeoutException {
        _stalled = true;
        _logMediaKit(
          'engine_stall generation=$generation cycle=$cycle '
          'phase=$phase elapsedMs=${elapsed.elapsedMilliseconds} outcome=timeout',
        );
        throw const ForegroundAudioException(
          ForegroundAudioFailure.coreUnavailable,
        );
      } on Object {
        _logMediaKit(
          'media_operation generation=$generation cycle=$cycle phase=$phase '
          'elapsedMs=${elapsed.elapsedMilliseconds} outcome=failure',
        );
        rethrow;
      }
    });
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _recoverPlayer() =>
      _recovery ??= _rebuildPlayer().whenComplete(() => _recovery = null);

  Future<void> _retirePlayer() => _playerRetirement ??= _player.dispose();

  Future<void> _rebuildPlayer() async {
    // Exactly one rebuild per engine lifetime. Await SDK retirement (which
    // stops the old source and detaches events); fail closed if it cannot
    // finish. media_kit 1.2.6 schedules native handle destruction five seconds
    // later, so this bounds active Players, not instantaneous native handles.
    await _operationTail;
    if (!_stalled) return;
    if (_disposed || _rebuildCount >= 1) {
      _logMediaKit(
        'engine_rebuild generation=$_playerGeneration rebuildCount=$_rebuildCount '
        'outcome=rejected',
      );
      throw const ForegroundAudioException(
        ForegroundAudioFailure.coreUnavailable,
      );
    }
    ++_rebuildCount;
    ++_playerGeneration;
    _logMediaKit(
      'engine_rebuild generation=$_playerGeneration rebuildCount=$_rebuildCount '
      'outcome=started',
    );
    try {
      await _retirePlayer().timeout(controlTimeout);
      if (_disposed) return;
      _player = _playerFactory();
      _playerRetirement = null;
      _stalled = false;
      _logMediaKit(
        'engine_rebuild generation=$_playerGeneration rebuildCount=$_rebuildCount '
        'outcome=success',
      );
    } on Object {
      _logMediaKit(
        'engine_rebuild generation=$_playerGeneration rebuildCount=$_rebuildCount '
        'outcome=failure',
      );
      throw const ForegroundAudioException(
        ForegroundAudioFailure.coreUnavailable,
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _operationTail;
    try {
      final recovery = _recovery;
      if (recovery != null) {
        await recovery.timeout(controlTimeout);
      }
      await _retirePlayer().timeout(controlTimeout);
    } on Object {
      // Terminal cleanup cannot expose media_kit's source-bearing error text.
    }
  }
}

class _MediaKitForegroundAudioSession
    implements ForegroundAudioSession, ForegroundCompletionFocusSession {
  _MediaKitForegroundAudioSession(
    this._player,
    this._audioFocusManager,
    this._serialize,
  ) {
    _subscriptions.addAll([
      _player.playing.listen((playing) {
        if (_disposed) return;
        if (!playing && _lastState == ForegroundAudioState.completed) return;
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
        if (!completed ||
            _disposed ||
            _lastState == ForegroundAudioState.completed) {
          return;
        }
        _lastState = ForegroundAudioState.completed;
        _logMediaKit(
          'playback_completed focus=${_focusActive ? 'retained' : 'inactive'}',
        );
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
  final Future<void> Function(String, Future<void> Function()) _serialize;
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
      if (!_focusActive) {
        _logMediaKit('audio_focus phase=activate outcome=started');
      }
      activated = _focusActive || await _audioFocusManager.setActive(true);
      if (!activated) {
        _logMediaKit('audio_focus phase=activate outcome=rejected');
        throw const ForegroundAudioException(ForegroundAudioFailure.playback);
      }
      if (!_focusActive) {
        _logMediaKit('audio_focus phase=activate outcome=success');
      }
      _focusActive = true;
      _lastState = ForegroundAudioState.playing;
      await _serialize('play', _player.play);
    } on ForegroundAudioException {
      if (activated) await _deactivateFocus();
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
      await _serialize('pause', _player.pause);
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
      await _serialize(
        'seek',
        () => _player.seek(Duration(milliseconds: positionMs)),
      );
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
      await _serialize('volume', () => _player.setVolume(volume * 100));
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
      await _serialize('stop', _player.stop);
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
    _logMediaKit('native_player_failure outcome=reported');
    unawaited(_deactivateFocus());
    _failures.add(ForegroundAudioFailure.playback);
  }

  Future<void> _deactivateFocus() async {
    if (!_focusActive) return;
    _focusActive = false;
    _logMediaKit('audio_focus phase=release outcome=started');
    try {
      await _audioFocusManager.setActive(false);
      _logMediaKit('audio_focus phase=release outcome=success');
    } on Object {
      _logMediaKit('audio_focus phase=release outcome=failure');
      // Focus release is best effort and remains secret-free.
    }
  }

  @override
  Future<void> releaseCompletionFocus() => _deactivateFocus();

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

// Only locally constructed phases/categories/counters enter this message.
// stdout is intentional: dart:developer logs alone require VM service tooling
// and cannot serve as an Android release logcat acceptance trace.
void _logMediaKit(String detail) => debugPrint('FURA_DIAGNOSTIC $detail');
