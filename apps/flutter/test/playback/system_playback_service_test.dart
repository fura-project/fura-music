import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

void main() {
  test(
    'publishes provider-neutral queue metadata and playback state',
    () async {
      final controller = _controller();
      final handler = ProjectSystemAudioHandler()..attach(controller);

      await controller.replaceAndPlay(const [first, second], 0);

      expect(handler.queue.value, hasLength(2));
      expect(handler.mediaItem.value?.title, 'First track');
      expect(handler.mediaItem.value?.artist, 'First artist');
      expect(handler.mediaItem.value?.album, 'First album');
      expect(
        handler.mediaItem.value?.artUri,
        Uri.parse('https://img.example.test/first.jpg'),
      );
      expect(handler.mediaItem.value?.duration, const Duration(minutes: 3));
      expect(handler.mediaItem.value?.id, isNot(contains('vkey')));
      expect(handler.playbackState.value.playing, isTrue);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(handler.playbackState.value.queueIndex, 0);
      expect(
        handler.playbackState.value.controls.map((control) => control.action),
        containsAll([MediaAction.pause, MediaAction.skipToNext]),
      );

      handler.detach(controller);
      expect(handler.queue.value, isEmpty);
      expect(handler.mediaItem.value, isNull);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(handler.playbackState.value.playing, isFalse);
      controller.dispose();
    },
  );

  test(
    'system commands delegate to the single queue and playback owner',
    () async {
      final audio = _FakeAudioEngine();
      final controller = _controller(audio: audio);
      final handler = ProjectSystemAudioHandler()..attach(controller);

      await controller.replaceAndPlay(const [first, second], 0);
      await handler.pause();
      expect(audio.sessions.first.pauseCalls, 1);
      expect(controller.playback.stage, TrackPlaybackStage.paused);

      await handler.play();
      expect(audio.sessions.first.playCalls, 2);
      expect(controller.playback.stage, TrackPlaybackStage.playing);

      await handler.seek(const Duration(seconds: 42));
      expect(audio.sessions.first.seekPositions, [42000]);

      await handler.skipToNext();
      expect(controller.current, same(second));
      expect(audio.sessions, hasLength(2));

      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      expect(controller.order, PlaybackOrder.shuffle);
      expect(controller.repeatMode, PlaybackRepeatMode.one);

      await handler.skipToPrevious();
      expect(controller.current, same(first));

      await handler.stop();
      expect(controller.playback.stage, TrackPlaybackStage.stopped);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );

      handler.detach(controller);
      controller.dispose();
    },
  );
}

const first = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'first',
  title: 'First track',
  artistNames: ['First artist'],
  albumTitle: 'First album',
  artworkUri: 'https://img.example.test/first.jpg',
  durationSeconds: 180,
);

const second = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'second',
  title: 'Second track',
  artistNames: ['Second artist'],
  artworkUri: 'not a URI',
  durationSeconds: 240,
);

QueuePlaybackController _controller({_FakeAudioEngine? audio}) =>
    QueuePlaybackController(
      _MemoryQueueGateway(),
      TrackPlaybackController(
        const _MediaGateway(),
        ForegroundPlaybackController(audio ?? _FakeAudioEngine()),
      ),
    );

