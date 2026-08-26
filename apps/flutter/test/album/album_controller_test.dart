import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_controller.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

void main() {
  const album = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'album:51001:fixtureAlbumMid',
    title: 'Synthetic album',
  );
  const firstTrack = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:41001:0:firstMid:-',
    title: 'First track',
    artistNames: ['Artist'],
  );
  const secondTrack = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:41002:0:secondMid:-',
    title: 'Second track',
    artistNames: ['Artist'],
  );

  test('loads content and retries a retryable first-page failure', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        AlbumTrackPageResult(failure: AlbumTrackFailure.network),
      ),
      const _ImmediateOperation(
        AlbumTrackPageResult(offset: 0, total: 1, tracks: [firstTrack]),
      ),
    ]);
    final controller = AlbumController(album, gateway);

    await controller.load();
    expect(controller.stage, AlbumTrackStage.error);
    expect(controller.failure, AlbumTrackFailure.network);
    expect(controller.canRetry, isTrue);

    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, AlbumTrackStage.content);
    expect(controller.tracks, [firstTrack]);
    expect(gateway.requests, [(album, 0, 30), (album, 0, 30)]);
    controller.dispose();
  });

  test(
    'paginates, deduplicates, and retains content on append failure',
    () async {
      final gateway = _ScriptedGateway([
        const _ImmediateOperation(
          AlbumTrackPageResult(
            offset: 0,
            total: 3,
            hasMore: true,
            tracks: [firstTrack],
          ),
        ),
        const _ImmediateOperation(
          AlbumTrackPageResult(
            offset: 1,
            total: 3,
            tracks: [firstTrack, secondTrack],
          ),
        ),
      ]);
      final controller = AlbumController(album, gateway);

      await controller.load();
      await controller.loadMore();
      expect(controller.tracks, [firstTrack, secondTrack]);
      expect(controller.hasMore, isFalse);

      final retryGateway = _ScriptedGateway([
        const _ImmediateOperation(
          AlbumTrackPageResult(
            offset: 0,
            total: 2,
            hasMore: true,
            tracks: [firstTrack],
          ),
        ),
        const _ImmediateOperation(
          AlbumTrackPageResult(failure: AlbumTrackFailure.network),
        ),
      ]);
      final retryController = AlbumController(album, retryGateway);
      await retryController.load();
      await retryController.loadMore();
      expect(retryController.stage, AlbumTrackStage.content);
      expect(retryController.tracks, [firstTrack]);
      expect(retryController.appendFailure, AlbumTrackFailure.network);
      expect(retryController.canRetryMore, isTrue);
      controller.dispose();
      retryController.dispose();
    },
  );

  test(
    'replaced and disposed loads cancel and suppress late results',
    () async {
      final firstResult = Completer<AlbumTrackPageResult>();
      final firstOperation = _PendingOperation(firstResult.future);
      final gateway = _ScriptedGateway([
        firstOperation,
        const _ImmediateOperation(
          AlbumTrackPageResult(offset: 0, total: 1, tracks: [secondTrack]),
        ),
      ]);
      final controller = AlbumController(album, gateway);

      final firstLoad = controller.load();
      await firstOperation.started.future;
      await controller.load();
      expect(firstOperation.cancelCalls, 1);
      expect(controller.tracks, [secondTrack]);
      firstResult.complete(
        const AlbumTrackPageResult(offset: 0, total: 1, tracks: [firstTrack]),
      );
      await firstLoad;
      expect(controller.tracks, [secondTrack]);

      final disposeResult = Completer<AlbumTrackPageResult>();
      final disposeOperation = _PendingOperation(disposeResult.future);
      final disposed = AlbumController(
        album,
        _ScriptedGateway([disposeOperation]),
      );
      final disposedLoad = disposed.load();
      await disposeOperation.started.future;
      disposed.dispose();
      expect(disposeOperation.cancelCalls, 1);
      disposeResult.complete(const AlbumTrackPageResult());
      await disposedLoad;
      controller.dispose();
    },
  );
}

class _ScriptedGateway implements AlbumTrackGateway {
  _ScriptedGateway(this.operations);

  final List<AlbumTrackPageLoadOperation> operations;
  final List<(AlbumSummary, int, int)> requests = [];
  int _next = 0;

  @override
  AlbumTrackPageLoadOperation beginLoad({
    required AlbumSummary album,
    required int offset,
    required int size,
  }) {
    requests.add((album, offset, size));
    return operations[_next++];
  }
}

class _ImmediateOperation implements AlbumTrackPageLoadOperation {
  const _ImmediateOperation(this.result);

  final AlbumTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumTrackPageResult> run() async => result;
}

class _PendingOperation implements AlbumTrackPageLoadOperation {
  _PendingOperation(this.result);

  final Future<AlbumTrackPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<AlbumTrackPageResult> run() {
    started.complete();
    return result;
  }
}
