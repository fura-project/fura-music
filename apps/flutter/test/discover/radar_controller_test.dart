import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/radar_controller.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

void main() {
  test('maps an operation start failure into a retryable error', () async {
    final controller = RadarController(_ThrowingGateway());
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.stage, RadarStage.error);
    expect(controller.failure, RadarFailure.coreUnavailable);
    expect(controller.canRetry, isTrue);
  });

  const first = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:first',
    title: 'First Radar Track',
    artistNames: ['First artist'],
  );
  const second = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:second',
    title: 'Second Radar Track',
    artistNames: ['Second artist'],
  );

  test('loads page one and retries a retryable initial failure', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        RadarTrackPageResult(failure: RadarFailure.network),
      ),
      const _ImmediateOperation(RadarTrackPageResult(page: 1, tracks: [first])),
    ]);
    final controller = RadarController(gateway);

    await controller.load();
    expect(controller.stage, RadarStage.error);
    expect(controller.canRetry, isTrue);

    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, RadarStage.content);
    expect(controller.tracks, [first]);
    expect(gateway.pages, [1, 1]);
    controller.dispose();
  });

  test(
    'pages by service page number and deduplicates overlapping Tracks',
    () async {
      final gateway = _ScriptedGateway([
        const _ImmediateOperation(
          RadarTrackPageResult(page: 1, hasMore: true, tracks: [first]),
        ),
        const _ImmediateOperation(
          RadarTrackPageResult(page: 2, tracks: [first, second]),
        ),
      ]);
      final controller = RadarController(gateway);

      await controller.load();
      await controller.loadMore();
      expect(controller.tracks, [first, second]);
      expect(controller.hasMore, isFalse);
      expect(gateway.pages, [1, 2]);
      controller.dispose();
    },
  );

  test('retains content and exact page after append failure', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        RadarTrackPageResult(page: 1, hasMore: true, tracks: [first]),
      ),
      const _ImmediateOperation(
        RadarTrackPageResult(failure: RadarFailure.network),
      ),
      const _ImmediateOperation(
        RadarTrackPageResult(page: 2, tracks: [second]),
      ),
    ]);
    final controller = RadarController(gateway);

    await controller.load();
    await controller.loadMore();
    expect(controller.tracks, [first]);
    expect(controller.appendFailure, RadarFailure.network);
    expect(controller.canRetryMore, isTrue);

    controller.retryMore();
    await Future<void>.delayed(Duration.zero);
    expect(controller.tracks, [first, second]);
    expect(gateway.pages, [1, 2, 2]);
    controller.dispose();
  });

  test('replacement and disposal cancel and suppress late results', () async {
    final firstResult = Completer<RadarTrackPageResult>();
    final firstOperation = _PendingOperation(firstResult.future);
    final gateway = _ScriptedGateway([
      firstOperation,
      const _ImmediateOperation(
        RadarTrackPageResult(page: 1, tracks: [second]),
      ),
    ]);
    final controller = RadarController(gateway);

    final firstLoad = controller.load();
    await firstOperation.started.future;
    await controller.load();
    expect(firstOperation.cancelCalls, 1);
    expect(controller.tracks, [second]);
    firstResult.complete(const RadarTrackPageResult(page: 1, tracks: [first]));
    await firstLoad;
    expect(controller.tracks, [second]);

    final disposeResult = Completer<RadarTrackPageResult>();
    final disposeOperation = _PendingOperation(disposeResult.future);
    final disposed = RadarController(_ScriptedGateway([disposeOperation]));
    final disposedLoad = disposed.load();
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(const RadarTrackPageResult());
    await disposedLoad;
    controller.dispose();
  });
}

class _ScriptedGateway implements RadarGateway {
  _ScriptedGateway(this.operations);

  final List<RadarTrackPageLoadOperation> operations;
  final List<int> pages = [];
  int _next = 0;

  @override
  RadarTrackPageLoadOperation beginLoad({required int page}) {
    pages.add(page);
    return operations[_next++];
  }
}

class _ImmediateOperation implements RadarTrackPageLoadOperation {
  const _ImmediateOperation(this.result);

  final RadarTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<RadarTrackPageResult> run() async => result;
}

class _PendingOperation implements RadarTrackPageLoadOperation {
  _PendingOperation(this.result);

  final Future<RadarTrackPageResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<RadarTrackPageResult> run() {
    started.complete();
    return result;
  }
}

class _ThrowingGateway implements RadarGateway {
  @override
  RadarTrackPageLoadOperation beginLoad({required int page}) =>
      throw StateError('bridge unavailable');
}
