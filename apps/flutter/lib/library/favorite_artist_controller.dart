import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';

enum FavoriteArtistStage {
  loading,
  content,
  empty,
  error,
  authenticationRequired,
  credentialRejected,
}

class FavoriteArtistController extends ChangeNotifier {
  FavoriteArtistController(this._gateway);

  static const pageSize = 20;

  final FavoriteArtistGateway _gateway;

  FavoriteArtistStage _stage = FavoriteArtistStage.loading;
  List<ArtistSummary> _artists = const [];
  FavoriteArtistFailure? _failure;
  FavoriteArtistFailure? _appendFailure;
  int _total = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  FavoriteArtistPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  FavoriteArtistStage get stage => _stage;
  List<ArtistSummary> get artists => _artists;
  FavoriteArtistFailure? get failure => _failure;
  FavoriteArtistFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoading => _operation != null;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry =>
      _stage == FavoriteArtistStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == FavoriteArtistStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == FavoriteArtistStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  Future<void> load() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(offset: 0, size: pageSize);
    _operation = operation;
    _artists = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextOffset = 0;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = FavoriteArtistStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedOffset: 0)) {
      _artists = List.unmodifiable(result.artists);
      _total = result.total;
      _nextOffset = result.artists.length;
      _hasMore = result.hasMore;
      _stage = _artists.isEmpty
          ? FavoriteArtistStage.empty
          : FavoriteArtistStage.content;
    } else {
      _applyInitialFailure(
        result.failure ?? FavoriteArtistFailure.invalidResponse,
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
      final seen = _artists
          .map((artist) => '${artist.providerId}\u0000${artist.opaqueId}')
          .toSet();
      final additions = result.artists.where(
        (artist) => seen.add('${artist.providerId}\u0000${artist.opaqueId}'),
      );
      _artists = List.unmodifiable([..._artists, ...additions]);
      _total = result.total;
      _nextOffset = expectedOffset + result.artists.length;
      _hasMore = result.hasMore;
    } else if (_isSessionFailure(result.failure)) {
      _artists = const [];
      _total = 0;
      _nextOffset = 0;
      _hasMore = false;
      _applyInitialFailure(
        result.failure ?? FavoriteArtistFailure.invalidResponse,
      );
    } else {
      _appendFailure = result.failure ?? FavoriteArtistFailure.invalidResponse;
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
    FavoriteArtistPageResult result, {
    required int expectedOffset,
  }) {
    final pageEnd = expectedOffset + result.artists.length;
    return result.failure == null &&
        result.offset == expectedOffset &&
        pageEnd <= result.total &&
        (result.hasMore
            ? result.artists.isNotEmpty && pageEnd < result.total
            : pageEnd == result.total);
  }

  void _applyInitialFailure(FavoriteArtistFailure failure) {
    _failure = failure;
    _stage = switch (failure) {
      FavoriteArtistFailure.authenticationRequired ||
      FavoriteArtistFailure.replaced ||
      FavoriteArtistFailure.cancelled =>
        FavoriteArtistStage.authenticationRequired,
      FavoriteArtistFailure.credentialRejected ||
      FavoriteArtistFailure.credentialRejectedStorageCleanupFailed =>
        FavoriteArtistStage.credentialRejected,
      FavoriteArtistFailure.coreUnavailable ||
      FavoriteArtistFailure.network ||
      FavoriteArtistFailure.serviceUnavailable ||
      FavoriteArtistFailure.invalidResponse ||
      FavoriteArtistFailure.alreadyRunning => FavoriteArtistStage.error,
    };
  }

  bool _isSessionFailure(FavoriteArtistFailure? failure) =>
      failure == FavoriteArtistFailure.authenticationRequired ||
      failure == FavoriteArtistFailure.credentialRejected ||
      failure == FavoriteArtistFailure.credentialRejectedStorageCleanupFailed ||
      failure == FavoriteArtistFailure.replaced ||
      failure == FavoriteArtistFailure.cancelled;

  bool _isRetryable(FavoriteArtistFailure? failure) =>
      failure == FavoriteArtistFailure.coreUnavailable ||
      failure == FavoriteArtistFailure.network ||
      failure == FavoriteArtistFailure.serviceUnavailable ||
      failure == FavoriteArtistFailure.invalidResponse ||
      failure == FavoriteArtistFailure.alreadyRunning;

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
