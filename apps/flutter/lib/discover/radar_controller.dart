import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/collection_playback_source.dart';

enum RadarStage { loading, content, empty, error }

class RadarController extends ChangeNotifier {
  RadarController(
    this._gateway, {
    this.initialPrefetchTarget = 0,
    this.maxInitialPrefetchPages = 1,
  }) : assert(initialPrefetchTarget >= 0),
       assert(maxInitialPrefetchPages >= 0),
       _session = _RadarSessionPages(_gateway);

  final RadarGateway _gateway;
  final int initialPrefetchTarget;
  final int maxInitialPrefetchPages;

  RadarStage _stage = RadarStage.loading;
  List<PlaylistTrackSummary> _tracks = const [];
  final Set<String> _seenTrackKeys = <String>{};
  RadarFailure? _failure;
  RadarFailure? _appendFailure;
  int _nextPage = 1;
  bool _hasMore = false;
  int _omittedTrackCount = 0;
  int _partialResultRevision = 0;
  bool _isLoadingMore = false;
  bool _manualPageRequested = false;
  int _initialPrefetchPagesRemaining = 0;
  int _prefetchTarget = 0;
  int _prefetchPages = 0;
  Duration _estimatedPageLatency = const Duration(milliseconds: 350);
  Completer<void>? _appendPump;
  RadarTrackPageLoadOperation? _operation;
  _RadarSessionPages _session;
  int _generation = 0;
  bool _disposed = false;

  RadarStage get stage => _stage;
  List<PlaylistTrackSummary> get tracks => _tracks;
  RadarFailure? get failure => _failure;
  RadarFailure? get appendFailure => _appendFailure;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  Duration get estimatedPageLatency => _estimatedPageLatency;
  int get omittedTrackCount => _omittedTrackCount;
  int get partialResultRevision => _partialResultRevision;
  bool get canRetry => _stage == RadarStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == RadarStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == RadarStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  /// Detaches a logical Radar playback source bound to this refresh session.
  ///
  /// The returned source shares pending and resolved pages with this session so
  /// rapid playback handoff does not duplicate in-flight pages, yet survives
  /// controller disposal and never mixes pages across separate Radar refreshes.
  CollectionPlaybackSource collectionPlaybackSource({
    required String providerId,
    String sourceId = 'radar',
  }) {
    final session = _session;
    final initialTracks = _tracks;
    final firstSeenPage = <String, int>{
      for (final track in initialTracks)
        '${track.providerId}\u0000${track.opaqueId}': 0,
    };
    return CollectionPlaybackSource(
      sourceId: '$sourceId:$providerId',
      providerId: providerId,
      initialTracks: initialTracks,
      nextCursor: _nextPage,
      hasMore: _hasMore,
      policy: const CollectionPlaybackPolicy(
        initialQueueTarget: 50,
        maxInitialPages: 5,
      ),
      loader: (page) {
        final operation = session.loadPage(page);
        return CallbackCollectionPlaybackPageOperation(() async {
          final result = await operation.run();
          final valid = _validRadarPage(result, expectedPage: page);
          final additions = <PlaylistTrackSummary>[];
          if (valid) {
            final pageSeen = <String>{};
            for (final track in result.tracks) {
              final key = '${track.providerId}\u0000${track.opaqueId}';
              final priorPage = firstSeenPage[key];
              if (priorPage != null && priorPage < page) continue;
              if (pageSeen.add(key)) {
                firstSeenPage[key] = page;
                additions.add(track);
              }
            }
          }
          return CollectionPlaybackPage(
            requestCursor: page,
            nextCursor: valid ? page + 1 : page,
            hasMore: valid && result.hasMore,
            tracks: valid ? List.unmodifiable(additions) : const [],
            omittedTrackCount: valid ? result.omittedTrackCount : 0,
            failure: valid ? null : _mapRadarCollectionFailure(result.failure),
          );
        }, operation.cancel);
      },
    );
  }

  Future<void> load() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _operation?.cancel();
    _operation = null;
    _session = _RadarSessionPages(_gateway);
    _appendPump = null;
    _manualPageRequested = false;
    _initialPrefetchPagesRemaining = 0;
    cancelPrefetch();
    _tracks = const [];
    _seenTrackKeys.clear();
    _failure = null;
    _appendFailure = null;
    _nextPage = 1;
    _hasMore = false;
    _omittedTrackCount = 0;
    _isLoadingMore = false;
    _stage = RadarStage.loading;
    _notify();

