import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_details_controller.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';

void main() {
  const album = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'album:43001:fixtureAlbumMid',
    title: 'Summary title',
  );
  const details = AlbumDetails(album: album, artists: []);

  test('loads canonical details and retries a first failure', () async {
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(
        AlbumDetailsResult(failure: AlbumDetailsFailure.network),
      ),
      const _ImmediateOperation(AlbumDetailsResult(details: details)),
    ]);
    final controller = AlbumDetailsController(album, gateway);

    await controller.load();
    expect(controller.stage, AlbumDetailsStage.error);
    expect(controller.canRetry, isTrue);
    controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage, AlbumDetailsStage.content);
    expect(controller.details, same(details));
    expect(gateway.albums, [album, album]);
    controller.dispose();
  });

  test('replacement and disposal cancel and suppress stale results', () async {
    final firstResult = Completer<AlbumDetailsResult>();
    final firstOperation = _PendingOperation(firstResult.future);
    final gateway = _ScriptedGateway([
      firstOperation,
      const _ImmediateOperation(AlbumDetailsResult(details: details)),
    ]);
    final controller = AlbumDetailsController(album, gateway);

    final firstLoad = controller.load();
    await firstOperation.started.future;
    await controller.load();
    expect(firstOperation.cancelCalls, 1);
    firstResult.complete(
      const AlbumDetailsResult(failure: AlbumDetailsFailure.network),
    );
    await firstLoad;
    expect(controller.stage, AlbumDetailsStage.content);

    final disposeResult = Completer<AlbumDetailsResult>();
    final disposeOperation = _PendingOperation(disposeResult.future);
    final disposed = AlbumDetailsController(
      album,
      _ScriptedGateway([disposeOperation]),
    );
    final disposedLoad = disposed.load();
    await disposeOperation.started.future;
    disposed.dispose();
    expect(disposeOperation.cancelCalls, 1);
    disposeResult.complete(const AlbumDetailsResult(details: details));
    await disposedLoad;
    controller.dispose();
  });
}

class _ScriptedGateway implements AlbumDetailsGateway {
  _ScriptedGateway(this.operations);

  final List<AlbumDetailsLoadOperation> operations;
  final List<AlbumSummary> albums = [];
  int _next = 0;

  @override
  AlbumDetailsLoadOperation beginLoad(AlbumSummary album) {
    albums.add(album);
    return operations[_next++];
  }
}

class _ImmediateOperation implements AlbumDetailsLoadOperation {
  const _ImmediateOperation(this.result);

  final AlbumDetailsResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumDetailsResult> run() async => result;
}

class _PendingOperation implements AlbumDetailsLoadOperation {
  _PendingOperation(this.result);

  final Future<AlbumDetailsResult> result;
  final Completer<void> started = Completer<void>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<AlbumDetailsResult> run() {
    started.complete();
    return result;
  }
}
