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
