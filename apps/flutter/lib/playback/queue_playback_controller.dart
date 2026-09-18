import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

enum RoamStage { idle, loading, continued, unsupported, empty, failed }

class QueuePlaybackController extends ChangeNotifier {
  QueuePlaybackController(
    this._gateway,
    this._playback, {
    this.lyrics,
    RelatedTracksGateway? relatedTracksGateway,
  }) : // The public named parameter cannot use a library-private name.
       // ignore: prefer_initializing_formals
       _relatedTracksGateway = relatedTracksGateway {
    _playback.addListener(_onPlaybackChanged);
    lyrics?.addListener(_onLyricsChanged);
    _accept(_gateway.snapshot());
    _syncLyricTrack();
  }

  final PlaybackQueueGateway _gateway;
  final TrackPlaybackController _playback;
  final LyricController? lyrics;
  final RelatedTracksGateway? _relatedTracksGateway;

  PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot.empty();
  final ValueNotifier<PlaylistTrackSummary?> _currentTrack = ValueNotifier(
    null,
  );
  PlaybackQueueFailure? _failure;
  bool _completionHandled = false;
  bool _disposed = false;
  String? _lyricTrackKey;
  bool _roamEnabled = false;
  RoamStage _roamStage = RoamStage.idle;
  RelatedTracksLoadOperation? _roamOperation;
  int _roamGeneration = 0;
  int _terminalIntentEpoch = 0;

  PlaybackQueueSnapshot get snapshot => _snapshot;

  /// Notifies only when the provider-scoped current Track identity changes.
  /// Playback position, state, volume, and lyric updates stay on this
  /// controller's broader [Listenable].
  ValueListenable<PlaylistTrackSummary?> get currentTrackListenable =>
      _currentTrack;
  PlaybackQueueFailure? get failure => _failure;
  TrackPlaybackController get playback => _playback;
  List<PlaylistTrackSummary> get tracks => _snapshot.tracks;
  PlaylistTrackSummary? get current => _snapshot.current;
  int? get currentIndex => _snapshot.currentIndex;
  bool get hasPrevious => _snapshot.hasPrevious;
  bool get hasNext => _snapshot.hasNext;
  PlaybackOrder get order => _snapshot.order;
  PlaybackRepeatMode get repeatMode => _snapshot.repeatMode;
  bool get roamEnabled => _roamEnabled;
  bool get roamEffective =>
      _roamEnabled &&
      _relatedTracksGateway != null &&
      _snapshot.order == PlaybackOrder.sequential &&
      _snapshot.repeatMode == PlaybackRepeatMode.off &&
      switch (_snapshot.current) {
        final current? => supportsRelatedTracksProvider(current.providerId),
        null => false,
      };
  RoamStage get roamStage => _roamStage;

  void setRoamEnabled(bool enabled) {
    if (_disposed || enabled == _roamEnabled) return;
    _roamEnabled = enabled;
    _invalidateRoam();
    if (!_disposed) notifyListeners();
  }

  Future<void> replaceAndPlay(
    List<PlaylistTrackSummary> tracks,
    int currentIndex,
  ) {
    _invalidateRoam();
    return _apply(
      _gateway.replace(tracks: tracks, currentIndex: currentIndex),
      playChangedCurrent: true,
    );
  }

  Future<void> push(PlaylistTrackSummary track) {
    _invalidateRoam();
    return _apply(_gateway.push(track), playChangedCurrent: true);
  }

  Future<void> select(int index) {
    _invalidateRoam();
    return _apply(_gateway.select(index), playChangedCurrent: true);
  }

  Future<void> advance() {
    _invalidateRoam();
    return _apply(_gateway.advance(), playChangedCurrent: true);
  }

  Future<void> rewind() {
    _invalidateRoam();
    return _apply(_gateway.rewind(), playChangedCurrent: true);
  }

  Future<void> setOrder(PlaybackOrder order) {
    _invalidateRoam();
    return _apply(_gateway.setOrder(order), playChangedCurrent: false);
  }

  Future<void> toggleShuffle() => setOrder(
    order == PlaybackOrder.shuffle
        ? PlaybackOrder.sequential
        : PlaybackOrder.shuffle,
  );

