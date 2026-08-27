import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/music_video/track_music_video_controller.dart';
import 'package:flutterustmusic/music_video/track_music_video_engine.dart';
import 'package:flutterustmusic/music_video/track_music_video_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

void main() {
  test('MV load yields music ownership and close does not resume it', () async {
    final audioSession = _FakeAudioSession();
    final queue = _musicController(
      initialTrack: track,
      audioSessions: [audioSession],
    );
    await queue.playback.playTrack(track);
    expect(queue.playback.stage, TrackPlaybackStage.playing);

    final videoSession = _FakeVideoSession(
      afterOpen: TrackMusicVideoSessionStage.playing,
    );
    final controller = TrackMusicVideoController(
      gateway: _FakeVideoGateway.immediate(_videoResult()),
      engine: _FakeVideoEngine([videoSession]),
      musicController: queue,
      track: track,
    );

    await controller.load();

    expect(audioSession.pauseCalls, 1);
    expect(queue.playback.stage, TrackPlaybackStage.paused);
    expect(controller.stage, TrackMusicVideoStage.playing);
    expect(videoSession.openedUri, _video.sourceUri);

    controller.dispose();
    expect(videoSession.disposed, isTrue);
    expect(audioSession.playCalls, 1);
    expect(queue.playback.stage, TrackPlaybackStage.paused);
    queue.dispose();
  });

  test('no associated MV and unavailable source remain distinct', () async {
    final queue = _musicController(initialTrack: track);
    final noMv = TrackMusicVideoController(
      gateway: _FakeVideoGateway.immediate(const TrackMusicVideoResult()),
      engine: _FakeVideoEngine(),
      musicController: queue,
      track: track,
    );
    await noMv.load();
    expect(noMv.stage, TrackMusicVideoStage.unavailable);
    expect(noMv.failure, isNull);
    expect(noMv.canRetry, isFalse);
    noMv.dispose();

    final noSource = TrackMusicVideoController(
      gateway: _FakeVideoGateway.immediate(
        const TrackMusicVideoResult(
          failure: TrackMusicVideoFailure.sourceUnavailable,
        ),
      ),
      engine: _FakeVideoEngine(),
      musicController: queue,
      track: track,
    );
    await noSource.load();
    expect(noSource.stage, TrackMusicVideoStage.error);
    expect(noSource.failure, TrackMusicVideoFailure.sourceUnavailable);
    expect(noSource.canRetry, isFalse);
    noSource.dispose();
    queue.dispose();
  });

  test('Queue Track replacement interrupts and disposes MV session', () async {
    final queue = _musicController(
      initialTrack: track,
      audioSessions: [_FakeAudioSession()],
    );
    final videoSession = _FakeVideoSession(
      afterOpen: TrackMusicVideoSessionStage.playing,
    );
    final controller = TrackMusicVideoController(
      gateway: _FakeVideoGateway.immediate(_videoResult()),
      engine: _FakeVideoEngine([videoSession]),
      musicController: queue,
      track: track,
    );
    await controller.load();

    await queue.replaceAndPlay([otherTrack], 0);

    expect(controller.stage, TrackMusicVideoStage.interrupted);
    expect(controller.session, isNull);
    expect(videoSession.disposed, isTrue);
    controller.dispose();
    queue.dispose();
  });

  test('restarted load cancels and suppresses the stale result', () async {
    final first = Completer<TrackMusicVideoResult>();
    final second = Completer<TrackMusicVideoResult>();
    final gateway = _FakeVideoGateway([first.future, second.future]);
    final queue = _musicController(initialTrack: track);
    final controller = TrackMusicVideoController(
      gateway: gateway,
      engine: _FakeVideoEngine(),
      musicController: queue,
      track: track,
    );

    final staleLoad = controller.load();
    final currentLoad = controller.load();
    expect(gateway.operations.first.cancelled, isTrue);
    second.complete(const TrackMusicVideoResult());
    await currentLoad;
    expect(controller.stage, TrackMusicVideoStage.unavailable);

    first.complete(_videoResult());
    await staleLoad;
    expect(controller.stage, TrackMusicVideoStage.unavailable);
    expect(gateway.operations[1].cancelled, isFalse);
    controller.dispose();
    queue.dispose();
  });

  test('MV controls resume, pause, and bound seeks to the session', () async {
    final queue = _musicController(initialTrack: track);
    final session = _FakeVideoSession(
      afterOpen: TrackMusicVideoSessionStage.paused,
      duration: const Duration(minutes: 2),
    );
    final controller = TrackMusicVideoController(
      gateway: _FakeVideoGateway.immediate(_videoResult()),
      engine: _FakeVideoEngine([session]),
      musicController: queue,
      track: track,
    );
    await controller.load();

    await controller.togglePlayback();
    expect(session.playCalls, 1);
    expect(controller.stage, TrackMusicVideoStage.playing);
    await controller.togglePlayback();
    expect(session.pauseCalls, 1);
    expect(controller.stage, TrackMusicVideoStage.paused);

    await controller.seek(const Duration(minutes: 10));
    expect(session.seeks.last, const Duration(minutes: 2));
    session.emit(TrackMusicVideoSessionStage.completed);
    await controller.togglePlayback();
    expect(session.seeks.last, Duration.zero);
    expect(session.playCalls, 2);
    controller.dispose();
    queue.dispose();
  });
}

