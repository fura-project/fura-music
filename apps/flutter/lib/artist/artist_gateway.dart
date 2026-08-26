import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge;

export 'package:flutterustmusic/catalog/catalog_models.dart' show ArtistSummary;

enum ArtistTrackFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class ArtistTrackPageResult {
  const ArtistTrackPageResult({
    this.offset = 0,
    this.total = 0,
    this.hasMore = false,
    this.tracks = const [],
    this.failure,
  });

  final int offset;
  final int total;
  final bool hasMore;
  final List<PlaylistTrackSummary> tracks;
  final ArtistTrackFailure? failure;
}

abstract interface class ArtistTrackGateway {
  ArtistTrackPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  });
}

abstract interface class ArtistTrackPageLoadOperation {
  Future<ArtistTrackPageResult> run();
  bool cancel();
}

typedef ArtistTrackPageLoadOperationFactory =
    ArtistTrackPageLoadOperation Function(
      ArtistSummary artist,
      int offset,
      int size,
    );

class RustArtistTrackGateway implements ArtistTrackGateway {
  const RustArtistTrackGateway({
    ArtistTrackPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final ArtistTrackPageLoadOperationFactory _operationFactory;

  @override
  ArtistTrackPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) => _operationFactory(artist, offset, size);
}

ArtistTrackPageLoadOperation _beginRustLoad(
  ArtistSummary artist,
  int offset,
  int size,
) => _RustArtistTrackPageLoadOperation(
  bridge.beginQqMusicArtistTrackPageLoad(
    providerId: artist.providerId,
    opaqueArtistId: artist.opaqueId,
    offset: offset,
    size: size,
  ),
);

class _RustArtistTrackPageLoadOperation
    implements ArtistTrackPageLoadOperation {
  const _RustArtistTrackPageLoadOperation(this._handle);

  final bridge.QqMusicArtistTrackPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<ArtistTrackPageResult> run() async {
    try {
      return mapBridgeArtistTrackPage(await _handle.run());
    } on Object {
      return const ArtistTrackPageResult(
        failure: ArtistTrackFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
ArtistTrackPageResult mapBridgeArtistTrackPage(
  bridge.QqMusicArtistTrackPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.offset != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.tracks.isNotEmpty) {
      return const ArtistTrackPageResult(
        failure: ArtistTrackFailure.invalidResponse,
      );
    }
    return ArtistTrackPageResult(failure: mapBridgeArtistTrackFailure(failure));
  }
  if (result.offset < 0 ||
      result.total < 0 ||
      result.offset + result.tracks.length > result.total ||
      (result.hasMore && result.tracks.isEmpty)) {
    return const ArtistTrackPageResult(
      failure: ArtistTrackFailure.invalidResponse,
    );
  }
  final tracks = <PlaylistTrackSummary>[];
  for (final track in result.tracks) {
    final mapped = mapBridgeLibraryTrackSummary(track);
    if (mapped == null) {
      return const ArtistTrackPageResult(
        failure: ArtistTrackFailure.invalidResponse,
      );
    }
    tracks.add(mapped);
  }
  return ArtistTrackPageResult(
    offset: result.offset,
    total: result.total,
    hasMore: result.hasMore,
    tracks: List.unmodifiable(tracks),
  );
}

@visibleForTesting
ArtistTrackFailure mapBridgeArtistTrackFailure(
  bridge.QqMusicArtistTrackPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicArtistTrackPageLoadFailure.coreUnavailable =>
    ArtistTrackFailure.coreUnavailable,
  bridge.QqMusicArtistTrackPageLoadFailure.network =>
    ArtistTrackFailure.network,
  bridge.QqMusicArtistTrackPageLoadFailure.serviceUnavailable =>
    ArtistTrackFailure.serviceUnavailable,
  bridge.QqMusicArtistTrackPageLoadFailure.invalidResponse =>
    ArtistTrackFailure.invalidResponse,
  bridge.QqMusicArtistTrackPageLoadFailure.cancelled =>
    ArtistTrackFailure.cancelled,
  bridge.QqMusicArtistTrackPageLoadFailure.alreadyRunning =>
    ArtistTrackFailure.alreadyRunning,
};
