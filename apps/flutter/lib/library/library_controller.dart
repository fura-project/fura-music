import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/library_gateway.dart';

enum OwnedLibraryStage {
  loading,
  content,
  empty,
  error,
  authenticationRequired,
  credentialRejected,
}

class OwnedLibraryController extends ChangeNotifier {
  OwnedLibraryController(this._gateway);

  final OwnedLibraryGateway _gateway;

  OwnedLibraryStage _stage = OwnedLibraryStage.loading;
  List<OwnedPlaylistSummary> _playlists = const [];
  OwnedLibraryFailure? _failure;
  OwnedLibraryLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  OwnedLibraryStage get stage => _stage;
  List<OwnedPlaylistSummary> get playlists => _playlists;
  OwnedLibraryFailure? get failure => _failure;

  bool get canRetry =>
      _stage == OwnedLibraryStage.error &&
      (_failure == OwnedLibraryFailure.network ||
          _failure == OwnedLibraryFailure.serviceUnavailable ||
          _failure == OwnedLibraryFailure.invalidResponse ||
          _failure == OwnedLibraryFailure.coreUnavailable);

  Future<void> load() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad();
    _operation = operation;
    _playlists = const [];
    _failure = null;
    _stage = OwnedLibraryStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) {
      _operation = null;
    }
    if (!_isCurrent(generation)) return;

    _failure = result.failure;
    if (result.failure == null) {
      _playlists = List<OwnedPlaylistSummary>.unmodifiable(result.playlists);
      _stage = _playlists.isEmpty
          ? OwnedLibraryStage.empty
          : OwnedLibraryStage.content;
    } else {
      _playlists = const [];
      _stage = switch (result.failure!) {
        OwnedLibraryFailure.authenticationRequired ||
        OwnedLibraryFailure.replaced ||
        OwnedLibraryFailure.cancelled =>
          OwnedLibraryStage.authenticationRequired,
        OwnedLibraryFailure.credentialRejected ||
        OwnedLibraryFailure.credentialRejectedStorageCleanupFailed =>
          OwnedLibraryStage.credentialRejected,
        OwnedLibraryFailure.coreUnavailable ||
        OwnedLibraryFailure.network ||
        OwnedLibraryFailure.serviceUnavailable ||
        OwnedLibraryFailure.invalidResponse ||
        OwnedLibraryFailure.alreadyRunning => OwnedLibraryStage.error,
      };
    }
    _notify();
  }

  void retry() {
    if (!canRetry) return;
    unawaited(load());
  }

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