    late final RadarTrackPageLoadOperation operation;
    try {
      operation = _session.loadPage(1);
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
    late final RadarTrackPageResult result;
    try {
      result = await operation.run();
    } on Object {
      if (identical(_operation, operation)) _operation = null;
      if (_isCurrent(generation)) {
        _failure = RadarFailure.coreUnavailable;
        _stage = RadarStage.error;
        _notify();
      }
      return;
    }
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validRadarPage(result, expectedPage: 1)) {
      _recordPageLatency(latency.elapsed);
      final additions = <PlaylistTrackSummary>[];
      for (final track in result.tracks) {
        if (_seenTrackKeys.add('${track.providerId}\u0000${track.opaqueId}')) {
          additions.add(track);
        }
      }
      _tracks = List.unmodifiable(additions);
      _nextPage = 2;
      _hasMore = result.hasMore;
      _omittedTrackCount = result.omittedTrackCount;
      if (result.omittedTrackCount > 0) _partialResultRevision += 1;
      _stage = _tracks.isEmpty && _omittedTrackCount == 0
          ? RadarStage.empty
          : RadarStage.content;
    } else {
      _failure = result.failure ?? RadarFailure.invalidResponse;
      _stage = RadarStage.error;
    }
    _notify();

    if (_isCurrent(generation) &&
        _stage == RadarStage.content &&
        _tracks.length < initialPrefetchTarget &&
        maxInitialPrefetchPages > 0 &&
        _hasMore) {
      _initialPrefetchPagesRemaining = maxInitialPrefetchPages;
      await _ensureAppendPump();
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

  bool get _wantsInitialPrefetch =>
      _initialPrefetchPagesRemaining > 0 &&
      _tracks.length < initialPrefetchTarget;

  bool get _wantsAppend =>
      _manualPageRequested ||
      _wantsInitialPrefetch ||
      (_prefetchPages > 0 && _tracks.length < _prefetchTarget);

  Future<void> _ensureAppendPump() {
    if (_appendPump case final pump?) return pump.future;
    final pump = Completer<void>();
    _appendPump = pump;
    unawaited(_runAppendPump(pump, _generation));
    return pump.future;
  }

  Future<void> _runAppendPump(Completer<void> pump, int generation) async {
    try {
      while (_isCurrent(generation) && _wantsAppend) {
        final manual = _manualPageRequested;
        final initialPrefetch = !manual && _wantsInitialPrefetch;
        _manualPageRequested = false;
        if (!canLoadMore && !canRetryMore) break;
        if (initialPrefetch) --_initialPrefetchPagesRemaining;
        if (!await _loadNextPage(generation)) {
          if (initialPrefetch) _initialPrefetchPagesRemaining = 0;
          break;
        }
        if (!manual && !initialPrefetch && _prefetchPages > 0) --_prefetchPages;
      }
    } finally {
      if (_isCurrent(generation) && identical(_appendPump, pump)) {
        _appendPump = null;
        if (_tracks.length >= initialPrefetchTarget || !_hasMore) {
          _initialPrefetchPagesRemaining = 0;
        }
      }
      if (!pump.isCompleted) pump.complete();
    }
  }

  Future<bool> _loadNextPage(int generation) async {
    final expectedPage = _nextPage;
    late final RadarTrackPageLoadOperation operation;
    try {
      operation = _session.loadPage(expectedPage);
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
    late final RadarTrackPageResult result;
    try {
      result = await operation.run();
    } on Object {
      if (identical(_operation, operation)) _operation = null;
      if (_isCurrent(generation)) {
        _isLoadingMore = false;
        _appendFailure = RadarFailure.coreUnavailable;
        _notify();
      }
      return false;
    }
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return false;
    _isLoadingMore = false;

    if (_validRadarPage(result, expectedPage: expectedPage)) {
      _recordPageLatency(latency.elapsed);
      final additions = <PlaylistTrackSummary>[];
      for (final track in result.tracks) {
        if (_seenTrackKeys.add('${track.providerId}\u0000${track.opaqueId}')) {
          additions.add(track);
        }
      }
      if (additions.isNotEmpty) {
        _tracks = List.unmodifiable([..._tracks, ...additions]);
      }
      _nextPage = expectedPage + 1;
      _hasMore = result.hasMore;
      _omittedTrackCount += result.omittedTrackCount;
      if (result.omittedTrackCount > 0) _partialResultRevision += 1;
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
    _initialPrefetchPagesRemaining = 0;
    cancelPrefetch();
    _operation?.cancel();
    _operation = null;
    super.dispose();
  }
}

bool _validRadarPage(
  RadarTrackPageResult result, {
  required int expectedPage,
}) =>
    result.failure == null &&
    result.page == expectedPage &&
    result.omittedTrackCount >= 0 &&
    (!result.hasMore ||
        result.tracks.isNotEmpty ||
        result.omittedTrackCount > 0);

/// Per-refresh-session shared Radar page table for single-flight handoff
/// between [RadarController] and a detached [CollectionPlaybackSource].
class _RadarSessionPages {
  _RadarSessionPages(this._gateway);

  static const int _maxCachedResolvedPages = 64;

  final RadarGateway _gateway;
  final Map<int, _SharedRadarPage> _pages = <int, _SharedRadarPage>{};

  RadarTrackPageLoadOperation loadPage(int page) {
    var entry = _pages[page];
    if (entry == null) {
      final source = _gateway.beginLoad(page: page);
      late final _SharedRadarPage created;
      final future = source.run().then(
        (result) {
          if (identical(_pages[page], created)) {
            if (_validRadarPage(result, expectedPage: page)) {
              created.resolved = result;
              _evictOverflowResolvedPages(keepPage: page);
            } else {
              _pages.remove(page);
            }
          }
          return result;
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_pages[page], created)) {
            _pages.remove(page);
          }
          Error.throwWithStackTrace(error, stackTrace);
        },
      );
      created = _SharedRadarPage(this, page, source, future);
      entry = created;
      _pages[page] = entry;
    }
    entry.activeJoiners += 1;
    return _JoinedRadarPageOperation(entry);
  }

  void _evictOverflowResolvedPages({required int keepPage}) {
    var resolvedCount = 0;
    for (final entry in _pages.values) {
      if (entry.resolved != null) resolvedCount += 1;
    }
    while (resolvedCount > _maxCachedResolvedPages) {
      int? victimPage;
      for (final candidate in _pages.entries) {
        if (candidate.key == keepPage || candidate.value.resolved == null) {
          continue;
        }
        if (victimPage == null || candidate.key < victimPage) {
          victimPage = candidate.key;
        }
      }
      if (victimPage == null) break;
      _pages.remove(victimPage);
      resolvedCount -= 1;
    }
  }

  void _releaseJoiner(_SharedRadarPage entry) {
    if (entry.activeJoiners <= 0) return;
    entry.activeJoiners -= 1;
    if (entry.activeJoiners == 0 && entry.resolved == null) {
      if (identical(_pages[entry.page], entry)) {
        _pages.remove(entry.page);
      }
      entry.source.cancel();
    }
  }
}

class _SharedRadarPage {
  _SharedRadarPage(this.session, this.page, this.source, this.future);

