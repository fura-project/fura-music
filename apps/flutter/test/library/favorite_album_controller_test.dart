import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/library/favorite_album_controller.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';

void main() {
  const first = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'album:43001:firstAlbumMid',
    title: 'First Album',
  );
  const second = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'album:43002:secondAlbumMid',
    title: 'Second Album',
  );

  test('loads and retries a first-page failure', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        FavoriteAlbumPageResult(failure: FavoriteAlbumFailure.network),
      ),
      const _ImmediateOperation(
        FavoriteAlbumPageResult(total: 1, albums: [first]),
      ),
    ]);
    final controller = FavoriteAlbumController(gateway);

    await controller.load();
    expect(controller.stage, FavoriteAlbumStage.error);
    expect(controller.canRetry, isTrue);
    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, FavoriteAlbumStage.content);
    expect(controller.albums, [first]);
    expect(gateway.requests, [(0, 20), (0, 20)]);
    controller.dispose();
  });

  test(
    'paginates by raw rows, deduplicates, and retains append errors',
    () async {
      final controller = FavoriteAlbumController(
        _ScriptedGateway([
          const _ImmediateOperation(
            FavoriteAlbumPageResult(total: 3, hasMore: true, albums: [first]),
          ),
          const _ImmediateOperation(
            FavoriteAlbumPageResult(
              offset: 1,
              total: 3,
              albums: [first, second],
            ),
          ),
        ]),
      );
      await controller.load();
      await controller.loadMore();
      expect(controller.albums, [first, second]);
      expect(controller.hasMore, isFalse);

      final failing = FavoriteAlbumController(
        _ScriptedGateway([
          const _ImmediateOperation(
            FavoriteAlbumPageResult(total: 2, hasMore: true, albums: [first]),
          ),
          const _ImmediateOperation(
            FavoriteAlbumPageResult(failure: FavoriteAlbumFailure.network),
          ),
        ]),
      );
      await failing.load();
      await failing.loadMore();
      expect(failing.albums, [first]);
      expect(failing.appendFailure, FavoriteAlbumFailure.network);
      expect(failing.canRetryMore, isTrue);
      controller.dispose();
      failing.dispose();
    },
  );

  test('an append credential failure clears private content', () async {
    final controller = FavoriteAlbumController(
      _ScriptedGateway([
        const _ImmediateOperation(
          FavoriteAlbumPageResult(total: 2, hasMore: true, albums: [first]),
        ),
        const _ImmediateOperation(
          FavoriteAlbumPageResult(
            failure: FavoriteAlbumFailure.credentialRejected,
          ),
        ),
      ]),
    );

    await controller.load();
    await controller.loadMore();
    expect(controller.stage, FavoriteAlbumStage.credentialRejected);
    expect(controller.albums, isEmpty);
    expect(controller.total, 0);
    controller.dispose();
  });

  test('replacement and disposal cancel stale first pages', () async {
    final firstResult = Completer<FavoriteAlbumPageResult>();
    final firstOperation = _PendingOperation(firstResult.future);
    final gateway = _ScriptedGateway([
      firstOperation,
      const _ImmediateOperation(
        FavoriteAlbumPageResult(total: 1, albums: [second]),
      ),
    ]);
    final controller = FavoriteAlbumController(gateway);

    final firstLoad = controller.load();
    await firstOperation.started.future;
    final replacement = controller.load();
    await replacement;
    expect(firstOperation.cancelCalls, 1);
    firstResult.complete(
      const FavoriteAlbumPageResult(total: 1, albums: [first]),
    );
    await firstLoad;
    expect(controller.albums, [second]);

    final disposeResult = Completer<FavoriteAlbumPageResult>();
    final disposeOperation = _PendingOperation(disposeResult.future);
    final disposed = FavoriteAlbumController(
      _ScriptedGateway([disposeOperation]),
    );
    final disposedLoad = disposed.load();
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(const FavoriteAlbumPageResult());
    await disposedLoad;
    controller.dispose();
  });
}

class _ScriptedGateway implements FavoriteAlbumGateway {
  _ScriptedGateway(this.operations);

  final List<FavoriteAlbumPageLoadOperation> operations;
  final List<(int, int)> requests = [];
  int _next = 0;

  @override
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return operations[_next++];
  }
}

class _ImmediateOperation implements FavoriteAlbumPageLoadOperation {
  const _ImmediateOperation(this.result);

  final FavoriteAlbumPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<FavoriteAlbumPageResult> run() async => result;
}

class _PendingOperation implements FavoriteAlbumPageLoadOperation {
  _PendingOperation(this.result);

  final Future<FavoriteAlbumPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<FavoriteAlbumPageResult> run() {
    started.complete();
    return result;
  }
}
