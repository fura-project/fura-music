import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_gateway.dart';

void main() {
  test('maps content and empty success separately', () async {
    final gateway = _FakeGateway();
    final controller = UserLibraryController(gateway);

    final content = controller.load();
    gateway.complete(
      0,
      const UserLibraryResult(
        playlists: [
          UserPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'owned:7001:201',
            title: 'Synthetic favorites',
            trackCount: 42,
          ),
        ],
      ),
    );
    await content;
    expect(controller.stage, UserLibraryStage.content);
    expect(controller.playlists.single.title, 'Synthetic favorites');

    final empty = controller.load();
    gateway.complete(1, const UserLibraryResult());
    await empty;
    expect(controller.stage, UserLibraryStage.empty);

    controller.dispose();
  });

  test('identifies the built-in liked playlist from typed semantics', () async {
    final gateway = _FakeGateway();
    final controller = UserLibraryController(gateway);

    final load = controller.load();
    gateway.complete(
      0,
      const UserLibraryResult(
        playlists: [
          UserPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'owned:7001:201',
            title: 'A regular playlist with a misleading identity',
          ),
          UserPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'opaque-liked-identity',
            title: 'Localized built-in collection',
            isLikedSongs: true,
          ),
        ],
      ),
    );
    await load;

    expect(controller.likedSongsPlaylist?.opaqueId, 'opaque-liked-identity');

    controller.dispose();
  });

  test('keeps transient failure retryable', () async {
    final gateway = _FakeGateway();
    final controller = UserLibraryController(gateway);

    final first = controller.load();
    gateway.complete(
      0,
      const UserLibraryResult(failure: UserLibraryFailure.network),
    );
    await first;
    expect(controller.stage, UserLibraryStage.error);
    expect(controller.canRetry, isTrue);

    final retry = controller.load();
    gateway.complete(1, const UserLibraryResult());
    await retry;
    expect(controller.stage, UserLibraryStage.empty);

    controller.dispose();
  });

  test('restart cancels and suppresses a late result', () async {
    final gateway = _FakeGateway();
    final controller = UserLibraryController(gateway);

    final first = controller.load();
    final second = controller.load();
    expect(gateway.operations.first.cancelCalls, 1);

    gateway.complete(1, const UserLibraryResult());
    await second;
    expect(controller.stage, UserLibraryStage.empty);

    gateway.complete(
      0,
      const UserLibraryResult(
        playlists: [
          UserPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'owned:late:late',
            title: 'Late result',
          ),
        ],
      ),
    );
    await first;
    expect(controller.stage, UserLibraryStage.empty);

    controller.dispose();
  });

  test(
    'refresh retains the last complete snapshot after a transient failure',
    () async {
      final gateway = _FakeGateway();
      final controller = UserLibraryController(gateway);

      final initial = controller.load();
      gateway.complete(
        0,
        const UserLibraryResult(
          playlists: [
            UserPlaylistSummary(
              providerId: 'qq-music',
              opaqueId: 'favorite:current',
              title: 'Current library',
            ),
          ],
        ),
      );
      await initial;

      final refresh = controller.refresh();
      expect(controller.stage, UserLibraryStage.content);
      expect(controller.playlists.single.title, 'Current library');
      expect(controller.isRefreshing, isTrue);
      expect(controller.isLoading, isTrue);

      gateway.complete(
        1,
        const UserLibraryResult(failure: UserLibraryFailure.network),
      );
      await refresh;

      expect(controller.stage, UserLibraryStage.content);
      expect(controller.playlists.single.title, 'Current library');
      expect(controller.isRefreshing, isFalse);
      expect(controller.isLoading, isFalse);
      expect(controller.failure, isNull);
      expect(controller.refreshFailure, UserLibraryFailure.network);
      expect(controller.canRetryRefresh, isTrue);

      final retry = controller.refresh();
      expect(controller.refreshFailure, isNull);
      expect(controller.isRefreshing, isTrue);
      gateway.complete(2, const UserLibraryResult());
      await retry;

      expect(controller.stage, UserLibraryStage.empty);
      expect(controller.playlists, isEmpty);
      expect(controller.refreshFailure, isNull);

      controller.dispose();
    },
  );

  test('refresh clears private content after credential rejection', () async {
    final gateway = _FakeGateway();
    final controller = UserLibraryController(gateway);

    final initial = controller.load();
    gateway.complete(
      0,
      const UserLibraryResult(
        playlists: [
          UserPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'owned:private:201',
            title: 'Private library',
          ),
        ],
      ),
    );
    await initial;

    final refresh = controller.refresh();
    gateway.complete(
      1,
      const UserLibraryResult(failure: UserLibraryFailure.credentialRejected),
    );
    await refresh;

    expect(controller.stage, UserLibraryStage.credentialRejected);
    expect(controller.playlists, isEmpty);
    expect(controller.refreshFailure, isNull);

    controller.dispose();
  });

  test('replacement refresh cancels and suppresses its late result', () async {
    final gateway = _FakeGateway();
    final controller = UserLibraryController(gateway);

    final initial = controller.load();
    gateway.complete(
      0,
      const UserLibraryResult(
        playlists: [
          UserPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'favorite:initial',
            title: 'Initial library',
          ),
        ],
      ),
    );
    await initial;

    final firstRefresh = controller.refresh();
    final replacementRefresh = controller.refresh();
    expect(gateway.operations[1].cancelCalls, 1);

    gateway.complete(
      2,
      const UserLibraryResult(
        playlists: [
          UserPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'favorite:replacement',
            title: 'Replacement library',
          ),
        ],
      ),
    );
    await replacementRefresh;
    expect(controller.playlists.single.title, 'Replacement library');

    gateway.complete(
      1,
      const UserLibraryResult(
        playlists: [
          UserPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'favorite:late',
            title: 'Late library',
          ),
        ],
      ),
    );
    await firstRefresh;
    expect(controller.playlists.single.title, 'Replacement library');

    controller.dispose();
  });

  test('dispose cancels and suppresses a late result', () async {
    final gateway = _FakeGateway();
    final controller = UserLibraryController(gateway);

    final load = controller.load();
    controller.dispose();
    expect(gateway.operations.single.cancelCalls, 1);

    gateway.complete(0, const UserLibraryResult());
    await load;
    expect(controller.stage, UserLibraryStage.loading);
  });

  test('maps credential rejection to a sign-in state', () async {
    final gateway = _FakeGateway();
    final controller = UserLibraryController(gateway);

    final load = controller.load();
    gateway.complete(
      0,
      const UserLibraryResult(failure: UserLibraryFailure.credentialRejected),
    );
    await load;

    expect(controller.stage, UserLibraryStage.credentialRejected);
    expect(controller.canRetry, isFalse);

    controller.dispose();
  });
}

class _FakeGateway implements UserLibraryGateway {
  final List<Completer<UserLibraryResult>> _results =
      <Completer<UserLibraryResult>>[];
  final List<_FakeOperation> operations = <_FakeOperation>[];

  @override
  UserLibraryLoadOperation beginLoad() {
    final result = Completer<UserLibraryResult>();
    _results.add(result);
    final operation = _FakeOperation(result.future);
    operations.add(operation);
    return operation;
  }

  void complete(int index, UserLibraryResult result) {
    _results[index].complete(result);
  }
}

class _FakeOperation implements UserLibraryLoadOperation {
  _FakeOperation(this._result);

  final Future<UserLibraryResult> _result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<UserLibraryResult> run() => _result;
}
