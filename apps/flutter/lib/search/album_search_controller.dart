import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';

enum AlbumSearchStage { idle, loading, content, empty, error }

class AlbumSearchController extends ChangeNotifier {
  AlbumSearchController(this._gateway);

  static const pageSize = 30;

  final AlbumSearchGateway _gateway;

  AlbumSearchStage _stage = AlbumSearchStage.idle;
  String _query = '';
  List<AlbumSummary> _albums = const [];
  SearchFailure? _failure;
  SearchFailure? _appendFailure;
  int _total = 0;
  int _nextPage = 1;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  AlbumSearchPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  AlbumSearchStage get stage => _stage;
  String get query => _query;
  List<AlbumSummary> get albums => _albums;
  SearchFailure? get failure => _failure;
  SearchFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry =>
      _stage == AlbumSearchStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == AlbumSearchStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == AlbumSearchStage.content &&
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
    _albums = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextPage = 1;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = AlbumSearchStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedPage: 1)) {
      _albums = List.unmodifiable(result.albums);
      _total = result.total;
      _nextPage = 2;
      _hasMore = result.hasMore;
      _stage = _albums.isEmpty
          ? AlbumSearchStage.empty
          : AlbumSearchStage.content;
    } else {
      _failure = result.failure ?? SearchFailure.invalidResponse;
      _stage = AlbumSearchStage.error;
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
      final seen = _albums
          .map((album) => '${album.providerId}\u0000${album.opaqueId}')
          .toSet();
      final additions = result.albums.where(
        (album) => seen.add('${album.providerId}\u0000${album.opaqueId}'),
      );
      _albums = List.unmodifiable([..._albums, ...additions]);
      _total = result.total;
      _nextPage = expectedPage + 1;
      _hasMore = result.hasMore;
    } else {
      _appendFailure = result.failure ?? SearchFailure.invalidResponse;
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
    _albums = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextPage = 1;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = AlbumSearchStage.idle;
    _notify();
  }

  bool _validPage(AlbumSearchPageResult result, {required int expectedPage}) =>
      result.failure == null &&
      result.page == expectedPage &&
      result.total >= result.albums.length &&
      (!result.hasMore || result.albums.isNotEmpty);

  bool _isRetryable(SearchFailure? failure) => failure?.isRetryable ?? false;

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
