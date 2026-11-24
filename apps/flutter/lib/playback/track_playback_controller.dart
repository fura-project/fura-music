import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';

enum TrackPlaybackStage {
  idle,
  resolving,
  loading,
  playing,
  paused,
  stopped,
  completed,
  resolutionError,
  engineError,
}

class TrackPlaybackController extends ChangeNotifier {
  TrackPlaybackController(this._resolutionGateway, this._playback)
    : _lastPlaybackPositionMs = _playback.positionMs,
      _lastPlaybackVolume = _playback.volume,
      _positionMs = ValueNotifier<int>(_playback.positionMs) {
    _playback.addListener(_onPlaybackChanged);
  }

  final MediaResolutionGateway _resolutionGateway;
  final ForegroundPlaybackController _playback;

  TrackPlaybackStage _stage = TrackPlaybackStage.idle;
  PlaylistTrackSummary? _track;
  MediaResolutionFailure? _resolutionFailure;
  ForegroundAudioFailure? _engineFailure;
  PlaybackAudioQuality? _resolvedQuality;
  MediaResolutionOperation? _resolutionOperation;
  Future<void> _activationTail = Future<void>.value();
  int _generation = 0;
  bool _resolving = false;
  bool _pausedSelection = false;
  bool _disposed = false;
  int _lastPlaybackPositionMs;
  double _lastPlaybackVolume;
  final _TrackPlaybackSignalNotifier _stateChanges =
      _TrackPlaybackSignalNotifier();
  final ValueNotifier<int> _positionMs;

  TrackPlaybackStage get stage => _stage;
  PlaylistTrackSummary? get track => _track;
  int get sourceGeneration => _generation;
  MediaResolutionFailure? get resolutionFailure => _resolutionFailure;
  ForegroundAudioFailure? get engineFailure => _engineFailure;
  PlaybackAudioQuality? get resolvedQuality => _resolvedQuality;
  int get positionMs => _playback.positionMs;
  Listenable get positionDiscontinuity => _playback.positionDiscontinuity;
  double get volume => _playback.volume;

  /// Notifies only on non-position playback state changes (track, stage,
  /// failures, resolved quality, volume). High-frequency position ticks stay
  /// on [positionMsListenable] and this controller's broader [Listenable].
  Listenable get stateListenable => _stateChanges;

  /// Notifies whenever the playback position in milliseconds changes.
  ValueListenable<int> get positionMsListenable => _positionMs;
  int? get durationMs {
    final durationSeconds = _track?.durationSeconds;
    return durationSeconds == null || durationSeconds <= 0
        ? null
        : durationSeconds * 1000;
  }

  bool get canPause => _stage == TrackPlaybackStage.playing;
  bool get canResume => _stage == TrackPlaybackStage.paused;
  bool get canSeek =>
      durationMs != null &&
      (_stage == TrackPlaybackStage.playing ||
          (_stage == TrackPlaybackStage.paused && _playback.canResume));
  bool get requiresAuthentication => switch (_resolutionFailure) {
    MediaResolutionFailure.authenticationRequired ||
    MediaResolutionFailure.credentialRejected ||
    MediaResolutionFailure.credentialRejectedStorageCleanupFailed ||
    MediaResolutionFailure.replaced ||
    MediaResolutionFailure.cancelled => true,
    _ => false,
  };
  bool get canActivate =>
      _track != null &&
      !requiresAuthentication &&
      _stage != TrackPlaybackStage.resolving &&
      _stage != TrackPlaybackStage.loading;

  Future<void> activate() {
    final generation = _generation;
    if (_track == null || !canActivate || _disposed) return Future.value();
    final request = _activationTail.then<void>(
      (_) => _activateCurrent(generation),
    );
    _activationTail = request.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return request;
  }