  Future<void> setRepeatMode(PlaybackRepeatMode repeatMode) {
    _invalidateRoam();
    return _apply(
      _gateway.setRepeatMode(repeatMode),
      playChangedCurrent: false,
    );
  }

  Future<void> cycleRepeatMode() => setRepeatMode(switch (repeatMode) {
    PlaybackRepeatMode.off => PlaybackRepeatMode.all,
    PlaybackRepeatMode.all => PlaybackRepeatMode.one,
    PlaybackRepeatMode.one => PlaybackRepeatMode.off,
  });

  Future<void> remove(int index) {
    _invalidateRoam();
    return _apply(_gateway.remove(index), playChangedCurrent: true);
  }

  Future<void> clear() {
    _invalidateRoam();
    return _apply(_gateway.clear(), playChangedCurrent: true);
  }

  /// Applies the current Track's play/pause/retry action through the Queue
  /// owner so an explicit user or system Play intent wins over pending Roam.
  Future<void> activateCurrent() {
    if (_disposed) return Future.value();
    _invalidateRoam();
    return _playback.activate();
  }

  /// Applies an idempotent system Play intent through the Queue owner. Unlike
  /// [activateCurrent], an already playing Track is not toggled to pause.
  Future<void> playCurrent() {
    if (_disposed) return Future.value();
    _invalidateRoam();
    if (_playback.canResume) return _playback.resume();
    if (_playback.stage == TrackPlaybackStage.playing) return Future.value();
    return _playback.activate();
  }

  /// Stops foreground playback through the Queue owner. The Queue contents
  /// remain intact, but a pending terminal continuation is synchronously stale
  /// before the audio engine begins its asynchronous stop tail.
  Future<void> stop() {
    if (_disposed) return Future.value();
    _invalidateRoam();
    return _playback.stop();
  }

  /// Re-resolves the current Track after an explicit playback-quality change.
  /// Active playback keeps its approximate position and paused/playing state;
  /// an idle, stopped, completed, or failed Track uses the new preference only
  /// on its next normal activation.
  Future<void> reloadCurrentSource() async {
    if (_disposed ||
        (_playback.stage != TrackPlaybackStage.playing &&
            _playback.stage != TrackPlaybackStage.paused)) {
      return;
    }
    final current = _snapshot.current;
    if (current == null) return;
    final providerId = current.providerId;
    final opaqueId = current.opaqueId;
    final positionMs = _playback.positionMs;
    final remainPaused = _playback.stage == TrackPlaybackStage.paused;

    _completionHandled = false;
    await _playback.playTrack(current);
    if (_disposed ||
        _snapshot.current?.providerId != providerId ||
        _snapshot.current?.opaqueId != opaqueId) {
      return;
    }
    if (_playback.canSeek && positionMs > 0) {
      await _playback.seekToMs(positionMs);
    }
    if (remainPaused && _playback.canPause) await _playback.pause();
  }

  Future<void> _completeCurrent(int terminalToken) async {
    final result = _gateway.completeCurrent();
    if (_disposed || !_accept(result)) return;
    if (result.playbackRequested) {
      _completionHandled = false;
      final current = _snapshot.current;
      if (current == null) {
        await _playback.stop();
      } else {
        await _playback.playTrack(current);
      }
      return;
    }
    await _continueRoamFromTerminal(terminalToken);
  }

