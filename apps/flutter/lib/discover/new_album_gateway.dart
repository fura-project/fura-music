import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/new_albums.dart' as bridge;

enum NewAlbumRegion {
  mainlandChina,
  hongKongTaiwan,
  western,
  korea,
  japan,
  other,
}

enum NewAlbumFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class NewAlbumRelease {
  const NewAlbumRelease({
    required this.album,
    required this.artists,
    this.releaseDate,
  });

  final AlbumSummary album;
  final List<ArtistSummary> artists;
  final String? releaseDate;
}

class NewAlbumPageResult {
  const NewAlbumPageResult({
    required this.region,
    this.offset = 0,
    this.total = 0,
    this.hasMore = false,
    this.releases = const [],
    this.failure,
  });

  final NewAlbumRegion region;
  final int offset;
  final int total;
  final bool hasMore;
  final List<NewAlbumRelease> releases;
  final NewAlbumFailure? failure;
}

abstract interface class NewAlbumGateway {
  NewAlbumPageLoadOperation beginLoad({
    required NewAlbumRegion region,
    required int offset,
    required int size,
  });
}

abstract interface class NewAlbumPageLoadOperation {
  Future<NewAlbumPageResult> run();
  bool cancel();
}

typedef NewAlbumPageLoadOperationFactory = NewAlbumPageLoadOperation Function(
  NewAlbumRegion region,
  int offset,
  int size,
);

class RustNewAlbumGateway implements NewAlbumGateway {
  const RustNewAlbumGateway({
    NewAlbumPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final NewAlbumPageLoadOperationFactory _operationFactory;

  @override
  NewAlbumPageLoadOperation beginLoad({
    required NewAlbumRegion region,
    required int offset,
    required int size,
  }) => _operationFactory(region, offset, size);
}

NewAlbumPageLoadOperation _beginRustLoad(
  NewAlbumRegion region,
  int offset,
  int size,
) => _RustNewAlbumPageLoadOperation(
  region,
  bridge.beginQqMusicNewAlbumPageLoad(
    region: _bridgeRegion(region),
    offset: offset,
    size: size,
  ),
);

class _RustNewAlbumPageLoadOperation implements NewAlbumPageLoadOperation {
  const _RustNewAlbumPageLoadOperation(this._expectedRegion, this._handle);

  final NewAlbumRegion _expectedRegion;
  final bridge.QqMusicNewAlbumPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<NewAlbumPageResult> run() async {
    try {
      return mapBridgeNewAlbumPage(await _handle.run(), _expectedRegion);
    } on Object {
      return NewAlbumPageResult(
        region: _expectedRegion,
        failure: NewAlbumFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
NewAlbumPageResult mapBridgeNewAlbumPage(
  bridge.QqMusicNewAlbumPageLoad result,
  NewAlbumRegion expectedRegion,
) {
  final region = mapBridgeNewAlbumRegion(result.region);
  final failure = result.failure;
  if (region != expectedRegion) {
    return NewAlbumPageResult(
      region: expectedRegion,
      failure: NewAlbumFailure.invalidResponse,
    );
  }
  if (failure != null) {
    if (result.offset != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.releases.isNotEmpty) {
      return NewAlbumPageResult(
        region: region,
        failure: NewAlbumFailure.invalidResponse,
      );
    }
    return NewAlbumPageResult(
      region: region,
      failure: mapBridgeNewAlbumFailure(failure),
    );
  }
  if (result.offset < 0 ||
      result.total < 0 ||
      result.offset + result.releases.length > result.total ||
      (result.hasMore && result.releases.isEmpty)) {
    return NewAlbumPageResult(
      region: region,
      failure: NewAlbumFailure.invalidResponse,
    );
  }

  final releases = <NewAlbumRelease>[];
  for (final release in result.releases) {
    final album = release.album;
    if (album.providerId.trim().isEmpty ||
        album.opaqueId.trim().isEmpty ||
        album.title.trim().isEmpty ||
        (album.artworkUri?.trim().isEmpty ?? false) ||
        (release.releaseDate?.trim().isEmpty ?? false)) {
      return NewAlbumPageResult(
        region: region,
        failure: NewAlbumFailure.invalidResponse,
      );
    }
    final artists = <ArtistSummary>[];
    for (final artist in release.artists) {
      if (artist.providerId.trim().isEmpty ||
          artist.opaqueId.trim().isEmpty ||
          artist.name.trim().isEmpty ||
          (artist.artworkUri?.trim().isEmpty ?? false)) {
        return NewAlbumPageResult(
          region: region,
          failure: NewAlbumFailure.invalidResponse,
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
    releases.add(
      NewAlbumRelease(
        album: AlbumSummary(
          providerId: album.providerId,
          opaqueId: album.opaqueId,
          title: album.title,
          artworkUri: album.artworkUri,
        ),
        artists: List.unmodifiable(artists),
        releaseDate: release.releaseDate,
      ),
    );
  }
  return NewAlbumPageResult(
    region: region,
    offset: result.offset,
    total: result.total,
    hasMore: result.hasMore,
    releases: List.unmodifiable(releases),
  );
}

@visibleForTesting
NewAlbumRegion mapBridgeNewAlbumRegion(
  bridge.QqMusicNewAlbumRegion region,
) => switch (region) {
  bridge.QqMusicNewAlbumRegion.mainlandChina => NewAlbumRegion.mainlandChina,
  bridge.QqMusicNewAlbumRegion.hongKongTaiwan => NewAlbumRegion.hongKongTaiwan,
  bridge.QqMusicNewAlbumRegion.western => NewAlbumRegion.western,
  bridge.QqMusicNewAlbumRegion.korea => NewAlbumRegion.korea,
  bridge.QqMusicNewAlbumRegion.japan => NewAlbumRegion.japan,
  bridge.QqMusicNewAlbumRegion.other => NewAlbumRegion.other,
};

bridge.QqMusicNewAlbumRegion _bridgeRegion(
  NewAlbumRegion region,
) => switch (region) {
  NewAlbumRegion.mainlandChina => bridge.QqMusicNewAlbumRegion.mainlandChina,
  NewAlbumRegion.hongKongTaiwan => bridge.QqMusicNewAlbumRegion.hongKongTaiwan,
  NewAlbumRegion.western => bridge.QqMusicNewAlbumRegion.western,
  NewAlbumRegion.korea => bridge.QqMusicNewAlbumRegion.korea,
  NewAlbumRegion.japan => bridge.QqMusicNewAlbumRegion.japan,
  NewAlbumRegion.other => bridge.QqMusicNewAlbumRegion.other,
};

@visibleForTesting
NewAlbumFailure mapBridgeNewAlbumFailure(
  bridge.QqMusicNewAlbumPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicNewAlbumPageLoadFailure.coreUnavailable =>
    NewAlbumFailure.coreUnavailable,
  bridge.QqMusicNewAlbumPageLoadFailure.network => NewAlbumFailure.network,
  bridge.QqMusicNewAlbumPageLoadFailure.serviceUnavailable =>
    NewAlbumFailure.serviceUnavailable,
  bridge.QqMusicNewAlbumPageLoadFailure.invalidResponse =>
    NewAlbumFailure.invalidResponse,
  bridge.QqMusicNewAlbumPageLoadFailure.cancelled => NewAlbumFailure.cancelled,
  bridge.QqMusicNewAlbumPageLoadFailure.alreadyRunning =>
    NewAlbumFailure.alreadyRunning,
};
