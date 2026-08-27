import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/search/artist_search_controller.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';

void main() {
  const firstArtist = ArtistSummary(
    providerId: 'qq-music',
    opaqueId: 'artist:61001:firstArtistMid',
    name: 'First Artist',
  );
  const secondArtist = ArtistSummary(
    providerId: 'qq-music',
    opaqueId: 'artist:61002:secondArtistMid',
    name: 'Second Artist',
  );

  test('maps content, empty, and retryable first-page failure', () async {
    final gateway = _ScriptedGateway([
      _ImmediateOperation(
        const ArtistSearchPageResult(page: 1, total: 1, artists: [firstArtist]),
      ),
      _ImmediateOperation(const ArtistSearchPageResult(page: 1)),
      _ImmediateOperation(
        const ArtistSearchPageResult(failure: SearchFailure.network),
      ),
      _ImmediateOperation(
        const ArtistSearchPageResult(
          page: 1,
          total: 1,
          artists: [secondArtist],
        ),
      ),
    ]);
    final controller = ArtistSearchController(gateway);

    await controller.submit('  first query  ');
    expect(controller.query, 'first query');
    expect(controller.stage, ArtistSearchStage.content);
    expect(controller.artists, [firstArtist]);

    await controller.submit('empty query');
    expect(controller.stage, ArtistSearchStage.empty);

    await controller.submit('retry query');
    expect(controller.stage, ArtistSearchStage.error);
    expect(controller.failure, SearchFailure.network);
    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, ArtistSearchStage.content);
    expect(controller.artists, [secondArtist]);
    expect(gateway.requests, [
      ('first query', 1, 30),
      ('empty query', 1, 30),
      ('retry query', 1, 30),
      ('retry query', 1, 30),
    ]);
    controller.dispose();
  });

  test('replacement cancels and suppresses a late old query', () async {
    final oldResult = Completer<ArtistSearchPageResult>();
    final oldOperation = _PendingOperation(oldResult.future);
    final gateway = _ScriptedGateway([
      oldOperation,
      _ImmediateOperation(
        const ArtistSearchPageResult(
          page: 1,
          total: 1,
          artists: [secondArtist],
        ),
      ),
    ]);
    final controller = ArtistSearchController(gateway);

    final oldRequest = controller.submit('old query');
    await oldOperation.started.future;
    await controller.submit('new query');
    expect(oldOperation.cancelCalls, 1);
    expect(controller.query, 'new query');
    expect(controller.artists, [secondArtist]);

    oldResult.complete(
      const ArtistSearchPageResult(page: 1, total: 1, artists: [firstArtist]),
    );
    await oldRequest;
    expect(controller.query, 'new query');
    expect(controller.artists, [secondArtist]);
    controller.dispose();
  });

  test(
    'paginates, deduplicates, and retains content on append failure',
    () async {
      final gateway = _ScriptedGateway([
        _ImmediateOperation(
          const ArtistSearchPageResult(
            page: 1,
            total: 3,
            hasMore: true,
            artists: [firstArtist],
          ),
        ),
        _ImmediateOperation(
          const ArtistSearchPageResult(
            page: 2,
            total: 3,
            hasMore: true,
            artists: [firstArtist, secondArtist],
          ),
        ),
        _ImmediateOperation(
          const ArtistSearchPageResult(failure: SearchFailure.network),
        ),
      ]);
      final controller = ArtistSearchController(gateway);

      await controller.submit('paged query');
      await controller.loadMore();
      expect(controller.artists, [firstArtist, secondArtist]);
      await controller.loadMore();
      expect(controller.stage, ArtistSearchStage.content);
      expect(controller.artists, [firstArtist, secondArtist]);
      expect(controller.appendFailure, SearchFailure.network);
      expect(controller.canRetryMore, isTrue);
      controller.dispose();
    },
  );

  test('clear and dispose cancel in-flight work', () async {
    final result = Completer<ArtistSearchPageResult>();
    final operation = _PendingOperation(result.future);
    final controller = ArtistSearchController(_ScriptedGateway([operation]));

    final request = controller.submit('query');
    await operation.started.future;
    controller.clear();
    expect(operation.cancelCalls, 1);
    expect(controller.stage, ArtistSearchStage.idle);
    result.complete(const ArtistSearchPageResult(page: 1));
    await request;

    final disposeResult = Completer<ArtistSearchPageResult>();
    final disposeOperation = _PendingOperation(disposeResult.future);
    final disposed = ArtistSearchController(
      _ScriptedGateway([disposeOperation]),
    );
    final disposedRequest = disposed.submit('dispose query');
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(const ArtistSearchPageResult(page: 1));
    await disposedRequest;
  });
}

class _ScriptedGateway implements ArtistSearchGateway {
  _ScriptedGateway(this.operations);

  final List<ArtistSearchPageLoadOperation> operations;
  final List<(String, int, int)> requests = [];
  int _next = 0;

  @override
  ArtistSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return operations[_next++];
  }
}

class _ImmediateOperation implements ArtistSearchPageLoadOperation {
  const _ImmediateOperation(this.result);

  final ArtistSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistSearchPageResult> run() async => result;
}

class _PendingOperation implements ArtistSearchPageLoadOperation {
  _PendingOperation(this.result);

  final Future<ArtistSearchPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<ArtistSearchPageResult> run() {
    started.complete();
    return result;
  }
}
