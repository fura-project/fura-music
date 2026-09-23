import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/media_kit_foreground_audio_engine.dart';

void main() {
  test(
    'reuses one Player across source replacement and terminal disposal',
    () async {
      final player = _FakeMediaKitPlayer();
      final focus = _FakeFocusManager();
      final engine = MediaKitForegroundAudioEngine(
        player: player,
        audioFocusManager: focus,
      );

      final first = await engine.loadRemote(
        Uri.parse('https://audio.example.test/one.mp3?vkey=private'),
      );
      await first.setVolume(0.35);
      await first.play();
      await first.pause();
      await first.seekToMs(420);
      await first.stop();
      await first.dispose();

      final second = await engine.loadRemote(
        Uri.parse('https://audio.example.test/two.flac?vkey=private'),
        format: ForegroundAudioFormat.flac,
      );
      await second.play();

      expect(engine.debugPlayer, same(player));
      expect(player.opened.map((uri) => uri.path), ['/one.mp3', '/two.flac']);
      expect(player.playCalls, 2);
      expect(player.pauseCalls, 1);
      expect(player.stopCalls, 1);
      expect(player.seekPositions, [const Duration(milliseconds: 420)]);
      expect(player.volumes, [35]);
      expect(player.disposeCalls, 0);
      expect(focus.values, [true, false, true]);

      await second.dispose();
      await engine.dispose();
      await engine.dispose();
      expect(player.disposeCalls, 1);
      expect(focus.values.last, isFalse);
    },
  );

  test(
    'maps playing position completion and errors to the common contract',
    () async {
      final player = _FakeMediaKitPlayer();
      final engine = MediaKitForegroundAudioEngine(
        player: player,
        audioFocusManager: _FakeFocusManager(),
      );
      final session = await engine.loadRemote(
        Uri.parse('https://audio.example.test/probe.m4a'),
        format: ForegroundAudioFormat.m4a,
      );
      final states = <ForegroundAudioState>[];
      final positions = <int>[];
      final failures = <ForegroundAudioFailure>[];
      final subscriptions = <StreamSubscription<Object?>>[
        session.states.listen(states.add),
        session.positionMs.listen(positions.add),
        session.failures.listen(failures.add),
      ];

      player.emitPlaying(true);
      await Future<void>.delayed(Duration.zero);
      player.emitPosition(const Duration(milliseconds: 321));
      player.emitPlaying(false);
      await Future<void>.delayed(Duration.zero);
      player.emitCompleted();
      player.emitError('source-bearing synthetic error');
      await Future<void>.delayed(Duration.zero);

      expect(
        states,
        containsAllInOrder([
          ForegroundAudioState.playing,
          ForegroundAudioState.paused,
          ForegroundAudioState.completed,
        ]),
      );
      expect(positions, [321]);
      expect(failures, [ForegroundAudioFailure.playback]);
      expect(failures.single.name, isNot(contains('source-bearing')));

      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await session.dispose();
      await engine.dispose();
    },
  );

  test('keeps audio_session as the only focus owner', () async {
    final player = _FakeMediaKitPlayer();
    final focus = _FakeFocusManager(allowActivation: false);
    final engine = MediaKitForegroundAudioEngine(
      player: player,
      audioFocusManager: focus,
    );
    final session = await engine.loadRemote(
      Uri.parse('https://audio.example.test/focus.mp3'),
    );

    await expectLater(
      session.play(),
      throwsA(
        isA<ForegroundAudioException>().having(
          (error) => error.failure,
          'failure',
          ForegroundAudioFailure.playback,
        ),
      ),
    );
    expect(player.playCalls, 0);
    expect(focus.values, [true]);

    await session.dispose();
    await engine.dispose();
  });

  test('reuses one Player across a 100-source replacement soak', () async {
    final player = _FakeMediaKitPlayer();
    final engine = MediaKitForegroundAudioEngine(
      player: player,
      audioFocusManager: _FakeFocusManager(),
    );

    for (var index = 0; index < 100; index += 1) {
      final session = await engine.loadRemote(
        Uri.parse('https://audio.example.test/source-$index.mp3'),
      );
      if (index < 20) {
        await session.play();
        await session.pause();
        await session.play();
      }
      await session.dispose();
    }

    expect(engine.debugPlayer, same(player));
    expect(player.opened, hasLength(100));
    expect(player.playCalls, 40);
    expect(player.pauseCalls, 20);
    expect(player.disposeCalls, 0);

    await engine.dispose();
    expect(player.disposeCalls, 1);
  });

  test('invalid and failed opens remain coarse and never fallback', () async {
    final player = _FakeMediaKitPlayer()..openFailure = StateError('private');
    final engine = MediaKitForegroundAudioEngine(player: player);

    await expectLater(
      engine.loadRemote(Uri.parse('file:///tmp/private.mp3')),
      throwsA(isA<ForegroundAudioException>()),
    );
    await expectLater(
      engine.loadRemote(
        Uri.parse('https://audio.example.test/private.mp3?vkey=secret'),
      ),
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
              isNot(contains('secret')),
            ),
      ),
    );
    expect(player.opened, hasLength(1));
    expect(player.playCalls, 0);

    await engine.dispose();
  });
}

class _FakeMediaKitPlayer implements MediaKitAudioPlayer {
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final List<Uri> opened = [];
  final List<Duration> seekPositions = [];
  final List<double> volumes = [];
  Object? openFailure;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<bool> get completed => _completed.stream;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> open(Uri source) async {
    opened.add(source);
    final failure = openFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> play() async => playCalls += 1;

  @override
  Future<void> pause() async => pauseCalls += 1;

  @override
  Future<void> stop() async => stopCalls += 1;

  @override
  Future<void> seek(Duration position) async => seekPositions.add(position);

  @override
  Future<void> setVolume(double percent) async => volumes.add(percent);

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _playing.close();
    await _completed.close();
    await _position.close();
    await _errors.close();
  }

  void emitPlaying(bool value) => _playing.add(value);

  void emitCompleted() => _completed.add(true);

  void emitPosition(Duration value) => _position.add(value);

  void emitError(String value) => _errors.add(value);
}

class _FakeFocusManager implements ForegroundAudioFocusManager {
  _FakeFocusManager({this.allowActivation = true});

  final bool allowActivation;
  final List<bool> values = [];

  @override
  Future<bool> setActive(bool active) async {
    values.add(active);
    return !active || allowActivation;
  }
}
