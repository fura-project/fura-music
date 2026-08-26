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

  test('volume applies before play and survives source replacement', () async {
    final first = _FakeSession();
    final second = _FakeSession();
    final controller = ForegroundPlaybackController(
      _FakeEngine.queued([Future.value(first), Future.value(second)]),
    );

    await controller.setVolume(0.4);
    expect(controller.volume, 0.4);
    await controller.playRemote(Uri.parse('https://audio.example.test/one'));
    expect(first.volumes, [0.4]);
    expect(first.playCalls, 1);

    await controller.setVolume(0.25);
    expect(first.volumes, [0.4, 0.25]);
    await controller.playRemote(Uri.parse('https://audio.example.test/two'));
    expect(second.volumes, [0.25]);
    expect(second.playCalls, 1);

    await controller.setVolume(double.nan);
    await controller.setVolume(2);
    expect(controller.volume, 0.25);
    expect(second.volumes, [0.25]);
    controller.dispose();
  });

  test('late old volume failure cannot cross source replacement', () async {
    final oldVolume = Completer<void>();
    final first = _FakeSession(
      volumeResults: [Future.value(), oldVolume.future],
    );
    final second = _FakeSession();
    final controller = ForegroundPlaybackController(
      _FakeEngine.queued([Future.value(first), Future.value(second)]),
    );
    await controller.playRemote(Uri.parse('https://audio.example.test/one'));

    final pendingVolume = controller.setVolume(0.35);
    await Future<void>.delayed(Duration.zero);
    await controller.playRemote(Uri.parse('https://audio.example.test/two'));
    expect(second.volumes, [0.35]);

    oldVolume.completeError(
      const ForegroundAudioException(ForegroundAudioFailure.playback),
    );
    await pendingVolume;
    expect(controller.stage, ForegroundPlaybackStage.playing);
    expect(controller.failure, isNull);
    controller.dispose();

    final failing = _FakeSession(
      volumeFailure: ForegroundAudioFailure.playback,
    );
    final failedController = ForegroundPlaybackController(
      _FakeEngine.immediate(failing),
    );
    await failedController.playRemote(
      Uri.parse('https://audio.example.test/failing'),
    );
    expect(failedController.stage, ForegroundPlaybackStage.error);
    expect(failedController.failure, ForegroundAudioFailure.playback);
    expect(failing.playCalls, 0);
    failedController.dispose();
  });

  test('out-of-order volume updates converge to the latest value', () async {
    final oldVolume = Completer<void>();
    final session = _FakeSession(
      volumeResults: [Future.value(), oldVolume.future, Future.value()],
    );
    final controller = ForegroundPlaybackController(
      _FakeEngine.immediate(session),
    );
    await controller.playRemote(Uri.parse('https://audio.example.test/volume'));

    final oldUpdate = controller.setVolume(0.3);
    await Future<void>.delayed(Duration.zero);
    await controller.setVolume(0.7);
    oldVolume.complete();
    await oldUpdate;

    expect(controller.volume, 0.7);
    expect(session.volumes, [1, 0.3, 0.7, 0.7]);
    expect(controller.stage, ForegroundPlaybackStage.playing);
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
    this.volumeResults = const [],
    this.volumeFailure,
  });

  final _states = StreamController<ForegroundAudioState>.broadcast();
  final _failures = StreamController<ForegroundAudioFailure>.broadcast();
  final _positions = StreamController<int>.broadcast();
  final bool throwOnStop;
  final bool throwOnDispose;
  final Future<void>? seekResult;
  final ForegroundAudioFailure? seekFailure;
  final List<Future<void>> volumeResults;
  final ForegroundAudioFailure? volumeFailure;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  final List<int> seekPositions = [];
  final List<double> volumes = [];
  int _nextVolumeResult = 0;

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
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    final failure = volumeFailure;
    if (failure != null) throw ForegroundAudioException(failure);
    if (_nextVolumeResult < volumeResults.length) {
      await volumeResults[_nextVolumeResult++];
    }
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
