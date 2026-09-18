import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/comments/track_comment_controller.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

void main() {
  test(
    'loads hot and newest comments then paginates with fixed page offset',
    () async {
      final gateway = _ScriptedGateway([
        _PendingOperation.completed(
          TrackCommentPageResult(
            nextOffset: 20,
            total: 22,
            hasMore: true,
            omittedLatestCommentCount: 18,
            hotComments: [_comment('hot')],
            latestComments: [_comment('one'), _comment('two')],
          ),
        ),
        _PendingOperation.completed(
          TrackCommentPageResult(
            offset: 20,
            nextOffset: 22,
            total: 22,
            latestComments: [_comment('two'), _comment('three')],
          ),
        ),
      ]);
      final controller = TrackCommentController(gateway, _track);

      await controller.load();
      expect(controller.stage, TrackCommentStage.content);
      expect(controller.hotComments.single.opaqueId, 'comment:hot');
      expect(controller.latestComments.map((comment) => comment.opaqueId), [
        'comment:one',
        'comment:two',
      ]);
      expect(controller.canLoadMore, isTrue);

      await controller.loadMore();
      expect(controller.latestComments.map((comment) => comment.opaqueId), [
        'comment:one',
        'comment:two',
        'comment:three',
      ]);
      expect(controller.total, 22);
      expect(controller.hasMore, isFalse);
      expect(gateway.requests, [(0, 20), (20, 20)]);
      controller.dispose();
    },
  );

  test('initial retry and append retry preserve successful content', () async {
    final gateway = _ScriptedGateway([
      _PendingOperation.completed(
        const TrackCommentPageResult(failure: TrackCommentFailure.network),
      ),
      _PendingOperation.completed(
        TrackCommentPageResult(
          nextOffset: 20,
          total: 21,
          hasMore: true,
          omittedLatestCommentCount: 19,
          latestComments: [_comment('one')],
        ),
      ),
      _PendingOperation.completed(
        const TrackCommentPageResult(failure: TrackCommentFailure.network),
      ),
      _PendingOperation.completed(
        TrackCommentPageResult(
          offset: 20,
          nextOffset: 21,
          total: 21,
          latestComments: [_comment('two')],
        ),
      ),
    ]);
    final controller = TrackCommentController(gateway, _track);

    await controller.load();
    expect(controller.stage, TrackCommentStage.error);
    expect(controller.canRetry, isTrue);
    controller.retry();
    await _flush();
    expect(controller.stage, TrackCommentStage.content);

    await controller.loadMore();
    expect(controller.appendFailure, TrackCommentFailure.network);
    expect(controller.latestComments.single.opaqueId, 'comment:one');
    expect(controller.canRetryMore, isTrue);
    controller.retryMore();
    await _flush();
    expect(controller.latestComments.map((comment) => comment.opaqueId), [
      'comment:one',
      'comment:two',
    ]);
    expect(controller.appendFailure, isNull);
    controller.dispose();
  });

  test('a restarted load cancels and suppresses a late result', () async {
    final first = _PendingOperation();
    final second = _PendingOperation();
    final gateway = _ScriptedGateway([first, second]);
    final controller = TrackCommentController(gateway, _track);

    final firstLoad = controller.load();
    final secondLoad = controller.load();
    expect(first.cancelCalls, 1);

    first.complete(
      TrackCommentPageResult(
        nextOffset: 1,
        total: 1,
        latestComments: [_comment('late')],
      ),
    );
    await firstLoad;
    expect(controller.stage, TrackCommentStage.loading);

    second.complete(
      TrackCommentPageResult(
        nextOffset: 1,
        total: 1,
        latestComments: [_comment('current')],
      ),
    );
    await secondLoad;
    expect(controller.latestComments.single.opaqueId, 'comment:current');
    controller.dispose();
  });

  test('dispose cancels and suppresses late completion', () async {
    final operation = _PendingOperation();
    final controller = TrackCommentController(
      _ScriptedGateway([operation]),
      _track,
    );

    final load = controller.load();
    controller.dispose();
    expect(operation.cancelCalls, 1);
    operation.complete(
      TrackCommentPageResult(total: 1, latestComments: [_comment('late')]),
    );
    await load;
    expect(controller.latestComments, isEmpty);
  });

  test(
    'accepts a terminal page after unavailable raw rows are omitted',
    () async {
      final gateway = _ScriptedGateway([
        _PendingOperation.completed(
          TrackCommentPageResult(
            nextOffset: 3,
            total: 3,
            omittedLatestCommentCount: 2,
            latestComments: [_comment('visible')],
          ),
        ),
      ]);
      final controller = TrackCommentController(gateway, _track);

      await controller.load();

      expect(controller.stage, TrackCommentStage.content);
      expect(controller.total, 3);
      expect(controller.hasMore, isFalse);
      expect(controller.latestComments.single.opaqueId, 'comment:visible');
      controller.dispose();
    },
  );

  test(
    'advances past a full page whose raw rows are all unavailable',
    () async {
      final gateway = _ScriptedGateway([
        _PendingOperation.completed(
          const TrackCommentPageResult(
            nextOffset: 20,
            total: 21,
            hasMore: true,
            omittedLatestCommentCount: 20,
          ),
        ),
        _PendingOperation.completed(
          TrackCommentPageResult(
            offset: 20,
            nextOffset: 21,
            total: 21,
            latestComments: [_comment('visible')],
          ),
        ),
      ]);
      final controller = TrackCommentController(gateway, _track);

      await controller.load();
      expect(controller.stage, TrackCommentStage.content);
      expect(controller.canLoadMore, isTrue);

      await controller.loadMore();
      expect(gateway.requests, [(0, 20), (20, 20)]);
      expect(controller.latestComments.single.opaqueId, 'comment:visible');
      expect(controller.hasMore, isFalse);
      controller.dispose();
    },
  );

  test('rapid append demand stays single-flight', () async {
    final append = _PendingOperation();
    final gateway = _ScriptedGateway([
      _PendingOperation.completed(
        TrackCommentPageResult(
          nextOffset: 20,
          total: 21,
          hasMore: true,
          omittedLatestCommentCount: 19,
          latestComments: [_comment('one')],
        ),
      ),
      append,
    ]);
    final controller = TrackCommentController(gateway, _track);
    await controller.load();

    final firstDemand = controller.loadMore();
    final repeatedDemand = controller.loadMore();
    expect(gateway.requests, [(0, 20), (20, 20)]);
    append.complete(
      TrackCommentPageResult(
        offset: 20,
        nextOffset: 21,
        total: 21,
        latestComments: [_comment('two')],
      ),
    );
    await Future.wait([firstDemand, repeatedDemand]);
    expect(controller.latestComments, hasLength(2));
    controller.dispose();
  });

  test('later pages cannot repeat hot-comment sections', () async {
    final gateway = _ScriptedGateway([
      _PendingOperation.completed(
        TrackCommentPageResult(
          nextOffset: 1,
          total: 2,
          hasMore: true,
          hotComments: [_comment('hot')],
          latestComments: [_comment('one')],
        ),
      ),
      _PendingOperation.completed(
        TrackCommentPageResult(
          offset: 1,
          nextOffset: 2,
          total: 2,
          hotComments: [_comment('repeated-hot')],
          latestComments: [_comment('two')],
        ),
      ),
    ]);
    final controller = TrackCommentController(gateway, _track);
    await controller.load();
    await controller.loadMore();

    expect(controller.appendFailure, TrackCommentFailure.invalidResponse);
    expect(controller.hotComments.single.opaqueId, 'comment:hot');
    expect(controller.latestComments.single.opaqueId, 'comment:one');
    controller.dispose();
  });
}

