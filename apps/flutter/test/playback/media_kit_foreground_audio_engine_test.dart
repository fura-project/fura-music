import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/media_kit_foreground_audio_engine.dart';

void main() {
  test('operation and rebuild diagnostics contain categories, never native errors or sources', () async {
    final messages = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = previous);
    final first = _FakeMediaKitPlayer()..openGate = Completer<void>().future;
    final replacement = _FakeMediaKitPlayer()
      ..openFailure = StateError('native-private-error-cookie-token');
    final engine = MediaKitForegroundAudioEngine(
      player: first,
      playerFactory: () => replacement,
      controlTimeout: const Duration(milliseconds: 20),
      openTimeout: const Duration(milliseconds: 20),
    );
    final uri = Uri.parse(
      'https://audio.example.test/private-track?vkey=signed-secret',
    );
    await expectLater(
      engine.loadRemote(uri),
      throwsA(isA<ForegroundAudioException>()),
    );
    await expectLater(
      engine.loadRemote(uri),
      throwsA(isA<ForegroundAudioException>()),
    );
    await engine.dispose();
    final trace = messages.join('\n');
    expect(trace, contains('phase=open elapsedMs=0 outcome=started'));
    expect(trace, contains('engine_stall generation=0 cycle=1'));
    expect(
      trace,
      contains('engine_rebuild generation=1 rebuildCount=1 outcome=success'),
    );
    expect(trace, contains('outcome=failure'));
    for (final secret in [
      'https:',
      'audio.example.test',
      'private-track',
      'signed-secret',
      'native-private-error',
      'cookie',
      'token',
    ]) {
      expect(trace, isNot(contains(secret)));
    }
  });

  test(
    'EOF replay retains source and focus; terminal completion releases it',
    () async {
      final player = _FakeMediaKitPlayer();
      final focus = _FakeFocusManager();
      var rebuilds = 0;
      final engine = MediaKitForegroundAudioEngine(
        player: player,
        playerFactory: () {
          rebuilds++;
          return _FakeMediaKitPlayer();
        },
        audioFocusManager: focus,
      );
      final session = await engine.loadRemote(
        Uri.parse('https://audio.example.test/repeat.mp3'),
      );
      await session.play();
      for (var cycle = 0; cycle < 100; cycle++) {
        player.emitCompleted();
        await Future<void>.delayed(Duration.zero);
        await session.seekToMs(0);
        await session.play();
      }
      expect(player.opened, hasLength(1));
      expect(player.stopCalls, 0);
      expect(player.disposeCalls, 0);
      expect(player.seekPositions, List.filled(100, Duration.zero));
      expect(player.playCalls, 101);
      expect(rebuilds, 0);
      expect(focus.values, [true]);
      await (session as ForegroundCompletionFocusSession)
          .releaseCompletionFocus();
      expect(focus.values, [true, false]);
      await session.dispose();
      await engine.dispose();
    },
  );

  test(
    'stalled native operation is bounded and concurrent recovery retires once',
    () async {
      final pending = Completer<void>();
      final first = _FakeMediaKitPlayer()..openGate = pending.future;
      final replacement = _FakeMediaKitPlayer();
      var factories = 0;
      final engine = MediaKitForegroundAudioEngine(
        player: first,
        playerFactory: () {
          factories++;
          return replacement;
        },
        audioFocusManager: _FakeFocusManager(),
        openTimeout: const Duration(milliseconds: 20),
        controlTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        engine.loadRemote(Uri.parse('https://audio.example.test/stall.mp3')),
        throwsA(isA<ForegroundAudioException>()),
      );
      final sessions = await Future.wait([
        engine.loadRemote(
          Uri.parse('https://audio.example.test/recovery-one.mp3'),
        ),
        engine.loadRemote(
          Uri.parse('https://audio.example.test/recovery-two.mp3'),
        ),
      ]);
      expect(first.disposeCalls, 1);
      expect(factories, 1);
      expect(engine.debugPlayer, same(replacement));
      // A late completion of the abandoned native Future cannot install a new
      // session or move the operation tail back onto the retired Player.
      pending.complete();
      for (final session in sessions) {
        await session.dispose();
      }
      await engine.dispose();
      expect(first.disposeCalls, 1);
      expect(replacement.disposeCalls, 1);
    },
  );

  test(
    'duplicate EOF and trailing paused events produce one completion per cycle',
    () async {
      final player = _FakeMediaKitPlayer();
      final focus = _FakeFocusManager();
      final engine = MediaKitForegroundAudioEngine(
        player: player,
        audioFocusManager: focus,
      );
      final session = await engine.loadRemote(
        Uri.parse('https://audio.example.test/repeat.mp3'),
      );
      final states = <ForegroundAudioState>[];
      final subscription = session.states.listen(states.add);
      await session.play();
      for (var cycle = 0; cycle < 100; cycle++) {
        // The SDK publishes playing=false before completed=true at EOF.
        player.emitPlaying(false);
        player.emitCompleted();
        await Future<void>.delayed(Duration.zero);
        player.emitCompleted();
        player.emitPlaying(false);
        await Future<void>.delayed(Duration.zero);
        expect(
          states.where((state) => state == ForegroundAudioState.completed),
          hasLength(cycle + 1),
        );
        expect(states.last, ForegroundAudioState.completed);
        await session.seekToMs(0);
        player.emitCompleted(false);
        await session.play();
        player.emitPlaying(true);
        await Future<void>.delayed(Duration.zero);
        expect(states.last, ForegroundAudioState.playing);
      }
      expect(player.opened, hasLength(1));
      expect(player.seekPositions, List.filled(100, Duration.zero));
      expect(player.playCalls, 101);
      expect(player.stopCalls, 0);
      expect(focus.values, [true]);
      await subscription.cancel();
      await session.dispose();
      await engine.dispose();
    },
  );

  for (final phase in ['seek', 'play']) {
    test(
      '$phase stall during EOF replay is bounded and explicit load recovers once',
      () async {
        final pending = Completer<void>();
        final first = _FakeMediaKitPlayer();
        final replacement = _FakeMediaKitPlayer();
        final focus = _FakeFocusManager();
        var factories = 0;
        final engine = MediaKitForegroundAudioEngine(
          player: first,
          playerFactory: () {
            factories++;
            return replacement;
          },
          audioFocusManager: focus,
          controlTimeout: const Duration(milliseconds: 20),
        );
        final session = await engine.loadRemote(
          Uri.parse('https://audio.example.test/stall.mp3'),
        );
        await session.play();
        first.emitCompleted();
        await Future<void>.delayed(Duration.zero);
        if (phase == 'seek') {
          first.seekGate = pending.future;
        } else {
          await session.seekToMs(0);
          first.playGate = pending.future;
        }
        await expectLater(
          phase == 'seek' ? session.seekToMs(0) : session.play(),
          throwsA(isA<ForegroundAudioException>()),
        );
        // The controller's error cleanup calls stop; it must not hang behind
        // a failed native control, and it releases the retained EOF focus.
        await expectLater(
          session.stop(),
          throwsA(isA<ForegroundAudioException>()),
        );
        expect(focus.values, [true, false]);
        await session.dispose();
        expect(factories, 0, reason: 'no automatic replay/source recovery');
        final recovered = await engine.loadRemote(
          Uri.parse('https://audio.example.test/recovered.mp3'),
        );
        await recovered.play();
        expect(first.disposeCalls, 1);
        expect(factories, 1);
        pending.complete();
        await recovered.pause();
        await recovered.play();
        expect(replacement.playCalls, 2);
        await recovered.dispose();
        await engine.dispose();
      },
    );
  }

  test('failed retirement never overlaps a replacement Player', () async {
    final first = _FakeMediaKitPlayer()
      ..openGate = Completer<void>().future
      ..disposeGate = Completer<void>().future;
    var factories = 0;
    final engine = MediaKitForegroundAudioEngine(
      player: first,
      playerFactory: () {
        factories++;
        return _FakeMediaKitPlayer();
      },
      openTimeout: const Duration(milliseconds: 20),
      controlTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      engine.loadRemote(Uri.parse('https://audio.example.test/stall.mp3')),
      throwsA(isA<ForegroundAudioException>()),
    );
    await expectLater(
      engine.loadRemote(Uri.parse('https://audio.example.test/retry.mp3')),
      throwsA(isA<ForegroundAudioException>()),
    );
    expect(factories, 0);
    await engine.dispose();
    expect(first.disposeCalls, 1);
  });

  test('control stall releases focus and cannot rebuild without a budget', () async {
    final pause = Completer<void>();
    final first = _FakeMediaKitPlayer()..pauseGate = pause.future;
    final replacement = _FakeMediaKitPlayer();
    final focus = _FakeFocusManager();
    var factories = 0;
    final engine = MediaKitForegroundAudioEngine(
      player: first,
      playerFactory: () {
        factories++;
        return replacement;
      },
      audioFocusManager: focus,
      openTimeout: const Duration(milliseconds: 20),
      controlTimeout: const Duration(milliseconds: 20),
    );
    final session = await engine.loadRemote(
      Uri.parse('https://audio.example.test/control.mp3'),
    );
    await session.play();
    await expectLater(
      session.pause(),
      throwsA(isA<ForegroundAudioException>()),
    );
    expect(focus.values, [true, false]);
    // Queued controls finish with a coarse error instead of waiting forever
    // behind the native pause. Only an explicit load retires the failed Player.
    await expectLater(
      session.seekToMs(0),
      throwsA(isA<ForegroundAudioException>()),
    );
    await session.dispose();
    final recovered = await engine.loadRemote(
      Uri.parse('https://audio.example.test/recovered.mp3'),
    );
    expect(factories, 1);
    expect(first.disposeCalls, 1);
    pause.complete();
    replacement.pauseGate = Completer<void>().future;
    await recovered.play();
    await expectLater(
      recovered.pause(),
      throwsA(isA<ForegroundAudioException>()),
    );
    await expectLater(
      engine.loadRemote(Uri.parse('https://audio.example.test/no-third.mp3')),
      throwsA(isA<ForegroundAudioException>()),
    );
    expect(factories, 1);
    await recovered.dispose();
    await engine.dispose();
  });

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
  Future<void>? openGate;
  Future<void>? pauseGate;
  Future<void>? seekGate;
  Future<void>? playGate;
  Future<void>? disposeGate;
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
    await openGate;
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    await playGate;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    await pauseGate;
  }

  @override
  Future<void> stop() async => stopCalls += 1;

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
    await seekGate;
  }

  @override
  Future<void> setVolume(double percent) async => volumes.add(percent);

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await disposeGate;
    await _playing.close();
    await _completed.close();
    await _position.close();
    await _errors.close();
  }

  void emitPlaying(bool value) => _playing.add(value);

  void emitCompleted([bool value = true]) => _completed.add(value);

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
