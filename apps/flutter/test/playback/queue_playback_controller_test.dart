import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

void main() {
  test(
    'replace and manual navigation play only Rust-selected current',
    () async {
      final gateway = _ScriptedQueueGateway(
        replaceResults: [
          _result([first, second, third], 1, changed: true),
        ],
        advanceResults: [
          _result([first, second, third], 2, changed: true),
        ],
        rewindResults: [
          _result([first, second, third], 1, changed: true),
        ],
      );
      final audio = _FakeAudioEngine([
        _FakeAudioSession(),
        _FakeAudioSession(),
        _FakeAudioSession(),
      ]);
      final media = _FakeMediaGateway(['second', 'third', 'second']);
      final controller = _controller(gateway, media, audio);

      await controller.replaceAndPlay([first, second, third], 1);
      expect(controller.current, same(second));
      expect(media.requests.last, second.opaqueId);

      await controller.advance();
      expect(controller.current, same(third));
      expect(media.requests.last, third.opaqueId);

      await controller.rewind();
      expect(controller.current, same(second));
      expect(media.requests, [
        second.opaqueId,
        third.opaqueId,
        second.opaqueId,
      ]);
      controller.dispose();
    },
  );

  test(
    'completion advances exactly once and terminal completion stays put',
    () async {
      final gateway = _ScriptedQueueGateway(
        replaceResults: [
          _result([first, second], 0, changed: true),
        ],
        completionResults: [
          _result([first, second], 1, changed: true),
          _result([first, second], 1),
        ],
      );
      final firstSession = _FakeAudioSession();
      final secondSession = _FakeAudioSession();
      final media = _FakeMediaGateway(['first', 'second']);
      final controller = _controller(
        gateway,
        media,
        _FakeAudioEngine([firstSession, secondSession]),
      );

      await controller.replaceAndPlay([first, second], 0);
      firstSession.emit(ForegroundAudioState.completed);
      await _flush();
      expect(gateway.completionCalls, 1);
      expect(controller.current, same(second));
      expect(media.requests.last, second.opaqueId);

      secondSession.emit(ForegroundAudioState.completed);
      await _flush();
      expect(gateway.completionCalls, 2);
      expect(controller.current, same(second));
      expect(media.requests, [first.opaqueId, second.opaqueId]);
      await _flush();
      expect(gateway.completionCalls, 2);
      controller.dispose();
    },
  );

  test(
    'repeat-one completion replays the Rust-selected position once',
    () async {
      final gateway = _ScriptedQueueGateway(
        replaceResults: [
          _result(
            [first],
            0,
            changed: true,
            repeatMode: PlaybackRepeatMode.one,
          ),
        ],
        completionResults: [
          _result(
            [first],
            0,
            changed: true,
            repeatMode: PlaybackRepeatMode.one,
          ),
        ],
      );
      final firstSession = _FakeAudioSession();
      final controller = _controller(
        gateway,
        _FakeMediaGateway(['first', 'first-again']),
        _FakeAudioEngine([firstSession, _FakeAudioSession()]),
      );

      await controller.replaceAndPlay([first], 0);
      firstSession.emit(ForegroundAudioState.completed);
      await _flush();

      expect(gateway.completionCalls, 1);
      expect(controller.current, same(first));
      expect(controller.playback.stage, TrackPlaybackStage.playing);
      controller.dispose();
    },
  );

  test('mode changes accept Rust state without restarting playback', () async {
    final gateway = _ScriptedQueueGateway(
      replaceResults: [
        _result([first, second], 0, changed: true),
      ],
      orderResults: [
        _result(
          [first, second],
          0,
          changed: true,
          order: PlaybackOrder.shuffle,
        ),
      ],
      repeatResults: [
        _result(
          [first, second],
          0,
          changed: true,
          order: PlaybackOrder.shuffle,
          repeatMode: PlaybackRepeatMode.all,
        ),
      ],
    );
    final media = _FakeMediaGateway(['first']);
    final controller = _controller(
      gateway,
      media,
      _FakeAudioEngine([_FakeAudioSession()]),
    );

    await controller.replaceAndPlay([first, second], 0);
    await controller.toggleShuffle();
    await controller.cycleRepeatMode();

    expect(controller.order, PlaybackOrder.shuffle);
    expect(controller.repeatMode, PlaybackRepeatMode.all);
    expect(media.requests, [first.opaqueId]);
    expect(controller.playback.stage, TrackPlaybackStage.playing);
    controller.dispose();
  });

  test('queue failure retains the last valid snapshot and playback', () async {
    final gateway = _ScriptedQueueGateway(
      replaceResults: [
        _result([first, second], 0, changed: true),
      ],
      advanceResults: [
        const PlaybackQueueResult(
          failure: PlaybackQueueFailure.coreUnavailable,
        ),
      ],
    );
    final media = _FakeMediaGateway(['first']);
    final controller = _controller(
      gateway,
      media,
      _FakeAudioEngine([_FakeAudioSession()]),
    );

    await controller.replaceAndPlay([first, second], 0);
    await controller.advance();

    expect(controller.failure, PlaybackQueueFailure.coreUnavailable);
    expect(controller.current, same(first));
    expect(media.requests, [first.opaqueId]);
    expect(controller.playback.stage, TrackPlaybackStage.playing);
    controller.dispose();
  });

  test('current removal plays replacement and clear stops playback', () async {
    final gateway = _ScriptedQueueGateway(
      replaceResults: [
        _result([first, second], 0, changed: true),
      ],
      removeResults: [
        _result([second], 0, changed: true),
      ],
      clearResults: [_result(const [], null, changed: true)],
    );
    final media = _FakeMediaGateway(['first', 'second']);
    final controller = _controller(
      gateway,
      media,
      _FakeAudioEngine([_FakeAudioSession(), _FakeAudioSession()]),
    );

    await controller.replaceAndPlay([first, second], 0);
    await controller.remove(0);
    expect(controller.current, same(second));
    expect(media.requests.last, second.opaqueId);

    await controller.clear();
    expect(controller.tracks, isEmpty);
    expect(controller.playback.stage, TrackPlaybackStage.stopped);
    controller.dispose();
  });

  test(
    'selected queue track owns lyric load and current-session position',
    () async {
      final queue = _ScriptedQueueGateway(
        replaceResults: [
          _result([first, second], 0, changed: true),
        ],
        advanceResults: [
          _result([first, second], 1, changed: true),
        ],
        clearResults: [_result(const [], null, changed: true)],
      );
      final firstSession = _FakeAudioSession();
      final secondSession = _FakeAudioSession();
      final lyricGateway = _FakeLyricGateway();
      final controller = _controller(
        queue,
        _FakeMediaGateway(['first', 'second']),
        _FakeAudioEngine([firstSession, secondSession]),
        lyrics: LyricController(lyricGateway),
      );

      await controller.replaceAndPlay([first, second], 0);
      await _flush();
      expect(lyricGateway.requests, [first.opaqueId]);
      expect(controller.lyrics?.stage, LyricStage.content);
      firstSession.emitPosition(250);
      await _flush();
      expect(controller.lyrics?.positionMs, 250);
      expect(controller.lyrics?.activeSelection?.lineIndex, 0);
      expect(controller.lyrics?.activeSelection?.segmentIndex, 0);
      expect(controller.lyrics?.activeSelection?.segmentProgress, 0.5);

      await controller.advance();
      await _flush();
      expect(lyricGateway.requests, [first.opaqueId, second.opaqueId]);
      expect(controller.lyrics?.track, same(second));
      expect(controller.lyrics?.positionMs, 0);
      secondSession.emitPosition(750);
      await _flush();
      expect(controller.lyrics?.activeSelection?.lineIndex, 0);
      expect(controller.lyrics?.activeSelection?.segmentIndex, 0);
      expect(controller.lyrics?.activeSelection?.segmentProgress, 1);

      await controller.clear();
      expect(controller.lyrics?.stage, LyricStage.idle);
      expect(controller.lyrics?.track, isNull);
      controller.dispose();
    },
  );
}