  Future<void> _activateCurrent(int generation) async {
    if (!_isCurrent(generation)) return;
    final current = _track;
    if (current == null || !canActivate) return;
    switch (_stage) {
      case TrackPlaybackStage.playing:
        await pause();
        return;
      case TrackPlaybackStage.paused:
        await resume();
        return;
      case TrackPlaybackStage.idle:
      case TrackPlaybackStage.stopped:
      case TrackPlaybackStage.completed:
      case TrackPlaybackStage.resolutionError:
      case TrackPlaybackStage.engineError:
        await playTrack(current);
        return;
      case TrackPlaybackStage.resolving:
      case TrackPlaybackStage.loading:
        return;
    }
  }

  Future<void> playTrack(PlaylistTrackSummary track) async {
    final generation = ++_generation;
    _resolutionOperation?.cancel();
    _resolutionOperation = null;
    _pausedSelection = false;
    _track = track;
    _resolutionFailure = null;
    _engineFailure = null;
    _resolvedQuality = null;
    _resolving = true;
    final safeProvider = _safeProviderName(track.providerId);
    _logPlaybackResolution(
      phase: 'resolve',
      outcome: 'started',
      provider: safeProvider,
    );
    if (!_setStage(TrackPlaybackStage.resolving)) {
      _notifyState();
    }
    await _playback.stop();
    if (!_isCurrent(generation)) return;
    _syncPositionMs();

    final operation = _resolutionGateway.beginResolution(
      providerId: track.providerId,
      opaqueTrackId: track.opaqueId,
    );
    _resolutionOperation = operation;
    final result = await operation.run();
    if (identical(_resolutionOperation, operation)) {
      _resolutionOperation = null;
    }
    if (!_isCurrent(generation)) return;

    final source = result.source;
    final failure = result.failure;
    if (failure != null || source == null) {
      _resolving = false;
      _resolutionFailure = failure ?? MediaResolutionFailure.invalidResponse;
      _logPlaybackResolution(
        phase: 'resolve',
        outcome: 'failure',
        provider: safeProvider,
        detail: 'failure=${_resolutionFailure!.name}',
      );
      if (!_setStage(TrackPlaybackStage.resolutionError)) {
        _notifyState();
      }
      return;
    }

    _resolving = false;
    _resolvedQuality = source.quality;
    _logPlaybackResolution(
      phase: 'resolve',
      outcome: 'success',
      provider: safeProvider,
      detail:
          'format=${source.format.name} '
          'quality=${source.quality.name} ttl=${source.validForSeconds}',
    );
    await _playback.playRemote(
      source.uri,
      format: switch (source.format) {
        PlaybackAudioFormat.mp3 => ForegroundAudioFormat.mp3,
        PlaybackAudioFormat.m4a => ForegroundAudioFormat.m4a,
        PlaybackAudioFormat.flac => ForegroundAudioFormat.flac,
      },
    );
  }

  Future<void> pause() => canPause ? _playback.pause() : Future.value();

  Future<void> replayCurrent() => _stage == TrackPlaybackStage.completed
      ? _playback.replayCurrent()
      : Future.value();

  Future<void> releaseCompletionFocus() => _playback.releaseCompletionFocus();

  Future<void> resume() {
    if (!canResume) return Future.value();
    return _playback.canResume ? _playback.resume() : playTrack(_track!);
  }

  Future<void> seekToMs(int positionMs) {
    final duration = durationMs;
    if (!canSeek || duration == null) return Future.value();
    final boundedPosition = positionMs < 0
        ? 0
        : positionMs > duration
        ? duration
        : positionMs;
    return _playback.seekToMs(boundedPosition);
  }

  Future<void> setVolume(double volume) => _playback.setVolume(volume);

  /// Changes the selected Track without starting its source.
  Future<void> selectWithoutStarting(
    PlaylistTrackSummary track, {
    required bool paused,
  }) async {
    if (_disposed) return;
    _track = track;
    await _stop(paused: paused);
  }

  Future<void> stop() => _stop(paused: false);

