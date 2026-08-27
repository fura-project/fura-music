import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum TrackCommentStage { loading, content, empty, error }

class TrackCommentController extends ChangeNotifier {
  TrackCommentController(this._gateway, this.track);

  static const pageSize = 20;

  final TrackCommentGateway _gateway;
  final PlaylistTrackSummary track;

  TrackCommentStage _stage = TrackCommentStage.loading;
  List<TrackCommentSummary> _hotComments = const [];
  List<TrackCommentSummary> _latestComments = const [];
  TrackCommentFailure? _failure;
  TrackCommentFailure? _appendFailure;
  int _total = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  TrackCommentPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  TrackCommentStage get stage => _stage;
  List<TrackCommentSummary> get hotComments => _hotComments;
  List<TrackCommentSummary> get latestComments => _latestComments;
  TrackCommentFailure? get failure => _failure;
  TrackCommentFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry =>
      _stage == TrackCommentStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == TrackCommentStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == TrackCommentStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  Future<void> load() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(
      track: track,
      offset: 0,
      size: pageSize,
    );
    _operation = operation;
    _hotComments = const [];
    _latestComments = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextOffset = 0;
    _hasMore = false;
    _isLoadingMore = false;
    _stage = TrackCommentStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedOffset: 0, firstPage: true)) {
      _hotComments = List.unmodifiable(result.hotComments);
      _latestComments = List.unmodifiable(result.latestComments);
      _total = result.total;
      _nextOffset = result.hasMore ? pageSize : result.latestComments.length;
      _hasMore = result.hasMore;
      _stage = _hotComments.isEmpty && _latestComments.isEmpty
          ? TrackCommentStage.empty
          : TrackCommentStage.content;
    } else {
      _failure = result.failure ?? TrackCommentFailure.invalidResponse;
      _stage = TrackCommentStage.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (!canLoadMore && !canRetryMore) return;
    final generation = _generation;
    final expectedOffset = _nextOffset;
    final operation = _gateway.beginLoad(
      track: track,
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

    if (_validPage(result, expectedOffset: expectedOffset, firstPage: false)) {
      final seen = _latestComments
          .map((comment) => '${comment.providerId}\u0000${comment.opaqueId}')
          .toSet();
      final additions = result.latestComments.where(
        (comment) => seen.add('${comment.providerId}\u0000${comment.opaqueId}'),
      );
      _latestComments = List.unmodifiable([..._latestComments, ...additions]);
      _total = result.total;
      _nextOffset = result.hasMore
          ? expectedOffset + pageSize
          : expectedOffset + result.latestComments.length;
      _hasMore = result.hasMore;
    } else {
      _appendFailure = result.failure ?? TrackCommentFailure.invalidResponse;
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
    TrackCommentPageResult result, {
    required int expectedOffset,
    required bool firstPage,
  }) {
    final pageEnd = expectedOffset + result.latestComments.length;
    return result.failure == null &&
        result.offset == expectedOffset &&
        result.total >= pageEnd &&
        (firstPage || result.hotComments.isEmpty) &&
        (result.hasMore
            ? result.latestComments.isNotEmpty && pageEnd < result.total
            : result.latestComments.isEmpty || pageEnd == result.total);
  }

  bool _isRetryable(TrackCommentFailure? failure) =>
      failure == TrackCommentFailure.coreUnavailable ||
      failure == TrackCommentFailure.network ||
      failure == TrackCommentFailure.serviceUnavailable ||
      failure == TrackCommentFailure.invalidResponse ||
      failure == TrackCommentFailure.alreadyRunning;

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
