import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/media_kit_foreground_audio_engine.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/playback_stack_experiment.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;

import 'playback_engine_test.dart' show syntheticSilentMp3Fixture;

/// Android machine evidence only. Playback media resolution is synthetic and
/// lyrics are suppressed: one deterministic URI, no Provider/account I/O.
/// Queue, typed Bridge, retained-source controllers, mpv, focus and D system
/// edge are real. No test commands/fixtures are wired into the shipping app.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  unawaited(
    binding.allTestsPassed.future.then((passed) {
      debugPrint(
        'FURA_DIAGNOSTIC synthetic_suite '
        'outcome=${passed ? 'success' : 'failed'}',
      );
    }),
  );
  MediaKit.ensureInitialized();

  for (final mediaKit in [true, false]) {
    testWidgets(
      'Android pending pause/resume (${mediaKit ? 'mediaKit' : 'audioplayers'})',
      (tester) async {
        final directory = await Directory.systemTemp.createTemp('fura-pause-');
        final file = File('${directory.path}/synthetic.mp3');
        await file.writeAsBytes(_lifecycleFixture(), flush: true);
        final focus = _DelayedReleaseFocus()..acknowledge.complete();
        final acknowledged = Completer<void>();
        final paused = Completer<void>();
        _CountedNativePlayer? mpv;
        _PausedAcknowledgementAudioplayers? audio;
        var nativeErrors = 0;
        late final StreamSubscription<Object?> errors;
        final ForegroundAudioEngine engine;
        if (mediaKit) {
          mpv = _CountedNativePlayer(
            localSource: Uri.file(file.path),
            pauseAcknowledgement: acknowledged.future,
            pauseEntered: paused,
          );
          engine = MediaKitForegroundAudioEngine(
            player: mpv,
            audioFocusManager: focus,
          );
          errors = mpv.errors.listen((_) => nativeErrors++);
        } else {
          audio = _PausedAcknowledgementAudioplayers(
            file.path,
            acknowledged.future,
            paused,
          );
          engine = AudioplayersForegroundAudioEngine(
            playerFactory: () => audio!,
            audioFocusManager: focus,
          );
          errors = audio.events.listen(
            (_) {},
            onError: (Object _) => nativeErrors++,
          );
        }
        ForegroundAudioSession? session;
        try {
          await tester.runAsync(() async {
            session = await engine.loadRemote(
              Uri.parse('https://synthetic.invalid/source.mp3'),
            );
            await session!.setVolume(0);
            await session!.play();
            final pausing = session!.pause();
            await paused.future.timeout(const Duration(seconds: 5));
            var resumed = false;
            final resuming = session!.play().then((_) => resumed = true);
            await Future<void>.delayed(Duration.zero);
            expect(resumed, isFalse);
            expect(mpv?.plays ?? audio!.plays, 1);
            expect(focus.activations, 1);
            expect(focus.releases, 0);
            acknowledged.complete();
            await pausing;
            await resuming;
            expect(mpv?.plays ?? audio!.plays, 2);
            expect(focus.activations, 2);
            expect(focus.releases, 1);
            expect(
              await session!.positionMs
                  .firstWhere((value) => value > 0)
                  .timeout(const Duration(seconds: 5)),
              greaterThan(0),
            );
            expect(nativeErrors, 0);
            debugPrint(
              'FURA_DIAGNOSTIC synthetic_pause_handoff '
              'engine=${mediaKit ? 'mediaKit' : 'audioplayers'} '
              'outcome=success plays=2 activations=2 releases=1 nativeErrors=0',
            );
          });
        } finally {
          if (!acknowledged.isCompleted) acknowledged.complete();
          await session?.dispose();
          await engine.dispose();
          await errors.cancel();
          await file.delete();
          await directory.delete();
        }
      },
      skip: !Platform.isAndroid,
    );
  }

  testWidgets('Android D Rust Queue replay and lifecycle machine gate', (
    tester,
  ) async {
    debugPrint('FURA_DIAGNOSTIC synthetic_case phase=repeat_started');
    await RustLib.init();
    final selection = PlaybackStackSelection.current();
    expect(selection.effectiveAudioEngine, MusicAudioEngineKind.mediaKit);
    expect(
      selection.effectiveSystemMediaEdge,
      SystemMediaEdgeKind.flutterMediaSession,
    );
    final queue = RustPlaybackQueueGateway();
    expect(queue.clear().failure, isNull);
    var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixturePort = server.port;
    final bytes = _lifecycleFixture();
    var httpRequests = 0;
    var requests = server.listen((request) {
      httpRequests++;
      unawaited(_serve(request, bytes));
    });
    final resolver = _SyntheticResolution(
      Uri.parse('http://127.0.0.1:${server.port}/synthetic.mp3'),
    );
    var playerCreations = 1;
    final player = _CountedNativePlayer();
    final engine = MediaKitForegroundAudioEngine(
      player: player,
      playerFactory: () {
        playerCreations++;
        return _CountedNativePlayer();
      },
    );
    final nativeErrors = <String, int>{};
    final errorSubscription = player.errors.listen((_) {
      // Raw native messages can contain URLs: never store or print them.
      nativeErrors.update(
        'native_error',
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    });
    var completions = 0;
    var pausedEvents = 0;
    var resumedEvents = 0;
    final lifecycle = AppLifecycleListener(
      onPause: () {
        pausedEvents++;
        debugPrint(
          'FURA_DIAGNOSTIC synthetic_lifecycle phase=paused '
          'count=$pausedEvents',
        );
      },
      onResume: () {
        resumedEvents++;
        debugPrint(
          'FURA_DIAGNOSTIC synthetic_lifecycle phase=resumed '
          'count=$resumedEvents',
        );
      },
    );
    final terminal = Completer<void>();
    final completionSubscription = player.completed.listen((completed) {
      if (!completed) return;
      completions++;
      if ([1, 11, 31, 101].contains(completions)) {
        debugPrint(
          'FURA_DIAGNOSTIC synthetic_checkpoint '
          'replays=${completions - 1}',
        );
      }
      // End the finite soak through the authoritative Rust Queue, before the
      // session publishes the terminal event. Earlier EOFs remain repeat-one.
      if (completions == 101) {
        expect(queue.setRepeatMode(PlaybackRepeatMode.off).failure, isNull);
        terminal.complete();
      }
    });
    AppPlaybackHost? host;
    var serverClosed = false;
    try {
      host = await initializeAppPlaybackHost(
        playbackQueueGateway: queue,
        mediaResolutionGateway: resolver,
        lyricGateway: const _NoLyrics(),
        audioEngine: engine,
        systemMediaEdge: selection.effectiveSystemMediaEdge,
      );
      expect(host, isA<FlutterMediaSessionAppPlaybackHost>());
      expect(host.systemControlsAvailable, isTrue);
      final controller = host.controller;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Synthetic Android replay gate')),
          ),
        ),
      );
      await tester.pump();
      // Real-time async work must continue even while Android pauses frames.
      await tester.runAsync(() async {
        await controller.playback.setVolume(0);
        await controller.setRepeatMode(PlaybackRepeatMode.one);
        await controller.replaceAndPlay(const [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'synthetic-android-replay',
            title: 'Synthetic fixture',
            artistNames: [],
            durationSeconds: 3,
          ),
        ], 0);
        debugPrint(
          'FURA_DIAGNOSTIC synthetic_ready '
          'requested=D effective=D systemControls=true',
        );
        // Wait for actual EOFs; neither timers nor seek manufacture completion.
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (completions < 31) {
          _assertHealthy(controller, nativeErrors);
          if (DateTime.now().isAfter(deadline)) {
            fail('bounded Android EOF deadline');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        final cachedRequestCount = httpRequests;
        expect(cachedRequestCount, greaterThan(0));
        // Fixture-only network outage. No host/Android global network setting
        // changes. If replay attempts another HTTP fetch it cannot succeed.
        await requests.cancel();
        await server.close(force: true);
        serverClosed = true;
        debugPrint(
          'FURA_DIAGNOSTIC synthetic_network phase=fixture_offline '
          'replays=${completions - 1}',
        );
        while (completions < 51) {
          _assertHealthy(controller, nativeErrors);
          if (DateTime.now().isAfter(deadline)) {
            fail('bounded cached-offline EOF deadline');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          fixturePort,
        );
        requests = server.listen((request) {
          httpRequests++;
          unawaited(_serve(request, bytes));
        });
        serverClosed = false;
        debugPrint(
          'FURA_DIAGNOSTIC synthetic_network phase=fixture_restored '
          'replays=${completions - 1}',
        );
        await terminal.future.timeout(const Duration(minutes: 3));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        _assertHealthy(controller, nativeErrors);
        expect(completions, 101);
        expect(resolver.count, 1);
        expect(player.opens, 1);
        expect(player.seeks, 100);
        expect(player.plays, 101);
        expect(player.stops, 0);
        expect(playerCreations, 1);
        expect(httpRequests, cachedRequestCount);
        expect(pausedEvents, greaterThanOrEqualTo(21));
        expect(resumedEvents, greaterThanOrEqualTo(21));
        expect(controller.tracks.length, 1);
        expect(controller.current?.opaqueId, 'synthetic-android-replay');
        debugPrint(
          'FURA_DIAGNOSTIC synthetic_result outcome=success '
          'resolve=${resolver.count} open=${player.opens} '
          'seek=${player.seeks} play=${player.plays} stop=${player.stops} '
          'replays=100 nativeErrors=${nativeErrors.length} '
          'rebuild=${playerCreations - 1} paused=$pausedEvents '
          'resumed=$resumedEvents extraHttpRequests=0',
        );
      });
    } finally {
      lifecycle.dispose();
      await errorSubscription.cancel();
      await completionSubscription.cancel();
      await host?.controller.stop();
      await host?.dispose();
      await engine.dispose();
      if (!serverClosed) {
        await requests.cancel();
        await server.close(force: true);
      }
      queue.clear();
    }
  }, skip: !Platform.isAndroid);

  testWidgets('Android control stall has observable bounded recovery', (
    tester,
  ) async {
    debugPrint('FURA_DIAGNOSTIC synthetic_case phase=injected_stall_started');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bytes = syntheticSilentMp3Fixture();
    final requests = server.listen(
      (request) => unawaited(_serve(request, bytes)),
    );
    final stalledPlayer = _CountedNativePlayer(hangSeek: true);
    var factories = 0;
    final engine = MediaKitForegroundAudioEngine(
      player: stalledPlayer,
      playerFactory: () {
        factories++;
        return _CountedNativePlayer();
      },
      controlTimeout: const Duration(seconds: 1),
    );
    ForegroundAudioSession? failed;
    ForegroundAudioSession? recovered;
    try {
      await tester.runAsync(() async {
        final uri = Uri.parse('http://127.0.0.1:${server.port}/synthetic.mp3');
        failed = await engine.loadRemote(uri);
        await failed!.setVolume(0);
        await failed!.play();
        await expectLater(
          failed!.seekToMs(0),
          throwsA(isA<ForegroundAudioException>()),
        );
        // The pending seam Future must not poison the operation tail forever.
        await expectLater(
          failed!.play().timeout(const Duration(seconds: 2)),
          throwsA(isA<ForegroundAudioException>()),
        );
        await failed!.dispose();
        recovered = await engine.loadRemote(uri);
        expect(factories, 1);
        await recovered!.setVolume(0);
        final progress = recovered!.positionMs.firstWhere((value) => value > 0);
        await recovered!.play();
        expect(
          await progress.timeout(const Duration(seconds: 5)),
          greaterThan(0),
        );
        debugPrint(
          'FURA_DIAGNOSTIC synthetic_stall outcome=success '
          'injectedPhase=seek recoveryCount=1',
        );
      });
    } finally {
      await failed?.dispose();
      await recovered?.dispose();
      await engine.dispose();
      await requests.cancel();
      await server.close(force: true);
    }
  }, skip: !Platform.isAndroid);

  testWidgets(
    'Android delayed focus acknowledgement cannot release a newer lease',
    (tester) async {
      debugPrint('FURA_DIAGNOSTIC synthetic_case phase=focus_delay_started');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = _lifecycleFixture();
      final requests = server.listen(
        (request) => unawaited(_serve(request, bytes)),
      );
      final focus = _DelayedReleaseFocus();
      final player = _CountedNativePlayer();
      final engine = MediaKitForegroundAudioEngine(
        player: player,
        audioFocusManager: focus,
        focusTimeout: const Duration(milliseconds: 250),
      );
      var nativeErrors = 0;
      final errors = player.errors.listen((_) => nativeErrors++);
      ForegroundAudioSession? old;
      ForegroundAudioSession? next;
      try {
        await tester.runAsync(() async {
          final uri = Uri.parse(
            'http://127.0.0.1:${server.port}/synthetic.mp3',
          );
          old = await engine.loadRemote(uri);
          await old!.setVolume(0);
          await old!.play();
          final watch = Stopwatch()..start();
          await expectLater(
            old!.pause().timeout(const Duration(seconds: 3)),
            throwsA(isA<ForegroundAudioException>()),
          );
          watch.stop();
          expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
          expect(focus.releases, 1);
          next = await engine.loadRemote(uri);
          await expectLater(
            next!.play(),
            throwsA(isA<ForegroundAudioException>()),
          );
          expect(focus.activations, 1);
          // The delay is in a test seam after real audio_session abandonment,
          // not a claim that Android reproduced the historic 40-second delay.
          focus.acknowledge.complete();
          await Future<void>.delayed(Duration.zero);
          final progress = next!.positionMs.firstWhere((value) => value > 0);
          await next!.setVolume(0);
          await next!.play();
          expect(
            await progress.timeout(const Duration(seconds: 5)),
            greaterThan(0),
          );
          await old!.dispose();
          expect(focus.activations, 2);
          expect(
            focus.releases,
            1,
            reason: 'stale lease must not abandon newer focus',
          );
          final playsBeforeRace = player.plays;
          final playing = next!.play();
          final releasing = (next! as ForegroundCompletionFocusSession)
              .releaseCompletionFocus();
          await expectLater(playing, throwsA(isA<ForegroundAudioException>()));
          await releasing;
          expect(
            player.plays,
            playsBeforeRace,
            reason: 'revoked result must not submit native play',
          );
          expect(nativeErrors, 0);
          debugPrint(
            'FURA_DIAGNOSTIC synthetic_focus outcome=success activations=2 staleRelease=0 revisionRaceRejected=1 callerElapsedMs=${watch.elapsedMilliseconds}',
          );
        });
      } finally {
        if (!focus.acknowledge.isCompleted) focus.acknowledge.complete();
        await old?.dispose();
        await next?.dispose();
        await engine.dispose();
        await errors.cancel();
        await requests.cancel();
        await server.close(force: true);
      }
    },
    skip: !Platform.isAndroid,
  );

  testWidgets('Android audioplayers rollback shares the bounded focus policy', (
    tester,
  ) async {
    debugPrint('FURA_DIAGNOSTIC synthetic_case phase=rollback_focus_started');
    // Android MediaPlayer honors the app's cleartext prohibition. Do not relax
    // TLS policy to reuse mpv's test-only loopback HTTP fixture. Supply the same
    // synthetic bytes through a local-file test seam, not a production resolver.
    final directory = await Directory.systemTemp.createTemp('fura-focus-');
    final file = File('${directory.path}/synthetic.mp3');
    await file.writeAsBytes(_lifecycleFixture(), flush: true);
    final focus = _DelayedReleaseFocus();
    final engine = AudioplayersForegroundAudioEngine(
      audioFocusManager: focus,
      playerFactory: () => _LocalFixtureAudioplayers(file.path),
      focusTimeout: const Duration(milliseconds: 250),
    );
    ForegroundAudioSession? session;
    try {
      await tester.runAsync(() async {
        session = await engine.loadRemote(
          Uri.parse('https://synthetic.invalid/source.mp3'),
        );
        await session!.setVolume(0);
        await session!.play();
        await expectLater(
          session!.pause().timeout(const Duration(seconds: 3)),
          throwsA(isA<ForegroundAudioException>()),
        );
        await expectLater(
          session!.play(),
          throwsA(isA<ForegroundAudioException>()),
        );
        expect(focus.activations, 1);
        focus.acknowledge.complete();
        await Future<void>.delayed(Duration.zero);
        final progress = session!.positionMs.firstWhere((value) => value > 0);
        await session!.play();
        expect(
          await progress.timeout(const Duration(seconds: 5)),
          greaterThan(0),
        );
        await session!.dispose();
        expect(focus.activations, 2);
        expect(focus.releases, 2);
        debugPrint(
          'FURA_DIAGNOSTIC synthetic_rollback_focus outcome=success activations=2 releases=2',
        );
      });
    } finally {
      if (!focus.acknowledge.isCompleted) focus.acknowledge.complete();
      await session?.dispose();
      await engine.dispose();
      await file.delete();
      await directory.delete();
    }
  }, skip: !Platform.isAndroid);

  testWidgets('Android incomplete source survives bounded transfer outage', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bytes = _lifecycleFixture(audioRepetitions: 256);
    final restore = Completer<void>();
    final transferFinished = Completer<void>();
    const initialBytes = 65536;
    var deliveredBytes = 0;
    final requests = server.listen((request) async {
      try {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.contentLength = bytes.length;
        // Supply enough real MPEG frames for demux/probe before the outage.
        // This is still only the first ~33 seconds of a ~166-second source.
        request.response.add(bytes.take(initialBytes).toList());
        await request.response.flush();
        deliveredBytes = initialBytes;
        await restore.future;
        request.response.add(bytes.skip(initialBytes).toList());
        await request.response.close();
        deliveredBytes = bytes.length;
        if (!transferFinished.isCompleted) transferFinished.complete();
      } on SocketException {
        // Test teardown can close an outstanding synthetic response.
      }
    });
    final player = _CountedNativePlayer();
    final engine = MediaKitForegroundAudioEngine(player: player);
    var nativeErrors = 0;
    final errors = player.errors.listen((_) => nativeErrors++);
    ForegroundAudioSession? session;
    try {
      await tester.runAsync(() async {
        session = await engine.loadRemote(
          Uri.parse('http://127.0.0.1:${server.port}/synthetic.mp3'),
        );
        await session!.setVolume(0);
        final initialProgress = session!.positionMs.firstWhere((ms) => ms > 0);
        await session!.play();
        final before = await initialProgress.timeout(
          const Duration(seconds: 5),
        );
        expect(deliveredBytes, lessThan(bytes.length));
        debugPrint(
          'FURA_DIAGNOSTIC synthetic_network phase=incomplete_transfer_outage '
          'fullyCached=false',
        );
        // Only withhold this app-owned fixture response, never host networking.
        await Future<void>.delayed(const Duration(seconds: 3));
        final resumedProgress = session!.positionMs.firstWhere(
          (ms) => ms > before + 500,
        );
        restore.complete();
        final after = await resumedProgress.timeout(const Duration(seconds: 8));
        await transferFinished.future.timeout(const Duration(seconds: 8));
        expect(deliveredBytes, bytes.length);
        // Prove the restored portion is consumable, not just position advance
        // inside the prefix that had already arrived before the outage.
        final restoredTail = session!.positionMs.firstWhere((ms) => ms > 60000);
        await session!.seekToMs(60000);
        await restoredTail.timeout(const Duration(seconds: 5));
        expect(nativeErrors, 0);
        expect(player.opens, 1);
        expect(player.plays, 1);
        expect(player.stops, 0);
        debugPrint(
          'FURA_DIAGNOSTIC synthetic_network phase=incomplete_transfer_restored '
          'outcome=success open=1 play=1 nativeErrors=0 '
          'positionBeforeMs=$before positionAfterMs=$after',
        );
      });
    } finally {
      if (!restore.isCompleted) restore.complete();
      await session?.dispose();
      await engine.dispose();
      await errors.cancel();
      await requests.cancel();
      await server.close(force: true);
    }
  }, skip: !Platform.isAndroid);
}

