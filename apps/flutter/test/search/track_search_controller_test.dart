import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/search/track_search_controller.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';

void main() {
  const firstTrack = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:41001:0:firstMid:-',
    title: 'First result',
    artistNames: ['Artist'],
  );
  const secondTrack = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:41002:0:secondMid:-',
    title: 'Second result',
    artistNames: ['Artist'],
  );
  const firstItem = TrackSearchItem(track: firstTrack);
  const secondItem = TrackSearchItem(track: secondTrack);

  test('maps content empty and retryable first-page failure', () async {
    final gateway = _ScriptedGateway([
      _ImmediateOperation(
        const TrackSearchPageResult(page: 1, total: 1, items: [firstItem]),
      ),
      _ImmediateOperation(const TrackSearchPageResult(page: 1)),
      _ImmediateOperation(
        const TrackSearchPageResult(failure: SearchFailure.network),
      ),
      _ImmediateOperation(
        const TrackSearchPageResult(page: 1, total: 1, items: [secondItem]),
      ),
    ]);
    final controller = TrackSearchController(gateway);

    await controller.submit('  first query  ');
    expect(controller.query, 'first query');
    expect(controller.stage, TrackSearchStage.content);
    expect(controller.tracks, [firstTrack]);

    await controller.submit('empty query');
    expect(controller.stage, TrackSearchStage.empty);

    await controller.submit('retry query');
    expect(controller.stage, TrackSearchStage.error);
    expect(controller.failure, SearchFailure.network);
    expect(controller.canRetry, isTrue);
    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, TrackSearchStage.content);
    expect(controller.tracks, [secondTrack]);
    expect(gateway.requests, [
      ('first query', 1, 30),
      ('empty query', 1, 30),
      ('retry query', 1, 30),
      ('retry query', 1, 30),
    ]);
    controller.dispose();
  });

  test('replacement cancels and suppresses a late old query', () async {
    final oldResult = Completer<TrackSearchPageResult>();
    final oldOperation = _PendingOperation(oldResult.future);
    final gateway = _ScriptedGateway([
      oldOperation,
      _ImmediateOperation(
        const TrackSearchPageResult(page: 1, total: 1, items: [secondItem]),
      ),
    ]);
    final controller = TrackSearchController(gateway);

    final oldRequest = controller.submit('old query');
    await oldOperation.started.future;
    await controller.submit('new query');
    expect(oldOperation.cancelCalls, 1);
    expect(controller.query, 'new query');
    expect(controller.tracks, [secondTrack]);

    oldResult.complete(
      const TrackSearchPageResult(page: 1, total: 1, items: [firstItem]),
    );
    await oldRequest;
    expect(controller.query, 'new query');
    expect(controller.tracks, [secondTrack]);
    controller.dispose();
  });

  test(
    'paginates, deduplicates, and retains content on append failure',
    () async {
      final gateway = _ScriptedGateway([
        _ImmediateOperation(
          const TrackSearchPageResult(
            page: 1,
            total: 3,
            hasMore: true,
            items: [firstItem],
          ),
        ),
        _ImmediateOperation(
          const TrackSearchPageResult(
            page: 2,
            total: 3,
            items: [firstItem, secondItem],
          ),
        ),
        _ImmediateOperation(
          const TrackSearchPageResult(failure: SearchFailure.network),
        ),
      ]);
      final controller = TrackSearchController(gateway);

      await controller.submit('paged query');
      await controller.loadMore();
      expect(controller.tracks, [firstTrack, secondTrack]);
      expect(controller.hasMore, isFalse);

      final retryGateway = _ScriptedGateway([
        _ImmediateOperation(
          const TrackSearchPageResult(
            page: 1,
            total: 2,
            hasMore: true,
            items: [firstItem],
          ),
        ),
        gateway.operations.last,
      ]);
      final retryController = TrackSearchController(retryGateway);
      await retryController.submit('append failure');
      await retryController.loadMore();
      expect(retryController.stage, TrackSearchStage.content);
      expect(retryController.tracks, [firstTrack]);
      expect(retryController.appendFailure, SearchFailure.network);
      expect(retryController.canRetryMore, isTrue);
      controller.dispose();
      retryController.dispose();
    },
  );

  test('blank query clears and dispose cancels in-flight work', () async {
    final result = Completer<TrackSearchPageResult>();
    final operation = _PendingOperation(result.future);
    final controller = TrackSearchController(_ScriptedGateway([operation]));

    final request = controller.submit('query');
    await operation.started.future;
    controller.clear();
    expect(operation.cancelCalls, 1);
    expect(controller.stage, TrackSearchStage.idle);
    expect(controller.query, isEmpty);
    result.complete(
      const TrackSearchPageResult(page: 1, total: 1, items: [firstItem]),
    );
    await request;
    expect(controller.stage, TrackSearchStage.idle);

    final disposeResult = Completer<TrackSearchPageResult>();
    final disposeOperation = _PendingOperation(disposeResult.future);
    final disposed = TrackSearchController(
      _ScriptedGateway([disposeOperation]),
    );
    final disposedRequest = disposed.submit('dispose query');
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(const TrackSearchPageResult(page: 1));
    await disposedRequest;
  });
}

class _ScriptedGateway implements TrackSearchGateway {
  _ScriptedGateway(this.operations);

  final List<TrackSearchPageLoadOperation> operations;
  final List<(String, int, int)> requests = [];
  int _next = 0;

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return operations[_next++];
  }
}

class _ImmediateOperation implements TrackSearchPageLoadOperation {
  const _ImmediateOperation(this.result);

  final TrackSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<TrackSearchPageResult> run() async => result;
}

class _PendingOperation implements TrackSearchPageLoadOperation {
  _PendingOperation(this.result);

  final Future<TrackSearchPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<TrackSearchPageResult> run() {
    started.complete();
    return result;
  }
}
