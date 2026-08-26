import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/discover/new_album_controller.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';

void main() {
  const first = NewAlbumRelease(
    album: AlbumSummary(
      providerId: 'qq-music',
      opaqueId: 'album:43001:firstAlbumMid',
      title: 'First Album',
    ),
    artists: [],
  );
  const second = NewAlbumRelease(
    album: AlbumSummary(
      providerId: 'qq-music',
      opaqueId: 'album:43002:secondAlbumMid',
      title: 'Second Album',
    ),
    artists: [],
  );

  test('loads the default region and retries a first-page failure', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        NewAlbumPageResult(
          region: NewAlbumRegion.mainlandChina,
          failure: NewAlbumFailure.network,
        ),
      ),
      const _ImmediateOperation(
        NewAlbumPageResult(
          region: NewAlbumRegion.mainlandChina,
          total: 1,
          releases: [first],
        ),
      ),
    ]);
    final controller = NewAlbumController(gateway);

    await controller.load();
    expect(controller.stage, NewAlbumStage.error);
    expect(controller.canRetry, isTrue);
    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, NewAlbumStage.content);
    expect(controller.releases, [first]);
    expect(gateway.requests, [
      (NewAlbumRegion.mainlandChina, 0, 20),
      (NewAlbumRegion.mainlandChina, 0, 20),
    ]);
    controller.dispose();
  });

  test(
    'paginates by raw rows, deduplicates, and retains append state',
    () async {
      final gateway = _ScriptedGateway([
        const _ImmediateOperation(
          NewAlbumPageResult(
            region: NewAlbumRegion.mainlandChina,
            total: 3,
            hasMore: true,
            releases: [first],
          ),
        ),
        const _ImmediateOperation(
          NewAlbumPageResult(
            region: NewAlbumRegion.mainlandChina,
            offset: 1,
            total: 3,
            releases: [first, second],
          ),
        ),
        const _ImmediateOperation(
          NewAlbumPageResult(
            region: NewAlbumRegion.mainlandChina,
            failure: NewAlbumFailure.network,
          ),
        ),
      ]);
      final controller = NewAlbumController(gateway);

      await controller.load();
      await controller.loadMore();
      expect(controller.releases, [first, second]);
      expect(gateway.requests[1], (NewAlbumRegion.mainlandChina, 1, 20));
      expect(controller.hasMore, isFalse);

      final failing = NewAlbumController(
        _ScriptedGateway([
          const _ImmediateOperation(
            NewAlbumPageResult(
              region: NewAlbumRegion.mainlandChina,
              total: 2,
              hasMore: true,
              releases: [first],
            ),
          ),
          const _ImmediateOperation(
            NewAlbumPageResult(
              region: NewAlbumRegion.mainlandChina,
              failure: NewAlbumFailure.network,
            ),
          ),
        ]),
      );
      await failing.load();
      await failing.loadMore();
      expect(failing.releases, [first]);
      expect(failing.appendFailure, NewAlbumFailure.network);
      expect(failing.canRetryMore, isTrue);
      controller.dispose();
      failing.dispose();
    },
  );

  test('region replacement and disposal cancel stale results', () async {
    final firstResult = Completer<NewAlbumPageResult>();
    final firstOperation = _PendingOperation(firstResult.future);
    final gateway = _ScriptedGateway([
      firstOperation,
      const _ImmediateOperation(
        NewAlbumPageResult(
          region: NewAlbumRegion.japan,
          total: 1,
          releases: [second],
        ),
      ),
    ]);
    final controller = NewAlbumController(gateway);

    final firstLoad = controller.load();
    await firstOperation.started.future;
    controller.selectRegion(NewAlbumRegion.japan);
    await Future<void>.delayed(Duration.zero);
    expect(firstOperation.cancelCalls, 1);
    firstResult.complete(
      const NewAlbumPageResult(
        region: NewAlbumRegion.mainlandChina,
        total: 1,
        releases: [first],
      ),
    );
    await firstLoad;
    expect(controller.region, NewAlbumRegion.japan);
    expect(controller.releases, [second]);

    final disposeResult = Completer<NewAlbumPageResult>();
    final disposeOperation = _PendingOperation(disposeResult.future);
    final disposed = NewAlbumController(_ScriptedGateway([disposeOperation]));
    final disposedLoad = disposed.load();
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(
      const NewAlbumPageResult(region: NewAlbumRegion.mainlandChina),
    );
    await disposedLoad;
    controller.dispose();
  });
}

class _ScriptedGateway implements NewAlbumGateway {
  _ScriptedGateway(this.operations);

  final List<NewAlbumPageLoadOperation> operations;
  final List<(NewAlbumRegion, int, int)> requests = [];
  int _next = 0;

  @override
  NewAlbumPageLoadOperation beginLoad({
    required NewAlbumRegion region,
    required int offset,
    required int size,
  }) {
    requests.add((region, offset, size));
    return operations[_next++];
  }
}

class _ImmediateOperation implements NewAlbumPageLoadOperation {
  const _ImmediateOperation(this.result);

  final NewAlbumPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<NewAlbumPageResult> run() async => result;
}

class _PendingOperation implements NewAlbumPageLoadOperation {
  _PendingOperation(this.result);

  final Future<NewAlbumPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<NewAlbumPageResult> run() {
    started.complete();
    return result;
  }
}
