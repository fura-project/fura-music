import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';

void main() {
  test(
    'maps one session through play pause resume and terminal stop',
    () async {
      final session = _FakeSession();
      final controller = ForegroundPlaybackController(
        _FakeEngine.immediate(session),
      );

      await controller.playRemote(
        Uri.parse('https://audio.example.test/source.mp3?vkey=private'),
      );
      expect(controller.stage, ForegroundPlaybackStage.playing);
      expect(controller.canPause, isTrue);
      await controller.pause();
      expect(controller.stage, ForegroundPlaybackStage.paused);
      expect(controller.canResume, isTrue);
      await controller.resume();
      expect(controller.stage, ForegroundPlaybackStage.playing);
      await controller.stop();
      expect(controller.stage, ForegroundPlaybackStage.stopped);
      expect(session.stopCalls, 1);
      expect(session.disposeCalls, 1);

      controller.dispose();
    },
  );

  test('seek is bounded to the active playing or paused session', () async {
    final session = _FakeSession();
    final controller = ForegroundPlaybackController(
      _FakeEngine.immediate(session),
    );

    await controller.seekToMs(10);
    expect(session.seekPositions, isEmpty);

    await controller.playRemote(Uri.parse('https://audio.example.test/seek'));
    await controller.seekToMs(420);
    expect(session.seekPositions, [420]);
    expect(controller.positionMs, 420);

    await controller.pause();
    await controller.seekToMs(840);
    expect(session.seekPositions, [420, 840]);
    expect(controller.positionMs, 840);

    await controller.seekToMs(-1);
    expect(session.seekPositions, [420, 840]);
    controller.dispose();
  });

  test(
    'late old seek and current seek failure respect session ownership',
    () async {
      final oldSeek = Completer<void>();
      final first = _FakeSession(seekResult: oldSeek.future);
      final second = _FakeSession();
      final controller = ForegroundPlaybackController(
        _FakeEngine.queued([Future.value(first), Future.value(second)]),
      );
      await controller.playRemote(Uri.parse('https://audio.example.test/one'));
      final pendingSeek = controller.seekToMs(500);
      await Future<void>.delayed(Duration.zero);
      first.emitPosition(300);
      await Future<void>.delayed(Duration.zero);
      expect(controller.positionMs, 0);

      await controller.playRemote(Uri.parse('https://audio.example.test/two'));
      oldSeek.completeError(
        const ForegroundAudioException(ForegroundAudioFailure.playback),
      );
      await pendingSeek;
      expect(controller.stage, ForegroundPlaybackStage.playing);
      expect(controller.positionMs, 0);

      final failing = _FakeSession(
        seekFailure: ForegroundAudioFailure.playback,
      );
      final failedController = ForegroundPlaybackController(
        _FakeEngine.immediate(failing),
      );
      await failedController.playRemote(
        Uri.parse('https://audio.example.test/failing'),
      );
      await failedController.seekToMs(250);
      expect(failedController.stage, ForegroundPlaybackStage.error);
      expect(failedController.failure, ForegroundAudioFailure.playback);

      controller.dispose();
      failedController.dispose();
    },
  );

  test('source replacement suppresses every late old-session event', () async {
    final first = _FakeSession();
    final second = _FakeSession();
    final secondLoad = Completer<ForegroundAudioSession>();
    final engine = _FakeEngine.queued([Future.value(first), secondLoad.future]);
    final controller = ForegroundPlaybackController(engine);
    await controller.playRemote(Uri.parse('https://audio.example.test/one'));

    final replacement = controller.playRemote(
      Uri.parse('https://audio.example.test/two'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, ForegroundPlaybackStage.loading);
    expect(controller.positionMs, 0);
    first.emitState(ForegroundAudioState.completed);
    first.emitFailure(ForegroundAudioFailure.playback);
    first.emitPosition(900);
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, ForegroundPlaybackStage.loading);

    secondLoad.complete(second);
    await replacement;
    expect(controller.stage, ForegroundPlaybackStage.playing);
    second.emitPosition(150);
    await Future<void>.delayed(Duration.zero);
    expect(controller.positionMs, 150);
    expect(first.stopCalls, 1);
    expect(first.disposeCalls, 1);
    controller.dispose();
  });

  test('terminal cleanup failures cannot block a replacement source', () async {
    final first = _FakeSession(throwOnStop: true, throwOnDispose: true);
    final second = _FakeSession();
    final controller = ForegroundPlaybackController(
      _FakeEngine.queued([Future.value(first), Future.value(second)]),
    );
    await controller.playRemote(Uri.parse('https://audio.example.test/one'));

    await controller.playRemote(Uri.parse('https://audio.example.test/two'));

    expect(controller.stage, ForegroundPlaybackStage.playing);
    expect(first.stopCalls, 1);
    expect(first.disposeCalls, 1);
    expect(second.playCalls, 1);
    controller.dispose();
  });

  test(
    'stop and dispose suppress late completion and failure events',
    () async {
      final stoppedSession = _FakeSession();
      final stopped = ForegroundPlaybackController(
        _FakeEngine.immediate(stoppedSession),
      );
      await stopped.playRemote(Uri.parse('https://audio.example.test/stop'));
      stoppedSession.emitPosition(450);
      await Future<void>.delayed(Duration.zero);
      expect(stopped.positionMs, 450);
      await stopped.stop();
      expect(stopped.positionMs, 0);
      stoppedSession.emitState(ForegroundAudioState.completed);
      stoppedSession.emitFailure(ForegroundAudioFailure.playback);
      stoppedSession.emitPosition(900);
      await Future<void>.delayed(Duration.zero);
      expect(stopped.stage, ForegroundPlaybackStage.stopped);
      expect(stopped.failure, isNull);
      stopped.dispose();

      final disposedSession = _FakeSession();
      final disposed = ForegroundPlaybackController(
        _FakeEngine.immediate(disposedSession),
      );
      await disposed.playRemote(
        Uri.parse('https://audio.example.test/dispose'),
      );
      disposedSession.emitPosition(200);
      await Future<void>.delayed(Duration.zero);
      expect(disposed.positionMs, 200);
      disposed.dispose();
      disposedSession.emitState(ForegroundAudioState.completed);
      disposedSession.emitFailure(ForegroundAudioFailure.playback);
      disposedSession.emitPosition(900);
      await Future<void>.delayed(Duration.zero);
      expect(disposed.positionMs, 200);
      expect(disposedSession.stopCalls, 1);
      expect(disposedSession.disposeCalls, 1);
    },
  );

  test('load and event failures are coarse and never retain the URI', () async {
    const privateUri =
        'https://audio.example.test/source.mp3?vkey=must-not-leak';
    final loadFailure = ForegroundPlaybackController(
      _FakeEngine.failure(
        const ForegroundAudioException(ForegroundAudioFailure.load),
      ),
    );
    await loadFailure.playRemote(Uri.parse(privateUri));
    expect(loadFailure.stage, ForegroundPlaybackStage.error);
    expect(loadFailure.failure, ForegroundAudioFailure.load);
    expect(loadFailure.toString(), isNot(contains('must-not-leak')));
    expect(
      const ForegroundAudioException(ForegroundAudioFailure.load).toString(),
      isNot(contains('must-not-leak')),
    );
    loadFailure.dispose();

    final session = _FakeSession();
    final eventFailure = ForegroundPlaybackController(
      _FakeEngine.immediate(session),
    );
    await eventFailure.playRemote(Uri.parse(privateUri));
    session.emitFailure(ForegroundAudioFailure.playback);
    await Future<void>.delayed(Duration.zero);
    expect(eventFailure.stage, ForegroundPlaybackStage.error);
    expect(eventFailure.failure, ForegroundAudioFailure.playback);
    eventFailure.dispose();
  });
}