class _MemoryQueueGateway implements PlaybackQueueGateway {
  PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot.empty();

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) => _update(tracks, currentIndex, playbackRequested: true);

  @override
  PlaybackQueueResult advance() {
    final current = _snapshot.currentIndex;
    if (current == null || _snapshot.tracks.isEmpty) return snapshot();
    final next = current + 1 < _snapshot.tracks.length ? current + 1 : 0;
    return _update(_snapshot.tracks, next, playbackRequested: next != current);
  }

  @override
  PlaybackQueueResult rewind() {
    final current = _snapshot.currentIndex;
    if (current == null || _snapshot.tracks.isEmpty) return snapshot();
    final previous = current > 0 ? current - 1 : _snapshot.tracks.length - 1;
    return _update(
      _snapshot.tracks,
      previous,
      playbackRequested: previous != current,
    );
  }

  @override
  PlaybackQueueResult select(int index) =>
      _update(_snapshot.tracks, index, playbackRequested: true);

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) {
    _snapshot = _copy(order: order);
    return snapshot();
  }

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) {
    _snapshot = _copy(repeatMode: repeatMode);
    return snapshot();
  }

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) => _update(
    [..._snapshot.tracks, track],
    _snapshot.currentIndex ?? 0,
    playbackRequested: _snapshot.currentIndex == null,
  );

  @override
  PlaybackQueueResult remove(int index) {
    final tracks = [..._snapshot.tracks]..removeAt(index);
    if (tracks.isEmpty) return _update(const [], null, playbackRequested: true);
    final current = _snapshot.currentIndex ?? 0;
    return _update(
      tracks,
      current > index ? current - 1 : current.clamp(0, tracks.length - 1),
      playbackRequested: current == index,
    );
  }

  @override
  PlaybackQueueResult clear() =>
      _update(const [], null, playbackRequested: true);

  @override
  PlaybackQueueResult completeCurrent() => advance();

  PlaybackQueueResult _update(
    List<PlaylistTrackSummary> tracks,
    int? currentIndex, {
    required bool playbackRequested,
  }) {
    _snapshot = PlaybackQueueSnapshot(
      tracks: List.unmodifiable(tracks),
      currentIndex: currentIndex,
      hasPrevious: currentIndex != null && tracks.length > 1,
      hasNext: currentIndex != null && tracks.length > 1,
      order: _snapshot.order,
      repeatMode: _snapshot.repeatMode,
    );
    return PlaybackQueueResult(
      snapshot: _snapshot,
      playbackRequested: playbackRequested,
    );
  }

  PlaybackQueueSnapshot _copy({
    PlaybackOrder? order,
    PlaybackRepeatMode? repeatMode,
  }) => PlaybackQueueSnapshot(
    tracks: _snapshot.tracks,
    currentIndex: _snapshot.currentIndex,
    hasPrevious: _snapshot.hasPrevious,
    hasNext: _snapshot.hasNext,
    order: order ?? _snapshot.order,
    repeatMode: repeatMode ?? _snapshot.repeatMode,
  );
}

class _MediaGateway implements MediaResolutionGateway {
  const _MediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => _ResolutionOperation(opaqueTrackId);
}

class _ResolutionOperation implements MediaResolutionOperation {
  const _ResolutionOperation(this.id);

  final String id;

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async => MediaResolutionResult(
    source: ResolvedPlaybackSource(
      uri: Uri.parse('https://audio.example.test/$id.mp3'),
      format: PlaybackAudioFormat.mp3,
      quality: PlaybackAudioQuality.standard,
      validForSeconds: 3600,
    ),
  );
}

class _FakeAudioEngine implements ForegroundAudioEngine {
  final List<_FakeAudioSession> sessions = [];

  @override
  Future<ForegroundAudioSession> loadRemote(Uri source) async {
    final session = _FakeAudioSession();
    sessions.add(session);
    return session;
  }
}

class _FakeAudioSession implements ForegroundAudioSession {
  final _states = StreamController<ForegroundAudioState>.broadcast();
  final _failures = StreamController<ForegroundAudioFailure>.broadcast();
  final _positions = StreamController<int>.broadcast();
  int playCalls = 0;
  int pauseCalls = 0;
  final List<int> seekPositions = [];

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> play() async {
    playCalls += 1;
    _states.add(ForegroundAudioState.playing);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    _states.add(ForegroundAudioState.paused);
  }

  @override
  Future<void> seekToMs(int positionMs) async {
    seekPositions.add(positionMs);
    _positions.add(positionMs);
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async => _states.add(ForegroundAudioState.stopped);

  @override
  Future<void> dispose() async {
    await _states.close();
    await _failures.close();
    await _positions.close();
  }
}