  final _RadarSessionPages session;
  final int page;
  final RadarTrackPageLoadOperation source;
  final Future<RadarTrackPageResult> future;
  RadarTrackPageResult? resolved;
  int activeJoiners = 0;
}

class _JoinedRadarPageOperation implements RadarTrackPageLoadOperation {
  _JoinedRadarPageOperation(this._entry);

  final _SharedRadarPage _entry;
  bool _active = true;

  @override
  bool cancel() {
    if (!_active) return false;
    _active = false;
    _entry.session._releaseJoiner(_entry);
    return true;
  }

  @override
  Future<RadarTrackPageResult> run() {
    if (!_active) {
      return SynchronousFuture(
        const RadarTrackPageResult(failure: RadarFailure.cancelled),
      );
    }
    final resolved = _entry.resolved;
    if (resolved != null) {
      return SynchronousFuture(resolved);
    }
    return _entry.future.then(
      (result) => _active
          ? result
          : const RadarTrackPageResult(failure: RadarFailure.cancelled),
    );
  }
}

CollectionPlaybackFailure _mapRadarCollectionFailure(RadarFailure? failure) =>
    switch (failure) {
      RadarFailure.coreUnavailable => CollectionPlaybackFailure.coreUnavailable,
      RadarFailure.authenticationRequired ||
      RadarFailure.replaced => CollectionPlaybackFailure.authenticationRequired,
      RadarFailure.credentialRejected ||
      RadarFailure.credentialRejectedStorageCleanupFailed =>
        CollectionPlaybackFailure.credentialRejected,
      RadarFailure.network => CollectionPlaybackFailure.network,
      RadarFailure.serviceUnavailable =>
        CollectionPlaybackFailure.serviceUnavailable,
      RadarFailure.cancelled => CollectionPlaybackFailure.cancelled,
      RadarFailure.alreadyRunning => CollectionPlaybackFailure.alreadyRunning,
      RadarFailure.invalidResponse ||
      null => CollectionPlaybackFailure.invalidResponse,
    };