const first = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'first',
  title: 'First track',
  artistNames: ['Artist'],
);
const second = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'second',
  title: 'Second track',
  artistNames: ['Artist'],
);
const third = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'third',
  title: 'Third track',
  artistNames: ['Artist'],
);

PlaybackQueueResult _result(
  List<PlaylistTrackSummary> tracks,
  int? currentIndex, {
  bool changed = false,
  PlaybackOrder order = PlaybackOrder.sequential,
  PlaybackRepeatMode repeatMode = PlaybackRepeatMode.off,
}) => PlaybackQueueResult(
  snapshot: PlaybackQueueSnapshot(
    tracks: tracks,
    currentIndex: currentIndex,
    hasPrevious:
        currentIndex != null &&
        (currentIndex > 0 || repeatMode == PlaybackRepeatMode.all),
    hasNext:
        currentIndex != null &&
        (currentIndex + 1 < tracks.length ||
            repeatMode == PlaybackRepeatMode.all),
    order: order,
    repeatMode: repeatMode,
  ),
  playbackRequested: changed,
);

QueuePlaybackController _controller(
  PlaybackQueueGateway gateway,
  MediaResolutionGateway media,
  ForegroundAudioEngine audio, {
  LyricController? lyrics,
}) => QueuePlaybackController(
  gateway,
  TrackPlaybackController(media, ForegroundPlaybackController(audio)),
  lyrics: lyrics,
);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _ScriptedQueueGateway implements PlaybackQueueGateway {
  _ScriptedQueueGateway({
    this.replaceResults = const [],
    this.advanceResults = const [],
    this.rewindResults = const [],
    this.orderResults = const [],
    this.repeatResults = const [],
    this.completionResults = const [],
    this.removeResults = const [],
    this.clearResults = const [],
  });

  final List<PlaybackQueueResult> replaceResults;
  final List<PlaybackQueueResult> advanceResults;
  final List<PlaybackQueueResult> rewindResults;
  final List<PlaybackQueueResult> orderResults;
  final List<PlaybackQueueResult> repeatResults;
  final List<PlaybackQueueResult> completionResults;
  final List<PlaybackQueueResult> removeResults;
  final List<PlaybackQueueResult> clearResults;
  int _replace = 0;
  int _advance = 0;
  int _rewind = 0;
  int _order = 0;
  int _repeat = 0;
  int _completion = 0;
  int _remove = 0;
  int _clear = 0;

  int get completionCalls => _completion;

  @override
  PlaybackQueueResult snapshot() => _result(const [], null);

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) => replaceResults[_replace++];

  @override
  PlaybackQueueResult advance() => advanceResults[_advance++];

  @override
  PlaybackQueueResult rewind() => rewindResults[_rewind++];

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) => orderResults[_order++];

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) =>
      repeatResults[_repeat++];

  @override
  PlaybackQueueResult completeCurrent() => completionResults[_completion++];

  @override
  PlaybackQueueResult remove(int index) => removeResults[_remove++];

  @override
  PlaybackQueueResult clear() => clearResults[_clear++];

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) =>
      throw StateError('not scripted');

  @override
  PlaybackQueueResult select(int index) => throw StateError('not scripted');
}

