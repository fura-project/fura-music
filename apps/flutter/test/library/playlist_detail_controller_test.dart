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
        total: 101,
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
    expect(controller.total, 101);
    expect(controller.hasMore, isTrue);
    expect(controller.tracks.single.title, 'Synthetic track');
    expect(gateway.requests.single.offset, 0);
    expect(gateway.requests.single.size, PlaylistDetailController.pageSize);

    final empty = controller.load();
    gateway.complete(1, const PlaylistTrackPageResult());
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
