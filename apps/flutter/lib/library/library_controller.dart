import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/library_gateway.dart';

enum UserLibraryStage {
  loading,
  content,
  empty,
  error,
  authenticationRequired,
  credentialRejected,
}

class UserLibraryController extends ChangeNotifier {
  UserLibraryController(this._gateway);

  final UserLibraryGateway _gateway;

  UserLibraryStage _stage = UserLibraryStage.loading;
  List<UserPlaylistSummary> _playlists = const [];
  UserLibraryFailure? _failure;
  UserLibraryLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  UserLibraryStage get stage => _stage;
  List<UserPlaylistSummary> get playlists => _playlists;
  UserLibraryFailure? get failure => _failure;

  bool get canRetry =>
      _stage == UserLibraryStage.error &&
      (_failure == UserLibraryFailure.network ||
          _failure == UserLibraryFailure.serviceUnavailable ||
          _failure == UserLibraryFailure.invalidResponse ||
          _failure == UserLibraryFailure.coreUnavailable);

  Future<void> load() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad();
    _operation = operation;
    _playlists = const [];
    _failure = null;
    _stage = UserLibraryStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) {
      _operation = null;
    }
    if (!_isCurrent(generation)) return;

    _failure = result.failure;
    if (result.failure == null) {
      _playlists = List<UserPlaylistSummary>.unmodifiable(result.playlists);
      _stage = _playlists.isEmpty
          ? UserLibraryStage.empty
          : UserLibraryStage.content;
    } else {
      _playlists = const [];
      _stage = switch (result.failure!) {
        UserLibraryFailure.authenticationRequired ||
        UserLibraryFailure.replaced ||
        UserLibraryFailure.cancelled => UserLibraryStage.authenticationRequired,
        UserLibraryFailure.credentialRejected ||
        UserLibraryFailure.credentialRejectedStorageCleanupFailed =>
          UserLibraryStage.credentialRejected,
        UserLibraryFailure.coreUnavailable ||
        UserLibraryFailure.network ||
        UserLibraryFailure.serviceUnavailable ||
        UserLibraryFailure.invalidResponse ||
        UserLibraryFailure.alreadyRunning => UserLibraryStage.error,
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
