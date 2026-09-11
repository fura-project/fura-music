import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum RadarStage { loading, content, empty, error }

class RadarController extends ChangeNotifier {
  RadarController(
    this._gateway, {
    this.initialPrefetchTarget = 0,
    this.maxInitialPrefetchPages = 1,
  }) : assert(initialPrefetchTarget >= 0),
       assert(maxInitialPrefetchPages >= 0);

  final RadarGateway _gateway;
  final int initialPrefetchTarget;
  final int maxInitialPrefetchPages;

  RadarStage _stage = RadarStage.loading;
  List<PlaylistTrackSummary> _tracks = const [];
  RadarFailure? _failure;
  RadarFailure? _appendFailure;
  int _nextPage = 1;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _manualPageRequested = false;
  int _prefetchTarget = 0;
  int _prefetchPages = 0;
  Duration _estimatedPageLatency = const Duration(milliseconds: 350);
  Completer<void>? _appendPump;
  RadarTrackPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  RadarStage get stage => _stage;
  List<PlaylistTrackSummary> get tracks => _tracks;
  RadarFailure? get failure => _failure;
  RadarFailure? get appendFailure => _appendFailure;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  Duration get estimatedPageLatency => _estimatedPageLatency;
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
    _appendPump = null;
    _manualPageRequested = false;
    cancelPrefetch();
    _tracks = const [];
    _failure = null;
    _appendFailure = null;
    _nextPage = 1;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = RadarStage.loading;
    _notify();

    late final RadarTrackPageLoadOperation operation;
    try {
      operation = _gateway.beginLoad(page: 1);
    } on Object {
      if (_isCurrent(generation)) {
        _failure = RadarFailure.coreUnavailable;
        _stage = RadarStage.error;
        _notify();
      }
      return;
    }
    _operation = operation;

    final latency = Stopwatch()..start();
    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedPage: 1)) {
      _recordPageLatency(latency.elapsed);
      _tracks = List.unmodifiable(result.tracks);
      _nextPage = 2;
      _hasMore = result.hasMore;
      _stage = _tracks.isEmpty ? RadarStage.empty : RadarStage.content;
    } else {
      _failure = result.failure ?? RadarFailure.invalidResponse;
      _stage = RadarStage.error;
    }
    _notify();

    if (_stage == RadarStage.content &&
        _tracks.length < initialPrefetchTarget &&
        _hasMore) {
      await _prefetchInitialPages(generation);
    }
  }

  Future<void> _prefetchInitialPages(int generation) async {
    var loadedPages = 0;
    while (_isCurrent(generation) &&
        _stage == RadarStage.content &&
        _tracks.length < initialPrefetchTarget &&
        _hasMore &&
        loadedPages < maxInitialPrefetchPages) {
      loadedPages += 1;
      if (!await _loadNextPage(generation)) return;
    }
  }

  Future<void> loadMore() async {
    if (_disposed) return;
    _manualPageRequested = true;
    await _ensureAppendPump();
  }

  /// Adds viewport-local demand without draining the station. One scroll event
  /// can budget at most two Radar pages; all demand shares the same serial pump.
  void prefetchTo(int trackCount) {
    if (_disposed ||
        _stage != RadarStage.content ||
        !_hasMore ||
        _appendFailure != null) {
      return;
    }
    const expectedPageSize = 10;
    _prefetchTarget = trackCount.clamp(
      0,
      _tracks.length + expectedPageSize * 2,
    );
    final missing = (_prefetchTarget - _tracks.length).clamp(
      0,
      expectedPageSize * 2,
    );
    _prefetchPages =
        ((missing + expectedPageSize - 1) ~/ expectedPageSize) -
        (_isLoadingMore ? 1 : 0);
    if (_prefetchPages < 0) _prefetchPages = 0;
    if (_wantsAppend) unawaited(_ensureAppendPump());
  }

  void cancelPrefetch() {
    _prefetchTarget = 0;
    _prefetchPages = 0;
  }

  bool get _wantsAppend =>
      _manualPageRequested ||
      (_prefetchPages > 0 && _tracks.length < _prefetchTarget);

  Future<void> _ensureAppendPump() {
    if (_appendPump case final pump?) return pump.future;
    final pump = Completer<void>();
    _appendPump = pump;
    unawaited(_runAppendPump(pump));
    return pump.future;
  }

  Future<void> _runAppendPump(Completer<void> pump) async {
    try {
      while (!_disposed && _wantsAppend) {
        final manual = _manualPageRequested;
        _manualPageRequested = false;
        if (!canLoadMore && !canRetryMore) break;
        if (!await _loadNextPage(_generation)) break;
        if (!manual && _prefetchPages > 0) --_prefetchPages;
      }
    } finally {
      if (identical(_appendPump, pump)) _appendPump = null;
      if (!pump.isCompleted) pump.complete();
    }
  }

  Future<bool> _loadNextPage(int generation) async {
    final expectedPage = _nextPage;
    late final RadarTrackPageLoadOperation operation;
    try {
      operation = _gateway.beginLoad(page: expectedPage);
    } on Object {
      if (_isCurrent(generation)) {
        _appendFailure = RadarFailure.coreUnavailable;
        _notify();
      }
      return false;
    }
    _operation = operation;
    _isLoadingMore = true;
    _appendFailure = null;
    _notify();

    final latency = Stopwatch()..start();
    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return false;
    _isLoadingMore = false;

    if (_validPage(result, expectedPage: expectedPage)) {
      _recordPageLatency(latency.elapsed);
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
    return _appendFailure == null;
  }

  void retry() {
    if (canRetry) unawaited(_loadFirstPage());
  }

  void retryMore() {
    if (canRetryMore) unawaited(loadMore());
  }

  void _recordPageLatency(Duration sample) {
    final micros = sample.inMicroseconds.clamp(1000, 30000000);
    _estimatedPageLatency = Duration(
      microseconds: (_estimatedPageLatency.inMicroseconds * 3 + micros) ~/ 4,
    );
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
    _manualPageRequested = false;
    cancelPrefetch();
    _operation?.cancel();
    _operation = null;
    super.dispose();
  }
}
