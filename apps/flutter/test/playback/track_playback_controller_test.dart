import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

void main() {
  const firstTrack = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:41001:0:1:firstMid',
    title: 'First track',
    artistNames: ['Artist'],
    durationSeconds: 120,
  );
  const secondTrack = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:41002:0:1:secondMid',
    title: 'Second track',
    artistNames: ['Artist'],
  );

  test('resolves one opaque track and maps playback lifecycle', () async {
    final audioSession = _FakeAudioSession();
    final engine = _FakeAudioEngine([audioSession]);
    final gateway = _FakeResolutionGateway([
      _ImmediateResolution(_successfulResolution('one')),
    ]);
    final controller = TrackPlaybackController(
      gateway,
      ForegroundPlaybackController(engine),
    );

    await controller.playTrack(firstTrack);
    expect(controller.track, same(firstTrack));
    expect(controller.stage, TrackPlaybackStage.playing);
    expect(gateway.requests, [('qq-music', 'track:41001:0:1:firstMid')]);
    expect(engine.requestedUris.single.queryParameters['vkey'], 'one');
    var positionNotifications = 0;
    controller.addListener(() => positionNotifications += 1);
    audioSession.emitPosition(375);
    await Future<void>.delayed(Duration.zero);
    expect(controller.positionMs, 375);
    expect(positionNotifications, 1);
    expect(controller.durationMs, 120000);
    expect(controller.canSeek, isTrue);
    await controller.seekToMs(130000);
    await Future<void>.delayed(Duration.zero);
    expect(audioSession.seekPositions, [120000]);
    expect(controller.positionMs, 120000);
    await controller.pause();
    expect(controller.stage, TrackPlaybackStage.paused);
    await controller.seekToMs(-25);
    await Future<void>.delayed(Duration.zero);
    expect(audioSession.seekPositions, [120000, 0]);
    expect(controller.positionMs, 0);
    await controller.resume();
    expect(controller.stage, TrackPlaybackStage.playing);
    audioSession.emitState(ForegroundAudioState.completed);
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, TrackPlaybackStage.completed);
    controller.dispose();
  });

  test('unknown duration never enables or forwards seeking', () async {
    const unknownDuration = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41003:0:1:unknownMid',
      title: 'Unknown duration',
      artistNames: ['Artist'],
    );
    final session = _FakeAudioSession();
    final controller = TrackPlaybackController(
      _FakeResolutionGateway([
        _ImmediateResolution(_successfulResolution('unknown')),
      ]),
      ForegroundPlaybackController(_FakeAudioEngine([session])),
    );

    await controller.playTrack(unknownDuration);
    expect(controller.durationMs, isNull);
    expect(controller.canSeek, isFalse);
    await controller.seekToMs(1000);
    expect(session.seekPositions, isEmpty);
    controller.dispose();
  });

  test('keeps resolution failures distinct from engine failures', () async {
    for (final failure in [
      MediaResolutionFailure.authenticationRequired,
      MediaResolutionFailure.credentialRejected,
      MediaResolutionFailure.unavailable,
      MediaResolutionFailure.network,
    ]) {
      final controller = TrackPlaybackController(
        _FakeResolutionGateway([
          _ImmediateResolution(MediaResolutionResult(failure: failure)),
        ]),
        ForegroundPlaybackController(_FakeAudioEngine(const [])),
      );
      await controller.playTrack(firstTrack);
      expect(controller.stage, TrackPlaybackStage.resolutionError);
      expect(controller.resolutionFailure, failure);
      expect(controller.engineFailure, isNull);
      controller.dispose();
    }

    final privateUri = _successfulResolution('must-not-leak');
    final controller = TrackPlaybackController(
      _FakeResolutionGateway([_ImmediateResolution(privateUri)]),
      ForegroundPlaybackController(
        _FakeAudioEngine(
          const [],
          failure: const ForegroundAudioException(ForegroundAudioFailure.load),
        ),
      ),
    );
    await controller.playTrack(firstTrack);
    expect(controller.stage, TrackPlaybackStage.engineError);
    expect(controller.engineFailure, ForegroundAudioFailure.load);
    expect(controller.resolutionFailure, isNull);
    expect(controller.toString(), isNot(contains('must-not-leak')));
    controller.dispose();
  });

  test(
    'track replacement cancels and suppresses late old resolution',
    () async {
      final firstResult = Completer<MediaResolutionResult>();
      final firstOperation = _PendingResolution(firstResult.future);
      final secondOperation = _ImmediateResolution(
        _successfulResolution('two'),
      );
      final gateway = _FakeResolutionGateway([firstOperation, secondOperation]);
      final engine = _FakeAudioEngine([_FakeAudioSession()]);
      final controller = TrackPlaybackController(
        gateway,
        ForegroundPlaybackController(engine),
      );

      final oldRequest = controller.playTrack(firstTrack);
      await firstOperation.started.future;
      final replacement = controller.playTrack(secondTrack);
      await replacement;
      expect(firstOperation.cancelCalls, 1);
      expect(controller.track, same(secondTrack));
      expect(controller.stage, TrackPlaybackStage.playing);

      firstResult.complete(
        const MediaResolutionResult(failure: MediaResolutionFailure.network),
      );
      await oldRequest;
      expect(controller.track, same(secondTrack));
      expect(controller.stage, TrackPlaybackStage.playing);
      expect(engine.requestedUris.single.queryParameters['vkey'], 'two');
      controller.dispose();
    },
  );

  test('stop and dispose cancel and suppress late resolution', () async {
    final stoppedResult = Completer<MediaResolutionResult>();
    final stoppedOperation = _PendingResolution(stoppedResult.future);
    final stoppedEngine = _FakeAudioEngine(const []);
    final stopped = TrackPlaybackController(
      _FakeResolutionGateway([stoppedOperation]),
      ForegroundPlaybackController(stoppedEngine),
    );
    final stoppingRequest = stopped.playTrack(firstTrack);
    await stoppedOperation.started.future;
    await stopped.stop();
    expect(stoppedOperation.cancelCalls, 1);
    stoppedResult.complete(_successfulResolution('stopped'));
    await stoppingRequest;
    expect(stopped.stage, TrackPlaybackStage.stopped);
    expect(stoppedEngine.requestedUris, isEmpty);
    stopped.dispose();

    final disposedResult = Completer<MediaResolutionResult>();
    final disposedOperation = _PendingResolution(disposedResult.future);
    final disposedEngine = _FakeAudioEngine(const []);
    final disposed = TrackPlaybackController(
      _FakeResolutionGateway([disposedOperation]),
      ForegroundPlaybackController(disposedEngine),
    );
    final disposedRequest = disposed.playTrack(firstTrack);
    await disposedOperation.started.future;
    disposed.dispose();
    expect(disposedOperation.cancelCalls, 1);
    disposedResult.complete(_successfulResolution('disposed'));
    await disposedRequest;
    expect(disposedEngine.requestedUris, isEmpty);
  });
}