class _FakeMediaGateway implements MediaResolutionGateway {
  _FakeMediaGateway(this.vkeys);

  final List<String> vkeys;
  final List<String> requests = [];
  int _next = 0;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) {
    requests.add(opaqueTrackId);
    return _ImmediateMediaOperation(vkeys[_next++]);
  }
}

class _ImmediateMediaOperation implements MediaResolutionOperation {
  const _ImmediateMediaOperation(this.vkey);

  final String vkey;

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async => MediaResolutionResult(
    source: ResolvedPlaybackSource(
      uri: Uri.parse('https://audio.example.test/source.mp3?vkey=$vkey'),
      format: PlaybackAudioFormat.mp3,
      quality: PlaybackAudioQuality.standard,
      validForSeconds: 7200,
    ),
  );
}

class _FakeAudioEngine implements ForegroundAudioEngine {
  _FakeAudioEngine(this.sessions);

  final List<ForegroundAudioSession> sessions;
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

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> play() async => emit(ForegroundAudioState.playing);

  @override
  Future<void> pause() async => emit(ForegroundAudioState.paused);

  @override
  Future<void> seekToMs(int positionMs) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async => emit(ForegroundAudioState.stopped);

  @override
  Future<void> dispose() async {
    await _states.close();
    await _failures.close();
    await _positions.close();
  }

  void emit(ForegroundAudioState state) => _states.add(state);

  void emitPosition(int positionMs) => _positions.add(positionMs);
}

class _FakeLyricGateway implements LyricGateway {
  final List<String> requests = [];

  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) {
    requests.add(opaqueTrackId);
    return _ImmediateLyricOperation(
      LyricLoadResult(
        lyrics: SynchronizedLyrics([
          SynchronizedLyricLine(
            text: 'Synthetic lyric',
            startMs: 0,
            durationMs: 1000,
            segments: const [
              TimedLyricSegment(text: 'Synthetic', startMs: 0, durationMs: 500),
            ],
          ),
        ]),
      ),
    );
  }
}

class _ImmediateLyricOperation implements LyricLoadOperation {
  const _ImmediateLyricOperation(this.result);

  final LyricLoadResult result;

  @override
  bool cancel() => true;

  @override
  Future<LyricLoadResult> run() async => result;
}
