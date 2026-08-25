import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_gateway.dart';

void main() {
  test('maps content and empty success separately', () async {
    final gateway = _FakeGateway();
    final controller = OwnedLibraryController(gateway);

    final content = controller.load();
    gateway.complete(
      0,
      const OwnedLibraryResult(
        playlists: [
          OwnedPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'owned:7001:201',
            title: 'Synthetic favorites',
            trackCount: 42,
          ),
        ],
      ),
    );
    await content;
    expect(controller.stage, OwnedLibraryStage.content);
    expect(controller.playlists.single.title, 'Synthetic favorites');

    final empty = controller.load();
    gateway.complete(1, const OwnedLibraryResult());
    await empty;
    expect(controller.stage, OwnedLibraryStage.empty);

    controller.dispose();
  });

  test('keeps transient failure retryable', () async {
    final gateway = _FakeGateway();
    final controller = OwnedLibraryController(gateway);

    final first = controller.load();
    gateway.complete(
      0,
      const OwnedLibraryResult(failure: OwnedLibraryFailure.network),
    );
    await first;
    expect(controller.stage, OwnedLibraryStage.error);
    expect(controller.canRetry, isTrue);

    final retry = controller.load();
    gateway.complete(1, const OwnedLibraryResult());
    await retry;
    expect(controller.stage, OwnedLibraryStage.empty);

    controller.dispose();
  });

  test('restart cancels and suppresses a late result', () async {
    final gateway = _FakeGateway();
    final controller = OwnedLibraryController(gateway);

    final first = controller.load();
    final second = controller.load();
    expect(gateway.operations.first.cancelCalls, 1);

    gateway.complete(1, const OwnedLibraryResult());
    await second;
    expect(controller.stage, OwnedLibraryStage.empty);

    gateway.complete(
      0,
      const OwnedLibraryResult(
        playlists: [
          OwnedPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'owned:late:late',
            title: 'Late result',
          ),
        ],
      ),
    );
    await first;
    expect(controller.stage, OwnedLibraryStage.empty);

    controller.dispose();
  });

  test('dispose cancels and suppresses a late result', () async {
    final gateway = _FakeGateway();
    final controller = OwnedLibraryController(gateway);

    final load = controller.load();
    controller.dispose();
    expect(gateway.operations.single.cancelCalls, 1);

    gateway.complete(0, const OwnedLibraryResult());
    await load;
    expect(controller.stage, OwnedLibraryStage.loading);
  });

  test('maps credential rejection to a sign-in state', () async {
    final gateway = _FakeGateway();
    final controller = OwnedLibraryController(gateway);

    final load = controller.load();
    gateway.complete(
      0,
      const OwnedLibraryResult(failure: OwnedLibraryFailure.credentialRejected),
    );
    await load;

    expect(controller.stage, OwnedLibraryStage.credentialRejected);
    expect(controller.canRetry, isFalse);

    controller.dispose();
  });
}

class _FakeGateway implements OwnedLibraryGateway {
  final List<Completer<OwnedLibraryResult>> _results =
      <Completer<OwnedLibraryResult>>[];
  final List<_FakeOperation> operations = <_FakeOperation>[];

  @override
  OwnedLibraryLoadOperation beginLoad() {
    final result = Completer<OwnedLibraryResult>();
    _results.add(result);
    final operation = _FakeOperation(result.future);
    operations.add(operation);
    return operation;
  }

  void complete(int index, OwnedLibraryResult result) {
    _results[index].complete(result);
  }
}

class _FakeOperation implements OwnedLibraryLoadOperation {
  _FakeOperation(this._result);

  final Future<OwnedLibraryResult> _result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<OwnedLibraryResult> run() => _result;
}
