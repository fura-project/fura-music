import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum PlaylistDetailStage {
  loading,
  content,
  empty,
  error,
  authenticationRequired,
  credentialRejected,
}

class PlaylistDetailController extends ChangeNotifier {
  PlaylistDetailController(this.playlist, this._gateway);

  static const pageSize = 100;

  final UserPlaylistSummary playlist;
  final PlaylistDetailGateway _gateway;

  PlaylistDetailStage _stage = PlaylistDetailStage.loading;
  List<PlaylistTrackSummary> _tracks = const [];
  UserLibraryFailure? _failure;
  int _total = 0;
  bool _hasMore = false;
  int _nextOffset = 0;
  bool _isLoadingMore = false;
  bool _isRefreshing = false;
  UserLibraryFailure? _appendFailure;
  UserLibraryFailure? _refreshFailure;
  PlaylistTrackPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  PlaylistDetailStage get stage => _stage;
  List<PlaylistTrackSummary> get tracks => _tracks;
  UserLibraryFailure? get failure => _failure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get isLoading => _operation != null;
  bool get isRefreshing => _isRefreshing;
  UserLibraryFailure? get appendFailure => _appendFailure;
  UserLibraryFailure? get refreshFailure => _refreshFailure;
  bool get canLoadMore =>
      _stage == PlaylistDetailStage.content &&
      _hasMore &&
      !_isLoadingMore &&
      !_isRefreshing;
  bool get canRetryMore => !_isRefreshing && _isRetryable(_appendFailure);

  bool get canRetry =>
      _stage == PlaylistDetailStage.error && _isRetryable(_failure);

  bool get canRetryRefresh => _isRetryable(_refreshFailure);

  Future<void> load() => _load(preserveSnapshot: false);

  Future<void> refresh() => _load(
    preserveSnapshot:
        _stage == PlaylistDetailStage.content ||
        _stage == PlaylistDetailStage.empty,
  );

  Future<void> _load({required bool preserveSnapshot}) async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(
      playlist: playlist,
      offset: 0,
      size: pageSize,
    );
    _operation = operation;
    _failure = null;
    _isLoadingMore = false;
    _isRefreshing = preserveSnapshot;
    _appendFailure = null;
    _refreshFailure = null;
    if (!preserveSnapshot) {
      _tracks = const [];
      _total = 0;
      _hasMore = false;
      _nextOffset = 0;
      _stage = PlaylistDetailStage.loading;
    }
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    _isRefreshing = false;
    final validSuccess =
        result.failure == null &&
        result.offset == 0 &&
        (!result.hasMore || result.tracks.isNotEmpty);
    if (validSuccess) {
      _tracks = List.unmodifiable(result.tracks);
      _total = result.total;
      _hasMore = result.hasMore;
      _nextOffset = result.tracks.length;
      _failure = null;
      _stage = _tracks.isEmpty
          ? PlaylistDetailStage.empty
          : PlaylistDetailStage.content;
    } else if (preserveSnapshot &&
        _canRetainSnapshot(
          result.failure ?? UserLibraryFailure.invalidResponse,
        )) {
      _failure = null;
      _refreshFailure = result.failure ?? UserLibraryFailure.invalidResponse;
    } else {
      _tracks = const [];
      _total = 0;
      _hasMore = false;
      _nextOffset = 0;
      _failure = result.failure ?? UserLibraryFailure.invalidResponse;
      _stage = switch (_failure!) {
        UserLibraryFailure.authenticationRequired ||
        UserLibraryFailure.replaced ||
        UserLibraryFailure.cancelled =>
          PlaylistDetailStage.authenticationRequired,
        UserLibraryFailure.credentialRejected ||
        UserLibraryFailure.credentialRejectedStorageCleanupFailed =>
          PlaylistDetailStage.credentialRejected,
        UserLibraryFailure.coreUnavailable ||
        UserLibraryFailure.network ||
        UserLibraryFailure.serviceUnavailable ||
        UserLibraryFailure.invalidResponse ||
        UserLibraryFailure.alreadyRunning => PlaylistDetailStage.error,
      };
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (!canLoadMore && !canRetryMore) return;
    final generation = _generation;
    final expectedOffset = _nextOffset;
    final operation = _gateway.beginLoad(
      playlist: playlist,
      offset: expectedOffset,
      size: pageSize,
    );
    _operation = operation;
    _isLoadingMore = true;
    _appendFailure = null;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;
    _isLoadingMore = false;

    if (result.failure == null &&
        result.offset == expectedOffset &&
        (!result.hasMore || result.tracks.isNotEmpty)) {
      final seen = _tracks
          .map((track) => '${track.providerId}\u0000${track.opaqueId}')
          .toSet();
      final additions = result.tracks.where(
        (track) => seen.add('${track.providerId}\u0000${track.opaqueId}'),
      );
      _tracks = List.unmodifiable([..._tracks, ...additions]);
      _nextOffset = expectedOffset + result.tracks.length;
      _total = result.total;
      _hasMore = result.hasMore;
      _appendFailure = null;
    } else {
      final failure = result.failure ?? UserLibraryFailure.invalidResponse;
      if (failure == UserLibraryFailure.authenticationRequired ||
          failure == UserLibraryFailure.replaced ||
          failure == UserLibraryFailure.cancelled ||
          failure == UserLibraryFailure.credentialRejected ||
          failure ==
              UserLibraryFailure.credentialRejectedStorageCleanupFailed) {
        _tracks = const [];
        _total = 0;
        _hasMore = false;
        _failure = failure;
        _stage =
            failure == UserLibraryFailure.credentialRejected ||
                failure ==
                    UserLibraryFailure.credentialRejectedStorageCleanupFailed
            ? PlaylistDetailStage.credentialRejected
            : PlaylistDetailStage.authenticationRequired;
      } else {
        _appendFailure = failure;
      }
    }
    _notify();
  }

  void retry() {
    if (canRetry) unawaited(load());
  }

  void retryMore() {
    if (canRetryMore) unawaited(loadMore());
  }

  void retryRefresh() {
    if (canRetryRefresh) unawaited(refresh());
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