MediaResolutionResult _successfulResolution(String vkey) =>
    MediaResolutionResult(
      source: ResolvedPlaybackSource(
        uri: Uri.parse('https://audio.example.test/source.mp3?vkey=$vkey'),
        format: PlaybackAudioFormat.mp3,
        quality: PlaybackAudioQuality.standard,
        validForSeconds: 7_200,
      ),
    );

class _FakeResolutionGateway implements MediaResolutionGateway {
  _FakeResolutionGateway(this._operations);

  final List<MediaResolutionOperation> _operations;
  final List<(String, String)> requests = [];
  int _next = 0;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) {
    requests.add((providerId, opaqueTrackId));
    return _operations[_next++];
  }
}

class _ImmediateResolution implements MediaResolutionOperation {
  const _ImmediateResolution(this._result);

  final MediaResolutionResult _result;

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async => _result;
}

class _PendingResolution implements MediaResolutionOperation {
  _PendingResolution(this._result);

  final Future<MediaResolutionResult> _result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<MediaResolutionResult> run() {
    started.complete();
    return _result;
  }
}

class _FakeAudioEngine implements ForegroundAudioEngine {
  _FakeAudioEngine(this._sessions, {this.failure});

  final List<ForegroundAudioSession> _sessions;
  final Object? failure;
  final List<Uri> requestedUris = [];
  int _next = 0;

  @override
  Future<ForegroundAudioSession> loadRemote(Uri source) async {
    requestedUris.add(source);
    final failure = this.failure;
    if (failure != null) throw failure;
    return _sessions[_next++];
  }
}

class _FakeAudioSession implements ForegroundAudioSession {
  final _states = StreamController<ForegroundAudioState>.broadcast();
  final _failures = StreamController<ForegroundAudioFailure>.broadcast();
  final _positions = StreamController<int>.broadcast();
  final List<int> seekPositions = [];

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> pause() async => emitState(ForegroundAudioState.paused);

  @override
  Future<void> play() async => emitState(ForegroundAudioState.playing);

  @override
  Future<void> seekToMs(int positionMs) async {
    seekPositions.add(positionMs);
    emitPosition(positionMs);
  }

  @override
  Future<void> stop() async => emitState(ForegroundAudioState.stopped);

  @override
  Future<void> dispose() async {}

  void emitState(ForegroundAudioState state) => _states.add(state);

  void emitPosition(int positionMs) => _positions.add(positionMs);
}
