import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';

enum ArtistAlbumStage { loading, content, empty, error }

class ArtistAlbumController extends ChangeNotifier {
  ArtistAlbumController(this.artist, this._gateway);

  static const pageSize = 30;

  final ArtistSummary artist;
  final ArtistAlbumGateway _gateway;

  ArtistAlbumStage _stage = ArtistAlbumStage.loading;
  List<AlbumSummary> _albums = const [];
  ArtistAlbumFailure? _failure;
  ArtistAlbumFailure? _appendFailure;
  int _total = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _hasLoaded = false;
  ArtistAlbumPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  ArtistAlbumStage get stage => _stage;
  List<AlbumSummary> get albums => _albums;
  ArtistAlbumFailure? get failure => _failure;
  ArtistAlbumFailure? get appendFailure => _appendFailure;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasLoaded => _hasLoaded;
  bool get canRetry =>
      _stage == ArtistAlbumStage.error && _isRetryable(_failure);
  bool get canLoadMore =>
      _stage == ArtistAlbumStage.content && _hasMore && !_isLoadingMore;
  bool get canRetryMore =>
      _stage == ArtistAlbumStage.content &&
      !_isLoadingMore &&
      _isRetryable(_appendFailure);

  Future<void> load() => _hasLoaded ? Future.value() : _loadFirstPage();

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(
      artist: artist,
      offset: 0,
      size: pageSize,
    );
    _operation = operation;
    _albums = const [];
    _failure = null;
    _appendFailure = null;
    _total = 0;
    _nextOffset = 0;
    _hasMore = false;
    _isLoadingMore = false;
    _hasLoaded = false;
    _stage = ArtistAlbumStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    _hasLoaded = true;
    if (_validPage(result, expectedOffset: 0)) {
      _albums = List.unmodifiable(result.albums);
      _total = result.total;
      _nextOffset = result.albums.length;
      _hasMore = result.hasMore;
      _stage = _albums.isEmpty
          ? ArtistAlbumStage.empty
          : ArtistAlbumStage.content;
    } else {
      _failure = result.failure ?? ArtistAlbumFailure.invalidResponse;
      _stage = ArtistAlbumStage.error;
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
      final seen = _albums
          .map((album) => '${album.providerId}\u0000${album.opaqueId}')
          .toSet();
      final additions = result.albums.where(
        (album) => seen.add('${album.providerId}\u0000${album.opaqueId}'),
      );
      _albums = List.unmodifiable([..._albums, ...additions]);
      _total = result.total;
      _nextOffset = expectedOffset + result.albums.length;
      _hasMore = result.hasMore;
    } else {
      _appendFailure = result.failure ?? ArtistAlbumFailure.invalidResponse;
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
    ArtistAlbumPageResult result, {
    required int expectedOffset,
  }) =>
      result.failure == null &&
      result.offset == expectedOffset &&
      result.total >= expectedOffset + result.albums.length &&
      (!result.hasMore || result.albums.isNotEmpty);

  bool _isRetryable(ArtistAlbumFailure? failure) =>
      failure == ArtistAlbumFailure.coreUnavailable ||
      failure == ArtistAlbumFailure.network ||
      failure == ArtistAlbumFailure.serviceUnavailable ||
      failure == ArtistAlbumFailure.invalidResponse ||
      failure == ArtistAlbumFailure.alreadyRunning;

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
