import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_kit_foreground_audio_engine.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/linux_mpris_player.dart';
import 'package:flutterustmusic/playback/playback_stack_experiment.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;

import 'playback_engine_test.dart' show syntheticSilentMp3Fixture;

/// Ordinary GTK/mpv + real Rust Queue, only generated/local synthetic media.
/// Never starts MusicApp or opens credentials/accounts. This first gate has
/// no system-media adapter, so it cannot credit MPRIS for native error repair.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  setUpAll(() async {
    if (Platform.isLinux) await RustLib.init();
  });
  testWidgets('Linux native ownership and retained Rust Queue replay', (
    tester,
  ) async {
    final gateway = RustPlaybackQueueGateway();
    expect(gateway.clear().failure, isNull);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bytes = syntheticSilentMp3Fixture();
    var httpRequests = 0;
    final requests = server.listen((request) async {
      httpRequests++;
      final data = request.uri.path == '/invalid' ? [0, 1, 2, 3] : bytes;
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      final range = RegExp(r'^bytes=(\d+)-(\d*)$')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      final start = range == null ? 0 : int.parse(range.group(1)!);
      if (start >= data.length) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      } else {
        if (range != null) {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${data.length - 1}/${data.length}',
          );
        }
        request.response.contentLength = data.length - start;
        request.response.add(data.sublist(start));
      }
      await request.response.close();
    });
    final player = _CountedPlayer();
    debugPrint(
      'FURA_DIAGNOSTIC linux_native_runtime version=${await player.native.debugNativePlayer.getProperty('mpv-version')}',
    );
    final focus = _CountedFocus();
    final engine = MediaKitForegroundAudioEngine(
      player: player,
      audioFocusManager: focus,
    );
    final resolver = _LocalResolver(
      Uri.parse('http://127.0.0.1:${server.port}/audio'),
    );
    final controller = QueuePlaybackController(
      gateway,
      TrackPlaybackController(resolver, ForegroundPlaybackController(engine)),
    );
    var eof = 0;
    var logs = 0;
    var fatal = 0;
    final subscriptions = <StreamSubscription<Object?>>[
      player.completed.listen((value) {
        if (value) eof++;
      }),
      player.errors.listen((_) => logs++),
      player.sourceFailures.listen((_) => fatal++),
    ];
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Synthetic Linux playback reliability')),
        ),
      );
      await controller.setRepeatMode(PlaybackRepeatMode.one);
      await controller.replaceAndPlay([_track('one')], 0);
      await _until(
        tester,
        () =>
            eof >= 31 &&
            controller.playback.stage == TrackPlaybackStage.playing,
      );
      expect(resolver.count, 1);
      expect(player.opens, 1);
      expect(player.stops, 0);
      expect(fatal, 0);
      // Each observed EOF has already started its retained replay when the
      // controller is playing again. The initial play precedes all EOFs.
      expect(eof, greaterThanOrEqualTo(31));
      expect(player.seeks, eof);
      expect(player.plays, eof + 1);
      expect(focus.values, [true]);
      final cachedRequests = httpRequests;
      await _until(
        tester,
        () =>
            eof >= 33 &&
            controller.playback.stage == TrackPlaybackStage.playing,
      );
      expect(httpRequests, cachedRequests);
      debugPrint(
        'FURA_DIAGNOSTIC linux_retained_gate resolve=${resolver.count} open=${player.opens} seek=${player.seeks} play=${player.plays} stop=${player.stops} nativeErrorEvent=$logs fatalError=$fatal focusActivate=1 focusRelease=0 rebuild=0',
      );
      await controller.playback.pause();
      expect(controller.playback.stage, TrackPlaybackStage.paused);
      await controller.playback.seekToMs(100);
      await controller.playCurrent();
      await controller.setRepeatMode(PlaybackRepeatMode.off);
      await controller.replaceAndPlay([_track('two'), _track('three')], 0);
      await _until(
        tester,
        () =>
            controller.current?.opaqueId == 'synthetic-three' &&
            controller.playback.stage == TrackPlaybackStage.playing,
      );
      expect(resolver.count, 3);
      expect(player.opens, 3);
      await controller.stop();
      expect(fatal, 0);
      expect(controller.playback.stage, TrackPlaybackStage.stopped);
      // A real native unexpected unload, bypassing the project's explicit stop.
      await controller.replaceAndPlay([_track('four')], 0);
      await player.native.debugNativePlayer.command(['stop']);
      await _until(
        tester,
        () => controller.playback.stage == TrackPlaybackStage.engineError,
      );
      expect(fatal, 1);
      expect(
        controller.playback.engineFailure,
        ForegroundAudioFailure.playback,
      );
      // Corrupt local bytes: SDK load Future may acknowledge before decoding.
      resolver.uri = Uri.parse('http://127.0.0.1:${server.port}/invalid');
      await controller.replaceAndPlay([_track('invalid')], 0);
      await _until(
        tester,
        () => controller.playback.stage == TrackPlaybackStage.engineError,
      );
      expect(fatal, 2);
      debugPrint(
        'FURA_DIAGNOSTIC linux_failure_gate resolve=${resolver.count} open=${player.opens} seek=${player.seeks} play=${player.plays} stop=${player.stops} nativeErrorEvent=$logs fatalError=$fatal focusActivate=${focus.values.where((v) => v).length} focusRelease=${focus.values.where((v) => !v).length} rebuild=0',
      );
    } finally {
      await controller.stop();
      controller.dispose();
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await requests.cancel();
      await server.close(force: true);
      gateway.clear();
    }
  }, skip: !Platform.isLinux);

  testWidgets(
    'Direct Fura MPRIS commands use real Rust Queue and native player',
    (tester) async {
      final gateway = RustPlaybackQueueGateway();
      expect(gateway.clear().failure, isNull);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final short = syntheticSilentMp3Fixture();
      final headerLength =
          10 + (short[6] << 21) + (short[7] << 14) + (short[8] << 7) + short[9];
      final bytes = [
        ...short.take(headerLength),
        for (var i = 0; i < 40; i++) ...short.skip(headerLength),
      ];
      final requests = server.listen((request) async {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      final player = _CountedPlayer();
      final focus = _CountedFocus();
      final resolver = _LocalResolver(
        Uri.parse('http://127.0.0.1:${server.port}/audio'),
      );
      final host = await initializeAppPlaybackHost(
        playbackQueueGateway: gateway,
        mediaResolutionGateway: resolver,
        lyricGateway: const _NoLyrics(),
        audioEngine: MediaKitForegroundAudioEngine(
          player: player,
          audioFocusManager: focus,
        ),
        systemMediaEdge: SystemMediaEdgeKind.furaMpris,
        audioServiceInitializer: (_, _) async =>
            fail('Linux must not initialize AudioService'),
      );
      final client = DBusClient.session();
      final name = projectMprisServiceName('com.fura.flutterustmusic.playback');
      final remote = DBusRemoteObject(
        client,
        name: name,
        path: DBusObjectPath(projectMprisObjectPath),
      );
      Future<DBusValue> property(String name) =>
          remote.getProperty(projectMprisPlayerInterface, name);
      Future<void> command(
        String name, [
        List<DBusValue> values = const [],
      ]) async {
        await remote.callMethod(
          projectMprisPlayerInterface,
          name,
          values,
          replySignature: DBusSignature(''),
        );
      }

      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Text('Synthetic direct MPRIS runtime')),
          ),
        );
        expect(host, isA<FuraMprisAppPlaybackHost>());
        expect(host.systemControlsAvailable, isTrue);
        expect(await client.nameHasOwner(name), isTrue);
        expect(
          (await remote.getProperty(
            'org.mpris.MediaPlayer2',
            'HasTrackList',
          )).asBoolean(),
          isFalse,
        );
        expect(
          (await remote.getProperty(
            'org.mpris.MediaPlayer2',
            'Identity',
          )).asString(),
          'fura music playback',
        );
        final controller = host.controller;
        void pageListener() {}
        controller.addListener(pageListener);
        await controller.replaceAndPlay([
          _track('mpris-one', duration: 40),
          _track('mpris-two', duration: 40),
        ], 0);
        controller.removeListener(pageListener);
        await _until(tester, () => controller.playback.positionMs > 100);
        expect((await property('PlaybackStatus')).asString(), 'Playing');
        final metadata = (await property('Metadata')).asStringVariantDict();
        expect(metadata['xesam:title']!.asString(), 'Synthetic');
        expect(metadata['xesam:artist']!.asStringArray(), ['Fixture']);
        expect(metadata['mpris:length']!.asInt64(), 40000000);
        final trackId = metadata['mpris:trackid']!.asObjectPath();
        final before = (await property('Position')).asInt64();
        await tester.pump(const Duration(milliseconds: 150));
        expect((await property('Position')).asInt64(), greaterThan(before));
        await command('Pause');
        await _until(
          tester,
          () => controller.playback.stage == TrackPlaybackStage.paused,
        );
        expect((await property('PlaybackStatus')).asString(), 'Paused');
        await command('Play');
        await _until(
          tester,
          () => controller.playback.stage == TrackPlaybackStage.playing,
        );
        expect(player.opens, 1);
        expect(resolver.count, 1);
        await command('Seek', [const DBusInt64(200000)]);
        await _until(tester, () => player.seeks == 1);
        await command('SetPosition', [
          DBusObjectPath('/stale'),
          const DBusInt64(300000),
        ]);
        await tester.pump(const Duration(milliseconds: 100));
        expect(player.seeks, 1);
        await command('SetPosition', [trackId, const DBusInt64(300000)]);
        await _until(tester, () => player.seeks == 2);
        await command('Next');
        await _until(
          tester,
          () =>
              controller.current?.opaqueId == 'synthetic-mpris-two' &&
              controller.playback.canPause,
        );
        await command('Previous');
        await _until(
          tester,
          () =>
              controller.current?.opaqueId == 'synthetic-mpris-one' &&
              controller.playback.canPause,
        );
        expect(resolver.count, 3);
        expect(player.opens, 3);
        await remote.setProperty(
          projectMprisPlayerInterface,
          'Shuffle',
          const DBusBoolean(true),
        );
        await remote.setProperty(
          projectMprisPlayerInterface,
          'LoopStatus',
          const DBusString('Track'),
        );
        await remote.setProperty(
          projectMprisPlayerInterface,
          'Volume',
          const DBusDouble(0.35),
        );
        await _until(
          tester,
          () =>
              controller.order == PlaybackOrder.shuffle &&
              controller.repeatMode == PlaybackRepeatMode.one &&
              controller.playback.volume == 0.35,
        );
        expect((await property('Volume')).asDouble(), 0.35);
        await controller.playback.setVolume(0.6);
        expect((await property('Volume')).asDouble(), 0.6);
        await remote.setProperty(
          projectMprisPlayerInterface,
          'LoopStatus',
          const DBusString('Playlist'),
        );
        await _until(
          tester,
          () => controller.repeatMode == PlaybackRepeatMode.all,
        );
        await remote.setProperty(
          projectMprisPlayerInterface,
          'LoopStatus',
          const DBusString('None'),
        );
        await _until(
          tester,
          () => controller.repeatMode == PlaybackRepeatMode.off,
        );
        await command('Stop');
        await _until(
          tester,
          () => controller.playback.stage == TrackPlaybackStage.stopped,
        );
        expect((await property('PlaybackStatus')).asString(), 'Stopped');
        await host.dispose();
        expect(await client.nameHasOwner(name), isFalse);
        // A new app-lifetime owner can reacquire the exact service name.
        final restarted = await initializeAppPlaybackHost(
          playbackQueueGateway: gateway,
          mediaResolutionGateway: resolver,
          lyricGateway: const _NoLyrics(),
          audioEngine: MediaKitForegroundAudioEngine(),
          systemMediaEdge: SystemMediaEdgeKind.furaMpris,
          audioServiceInitializer: (_, _) async =>
              fail('Restart AudioService init'),
        );
        try {
          expect(restarted.systemControlsAvailable, isTrue);
          expect(await client.nameHasOwner(name), isTrue);
          expect((await property('PlaybackStatus')).asString(), 'Stopped');
        } finally {
          await restarted.dispose();
        }
        expect(await client.nameHasOwner(name), isFalse);
        debugPrint(
          'FURA_DIAGNOSTIC direct_mpris_gate resolve=${resolver.count} open=${player.opens} seek=${player.seeks} play=${player.plays} stop=${player.stops} focusActivate=${focus.values.where((v) => v).length} focusRelease=${focus.values.where((v) => !v).length} ownership=direct commands=passed restart=passed',
        );
      } finally {
        await host.dispose();
        await client.close();
        await requests.cancel();
        await server.close(force: true);
        gateway.clear();
      }
    },
    skip: !Platform.isLinux,
  );
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Synthetic lifecycle condition timed out');
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
}

