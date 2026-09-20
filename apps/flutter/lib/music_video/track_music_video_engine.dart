import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

enum TrackMusicVideoSessionStage { loading, playing, paused, completed, error }

abstract class TrackMusicVideoSession extends ChangeNotifier {
  TrackMusicVideoSessionStage get stage;
  Duration get position;
  Duration get duration;
  String? get errorMessage => null;
  List<String> get diagnosticLog => const [];

  Future<void> open(String uri);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Widget buildVideo({Key? key});
}

abstract interface class TrackMusicVideoEngine {
  TrackMusicVideoSession createSession();
}

class MediaKitTrackMusicVideoEngine implements TrackMusicVideoEngine {
  const MediaKitTrackMusicVideoEngine({this.enableDiagnostics = false});

  final bool enableDiagnostics;

  @override
  TrackMusicVideoSession createSession() =>
      _MediaKitTrackMusicVideoSession(enableDiagnostics: enableDiagnostics);
}

class _MediaKitTrackMusicVideoSession extends TrackMusicVideoSession {
  _MediaKitTrackMusicVideoSession({required bool enableDiagnostics})
    : _player = Player(
        configuration: PlayerConfiguration(
          logLevel: enableDiagnostics ? MPVLogLevel.info : MPVLogLevel.error,
        ),
      ),
      _enableDiagnostics = enableDiagnostics,
      _stage = TrackMusicVideoSessionStage.loading {
    _videoController = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        // mpv 0.37's broad `auto` probe emits a fatal-looking decoder error
        // for unavailable v4l2m2m before successfully falling back to software.
        // `auto-safe` keeps hardware acceleration where mpv considers it safe
        // and preserves the normal software fallback on headless Linux hosts.
        hwdec: defaultTargetPlatform == TargetPlatform.linux
            ? 'auto-safe'
            : null,
      ),
    );
    _subscriptions.addAll([
      _player.stream.playing.listen((playing) {
        if (_disposed) return;
        if (playing) {
          _setStage(TrackMusicVideoSessionStage.playing);
        } else if (_stage == TrackMusicVideoSessionStage.playing) {
          _setStage(TrackMusicVideoSessionStage.paused);
        }
      }),
      _player.stream.completed.listen((completed) {
        if (completed && !_disposed) {
          _setStage(TrackMusicVideoSessionStage.completed);
        }
      }),
      _player.stream.error.listen((message) {
        if (_disposed) return;
        _recordFailure(message);
      }),
      _player.stream.log.listen((event) {
        if (_disposed || !_enableDiagnostics) return;
        _appendDiagnostic(
          'mpv ${event.level} ${event.prefix}: ${event.text.trim()}',
        );
      }),
      _player.stream.position.listen((position) {
        if (_disposed || _position == position) return;
        _position = position;
        notifyListeners();
      }),
      _player.stream.duration.listen((duration) {
        if (_disposed || _duration == duration) return;
        _duration = duration;
        notifyListeners();
      }),
    ]);
  }

  final Player _player;
  final bool _enableDiagnostics;
  late final VideoController _videoController;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<String> _diagnosticLog = [];
  TrackMusicVideoSessionStage _stage;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _errorMessage;
  bool _disposed = false;

  @override
  TrackMusicVideoSessionStage get stage => _stage;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  String? get errorMessage => _errorMessage;

  @override
  List<String> get diagnosticLog => List.unmodifiable(_diagnosticLog);

  @override
  Future<void> open(String uri) async {
    _setStage(TrackMusicVideoSessionStage.loading);
    try {
      await _player.open(Media(uri));
    } on Object catch (error) {
      if (!_disposed) _recordFailure('open failed: $error');
    }
  }

  @override
  Future<void> play() async {
    try {
      await _player.play();
    } on Object catch (error) {
      if (!_disposed) _recordFailure('play failed: $error');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } on Object catch (error) {
      if (!_disposed) _recordFailure('pause failed: $error');
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } on Object catch (error) {
      if (!_disposed) _recordFailure('seek failed: $error');
    }
  }

  @override
  Widget buildVideo({Key? key}) => Video(
    key: key,
    controller: _videoController,
    controls: NoVideoControls,
    fit: BoxFit.contain,
    fill: Colors.black,
  );

  void _setStage(TrackMusicVideoSessionStage stage) {
    if (_disposed || _stage == stage) return;
    _stage = stage;
    if (_enableDiagnostics) {
      _appendDiagnostic(
        'stage=${stage.name} position=${_position.inMilliseconds}ms '
        'duration=${_duration.inMilliseconds}ms',
      );
    }
    notifyListeners();
  }

  void _recordFailure(String message) {
    _errorMessage = message;
    _appendDiagnostic('error=$message');
    _setStage(TrackMusicVideoSessionStage.error);
  }

  void _appendDiagnostic(String message) {
    _diagnosticLog.add(message);
    if (_diagnosticLog.length > 200) {
      _diagnosticLog.removeAt(0);
    }
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      _subscriptions.clear();
      unawaited(_player.dispose());
    }
    super.dispose();
  }
}
