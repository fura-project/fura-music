import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';

void main() {
  const first = RecommendedPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'catalog:81001',
    title: 'First discovery',
  );
  const second = RecommendedPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'catalog:81002',
    title: 'Second discovery',
  );

  test('loads content and retries a retryable first-page failure', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        RecommendedPlaylistPageResult(
          failure: RecommendedPlaylistFailure.network,
        ),
      ),
      const _ImmediateOperation(
        RecommendedPlaylistPageResult(playlists: [first]),
      ),
    ]);
    final controller = RecommendedPlaylistController(gateway);

    await controller.load();
    expect(controller.stage, RecommendedPlaylistStage.error);
    expect(controller.canRetry, isTrue);

    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, RecommendedPlaylistStage.content);
    expect(controller.playlists, [first]);
    expect(gateway.requests, [(0, 20), (0, 20)]);
    controller.dispose();
  });

  test('maps a synchronous gateway startup failure without escaping', () async {
    final controller = RecommendedPlaylistController(const _ThrowingGateway());

    await controller.load();

    expect(controller.stage, RecommendedPlaylistStage.error);
    expect(controller.failure, RecommendedPlaylistFailure.coreUnavailable);
    expect(controller.canRetry, isTrue);
    controller.dispose();
  });

  test('paginates by raw page length and deduplicates display rows', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        RecommendedPlaylistPageResult(
          offset: 0,
          hasMore: true,
          playlists: [first],
        ),
      ),
      const _ImmediateOperation(
        RecommendedPlaylistPageResult(offset: 1, playlists: [first, second]),
      ),
    ]);
    final controller = RecommendedPlaylistController(gateway);

    await controller.load();
    await controller.loadMore();
    expect(controller.playlists, [first, second]);
    expect(controller.hasMore, isFalse);
    expect(gateway.requests, [(0, 20), (1, 20)]);
    controller.dispose();
  });

  test('retains content and exact offset after append failure', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        RecommendedPlaylistPageResult(
          offset: 0,
          hasMore: true,
          playlists: [first],
        ),
      ),
      const _ImmediateOperation(
        RecommendedPlaylistPageResult(
          failure: RecommendedPlaylistFailure.network,
        ),
      ),
      const _ImmediateOperation(
        RecommendedPlaylistPageResult(offset: 1, playlists: [second]),
      ),
    ]);
    final controller = RecommendedPlaylistController(gateway);

    await controller.load();
    await controller.loadMore();
    expect(controller.playlists, [first]);
    expect(controller.appendFailure, RecommendedPlaylistFailure.network);
    expect(controller.canRetryMore, isTrue);

    controller.retryMore();
    await Future<void>.delayed(Duration.zero);
    expect(controller.playlists, [first, second]);
    expect(gateway.requests, [(0, 20), (1, 20), (1, 20)]);
    controller.dispose();
  });

  test(
    'replaced and disposed loads cancel and suppress late results',
    () async {
      final firstResult = Completer<RecommendedPlaylistPageResult>();
      final firstOperation = _PendingOperation(firstResult.future);
      final gateway = _ScriptedGateway([
        firstOperation,
        const _ImmediateOperation(
          RecommendedPlaylistPageResult(playlists: [second]),
        ),
      ]);
      final controller = RecommendedPlaylistController(gateway);

      final firstLoad = controller.load();
      await firstOperation.started.future;
      await controller.load();
      expect(firstOperation.cancelCalls, 1);
      expect(controller.playlists, [second]);
      firstResult.complete(
        const RecommendedPlaylistPageResult(playlists: [first]),
      );
      await firstLoad;
      expect(controller.playlists, [second]);

      final disposeResult = Completer<RecommendedPlaylistPageResult>();
      final disposeOperation = _PendingOperation(disposeResult.future);
      final disposed = RecommendedPlaylistController(
        _ScriptedGateway([disposeOperation]),
      );
      final disposedLoad = disposed.load();
      await disposeOperation.started.future;
      disposed.dispose();
      expect(disposeOperation.cancelCalls, 1);
      disposeResult.complete(const RecommendedPlaylistPageResult());
      await disposedLoad;
      controller.dispose();
    },
  );
}

class _ScriptedGateway implements RecommendedPlaylistGateway {
  _ScriptedGateway(this.operations);

  final List<RecommendedPlaylistPageLoadOperation> operations;
  final List<(int, int)> requests = [];
  int _next = 0;

  @override
  RecommendedPlaylistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return operations[_next++];
  }
}

class _ThrowingGateway implements RecommendedPlaylistGateway {
  const _ThrowingGateway();

  @override
  RecommendedPlaylistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => throw StateError('bridge unavailable');
}

class _ImmediateOperation implements RecommendedPlaylistPageLoadOperation {
  const _ImmediateOperation(this.result);

  final RecommendedPlaylistPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<RecommendedPlaylistPageResult> run() async => result;
}

class _PendingOperation implements RecommendedPlaylistPageLoadOperation {
  _PendingOperation(this.result);

  final Future<RecommendedPlaylistPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<RecommendedPlaylistPageResult> run() {
    started.complete();
    return result;
  }
}
