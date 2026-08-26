import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge;

class AlbumDetails {
  const AlbumDetails({
    required this.album,
    required this.artists,
    this.subtitle,
    this.releaseDate,
    this.description,
    this.language,
    this.albumType,
    this.genre,
    this.company,
  });

  final AlbumSummary album;
  final List<ArtistSummary> artists;
  final String? subtitle;
  final String? releaseDate;
  final String? description;
  final String? language;
  final String? albumType;
  final String? genre;
  final String? company;
}

enum AlbumDetailsFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class AlbumDetailsResult {
  const AlbumDetailsResult({this.details, this.failure});

  final AlbumDetails? details;
  final AlbumDetailsFailure? failure;
}

abstract interface class AlbumDetailsGateway {
  AlbumDetailsLoadOperation beginLoad(AlbumSummary album);
}

abstract interface class AlbumDetailsLoadOperation {
  Future<AlbumDetailsResult> run();
  bool cancel();
}

typedef AlbumDetailsLoadOperationFactory = AlbumDetailsLoadOperation Function(
  AlbumSummary album,
);

class RustAlbumDetailsGateway implements AlbumDetailsGateway {
  const RustAlbumDetailsGateway({
    AlbumDetailsLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final AlbumDetailsLoadOperationFactory _operationFactory;

  @override
  AlbumDetailsLoadOperation beginLoad(AlbumSummary album) =>
      _operationFactory(album);
}

AlbumDetailsLoadOperation _beginRustLoad(AlbumSummary album) =>
    _RustAlbumDetailsLoadOperation(
      album,
      bridge.beginQqMusicAlbumDetailsLoad(
        providerId: album.providerId,
        opaqueAlbumId: album.opaqueId,
      ),
    );

class _RustAlbumDetailsLoadOperation implements AlbumDetailsLoadOperation {
  const _RustAlbumDetailsLoadOperation(this._expectedAlbum, this._handle);

  final AlbumSummary _expectedAlbum;
  final bridge.QqMusicAlbumDetailsLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<AlbumDetailsResult> run() async {
    try {
      return mapBridgeAlbumDetails(await _handle.run(), _expectedAlbum);
    } on Object {
      return const AlbumDetailsResult(
        failure: AlbumDetailsFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
AlbumDetailsResult mapBridgeAlbumDetails(
  bridge.QqMusicAlbumDetailsLoad result,
  AlbumSummary expectedAlbum,
) {
  final details = result.details;
  final failure = result.failure;
  if (failure != null) {
    if (details != null) {
      return const AlbumDetailsResult(
        failure: AlbumDetailsFailure.invalidResponse,
      );
    }
    return AlbumDetailsResult(failure: mapBridgeAlbumDetailsFailure(failure));
  }
  if (details == null) {
    return const AlbumDetailsResult(
      failure: AlbumDetailsFailure.invalidResponse,
    );
  }

  final album = details.album;
  if (album.providerId != expectedAlbum.providerId ||
      album.providerId.trim().isEmpty ||
      album.opaqueId.trim().isEmpty ||
      album.title.trim().isEmpty ||
      (album.artworkUri?.trim().isEmpty ?? false) ||
      !_validOptional(details.subtitle) ||
      !_validOptional(details.releaseDate) ||
      !_validOptional(details.description) ||
      !_validOptional(details.language) ||
      !_validOptional(details.albumType) ||
      !_validOptional(details.genre) ||
      !_validOptional(details.company)) {
    return const AlbumDetailsResult(
      failure: AlbumDetailsFailure.invalidResponse,
    );
  }

  final artists = <ArtistSummary>[];
  for (final artist in details.artists) {
    if (artist.providerId != expectedAlbum.providerId ||
        artist.providerId.trim().isEmpty ||
        artist.opaqueId.trim().isEmpty ||
        artist.name.trim().isEmpty) {
      return const AlbumDetailsResult(
        failure: AlbumDetailsFailure.invalidResponse,
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

  return AlbumDetailsResult(
    details: AlbumDetails(
      album: AlbumSummary(
        providerId: album.providerId,
        opaqueId: album.opaqueId,
        title: album.title,
        artworkUri: album.artworkUri,
      ),
      artists: List.unmodifiable(artists),
      subtitle: details.subtitle,
      releaseDate: details.releaseDate,
      description: details.description,
      language: details.language,
      albumType: details.albumType,
      genre: details.genre,
      company: details.company,
    ),
  );
}

bool _validOptional(String? value) => value == null || value.trim().isNotEmpty;

@visibleForTesting
AlbumDetailsFailure mapBridgeAlbumDetailsFailure(
  bridge.QqMusicAlbumDetailsLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicAlbumDetailsLoadFailure.coreUnavailable =>
    AlbumDetailsFailure.coreUnavailable,
  bridge.QqMusicAlbumDetailsLoadFailure.network => AlbumDetailsFailure.network,
  bridge.QqMusicAlbumDetailsLoadFailure.serviceUnavailable =>
    AlbumDetailsFailure.serviceUnavailable,
  bridge.QqMusicAlbumDetailsLoadFailure.invalidResponse =>
    AlbumDetailsFailure.invalidResponse,
  bridge.QqMusicAlbumDetailsLoadFailure.cancelled =>
    AlbumDetailsFailure.cancelled,
  bridge.QqMusicAlbumDetailsLoadFailure.alreadyRunning =>
    AlbumDetailsFailure.alreadyRunning,
};
