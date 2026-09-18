import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
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
    'mixed-provider queue keeps ownership across next and previous navigation',
    () async {
      const qqFirst = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'shared-id',
        title: 'QQ first',
        artistNames: ['QQ artist'],
      );
      const netEaseFirst = PlaylistTrackSummary(
        providerId: 'netease-cloud-music',
        opaqueId: 'shared-id',
        title: 'NetEase first',
        artistNames: ['NetEase artist'],
      );
      const qqSecond = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'qq-second',
        title: 'QQ second',
        artistNames: ['QQ artist'],
      );
      const netEaseSecond = PlaylistTrackSummary(
        providerId: 'netease-cloud-music',
        opaqueId: 'netease-second',
        title: 'NetEase second',
        artistNames: ['NetEase artist'],
      );
      const tracks = [qqFirst, netEaseFirst, qqSecond, netEaseSecond];
      final queue = _ScriptedQueueGateway(
        replaceResults: [_result(tracks, 0, changed: true)],
        advanceResults: [
          _result(tracks, 1, changed: true),
          _result(tracks, 2, changed: true),
          _result(tracks, 3, changed: true),
        ],
        rewindResults: [_result(tracks, 2, changed: true)],
      );
      final media = _FakeMediaGateway([
        'qq-first',
        'netease-first',
        'qq-second',
        'netease-second',
        'qq-second-again',
      ]);
      final controller = _controller(
        queue,
        media,
        _FakeAudioEngine(List.generate(5, (_) => _FakeAudioSession())),
      );

      await controller.replaceAndPlay(tracks, 0);
      await controller.advance();
      await controller.advance();
      await controller.advance();
      await controller.rewind();

      expect(media.providerRequests, [
        (providerId: 'qq-music', opaqueTrackId: 'shared-id'),
        (providerId: 'netease-cloud-music', opaqueTrackId: 'shared-id'),
        (providerId: 'qq-music', opaqueTrackId: 'qq-second'),
        (providerId: 'netease-cloud-music', opaqueTrackId: 'netease-second'),
        (providerId: 'qq-music', opaqueTrackId: 'qq-second'),
      ]);
      expect(controller.current, same(qqSecond));
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

  test('current Track signal ignores playback-only notifications', () async {
    final gateway = _ScriptedQueueGateway(
      replaceResults: [
        _result([first, second], 0, changed: true),
      ],
      advanceResults: [
        _result([first, second], 1, changed: true),
      ],
    );
    final firstSession = _FakeAudioSession();
    final controller = _controller(
      gateway,
      _FakeMediaGateway(['first', 'second']),
      _FakeAudioEngine([firstSession, _FakeAudioSession()]),
    );
    var currentTrackChanges = 0;
    controller.currentTrackListenable.addListener(() {
      currentTrackChanges += 1;
    });

    await controller.replaceAndPlay([first, second], 0);
    expect(controller.currentTrackListenable.value, same(first));
    expect(currentTrackChanges, 1);

    firstSession.emitPosition(1250);
    firstSession.emit(ForegroundAudioState.paused);
    await _flush();
    expect(currentTrackChanges, 1);

    await controller.advance();
    expect(controller.currentTrackListenable.value, same(second));
    expect(currentTrackChanges, 2);
    controller.dispose();
  });

  test('quality reload preserves the current paused position', () async {
    const qualityTrack = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'quality-track',
      title: 'Quality track',
      artistNames: ['Artist'],
      durationSeconds: 120,
    );
    final gateway = _ScriptedQueueGateway(
      replaceResults: [
        _result([qualityTrack], 0, changed: true),
      ],
    );
    final firstSession = _FakeAudioSession();
    final secondSession = _FakeAudioSession();
    final media = _FakeMediaGateway(['standard', 'lossless']);
    final controller = _controller(
      gateway,
      media,
      _FakeAudioEngine([firstSession, secondSession]),
    );

    await controller.replaceAndPlay([qualityTrack], 0);
    firstSession.emitPosition(4250);
    await _flush();
    await controller.playback.pause();
    await controller.reloadCurrentSource();

    expect(media.requests, [qualityTrack.opaqueId, qualityTrack.opaqueId]);
    expect(secondSession.seekPositions, [4250]);
    expect(secondSession.pauseCalls, 1);
    expect(controller.playback.stage, TrackPlaybackStage.paused);
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

  test(
    'roam extends terminal queue atomically and starts first candidate',
    () async {
      const related = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'related',
        title: 'Related track',
        artistNames: ['Artist'],
      );
      final queue = _ScriptedQueueGateway(
        replaceResults: [
          _result([first], 0, changed: true),
        ],
        completionResults: [
          _result([first], 0),
        ],
        extensionResults: [
          _result([first, related], 1, changed: true),
        ],
      );
      final relatedGateway = _RelatedGateway([
        const RelatedTracksResult(tracks: [related]),
      ]);
      final firstSession = _FakeAudioSession();
      final controller = _controller(
        queue,
        _FakeMediaGateway(['first', 'related']),
        _FakeAudioEngine([firstSession, _FakeAudioSession()]),
        relatedTracksGateway: relatedGateway,
      );
      controller.setRoamEnabled(true);

      await controller.replaceAndPlay([first], 0);
      firstSession.emit(ForegroundAudioState.completed);
      await _flush();
      await _flush();

      expect(relatedGateway.seeds, [first]);
      expect(queue.extensionCalls, 1);
      expect(controller.current, related);
      expect(controller.roamStage, RoamStage.continued);
      expect(controller.playback.stage, TrackPlaybackStage.playing);
      controller.dispose();
    },
  );

  test(
    'roam respects repeat, shuffle, next-item, and provider boundaries',
    () async {
      const unsupported = PlaylistTrackSummary(
        providerId: 'local',
        opaqueId: 'local',
        title: 'Local track',
        artistNames: ['Artist'],
      );
      final relatedGateway = _RelatedGateway(const []);
      final queue = _ScriptedQueueGateway(
        replaceResults: [
          _result([first, second], 0, changed: true),
          _result([first], 0, changed: true, order: PlaybackOrder.shuffle),
          _result(
            [first],
            0,
            changed: true,
            repeatMode: PlaybackRepeatMode.one,
          ),
          _result([unsupported], 0, changed: true),
        ],
        completionResults: [
          _result([first, second], 1, changed: true),
          _result([first], 0, order: PlaybackOrder.shuffle),
          _result(
            [first],
            0,
            changed: true,
            repeatMode: PlaybackRepeatMode.one,
          ),
          _result([unsupported], 0),
        ],
      );
      final sessions = List.generate(7, (_) => _FakeAudioSession());
      final audio = _FakeAudioEngine(sessions);
      final controller = _controller(
        queue,
        _FakeMediaGateway(List.generate(7, (index) => 'key-$index')),
        audio,
        relatedTracksGateway: relatedGateway,
      );
      controller.setRoamEnabled(true);

      for (var index = 0; index < 4; index++) {
        final tracks = switch (index) {
          0 => [first, second],
          1 || 2 => [first],
          _ => [unsupported],
        };
        await controller.replaceAndPlay(tracks, 0);
        sessions[audio._next - 1].emit(ForegroundAudioState.completed);
        await _flush();
      }

      expect(relatedGateway.seeds, isEmpty);
      expect(controller.roamStage, RoamStage.unsupported);
      controller.dispose();
    },
  );

  test(
    'roam filters exact duplicates and rejects foreign-provider output',
    () async {
      const foreign = PlaylistTrackSummary(
        providerId: 'netease-cloud-music',
        opaqueId: 'foreign',
        title: 'Foreign',
        artistNames: ['Artist'],
      );
      final queue = _ScriptedQueueGateway(
        replaceResults: [
          _result([first], 0, changed: true),
          _result([first], 0, changed: true),
        ],
        completionResults: [
          _result([first], 0),
          _result([first], 0),
        ],
      );
      final relatedGateway = _RelatedGateway([
        const RelatedTracksResult(tracks: [first]),
        const RelatedTracksResult(tracks: [foreign]),
      ]);
      final firstSession = _FakeAudioSession();
      final secondSession = _FakeAudioSession();
      final controller = _controller(
        queue,
        _FakeMediaGateway(['one', 'two']),
        _FakeAudioEngine([firstSession, secondSession]),
        relatedTracksGateway: relatedGateway,
      );
      controller.setRoamEnabled(true);

      await controller.replaceAndPlay([first], 0);
      firstSession.emit(ForegroundAudioState.completed);
      await _flush();
      expect(controller.roamStage, RoamStage.empty);
      expect(queue.extensionCalls, 0);

      await controller.replaceAndPlay([first], 0);
      secondSession.emit(ForegroundAudioState.completed);
      await _flush();
      expect(controller.roamStage, RoamStage.failed);
      expect(queue.extensionCalls, 0);
      expect(controller.tracks, [first]);
      controller.dispose();
    },
  );

  test('queue replacement cancels and suppresses late roam result', () async {
    final late = Completer<RelatedTracksResult>();
    final operation = _ControlledRelatedOperation(late.future);
    final relatedGateway = _RelatedGateway.controlled(operation);
    final queue = _ScriptedQueueGateway(
      replaceResults: [
        _result([first], 0, changed: true),
        _result([second], 0, changed: true),
      ],
      completionResults: [
        _result([first], 0),
      ],
    );
    final session = _FakeAudioSession();
    final controller = _controller(
      queue,
      _FakeMediaGateway(['first', 'second']),
      _FakeAudioEngine([session, _FakeAudioSession()]),
      relatedTracksGateway: relatedGateway,
    );
    controller.setRoamEnabled(true);

    await controller.replaceAndPlay([first], 0);
    session.emit(ForegroundAudioState.completed);
    await _flush();
    expect(controller.roamStage, RoamStage.loading);
    await controller.replaceAndPlay([second], 0);
    expect(operation.cancelCalls, 1);
    late.complete(const RelatedTracksResult(tracks: [third]));
    await _flush();

    expect(queue.extensionCalls, 0);
    expect(controller.current, second);
    expect(controller.roamStage, RoamStage.idle);
    controller.dispose();
  });

  test(
    'roam stays inactive by default and failures keep the queue intact',
    () async {
      final queue = _ScriptedQueueGateway(
        replaceResults: [
          _result([first], 0, changed: true),
          _result([first], 0, changed: true),
        ],
        completionResults: [
          _result([first], 0),
          _result([first], 0),
        ],
      );
      final relatedGateway = _RelatedGateway([
        const RelatedTracksResult(failure: RelatedTracksFailure.network),
      ]);
      final firstSession = _FakeAudioSession();
      final secondSession = _FakeAudioSession();
      final controller = _controller(
        queue,
        _FakeMediaGateway(['first', 'first-again']),
        _FakeAudioEngine([firstSession, secondSession]),
        relatedTracksGateway: relatedGateway,
      );

      await controller.replaceAndPlay([first], 0);
      firstSession.emit(ForegroundAudioState.completed);
      await _flush();
      expect(relatedGateway.seeds, isEmpty);
      expect(controller.roamStage, RoamStage.idle);

      controller.setRoamEnabled(true);
      await controller.replaceAndPlay([first], 0);
      secondSession.emit(ForegroundAudioState.completed);
      await _flush();
      expect(relatedGateway.seeds, [first]);
      expect(controller.roamStage, RoamStage.failed);
      expect(controller.tracks, [first]);
      expect(queue.extensionCalls, 0);
      controller.dispose();
    },
  );

  test('disabling or disposing cancels an in-flight roam request', () async {
    Future<void> exercise({required bool dispose}) async {
      final late = Completer<RelatedTracksResult>();
      final operation = _ControlledRelatedOperation(late.future);
      final queue = _ScriptedQueueGateway(
        replaceResults: [
          _result([first], 0, changed: true),
        ],
        completionResults: [
          _result([first], 0),
        ],
      );
      final session = _FakeAudioSession();
      final controller = _controller(
        queue,
        _FakeMediaGateway(['first']),
        _FakeAudioEngine([session]),
        relatedTracksGateway: _RelatedGateway.controlled(operation),
      );
      controller.setRoamEnabled(true);
      await controller.replaceAndPlay([first], 0);
      session.emit(ForegroundAudioState.completed);
      await _flush();
      expect(controller.roamStage, RoamStage.loading);

      if (dispose) {
        controller.dispose();
      } else {
        controller.setRoamEnabled(false);
        expect(controller.roamStage, RoamStage.idle);
      }
      expect(operation.cancelCalls, 1);
      late.complete(const RelatedTracksResult(tracks: [second]));
      await _flush();
      expect(queue.extensionCalls, 0);
      if (!dispose) controller.dispose();
    }

    await exercise(dispose: false);
    await exercise(dispose: true);
  });

  test(
    'roam requests another bounded batch only at the next terminal',
    () async {
      final firstSession = _FakeAudioSession();
      final secondSession = _FakeAudioSession();
      final queue = _ScriptedQueueGateway(
        replaceResults: [
          _result([first], 0, changed: true),
        ],
        completionResults: [
          _result([first], 0),
          _result([first, second], 1),
        ],
        extensionResults: [
          _result([first, second], 1, changed: true),
          _result([first, second, third], 2, changed: true),
        ],
      );
      final relatedGateway = _RelatedGateway([
        const RelatedTracksResult(tracks: [second]),
        const RelatedTracksResult(tracks: [third]),
      ]);
      final controller = _controller(
        queue,
        _FakeMediaGateway(['first', 'second', 'third']),
        _FakeAudioEngine([firstSession, secondSession, _FakeAudioSession()]),
        relatedTracksGateway: relatedGateway,
      );
      controller.setRoamEnabled(true);

      await controller.replaceAndPlay([first], 0);
      firstSession.emit(ForegroundAudioState.completed);
      await _flush();
      await _flush();
      expect(relatedGateway.seeds, [first]);
      expect(queue.extensionCalls, 1);
      expect(controller.current, second);

      await _flush();
      expect(relatedGateway.seeds, [first]);
      secondSession.emit(ForegroundAudioState.completed);
      await _flush();
      await _flush();
      expect(relatedGateway.seeds, [first, second]);
      expect(queue.extensionCalls, 2);
      expect(controller.current, third);
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
  RelatedTracksGateway? relatedTracksGateway,
}) => QueuePlaybackController(
  gateway,
  TrackPlaybackController(media, ForegroundPlaybackController(audio)),
  lyrics: lyrics,
  relatedTracksGateway: relatedTracksGateway,
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
    this.extensionResults = const [],
    this.removeResults = const [],
    this.clearResults = const [],
  });

  final List<PlaybackQueueResult> replaceResults;
  final List<PlaybackQueueResult> advanceResults;
  final List<PlaybackQueueResult> rewindResults;
  final List<PlaybackQueueResult> orderResults;
  final List<PlaybackQueueResult> repeatResults;
  final List<PlaybackQueueResult> completionResults;
  final List<PlaybackQueueResult> extensionResults;
  final List<PlaybackQueueResult> removeResults;
  final List<PlaybackQueueResult> clearResults;
  int _replace = 0;
  int _advance = 0;
  int _rewind = 0;
  int _order = 0;
  int _repeat = 0;
  int _completion = 0;
  int _extension = 0;
  int _remove = 0;
  int _clear = 0;

  int get completionCalls => _completion;
  int get extensionCalls => _extension;

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
  PlaybackQueueResult extendAndAdvanceFromTerminal(
    List<PlaylistTrackSummary> tracks,
  ) => extensionResults[_extension++];

  @override
  PlaybackQueueResult select(int index) => throw StateError('not scripted');
}

