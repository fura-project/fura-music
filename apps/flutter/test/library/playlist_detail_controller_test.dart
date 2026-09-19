import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

void main() {
  const playlist = UserPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'favorite:8001',
    title: 'Synthetic playlist',
  );

  test('maps first-page content, empty, and pagination metadata', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(playlist, gateway);

    final content = controller.load();
    gateway.complete(
      0,
      const PlaylistTrackPageResult(
        total: 2,
        totalIsExact: false,
        hasMore: true,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:opaque',
            title: 'Synthetic track',
            artistNames: ['Artist'],
          ),
        ],
      ),
    );
    await content;
    expect(controller.stage, PlaylistDetailStage.content);
    expect(controller.total, 2);
    expect(controller.totalIsExact, isFalse);
    expect(controller.hasMore, isTrue);
    expect(controller.tracks.single.title, 'Synthetic track');
    expect(gateway.requests.single.offset, 0);
    expect(gateway.requests.single.size, PlaylistDetailController.pageSize);

    final more = controller.loadMore();
    gateway.complete(
      1,
      const PlaylistTrackPageResult(
        offset: 1,
        total: 3,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:opaque',
            title: 'Duplicate track',
            artistNames: ['Artist'],
          ),
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:second',
            title: 'Second track',
            artistNames: ['Artist'],
          ),
        ],
      ),
    );
    await more;
    expect(controller.tracks.map((track) => track.title), [
      'Synthetic track',
      'Second track',
    ]);
    expect(controller.hasMore, isFalse);
    expect(controller.totalIsExact, isTrue);
    expect(gateway.requests[1].offset, 1);

    final empty = controller.load();
    gateway.complete(2, const PlaylistTrackPageResult());
    await empty;
    expect(controller.stage, PlaylistDetailStage.empty);
    controller.dispose();
  });

  test(
    'keeps transient failure retryable and rejects a wrong page offset',
    () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(playlist, gateway);

      final first = controller.load();
      gateway.complete(
        0,
        const PlaylistTrackPageResult(failure: UserLibraryFailure.network),
      );
      await first;
      expect(controller.stage, PlaylistDetailStage.error);
      expect(controller.canRetry, isTrue);

      final second = controller.load();
      gateway.complete(1, const PlaylistTrackPageResult(offset: 100));
      await second;
      expect(controller.stage, PlaylistDetailStage.error);
      expect(controller.failure, UserLibraryFailure.invalidResponse);

      final nonAdvancing = controller.load();
      gateway.complete(
        2,
        const PlaylistTrackPageResult(total: 1, hasMore: true),
      );
      await nonAdvancing;
      expect(controller.stage, PlaylistDetailStage.error);
      expect(controller.failure, UserLibraryFailure.invalidResponse);
      controller.dispose();
    },
  );

  test('retains loaded rows after a retryable append failure', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(playlist, gateway);
    final first = controller.load();
    gateway.complete(
      0,
      const PlaylistTrackPageResult(
        total: 2,
        hasMore: true,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:first',
            title: 'First track',
            artistNames: [],
          ),
        ],
      ),
    );
    await first;

    final more = controller.loadMore();
    gateway.complete(
      1,
      const PlaylistTrackPageResult(
        offset: 1,
        failure: UserLibraryFailure.network,
      ),
    );
    await more;
    expect(controller.stage, PlaylistDetailStage.content);
    expect(controller.tracks.single.title, 'First track');
    expect(controller.appendFailure, UserLibraryFailure.network);
    expect(controller.canRetryMore, isTrue);

    final invalidPage = controller.loadMore();
    gateway.complete(
      2,
      const PlaylistTrackPageResult(
        offset: 99,
        total: 2,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:second',
            title: 'Second track',
            artistNames: [],
          ),
        ],
      ),
    );
    await invalidPage;
    expect(controller.tracks.single.title, 'First track');
    expect(controller.appendFailure, UserLibraryFailure.invalidResponse);
    controller.dispose();
  });

  test(
    'does not invent continuation when provider has-more is false',
    () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(playlist, gateway);
      final first = controller.load();
      gateway.complete(
        0,
        PlaylistTrackPageResult(total: 2, tracks: _tracks(0, 1)),
      );
      await first;

      expect(controller.stage, PlaylistDetailStage.error);
      expect(controller.failure, UserLibraryFailure.invalidResponse);
      await controller.loadMore();
      expect(gateway.requests.map((request) => request.offset), [0]);
      expect(controller.tracks, isEmpty);
      expect(controller.hasMore, isFalse);
      controller.dispose();
    },
  );

  test(
    'refresh retains the complete paged snapshot after transient failure',
    () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(playlist, gateway);
      final initial = controller.load();
      gateway.complete(
        0,
        const PlaylistTrackPageResult(
          total: 3,
          hasMore: true,
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:current',
              title: 'Current track',
              artistNames: [],
            ),
          ],
        ),
      );
      await initial;

      final refresh = controller.refresh();
      expect(controller.stage, PlaylistDetailStage.content);
      expect(controller.tracks.single.title, 'Current track');
      expect(controller.total, 3);
      expect(controller.hasMore, isTrue);
      expect(controller.isRefreshing, isTrue);
      expect(controller.isLoading, isTrue);
      expect(controller.canLoadMore, isFalse);

      gateway.complete(
        1,
        const PlaylistTrackPageResult(failure: UserLibraryFailure.network),
      );
      await refresh;

      expect(controller.stage, PlaylistDetailStage.content);
      expect(controller.tracks.single.title, 'Current track');
      expect(controller.total, 3);
      expect(controller.hasMore, isTrue);
      expect(controller.refreshFailure, UserLibraryFailure.network);
      expect(controller.canRetryRefresh, isTrue);
      expect(controller.canLoadMore, isTrue);

      final retry = controller.refresh();
      gateway.complete(
        2,
        const PlaylistTrackPageResult(
          total: 1,
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:fresh',
              title: 'Fresh track',
              artistNames: [],
            ),
          ],
        ),
      );
      await retry;

      expect(controller.tracks.single.title, 'Fresh track');
      expect(controller.total, 1);
      expect(controller.hasMore, isFalse);
      expect(controller.refreshFailure, isNull);

      controller.dispose();
    },
  );

  test(
    'full loading drains every page beyond the old 300 Track boundary',
    () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(
        playlist,
        gateway,
        loadAllPageInterval: Duration.zero,
      );
      final initial = controller.load();
      gateway.complete(
        0,
        PlaylistTrackPageResult(
          total: 350,
          hasMore: true,
          tracks: _tracks(0, 100),
        ),
      );
      await initial;

      final all = controller.loadAll();
      expect(controller.isLoadingAll, isTrue);
      expect(gateway.requests.last.offset, 100);
      gateway.complete(
        1,
        PlaylistTrackPageResult(
          offset: 100,
          total: 350,
          hasMore: true,
          tracks: _tracks(100, 100),
        ),
      );
      await _flushTasks();
      expect(gateway.requests.last.offset, 200);
      gateway.complete(
        2,
        PlaylistTrackPageResult(
          offset: 200,
          total: 350,
          hasMore: true,
          tracks: _tracks(200, 100),
        ),
      );
      await _flushTasks();
      expect(gateway.requests.last.offset, 300);
      gateway.complete(
        3,
        PlaylistTrackPageResult(
          offset: 300,
          total: 350,
          tracks: _tracks(300, 50),
        ),
      );
      await all;

      expect(gateway.requests.map((request) => request.offset), [
        0,
        100,
        200,
        300,
      ]);
      expect(controller.tracks, hasLength(350));
      expect(controller.tracks.last.title, 'Track 349');
      expect(controller.hasMore, isFalse);
      expect(controller.isLoadingAll, isFalse);
      controller.dispose();
    },
  );

  test(
    'cancelling full loading stops after the current bounded page',
    () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(
        playlist,
        gateway,
        loadAllPageInterval: Duration.zero,
      );
      final initial = controller.load();
      gateway.complete(
        0,
        PlaylistTrackPageResult(
          total: 400,
          hasMore: true,
          tracks: _tracks(0, 100),
        ),
      );
      await initial;

      final all = controller.loadAll();
      expect(gateway.requests.last.offset, 100);
      controller.cancelLoadAll();
      expect(controller.isLoadingAll, isFalse);
      gateway.complete(
        1,
        PlaylistTrackPageResult(
          offset: 100,
          total: 400,
          hasMore: true,
          tracks: _tracks(100, 100),
        ),
      );
      await all;

      expect(gateway.requests.map((request) => request.offset), [0, 100]);
      expect(controller.tracks, hasLength(200));
      expect(controller.hasMore, isTrue);
      controller.dispose();
    },
  );

  test('full loading uses the low-latency successful-page cadence', () async {
    final gateway = _FakeDetailGateway();
    final delays = <Duration>[];
    final controller = PlaylistDetailController(
      playlist,
      gateway,
      delay: (duration) async => delays.add(duration),
    );
    final initial = controller.load();
    gateway.complete(
      0,
      PlaylistTrackPageResult(
        total: 201,
        hasMore: true,
        tracks: _tracks(0, 100),
      ),
    );
    await initial;

    final all = controller.loadAll();
    gateway.complete(
      1,
      PlaylistTrackPageResult(
        offset: 100,
        total: 201,
        hasMore: true,
        tracks: _tracks(100, 100),
      ),
    );
    await _flushTasks();
    gateway.complete(
      2,
      PlaylistTrackPageResult(offset: 200, total: 201, tracks: _tracks(200, 1)),
    );
    await all;

    expect(delays, [const Duration(milliseconds: 180)]);
    expect(controller.tracks, hasLength(201));
    controller.dispose();
  });

  test('full loading stops on a permanent failure and resumes from the failed offset', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(
      playlist,
      gateway,
      loadAllPageInterval: Duration.zero,
    );
    final initial = controller.load();
    gateway.complete(
      0,
      PlaylistTrackPageResult(total: 3, hasMore: true, tracks: _tracks(0, 1)),
    );
    await initial;

    final failing = controller.loadAll();
    gateway.complete(
      1,
      const PlaylistTrackPageResult(
        failure: UserLibraryFailure.invalidResponse,
      ),
    );
    await failing;
    expect(controller.tracks, hasLength(1));
    expect(controller.appendFailure, UserLibraryFailure.invalidResponse);
    expect(controller.isLoadingAll, isFalse);

    final retry = controller.loadAll();
    gateway.complete(
      2,
      PlaylistTrackPageResult(offset: 1, total: 3, tracks: _tracks(1, 2)),
    );
    await retry;

    expect(gateway.requests.map((request) => request.offset), [0, 1, 1]);
    expect(controller.tracks, hasLength(3));
    expect(controller.appendFailure, isNull);
    expect(controller.hasMore, isFalse);
    controller.dispose();
  });

  test('full loading paces pages and backs off before retrying a transient boundary', () async {
    final gateway = _FakeDetailGateway();
    final delays = <Duration>[];
    final controller = PlaylistDetailController(
      playlist,
      gateway,
      loadAllPageInterval: const Duration(milliseconds: 100),
      postTransientPageInterval: const Duration(milliseconds: 500),
      transientRetryDelays: const [Duration(seconds: 1)],
      delay: (duration) async => delays.add(duration),
    );
    final initial = controller.load();
    gateway.complete(
      0,
      PlaylistTrackPageResult(
        total: 400,
        hasMore: true,
        tracks: _tracks(0, 100),
      ),
    );
    await initial;

    final all = controller.loadAll();
    gateway.complete(
      1,
      PlaylistTrackPageResult(
        offset: 100,
        total: 400,
        hasMore: true,
        tracks: _tracks(100, 100),
      ),
    );
    await _flushTasks();
    gateway.complete(
      2,
      const PlaylistTrackPageResult(
        failure: UserLibraryFailure.serviceUnavailable,
      ),
    );
    await _flushTasks();
    expect(gateway.requests.last.offset, 200);
    gateway.complete(
      3,
      PlaylistTrackPageResult(
        offset: 200,
        total: 400,
        hasMore: true,
        tracks: _tracks(200, 100),
      ),
    );
    await _flushTasks();
    gateway.complete(
      4,
      PlaylistTrackPageResult(
        offset: 300,
        total: 400,
        tracks: _tracks(300, 100),
      ),
    );
    await all;

    expect(gateway.requests.map((request) => request.offset), [
      0,
      100,
      200,
      200,
      300,
    ]);
    expect(delays, [
      const Duration(milliseconds: 100),
      const Duration(seconds: 1),
      const Duration(milliseconds: 500),
    ]);
    expect(controller.tracks, hasLength(400));
    expect(controller.appendFailure, isNull);
    expect(controller.hasMore, isFalse);
    controller.dispose();
  });

  test('an omitted page advances search to later usable tracks', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(
      playlist,
      gateway,
      loadAllPageInterval: Duration.zero,
    );
    final initial = controller.load();
    gateway.complete(
      0,
      PlaylistTrackPageResult(
        total: 201,
        hasMore: true,
        tracks: _tracks(0, 100),
      ),
    );
    await initial;

    final all = controller.loadAll();
    gateway.complete(
      1,
      const PlaylistTrackPageResult(
        offset: 100,
        nextOffset: 200,
        total: 201,
        hasMore: true,
        omittedTrackCount: 100,
      ),
    );
    await _flushTasks();
    gateway.complete(
      2,
      PlaylistTrackPageResult(offset: 200, total: 201, tracks: _tracks(200, 1)),
    );
    await all;

    expect(gateway.requests.map((request) => request.offset), [0, 100, 200]);
    expect(controller.processedCount, 201);
    expect(controller.omittedTrackCount, 100);
    expect(controller.tracks, hasLength(101));
    expect(controller.tracks.last.title, 'Track 200');
    controller.dispose();
  });

  test('refresh clears loaded tracks after credential rejection', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(playlist, gateway);
    final initial = controller.load();
    gateway.complete(
      0,
      const PlaylistTrackPageResult(
        total: 1,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:private',
            title: 'Private track',
            artistNames: [],
          ),
        ],
      ),
    );
    await initial;

    final refresh = controller.refresh();
    gateway.complete(
      1,
      const PlaylistTrackPageResult(
        failure: UserLibraryFailure.credentialRejected,
      ),
    );
    await refresh;

    expect(controller.stage, PlaylistDetailStage.credentialRejected);
    expect(controller.tracks, isEmpty);
    expect(controller.total, 0);
    expect(controller.refreshFailure, isNull);

    controller.dispose();
  });

  test(
    'replacement detail refresh cancels and suppresses its late result',
    () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(playlist, gateway);
      final initial = controller.load();
      gateway.complete(0, const PlaylistTrackPageResult());
      await initial;

      final firstRefresh = controller.refresh();
      final replacementRefresh = controller.refresh();
      expect(gateway.operations[1].cancelCalls, 1);

      gateway.complete(
        2,
        const PlaylistTrackPageResult(
          total: 1,
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:replacement',
              title: 'Replacement track',
              artistNames: [],
            ),
          ],
        ),
      );
      await replacementRefresh;

      gateway.complete(
        1,
        const PlaylistTrackPageResult(
          total: 1,
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:late',
              title: 'Late track',
              artistNames: [],
            ),
          ],
        ),
      );
      await firstRefresh;

      expect(controller.tracks.single.title, 'Replacement track');
      controller.dispose();
    },
  );

  test('restart and dispose cancel and suppress late results', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(playlist, gateway);

    final first = controller.load();
    final second = controller.load();
    expect(gateway.operations.first.cancelCalls, 1);
    gateway.complete(1, const PlaylistTrackPageResult());
    await second;
    gateway.complete(
      0,
      const PlaylistTrackPageResult(
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'late',
            title: 'Late track',
            artistNames: [],
          ),
        ],
      ),
    );
    await first;
    expect(controller.stage, PlaylistDetailStage.empty);

    final third = controller.load();
    controller.dispose();
    expect(gateway.operations.last.cancelCalls, 1);
    gateway.complete(2, const PlaylistTrackPageResult());
    await third;
  });

  group('viewport prefetch scheduling', () {
    late _FakeDetailGateway gateway;
    late PlaylistDetailController controller;

    Future<void> prime({Future<void> Function(Duration)? delay}) async {
      gateway = _FakeDetailGateway();
      controller = PlaylistDetailController(
        playlist,
        gateway,
        delay: delay ?? (_) async {},
      );
      final initial = controller.load();
      gateway.complete(
        0,
        PlaylistTrackPageResult(
          total: 1000,
          hasMore: true,
          tracks: _tracks(0, 100),
        ),
      );
      await initial;
    }

    void completePage(int request, int offset, {int count = 100}) {
      gateway.complete(
        request,
        PlaylistTrackPageResult(
          offset: offset,
          total: 1000,
          hasMore: offset + count < 1000,
          tracks: _tracks(offset, count),
        ),
      );
    }

    tearDown(() => controller.dispose());

    test(
      'one horizon serializes two pages and coalesces repeated demand',
      () async {
        await prime();
        controller.prefetchTo(290);
        controller.prefetchTo(295);
        final joined = controller.loadMore();
        expect(gateway.requests.map((r) => r.offset), [0, 100]);
        completePage(1, 100);
        await _flushTasks();
        expect(gateway.requests.map((r) => r.offset), [0, 100, 200]);
        completePage(2, 200);
        await joined;
        expect(controller.tracks, hasLength(300));
        expect(controller.hasMore, isTrue);
        expect(gateway.requests, hasLength(3));
        controller.prefetchTo(290);
        await _flushTasks();
        expect(gateway.requests, hasLength(3));
        expect(gateway.requests.every((r) => r.size == 100), isTrue);
      },
    );

    test('ordinary lookahead stops after one page', () async {
      await prime();
      controller.prefetchTo(125);
      completePage(1, 100);
      await _flushTasks();
      expect(controller.tracks, hasLength(200));
      expect(gateway.requests, hasLength(2));
    });

    test(
      'short and omitted pages cannot turn scrolling into a full drain',
      () async {
        await prime();
        controller.prefetchTo(9999);
        completePage(1, 100, count: 1);
        await _flushTasks();
        gateway.complete(
          2,
          const PlaylistTrackPageResult(
            offset: 101,
            nextOffset: 103,
            omittedTrackCount: 2,
            total: 1000,
            hasMore: true,
          ),
        );
        await _flushTasks();
        expect(gateway.requests.map((r) => r.offset), [0, 100, 101]);
        expect(controller.processedCount, 103);
        expect(controller.tracks, hasLength(101));
        expect(controller.hasMore, isTrue);
      },
    );

    test(
      'returning upward cancels pending pages but keeps the in-flight result',
      () async {
        await prime();
        controller.prefetchTo(300);
        controller.cancelPrefetch();
        completePage(1, 100);
        await _flushTasks();
        expect(gateway.requests, hasLength(2));
        expect(gateway.operations[1].cancelCalls, 0);
        expect(controller.tracks, hasLength(200));
        controller.prefetchTo(100);
        await _flushTasks();
        expect(gateway.requests, hasLength(2));
      },
    );

    test('search promotes in-flight browse work and scroll cannot skip its cadence', () async {
      final cooldown = Completer<void>();
      await prime(delay: (_) => cooldown.future);
      controller.prefetchTo(150);
      final search = controller.loadAll();
      expect(controller.isLoadingAll, isTrue);
      expect(gateway.requests, hasLength(2));
      completePage(1, 100);
      await _flushTasks();
      controller.prefetchTo(400);
      final joined = controller.loadMore();
      await _flushTasks();
      expect(gateway.requests, hasLength(2));
      cooldown.complete();
      await _flushTasks();
      expect(gateway.requests.map((r) => r.offset), [0, 100, 200]);
      controller.cancelLoadAll();
      completePage(2, 200);
      await Future.wait([search, joined]);
      expect(gateway.requests, hasLength(3));
      expect(controller.tracks, hasLength(300));
    });

    test(
      'stopping and restarting search during backoff keeps one retry owner',
      () async {
        final backoff = Completer<void>();
        await prime(delay: (_) => backoff.future);
        final search = controller.loadAll();
        gateway.complete(
          1,
          const PlaylistTrackPageResult(
            failure: UserLibraryFailure.serviceUnavailable,
          ),
        );
        await _flushTasks();
        controller.cancelLoadAll();
        controller.prefetchTo(300);
        final restarted = controller.loadAll();
        final manual = controller.loadMore();
        expect(gateway.requests, hasLength(2));
        backoff.complete();
        await _flushTasks();
        expect(gateway.requests.map((r) => r.offset), [0, 100, 100]);
        controller.cancelLoadAll();
        completePage(2, 100);
        await Future.wait([search, restarted, manual]);
        expect(controller.tracks, hasLength(200));
        expect(gateway.requests, hasLength(3));
      },
    );

    test('scroll stops at failure until an explicit retry succeeds', () async {
      await prime();
      controller.prefetchTo(300);
      gateway.complete(
        1,
        const PlaylistTrackPageResult(failure: UserLibraryFailure.network),
      );
      await _flushTasks();
      controller.prefetchTo(300);
      controller.prefetchTo(400);
      await _flushTasks();
      expect(gateway.requests, hasLength(2));
      expect(controller.tracks, hasLength(100));
      final retry = controller.loadMore();
      completePage(2, 100);
      await retry;
      expect(gateway.requests.map((r) => r.offset), [0, 100, 100]);
      expect(controller.appendFailure, isNull);
    });

    test('refresh supersedes prefetch and its late page cannot change the new snapshot', () async {
      await prime();
      controller.prefetchTo(300);
      final refresh = controller.refresh();
      expect(gateway.operations[1].cancelCalls, 1);
      gateway.complete(
        2,
        PlaylistTrackPageResult(total: 1, tracks: _tracks(900, 1)),
      );
      await refresh;
      completePage(1, 100);
      await _flushTasks();
      expect(controller.tracks.single.title, 'Track 900');
      expect(controller.processedCount, 1);
      expect(gateway.requests, hasLength(3));
    });

    test('dispose during cooldown suppresses queued pages and notifications', () async {
      final cooldown = Completer<void>();
      await prime(delay: (_) => cooldown.future);
      controller.prefetchTo(300);
      completePage(1, 100);
      await _flushTasks();
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.dispose();
      cooldown.complete();
      await _flushTasks();
      expect(gateway.requests, hasLength(2));
      expect(notifications, 0);
      // Keep the group teardown independent of this explicitly disposed owner.
      controller = PlaylistDetailController(playlist, gateway);
    });
  });

  group('bounded collection search', () {
    test('one demand window fetches at most two raw pages', () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(
        playlist,
        gateway,
        loadAllPageInterval: Duration.zero,
      );
      final initial = controller.load();
      gateway.complete(
        0,
        PlaylistTrackPageResult(
          nextOffset: 100,
          total: 1000,
          hasMore: true,
          tracks: _tracks(0, 100),
        ),
      );
      await initial;

      final search = controller.requestSearchWindow(
        hasEnoughMatches: () => false,
      );
      gateway.complete(
        1,
        PlaylistTrackPageResult(
          offset: 100,
          nextOffset: 200,
          total: 1000,
          hasMore: true,
          tracks: _tracks(100, 100),
        ),
      );
      await _flushTasks();
      gateway.complete(
        2,
        PlaylistTrackPageResult(
          offset: 200,
          nextOffset: 300,
          total: 1000,
          hasMore: true,
          tracks: _tracks(200, 100),
        ),
      );
      await search;

      expect(gateway.requests.map((request) => request.offset), [0, 100, 200]);
      expect(controller.searchScanStage, CollectionSearchScanStage.paused);
      expect(controller.processedCount, 300);
      controller.dispose();
    });

    test('dedup never changes the provider continuation cursor', () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(playlist, gateway);
      final initial = controller.load();
      gateway.complete(
        0,
        PlaylistTrackPageResult(
          nextOffset: 100,
          total: 300,
          hasMore: true,
          tracks: _tracks(0, 100),
        ),
      );
      await initial;

      final more = controller.loadMore();
      gateway.complete(
        1,
        PlaylistTrackPageResult(
          offset: 100,
          nextOffset: 200,
          total: 300,
          hasMore: true,
          tracks: _tracks(99, 100),
        ),
      );
      await more;

      expect(controller.tracks, hasLength(199));
      expect(controller.processedCount, 200);
      final next = controller.loadMore();
      expect(gateway.requests.last.offset, 200);
      gateway.complete(
        2,
        PlaylistTrackPageResult(
          offset: 200,
          nextOffset: 300,
          total: 300,
          tracks: _tracks(200, 100),
        ),
      );
      await next;
      controller.dispose();
    });

    test('an in-flight browse page counts against the search window', () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(
        playlist,
        gateway,
        loadAllPageInterval: Duration.zero,
      );
      final initial = controller.load();
      gateway.complete(
        0,
        PlaylistTrackPageResult(
          nextOffset: 100,
          total: 1000,
          hasMore: true,
          tracks: _tracks(0, 100),
        ),
      );
      await initial;

      controller.prefetchTo(150);
      expect(gateway.requests.map((request) => request.offset), [0, 100]);
      final search = controller.requestSearchWindow(
        hasEnoughMatches: () => false,
      );
      gateway.complete(
        1,
        PlaylistTrackPageResult(
          offset: 100,
          nextOffset: 200,
          total: 1000,
          hasMore: true,
          tracks: _tracks(100, 100),
        ),
      );
      await _flushTasks();
      gateway.complete(
        2,
        PlaylistTrackPageResult(
          offset: 200,
          nextOffset: 300,
          total: 1000,
          hasMore: true,
          tracks: _tracks(200, 100),
        ),
      );
      await search;

      expect(gateway.requests.map((request) => request.offset), [0, 100, 200]);
      expect(controller.searchScanStage, CollectionSearchScanStage.paused);
      controller.dispose();
    });
  });

  test('maps credential rejection to a sign-in state', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(playlist, gateway);
    final load = controller.load();
    gateway.complete(
      0,
      const PlaylistTrackPageResult(
        failure: UserLibraryFailure.credentialRejected,
      ),
    );
    await load;
    expect(controller.stage, PlaylistDetailStage.credentialRejected);
    expect(controller.canRetry, isFalse);
    controller.dispose();
  });

  test('detached collection continuation survives page disposal', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(playlist, gateway);
    final load = controller.load();
    gateway.complete(
      0,
      PlaylistTrackPageResult(
        offset: 0,
        nextOffset: 1,
        total: 2,
        hasMore: true,
        tracks: _tracks(0, 1),
      ),
    );
    await load;
    final source = controller.collectionPlaybackSource(
      sourceId: 'playlist:test',
      providerId: 'qq-music',
    );
    controller.dispose();

    final next = source.loader(source.nextCursor).run();
    gateway.complete(
      1,
      PlaylistTrackPageResult(
        offset: 1,
        nextOffset: 2,
        total: 2,
        tracks: _tracks(1, 1),
      ),
    );
    final page = await next;

    expect(page.requestCursor, 1);
    expect(page.nextCursor, 2);
    expect(page.hasMore, isFalse);
    expect(page.tracks.single.opaqueId, 'track:1');
    expect(gateway.requests.map((request) => request.offset), [0, 1]);
  });
}

