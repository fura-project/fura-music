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
  UserLibraryFailure? _refreshFailure;
  UserLibraryLoadOperation? _operation;
  int _generation = 0;
  bool _isRefreshing = false;
  bool _disposed = false;

  UserLibraryStage get stage => _stage;
  List<UserPlaylistSummary> get playlists => _playlists;
  UserLibraryFailure? get failure => _failure;
  UserLibraryFailure? get refreshFailure => _refreshFailure;
  bool get isLoading => _operation != null;
  bool get isRefreshing => _isRefreshing;

  bool get canRetry =>
      _stage == UserLibraryStage.error && _isRetryable(_failure);

  bool get canRetryRefresh => _isRetryable(_refreshFailure);

  Future<void> load() => _load(preserveSnapshot: false);

  Future<void> refresh() => _load(
    preserveSnapshot:
        _stage == UserLibraryStage.content || _stage == UserLibraryStage.empty,
  );

  Future<void> _load({required bool preserveSnapshot}) async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad();
    _operation = operation;
    _failure = null;
    _refreshFailure = null;
    _isRefreshing = preserveSnapshot;
    if (!preserveSnapshot) {
      _playlists = const [];
      _stage = UserLibraryStage.loading;
    }
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) {
      _operation = null;
    }
    if (!_isCurrent(generation)) return;

    _isRefreshing = false;
    _failure = result.failure;
    if (result.failure == null) {
      _playlists = List<UserPlaylistSummary>.unmodifiable(result.playlists);
      _stage = _playlists.isEmpty
          ? UserLibraryStage.empty
          : UserLibraryStage.content;
    } else if (preserveSnapshot && _canRetainSnapshot(result.failure)) {
      _failure = null;
      _refreshFailure = result.failure;
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

  void retryRefresh() {
    if (!canRetryRefresh) return;
    unawaited(refresh());
  }

  void dismissRefreshFailure() {
    if (_refreshFailure == null) return;
    _refreshFailure = null;
    _notify();
  }

  bool _isRetryable(UserLibraryFailure? failure) =>
      failure == UserLibraryFailure.network ||
      failure == UserLibraryFailure.serviceUnavailable ||
      failure == UserLibraryFailure.invalidResponse ||
      failure == UserLibraryFailure.coreUnavailable;

  bool _canRetainSnapshot(UserLibraryFailure? failure) =>
      _isRetryable(failure) || failure == UserLibraryFailure.alreadyRunning;

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
    _isRefreshing = false;
    super.dispose();
  }
}