class _FakeEngine implements ForegroundAudioEngine {
  _FakeEngine.queued(this._loads) : _failure = null;

  _FakeEngine.immediate(ForegroundAudioSession session)
    : this.queued([Future.value(session)]);

  _FakeEngine.failure(this._failure) : _loads = const [];

  final List<Future<ForegroundAudioSession>> _loads;
  final Object? _failure;
  int _next = 0;

  @override
  Future<ForegroundAudioSession> loadRemote(Uri source) {
    final failure = _failure;
    if (failure != null) return Future.error(failure);
    return _loads[_next++];
  }
}

class _FakeSession implements ForegroundAudioSession {
  _FakeSession({
    this.throwOnStop = false,
    this.throwOnDispose = false,
    this.seekResult,
    this.seekFailure,
  });

  final _states = StreamController<ForegroundAudioState>.broadcast();
  final _failures = StreamController<ForegroundAudioFailure>.broadcast();
  final _positions = StreamController<int>.broadcast();
  final bool throwOnStop;
  final bool throwOnDispose;
  final Future<void>? seekResult;
  final ForegroundAudioFailure? seekFailure;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
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
    emitState(ForegroundAudioState.playing);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    emitState(ForegroundAudioState.paused);
  }

  @override
  Future<void> seekToMs(int positionMs) async {
    seekPositions.add(positionMs);
    final failure = seekFailure;
    if (failure != null) throw ForegroundAudioException(failure);
    final result = seekResult;
    if (result != null) await result;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    if (throwOnStop) throw StateError('synthetic stop failure');
    emitState(ForegroundAudioState.stopped);
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    if (throwOnDispose) throw StateError('synthetic dispose failure');
  }

  void emitState(ForegroundAudioState state) => _states.add(state);

  void emitFailure(ForegroundAudioFailure failure) => _failures.add(failure);

  void emitPosition(int positionMs) => _positions.add(positionMs);
}
