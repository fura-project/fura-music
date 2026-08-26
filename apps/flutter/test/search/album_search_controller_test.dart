import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/search/album_search_controller.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';

void main() {
  const firstAlbum = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'album:43001:firstAlbumMid',
    title: 'First Album',
  );
  const secondAlbum = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'album:43002:secondAlbumMid',
    title: 'Second Album',
  );

  test('maps content, empty, and retryable first-page failure', () async {
    final gateway = _ScriptedGateway([
      _ImmediateOperation(
        const AlbumSearchPageResult(page: 1, total: 1, albums: [firstAlbum]),
      ),
      _ImmediateOperation(const AlbumSearchPageResult(page: 1)),
      _ImmediateOperation(
        const AlbumSearchPageResult(failure: AlbumSearchFailure.network),
      ),
      _ImmediateOperation(
        const AlbumSearchPageResult(page: 1, total: 1, albums: [secondAlbum]),
      ),
    ]);
    final controller = AlbumSearchController(gateway);

    await controller.submit('  first query  ');
    expect(controller.query, 'first query');
    expect(controller.stage, AlbumSearchStage.content);
    expect(controller.albums, [firstAlbum]);

    await controller.submit('empty query');
    expect(controller.stage, AlbumSearchStage.empty);

    await controller.submit('retry query');
    expect(controller.stage, AlbumSearchStage.error);
    expect(controller.failure, AlbumSearchFailure.network);
    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, AlbumSearchStage.content);
    expect(controller.albums, [secondAlbum]);
    expect(gateway.requests, [
      ('first query', 1, 30),
      ('empty query', 1, 30),
      ('retry query', 1, 30),
      ('retry query', 1, 30),
    ]);
    controller.dispose();
  });

  test('replacement cancels and suppresses a late old query', () async {
    final oldResult = Completer<AlbumSearchPageResult>();
    final oldOperation = _PendingOperation(oldResult.future);
    final gateway = _ScriptedGateway([
      oldOperation,
      _ImmediateOperation(
        const AlbumSearchPageResult(page: 1, total: 1, albums: [secondAlbum]),
      ),
    ]);
    final controller = AlbumSearchController(gateway);

    final oldRequest = controller.submit('old query');
    await oldOperation.started.future;
    await controller.submit('new query');
    expect(oldOperation.cancelCalls, 1);
    expect(controller.query, 'new query');
    expect(controller.albums, [secondAlbum]);

    oldResult.complete(
      const AlbumSearchPageResult(page: 1, total: 1, albums: [firstAlbum]),
    );
    await oldRequest;
    expect(controller.query, 'new query');
    expect(controller.albums, [secondAlbum]);
    controller.dispose();
  });

  test(
    'paginates, deduplicates, and retains content on append failure',
    () async {
      final gateway = _ScriptedGateway([
        _ImmediateOperation(
          const AlbumSearchPageResult(
            page: 1,
            total: 3,
            hasMore: true,
            albums: [firstAlbum],
          ),
        ),
        _ImmediateOperation(
          const AlbumSearchPageResult(
            page: 2,
            total: 3,
            hasMore: true,
            albums: [firstAlbum, secondAlbum],
          ),
        ),
        _ImmediateOperation(
          const AlbumSearchPageResult(failure: AlbumSearchFailure.network),
        ),
      ]);
      final controller = AlbumSearchController(gateway);

      await controller.submit('paged query');
      await controller.loadMore();
      expect(controller.albums, [firstAlbum, secondAlbum]);
      await controller.loadMore();
      expect(controller.stage, AlbumSearchStage.content);
      expect(controller.albums, [firstAlbum, secondAlbum]);
      expect(controller.appendFailure, AlbumSearchFailure.network);
      expect(controller.canRetryMore, isTrue);
      controller.dispose();
    },
  );

  test('clear and dispose cancel in-flight work', () async {
    final result = Completer<AlbumSearchPageResult>();
    final operation = _PendingOperation(result.future);
    final controller = AlbumSearchController(_ScriptedGateway([operation]));

    final request = controller.submit('query');
    await operation.started.future;
    controller.clear();
    expect(operation.cancelCalls, 1);
    expect(controller.stage, AlbumSearchStage.idle);
    result.complete(const AlbumSearchPageResult(page: 1));
    await request;

    final disposeResult = Completer<AlbumSearchPageResult>();
    final disposeOperation = _PendingOperation(disposeResult.future);
    final disposed = AlbumSearchController(
      _ScriptedGateway([disposeOperation]),
    );
    final disposedRequest = disposed.submit('dispose query');
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(const AlbumSearchPageResult(page: 1));
    await disposedRequest;
  });
}

class _ScriptedGateway implements AlbumSearchGateway {
  _ScriptedGateway(this.operations);

  final List<AlbumSearchPageLoadOperation> operations;
  final List<(String, int, int)> requests = [];
  int _next = 0;

  @override
  AlbumSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return operations[_next++];
  }
}

class _ImmediateOperation implements AlbumSearchPageLoadOperation {
  const _ImmediateOperation(this.result);

  final AlbumSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumSearchPageResult> run() async => result;
}

class _PendingOperation implements AlbumSearchPageLoadOperation {
  _PendingOperation(this.result);

  final Future<AlbumSearchPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<AlbumSearchPageResult> run() {
    started.complete();
    return result;
  }
}
