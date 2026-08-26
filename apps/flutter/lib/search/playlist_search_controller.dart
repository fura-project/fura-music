import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';

enum PlaylistSearchStage { idle, loading, content, empty, error }

class PlaylistSearchController extends ChangeNotifier {
  PlaylistSearchController(this._gateway);

  static const pageSize = 30;

  final PlaylistSearchGateway _gateway;

  PlaylistSearchStage _stage = PlaylistSearchStage.idle;
  String _query = '';
  List<UserPlaylistSummary> _playlists = const [];
  PlaylistSearchFailure? _failure;
  PlaylistSearchFailure? _appendFailure;
  int _total = 0;
  int _nextPage = 1;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  PlaylistSearchPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  PlaylistSearchStage get stage => _stage;
  String get query => _query;
  List<UserPlaylistSummary> get playlists => _playlists;
  PlaylistSearchFailure? get failure => _failure;
  PlaylistSearchFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry =>
      _stage == PlaylistSearchStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == PlaylistSearchStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == PlaylistSearchStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  Future<void> submit(String rawQuery) async {
    final normalized = rawQuery.trim();
    if (normalized.isEmpty) {
      clear();
      return;
    }
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(
      query: normalized,
      page: 1,
      size: pageSize,
    );
    _operation = operation;
    _query = normalized;
    _playlists = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextPage = 1;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = PlaylistSearchStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedPage: 1)) {
      _playlists = List.unmodifiable(result.playlists);
      _total = result.total;
      _nextPage = 2;
      _hasMore = result.hasMore;
      _stage = _playlists.isEmpty
          ? PlaylistSearchStage.empty
          : PlaylistSearchStage.content;
    } else {
      _failure = result.failure ?? PlaylistSearchFailure.invalidResponse;
      _stage = PlaylistSearchStage.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (!canLoadMore && !canRetryMore) return;
    final generation = _generation;
    final expectedPage = _nextPage;
    final operation = _gateway.beginLoad(
      query: _query,
      page: expectedPage,
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

    if (_validPage(result, expectedPage: expectedPage)) {
      final seen = _playlists
          .map((playlist) => '${playlist.providerId}\u0000${playlist.opaqueId}')
          .toSet();
      final additions = result.playlists.where(
        (playlist) =>
            seen.add('${playlist.providerId}\u0000${playlist.opaqueId}'),
      );
      _playlists = List.unmodifiable([..._playlists, ...additions]);
      _total = result.total;
      _nextPage = expectedPage + 1;
      _hasMore = result.hasMore;
    } else {
      _appendFailure = result.failure ?? PlaylistSearchFailure.invalidResponse;
    }
    _notify();
  }

  void retry() {
    if (canRetry) unawaited(submit(_query));
  }

  void retryMore() {
    if (canRetryMore) unawaited(loadMore());
  }

  void clear() {
    ++_generation;
    _operation?.cancel();
    _operation = null;
    _query = '';
    _playlists = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextPage = 1;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = PlaylistSearchStage.idle;
    _notify();
  }

  bool _validPage(
    PlaylistSearchPageResult result, {
    required int expectedPage,
  }) =>
      result.failure == null &&
      result.page == expectedPage &&
      result.total >= result.playlists.length &&
      (!result.hasMore || result.playlists.isNotEmpty);

  bool _isRetryable(PlaylistSearchFailure? failure) =>
      failure == PlaylistSearchFailure.coreUnavailable ||
      failure == PlaylistSearchFailure.network ||
      failure == PlaylistSearchFailure.serviceUnavailable ||
      failure == PlaylistSearchFailure.invalidResponse ||
      failure == PlaylistSearchFailure.alreadyRunning;

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
