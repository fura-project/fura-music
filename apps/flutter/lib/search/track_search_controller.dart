import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';

enum TrackSearchStage { idle, loading, content, empty, error }

class TrackSearchController extends ChangeNotifier {
  TrackSearchController(this._gateway);

  static const pageSize = 30;

  final TrackSearchGateway _gateway;

  TrackSearchStage _stage = TrackSearchStage.idle;
  String _query = '';
  List<TrackSearchItem> _items = const [];
  SearchFailure? _failure;
  SearchFailure? _appendFailure;
  int _total = 0;
  int _nextPage = 1;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  TrackSearchPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  TrackSearchStage get stage => _stage;
  String get query => _query;
  List<TrackSearchItem> get items => _items;
  List<PlaylistTrackSummary> get tracks =>
      List.unmodifiable(_items.map((item) => item.track));
  SearchFailure? get failure => _failure;
  SearchFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry =>
      _stage == TrackSearchStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == TrackSearchStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == TrackSearchStage.content &&
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
    _items = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextPage = 1;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = TrackSearchStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedPage: 1)) {
      _items = List.unmodifiable(result.items);
      _total = result.total;
      _nextPage = 2;
      _hasMore = result.hasMore;
      _stage = _items.isEmpty
          ? TrackSearchStage.empty
          : TrackSearchStage.content;
    } else {
      _failure = result.failure ?? SearchFailure.invalidResponse;
      _stage = TrackSearchStage.error;
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
      final seen = _items
          .map((item) => '${item.track.providerId}\u0000${item.track.opaqueId}')
          .toSet();
      final additions = result.items.where(
        (item) =>
            seen.add('${item.track.providerId}\u0000${item.track.opaqueId}'),
      );
      _items = List.unmodifiable([..._items, ...additions]);
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
    _items = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextPage = 1;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = TrackSearchStage.idle;
    _notify();
  }

  bool _validPage(TrackSearchPageResult result, {required int expectedPage}) =>
      result.failure == null &&
      result.page == expectedPage &&
      result.total >= result.items.length &&
      (!result.hasMore || result.items.isNotEmpty);

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
