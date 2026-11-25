import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/radar_controller.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

void main() {
  group('Workstream C — Radar Loading, Session Sharing & Queue Modes (R01–R10)', () {
    test('R01: 1 + 10 + 10 + 10 fills Discover Radar to 31 unique tracks in 4 bounded pages', () async {
      final gateway = _DynamicRadarGateway((page, callNumber) {
        if (page == 1) {
          return RadarTrackPageResult(
            page: 1,
            hasMore: true,
            tracks: [_track('seed-1')],
          );
        }
        return RadarTrackPageResult(
          page: page,
          hasMore: true,
          tracks: _batch(page, 10),
        );
      });
      final controller = RadarController(
        gateway,
        initialPrefetchTarget: 30,
        maxInitialPrefetchPages: 3,
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.stage, RadarStage.content);
      expect(controller.tracks, hasLength(31));
      expect(controller.hasMore, isTrue);
      expect(gateway.requestedPages, [1, 2, 3, 4]);
    });

    test('R02: 10 + 10 + 10 stops at 30 tracks in 3 pages without requesting page 4', () async {
      final gateway = _DynamicRadarGateway(
        (page, _) => RadarTrackPageResult(
          page: page,
          hasMore: true,
          tracks: _batch(page, 10),
        ),
      );
      final controller = RadarController(
        gateway,
        initialPrefetchTarget: 30,
        maxInitialPrefetchPages: 3,
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.tracks, hasLength(30));
      expect(gateway.requestedPages, [1, 2, 3]);
    });

    test('R03: heavy duplicates and all-omitted pages stay bounded and deduplicate in both Radar and Queue', () async {
      final gateway = _DynamicRadarGateway((page, _) {
        return switch (page) {
          1 => RadarTrackPageResult(
            page: 1,
            hasMore: true,
            tracks: [_track('dup-0')],
          ),
          2 => RadarTrackPageResult(
            page: 2,
            hasMore: true,
            tracks: [_track('dup-0'), _track('dup-0'), _track('unique-2')],
            omittedTrackCount: 2,
          ),
          3 => const RadarTrackPageResult(
            page: 3,
            hasMore: true,
            tracks: [],
            omittedTrackCount: 10,
          ),
          _ => RadarTrackPageResult(
            page: page,
            hasMore: page < 6,
            tracks: [
              _track('dup-0'),
              _track('unique-2'),
              _track('unique-$page'),
            ],
          ),
        };
      });

      final controller = RadarController(
        gateway,
        initialPrefetchTarget: 30,
        maxInitialPrefetchPages: 3,
      );
      addTearDown(controller.dispose);
      await controller.load();

      // Bounded to 4 pages total (1 + 3 prefetch), exact dedup, omissions tracked.
      expect(gateway.requestedPages, [1, 2, 3, 4]);
      expect(controller.tracks.map((t) => t.opaqueId), [
        'track:dup-0',
        'track:unique-2',
        'track:unique-4',
      ]);
      expect(controller.omittedTrackCount, 12);

      // Hand off to Queue: pages 5 and 6 must also deduplicate against initialTracks!
      final queue = _buildQueue();
      addTearDown(queue.dispose);
      await queue.replaceAndPlayCollection(
        controller.collectionPlaybackSource(providerId: 'qq-music'),
        0,
      );
      await _drain();

      expect(queue.tracks.map((t) => t.opaqueId), [
        'track:dup-0',
        'track:unique-2',
        'track:unique-4',
        'track:unique-5',
        'track:unique-6',
      ]);
      expect(queue.collectionStage, CollectionPlaybackStage.exhausted);
    });

    test('R04: slow first-track media resolution does not block Radar Queue initial fill to 50', () async {
      final slowMedia = Completer<MediaResolutionResult>();
      final queue = _buildQueue(mediaResultFuture: slowMedia.future);
      addTearDown(queue.dispose);

      final gateway = _DynamicRadarGateway(
        (page, _) => RadarTrackPageResult(
          page: page,
          hasMore: true,
          tracks: page == 1 ? [_track('seed-1')] : _batch(page, 10),
        ),
      );
      final radar = RadarController(gateway);
      addTearDown(radar.dispose);
      await radar.load();

      // Start playback while first track media resolution stays pending!
      final playFuture = queue.replaceAndPlayCollection(
        radar.collectionPlaybackSource(providerId: 'qq-music'),
        0,
      );
      await _drain();

      // First track is still resolving, yet Queue ALREADY filled 51 tracks (pages 2..6)!
      expect(queue.playback.stage, TrackPlaybackStage.resolving);
      expect(queue.tracks, hasLength(51));
      expect(gateway.requestedPages, [1, 2, 3, 4, 5, 6]);

      slowMedia.complete(
        MediaResolutionResult(
          source: ResolvedPlaybackSource(
            uri: Uri.parse('https://example.invalid/seed.mp3'),
            format: PlaybackAudioFormat.mp3,
            quality: PlaybackAudioQuality.standard,
            validForSeconds: 300,
          ),
        ),
      );
      await playFuture;
      expect(queue.playback.stage, TrackPlaybackStage.playing);
      expect(queue.current?.opaqueId, 'track:seed-1');
    });

    test('R05 & R10: page prefetch and Queue handoff share pending Page 2 single-flight and survive page disposal', () async {
      final page2Completer = Completer<RadarTrackPageResult>();
      var page2Requests = 0;
      var page2CancelCalls = 0;
      final requestedPages = <int>[];
      final gateway = _CustomRadarGateway((page) {
        requestedPages.add(page);
        if (page == 1) {
          return _ImmediateRadarOp(
            RadarTrackPageResult(
              page: 1,
              hasMore: true,
              tracks: [_track('seed-1')],
            ),
          );
        }
        if (page == 2) {
          page2Requests += 1;
          // Dynamic endpoint would return DIFFERENT tracks if called twice!
          final callId = page2Requests;
          return _TrackedPendingRadarOp(
            page2Completer.future.then(
              (result) => RadarTrackPageResult(
                page: result.page,
                hasMore: result.hasMore,
                tracks: result.tracks
                    .map(
                      (t) => PlaylistTrackSummary(
                        providerId: t.providerId,
                        opaqueId: '${t.opaqueId}-call$callId',
                        title: t.title,
                        artistNames: t.artistNames,
                      ),
                    )
                    .toList(),
              ),
            ),
            onCancel: () => page2CancelCalls += 1,
          );
        }
        return _ImmediateRadarOp(
          RadarTrackPageResult(
            page: page,
            hasMore: page < 4,
            tracks: _batch(page, 10),
          ),
        );
      });

      final radar = RadarController(
        gateway,
        initialPrefetchTarget: 30,
        maxInitialPrefetchPages: 3,
      );
      // Start loading: Page 1 finishes and immediately begins Page 2 prefetch.
      final radarLoad = radar.load();
      await _drain();
      expect(requestedPages, [1, 2]);
      expect(page2Requests, 1);

      // User taps Play while Page 2 is in flight, then navigates away (disposing RadarController!).
      final queue = _buildQueue();
      addTearDown(queue.dispose);
      await queue.replaceAndPlayCollection(
        radar.collectionPlaybackSource(providerId: 'qq-music'),
        0,
      );
      await _drain();

      // Queue joined the in-flight Page 2 — STILL ONLY 1 Page 2 request!
      expect(page2Requests, 1);

      // User leaves Discover Radar while Page 2 is STILL pending.
      radar.dispose();
      // Page 2 underlying operation MUST NOT be cancelled because Queue still owns a joiner!
      expect(page2CancelCalls, 0);

      // Page 2 completes -> Queue receives Page 2 and continues Pages 3 & 4 cleanly.
      page2Completer.complete(
        RadarTrackPageResult(page: 2, hasMore: true, tracks: _batch(2, 10)),
      );
      await radarLoad;
      await _drain();

      expect(page2Requests, 1);
      expect(requestedPages, [1, 2, 3, 4]);
      expect(queue.tracks, hasLength(31));
      expect(queue.tracks[1].opaqueId, 'track:p2-0-call1');
      expect(queue.collectionStage, CollectionPlaybackStage.exhausted);
    });

    test('R05b: intra-controller loadMore/prefetchTo during initial prefetch stays strictly serial with no duplicate page', () async {
      final page2 = Completer<RadarTrackPageResult>();
      final requestedPages = <int>[];
      final gateway = _CustomRadarGateway((page) {
        requestedPages.add(page);
        if (page == 1) {
          return _ImmediateRadarOp(
            RadarTrackPageResult(
              page: 1,
              hasMore: true,
              tracks: [_track('seed-1')],
            ),
          );
        }
        if (page == 2) {
          return _TrackedPendingRadarOp(page2.future, onCancel: () {});
        }
        return _ImmediateRadarOp(
          RadarTrackPageResult(
            page: page,
            hasMore: false,
            tracks: _batch(page, 10),
          ),
        );
      });
      final radar = RadarController(
        gateway,
        initialPrefetchTarget: 30,
        maxInitialPrefetchPages: 3,
      );
      addTearDown(radar.dispose);

      final loadFuture = radar.load();
      await _drain();
      expect(requestedPages, [1, 2]);

      // Trigger manual loadMore and viewport prefetch while initial prefetch is waiting on Page 2.
      final moreFuture = radar.loadMore();
      radar.prefetchTo(50);
      await _drain();
      expect(requestedPages, [1, 2]);

      page2.complete(
        RadarTrackPageResult(page: 2, hasMore: true, tracks: _batch(2, 10)),
      );
      await Future.wait([loadFuture, moreFuture]);

      expect(requestedPages, [1, 2, 3]);
      expect(radar.tracks, hasLength(21));
    });

    test('R06: rapid Refresh isolates Radar sessions and sign-out invalidation cancels Queue continuation', () async {
      var sessionCounter = 0;
      final pendingQueuePage = Completer<RadarTrackPageResult>();
      var cancelledCount = 0;
      final gateway = _CustomRadarGateway((page) {
        if (page == 1) {
          sessionCounter += 1;
          return _ImmediateRadarOp(
            RadarTrackPageResult(
              page: 1,
              hasMore: true,
              tracks: [_track('s$sessionCounter-p1')],
            ),
          );
        }
        return _TrackedPendingRadarOp(
          pendingQueuePage.future,
          onCancel: () => cancelledCount += 1,
        );
      });
      final radar = RadarController(gateway);
      addTearDown(radar.dispose);
      await radar.load();
      final sourceFromSession1 = radar.collectionPlaybackSource(
        providerId: 'qq-music',
      );

      // Refresh Radar into session 2.
      await radar.load();
      expect(radar.tracks.single.opaqueId, 'track:s2-p1');

      // Queue starts session 1; then account replacement calls invalidateCollectionSource().
      final queue = _buildQueue();
      addTearDown(queue.dispose);
      await queue.replaceAndPlayCollection(sourceFromSession1, 0);
      await _drain();
      expect(queue.collectionStage, CollectionPlaybackStage.loading);

      queue.invalidateCollectionSource();
      expect(cancelledCount, 1);
      expect(queue.collectionStage, CollectionPlaybackStage.idle);

      // Late completion cannot touch the invalidated Queue.
      pendingQueuePage.complete(
        RadarTrackPageResult(page: 2, hasMore: false, tracks: _batch(2, 5)),
      );
      await _drain();
      expect(queue.tracks.map((t) => t.opaqueId), ['track:s1-p1']);
    });

    test('R07: Shuffle, Repeat One, Repeat All, mid-fill mode toggle, and return to sequential repeat-off', () async {
      // 1. Shuffle already ON when starting Radar: keeps Shuffle ON and fills ~50 tracks!
      {
        final gateway = _DynamicRadarGateway(
          (page, _) => RadarTrackPageResult(
            page: page,
            hasMore: true,
            tracks: page == 1 ? [_track('seed')] : _batch(page, 10),
          ),
        );
        final radar = RadarController(gateway);
        addTearDown(radar.dispose);
        await radar.load();

        final queue = _buildQueue();
        addTearDown(queue.dispose);
        await queue.setOrder(PlaybackOrder.shuffle);
        await queue.replaceAndPlayCollection(
          radar.collectionPlaybackSource(providerId: 'qq-music'),
          0,
        );
        await _drain();

        expect(queue.order, PlaybackOrder.shuffle);
        expect(queue.tracks, hasLength(51));
        expect(gateway.requestedPages, [1, 2, 3, 4, 5, 6]);
      }

      // 2. Repeat One active when starting Radar: keeps Repeat One, fills ~50 tracks, EOF replays current.
      {
        final session = _ScriptedAudioSession();
        final gateway = _DynamicRadarGateway(
          (page, _) => RadarTrackPageResult(
            page: page,
            hasMore: true,
            tracks: page == 1 ? [_track('seed')] : _batch(page, 10),
          ),
        );
        final radar = RadarController(gateway);
        addTearDown(radar.dispose);
        await radar.load();

        final queue = _buildQueue(sessions: [session]);
        addTearDown(queue.dispose);
        await queue.setRepeatMode(PlaybackRepeatMode.one);
        await queue.replaceAndPlayCollection(
          radar.collectionPlaybackSource(providerId: 'qq-music'),
          0,
        );
        await _drain();

        expect(queue.repeatMode, PlaybackRepeatMode.one);
        expect(queue.tracks, hasLength(51));
        session.emitState(ForegroundAudioState.completed);
        await _drain();
        // Repeat One replays index 0, does NOT load page 7!
        expect(queue.currentIndex, 0);
        expect(gateway.requestedPages, [1, 2, 3, 4, 5, 6]);
      }

      // 3. Repeat All active when starting Radar -> fills ~50 tracks -> switch BACK to Repeat Off
      //    retains collection source and resumes low-watermark continuation near tail!
      {
        final gateway = _DynamicRadarGateway(
          (page, _) => RadarTrackPageResult(
            page: page,
            hasMore: page < 7,
            tracks: page == 1 ? [_track('seed')] : _batch(page, 10),
          ),
        );
        final radar = RadarController(gateway);
        addTearDown(radar.dispose);
        await radar.load();

        final queue = _buildQueue();
        addTearDown(queue.dispose);
        await queue.setRepeatMode(PlaybackRepeatMode.all);
        await queue.replaceAndPlayCollection(
          radar.collectionPlaybackSource(providerId: 'qq-music'),
          0,
        );
        await _drain();

        expect(queue.repeatMode, PlaybackRepeatMode.all);
        expect(queue.tracks, hasLength(51));
        expect(queue.collectionHasMore, isTrue);

        // Near tail while Repeat All is ON: ongoing continuation must NOT fire.
        await queue.select(49);
        await _drain();
        expect(gateway.requestedPages, [1, 2, 3, 4, 5, 6]);

        // Switching BACK to Repeat Off resumes low-watermark continuation from page 7!
        await queue.setRepeatMode(PlaybackRepeatMode.off);
        await _drain();
        expect(gateway.requestedPages, [1, 2, 3, 4, 5, 6, 7]);
        expect(queue.tracks, hasLength(61));
        expect(queue.collectionStage, CollectionPlaybackStage.exhausted);
      }

      // 4. Toggling mode DURING initial fill does NOT kill initial fill.
      {
        final page2 = Completer<RadarTrackPageResult>();
        final gateway = _CustomRadarGateway((page) {
          if (page == 1) {
            return _ImmediateRadarOp(
              RadarTrackPageResult(
                page: 1,
                hasMore: true,
                tracks: [_track('seed')],
              ),
            );
          }
          if (page == 2) {
            return _TrackedPendingRadarOp(page2.future, onCancel: () {});
          }
          return _ImmediateRadarOp(
            RadarTrackPageResult(
              page: page,
              hasMore: page < 4,
              tracks: _batch(page, 10),
            ),
          );
        });
        final radar = RadarController(gateway);
        addTearDown(radar.dispose);
        await radar.load();

        final queue = _buildQueue();
        addTearDown(queue.dispose);
        await queue.replaceAndPlayCollection(
          radar.collectionPlaybackSource(providerId: 'qq-music'),
          0,
        );
        await _drain();
        expect(queue.collectionStage, CollectionPlaybackStage.loading);

        // User toggles Shuffle while initial fill Page 2 is in flight.
        await queue.setOrder(PlaybackOrder.shuffle);
        expect(queue.order, PlaybackOrder.shuffle);

        page2.complete(
          RadarTrackPageResult(page: 2, hasMore: true, tracks: _batch(2, 10)),
        );
        await _drain();
        expect(queue.tracks, hasLength(31));
        expect(queue.collectionStage, CollectionPlaybackStage.exhausted);
      }
    });

    test('R08 & R09: low-watermark replenishment, failure retry, and unbounded-load cap', () async {
      var failPage3Once = true;
      final gateway = _DynamicRadarGateway((page, _) {
        if (page == 3 && failPage3Once) {
          failPage3Once = false;
          return const RadarTrackPageResult(failure: RadarFailure.network);
        }
        // Short 2-track pages with hasMore: true to verify maxInitialPages=5 hard cap!
        return RadarTrackPageResult(
          page: page,
          hasMore: true,
          tracks: _batch(page, 2),
        );
      });
      final radar = RadarController(gateway);
      addTearDown(radar.dispose);
      await radar.load();

      final queue = _buildQueue();
      addTearDown(queue.dispose);
      await queue.replaceAndPlayCollection(
        radar.collectionPlaybackSource(providerId: 'qq-music'),
        0,
      );
      await _drain();

      // Failed at Page 3, retained Page 1 + Page 2 (4 tracks).
      expect(queue.collectionStage, CollectionPlaybackStage.failed);
      expect(queue.tracks, hasLength(4));

      // Explicit retry resumes exact Page 3 and stops at maxInitialPages=5 (Pages 2,3,4,5,6 -> 12 tracks).
      queue.retryCollectionContinuation();
      await _drain();
      expect(queue.collectionStage, CollectionPlaybackStage.ready);
      expect(queue.tracks, hasLength(12));
      expect(gateway.requestedPages, [1, 2, 3, 3, 4, 5, 6]);

      // Selecting near tail (index 9, remaining = 2 <= 3) triggers ONE low-watermark page (Page 7).
      await queue.select(9);
      await _drain();
      expect(gateway.requestedPages, [1, 2, 3, 3, 4, 5, 6, 7]);
      expect(queue.tracks, hasLength(14));
    });

    test('Bug 5: reusing Radar collectionPlaybackSource or re-requesting a page does not poison dedup and stall at 1 track', () async {
      final gateway = _DynamicRadarGateway((page, _) {
        if (page == 1) {
          return RadarTrackPageResult(
            page: 1,
            hasMore: true,
            tracks: [_track('seed')],
          );
        }
        return RadarTrackPageResult(
          page: page,
          hasMore: page < 6,
          tracks: _batch(page, 10),
        );
      });
      final radar = RadarController(gateway);
      addTearDown(radar.dispose);
      await radar.load();

      // Capture source once (matching HomePage _radarSlot reuse across taps).
      final source = radar.collectionPlaybackSource(
        providerId: 'qq-music',
        sourceId: 'home-radar',
      );
      final queue = _buildQueue();
      addTearDown(queue.dispose);

      await queue.replaceAndPlayCollection(source, 0);
      await _drain();
      expect(queue.tracks, hasLength(51));

      // Play another track, then replay the same Radar source!
      await queue.replaceAndPlay([_track('other')], 0);
      await queue.replaceAndPlayCollection(source, 0);
      await _drain();

      // Must STILL fill all 51 tracks (and reuse cached session pages with 0 extra fetches).
      expect(queue.tracks, hasLength(51));
      expect(gateway.requestedPages, [1, 2, 3, 4, 5, 6]);
    });

    test('Bug 5b: RadarController handles throwing operation.run() without stranding isLoadingMore', () async {
      final gateway = _CustomRadarGateway((page) {
        if (page == 1) {
          return _ImmediateRadarOp(
            RadarTrackPageResult(
              page: 1,
              hasMore: true,
              tracks: [_track('seed')],
            ),
          );
        }
        return _ThrowingRadarOp();
      });
      final radar = RadarController(
        gateway,
        initialPrefetchTarget: 30,
        maxInitialPrefetchPages: 3,
      );
      addTearDown(radar.dispose);

      await radar.load();
      expect(radar.isLoadingMore, isFalse);
      expect(radar.appendFailure, RadarFailure.coreUnavailable);
    });
  });
}

