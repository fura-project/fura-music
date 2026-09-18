import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/pagination/raw_offset_page.dart';

enum PlaylistDetailStage {
  loading,
  content,
  empty,
  error,
  authenticationRequired,
  credentialRejected,
}

enum CollectionSearchScanStage { idle, scanning, paused, complete, interrupted }

/// Shared ordered track-page loader for playlists and account collections.
/// A page supplies the operation factory; collection identity stays outside.
class PagedTracksController extends ChangeNotifier {
  PagedTracksController(
    this._beginLoad, {
    this.loadAllPageInterval = const Duration(milliseconds: 180),
    this.postTransientPageInterval = const Duration(milliseconds: 500),
    this.transientRetryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 3),
    ],
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  static const pageSize = 100;

  final PlaylistTrackPageLoadOperation Function(int offset, int size)
  _beginLoad;
  final Duration loadAllPageInterval;
  final Duration postTransientPageInterval;
  final List<Duration> transientRetryDelays;
  final Future<void> Function(Duration) _delay;

  PlaylistDetailStage _stage = PlaylistDetailStage.loading;
  List<PlaylistTrackSummary> _tracks = const [];
  UserLibraryFailure? _failure;
  int _total = 0;
  bool _totalIsExact = true;
  bool _hasMore = false;
  int _nextOffset = 0;
  int _omittedTrackCount = 0;
  int _partialResultRevision = 0;
  bool _isLoadingMore = false;
  bool _isLoadingAll = false;
  bool _isRefreshing = false;
  UserLibraryFailure? _appendFailure;
  UserLibraryFailure? _refreshFailure;
  PlaylistTrackPageLoadOperation? _operation;
  int _generation = 0;
  Completer<void>? _appendPump;
  bool _manualPageRequested = false;
  int _searchPageBudget = 0;
  bool Function()? _searchHasEnoughMatches;
  CollectionSearchScanStage _searchScanStage = CollectionSearchScanStage.idle;
  int _prefetchTarget = 0;
  int _prefetchPages = 0;
  Duration _estimatedPageLatency = const Duration(milliseconds: 350);
  bool _disposed = false;

  PlaylistDetailStage get stage => _stage;
  List<PlaylistTrackSummary> get tracks => _tracks;
  UserLibraryFailure? get failure => _failure;
  int get total => _total;
  bool get totalIsExact => _totalIsExact;
  int get processedCount => _nextOffset;
  int get omittedTrackCount => _omittedTrackCount;
  int get partialResultRevision => _partialResultRevision;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get isLoadingAll => _isLoadingAll;
  bool get isScanningSearch =>
      _searchScanStage == CollectionSearchScanStage.scanning;
  CollectionSearchScanStage get searchScanStage => _searchScanStage;
  bool get isLoading => _operation != null;
  bool get isRefreshing => _isRefreshing;
  Duration get estimatedPageLatency => _estimatedPageLatency;
  UserLibraryFailure? get appendFailure => _appendFailure;
  UserLibraryFailure? get refreshFailure => _refreshFailure;
  bool get canLoadMore =>
      _stage == PlaylistDetailStage.content &&
      _hasMore &&
      _appendFailure == null &&
      !_isLoadingMore &&
      !_isRefreshing;
  bool get canRetryMore => !_isRefreshing && _isRetryable(_appendFailure);

  bool get canRetry =>
      _stage == PlaylistDetailStage.error && _isRetryable(_failure);

  bool get canRetryRefresh => _isRetryable(_refreshFailure);

  Future<void> load() => _load(preserveSnapshot: false);

  Future<void> refresh() => _load(
    preserveSnapshot:
        _stage == PlaylistDetailStage.content ||
        _stage == PlaylistDetailStage.empty,
  );