const track = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:one',
  title: 'Track one',
  artistNames: ['Artist'],
  durationSeconds: 180,
);

const otherTrack = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:two',
  title: 'Track two',
  artistNames: ['Artist'],
  durationSeconds: 200,
);

const _video = TrackMusicVideoSummary(
  providerId: 'qq-music',
  opaqueId: 'mv:one',
  title: 'Track one MV',
  artistNames: ['Artist'],
  sourceUri: 'https://media.example.invalid/mv.mp4',
  quality: TrackMusicVideoQuality.hd,
  durationSeconds: 120,
);

TrackMusicVideoResult _videoResult() =>
    const TrackMusicVideoResult(musicVideo: _video);

QueuePlaybackController _musicController({
  required PlaylistTrackSummary initialTrack,
  List<_FakeAudioSession> audioSessions = const [],
}) => QueuePlaybackController(
  _FakeQueueGateway(initialTrack),
  TrackPlaybackController(
    const _FakeMediaGateway(),
    ForegroundPlaybackController(_FakeAudioEngine(audioSessions)),
  ),
);

class _FakeVideoGateway implements TrackMusicVideoGateway {
  _FakeVideoGateway(this.results);

  factory _FakeVideoGateway.immediate(TrackMusicVideoResult result) =>
      _FakeVideoGateway([Future.value(result)]);

  final List<Future<TrackMusicVideoResult>> results;
  final List<_FakeVideoOperation> operations = [];
  int _next = 0;

  @override
  TrackMusicVideoLoadOperation beginLoad({
    required PlaylistTrackSummary track,
  }) {
    final operation = _FakeVideoOperation(results[_next++]);
    operations.add(operation);
    return operation;
  }
}

class _FakeVideoOperation implements TrackMusicVideoLoadOperation {
  _FakeVideoOperation(this.result);

  final Future<TrackMusicVideoResult> result;
  bool cancelled = false;

  @override
  Future<TrackMusicVideoResult> run() => result;

  @override
  bool cancel() {
    if (cancelled) return false;
    cancelled = true;
    return true;
  }
}

class _FakeVideoEngine implements TrackMusicVideoEngine {
  _FakeVideoEngine([this.sessions = const []]);

  final List<_FakeVideoSession> sessions;
  int _next = 0;

  @override
  TrackMusicVideoSession createSession() => sessions[_next++];
}

class _FakeVideoSession extends TrackMusicVideoSession {
  _FakeVideoSession({
    required this.afterOpen,
    this.duration = const Duration(minutes: 2),
  });

