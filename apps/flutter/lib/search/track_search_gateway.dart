import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/search/search_failure.dart';
import 'package:flutterustmusic/src/rust/api/search.dart' as bridge;

export 'package:flutterustmusic/search/search_failure.dart';

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
  final SearchFailure? failure;
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
        failure: SearchFailure.coreUnavailable,
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
        failure: SearchFailure.invalidResponse,
      );
    }
    return TrackSearchPageResult(failure: mapBridgeSearchFailure(failure));
  }
  if (result.page <= 0 ||
      result.total < 0 ||
      result.items.length > result.total ||
      (result.hasMore && result.items.isEmpty)) {
    return const TrackSearchPageResult(failure: SearchFailure.invalidResponse);
  }
  final items = <TrackSearchItem>[];
  for (final item in result.items) {
    final track = item.track;
    final mappedTrack = mapBridgeLibraryTrackSummary(track);
    if (mappedTrack == null) {
      return const TrackSearchPageResult(
        failure: SearchFailure.invalidResponse,
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
          failure: SearchFailure.invalidResponse,
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
        failure: SearchFailure.invalidResponse,
      );
    }
    final artists = <ArtistSummary>[];
    for (final artist in item.artists) {
      if (artist.providerId.trim().isEmpty ||
          artist.opaqueId.trim().isEmpty ||
          artist.name.trim().isEmpty ||
          (artist.artworkUri?.trim().isEmpty ?? false)) {
        return const TrackSearchPageResult(
          failure: SearchFailure.invalidResponse,
        );
      }
      artists.add(
        ArtistSummary(
          providerId: artist.providerId,
          opaqueId: artist.opaqueId,
          name: artist.name,
          artworkUri: artist.artworkUri,
        ),
      );
    }
    if (!_sameArtists(mappedTrack.artists, artists)) {
      return const TrackSearchPageResult(
        failure: SearchFailure.invalidResponse,
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

bool _sameArtists(List<ArtistSummary> first, List<ArtistSummary> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index].providerId != second[index].providerId ||
        first[index].opaqueId != second[index].opaqueId ||
        first[index].name != second[index].name ||
        first[index].artworkUri != second[index].artworkUri) {
      return false;
    }
  }
  return true;
}

@visibleForTesting
SearchFailure mapBridgeSearchFailure(
  bridge.QqMusicTrackSearchPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicTrackSearchPageLoadFailure.coreUnavailable =>
    SearchFailure.coreUnavailable,
  bridge.QqMusicTrackSearchPageLoadFailure.network => SearchFailure.network,
  bridge.QqMusicTrackSearchPageLoadFailure.serviceUnavailable =>
    SearchFailure.serviceUnavailable,
  bridge.QqMusicTrackSearchPageLoadFailure.invalidResponse =>
    SearchFailure.invalidResponse,
  bridge.QqMusicTrackSearchPageLoadFailure.cancelled => SearchFailure.cancelled,
  bridge.QqMusicTrackSearchPageLoadFailure.alreadyRunning =>
    SearchFailure.alreadyRunning,
};
