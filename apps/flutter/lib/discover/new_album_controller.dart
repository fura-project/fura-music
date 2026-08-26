import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';

enum NewAlbumStage { loading, content, empty, error }

class NewAlbumController extends ChangeNotifier {
  NewAlbumController(this._gateway);

  static const pageSize = 20;

  final NewAlbumGateway _gateway;

  NewAlbumRegion _region = NewAlbumRegion.mainlandChina;
  NewAlbumStage _stage = NewAlbumStage.loading;
  List<NewAlbumRelease> _releases = const [];
  NewAlbumFailure? _failure;
  NewAlbumFailure? _appendFailure;
  int _total = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  NewAlbumPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  NewAlbumRegion get region => _region;
  NewAlbumStage get stage => _stage;
  List<NewAlbumRelease> get releases => _releases;
  NewAlbumFailure? get failure => _failure;
  NewAlbumFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry => _stage == NewAlbumStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == NewAlbumStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == NewAlbumStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  Future<void> load() => _loadFirstPage(_region);

  void selectRegion(NewAlbumRegion region) {
    if (_region == region) return;
    _region = region;
    unawaited(_loadFirstPage(region));
  }

  Future<void> _loadFirstPage(NewAlbumRegion expectedRegion) async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(
      region: expectedRegion,
      offset: 0,
      size: pageSize,
    );
    _operation = operation;
    _releases = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextOffset = 0;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = NewAlbumStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation, expectedRegion)) return;

    if (_validPage(result, expectedRegion: expectedRegion, expectedOffset: 0)) {
      _releases = List.unmodifiable(result.releases);
      _total = result.total;
      _nextOffset = result.releases.length;
      _hasMore = result.hasMore;
      _stage = _releases.isEmpty ? NewAlbumStage.empty : NewAlbumStage.content;
    } else {
      _failure = result.failure ?? NewAlbumFailure.invalidResponse;
      _stage = NewAlbumStage.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (!canLoadMore && !canRetryMore) return;
    final generation = _generation;
    final expectedRegion = _region;
    final expectedOffset = _nextOffset;
    final operation = _gateway.beginLoad(
      region: expectedRegion,
      offset: expectedOffset,
      size: pageSize,
    );
    _operation = operation;
    _isLoadingMore = true;
    _appendFailure = null;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation, expectedRegion)) return;
    _isLoadingMore = false;

    if (_validPage(
      result,
      expectedRegion: expectedRegion,
      expectedOffset: expectedOffset,
    )) {
      final seen = _releases
          .map(
            (release) =>
                '${release.album.providerId}\u0000${release.album.opaqueId}',
          )
          .toSet();
      final additions = result.releases.where(
        (release) => seen.add(
          '${release.album.providerId}\u0000${release.album.opaqueId}',
        ),
      );
      _releases = List.unmodifiable([..._releases, ...additions]);
      _total = result.total;
      _nextOffset = expectedOffset + result.releases.length;
      _hasMore = result.hasMore;
    } else {
      _appendFailure = result.failure ?? NewAlbumFailure.invalidResponse;
    }
    _notify();
  }

  void retry() {
    if (canRetry) unawaited(_loadFirstPage(_region));
  }

  void retryMore() {
    if (canRetryMore) unawaited(loadMore());
  }

  bool _validPage(
    NewAlbumPageResult result, {
    required NewAlbumRegion expectedRegion,
    required int expectedOffset,
  }) =>
      result.failure == null &&
      result.region == expectedRegion &&
      result.offset == expectedOffset &&
      result.total >= expectedOffset + result.releases.length &&
      (!result.hasMore || result.releases.isNotEmpty);

  bool _isRetryable(NewAlbumFailure? failure) =>
      failure == NewAlbumFailure.coreUnavailable ||
      failure == NewAlbumFailure.network ||
      failure == NewAlbumFailure.serviceUnavailable ||
      failure == NewAlbumFailure.invalidResponse ||
      failure == NewAlbumFailure.alreadyRunning;

  bool _isCurrent(int generation, NewAlbumRegion expectedRegion) =>
      !_disposed && generation == _generation && expectedRegion == _region;

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