  Future<void> _continueRoamFromTerminal(int terminalToken) async {
    final gateway = _relatedTracksGateway;
    final seed = _snapshot.current;
    if (!_roamEnabled ||
        gateway == null ||
        seed == null ||
        _snapshot.hasNext ||
        _snapshot.order != PlaybackOrder.sequential ||
        _snapshot.repeatMode != PlaybackRepeatMode.off) {
      return;
    }
    if (!supportsRelatedTracksProvider(seed.providerId)) {
      _roamStage = RoamStage.unsupported;
      notifyListeners();
      return;
    }

    final generation = ++_roamGeneration;
    final seedKey = _trackKey(seed);
    final expectedLength = _snapshot.tracks.length;
    late final RelatedTracksLoadOperation operation;
    try {
      operation = gateway.beginLoad(seed);
    } on Object {
      if (_roamIsCurrent(generation, terminalToken, seedKey, expectedLength)) {
        _roamStage = RoamStage.failed;
        notifyListeners();
      }
      return;
    }
    _roamOperation = operation;
    _roamStage = RoamStage.loading;
    notifyListeners();

    late final RelatedTracksResult result;
    try {
      result = await operation.run();
    } on Object {
      if (identical(_roamOperation, operation)) _roamOperation = null;
      if (_roamIsCurrent(generation, terminalToken, seedKey, expectedLength)) {
        _roamStage = RoamStage.failed;
        notifyListeners();
      }
      return;
    }
    if (identical(_roamOperation, operation)) _roamOperation = null;
    if (!_roamIsCurrent(generation, terminalToken, seedKey, expectedLength)) {
      return;
    }
    if (result.failure != null) {
      _roamStage = RoamStage.failed;
      notifyListeners();
      return;
    }
    if (result.tracks.any((track) => track.providerId != seed.providerId)) {
      _roamStage = RoamStage.failed;
      notifyListeners();
      return;
    }

    final identities = _snapshot.tracks.map(_trackKey).toSet();
    final additions = <PlaylistTrackSummary>[];
    for (final candidate in result.tracks) {
      if (identities.add(_trackKey(candidate))) additions.add(candidate);
    }
    if (additions.isEmpty) {
      _roamStage = RoamStage.empty;
      notifyListeners();
      return;
    }

    late final PlaybackQueueResult update;
    try {
      update = _gateway.extendAndAdvanceFromTerminal(additions);
    } on Object {
      if (_roamIsCurrent(generation, terminalToken, seedKey, expectedLength)) {
        _roamStage = RoamStage.failed;
        notifyListeners();
      }
      return;
    }
    if (!_roamIsCurrent(generation, terminalToken, seedKey, expectedLength) ||
        !_accept(update) ||
        !update.playbackRequested) {
      if (!_disposed && generation == _roamGeneration) {
        _roamStage = RoamStage.failed;
        notifyListeners();
      }
      return;
    }
    _roamStage = RoamStage.continued;
    _completionHandled = false;
    notifyListeners();
    final current = _snapshot.current;
    if (current != null) await _playback.playTrack(current);
  }

  bool _roamIsCurrent(
    int generation,
    int terminalToken,
    String seedKey,
    int expectedLength,
  ) =>
      !_disposed &&
      generation == _roamGeneration &&
      terminalToken == _terminalIntentEpoch &&
      _roamEnabled &&
      _playback.stage == TrackPlaybackStage.completed &&
      _snapshot.order == PlaybackOrder.sequential &&
      _snapshot.repeatMode == PlaybackRepeatMode.off &&
      !_snapshot.hasNext &&
      _snapshot.tracks.length == expectedLength &&
      switch (_snapshot.current) {
        final current? => _trackKey(current) == seedKey,
        null => false,
      };

  void _invalidateRoam() {
    ++_roamGeneration;
    ++_terminalIntentEpoch;
    _roamOperation?.cancel();
    _roamOperation = null;
    _roamStage = RoamStage.idle;
  }

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
    final previousCurrent = _snapshot.current;
    _snapshot = snapshot;
    if (!_sameTrack(previousCurrent, _snapshot.current)) {
      _currentTrack.value = _snapshot.current;
    }
    _syncLyricTrack();
    if (!_disposed) notifyListeners();
    return true;
  }

  void _onPlaybackChanged() {
    if (_disposed) return;
    if (_playback.stage != TrackPlaybackStage.completed &&
        _roamOperation != null) {
      _invalidateRoam();
    }
    lyrics?.updatePositionMs(_playback.positionMs);
    notifyListeners();
    if (_playback.stage == TrackPlaybackStage.completed) {
      if (!_completionHandled) {
        _completionHandled = true;
        final terminalToken = ++_terminalIntentEpoch;
        unawaited(_completeCurrent(terminalToken));
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
      _invalidateRoam();
      _playback.removeListener(_onPlaybackChanged);
      lyrics?.removeListener(_onLyricsChanged);
      lyrics?.dispose();
      _playback.dispose();
      _currentTrack.dispose();
    }
    super.dispose();
  }
}

bool _sameTrack(PlaylistTrackSummary? first, PlaylistTrackSummary? second) =>
    first?.providerId == second?.providerId &&
    first?.opaqueId == second?.opaqueId;

String _trackKey(PlaylistTrackSummary track) =>
    '${track.providerId}\u0000${track.opaqueId}';
