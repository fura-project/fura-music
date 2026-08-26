import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum RadarStage { loading, content, empty, error }

class RadarController extends ChangeNotifier {
  RadarController(this._gateway);

  final RadarGateway _gateway;

  RadarStage _stage = RadarStage.loading;
  List<PlaylistTrackSummary> _tracks = const [];
  RadarFailure? _failure;
  RadarFailure? _appendFailure;
  int _nextPage = 1;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  RadarTrackPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  RadarStage get stage => _stage;
  List<PlaylistTrackSummary> get tracks => _tracks;
  RadarFailure? get failure => _failure;
  RadarFailure? get appendFailure => _appendFailure;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry => _stage == RadarStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == RadarStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == RadarStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  Future<void> load() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(page: 1);
    _operation = operation;
    _tracks = const [];
    _failure = null;
    _appendFailure = null;
    _nextPage = 1;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = RadarStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedPage: 1)) {
      _tracks = List.unmodifiable(result.tracks);
      _nextPage = 2;
      _hasMore = result.hasMore;
      _stage = _tracks.isEmpty ? RadarStage.empty : RadarStage.content;
    } else {
      _failure = result.failure ?? RadarFailure.invalidResponse;
      _stage = RadarStage.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (!canLoadMore && !canRetryMore) return;
    final generation = _generation;
    final expectedPage = _nextPage;
    final operation = _gateway.beginLoad(page: expectedPage);
    _operation = operation;
    _isLoadingMore = true;
    _appendFailure = null;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;
    _isLoadingMore = false;

    if (_validPage(result, expectedPage: expectedPage)) {
      final seen = _tracks
          .map((track) => '${track.providerId}\u0000${track.opaqueId}')
          .toSet();
      final additions = result.tracks.where(
        (track) => seen.add('${track.providerId}\u0000${track.opaqueId}'),
      );
      _tracks = List.unmodifiable([..._tracks, ...additions]);
      _nextPage = expectedPage + 1;
      _hasMore = result.hasMore;
    } else {
      _appendFailure = result.failure ?? RadarFailure.invalidResponse;
    }
    _notify();
  }

  void retry() {
    if (canRetry) unawaited(_loadFirstPage());
  }

  void retryMore() {
    if (canRetryMore) unawaited(loadMore());
  }

  bool _validPage(RadarTrackPageResult result, {required int expectedPage}) =>
      result.failure == null &&
      result.page == expectedPage &&
      (!result.hasMore || result.tracks.isNotEmpty);

  bool _isRetryable(RadarFailure? failure) =>
      failure == RadarFailure.coreUnavailable ||
      failure == RadarFailure.network ||
      failure == RadarFailure.serviceUnavailable ||
      failure == RadarFailure.invalidResponse ||
      failure == RadarFailure.alreadyRunning;

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
