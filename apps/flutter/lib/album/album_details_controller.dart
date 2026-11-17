import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';

enum AlbumDetailsStage { loading, content, error }

class AlbumDetailsController extends ChangeNotifier {
  AlbumDetailsController(this.album, this._gateway);

  final AlbumSummary album;
  final AlbumDetailsGateway _gateway;

  AlbumDetailsStage _stage = AlbumDetailsStage.loading;
  AlbumDetails? _details;
  AlbumDetailsFailure? _failure;
  AlbumDetailsLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  AlbumDetailsStage get stage => _stage;
  AlbumDetails? get details => _details;
  AlbumDetailsFailure? get failure => _failure;
  bool get canRetry =>
      _stage == AlbumDetailsStage.error && _isRetryable(_failure);

  Future<void> load() {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(album);
    _operation = operation;
    _failure = null;

    var completedSynchronously = false;
    final future = operation.run().then((result) {
      completedSynchronously = true;
      _completeLoad(generation, operation, result);
    });
    if (completedSynchronously) {
      return future;
    }

    _details = null;
    _stage = AlbumDetailsStage.loading;
    _notify();
    return future;
  }

  void _completeLoad(
    int generation,
    AlbumDetailsLoadOperation operation,
    AlbumDetailsResult result,
  ) {
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;
    final details = result.details;
    if (details != null && result.failure == null) {
      _details = details;
      _stage = AlbumDetailsStage.content;
    } else {
      _details = null;
      _failure = result.failure ?? AlbumDetailsFailure.invalidResponse;
      _stage = AlbumDetailsStage.error;
    }
    _notify();
  }

  void retry() {
    if (canRetry) unawaited(load());
  }

  bool _isRetryable(AlbumDetailsFailure? failure) =>
      failure == AlbumDetailsFailure.coreUnavailable ||
      failure == AlbumDetailsFailure.network ||
      failure == AlbumDetailsFailure.serviceUnavailable ||
      failure == AlbumDetailsFailure.invalidResponse ||
      failure == AlbumDetailsFailure.alreadyRunning;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _operation?.cancel();
    _operation = null;
    super.dispose();
  }
}