  Future<void> _load({required bool preserveSnapshot}) async {
    if (_disposed) return;
    final generation = ++_generation;
    _appendPump = null;
    _manualPageRequested = false;
    cancelSearchScan(notify: false);
    cancelPrefetch();
    _isLoadingAll = false;
    _operation?.cancel();
    final operation = _beginLoad(0, pageSize);
    _operation = operation;
    _failure = null;
    _isLoadingMore = false;
    _isRefreshing = preserveSnapshot;
    _appendFailure = null;
    _refreshFailure = null;
    if (!preserveSnapshot) {
      _tracks = const [];
      _total = 0;
      _totalIsExact = true;
      _hasMore = false;
      _nextOffset = 0;
      _omittedTrackCount = 0;
      _stage = PlaylistDetailStage.loading;
    }
    _notify();

    final latency = Stopwatch()..start();
    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    _isRefreshing = false;
    final nextOffset = result.nextOffset;
    final hasMore = _pageHasMore(result);
    final validSuccess =
        result.failure == null &&
        result.offset == 0 &&
        _validPage(result, nextOffset, hasMore);
    if (validSuccess) {
      _recordPageLatency(latency.elapsed);
      _tracks = List.unmodifiable(result.tracks);
      _total = result.total;
      _totalIsExact = result.totalIsExact;
      _hasMore = hasMore;
      _nextOffset = nextOffset;
      _omittedTrackCount = result.omittedTrackCount;
      if (result.omittedTrackCount > 0) _partialResultRevision += 1;
      _failure = null;
      _stage = _tracks.isEmpty && result.omittedTrackCount == 0 && !hasMore
          ? PlaylistDetailStage.empty
          : PlaylistDetailStage.content;
    } else if (preserveSnapshot &&
        _canRetainSnapshot(
          result.failure ?? UserLibraryFailure.invalidResponse,
        )) {
      _failure = null;
      _refreshFailure = result.failure ?? UserLibraryFailure.invalidResponse;
    } else {
      _tracks = const [];
      _total = 0;
      _totalIsExact = true;
      _hasMore = false;
      _nextOffset = 0;
      _omittedTrackCount = 0;
      _failure = result.failure ?? UserLibraryFailure.invalidResponse;
      _stage = switch (_failure!) {
        UserLibraryFailure.authenticationRequired ||
        UserLibraryFailure.replaced ||
        UserLibraryFailure.cancelled =>
          PlaylistDetailStage.authenticationRequired,
        UserLibraryFailure.credentialRejected ||
        UserLibraryFailure.credentialRejectedStorageCleanupFailed =>
          PlaylistDetailStage.credentialRejected,
        UserLibraryFailure.coreUnavailable ||
        UserLibraryFailure.network ||
        UserLibraryFailure.serviceUnavailable ||
        UserLibraryFailure.invalidResponse ||
        UserLibraryFailure.alreadyRunning => PlaylistDetailStage.error,
      };
    }
    _notify();
  }

  /// Manual loading, scrolling and search share one paced, single-flight pump.
  /// Repeated clicks join its work; they never queue another identical page.
  Future<void> loadMore() {
    if (_disposed) return Future.value();
    if (_appendPump case final pump?) return pump.future;
    if (!canLoadMore && !canRetryMore) return Future.value();
    _manualPageRequested = true;
    return _ensureAppendPump();
  }

  /// A viewport-local demand, not an instruction to drain the collection.
  /// At most two transport pages (including any in flight) are budgeted. Short,
  /// duplicate or omitted pages cannot turn one scroll event into an unbounded
  /// fetch. A later scroll can supply fresh demand without discarding old rows.
  void prefetchTo(int trackCount) {
    if (_disposed ||
        _isLoadingAll ||
        _isRefreshing ||
        _stage != PlaylistDetailStage.content ||
        !_hasMore ||
        _appendFailure != null) {
      return;
    }
    _prefetchTarget = trackCount.clamp(0, _tracks.length + 2 * pageSize);
    final missing = (_prefetchTarget - _tracks.length).clamp(0, 2 * pageSize);
    _prefetchPages =
        ((missing + pageSize - 1) ~/ pageSize) - (_isLoadingMore ? 1 : 0);
    if (_prefetchPages < 0) _prefetchPages = 0;
    if (_wantsAppend) unawaited(_ensureAppendPump());
  }

  void cancelPrefetch() {
    _prefetchTarget = 0;
    _prefetchPages = 0;
  }

  /// Supplies one bounded unit of search demand over the already ordered
  /// collection. Loaded pages remain reusable when the query changes. The
  /// caller decides whether enough matches are visible; one request can fetch
  /// at most [maxPages] raw provider pages and never drains the collection.
  Future<void> requestSearchWindow({
    required bool Function() hasEnoughMatches,
    int maxPages = 2,
    bool retryInterrupted = false,
  }) {
    if (_disposed || maxPages <= 0) return Future.value();
    _searchHasEnoughMatches = hasEnoughMatches;
    cancelPrefetch();
    if (hasEnoughMatches()) {
      _searchPageBudget = 0;
      _searchScanStage = CollectionSearchScanStage.paused;
      _notify();
      return Future.value();
    }
    if (_appendFailure != null && !retryInterrupted) {
      _searchPageBudget = 0;
      _searchScanStage = CollectionSearchScanStage.interrupted;
      _notify();
      return Future.value();
    }
    if (!_hasMore || _stage != PlaylistDetailStage.content) {
      _searchPageBudget = 0;
      _searchScanStage = CollectionSearchScanStage.complete;
      _notify();
      return Future.value();
    }
    // A browse/manual page that is already in flight contributes to this
    // demand window once its rows reach the shared local index. Do not grant
    // two additional pages on top of it.
    _searchPageBudget = (maxPages - (_isLoadingMore ? 1 : 0)).clamp(0, 2);
    _searchScanStage = CollectionSearchScanStage.scanning;
    final future = _ensureAppendPump();
    _notify();
    return future;
  }