  final TrackMusicVideoSessionStage afterOpen;
  @override
  final Duration duration;
  @override
  Duration position = Duration.zero;
  TrackMusicVideoSessionStage _stage = TrackMusicVideoSessionStage.loading;
  String? openedUri;
  int playCalls = 0;
  int pauseCalls = 0;
  final List<Duration> seeks = [];
  bool disposed = false;

  @override
  TrackMusicVideoSessionStage get stage => _stage;

  @override
  Future<void> open(String uri) async {
    openedUri = uri;
    emit(afterOpen);
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    emit(TrackMusicVideoSessionStage.playing);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    emit(TrackMusicVideoSessionStage.paused);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    this.position = position;
    notifyListeners();
  }

  void emit(TrackMusicVideoSessionStage value) {
    _stage = value;
    notifyListeners();
  }

  @override
  Widget buildVideo({Key? key}) => SizedBox(key: key);

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _FakeQueueGateway implements PlaybackQueueGateway {
  _FakeQueueGateway(PlaylistTrackSummary initialTrack)
    : _snapshot = _queueSnapshot([initialTrack], 0);

  PlaybackQueueSnapshot _snapshot;

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) {
    _snapshot = _queueSnapshot(tracks, currentIndex);
    return PlaybackQueueResult(snapshot: _snapshot, playbackRequested: true);
  }

  @override
  PlaybackQueueResult clear() => replace(tracks: const [], currentIndex: null);

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) =>
      throw UnimplementedError();
  @override
  PlaybackQueueResult select(int index) => throw UnimplementedError();
  @override
  PlaybackQueueResult advance() => throw UnimplementedError();
  @override
  PlaybackQueueResult rewind() => throw UnimplementedError();
  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) =>
      PlaybackQueueResult(snapshot: _snapshot);
  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) =>
      PlaybackQueueResult(snapshot: _snapshot);
  @override
  PlaybackQueueResult completeCurrent() => throw UnimplementedError();
  @override
  PlaybackQueueResult remove(int index) => throw UnimplementedError();
}

PlaybackQueueSnapshot _queueSnapshot(
  List<PlaylistTrackSummary> tracks,
  int? currentIndex,
) => PlaybackQueueSnapshot(
  tracks: tracks,
  currentIndex: currentIndex,
  hasPrevious: currentIndex != null && currentIndex > 0,
  hasNext: currentIndex != null && currentIndex + 1 < tracks.length,
);

class _FakeMediaGateway implements MediaResolutionGateway {
  const _FakeMediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => const _FakeMediaOperation();
}

class _FakeMediaOperation implements MediaResolutionOperation {
  const _FakeMediaOperation();

  @override
  Future<MediaResolutionResult> run() async => MediaResolutionResult(
    source: ResolvedPlaybackSource(
      uri: Uri.parse('https://media.example.invalid/audio.mp3'),
      format: PlaybackAudioFormat.mp3,
      quality: PlaybackAudioQuality.standard,
      validForSeconds: 60,
    ),
  );

  @override
  bool cancel() => true;
}

class _FakeAudioEngine implements ForegroundAudioEngine {
  _FakeAudioEngine(this.sessions);

  final List<_FakeAudioSession> sessions;
  int _next = 0;

  @override
  Future<ForegroundAudioSession> loadRemote(Uri source) async =>
      sessions[_next++];
}

class _FakeAudioSession implements ForegroundAudioSession {
  final StreamController<ForegroundAudioState> _states =
      StreamController.broadcast();
  final StreamController<ForegroundAudioFailure> _failures =
      StreamController.broadcast();
  final StreamController<int> _positions = StreamController.broadcast();
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Stream<ForegroundAudioState> get states => _states.stream;
  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;
  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> play() async {
    playCalls += 1;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
  }

  @override
  Future<void> seekToMs(int positionMs) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _states.close();
    await _failures.close();
    await _positions.close();
  }
}
