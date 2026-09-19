import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/pagination/raw_offset_page.dart';
import 'package:flutterustmusic/playback/collection_playback_source.dart';

enum ArtistTrackStage { loading, content, empty, error }

class ArtistController extends ChangeNotifier {
  ArtistController(this.artist, this._gateway);

  static const pageSize = 30;

  final ArtistSummary artist;
  final ArtistTrackGateway _gateway;

  ArtistTrackStage _stage = ArtistTrackStage.loading;
  List<PlaylistTrackSummary> _tracks = const [];
  ArtistTrackFailure? _failure;
  ArtistTrackFailure? _appendFailure;
  int _total = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  int _omittedTrackCount = 0;
  int _partialResultRevision = 0;
  bool _isLoadingMore = false;
  ArtistTrackPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  ArtistTrackStage get stage => _stage;
  List<PlaylistTrackSummary> get tracks => _tracks;
  ArtistTrackFailure? get failure => _failure;
  ArtistTrackFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  int get omittedTrackCount => _omittedTrackCount;
  int get partialResultRevision => _partialResultRevision;
  bool get canRetry =>
      _stage == ArtistTrackStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == ArtistTrackStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == ArtistTrackStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  CollectionPlaybackSource collectionPlaybackSource() {
    final artistIdentity = artist;
    final gateway = _gateway;
    return CollectionPlaybackSource(
      sourceId:
          'artist-tracks:${artistIdentity.providerId}:${artistIdentity.opaqueId}',
      providerId: artistIdentity.providerId,
      initialTracks: _tracks,
      nextCursor: _nextOffset,
      hasMore: _hasMore,
      loader: (cursor) {
        final operation = gateway.beginLoad(
          artist: artistIdentity,
          offset: cursor,
          size: pageSize,
        );
        return CallbackCollectionPlaybackPageOperation(() async {
          final result = await operation.run();
          final valid =
              result.failure == null &&
              result.offset == cursor &&
              isValidRawOffsetPage(
                offset: cursor,
                continuationOffset: result.continuationOffset,
                total: result.total,
                hasMore: result.hasMore,
                visibleCount: result.tracks.length,
                omittedCount: result.omittedTrackCount,
              );
          return CollectionPlaybackPage(
            requestCursor: cursor,
            nextCursor: valid ? result.continuationOffset : cursor,
            hasMore: valid && result.hasMore,
            tracks: valid ? result.tracks : const [],
            omittedTrackCount: valid ? result.omittedTrackCount : 0,
            failure: valid ? null : _mapArtistCollectionFailure(result.failure),
          );
        }, operation.cancel);
      },
    );
  }

  Future<void> load() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(
      artist: artist,
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
    _omittedTrackCount = 0;
    _isLoadingMore = false;
    _stage = ArtistTrackStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result, expectedOffset: 0)) {
      _tracks = List.unmodifiable(result.tracks);
      _total = result.total;
      _nextOffset = result.continuationOffset;
      _hasMore = result.hasMore;
      _omittedTrackCount = result.omittedTrackCount;
      if (result.omittedTrackCount > 0) _partialResultRevision += 1;
      _stage = _tracks.isEmpty && _omittedTrackCount == 0
          ? ArtistTrackStage.empty
          : ArtistTrackStage.content;
    } else {
      _failure = result.failure ?? ArtistTrackFailure.invalidResponse;
      _stage = ArtistTrackStage.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (!canLoadMore && !canRetryMore) return;
    final generation = _generation;
    final expectedOffset = _nextOffset;
    final operation = _gateway.beginLoad(
      artist: artist,
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
      _nextOffset = result.continuationOffset;
      _hasMore = result.hasMore;
      _omittedTrackCount += result.omittedTrackCount;
      if (result.omittedTrackCount > 0) _partialResultRevision += 1;
    } else {
      _appendFailure = result.failure ?? ArtistTrackFailure.invalidResponse;
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
    ArtistTrackPageResult result, {
    required int expectedOffset,
  }) =>
      result.failure == null &&
      result.offset == expectedOffset &&
      isValidRawOffsetPage(
        offset: expectedOffset,
        continuationOffset: result.continuationOffset,
        total: result.total,
        hasMore: result.hasMore,
        visibleCount: result.tracks.length,
        omittedCount: result.omittedTrackCount,
      );

  bool _isRetryable(ArtistTrackFailure? failure) =>
      failure == ArtistTrackFailure.coreUnavailable ||
      failure == ArtistTrackFailure.network ||
      failure == ArtistTrackFailure.serviceUnavailable ||
      failure == ArtistTrackFailure.invalidResponse ||
      failure == ArtistTrackFailure.alreadyRunning;

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

CollectionPlaybackFailure _mapArtistCollectionFailure(
  ArtistTrackFailure? failure,
) => switch (failure) {
  ArtistTrackFailure.coreUnavailable =>
    CollectionPlaybackFailure.coreUnavailable,
  ArtistTrackFailure.network => CollectionPlaybackFailure.network,
  ArtistTrackFailure.serviceUnavailable =>
    CollectionPlaybackFailure.serviceUnavailable,
  ArtistTrackFailure.cancelled => CollectionPlaybackFailure.cancelled,
  ArtistTrackFailure.alreadyRunning => CollectionPlaybackFailure.alreadyRunning,
  ArtistTrackFailure.invalidResponse ||
  null => CollectionPlaybackFailure.invalidResponse,
};