  /// Stops future search pages without cancelling an in-flight transport page.
  /// That page remains part of the reusable ordered snapshot when it finishes.
  void cancelSearchScan({bool notify = true}) {
    final changed =
        _searchPageBudget != 0 ||
        _searchHasEnoughMatches != null ||
        _searchScanStage == CollectionSearchScanStage.scanning;
    _searchPageBudget = 0;
    _searchHasEnoughMatches = null;
    _searchScanStage = CollectionSearchScanStage.idle;
    if (changed && notify) _notify();
  }

  bool get _wantsAppend =>
      _isLoadingAll ||
      _manualPageRequested ||
      (_searchPageBudget > 0 && !(_searchHasEnoughMatches?.call() ?? false)) ||
      (_prefetchPages > 0 && _tracks.length < _prefetchTarget);

  Future<void> _loadNextPage() async {
    if (!canLoadMore && !canRetryMore) return;
    final generation = _generation;
    final expectedOffset = _nextOffset;
    final operation = _beginLoad(expectedOffset, pageSize);
    _operation = operation;
    _isLoadingMore = true;
    _appendFailure = null;
    _notify();

    final latency = Stopwatch()..start();
    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;
    _isLoadingMore = false;

    final pageEnd = result.nextOffset;
    final hasMore = _pageHasMore(result);
    if (result.failure == null &&
        result.offset == expectedOffset &&
        _validPage(result, pageEnd, hasMore)) {
      _recordPageLatency(latency.elapsed);
      final seen = _tracks
          .map((track) => '${track.providerId}\u0000${track.opaqueId}')
          .toSet();
      final additions = result.tracks.where(
        (track) => seen.add('${track.providerId}\u0000${track.opaqueId}'),
      );
      _tracks = List.unmodifiable([..._tracks, ...additions]);
      _nextOffset = pageEnd;
      _omittedTrackCount += result.omittedTrackCount;
      if (result.omittedTrackCount > 0) _partialResultRevision += 1;
      _total = result.total;
      _totalIsExact = result.totalIsExact;
      _hasMore = hasMore;
      _appendFailure = null;
    } else {
      final failure = result.failure ?? UserLibraryFailure.invalidResponse;
      if (failure == UserLibraryFailure.authenticationRequired ||
          failure == UserLibraryFailure.replaced ||
          failure == UserLibraryFailure.cancelled ||
          failure == UserLibraryFailure.credentialRejected ||
          failure ==
              UserLibraryFailure.credentialRejectedStorageCleanupFailed) {
        _tracks = const [];
        _total = 0;
        _totalIsExact = true;
        _hasMore = false;
        _nextOffset = 0;
        _omittedTrackCount = 0;
        _failure = failure;
        _stage =
            failure == UserLibraryFailure.credentialRejected ||
                failure ==
                    UserLibraryFailure.credentialRejectedStorageCleanupFailed
            ? PlaylistDetailStage.credentialRejected
            : PlaylistDetailStage.authenticationRequired;
      } else {
        _appendFailure = failure;
      }
    }
    _notify();
  }

  /// Search promotes an existing browse request instead of starting a second
  /// loader. Its matches can use every page as soon as that page is published.
  Future<void> loadAll() {
    if (_disposed ||
        _isRefreshing ||
        !_hasMore ||
        _stage != PlaylistDetailStage.content) {
      return Future.value();
    }
    cancelSearchScan(notify: false);
    _isLoadingAll = true;
    cancelPrefetch();
    final future = _ensureAppendPump();
    _notify();
    return future;
  }

  Future<void> _ensureAppendPump() {
    if (_appendPump case final pump?) return pump.future;
    final pump = Completer<void>();
    _appendPump = pump; // Install before notifications can reenter this owner.
    unawaited(_runAppendPump(pump, _generation));
    return pump.future;
  }

