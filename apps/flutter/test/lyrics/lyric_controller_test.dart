import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';

void main() {
  test('loads synchronized content for the exact selected track', () async {
    final gateway = _ScriptedGateway([_PendingOperation.completed(_success())]);
    final controller = LyricController(gateway);

    await controller.load(_track('first'));

    expect(controller.stage, LyricStage.content);
    expect(controller.track?.opaqueId, 'first');
    expect(controller.lyrics?.lines.single.text, 'synthetic line');
    expect(controller.failure, isNull);
    expect(gateway.identities, [('qq-music', 'first')]);
  });

  test('track replacement cancels and suppresses a late old result', () async {
    final first = _PendingOperation();
    final second = _PendingOperation();
    final gateway = _ScriptedGateway([first, second]);
    final controller = LyricController(gateway);

    final firstLoad = controller.load(_track('first'));
    final secondLoad = controller.load(_track('second'));
    expect(first.cancelCalls, 1);
    expect(controller.track?.opaqueId, 'second');
    expect(controller.stage, LyricStage.loading);

    first.complete(_success(text: 'late first'));
    await firstLoad;
    expect(controller.track?.opaqueId, 'second');
    expect(controller.stage, LyricStage.loading);

    second.complete(_success(text: 'current second'));
    await secondLoad;
    expect(controller.stage, LyricStage.content);
    expect(controller.lyrics?.lines.single.text, 'current second');
  });

  test('clear and dispose cancel work and suppress late completion', () async {
    final clearOperation = _PendingOperation();
    final clearController = LyricController(_ScriptedGateway([clearOperation]));
    final clearingLoad = clearController.load(_track('clear'));
    clearController.clear();
    expect(clearOperation.cancelCalls, 1);
    expect(clearController.stage, LyricStage.idle);
    expect(clearController.track, isNull);
    expect(clearController.lyrics, isNull);
    clearOperation.complete(_success(text: 'late clear'));
    await clearingLoad;
    expect(clearController.stage, LyricStage.idle);

    final disposeOperation = _PendingOperation();
    final disposedController = LyricController(
      _ScriptedGateway([disposeOperation]),
    );
    final disposedLoad = disposedController.load(_track('dispose'));
    disposedController.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeOperation.complete(_success(text: 'late dispose'));
    await disposedLoad;
    expect(disposedController.lyrics, isNull);
    await disposedController.load(_track('after-dispose'));
  });

  test(
    'maps availability, account, rejection, and retryable failures',
    () async {
      final cases = [
        (LyricFailure.unavailable, LyricStage.unavailable, false),
        (
          LyricFailure.authenticationRequired,
          LyricStage.authenticationRequired,
          false,
        ),
        (LyricFailure.replaced, LyricStage.authenticationRequired, false),
        (LyricFailure.credentialRejected, LyricStage.credentialRejected, false),
        (LyricFailure.network, LyricStage.error, true),
        (LyricFailure.invalidResponse, LyricStage.error, true),
        (LyricFailure.alreadyRunning, LyricStage.error, false),
      ];

      for (final (failure, stage, canRetry) in cases) {
        final controller = LyricController(
          _ScriptedGateway([
            _PendingOperation.completed(LyricLoadResult(failure: failure)),
          ]),
        );
        await controller.load(_track(failure.name));
        expect(controller.stage, stage, reason: failure.name);
        expect(controller.failure, failure, reason: failure.name);
        expect(controller.canRetry, canRetry, reason: failure.name);
        controller.dispose();
      }
    },
  );
}

PlaylistTrackSummary _track(String opaqueId) => PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: opaqueId,
  title: 'Synthetic track',
  artistNames: const ['Synthetic artist'],
);

LyricLoadResult _success({String text = 'synthetic line'}) => LyricLoadResult(
  lyrics: SynchronizedLyrics([
    SynchronizedLyricLine(
      text: text,
      startMs: 1000,
      durationMs: 800,
      segments: const [
        TimedLyricSegment(text: 'segment', startMs: 1000, durationMs: 400),
      ],
    ),
  ]),
);

class _ScriptedGateway implements LyricGateway {
  _ScriptedGateway(this._operations);

  final List<_PendingOperation> _operations;
  final List<(String, String)> identities = [];
  int _next = 0;

  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) {
    identities.add((providerId, opaqueTrackId));
    return _operations[_next++];
  }
}

class _PendingOperation implements LyricLoadOperation {
  _PendingOperation();

  _PendingOperation.completed(LyricLoadResult result) {
    _completer.complete(result);
  }

  final Completer<LyricLoadResult> _completer = Completer();
  int cancelCalls = 0;

  void complete(LyricLoadResult result) => _completer.complete(result);

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<LyricLoadResult> run() => _completer.future;
}
