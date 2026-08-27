import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';

enum ArtistSearchStage { idle, loading, content, empty, error }

class ArtistSearchController extends ChangeNotifier {
  ArtistSearchController(this._gateway);

  static const pageSize = 30;

  final ArtistSearchGateway _gateway;

  ArtistSearchStage _stage = ArtistSearchStage.idle;
  String _query = '';
  List<ArtistSummary> _artists = const [];
  SearchFailure? _failure;
  SearchFailure? _appendFailure;
  int _total = 0;
  int _nextPage = 1;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  ArtistSearchPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  ArtistSearchStage get stage => _stage;
  String get query => _query;
  List<ArtistSummary> get artists => _artists;
  SearchFailure? get failure => _failure;
  SearchFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry =>
      _stage == ArtistSearchStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == ArtistSearchStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == ArtistSearchStage.content &&
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
    _artists = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextPage = 1;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = ArtistSearchStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedPage: 1)) {
      _artists = List.unmodifiable(result.artists);
      _total = result.total;
      _nextPage = 2;
      _hasMore = result.hasMore;
      _stage = _artists.isEmpty
          ? ArtistSearchStage.empty
          : ArtistSearchStage.content;
    } else {
      _failure = result.failure ?? SearchFailure.invalidResponse;
      _stage = ArtistSearchStage.error;
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
      final seen = _artists
          .map((artist) => '${artist.providerId}\u0000${artist.opaqueId}')
          .toSet();
      final additions = result.artists.where(
        (artist) => seen.add('${artist.providerId}\u0000${artist.opaqueId}'),
      );
      _artists = List.unmodifiable([..._artists, ...additions]);
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
    _artists = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextPage = 1;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = ArtistSearchStage.idle;
    _notify();
  }

  bool _validPage(ArtistSearchPageResult result, {required int expectedPage}) =>
      result.failure == null &&
      result.page == expectedPage &&
      result.total >= result.artists.length &&
      (!result.hasMore || result.artists.isNotEmpty);

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
