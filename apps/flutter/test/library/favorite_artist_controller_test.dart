import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/library/favorite_artist_controller.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';

void main() {
  const first = ArtistSummary(
    providerId: 'qq-music',
    opaqueId: 'artist:-:firstArtistMid',
    name: 'First Artist',
  );
  const second = ArtistSummary(
    providerId: 'qq-music',
    opaqueId: 'artist:-:secondArtistMid',
    name: 'Second Artist',
  );

  test('loads and retries a first-page failure', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        FavoriteArtistPageResult(failure: FavoriteArtistFailure.network),
      ),
      const _ImmediateOperation(
        FavoriteArtistPageResult(total: 1, artists: [first]),
      ),
    ]);
    final controller = FavoriteArtistController(gateway);

    await controller.load();
    expect(controller.stage, FavoriteArtistStage.error);
    expect(controller.canRetry, isTrue);
    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, FavoriteArtistStage.content);
    expect(controller.artists, [first]);
    expect(gateway.requests, [(0, 20), (0, 20)]);
    controller.dispose();
  });

  test(
    'paginates by raw rows, deduplicates, and retains append errors',
    () async {
      final controller = FavoriteArtistController(
        _ScriptedGateway([
          const _ImmediateOperation(
            FavoriteArtistPageResult(total: 3, hasMore: true, artists: [first]),
          ),
          const _ImmediateOperation(
            FavoriteArtistPageResult(
              offset: 1,
              total: 3,
              artists: [first, second],
            ),
          ),
        ]),
      );
      await controller.load();
      await controller.loadMore();
      expect(controller.artists, [first, second]);
      expect(controller.hasMore, isFalse);

      final failing = FavoriteArtistController(
        _ScriptedGateway([
          const _ImmediateOperation(
            FavoriteArtistPageResult(total: 2, hasMore: true, artists: [first]),
          ),
          const _ImmediateOperation(
            FavoriteArtistPageResult(failure: FavoriteArtistFailure.network),
          ),
        ]),
      );
      await failing.load();
      await failing.loadMore();
      expect(failing.artists, [first]);
      expect(failing.appendFailure, FavoriteArtistFailure.network);
      expect(failing.canRetryMore, isTrue);
      controller.dispose();
      failing.dispose();
    },
  );

  test('an append credential failure clears private content', () async {
    final controller = FavoriteArtistController(
      _ScriptedGateway([
        const _ImmediateOperation(
          FavoriteArtistPageResult(total: 2, hasMore: true, artists: [first]),
        ),
        const _ImmediateOperation(
          FavoriteArtistPageResult(
            failure: FavoriteArtistFailure.credentialRejected,
          ),
        ),
      ]),
    );

    await controller.load();
    await controller.loadMore();
    expect(controller.stage, FavoriteArtistStage.credentialRejected);
    expect(controller.artists, isEmpty);
    expect(controller.total, 0);
    controller.dispose();
  });

  test('replacement and disposal cancel stale first pages', () async {
    final firstResult = Completer<FavoriteArtistPageResult>();
    final firstOperation = _PendingOperation(firstResult.future);
    final gateway = _ScriptedGateway([
      firstOperation,
      const _ImmediateOperation(
        FavoriteArtistPageResult(total: 1, artists: [second]),
      ),
    ]);
    final controller = FavoriteArtistController(gateway);

    final firstLoad = controller.load();
    await firstOperation.started.future;
    final replacement = controller.load();
    await replacement;
    expect(firstOperation.cancelCalls, 1);
    firstResult.complete(
      const FavoriteArtistPageResult(total: 1, artists: [first]),
    );
    await firstLoad;
    expect(controller.artists, [second]);

    final disposeResult = Completer<FavoriteArtistPageResult>();
    final disposeOperation = _PendingOperation(disposeResult.future);
    final disposed = FavoriteArtistController(
      _ScriptedGateway([disposeOperation]),
    );
    final disposedLoad = disposed.load();
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(const FavoriteArtistPageResult());
    await disposedLoad;
    controller.dispose();
  });
}

class _ScriptedGateway implements FavoriteArtistGateway {
  _ScriptedGateway(this.operations);

  final List<FavoriteArtistPageLoadOperation> operations;
  final List<(int, int)> requests = [];
  int _next = 0;

  @override
  FavoriteArtistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return operations[_next++];
  }
}

class _ImmediateOperation implements FavoriteArtistPageLoadOperation {
  const _ImmediateOperation(this.result);

  final FavoriteArtistPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<FavoriteArtistPageResult> run() async => result;
}

class _PendingOperation implements FavoriteArtistPageLoadOperation {
  _PendingOperation(this.result);

  final Future<FavoriteArtistPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<FavoriteArtistPageResult> run() {
    started.complete();
    return result;
  }
}
