import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/music_video/track_music_video_engine.dart';
import 'package:flutterustmusic/music_video/track_music_video_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

enum TrackMusicVideoStage {
  loading,
  playing,
  paused,
  completed,
  unavailable,
  error,
  interrupted,
}

class TrackMusicVideoController extends ChangeNotifier {
  factory TrackMusicVideoController({
    required TrackMusicVideoGateway gateway,
    required TrackMusicVideoEngine engine,
    required QueuePlaybackController musicController,
    required PlaylistTrackSummary track,
  }) => TrackMusicVideoController._(gateway, engine, musicController, track);

  TrackMusicVideoController._(
    this._gateway,
    this._engine,
    this._musicController,
    this.track,
  ) {
    _musicController.addListener(_handleMusicChanged);
  }

  final TrackMusicVideoGateway _gateway;
  final TrackMusicVideoEngine _engine;
  final QueuePlaybackController _musicController;
  final PlaylistTrackSummary track;

  TrackMusicVideoStage _stage = TrackMusicVideoStage.loading;
  TrackMusicVideoSummary? _musicVideo;
  TrackMusicVideoFailure? _failure;
  TrackMusicVideoLoadOperation? _operation;
  TrackMusicVideoSession? _session;
  int _generation = 0;
  bool _disposed = false;

  TrackMusicVideoStage get stage => _stage;
  TrackMusicVideoSummary? get musicVideo => _musicVideo;
  TrackMusicVideoFailure? get failure => _failure;
  TrackMusicVideoSession? get session => _session;
  Duration get position => _session?.position ?? Duration.zero;
  Duration get duration {
    final sessionDuration = _session?.duration ?? Duration.zero;
    if (sessionDuration > Duration.zero) return sessionDuration;
    final seconds = _musicVideo?.durationSeconds;
    return seconds == null ? Duration.zero : Duration(seconds: seconds);
  }

  bool get canRetry =>
      _stage == TrackMusicVideoStage.error &&
      _failure != TrackMusicVideoFailure.sourceUnavailable;
  bool get canTogglePlayback =>
      _stage == TrackMusicVideoStage.playing ||
      _stage == TrackMusicVideoStage.paused ||
      _stage == TrackMusicVideoStage.completed;
  bool get canSeek =>
      _session != null &&
      duration > Duration.zero &&
      _stage != TrackMusicVideoStage.loading &&
      _stage != TrackMusicVideoStage.error &&
      _stage != TrackMusicVideoStage.interrupted;

  Future<void> load() async {
    final generation = ++_generation;
    _operation?.cancel();
    _operation = null;
    _disposeSession();
    _musicVideo = null;
    _failure = null;
    _stage = TrackMusicVideoStage.loading;
    _notify();

    final operation = _gateway.beginLoad(track: track);
    _operation = operation;
    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;
    final failure = result.failure;
    final video = result.musicVideo;
    if (failure != null) {
      _failure = failure;
      _stage = TrackMusicVideoStage.error;
      _notify();
      return;
    }
    if (video == null) {
      _stage = TrackMusicVideoStage.unavailable;
      _notify();
      return;
    }
    _musicVideo = video;

    await _yieldMusicOwnership();
    if (!_isCurrent(generation)) return;
    final session = _engine.createSession();
    _session = session;
    session.addListener(_handleSessionChanged);
    _notify();
    await session.open(video.sourceUri);
    if (!_isCurrent(generation) || !identical(_session, session)) return;
    _handleSessionChanged();
  }

  void retry() {
    if (canRetry) unawaited(load());
  }

  Future<void> togglePlayback() async {
    final session = _session;
    if (session == null || !canTogglePlayback) return;
    if (_stage == TrackMusicVideoStage.playing) {
      await session.pause();
      return;
    }
    await _yieldMusicOwnership();
    if (_disposed || !identical(_session, session)) return;
    if (_stage == TrackMusicVideoStage.completed) {
      await session.seek(Duration.zero);
    }
    await session.play();
  }

  Future<void> seek(Duration position) async {
    final session = _session;
    final maximum = duration;
    if (session == null || !canSeek || maximum <= Duration.zero) return;
    final bounded = position < Duration.zero
        ? Duration.zero
        : position > maximum
        ? maximum
        : position;
    await session.seek(bounded);
  }

  Future<void> _yieldMusicOwnership() async {
    final playback = _musicController.playback;
    if (playback.canPause) {
      await playback.pause();
    } else if (playback.stage == TrackPlaybackStage.resolving ||
        playback.stage == TrackPlaybackStage.loading) {
      await playback.stop();
    }
  }

  void _handleMusicChanged() {
    if (_disposed) return;
    final current = _musicController.current;
    if (current == null || _trackKey(current) != _trackKey(track)) {
      _interrupt();
      return;
    }
    final musicStage = _musicController.playback.stage;
    if (_session != null &&
        (musicStage == TrackPlaybackStage.resolving ||
            musicStage == TrackPlaybackStage.loading ||
            musicStage == TrackPlaybackStage.playing)) {
      _interrupt();
    }
  }

  void _handleSessionChanged() {
    if (_disposed) return;
    final session = _session;
    if (session == null) return;
    _stage = switch (session.stage) {
      TrackMusicVideoSessionStage.loading => TrackMusicVideoStage.loading,
      TrackMusicVideoSessionStage.playing => TrackMusicVideoStage.playing,
      TrackMusicVideoSessionStage.paused => TrackMusicVideoStage.paused,
      TrackMusicVideoSessionStage.completed => TrackMusicVideoStage.completed,
      TrackMusicVideoSessionStage.error => TrackMusicVideoStage.error,
    };
    if (_stage == TrackMusicVideoStage.error) {
      _failure = TrackMusicVideoFailure.coreUnavailable;
    }
    _notify();
  }

  void _interrupt() {
    if (_disposed ||
        (_operation == null &&
            _session == null &&
            _stage == TrackMusicVideoStage.interrupted)) {
      return;
    }
    ++_generation;
    _operation?.cancel();
    _operation = null;
    _disposeSession();
    _stage = TrackMusicVideoStage.interrupted;
    _notify();
  }

  void _disposeSession() {
    final session = _session;
    _session = null;
    if (session != null) {
      session.removeListener(_handleSessionChanged);
      session.dispose();
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _trackKey(PlaylistTrackSummary value) =>
      '${value.providerId}\u0000${value.opaqueId}';

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      ++_generation;
      _operation?.cancel();
      _operation = null;
      _musicController.removeListener(_handleMusicChanged);
      _disposeSession();
    }
    super.dispose();
  }
}
