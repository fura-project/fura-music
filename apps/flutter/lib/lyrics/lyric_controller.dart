import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';

enum LyricStage {
  idle,
  loading,
  content,
  unavailable,
  error,
  authenticationRequired,
  credentialRejected,
}

class LyricController extends ChangeNotifier {
  LyricController(this._gateway);

  final LyricGateway _gateway;

  LyricStage _stage = LyricStage.idle;
  PlaylistTrackSummary? _track;
  SynchronizedLyrics? _lyrics;
  LyricFailure? _failure;
  LyricLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  LyricStage get stage => _stage;
  PlaylistTrackSummary? get track => _track;
  SynchronizedLyrics? get lyrics => _lyrics;
  LyricFailure? get failure => _failure;
  bool get canRetry =>
      _stage == LyricStage.error &&
      (_failure == LyricFailure.coreUnavailable ||
          _failure == LyricFailure.network ||
          _failure == LyricFailure.serviceUnavailable ||
          _failure == LyricFailure.invalidResponse);

  Future<void> load(PlaylistTrackSummary track) async {
    if (_disposed) return;
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(
      providerId: track.providerId,
      opaqueTrackId: track.opaqueId,
    );
    _operation = operation;
    _track = track;
    _lyrics = null;
    _failure = null;
    _stage = LyricStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    _lyrics = result.lyrics;
    _failure = result.failure;
    if (result.failure == null && result.lyrics != null) {
      _stage = LyricStage.content;
    } else {
      _lyrics = null;
      _failure ??= LyricFailure.invalidResponse;
      _stage = switch (_failure!) {
        LyricFailure.unavailable => LyricStage.unavailable,
        LyricFailure.authenticationRequired ||
        LyricFailure.replaced => LyricStage.authenticationRequired,
        LyricFailure.credentialRejected ||
        LyricFailure.credentialRejectedStorageCleanupFailed =>
          LyricStage.credentialRejected,
        LyricFailure.coreUnavailable ||
        LyricFailure.network ||
        LyricFailure.serviceUnavailable ||
        LyricFailure.invalidResponse ||
        LyricFailure.cancelled ||
        LyricFailure.alreadyRunning => LyricStage.error,
      };
    }
    _notify();
  }

  void retry() {
    final current = _track;
    if (current != null && canRetry) unawaited(load(current));
  }

  void clear() {
    if (_disposed) return;
    ++_generation;
    _operation?.cancel();
    _operation = null;
    _track = null;
    _lyrics = null;
    _failure = null;
    _stage = LyricStage.idle;
    _notify();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      ++_generation;
      _operation?.cancel();
      _operation = null;
    }
    super.dispose();
  }
}