const _track = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:41001:0:syntheticMid:-',
  title: 'Synthetic Track',
  artistNames: ['Synthetic Artist'],
);

TrackCommentSummary _comment(String id) => TrackCommentSummary(
  providerId: 'qq-music',
  opaqueId: 'comment:$id',
  authorDisplayName: 'Author $id',
  content: 'Content $id',
  publishedAtUnixSeconds: 1700000000,
  praiseCount: 4,
);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _ScriptedGateway implements TrackCommentGateway {
  _ScriptedGateway(this.operations);

  final List<_PendingOperation> operations;
  final List<(int, int)> requests = [];
  int next = 0;

  @override
  TrackCommentPageLoadOperation beginLoad({
    required PlaylistTrackSummary track,
    required int offset,
    required int size,
  }) {
    expect(track.opaqueId, _track.opaqueId);
    requests.add((offset, size));
    return operations[next++];
  }
}

class _PendingOperation implements TrackCommentPageLoadOperation {
  _PendingOperation();

  _PendingOperation.completed(TrackCommentPageResult result) {
    completer.complete(result);
  }

  final Completer<TrackCommentPageResult> completer = Completer();
  int cancelCalls = 0;

  void complete(TrackCommentPageResult result) => completer.complete(result);

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<TrackCommentPageResult> run() => completer.future;
}
