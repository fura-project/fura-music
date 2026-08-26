import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum RankingGroupStage { loading, content, empty, error }

class RankingGroupController extends ChangeNotifier {
  RankingGroupController(this._gateway);

  final RankingGateway _gateway;

  RankingGroupStage _stage = RankingGroupStage.loading;
  List<RankingGroup> _groups = const [];
  RankingFailure? _failure;
  RankingGroupLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  RankingGroupStage get stage => _stage;
  List<RankingGroup> get groups => _groups;
  RankingFailure? get failure => _failure;
  bool get canRetry =>
      _stage == RankingGroupStage.error && _isRetryable(_failure);

  Future<void> load() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginGroupLoad();
    _operation = operation;
    _groups = const [];
    _failure = null;
    _stage = RankingGroupStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (result.failure == null) {
      _groups = List.unmodifiable(result.groups);
      _stage = _groups.isEmpty
          ? RankingGroupStage.empty
          : RankingGroupStage.content;
    } else {
      _failure = result.failure;
      _stage = RankingGroupStage.error;
    }
    _notify();
  }

  void retry() {
    if (canRetry) unawaited(load());
  }

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

enum RankingTrackStage { loading, content, empty, error }

class RankingTrackController extends ChangeNotifier {
  RankingTrackController(RankingSummary ranking, this._gateway)
    : _ranking = ranking;

  static const pageSize = 30;

  RankingSummary _ranking;
  final RankingGateway _gateway;

  RankingTrackStage _stage = RankingTrackStage.loading;
  List<PlaylistTrackSummary> _tracks = const [];
  RankingFailure? _failure;
  RankingFailure? _appendFailure;
  int _total = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  RankingTrackPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  RankingSummary get ranking => _ranking;
  RankingTrackStage get stage => _stage;
  List<PlaylistTrackSummary> get tracks => _tracks;
  RankingFailure? get failure => _failure;
  RankingFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry =>
      _stage == RankingTrackStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == RankingTrackStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == RankingTrackStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  Future<void> load() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginTrackLoad(
      ranking: _ranking,
      offset: 0,
      size: pageSize,
    );
    _operation = operation;
    _tracks = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextOffset = 0;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = RankingTrackStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedOffset: 0)) {
      _ranking = result.ranking!;
      _tracks = List.unmodifiable(result.tracks);
      _total = result.total;
      _nextOffset = result.tracks.length;
      _hasMore = result.hasMore;
      _stage = _tracks.isEmpty
          ? RankingTrackStage.empty
          : RankingTrackStage.content;
    } else {
      _failure = result.failure ?? RankingFailure.invalidResponse;
      _stage = RankingTrackStage.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (!canLoadMore && !canRetryMore) return;
    final generation = _generation;
    final expectedOffset = _nextOffset;
    final operation = _gateway.beginTrackLoad(
      ranking: _ranking,
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
      _ranking = result.ranking!;
      final seen = _tracks
          .map((track) => '${track.providerId}\u0000${track.opaqueId}')
          .toSet();
      final additions = result.tracks.where(
        (track) => seen.add('${track.providerId}\u0000${track.opaqueId}'),
      );
      _tracks = List.unmodifiable([..._tracks, ...additions]);
      _total = result.total;
      _nextOffset = expectedOffset + result.tracks.length;
      _hasMore = result.hasMore;
    } else {
      _appendFailure = result.failure ?? RankingFailure.invalidResponse;
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
    RankingTrackPageResult result, {
    required int expectedOffset,
  }) =>
      result.failure == null &&
      result.ranking != null &&
      result.ranking!.providerId == _ranking.providerId &&
      result.ranking!.opaqueId == _ranking.opaqueId &&
      result.offset == expectedOffset &&
      result.total >= expectedOffset + result.tracks.length &&
      (!result.hasMore || result.tracks.isNotEmpty);

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

bool _isRetryable(RankingFailure? failure) =>
    failure == RankingFailure.coreUnavailable ||
    failure == RankingFailure.network ||
    failure == RankingFailure.serviceUnavailable ||
    failure == RankingFailure.invalidResponse ||
    failure == RankingFailure.alreadyRunning;
