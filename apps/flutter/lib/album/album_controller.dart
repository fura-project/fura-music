import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum AlbumTrackStage { loading, content, empty, error }

class AlbumController extends ChangeNotifier {
  AlbumController(this.album, this._gateway);

  static const pageSize = 30;

  final AlbumSummary album;
  final AlbumTrackGateway _gateway;

  AlbumTrackStage _stage = AlbumTrackStage.loading;
  List<PlaylistTrackSummary> _tracks = const [];
  AlbumTrackFailure? _failure;
  AlbumTrackFailure? _appendFailure;
  int _total = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  AlbumTrackPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  AlbumTrackStage get stage => _stage;
  List<PlaylistTrackSummary> get tracks => _tracks;
  AlbumTrackFailure? get failure => _failure;
  AlbumTrackFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get canRetry =>
      _stage == AlbumTrackStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == AlbumTrackStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == AlbumTrackStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  Future<void> load() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(
      album: album,
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
    _stage = AlbumTrackStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedOffset: 0)) {
      _tracks = List.unmodifiable(result.tracks);
      _total = result.total;
      _nextOffset = result.tracks.length;
      _hasMore = result.hasMore;
      _stage = _tracks.isEmpty
          ? AlbumTrackStage.empty
          : AlbumTrackStage.content;
    } else {
      _failure = result.failure ?? AlbumTrackFailure.invalidResponse;
      _stage = AlbumTrackStage.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (!canLoadMore && !canRetryMore) return;
    final generation = _generation;
    final expectedOffset = _nextOffset;
    final operation = _gateway.beginLoad(
      album: album,
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
      _appendFailure = result.failure ?? AlbumTrackFailure.invalidResponse;
    }
    _notify();
  }

  void retry() {
    if (canRetry) unawaited(_loadFirstPage());
  }

  void retryMore() {
    if (canRetryMore) unawaited(loadMore());
  }

  bool _validPage(AlbumTrackPageResult result, {required int expectedOffset}) =>
      result.failure == null &&
      result.offset == expectedOffset &&
      result.total >= expectedOffset + result.tracks.length &&
      (!result.hasMore || result.tracks.isNotEmpty);

  bool _isRetryable(AlbumTrackFailure? failure) =>
      failure == AlbumTrackFailure.coreUnavailable ||
      failure == AlbumTrackFailure.network ||
      failure == AlbumTrackFailure.serviceUnavailable ||
      failure == AlbumTrackFailure.invalidResponse ||
      failure == AlbumTrackFailure.alreadyRunning;

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
