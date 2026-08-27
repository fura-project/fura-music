import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_controller.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';

void main() {
  const firstPlaylist = UserPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'catalog:81001',
    title: 'First Playlist',
  );
  const secondPlaylist = UserPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'catalog:81002',
    title: 'Second Playlist',
  );

  test('maps content, empty, and retryable first-page failure', () async {
    final gateway = _ScriptedGateway([
      _ImmediateOperation(
        const PlaylistSearchPageResult(
          page: 1,
          total: 1,
          playlists: [firstPlaylist],
        ),
      ),
      _ImmediateOperation(const PlaylistSearchPageResult(page: 1)),
      _ImmediateOperation(
        const PlaylistSearchPageResult(failure: SearchFailure.network),
      ),
      _ImmediateOperation(
        const PlaylistSearchPageResult(
          page: 1,
          total: 1,
          playlists: [secondPlaylist],
        ),
      ),
    ]);
    final controller = PlaylistSearchController(gateway);

    await controller.submit('  first query  ');
    expect(controller.query, 'first query');
    expect(controller.stage, PlaylistSearchStage.content);
    expect(controller.playlists, [firstPlaylist]);

    await controller.submit('empty query');
    expect(controller.stage, PlaylistSearchStage.empty);

    await controller.submit('retry query');
    expect(controller.stage, PlaylistSearchStage.error);
    expect(controller.failure, SearchFailure.network);
    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, PlaylistSearchStage.content);
    expect(controller.playlists, [secondPlaylist]);
    expect(gateway.requests, [
      ('first query', 1, 30),
      ('empty query', 1, 30),
      ('retry query', 1, 30),
      ('retry query', 1, 30),
    ]);
    controller.dispose();
  });

  test('replacement cancels and suppresses a late old query', () async {
    final oldResult = Completer<PlaylistSearchPageResult>();
    final oldOperation = _PendingOperation(oldResult.future);
    final gateway = _ScriptedGateway([
      oldOperation,
      _ImmediateOperation(
        const PlaylistSearchPageResult(
          page: 1,
          total: 1,
          playlists: [secondPlaylist],
        ),
      ),
    ]);
    final controller = PlaylistSearchController(gateway);

    final oldRequest = controller.submit('old query');
    await oldOperation.started.future;
    await controller.submit('new query');
    expect(oldOperation.cancelCalls, 1);
    expect(controller.query, 'new query');
    expect(controller.playlists, [secondPlaylist]);

    oldResult.complete(
      const PlaylistSearchPageResult(
        page: 1,
        total: 1,
        playlists: [firstPlaylist],
      ),
    );
    await oldRequest;
    expect(controller.query, 'new query');
    expect(controller.playlists, [secondPlaylist]);
    controller.dispose();
  });

  test('follows server pagination after a short page and retains content on failure', () async {
    final gateway = _ScriptedGateway([
      _ImmediateOperation(
        const PlaylistSearchPageResult(
          page: 1,
          total: 3,
          hasMore: true,
          playlists: [firstPlaylist],
        ),
      ),
      _ImmediateOperation(
        const PlaylistSearchPageResult(
          page: 2,
          total: 3,
          hasMore: true,
          playlists: [firstPlaylist, secondPlaylist],
        ),
      ),
      _ImmediateOperation(
        const PlaylistSearchPageResult(failure: SearchFailure.network),
      ),
    ]);
    final controller = PlaylistSearchController(gateway);

    await controller.submit('paged query');
    await controller.loadMore();
    expect(gateway.requests[1], ('paged query', 2, 30));
    expect(controller.playlists, [firstPlaylist, secondPlaylist]);
    await controller.loadMore();
    expect(controller.stage, PlaylistSearchStage.content);
    expect(controller.playlists, [firstPlaylist, secondPlaylist]);
    expect(controller.appendFailure, SearchFailure.network);
    expect(controller.canRetryMore, isTrue);
    controller.dispose();
  });

  test('clear and dispose cancel in-flight work', () async {
    final result = Completer<PlaylistSearchPageResult>();
    final operation = _PendingOperation(result.future);
    final controller = PlaylistSearchController(_ScriptedGateway([operation]));

    final request = controller.submit('query');
    await operation.started.future;
    controller.clear();
    expect(operation.cancelCalls, 1);
    expect(controller.stage, PlaylistSearchStage.idle);
    result.complete(const PlaylistSearchPageResult(page: 1));
    await request;

    final disposeResult = Completer<PlaylistSearchPageResult>();
    final disposeOperation = _PendingOperation(disposeResult.future);
    final disposed = PlaylistSearchController(
      _ScriptedGateway([disposeOperation]),
    );
    final disposedRequest = disposed.submit('dispose query');
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(const PlaylistSearchPageResult(page: 1));
    await disposedRequest;
  });
}

class _ScriptedGateway implements PlaylistSearchGateway {
  _ScriptedGateway(this.operations);

  final List<PlaylistSearchPageLoadOperation> operations;
  final List<(String, int, int)> requests = [];
  int _next = 0;

  @override
  PlaylistSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return operations[_next++];
  }
}

class _ImmediateOperation implements PlaylistSearchPageLoadOperation {
  const _ImmediateOperation(this.result);

  final PlaylistSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistSearchPageResult> run() async => result;
}

class _PendingOperation implements PlaylistSearchPageLoadOperation {
  _PendingOperation(this.result);

  final Future<PlaylistSearchPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<PlaylistSearchPageResult> run() {
    started.complete();
    return result;
  }
}
