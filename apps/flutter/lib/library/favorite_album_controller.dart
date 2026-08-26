import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';

enum FavoriteAlbumStage {
  loading,
  content,
  empty,
  error,
  authenticationRequired,
  credentialRejected,
}

class FavoriteAlbumController extends ChangeNotifier {
  FavoriteAlbumController(this._gateway);

  static const pageSize = 20;

  final FavoriteAlbumGateway _gateway;

  FavoriteAlbumStage _stage = FavoriteAlbumStage.loading;
  List<AlbumSummary> _albums = const [];
  FavoriteAlbumFailure? _failure;
  FavoriteAlbumFailure? _appendFailure;
  int _total = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  FavoriteAlbumPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  FavoriteAlbumStage get stage => _stage;
  List<AlbumSummary> get albums => _albums;
  FavoriteAlbumFailure? get failure => _failure;
  FavoriteAlbumFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoading => _operation != null;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry =>
      _stage == FavoriteAlbumStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == FavoriteAlbumStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == FavoriteAlbumStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  Future<void> load() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(offset: 0, size: pageSize);
    _operation = operation;
    _albums = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextOffset = 0;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = FavoriteAlbumStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedOffset: 0)) {
      _albums = List.unmodifiable(result.albums);
      _total = result.total;
      _nextOffset = result.albums.length;
      _hasMore = result.hasMore;
      _stage = _albums.isEmpty
          ? FavoriteAlbumStage.empty
          : FavoriteAlbumStage.content;
    } else {
      _applyInitialFailure(
        result.failure ?? FavoriteAlbumFailure.invalidResponse,
      );
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (!canLoadMore && !canRetryMore) return;
    final generation = _generation;
    final expectedOffset = _nextOffset;
    final operation = _gateway.beginLoad(
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

    if (_validPage(result, expectedOffset: expectedOffset)) {
      final seen = _albums
          .map((album) => '${album.providerId}\u0000${album.opaqueId}')
          .toSet();
      final additions = result.albums.where(
        (album) => seen.add('${album.providerId}\u0000${album.opaqueId}'),
      );
      _albums = List.unmodifiable([..._albums, ...additions]);
      _total = result.total;
      _nextOffset = expectedOffset + result.albums.length;
      _hasMore = result.hasMore;
    } else if (_isSessionFailure(result.failure)) {
      _albums = const [];
      _total = 0;
      _nextOffset = 0;
      _hasMore = false;
      _applyInitialFailure(
        result.failure ?? FavoriteAlbumFailure.invalidResponse,
      );
    } else {
      _appendFailure = result.failure ?? FavoriteAlbumFailure.invalidResponse;
    }
    _notify();
  }

  void retry() {
    if (canRetry) unawaited(_loadFirstPage());
  }

  void retryMore() {
    if (canRetryMore) unawaited(loadMore());
  }

  bool _validPage(
    FavoriteAlbumPageResult result, {
    required int expectedOffset,
  }) {
    final pageEnd = expectedOffset + result.albums.length;
    return result.failure == null &&
        result.offset == expectedOffset &&
        pageEnd <= result.total &&
        (result.hasMore
            ? result.albums.isNotEmpty && pageEnd < result.total
            : pageEnd == result.total);
  }

  void _applyInitialFailure(FavoriteAlbumFailure failure) {
    _failure = failure;
    _stage = switch (failure) {
      FavoriteAlbumFailure.authenticationRequired ||
      FavoriteAlbumFailure.replaced ||
      FavoriteAlbumFailure.cancelled =>
        FavoriteAlbumStage.authenticationRequired,
      FavoriteAlbumFailure.credentialRejected ||
      FavoriteAlbumFailure.credentialRejectedStorageCleanupFailed =>
        FavoriteAlbumStage.credentialRejected,
      FavoriteAlbumFailure.coreUnavailable ||
      FavoriteAlbumFailure.network ||
      FavoriteAlbumFailure.serviceUnavailable ||
      FavoriteAlbumFailure.invalidResponse ||
      FavoriteAlbumFailure.alreadyRunning => FavoriteAlbumStage.error,
    };
  }

  bool _isSessionFailure(FavoriteAlbumFailure? failure) =>
      failure == FavoriteAlbumFailure.authenticationRequired ||
      failure == FavoriteAlbumFailure.credentialRejected ||
      failure == FavoriteAlbumFailure.credentialRejectedStorageCleanupFailed ||
      failure == FavoriteAlbumFailure.replaced ||
      failure == FavoriteAlbumFailure.cancelled;

  bool _isRetryable(FavoriteAlbumFailure? failure) =>
      failure == FavoriteAlbumFailure.coreUnavailable ||
      failure == FavoriteAlbumFailure.network ||
      failure == FavoriteAlbumFailure.serviceUnavailable ||
      failure == FavoriteAlbumFailure.invalidResponse ||
      failure == FavoriteAlbumFailure.alreadyRunning;

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
