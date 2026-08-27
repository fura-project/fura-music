import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

class QueuePlaybackController extends ChangeNotifier {
  QueuePlaybackController(this._gateway, this._playback, {this.lyrics}) {
    _playback.addListener(_onPlaybackChanged);
    lyrics?.addListener(_onLyricsChanged);
    _accept(_gateway.snapshot());
    _syncLyricTrack();
  }

  final PlaybackQueueGateway _gateway;
  final TrackPlaybackController _playback;
  final LyricController? lyrics;

  PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot.empty();
  PlaybackQueueFailure? _failure;
  bool _completionHandled = false;
  bool _disposed = false;
  String? _lyricTrackKey;

  PlaybackQueueSnapshot get snapshot => _snapshot;
  PlaybackQueueFailure? get failure => _failure;
  TrackPlaybackController get playback => _playback;
  List<PlaylistTrackSummary> get tracks => _snapshot.tracks;
  PlaylistTrackSummary? get current => _snapshot.current;
  int? get currentIndex => _snapshot.currentIndex;
  bool get hasPrevious => _snapshot.hasPrevious;
  bool get hasNext => _snapshot.hasNext;
  PlaybackOrder get order => _snapshot.order;
  PlaybackRepeatMode get repeatMode => _snapshot.repeatMode;

  Future<void> replaceAndPlay(
    List<PlaylistTrackSummary> tracks,
    int currentIndex,
  ) => _apply(
    _gateway.replace(tracks: tracks, currentIndex: currentIndex),
    playChangedCurrent: true,
  );

  Future<void> push(PlaylistTrackSummary track) =>
      _apply(_gateway.push(track), playChangedCurrent: true);

  Future<void> select(int index) =>
      _apply(_gateway.select(index), playChangedCurrent: true);

  Future<void> advance() =>
      _apply(_gateway.advance(), playChangedCurrent: true);

  Future<void> rewind() => _apply(_gateway.rewind(), playChangedCurrent: true);

  Future<void> setOrder(PlaybackOrder order) =>
      _apply(_gateway.setOrder(order), playChangedCurrent: false);

  Future<void> toggleShuffle() => setOrder(
    order == PlaybackOrder.shuffle
        ? PlaybackOrder.sequential
        : PlaybackOrder.shuffle,
  );

  Future<void> setRepeatMode(PlaybackRepeatMode repeatMode) =>
      _apply(_gateway.setRepeatMode(repeatMode), playChangedCurrent: false);

  Future<void> cycleRepeatMode() => setRepeatMode(switch (repeatMode) {
    PlaybackRepeatMode.off => PlaybackRepeatMode.all,
    PlaybackRepeatMode.all => PlaybackRepeatMode.one,
    PlaybackRepeatMode.one => PlaybackRepeatMode.off,
  });

  Future<void> remove(int index) =>
      _apply(_gateway.remove(index), playChangedCurrent: true);

  Future<void> clear() => _apply(_gateway.clear(), playChangedCurrent: true);

  Future<void> _completeCurrent() =>
      _apply(_gateway.completeCurrent(), playChangedCurrent: true);

  Future<void> _apply(
    PlaybackQueueResult result, {
    required bool playChangedCurrent,
  }) async {
    if (_disposed || !_accept(result)) return;
    if (!playChangedCurrent || !result.playbackRequested) return;

    _completionHandled = false;
    final current = _snapshot.current;
    if (current == null) {
      await _playback.stop();
    } else {
      await _playback.playTrack(current);
    }
  }

  bool _accept(PlaybackQueueResult result) {
    final failure = result.failure;
    final snapshot = result.snapshot;
    if (failure != null || snapshot == null) {
      _failure = failure ?? PlaybackQueueFailure.invalidResponse;
      if (!_disposed) notifyListeners();
      return false;
    }
    _failure = null;
    _snapshot = snapshot;
    _syncLyricTrack();
    if (!_disposed) notifyListeners();
    return true;
  }

  void _onPlaybackChanged() {
    if (_disposed) return;
    lyrics?.updatePositionMs(_playback.positionMs);
    notifyListeners();
    if (_playback.stage == TrackPlaybackStage.completed) {
      if (!_completionHandled) {
        _completionHandled = true;
        unawaited(_completeCurrent());
      }
    } else {
      _completionHandled = false;
    }
  }

  void _onLyricsChanged() {
    if (!_disposed) notifyListeners();
  }

  void _syncLyricTrack() {
    final lyricController = lyrics;
    if (lyricController == null || _disposed) return;
    final current = _snapshot.current;
    final key = current == null
        ? null
        : '${current.providerId}\u0000${current.opaqueId}';
    if (key == _lyricTrackKey) return;
    _lyricTrackKey = key;
    if (current == null) {
      lyricController.clear();
    } else {
      unawaited(lyricController.load(current));
    }
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      _playback.removeListener(_onPlaybackChanged);
      lyrics?.removeListener(_onLyricsChanged);
      lyrics?.dispose();
      _playback.dispose();
    }
    super.dispose();
  }
}
