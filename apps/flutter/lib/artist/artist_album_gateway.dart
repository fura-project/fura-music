import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge;

enum ArtistAlbumFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class ArtistAlbumPageResult {
  const ArtistAlbumPageResult({
    this.offset = 0,
    this.total = 0,
    this.hasMore = false,
    this.albums = const [],
    this.failure,
  });

  final int offset;
  final int total;
  final bool hasMore;
  final List<AlbumSummary> albums;
  final ArtistAlbumFailure? failure;
}

abstract interface class ArtistAlbumGateway {
  ArtistAlbumPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  });
}

abstract interface class ArtistAlbumPageLoadOperation {
  Future<ArtistAlbumPageResult> run();
  bool cancel();
}

typedef ArtistAlbumPageLoadOperationFactory =
    ArtistAlbumPageLoadOperation Function(
      ArtistSummary artist,
      int offset,
      int size,
    );

class RustArtistAlbumGateway implements ArtistAlbumGateway {
  const RustArtistAlbumGateway({
    ArtistAlbumPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final ArtistAlbumPageLoadOperationFactory _operationFactory;

  @override
  ArtistAlbumPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) => _operationFactory(artist, offset, size);
}

ArtistAlbumPageLoadOperation _beginRustLoad(
  ArtistSummary artist,
  int offset,
  int size,
) => _RustArtistAlbumPageLoadOperation(
  bridge.beginQqMusicArtistAlbumPageLoad(
    providerId: artist.providerId,
    opaqueArtistId: artist.opaqueId,
    offset: offset,
    size: size,
  ),
);

class _RustArtistAlbumPageLoadOperation
    implements ArtistAlbumPageLoadOperation {
  const _RustArtistAlbumPageLoadOperation(this._handle);

  final bridge.QqMusicArtistAlbumPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<ArtistAlbumPageResult> run() async {
    try {
      return mapBridgeArtistAlbumPage(await _handle.run());
    } on Object {
      return const ArtistAlbumPageResult(
        failure: ArtistAlbumFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
ArtistAlbumPageResult mapBridgeArtistAlbumPage(
  bridge.QqMusicArtistAlbumPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.offset != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.albums.isNotEmpty) {
      return const ArtistAlbumPageResult(
        failure: ArtistAlbumFailure.invalidResponse,
      );
    }
    return ArtistAlbumPageResult(failure: mapBridgeArtistAlbumFailure(failure));
  }
  if (result.offset < 0 ||
      result.total < 0 ||
      result.offset + result.albums.length > result.total ||
      (result.hasMore && result.albums.isEmpty)) {
    return const ArtistAlbumPageResult(
      failure: ArtistAlbumFailure.invalidResponse,
    );
  }
  final albums = <AlbumSummary>[];
  for (final album in result.albums) {
    if (album.providerId.trim().isEmpty ||
        album.opaqueId.trim().isEmpty ||
        album.title.trim().isEmpty ||
        (album.artworkUri?.trim().isEmpty ?? false)) {
      return const ArtistAlbumPageResult(
        failure: ArtistAlbumFailure.invalidResponse,
      );
    }
    albums.add(
      AlbumSummary(
        providerId: album.providerId,
        opaqueId: album.opaqueId,
        title: album.title,
        artworkUri: album.artworkUri,
      ),
    );
  }
  return ArtistAlbumPageResult(
    offset: result.offset,
    total: result.total,
    hasMore: result.hasMore,
    albums: List.unmodifiable(albums),
  );
}

@visibleForTesting
ArtistAlbumFailure mapBridgeArtistAlbumFailure(
  bridge.QqMusicArtistAlbumPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicArtistAlbumPageLoadFailure.coreUnavailable =>
    ArtistAlbumFailure.coreUnavailable,
  bridge.QqMusicArtistAlbumPageLoadFailure.network =>
    ArtistAlbumFailure.network,
  bridge.QqMusicArtistAlbumPageLoadFailure.serviceUnavailable =>
    ArtistAlbumFailure.serviceUnavailable,
  bridge.QqMusicArtistAlbumPageLoadFailure.invalidResponse =>
    ArtistAlbumFailure.invalidResponse,
  bridge.QqMusicArtistAlbumPageLoadFailure.cancelled =>
    ArtistAlbumFailure.cancelled,
  bridge.QqMusicArtistAlbumPageLoadFailure.alreadyRunning =>
    ArtistAlbumFailure.alreadyRunning,
};