PlaylistTrackSummary _track(String id, {int duration = 1}) =>
    PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'synthetic-$id',
      title: 'Synthetic',
      artistNames: const ['Fixture'],
      durationSeconds: duration,
    );

class _NoLyrics implements LyricGateway {
  const _NoLyrics();
  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) => _NoLyricsOperation();
}

class _NoLyricsOperation implements LyricLoadOperation {
  @override
  bool cancel() => true;
  @override
  Future<LyricLoadResult> run() async =>
      const LyricLoadResult(failure: LyricFailure.unavailable);
}

class _CountedPlayer implements MediaKitAudioPlayer {
  final native = PlatformMediaKitAudioPlayer();
  int opens = 0, plays = 0, seeks = 0, stops = 0;
  @override
  Stream<bool> get playing => native.playing;
  @override
  Stream<bool> get completed => native.completed;
  @override
  Stream<Duration> get position => native.position;
  @override
  Stream<String> get errors => native.errors;
  @override
  Stream<int> get sourceFailures => native.sourceFailures;
  @override
  int get sourceGeneration => native.sourceGeneration;
  @override
  bool get sourceFailed => native.sourceFailed;
  @override
  Future<void> open(Uri uri) {
    opens++;
    return native.open(uri);
  }

  @override
  Future<void> play() {
    plays++;
    return native.play();
  }