  Future<void> _runAppendPump(Completer<void> pump, int generation) async {
    var retryIndex = 0;
    var nextPageInterval = loadAllPageInterval;
    if (_isLoadingAll &&
        _isTransientForAutomaticRetry(_appendFailure) &&
        transientRetryDelays.isNotEmpty) {
      await _delay(transientRetryDelays.first);
      retryIndex = 1;
      nextPageInterval = postTransientPageInterval;
    }

    while (_isCurrent(generation) &&
        _wantsAppend &&
        (canLoadMore || canRetryMore)) {
      _manualPageRequested = false;
      if (_prefetchPages > 0) --_prefetchPages;
      if (_searchPageBudget > 0) --_searchPageBudget;
      await _loadNextPage();
      if (!_isCurrent(generation)) break;
      final appendFailure = _appendFailure;
      if (appendFailure != null) {
        if (_searchScanStage == CollectionSearchScanStage.scanning) {
          _searchScanStage = CollectionSearchScanStage.interrupted;
          _searchPageBudget = 0;
        }
        if (_isLoadingAll &&
            _isTransientForAutomaticRetry(appendFailure) &&
            retryIndex < transientRetryDelays.length) {
          final retryDelay = transientRetryDelays[retryIndex++];
          await _delay(retryDelay);
          nextPageInterval = postTransientPageInterval;
          continue;
        }
        break;
      }
      if (_searchScanStage == CollectionSearchScanStage.scanning) {
        if (_searchHasEnoughMatches?.call() ?? false) {
          _searchPageBudget = 0;
          _searchScanStage = CollectionSearchScanStage.paused;
        } else if (!_hasMore) {
          _searchPageBudget = 0;
          _searchScanStage = CollectionSearchScanStage.complete;
        } else if (_searchPageBudget == 0) {
          _searchScanStage = CollectionSearchScanStage.paused;
        }
      }
      retryIndex = 0;
      if (_wantsAppend && canLoadMore && nextPageInterval > Duration.zero) {
        await _delay(nextPageInterval);
      }
      nextPageInterval = loadAllPageInterval;
    }

    if (_isCurrent(generation) && identical(_appendPump, pump)) {
      _appendPump = null;
      _manualPageRequested = false;
      cancelPrefetch();
      _isLoadingAll = false;
      if (_searchScanStage == CollectionSearchScanStage.scanning) {
        _searchScanStage = _hasMore
            ? CollectionSearchScanStage.paused
            : CollectionSearchScanStage.complete;
      }
      _notify();
    }
    pump.complete();
  }

  /// Stops automatic full-playlist loading after the current bounded page.
  /// The in-flight page is still allowed to finish and remains usable.
  void cancelLoadAll() {
    if (!_isLoadingAll) return;
    _isLoadingAll = false;
    _notify();
  }

  void retry() {
    if (canRetry) unawaited(load());
  }

  void retryMore() {
    if (canRetryMore) unawaited(loadMore());
  }

  void retryRefresh() {
    if (canRetryRefresh) unawaited(refresh());
  }

  void dismissRefreshFailure() {
    if (_refreshFailure == null) return;
    _refreshFailure = null;
    _notify();
  }

  bool _isRetryable(UserLibraryFailure? failure) =>
      failure == UserLibraryFailure.network ||
      failure == UserLibraryFailure.serviceUnavailable ||
      failure == UserLibraryFailure.invalidResponse ||
      failure == UserLibraryFailure.coreUnavailable;

  bool _canRetainSnapshot(UserLibraryFailure? failure) =>
      _isRetryable(failure) || failure == UserLibraryFailure.alreadyRunning;

  bool _isTransientForAutomaticRetry(UserLibraryFailure? failure) =>
      failure == UserLibraryFailure.network ||
      failure == UserLibraryFailure.serviceUnavailable;

  bool _pageHasMore(PlaylistTrackPageResult result) => result.hasMore;

  bool _validPage(
    PlaylistTrackPageResult result,
    int nextOffset,
    bool hasMore,
  ) {
    if (result.total < 0) return false;
    return isValidRawOffsetPage(
      offset: result.offset,
      continuationOffset: nextOffset,
      hasMore: hasMore,
      visibleCount: result.tracks.length,
      omittedCount: result.omittedTrackCount,
      total: result.totalIsExact ? result.total : null,
    );
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _recordPageLatency(Duration elapsed) {
    final micros = elapsed.inMicroseconds.clamp(50000, 10000000);
    _estimatedPageLatency = Duration(
      microseconds: (_estimatedPageLatency.inMicroseconds * 3 + micros) ~/ 4,
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    cancelPrefetch();
    cancelSearchScan(notify: false);
    _operation?.cancel();
    _operation = null;
    _isRefreshing = false;
    _isLoadingAll = false;
    super.dispose();
  }
}
