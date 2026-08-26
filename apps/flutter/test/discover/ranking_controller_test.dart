import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/ranking_controller.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

void main() {
  const ranking = RankingSummary(
    providerId: 'qq-music',
    opaqueId: 'ranking:62001',
    title: 'Synthetic ranking',
  );
  const first = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:1',
    title: 'First Track',
    artistNames: ['Artist'],
  );
  const second = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:2',
    title: 'Second Track',
    artistNames: ['Artist'],
  );

  test(
    'group load retries and replacement suppresses stale completion',
    () async {
      final late = Completer<RankingGroupResult>();
      final pending = _PendingGroupOperation(late.future);
      final gateway = _ScriptedRankingGateway(
        groupOperations: [
          pending,
          const _ImmediateGroupOperation(
            RankingGroupResult(
              groups: [
                RankingGroup(title: 'Group', rankings: [ranking]),
              ],
            ),
          ),
        ],
      );
      final controller = RankingGroupController(gateway);

      final firstLoad = controller.load();
      await pending.started.future;
      await controller.load();
      expect(pending.cancelCalls, 1);
      expect(controller.stage, RankingGroupStage.content);
      expect(controller.groups.single.rankings.single, same(ranking));
      late.complete(const RankingGroupResult(failure: RankingFailure.network));
      await firstLoad;
      expect(controller.stage, RankingGroupStage.content);
      controller.dispose();
    },
  );

  test('group disposal cancels in-flight work', () async {
    final result = Completer<RankingGroupResult>();
    final operation = _PendingGroupOperation(result.future);
    final controller = RankingGroupController(
      _ScriptedRankingGateway(groupOperations: [operation]),
    );
    final load = controller.load();
    await operation.started.future;
    controller.dispose();
    expect(operation.cancelCalls, 1);
    result.complete(const RankingGroupResult());
    await load;
  });

  test(
    'Track controller paginates, deduplicates, and retries append',
    () async {
      final gateway = _ScriptedRankingGateway(
        trackOperations: [
          const _ImmediateTrackOperation(
            RankingTrackPageResult(
              ranking: ranking,
              total: 3,
              hasMore: true,
              tracks: [first],
            ),
          ),
          const _ImmediateTrackOperation(
            RankingTrackPageResult(failure: RankingFailure.network),
          ),
          const _ImmediateTrackOperation(
            RankingTrackPageResult(
              ranking: ranking,
              offset: 1,
              total: 3,
              tracks: [first, second],
            ),
          ),
        ],
      );
      final controller = RankingTrackController(ranking, gateway);

      await controller.load();
      expect(controller.stage, RankingTrackStage.content);
      await controller.loadMore();
      expect(controller.tracks, [first]);
      expect(controller.appendFailure, RankingFailure.network);
      controller.retryMore();
      await Future<void>.delayed(Duration.zero);
      expect(controller.tracks, [first, second]);
      expect(gateway.trackRequests, [
        (ranking, 0, 30),
        (ranking, 1, 30),
        (ranking, 1, 30),
      ]);
      controller.dispose();
    },
  );

  test('Track replacement and disposal cancel late results', () async {
    final late = Completer<RankingTrackPageResult>();
    final pending = _PendingTrackOperation(late.future);
    final gateway = _ScriptedRankingGateway(
      trackOperations: [
        pending,
        const _ImmediateTrackOperation(
          RankingTrackPageResult(ranking: ranking, total: 1, tracks: [second]),
        ),
      ],
    );
    final controller = RankingTrackController(ranking, gateway);

    final firstLoad = controller.load();
    await pending.started.future;
    await controller.load();
    expect(pending.cancelCalls, 1);
    expect(controller.tracks, [second]);
    late.complete(
      const RankingTrackPageResult(ranking: ranking, total: 1, tracks: [first]),
    );
    await firstLoad;
    expect(controller.tracks, [second]);

    final disposeResult = Completer<RankingTrackPageResult>();
    final disposeOperation = _PendingTrackOperation(disposeResult.future);
    final disposed = RankingTrackController(
      ranking,
      _ScriptedRankingGateway(trackOperations: [disposeOperation]),
    );
    final disposedLoad = disposed.load();
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(const RankingTrackPageResult());
    await disposedLoad;
    controller.dispose();
  });
}

class _ScriptedRankingGateway implements RankingGateway {
  _ScriptedRankingGateway({
    this.groupOperations = const [],
    this.trackOperations = const [],
  });

  final List<RankingGroupLoadOperation> groupOperations;
  final List<RankingTrackPageLoadOperation> trackOperations;
  final List<(RankingSummary, int, int)> trackRequests = [];
  int _nextGroup = 0;
  int _nextTrack = 0;

  @override
  RankingGroupLoadOperation beginGroupLoad() => groupOperations[_nextGroup++];

  @override
  RankingTrackPageLoadOperation beginTrackLoad({
    required RankingSummary ranking,
    required int offset,
    required int size,
  }) {
    trackRequests.add((ranking, offset, size));
    return trackOperations[_nextTrack++];
  }
}

class _ImmediateGroupOperation implements RankingGroupLoadOperation {
  const _ImmediateGroupOperation(this.result);
  final RankingGroupResult result;
  @override
  bool cancel() => true;
  @override
  Future<RankingGroupResult> run() async => result;
}

class _PendingGroupOperation implements RankingGroupLoadOperation {
  _PendingGroupOperation(this.result);
  final Future<RankingGroupResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;
  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<RankingGroupResult> run() {
    started.complete();
    return result;
  }
}

class _ImmediateTrackOperation implements RankingTrackPageLoadOperation {
  const _ImmediateTrackOperation(this.result);
  final RankingTrackPageResult result;
  @override
  bool cancel() => true;
  @override
  Future<RankingTrackPageResult> run() async => result;
}

class _PendingTrackOperation implements RankingTrackPageLoadOperation {
  _PendingTrackOperation(this.result);
  final Future<RankingTrackPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;
  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<RankingTrackPageResult> run() {
    started.complete();
    return result;
  }
}