class _Request {
  const _Request(this.playlist, this.offset, this.size);
  final UserPlaylistSummary playlist;
  final int offset;
  final int size;
}

List<PlaylistTrackSummary> _tracks(int start, int count) => List.generate(
  count,
  (index) => PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:${start + index}',
    title: 'Track ${start + index}',
    artistNames: const ['Artist'],
  ),
  growable: false,
);

Future<void> _flushTasks() => Future<void>.delayed(Duration.zero);

class _FakeDetailGateway implements PlaylistDetailGateway {
  final List<Completer<PlaylistTrackPageResult>> _results = [];
  final List<_FakeDetailOperation> operations = [];
  final List<_Request> requests = [];

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    final result = Completer<PlaylistTrackPageResult>();
    _results.add(result);
    requests.add(_Request(playlist, offset, size));
    final operation = _FakeDetailOperation(result.future);
    operations.add(operation);
    return operation;
  }

  void complete(int index, PlaylistTrackPageResult result) {
    // Legacy fixtures describe the synthetic raw window with their explicit
    // row and omission counts. Production results must always carry the
    // Provider-owned next offset; strict cursor tests pass it directly.
    final completed = result.nextOffset >= 0
        ? result
        : PlaylistTrackPageResult(
            offset: result.offset,
            nextOffset:
                result.offset + result.tracks.length + result.omittedTrackCount,
            total: result.total,
            totalIsExact: result.totalIsExact,
            hasMore: result.hasMore,
            omittedTrackCount: result.omittedTrackCount,
            tracks: result.tracks,
            failure: result.failure,
          );
    _results[index].complete(completed);
  }
}

class _FakeDetailOperation implements PlaylistTrackPageLoadOperation {
  _FakeDetailOperation(this._result);
  final Future<PlaylistTrackPageResult> _result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<PlaylistTrackPageResult> run() => _result;
}