class _ThrowingRadarOp implements RadarTrackPageLoadOperation {
  @override
  bool cancel() => true;

  @override
  Future<RadarTrackPageResult> run() => Future.error(StateError('boom'));
}

PlaylistTrackSummary _track(String id) => PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:$id',
  title: 'Radar $id',
  artistNames: const ['Radar Artist'],
);

List<PlaylistTrackSummary> _batch(int page, int count) =>
    List.generate(count, (i) => _track('p$page-$i'), growable: false);

Future<void> _drain() async {
  for (var i = 0; i < 16; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

QueuePlaybackController _buildQueue({
  Future<MediaResolutionResult>? mediaResultFuture,
  List<_ScriptedAudioSession>? sessions,
}) => QueuePlaybackController(
  _ModeAwareQueueGateway(),
  TrackPlaybackController(
    _ScriptedMediaGateway(mediaResultFuture),
    ForegroundPlaybackController(_ScriptedAudioEngine(sessions)),
  ),
);

class _DynamicRadarGateway implements RadarGateway {
  _DynamicRadarGateway(this._handler);

  final RadarTrackPageResult Function(int page, int callNumber) _handler;
  final List<int> requestedPages = [];

  @override
  RadarTrackPageLoadOperation beginLoad({required int page}) {
    requestedPages.add(page);
    return _ImmediateRadarOp(_handler(page, requestedPages.length));
  }
}

class _CustomRadarGateway implements RadarGateway {
  _CustomRadarGateway(this._factory);
  final RadarTrackPageLoadOperation Function(int page) _factory;

  @override
  RadarTrackPageLoadOperation beginLoad({required int page}) => _factory(page);
}

class _ImmediateRadarOp implements RadarTrackPageLoadOperation {
  const _ImmediateRadarOp(this.result);
  final RadarTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<RadarTrackPageResult> run() async => result;
}

class _TrackedPendingRadarOp implements RadarTrackPageLoadOperation {
  _TrackedPendingRadarOp(this.future, {required this.onCancel});
  final Future<RadarTrackPageResult> future;
  final void Function() onCancel;

  @override
  bool cancel() {
    onCancel();
    return true;
  }

  @override
  Future<RadarTrackPageResult> run() => future;
}

class _ModeAwareQueueGateway
    implements PlaybackQueueGateway, PlaybackQueueBatchGateway {
  List<PlaylistTrackSummary> _tracks = const [];
  int? _current;
  PlaybackOrder _order = PlaybackOrder.sequential;
  PlaybackRepeatMode _repeat = PlaybackRepeatMode.off;

  PlaybackQueueResult _ok({
    bool changed = false,
    PlaybackCompletionAction? completionAction,
  }) => PlaybackQueueResult(
    snapshot: PlaybackQueueSnapshot(
      tracks: List.unmodifiable(_tracks),
      currentIndex: _current,
      hasPrevious:
          _current != null &&
          (_current! > 0 || _repeat == PlaybackRepeatMode.all),
      hasNext:
          _current != null &&
          (_current! + 1 < _tracks.length || _repeat == PlaybackRepeatMode.all),
      order: _order,
      repeatMode: _repeat,
    ),
    playbackRequested: changed,
    completionAction: completionAction,
  );

  @override
  PlaybackQueueResult snapshot() => _ok();

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    int? currentIndex,
  }) {
    _tracks = List.of(tracks);
    _current = currentIndex;
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) {
    _tracks = [..._tracks, track];
    final changed = _current == null;
    _current ??= 0;
    return _ok(changed: changed);
  }

  @override
  PlaybackQueueResult extend(List<PlaylistTrackSummary> tracks) {
    _tracks = [..._tracks, ...tracks];
    return _ok();
  }

  @override
  PlaybackQueueResult extendAndAdvanceFromTerminal(
    List<PlaylistTrackSummary> tracks,
  ) {
    final next = _tracks.length;
    _tracks = [..._tracks, ...tracks];
    _current = next;
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult select(int index) {
    _current = index;
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult advance() {
    if (_current == null || _tracks.isEmpty) return _ok();
    if (_current! + 1 < _tracks.length) {
      _current = _current! + 1;
      return _ok(changed: true);
    }
    if (_repeat == PlaybackRepeatMode.all) {
      _current = 0;
      return _ok(changed: true);
    }
    return _ok();
  }

  @override
  PlaybackQueueResult rewind() {
    if (_current == null || _tracks.isEmpty) return _ok();
    if (_current! > 0) {
      _current = _current! - 1;
      return _ok(changed: true);
    }
    if (_repeat == PlaybackRepeatMode.all) {
      _current = _tracks.length - 1;
      return _ok(changed: true);
    }
    return _ok();
  }

  @override
  PlaybackQueueResult completeCurrent() {
    if (_current != null && _repeat == PlaybackRepeatMode.one) {
      return _ok(completionAction: PlaybackCompletionAction.replayCurrent);
    }
    final next = advance();
    return PlaybackQueueResult(
      snapshot: next.snapshot,
      playbackRequested: next.playbackRequested,
      completionAction: next.playbackRequested
          ? PlaybackCompletionAction.playCurrent
          : PlaybackCompletionAction.none,
    );
  }

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) {
    _order = order;
    return _ok();
  }

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) {
    _repeat = repeatMode;
    return _ok();
  }

  @override
  PlaybackQueueResult remove(int index) {
    final list = List<PlaylistTrackSummary>.of(_tracks)..removeAt(index);
    _tracks = list;
    _current = list.isEmpty ? null : 0;
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult clear() {
    _tracks = const [];
    _current = null;
    return _ok(changed: true);
  }
}

class _ScriptedMediaGateway implements MediaResolutionGateway {
  _ScriptedMediaGateway(this.future);
  final Future<MediaResolutionResult>? future;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => _ScriptedMediaOp(
    future ??
        Future.value(
          MediaResolutionResult(
            source: ResolvedPlaybackSource(
              uri: Uri.parse('https://example.invalid/$opaqueTrackId.mp3'),
              format: PlaybackAudioFormat.mp3,
              quality: PlaybackAudioQuality.standard,
              validForSeconds: 300,
            ),
          ),
        ),
  );
}

class _ScriptedMediaOp implements MediaResolutionOperation {
  _ScriptedMediaOp(this.future);
  final Future<MediaResolutionResult> future;

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() => future;
}

class _ScriptedAudioEngine implements ForegroundAudioEngine {
  _ScriptedAudioEngine(List<_ScriptedAudioSession>? sessions)
    : _sessions = List<_ScriptedAudioSession>.of(sessions ?? const []);

  final List<_ScriptedAudioSession> _sessions;

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) async =>
      _sessions.isNotEmpty ? _sessions.removeAt(0) : _ScriptedAudioSession();

  @override
  Future<void> dispose() async {}
}

class _ScriptedAudioSession implements ForegroundAudioSession {
  final _states = StreamController<ForegroundAudioState>.broadcast();
  final _failures = StreamController<ForegroundAudioFailure>.broadcast();
  final _positions = StreamController<int>.broadcast();

  void emitState(ForegroundAudioState state) => _states.add(state);

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> play() async {
    _states.add(ForegroundAudioState.playing);
  }

  @override
  Future<void> pause() async {
    _states.add(ForegroundAudioState.paused);
  }

  @override
  Future<void> seekToMs(int positionMs) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {
    _states.add(ForegroundAudioState.stopped);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _failures.close();
    await _positions.close();
  }
}
