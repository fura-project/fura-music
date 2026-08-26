import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/search.dart' as bridge;

enum TrackSearchFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class TrackSearchPageResult {
  const TrackSearchPageResult({
    this.page = 0,
    this.total = 0,
    this.hasMore = false,
    this.items = const [],
    this.failure,
  });

  final int page;
  final int total;
  final bool hasMore;
  final List<TrackSearchItem> items;
  final TrackSearchFailure? failure;
}

class TrackSearchItem {
  const TrackSearchItem({
    required this.track,
    this.album,
    this.artists = const [],
  });

  final PlaylistTrackSummary track;
  final AlbumSummary? album;
  final List<ArtistSummary> artists;
}

abstract interface class TrackSearchGateway {
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  });
}

abstract interface class TrackSearchPageLoadOperation {
  Future<TrackSearchPageResult> run();
  bool cancel();
}

typedef TrackSearchPageLoadOperationFactory =
    TrackSearchPageLoadOperation Function(String query, int page, int size);

class RustTrackSearchGateway implements TrackSearchGateway {
  const RustTrackSearchGateway({
    TrackSearchPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final TrackSearchPageLoadOperationFactory _operationFactory;

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) => _operationFactory(query, page, size);
}

TrackSearchPageLoadOperation _beginRustLoad(String query, int page, int size) =>
    _RustTrackSearchPageLoadOperation(
      bridge.beginQqMusicTrackSearchPageLoad(
        query: query,
        page: page,
        size: size,
      ),
    );

class _RustTrackSearchPageLoadOperation
    implements TrackSearchPageLoadOperation {
  const _RustTrackSearchPageLoadOperation(this._handle);

  final bridge.QqMusicTrackSearchPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<TrackSearchPageResult> run() async {
    try {
      return mapBridgeTrackSearchPage(await _handle.run());
    } on Object {
      return const TrackSearchPageResult(
        failure: TrackSearchFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
TrackSearchPageResult mapBridgeTrackSearchPage(
  bridge.QqMusicTrackSearchPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.page != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.items.isNotEmpty) {
      return const TrackSearchPageResult(
        failure: TrackSearchFailure.invalidResponse,
      );
    }
    return TrackSearchPageResult(failure: mapBridgeTrackSearchFailure(failure));
  }
  if (result.page <= 0 ||
      result.total < 0 ||
      result.items.length > result.total ||
      (result.hasMore && result.items.isEmpty)) {
    return const TrackSearchPageResult(
      failure: TrackSearchFailure.invalidResponse,
    );
  }
  final items = <TrackSearchItem>[];
  for (final item in result.items) {
    final track = item.track;
    final mappedTrack = mapBridgeLibraryTrackSummary(track);
    if (mappedTrack == null) {
      return const TrackSearchPageResult(
        failure: TrackSearchFailure.invalidResponse,
      );
    }
    final album = item.album;
    AlbumSummary? mappedAlbum;
    if (album != null) {
      if (album.providerId.trim().isEmpty ||
          album.opaqueId.trim().isEmpty ||
          album.title.trim().isEmpty ||
          (album.artworkUri != null && album.artworkUri!.trim().isEmpty)) {
        return const TrackSearchPageResult(
          failure: TrackSearchFailure.invalidResponse,
        );
      }
      mappedAlbum = AlbumSummary(
        providerId: album.providerId,
        opaqueId: album.opaqueId,
        title: album.title,
        artworkUri: album.artworkUri,
      );
    }
    if (!_sameAlbum(mappedTrack.album, mappedAlbum)) {
      return const TrackSearchPageResult(
        failure: TrackSearchFailure.invalidResponse,
      );
    }
    final artists = <ArtistSummary>[];
    for (final artist in item.artists) {
      if (artist.providerId.trim().isEmpty ||
          artist.opaqueId.trim().isEmpty ||
          artist.name.trim().isEmpty) {
        return const TrackSearchPageResult(
          failure: TrackSearchFailure.invalidResponse,
        );
      }
      artists.add(
        ArtistSummary(
          providerId: artist.providerId,
          opaqueId: artist.opaqueId,
          name: artist.name,
        ),
      );
    }
    items.add(
      TrackSearchItem(
        track: mappedTrack,
        album: mappedAlbum,
        artists: List.unmodifiable(artists),
      ),
    );
  }
  return TrackSearchPageResult(
    page: result.page,
    total: result.total,
    hasMore: result.hasMore,
    items: List.unmodifiable(items),
  );
}

bool _sameAlbum(AlbumSummary? first, AlbumSummary? second) =>
    first == null && second == null ||
    first != null &&
        second != null &&
        first.providerId == second.providerId &&
        first.opaqueId == second.opaqueId &&
        first.title == second.title &&
        first.artworkUri == second.artworkUri;

@visibleForTesting
TrackSearchFailure mapBridgeTrackSearchFailure(
  bridge.QqMusicTrackSearchPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicTrackSearchPageLoadFailure.coreUnavailable =>
    TrackSearchFailure.coreUnavailable,
  bridge.QqMusicTrackSearchPageLoadFailure.network =>
    TrackSearchFailure.network,
  bridge.QqMusicTrackSearchPageLoadFailure.serviceUnavailable =>
    TrackSearchFailure.serviceUnavailable,
  bridge.QqMusicTrackSearchPageLoadFailure.invalidResponse =>
    TrackSearchFailure.invalidResponse,
  bridge.QqMusicTrackSearchPageLoadFailure.cancelled =>
    TrackSearchFailure.cancelled,
  bridge.QqMusicTrackSearchPageLoadFailure.alreadyRunning =>
    TrackSearchFailure.alreadyRunning,
};
