import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

void main() {
  const playlist = UserPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'favorite:8001',
    title: 'Synthetic playlist',
  );

  test('maps first-page content, empty, and pagination metadata', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(playlist, gateway);

    final content = controller.load();
    gateway.complete(
      0,
      const PlaylistTrackPageResult(
        total: 2,
        hasMore: true,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:opaque',
            title: 'Synthetic track',
            artistNames: ['Artist'],
          ),
        ],
      ),
    );
    await content;
    expect(controller.stage, PlaylistDetailStage.content);
    expect(controller.total, 2);
    expect(controller.hasMore, isTrue);
    expect(controller.tracks.single.title, 'Synthetic track');
    expect(gateway.requests.single.offset, 0);
    expect(gateway.requests.single.size, PlaylistDetailController.pageSize);

    final more = controller.loadMore();
    gateway.complete(
      1,
      const PlaylistTrackPageResult(
        offset: 1,
        total: 2,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:opaque',
            title: 'Duplicate track',
            artistNames: ['Artist'],
          ),
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:second',
            title: 'Second track',
            artistNames: ['Artist'],
          ),
        ],
      ),
    );
    await more;
    expect(controller.tracks.map((track) => track.title), [
      'Synthetic track',
      'Second track',
    ]);
    expect(controller.hasMore, isFalse);
    expect(gateway.requests[1].offset, 1);

    final empty = controller.load();
    gateway.complete(2, const PlaylistTrackPageResult());
    await empty;
    expect(controller.stage, PlaylistDetailStage.empty);
    controller.dispose();
  });

  test(
    'keeps transient failure retryable and rejects a wrong page offset',
    () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(playlist, gateway);

      final first = controller.load();
      gateway.complete(
        0,
        const PlaylistTrackPageResult(failure: UserLibraryFailure.network),
      );
      await first;
      expect(controller.stage, PlaylistDetailStage.error);
      expect(controller.canRetry, isTrue);

      final second = controller.load();
      gateway.complete(1, const PlaylistTrackPageResult(offset: 100));
      await second;
      expect(controller.stage, PlaylistDetailStage.error);
      expect(controller.failure, UserLibraryFailure.invalidResponse);

      final nonAdvancing = controller.load();
      gateway.complete(
        2,
        const PlaylistTrackPageResult(total: 1, hasMore: true),
      );
      await nonAdvancing;
      expect(controller.stage, PlaylistDetailStage.error);
      expect(controller.failure, UserLibraryFailure.invalidResponse);
      controller.dispose();
    },
  );

  test('retains loaded rows after a retryable append failure', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(playlist, gateway);
    final first = controller.load();
    gateway.complete(
      0,
      const PlaylistTrackPageResult(
        total: 2,
        hasMore: true,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:first',
            title: 'First track',
            artistNames: [],
          ),
        ],
      ),
    );
    await first;

    final more = controller.loadMore();
    gateway.complete(
      1,
      const PlaylistTrackPageResult(
        offset: 1,
        failure: UserLibraryFailure.network,
      ),
    );
    await more;
    expect(controller.stage, PlaylistDetailStage.content);
    expect(controller.tracks.single.title, 'First track');
    expect(controller.appendFailure, UserLibraryFailure.network);
    expect(controller.canRetryMore, isTrue);

    final invalidPage = controller.loadMore();
    gateway.complete(
      2,
      const PlaylistTrackPageResult(
        offset: 99,
        total: 2,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:second',
            title: 'Second track',
            artistNames: [],
          ),
        ],
      ),
    );
    await invalidPage;
    expect(controller.tracks.single.title, 'First track');
    expect(controller.appendFailure, UserLibraryFailure.invalidResponse);
    controller.dispose();
  });

  test(
    'refresh retains the complete paged snapshot after transient failure',
    () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(playlist, gateway);
      final initial = controller.load();
      gateway.complete(
        0,
        const PlaylistTrackPageResult(
          total: 3,
          hasMore: true,
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:current',
              title: 'Current track',
              artistNames: [],
            ),
          ],
        ),
      );
      await initial;

      final refresh = controller.refresh();
      expect(controller.stage, PlaylistDetailStage.content);
      expect(controller.tracks.single.title, 'Current track');
      expect(controller.total, 3);
      expect(controller.hasMore, isTrue);
      expect(controller.isRefreshing, isTrue);
      expect(controller.isLoading, isTrue);
      expect(controller.canLoadMore, isFalse);

      gateway.complete(
        1,
        const PlaylistTrackPageResult(failure: UserLibraryFailure.network),
      );
      await refresh;

      expect(controller.stage, PlaylistDetailStage.content);
      expect(controller.tracks.single.title, 'Current track');
      expect(controller.total, 3);
      expect(controller.hasMore, isTrue);
      expect(controller.refreshFailure, UserLibraryFailure.network);
      expect(controller.canRetryRefresh, isTrue);
      expect(controller.canLoadMore, isTrue);

      final retry = controller.refresh();
      gateway.complete(
        2,
        const PlaylistTrackPageResult(
          total: 1,
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:fresh',
              title: 'Fresh track',
              artistNames: [],
            ),
          ],
        ),
      );
      await retry;

      expect(controller.tracks.single.title, 'Fresh track');
      expect(controller.total, 1);
      expect(controller.hasMore, isFalse);
      expect(controller.refreshFailure, isNull);

      controller.dispose();
    },
  );

  test('refresh clears loaded tracks after credential rejection', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(playlist, gateway);
    final initial = controller.load();
    gateway.complete(
      0,
      const PlaylistTrackPageResult(
        total: 1,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:private',
            title: 'Private track',
            artistNames: [],
          ),
        ],
      ),
    );
    await initial;

    final refresh = controller.refresh();
    gateway.complete(
      1,
      const PlaylistTrackPageResult(
        failure: UserLibraryFailure.credentialRejected,
      ),
    );
    await refresh;

    expect(controller.stage, PlaylistDetailStage.credentialRejected);
    expect(controller.tracks, isEmpty);
    expect(controller.total, 0);
    expect(controller.refreshFailure, isNull);

    controller.dispose();
  });

  test(
    'replacement detail refresh cancels and suppresses its late result',
    () async {
      final gateway = _FakeDetailGateway();
      final controller = PlaylistDetailController(playlist, gateway);
      final initial = controller.load();
      gateway.complete(0, const PlaylistTrackPageResult());
      await initial;

      final firstRefresh = controller.refresh();
      final replacementRefresh = controller.refresh();
      expect(gateway.operations[1].cancelCalls, 1);

      gateway.complete(
        2,
        const PlaylistTrackPageResult(
          total: 1,
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:replacement',
              title: 'Replacement track',
              artistNames: [],
            ),
          ],
        ),
      );
      await replacementRefresh;

      gateway.complete(
        1,
        const PlaylistTrackPageResult(
          total: 1,
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:late',
              title: 'Late track',
              artistNames: [],
            ),
          ],
        ),
      );
      await firstRefresh;

      expect(controller.tracks.single.title, 'Replacement track');
      controller.dispose();
    },
  );

  test('restart and dispose cancel and suppress late results', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(playlist, gateway);

    final first = controller.load();
    final second = controller.load();
    expect(gateway.operations.first.cancelCalls, 1);
    gateway.complete(1, const PlaylistTrackPageResult());
    await second;
    gateway.complete(
      0,
      const PlaylistTrackPageResult(
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'late',
            title: 'Late track',
            artistNames: [],
          ),
        ],
      ),
    );
    await first;
    expect(controller.stage, PlaylistDetailStage.empty);

    final third = controller.load();
    controller.dispose();
    expect(gateway.operations.last.cancelCalls, 1);
    gateway.complete(2, const PlaylistTrackPageResult());
    await third;
  });

  test('maps credential rejection to a sign-in state', () async {
    final gateway = _FakeDetailGateway();
    final controller = PlaylistDetailController(playlist, gateway);
    final load = controller.load();
    gateway.complete(
      0,
      const PlaylistTrackPageResult(
        failure: UserLibraryFailure.credentialRejected,
      ),
    );
    await load;
    expect(controller.stage, PlaylistDetailStage.credentialRejected);
    expect(controller.canRetry, isFalse);
    controller.dispose();
  });
}

class _Request {
  const _Request(this.playlist, this.offset, this.size);
  final UserPlaylistSummary playlist;
  final int offset;
  final int size;
}

class _FakeDetailGateway implements PlaylistDetailGateway {
  final List<Completer<PlaylistTrackPageResult>> _results = [];
  final List<_FakeDetailOperation> operations = [];
  final List<_Request> requests = [];

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    final result = Completer<PlaylistTrackPageResult>();
    _results.add(result);
    requests.add(_Request(playlist, offset, size));
    final operation = _FakeDetailOperation(result.future);
    operations.add(operation);
    return operation;
  }

  void complete(int index, PlaylistTrackPageResult result) {
    _results[index].complete(result);
  }
}

class _FakeDetailOperation implements PlaylistTrackPageLoadOperation {
  _FakeDetailOperation(this._result);
  final Future<PlaylistTrackPageResult> _result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<PlaylistTrackPageResult> run() => _result;
}