List<int> _lifecycleFixture({int audioRepetitions = 4}) {
  final short = syntheticSilentMp3Fixture();
  // This pinned fixture has one ID3v2.4 header and no Xing/end tag. Reuse its
  // complete silent MPEG frames, not a Player playlist/loop or artificial EOF.
  // A longer real source gives host-driven Activity transitions enough time.
  expect(short.take(3), [0x49, 0x44, 0x33]);
  final headerEnd =
      10 + (short[6] << 21) + (short[7] << 14) + (short[8] << 7) + short[9];
  expect(short[headerEnd], 0xff);
  return [
    ...short.take(headerEnd),
    for (var repeat = 0; repeat < audioRepetitions; repeat++)
      ...short.skip(headerEnd),
  ];
}

void _assertHealthy(
  QueuePlaybackController controller,
  Map<String, int> errors,
) {
  expect(controller.failure, isNull, reason: 'Rust Queue must remain healthy');
  expect(errors, isEmpty, reason: 'native errors are not acceptable EOF proof');
  expect(
    controller.playback.stage,
    isNot(
      anyOf(TrackPlaybackStage.engineError, TrackPlaybackStage.resolutionError),
    ),
  );
}

class _LocalFixtureAudioplayers extends PlatformAudioplayersAudioPlayer {
  _LocalFixtureAudioplayers(this._path);
  final String _path;
  @override
  Future<void> setSourceUrl(String source, {required String mimeType}) =>
      super.setSourceUrl(_path, mimeType: mimeType);
}

