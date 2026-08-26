import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_controller.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';

void main() {
  const artist = ArtistSummary(
    providerId: 'qq-music',
    opaqueId: 'artist:61001:fixtureArtistMid',
    name: 'Synthetic artist',
  );
  const firstAlbum = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'album:43001:firstAlbumMid',
    title: 'First album',
  );
  const secondAlbum = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'album:43002:secondAlbumMid',
    title: 'Second album',
  );

  test(
    'loads once lazily and retries a retryable first-page failure',
    () async {
      final gateway = _ScriptedGateway([
        const _ImmediateOperation(
          ArtistAlbumPageResult(failure: ArtistAlbumFailure.network),
        ),
        const _ImmediateOperation(
          ArtistAlbumPageResult(offset: 0, total: 1, albums: [firstAlbum]),
        ),
      ]);
      final controller = ArtistAlbumController(artist, gateway);

      expect(controller.hasLoaded, isFalse);
      await controller.load();
      expect(controller.stage, ArtistAlbumStage.error);
      expect(controller.hasLoaded, isTrue);
      expect(controller.canRetry, isTrue);
      controller.retry();
      await Future<void>.delayed(Duration.zero);
      expect(controller.stage, ArtistAlbumStage.content);
      expect(controller.albums, [firstAlbum]);
      await controller.load();
      expect(gateway.requests, [(artist, 0, 30), (artist, 0, 30)]);
      controller.dispose();
    },
  );

  test('separates an empty page from invalid pagination', () async {
    final empty = ArtistAlbumController(
      artist,
      _ScriptedGateway([const _ImmediateOperation(ArtistAlbumPageResult())]),
    );
    await empty.load();
    expect(empty.stage, ArtistAlbumStage.empty);
    expect(empty.failure, isNull);

    final invalid = ArtistAlbumController(
      artist,
      _ScriptedGateway([
        const _ImmediateOperation(
          ArtistAlbumPageResult(offset: 1, total: 2, albums: [firstAlbum]),
        ),
      ]),
    );
    await invalid.load();
    expect(invalid.stage, ArtistAlbumStage.error);
    expect(invalid.failure, ArtistAlbumFailure.invalidResponse);
    empty.dispose();
    invalid.dispose();
  });

  test(
    'paginates, deduplicates, and retains content on append failure',
    () async {
      final gateway = _ScriptedGateway([
        const _ImmediateOperation(
          ArtistAlbumPageResult(
            offset: 0,
            total: 3,
            hasMore: true,
            albums: [firstAlbum],
          ),
        ),
        const _ImmediateOperation(
          ArtistAlbumPageResult(
            offset: 1,
            total: 3,
            albums: [firstAlbum, secondAlbum],
          ),
        ),
      ]);
      final controller = ArtistAlbumController(artist, gateway);
      await controller.load();
      await controller.loadMore();
      expect(controller.albums, [firstAlbum, secondAlbum]);

      final failureGateway = _ScriptedGateway([
        const _ImmediateOperation(
          ArtistAlbumPageResult(
            offset: 0,
            total: 2,
            hasMore: true,
            albums: [firstAlbum],
          ),
        ),
        const _ImmediateOperation(
          ArtistAlbumPageResult(failure: ArtistAlbumFailure.network),
        ),
      ]);
      final failureController = ArtistAlbumController(artist, failureGateway);
      await failureController.load();
      await failureController.loadMore();
      expect(failureController.stage, ArtistAlbumStage.content);
      expect(failureController.albums, [firstAlbum]);
      expect(failureController.appendFailure, ArtistAlbumFailure.network);
      expect(failureController.canRetryMore, isTrue);
      controller.dispose();
      failureController.dispose();
    },
  );

  test('replacement and disposal cancel and suppress late results', () async {
    final firstResult = Completer<ArtistAlbumPageResult>();
    final firstOperation = _PendingOperation(firstResult.future);
    final gateway = _ScriptedGateway([
      firstOperation,
      const _ImmediateOperation(
        ArtistAlbumPageResult(offset: 0, total: 1, albums: [secondAlbum]),
      ),
    ]);
    final controller = ArtistAlbumController(artist, gateway);

    final firstLoad = controller.load();
    await firstOperation.started.future;
    await controller.load();
    expect(firstOperation.cancelCalls, 1);
    firstResult.complete(
      const ArtistAlbumPageResult(offset: 0, total: 1, albums: [firstAlbum]),
    );
    await firstLoad;
    expect(controller.albums, [secondAlbum]);

    final disposeResult = Completer<ArtistAlbumPageResult>();
    final disposeOperation = _PendingOperation(disposeResult.future);
    final disposed = ArtistAlbumController(
      artist,
      _ScriptedGateway([disposeOperation]),
    );
    final disposedLoad = disposed.load();
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(const ArtistAlbumPageResult());
    await disposedLoad;
    controller.dispose();
  });
}

class _ScriptedGateway implements ArtistAlbumGateway {
  _ScriptedGateway(this.operations);

  final List<ArtistAlbumPageLoadOperation> operations;
  final List<(ArtistSummary, int, int)> requests = [];
  int _next = 0;

  @override
  ArtistAlbumPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) {
    requests.add((artist, offset, size));
    return operations[_next++];
  }
}

class _ImmediateOperation implements ArtistAlbumPageLoadOperation {
  const _ImmediateOperation(this.result);

  final ArtistAlbumPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistAlbumPageResult> run() async => result;
}

class _PendingOperation implements ArtistAlbumPageLoadOperation {
  _PendingOperation(this.result);

  final Future<ArtistAlbumPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<ArtistAlbumPageResult> run() {
    started.complete();
    return result;
  }
}
