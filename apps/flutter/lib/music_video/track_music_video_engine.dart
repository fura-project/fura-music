import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

enum TrackMusicVideoSessionStage { loading, playing, paused, completed, error }

abstract class TrackMusicVideoSession extends ChangeNotifier {
  TrackMusicVideoSessionStage get stage;
  Duration get position;
  Duration get duration;

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
  const MediaKitTrackMusicVideoEngine();

  @override
  TrackMusicVideoSession createSession() => _MediaKitTrackMusicVideoSession();
}

class _MediaKitTrackMusicVideoSession extends TrackMusicVideoSession {
  _MediaKitTrackMusicVideoSession()
    : _player = Player(),
      _stage = TrackMusicVideoSessionStage.loading {
    _videoController = VideoController(_player);
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
      _player.stream.error.listen((_) {
        if (!_disposed) _setStage(TrackMusicVideoSessionStage.error);
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
  late final VideoController _videoController;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  TrackMusicVideoSessionStage _stage;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _disposed = false;

  @override
  TrackMusicVideoSessionStage get stage => _stage;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  Future<void> open(String uri) async {
    _setStage(TrackMusicVideoSessionStage.loading);
    try {
      await _player.open(Media(uri));
    } on Object {
      if (!_disposed) _setStage(TrackMusicVideoSessionStage.error);
    }
  }

  @override
  Future<void> play() async {
    try {
      await _player.play();
    } on Object {
      if (!_disposed) _setStage(TrackMusicVideoSessionStage.error);
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } on Object {
      if (!_disposed) _setStage(TrackMusicVideoSessionStage.error);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } on Object {
      if (!_disposed) _setStage(TrackMusicVideoSessionStage.error);
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
    notifyListeners();
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