class _PausedAcknowledgementAudioplayers extends _LocalFixtureAudioplayers {
  _PausedAcknowledgementAudioplayers(
    super.path,
    this.acknowledgement,
    this.entered,
  );
  final Future<void> acknowledgement;
  final Completer<void> entered;
  int plays = 0;
  @override
  Future<void> resume() {
    plays++;
    return super.resume();
  }

  @override
  Future<void> pause() async {
    await super.pause();
    entered.complete();
    await acknowledgement;
  }
}

class _DelayedReleaseFocus implements ForegroundAudioFocusManager {
  final _platform = const AudioSessionForegroundAudioFocusManager();
  final acknowledge = Completer<void>();
  int activations = 0;
  int releases = 0;
  @override
  Future<bool> setActive(bool active) async {
    if (active) {
      activations++;
    } else {
      releases++;
    }
    final result = await _platform.setActive(active);
    if (!active && releases == 1) await acknowledge.future;
    return result;
  }
}

class _CountedNativePlayer implements MediaKitAudioPlayer {
  _CountedNativePlayer({
    this.hangSeek = false,
    this.localSource,
    this.pauseAcknowledgement,
    this.pauseEntered,
  });
  final bool hangSeek;
  final Uri? localSource;
  final Future<void>? pauseAcknowledgement;
  final Completer<void>? pauseEntered;
  final _native = PlatformMediaKitAudioPlayer();
  int opens = 0;
  int seeks = 0;
  int plays = 0;
  int stops = 0;
  @override
  Stream<bool> get playing => _native.playing;
  @override
  Stream<bool> get completed => _native.completed;
  @override
  Stream<Duration> get position => _native.position;
  @override
  Stream<String> get errors => _native.errors;
  @override
  Future<void> open(Uri source) {
    opens++;
    return _native.open(localSource ?? source);
  }

