import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';

enum RecommendedPlaylistStage { loading, content, empty, error }

class RecommendedPlaylistController extends ChangeNotifier {
  RecommendedPlaylistController(this._gateway);

  static const pageSize = 20;

  final RecommendedPlaylistGateway _gateway;

  RecommendedPlaylistStage _stage = RecommendedPlaylistStage.loading;
  List<RecommendedPlaylistSummary> _playlists = const [];
  RecommendedPlaylistFailure? _failure;
  RecommendedPlaylistFailure? _appendFailure;
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  RecommendedPlaylistPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  RecommendedPlaylistStage get stage => _stage;
  List<RecommendedPlaylistSummary> get playlists => _playlists;
  RecommendedPlaylistFailure? get failure => _failure;
  RecommendedPlaylistFailure? get appendFailure => _appendFailure;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry =>
      _stage == RecommendedPlaylistStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == RecommendedPlaylistStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == RecommendedPlaylistStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  Future<void> load() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(offset: 0, size: pageSize);
    _operation = operation;
    _playlists = const [];
    _failure = null;
    _appendFailure = null;
    _nextOffset = 0;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = RecommendedPlaylistStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedOffset: 0)) {
      _playlists = List.unmodifiable(result.playlists);
      _nextOffset = result.playlists.length;
      _hasMore = result.hasMore;
      _stage = _playlists.isEmpty
          ? RecommendedPlaylistStage.empty
          : RecommendedPlaylistStage.content;
    } else {
      _failure = result.failure ?? RecommendedPlaylistFailure.invalidResponse;
      _stage = RecommendedPlaylistStage.error;
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
      final seen = _playlists
          .map((playlist) => '${playlist.providerId}\u0000${playlist.opaqueId}')
          .toSet();
      final additions = result.playlists.where(
        (playlist) =>
            seen.add('${playlist.providerId}\u0000${playlist.opaqueId}'),
      );
      _playlists = List.unmodifiable([..._playlists, ...additions]);
      _nextOffset = expectedOffset + result.playlists.length;
      _hasMore = result.hasMore;
    } else {
      _appendFailure =
          result.failure ?? RecommendedPlaylistFailure.invalidResponse;
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
    RecommendedPlaylistPageResult result, {
    required int expectedOffset,
  }) =>
      result.failure == null &&
      result.offset == expectedOffset &&
      (!result.hasMore || result.playlists.isNotEmpty);

  bool _isRetryable(RecommendedPlaylistFailure? failure) =>
      failure == RecommendedPlaylistFailure.coreUnavailable ||
      failure == RecommendedPlaylistFailure.network ||
      failure == RecommendedPlaylistFailure.serviceUnavailable ||
      failure == RecommendedPlaylistFailure.invalidResponse ||
      failure == RecommendedPlaylistFailure.alreadyRunning;

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
