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
  TrackPlaybackController(this._resolutionGateway, this._playback) {
    _playback.addListener(_onPlaybackChanged);
  }

  final MediaResolutionGateway _resolutionGateway;
  final ForegroundPlaybackController _playback;

  TrackPlaybackStage _stage = TrackPlaybackStage.idle;
  PlaylistTrackSummary? _track;
  MediaResolutionFailure? _resolutionFailure;
  ForegroundAudioFailure? _engineFailure;
  MediaResolutionOperation? _resolutionOperation;
  int _generation = 0;
  bool _resolving = false;
  bool _disposed = false;
  int _lastPlaybackPositionMs = 0;

  TrackPlaybackStage get stage => _stage;
  PlaylistTrackSummary? get track => _track;
  MediaResolutionFailure? get resolutionFailure => _resolutionFailure;
  ForegroundAudioFailure? get engineFailure => _engineFailure;
  int get positionMs => _playback.positionMs;
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
          _stage == TrackPlaybackStage.paused);
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

  Future<void> activate() async {
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
    _track = track;
    _resolutionFailure = null;
    _engineFailure = null;
    _resolving = true;
    _setStage(TrackPlaybackStage.resolving);
    await _playback.stop();
    if (!_isCurrent(generation)) return;

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
      _setStage(TrackPlaybackStage.resolutionError);
      return;
    }

    _resolving = false;
    await _playback.playRemote(source.uri);
  }

  Future<void> pause() => canPause ? _playback.pause() : Future.value();

  Future<void> resume() => canResume ? _playback.resume() : Future.value();

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

  Future<void> stop() async {
    ++_generation;
    _resolutionOperation?.cancel();
    _resolutionOperation = null;
    _resolving = false;
    _resolutionFailure = null;
    _engineFailure = null;
    _setStage(TrackPlaybackStage.stopped);
    await _playback.stop();
  }

  void _onPlaybackChanged() {
    if (_disposed || _resolving) return;
    final positionChanged = _lastPlaybackPositionMs != _playback.positionMs;
    _lastPlaybackPositionMs = _playback.positionMs;
    final playbackFailure = _playback.failure;
    if (_playback.stage == ForegroundPlaybackStage.error) {
      _engineFailure =
          playbackFailure ?? ForegroundAudioFailure.coreUnavailable;
      if (!_setStage(TrackPlaybackStage.engineError) && positionChanged) {
        notifyListeners();
      }
      return;
    }
    _engineFailure = null;
    final stageChanged = _setStage(switch (_playback.stage) {
      ForegroundPlaybackStage.idle => TrackPlaybackStage.idle,
      ForegroundPlaybackStage.loading => TrackPlaybackStage.loading,
      ForegroundPlaybackStage.playing => TrackPlaybackStage.playing,
      ForegroundPlaybackStage.paused => TrackPlaybackStage.paused,
      ForegroundPlaybackStage.stopped => TrackPlaybackStage.stopped,
      ForegroundPlaybackStage.completed => TrackPlaybackStage.completed,
      ForegroundPlaybackStage.error => TrackPlaybackStage.engineError,
    });
    if (!stageChanged && positionChanged) notifyListeners();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _setStage(TrackPlaybackStage stage) {
    if (_disposed || _stage == stage) return false;
    _stage = stage;
    notifyListeners();
    return true;
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
    }
    super.dispose();
  }
}
