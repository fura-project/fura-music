import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/media_kit_foreground_audio_engine.dart';

void main() {
  _runForegroundAudioEngineContract(
    'AudioplayersForegroundAudioEngine',
    _AudioplayersHarness.new,
  );
  _runForegroundAudioEngineContract(
    'MediaKitForegroundAudioEngine',
    _MediaKitHarness.new,
  );
}

void _runForegroundAudioEngineContract(
  String name,
  _EngineHarness Function() createHarness,
) {
  group('$name shared contract', () {
    test('open play pause resume seek volume stop and dispose', () async {
      final harness = createHarness();
      final session = await harness.engine.loadRemote(
        Uri.parse('https://audio.example.test/contract.mp3?vkey=private'),
        format: ForegroundAudioFormat.mp3,
      );
      final states = <ForegroundAudioState>[];
      final positions = <int>[];
      final stateSubscription = session.states.listen(states.add);
      final positionSubscription = session.positionMs.listen(positions.add);

      await session.play();
      await session.pause();
      await session.play();
      await session.seekToMs(625);
      await session.setVolume(0.42);
      harness.emitPosition(const Duration(milliseconds: 625));
      await session.stop();
      await Future<void>.delayed(Duration.zero);

      expect(harness.opened.single.path, '/contract.mp3');
      expect(harness.playCalls, 2);
      expect(harness.pauseCalls, 1);
      expect(harness.stopCalls, 1);
      expect(harness.seekPositions, [const Duration(milliseconds: 625)]);
      expect(harness.normalizedVolumes, [closeTo(0.42, 0.0001)]);
      expect(
        states,
        containsAllInOrder([
          ForegroundAudioState.playing,
          ForegroundAudioState.paused,
          ForegroundAudioState.playing,
          ForegroundAudioState.stopped,
        ]),
      );
      expect(positions, [625]);
      expect(harness.focusValues, [true, false, true, false]);

      await stateSubscription.cancel();
      await positionSubscription.cancel();
      await session.dispose();
      await harness.engine.dispose();
      expect(harness.resourceDisposeCalls, 1);
    });

    test('completion and errors map to common coarse events', () async {
      final harness = createHarness();
      final session = await harness.engine.loadRemote(
        Uri.parse('https://audio.example.test/events.m4a?vkey=private'),
        format: ForegroundAudioFormat.m4a,
      );
      final states = <ForegroundAudioState>[];
      final failures = <ForegroundAudioFailure>[];
      final subscriptions = <StreamSubscription<Object?>>[
        session.states.listen(states.add),
        session.failures.listen(failures.add),
      ];

      await session.play();
      harness.emitCompletion();
      harness.emitFailure();
      await Future<void>.delayed(Duration.zero);

      expect(states, contains(ForegroundAudioState.completed));
      expect(failures, [ForegroundAudioFailure.playback]);

      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await session.dispose();
      await harness.engine.dispose();
    });

    test('source replacement uses the same engine without fallback', () async {
      final harness = createHarness();
      final first = await harness.engine.loadRemote(
        Uri.parse('https://audio.example.test/first.mp3'),
      );
      await first.dispose();
      final second = await harness.engine.loadRemote(
        Uri.parse('https://audio.example.test/second.flac'),
        format: ForegroundAudioFormat.flac,
      );

      expect(harness.opened.map((uri) => uri.path), [
        '/first.mp3',
        '/second.flac',
      ]);
      expect(harness.backendInstanceCount, harness.expectedBackendInstances);

      await second.dispose();
      await harness.engine.dispose();
    });

    test('invalid source fails with typed source-free failure', () async {
      final harness = createHarness();

      await expectLater(
        harness.engine.loadRemote(Uri.parse('file:///tmp/private.mp3')),
        throwsA(
          isA<ForegroundAudioException>()
              .having(
                (error) => error.failure,
                'failure',
                ForegroundAudioFailure.load,
              )
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('/tmp/private.mp3')),
              ),
        ),
      );
      expect(harness.opened, isEmpty);

      await harness.engine.dispose();
    });
  });
}

abstract class _EngineHarness {
  ForegroundAudioEngine get engine;
  List<Uri> get opened;
  int get playCalls;
  int get pauseCalls;
  int get stopCalls;
  List<Duration> get seekPositions;
  List<Object> get normalizedVolumes;
  List<bool> get focusValues;
  int get resourceDisposeCalls;
  int get backendInstanceCount;
  int get expectedBackendInstances;

  void emitPosition(Duration position);
  void emitCompletion();
  void emitFailure();
}

class _AudioplayersHarness implements _EngineHarness {
  _AudioplayersHarness() {
    engine = AudioplayersForegroundAudioEngine(
      playerFactory: () {
        final player = _FakeAudioplayersPlayer();
        players.add(player);
        return player;
      },
      audioFocusManager: focus,
    );
  }

  final focus = _ContractFocusManager();
  final List<_FakeAudioplayersPlayer> players = [];

  @override
  late final ForegroundAudioEngine engine;

  _FakeAudioplayersPlayer get _current => players.last;

