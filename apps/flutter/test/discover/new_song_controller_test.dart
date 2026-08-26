import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/new_song_controller.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

void main() {
  const first = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:41001:0:firstMid:-',
    title: 'First Track',
    artistNames: ['Artist'],
  );
  const second = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:41002:0:secondMid:-',
    title: 'Second Track',
    artistNames: ['Artist'],
  );

  test('loads latest and retries a retryable failure', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        NewSongResult(
          category: NewSongCategory.latest,
          failure: NewSongFailure.network,
        ),
      ),
      const _ImmediateOperation(
        NewSongResult(category: NewSongCategory.latest, tracks: [first]),
      ),
    ]);
    final controller = NewSongController(gateway);

    await controller.load();
    expect(controller.stage, NewSongStage.error);
    expect(controller.canRetry, isTrue);
    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, NewSongStage.content);
    expect(controller.tracks, [first]);
    expect(gateway.requests, [NewSongCategory.latest, NewSongCategory.latest]);
    controller.dispose();
  });

  test('category replacement cancels and suppresses stale content', () async {
    final firstResult = Completer<NewSongResult>();
    final pending = _PendingOperation(firstResult.future);
    final gateway = _ScriptedGateway([
      pending,
      const _ImmediateOperation(
        NewSongResult(category: NewSongCategory.japan, tracks: [second]),
      ),
    ]);
    final controller = NewSongController(gateway);

    final firstLoad = controller.load();
    await pending.started.future;
    controller.selectCategory(NewSongCategory.japan);
    await Future<void>.delayed(Duration.zero);
    expect(pending.cancelCalls, 1);
    expect(controller.category, NewSongCategory.japan);
    expect(controller.tracks, [second]);
    firstResult.complete(
      const NewSongResult(category: NewSongCategory.latest, tracks: [first]),
    );
    await firstLoad;
    expect(controller.tracks, [second]);
    controller.dispose();
  });

  test('empty and disposal remain terminal for their generation', () async {
    final empty = NewSongController(
      _ScriptedGateway([
        const _ImmediateOperation(
          NewSongResult(category: NewSongCategory.latest),
        ),
      ]),
    );
    await empty.load();
    expect(empty.stage, NewSongStage.empty);
    empty.dispose();

    final result = Completer<NewSongResult>();
    final operation = _PendingOperation(result.future);
    final disposed = NewSongController(_ScriptedGateway([operation]));
    final load = disposed.load();
    await operation.started.future;
    disposed.dispose();
    expect(operation.cancelCalls, 1);
    result.complete(
      const NewSongResult(category: NewSongCategory.latest, tracks: [first]),
    );
    await load;
  });
}

class _ScriptedGateway implements NewSongGateway {
  _ScriptedGateway(this.operations);

  final List<NewSongLoadOperation> operations;
  final List<NewSongCategory> requests = [];
  int _next = 0;

  @override
  NewSongLoadOperation beginLoad({required NewSongCategory category}) {
    requests.add(category);
    return operations[_next++];
  }
}

class _ImmediateOperation implements NewSongLoadOperation {
  const _ImmediateOperation(this.result);

  final NewSongResult result;

  @override
  bool cancel() => true;

  @override
  Future<NewSongResult> run() async => result;
}

class _PendingOperation implements NewSongLoadOperation {
  _PendingOperation(this.result);

  final Future<NewSongResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<NewSongResult> run() {
    started.complete();
    return result;
  }
}