  @override
  Future<void> seek(Duration position) {
    seeks++;
    if (hangSeek) return Completer<void>().future;
    return _native.seek(position);
  }

  @override
  Future<void> play() {
    plays++;
    return _native.play();
  }

  @override
  Future<void> pause() async {
    await _native.pause();
    pauseEntered?.complete();
    await pauseAcknowledgement;
  }

  @override
  Future<void> stop() {
    stops++;
    return _native.stop();
  }

  @override
  Future<void> setVolume(double percent) => _native.setVolume(percent);
  @override
  Future<void> dispose() => _native.dispose();
}

class _SyntheticResolution implements MediaResolutionGateway {
  _SyntheticResolution(this.uri);
  final Uri uri;
  int count = 0;
  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) {
    count++;
    return _SyntheticOperation(uri);
  }
}

class _SyntheticOperation implements MediaResolutionOperation {
  _SyntheticOperation(this.uri);
  final Uri uri;
  @override
  bool cancel() => false;
  @override
  Future<MediaResolutionResult> run() async => MediaResolutionResult(
    source: ResolvedPlaybackSource(
      uri: uri,
      format: PlaybackAudioFormat.mp3,
      quality: PlaybackAudioQuality.standard,
      validForSeconds: 600,
    ),
  );
}

class _NoLyrics implements LyricGateway {
  const _NoLyrics();
  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) => _NoLyricOperation();
}

class _NoLyricOperation implements LyricLoadOperation {
  @override
  bool cancel() => false;
  @override
  Future<LyricLoadResult> run() async =>
      const LyricLoadResult(failure: LyricFailure.unavailable);
}

Future<void> _serve(HttpRequest request, List<int> bytes) async {
  final response = request.response;
  response.headers.contentType = ContentType('audio', 'mpeg');
  response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  final match = RegExp(r'^bytes=(\d+)-(\d*)$')
      .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
  final start = match == null ? 0 : int.parse(match.group(1)!);
  final end = match == null || match.group(2)!.isEmpty
      ? bytes.length - 1
      : int.parse(match.group(2)!).clamp(0, bytes.length - 1);
  if (start < 0 || start > end) {
    response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
  } else {
    if (match != null) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${bytes.length}',
      );
    }
    response.contentLength = end - start + 1;
    response.add(bytes.sublist(start, end + 1));
  }
  await response.close();
}