  @override
  List<Uri> get opened => [for (final player in players) ...player.opened];

  @override
  int get playCalls =>
      players.fold(0, (total, player) => total + player.playCalls);

  @override
  int get pauseCalls =>
      players.fold(0, (total, player) => total + player.pauseCalls);

  @override
  int get stopCalls =>
      players.fold(0, (total, player) => total + player.stopCalls);

  @override
  List<Duration> get seekPositions => [
    for (final player in players) ...player.seekPositions,
  ];

  @override
  List<Object> get normalizedVolumes => [
    for (final player in players) ...player.volumes,
  ];

  @override
  List<bool> get focusValues => focus.values;

  @override
  int get resourceDisposeCalls =>
      players.fold(0, (total, player) => total + player.disposeCalls);

  @override
  int get backendInstanceCount => players.length;

  @override
  int get expectedBackendInstances => 2;

  @override
  void emitPosition(Duration position) =>
      _current.positionsController.add(position);

  @override
  void emitCompletion() =>
      _current.statesController.add(audio.PlayerState.completed);

  @override
  void emitFailure() =>
      _current.eventsController.addError(StateError('synthetic'));
}

class _FakeAudioplayersPlayer implements AudioplayersAudioPlayer {
  final statesController = StreamController<audio.PlayerState>.broadcast();
  final eventsController = StreamController<Object?>.broadcast();
  final positionsController = StreamController<Duration>.broadcast();
  final List<Uri> opened = [];
  final List<Duration> seekPositions = [];
  final List<double> volumes = [];
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<audio.PlayerState> get states => statesController.stream;

  @override
  Stream<Object?> get events => eventsController.stream;

  @override
  Stream<Duration> get positions => positionsController.stream;

  @override
  Future<void> setAudioContext(audio.AudioContext context) async {}

  @override
  Future<void> setReleaseMode(audio.ReleaseMode mode) async {}

  @override
  Future<void> setSourceUrl(String source, {required String mimeType}) async =>
      opened.add(Uri.parse(source));

  @override
  Future<void> resume() async {
    playCalls += 1;
    statesController.add(audio.PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    statesController.add(audio.PlayerState.paused);
  }

  @override
  Future<void> seek(Duration position) async => seekPositions.add(position);

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> stop() async {
    stopCalls += 1;
    statesController.add(audio.PlayerState.stopped);
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await statesController.close();
    await eventsController.close();
    await positionsController.close();
  }
}

class _MediaKitHarness implements _EngineHarness {
  _MediaKitHarness() {
    player = _FakeMediaKitContractPlayer();
    focus = _ContractFocusManager();
    engine = MediaKitForegroundAudioEngine(
      player: player,
      audioFocusManager: focus,
    );
  }

  late final _FakeMediaKitContractPlayer player;
  late final _ContractFocusManager focus;

  @override
  late final ForegroundAudioEngine engine;

  @override
  List<Uri> get opened => player.opened;

  @override
  int get playCalls => player.playCalls;

  @override
  int get pauseCalls => player.pauseCalls;

  @override
  int get stopCalls => player.stopCalls;

  @override
  List<Duration> get seekPositions => player.seekPositions;

  @override
  List<Object> get normalizedVolumes =>
      player.volumes.map<Object>((value) => value / 100).toList();

  @override
  List<bool> get focusValues => focus.values;

  @override
  int get resourceDisposeCalls => player.disposeCalls;

  @override
  int get backendInstanceCount => 1;

  @override
  int get expectedBackendInstances => 1;

  @override
  void emitPosition(Duration position) =>
      player.positionController.add(position);

  @override
  void emitCompletion() => player.completedController.add(true);

  @override
  void emitFailure() => player.errorsController.add('synthetic');
}

class _FakeMediaKitContractPlayer implements MediaKitAudioPlayer {
  final playingController = StreamController<bool>.broadcast();
  final completedController = StreamController<bool>.broadcast();
  final positionController = StreamController<Duration>.broadcast();
  final errorsController = StreamController<String>.broadcast();
  final List<Uri> opened = [];
  final List<Duration> seekPositions = [];
  final List<double> volumes = [];
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<bool> get playing => playingController.stream;

  @override
  Stream<bool> get completed => completedController.stream;

  @override
  Stream<Duration> get position => positionController.stream;

  @override
  Stream<String> get errors => errorsController.stream;

  @override
  Future<void> open(Uri source) async => opened.add(source);

  @override
  Future<void> play() async {
    playCalls += 1;
    playingController.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    playingController.add(false);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    playingController.add(false);
  }

  @override
  Future<void> seek(Duration position) async => seekPositions.add(position);

  @override
  Future<void> setVolume(double percent) async => volumes.add(percent);

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await playingController.close();
    await completedController.close();
    await positionController.close();
    await errorsController.close();
  }
}

class _ContractFocusManager implements ForegroundAudioFocusManager {
  final List<bool> values = [];

  @override
  Future<bool> setActive(bool active) async {
    values.add(active);
    return true;
  }
}