class _RelatedGateway implements RelatedTracksGateway {
  _RelatedGateway(List<RelatedTracksResult> results)
    : _results = results.map(_ImmediateRelatedOperation.new).toList();

  _RelatedGateway.controlled(RelatedTracksLoadOperation operation)
    : _results = [operation];

  final List<RelatedTracksLoadOperation> _results;
  final List<PlaylistTrackSummary> seeds = [];

  @override
  RelatedTracksLoadOperation beginLoad(PlaylistTrackSummary seed) {
    seeds.add(seed);
    return _results.removeAt(0);
  }
}

class _ImmediateRelatedOperation implements RelatedTracksLoadOperation {
  const _ImmediateRelatedOperation(this.result);

  final RelatedTracksResult result;

  @override
  bool cancel() => true;

  @override
  Future<RelatedTracksResult> run() async => result;
}

class _ControlledRelatedOperation implements RelatedTracksLoadOperation {
  _ControlledRelatedOperation(this.result);

  final Future<RelatedTracksResult> result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<RelatedTracksResult> run() => result;
}

class _FakeMediaGateway implements MediaResolutionGateway {
  _FakeMediaGateway(this.vkeys);

  final List<String> vkeys;
  final List<String> requests = [];
  final List<({String providerId, String opaqueTrackId})> providerRequests = [];
  int _next = 0;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) {
    requests.add(opaqueTrackId);
    providerRequests.add((
      providerId: providerId,
      opaqueTrackId: opaqueTrackId,
    ));
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
  Future<void> dispose() async {}

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) async => sessions[_next++];
}

class _FakeAudioSession implements ForegroundAudioSession {
  final StreamController<ForegroundAudioState> _states =
      StreamController.broadcast();
  final StreamController<ForegroundAudioFailure> _failures =
      StreamController.broadcast();
  final StreamController<int> _positions = StreamController.broadcast();
  final List<int> seekPositions = [];
  int pauseCalls = 0;

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> play() async => emit(ForegroundAudioState.playing);

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    emit(ForegroundAudioState.paused);
  }

  @override
  Future<void> seekToMs(int positionMs) async {
    seekPositions.add(positionMs);
    emitPosition(positionMs);
  }

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