  Future<void> _stop({required bool paused}) async {
    ++_generation;
    _resolutionOperation?.cancel();
    _resolutionOperation = null;
    _resolving = false;
    _resolutionFailure = null;
    _engineFailure = null;
    _resolvedQuality = null;
    // stop detaches the old session synchronously. Do not project that
    // session's final state over an inactive selection.
    _resolving = true;
    final stopping = _playback.stop();
    _resolving = false;
    _syncPositionMs();
    _pausedSelection = paused;
    final nextStage = paused
        ? TrackPlaybackStage.paused
        : TrackPlaybackStage.stopped;
    if (!_setStage(nextStage)) _notifyState();
    await stopping;
  }

  void _onPlaybackChanged() {
    if (_disposed || _resolving) return;
    final nextPositionMs = _playback.positionMs;
    final positionChanged = _lastPlaybackPositionMs != nextPositionMs;
    _lastPlaybackPositionMs = nextPositionMs;
    final volumeChanged = _lastPlaybackVolume != _playback.volume;
    _lastPlaybackVolume = _playback.volume;
    final playbackFailure = _playback.failure;

    final bool stateChanged;
    if (_playback.stage == ForegroundPlaybackStage.error) {
      final nextFailure =
          playbackFailure ?? ForegroundAudioFailure.coreUnavailable;
      final failureChanged = _engineFailure != nextFailure;
      _engineFailure = nextFailure;
      _logPlaybackResolution(
        phase: 'engine',
        outcome: 'failure',
        provider: _safeProviderName(_track?.providerId),
        detail: 'failure=${_engineFailure!.name}',
      );
      final stageChanged = _stage != TrackPlaybackStage.engineError;
      _stage = TrackPlaybackStage.engineError;
      stateChanged = stageChanged || volumeChanged || failureChanged;
    } else {
      final failureCleared = _engineFailure != null;
      _engineFailure = null;
      final nextStage = switch (_playback.stage) {
        ForegroundPlaybackStage.idle => TrackPlaybackStage.idle,
        ForegroundPlaybackStage.loading => TrackPlaybackStage.loading,
        ForegroundPlaybackStage.playing => TrackPlaybackStage.playing,
        ForegroundPlaybackStage.paused => TrackPlaybackStage.paused,
        ForegroundPlaybackStage.stopped when _pausedSelection =>
          TrackPlaybackStage.paused,
        ForegroundPlaybackStage.stopped => TrackPlaybackStage.stopped,
        ForegroundPlaybackStage.completed => TrackPlaybackStage.completed,
        ForegroundPlaybackStage.error => TrackPlaybackStage.engineError,
      };
      final stageChanged = _stage != nextStage;
      _stage = nextStage;
      stateChanged = stageChanged || volumeChanged || failureCleared;
    }

    if (positionChanged && !_disposed) {
      _positionMs.value = nextPositionMs;
    }
    if (stateChanged) {
      _notifyState();
    } else if (positionChanged && !_disposed) {
      notifyListeners();
    }
  }

  bool _syncPositionMs() {
    final nextPositionMs = _playback.positionMs;
    if (_lastPlaybackPositionMs == nextPositionMs) return false;
    _lastPlaybackPositionMs = nextPositionMs;
    if (!_disposed) _positionMs.value = nextPositionMs;
    return true;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _setStage(TrackPlaybackStage stage) {
    if (_disposed || _stage == stage) return false;
    _stage = stage;
    _notifyState();
    return true;
  }

  void _notifyState() {
    if (_disposed) return;
    _stateChanges.notify();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      ++_generation;
      _resolutionOperation?.cancel();
      _resolutionOperation = null;
      _playback.removeListener(_onPlaybackChanged);
      _playback.dispose();
      _stateChanges.dispose();
      _positionMs.dispose();
    }
    super.dispose();
  }
}

class _TrackPlaybackSignalNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

void _logPlaybackResolution({
  required String phase,
  required String outcome,
  required String provider,
  String? detail,
}) {
  debugPrint(
    'FURA_DIAGNOSTIC media_playback phase=$phase outcome=$outcome '
    'provider=$provider${detail == null ? '' : ' $detail'}',
  );
}

String _safeProviderName(String? providerId) => switch (providerId) {
  'qq-music' => 'qq_music',
  'netease-cloud-music' => 'netease',
  _ => 'other',
};