  @override
  Future<void> seek(Duration value) {
    seeks++;
    return native.seek(value);
  }

  @override
  Future<void> stop() {
    stops++;
    return native.stop();
  }

  @override
  Future<void> pause() => native.pause();
  @override
  Future<void> setVolume(double percent) => native.setVolume(percent);
  @override
  Future<void> dispose() => native.dispose();
}

class _CountedFocus implements ForegroundAudioFocusManager {
  final values = <bool>[];
  final native = const AudioSessionForegroundAudioFocusManager();
  @override
  Future<bool> setActive(bool value) {
    values.add(value);
    return native.setActive(value);
  }
}

class _LocalResolver implements MediaResolutionGateway {
  _LocalResolver(this.uri);
  Uri uri;
  int count = 0;
  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) {
    count++;
    return _LocalResolution(uri);
  }
}

class _LocalResolution implements MediaResolutionOperation {
  _LocalResolution(this.uri);
  final Uri uri;
  @override
  bool cancel() => false;
  @override
  Future<MediaResolutionResult> run() async => MediaResolutionResult(
    source: ResolvedPlaybackSource(
      uri: uri,
      format: PlaybackAudioFormat.mp3,
      quality: PlaybackAudioQuality.standard,
      validForSeconds: 60,
    ),
  );
}
