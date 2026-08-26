import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/artist/artist_controller.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

void main() {
  const artist = ArtistSummary(
    providerId: 'qq-music',
    opaqueId: 'artist:61001:fixtureArtistMid',
    name: 'Synthetic artist',
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
        ArtistTrackPageResult(failure: ArtistTrackFailure.network),
      ),
      const _ImmediateOperation(
        ArtistTrackPageResult(offset: 0, total: 1, tracks: [firstTrack]),
      ),
    ]);
    final controller = ArtistController(artist, gateway);

    await controller.load();
    expect(controller.stage, ArtistTrackStage.error);
    expect(controller.canRetry, isTrue);
    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, ArtistTrackStage.content);
    expect(controller.tracks, [firstTrack]);
    expect(gateway.requests, [(artist, 0, 30), (artist, 0, 30)]);
    controller.dispose();
  });

  test('paginates, deduplicates, and retains content on failure', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        ArtistTrackPageResult(
          offset: 0,
          total: 3,
          hasMore: true,
          tracks: [firstTrack],
        ),
      ),
      const _ImmediateOperation(
        ArtistTrackPageResult(
          offset: 1,
          total: 3,
          tracks: [firstTrack, secondTrack],
        ),
      ),
    ]);
    final controller = ArtistController(artist, gateway);
    await controller.load();
    await controller.loadMore();
    expect(controller.tracks, [firstTrack, secondTrack]);

    final failureGateway = _ScriptedGateway([
      const _ImmediateOperation(
        ArtistTrackPageResult(
          offset: 0,
          total: 2,
          hasMore: true,
          tracks: [firstTrack],
        ),
      ),
      const _ImmediateOperation(
        ArtistTrackPageResult(failure: ArtistTrackFailure.network),
      ),
    ]);
    final failureController = ArtistController(artist, failureGateway);
    await failureController.load();
    await failureController.loadMore();
    expect(failureController.stage, ArtistTrackStage.content);
    expect(failureController.tracks, [firstTrack]);
    expect(failureController.appendFailure, ArtistTrackFailure.network);
    expect(failureController.canRetryMore, isTrue);
    controller.dispose();
    failureController.dispose();
  });

  test('replacement and disposal cancel and suppress late results', () async {
    final firstResult = Completer<ArtistTrackPageResult>();
    final firstOperation = _PendingOperation(firstResult.future);
    final gateway = _ScriptedGateway([
      firstOperation,
      const _ImmediateOperation(
        ArtistTrackPageResult(offset: 0, total: 1, tracks: [secondTrack]),
      ),
    ]);
    final controller = ArtistController(artist, gateway);

    final firstLoad = controller.load();
    await firstOperation.started.future;
    await controller.load();
    expect(firstOperation.cancelCalls, 1);
    firstResult.complete(
      const ArtistTrackPageResult(offset: 0, total: 1, tracks: [firstTrack]),
    );
    await firstLoad;
    expect(controller.tracks, [secondTrack]);

    final disposeResult = Completer<ArtistTrackPageResult>();
    final disposeOperation = _PendingOperation(disposeResult.future);
    final disposed = ArtistController(
      artist,
      _ScriptedGateway([disposeOperation]),
    );
    final disposedLoad = disposed.load();
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(const ArtistTrackPageResult());
    await disposedLoad;
    controller.dispose();
  });
}

class _ScriptedGateway implements ArtistTrackGateway {
  _ScriptedGateway(this.operations);

  final List<ArtistTrackPageLoadOperation> operations;
  final List<(ArtistSummary, int, int)> requests = [];
  int _next = 0;

  @override
  ArtistTrackPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) {
    requests.add((artist, offset, size));
    return operations[_next++];
  }
}

class _ImmediateOperation implements ArtistTrackPageLoadOperation {
  const _ImmediateOperation(this.result);

  final ArtistTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistTrackPageResult> run() async => result;
}

class _PendingOperation implements ArtistTrackPageLoadOperation {
  _PendingOperation(this.result);

  final Future<ArtistTrackPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<ArtistTrackPageResult> run() {
    started.complete();
    return result;
  }
}
