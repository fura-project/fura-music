import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge;

export 'package:flutterustmusic/catalog/catalog_models.dart' show AlbumSummary;

enum AlbumTrackFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class AlbumTrackPageResult {
  const AlbumTrackPageResult({
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
  final AlbumTrackFailure? failure;
}

abstract interface class AlbumTrackGateway {
  AlbumTrackPageLoadOperation beginLoad({
    required AlbumSummary album,
    required int offset,
    required int size,
  });
}

abstract interface class AlbumTrackPageLoadOperation {
  Future<AlbumTrackPageResult> run();
  bool cancel();
}

typedef AlbumTrackPageLoadOperationFactory =
    AlbumTrackPageLoadOperation Function(
      AlbumSummary album,
      int offset,
      int size,
    );

class RustAlbumTrackGateway implements AlbumTrackGateway {
  const RustAlbumTrackGateway({
    AlbumTrackPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final AlbumTrackPageLoadOperationFactory _operationFactory;

  @override
  AlbumTrackPageLoadOperation beginLoad({
    required AlbumSummary album,
    required int offset,
    required int size,
  }) => _operationFactory(album, offset, size);
}

AlbumTrackPageLoadOperation _beginRustLoad(
  AlbumSummary album,
  int offset,
  int size,
) => _RustAlbumTrackPageLoadOperation(
  bridge.beginQqMusicAlbumTrackPageLoad(
    providerId: album.providerId,
    opaqueAlbumId: album.opaqueId,
    offset: offset,
    size: size,
  ),
);

class _RustAlbumTrackPageLoadOperation implements AlbumTrackPageLoadOperation {
  const _RustAlbumTrackPageLoadOperation(this._handle);

  final bridge.QqMusicAlbumTrackPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<AlbumTrackPageResult> run() async {
    try {
      return mapBridgeAlbumTrackPage(await _handle.run());
    } on Object {
      return const AlbumTrackPageResult(
        failure: AlbumTrackFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
AlbumTrackPageResult mapBridgeAlbumTrackPage(
  bridge.QqMusicAlbumTrackPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.offset != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.tracks.isNotEmpty) {
      return const AlbumTrackPageResult(
        failure: AlbumTrackFailure.invalidResponse,
      );
    }
    return AlbumTrackPageResult(failure: mapBridgeAlbumTrackFailure(failure));
  }
  if (result.offset < 0 ||
      result.total < 0 ||
      result.offset + result.tracks.length > result.total ||
      (result.hasMore && result.tracks.isEmpty)) {
    return const AlbumTrackPageResult(
      failure: AlbumTrackFailure.invalidResponse,
    );
  }
  final tracks = <PlaylistTrackSummary>[];
  for (final track in result.tracks) {
    final mapped = mapBridgeLibraryTrackSummary(track);
    if (mapped == null) {
      return const AlbumTrackPageResult(
        failure: AlbumTrackFailure.invalidResponse,
      );
    }
    tracks.add(mapped);
  }
  return AlbumTrackPageResult(
    offset: result.offset,
    total: result.total,
    hasMore: result.hasMore,
    tracks: List.unmodifiable(tracks),
  );
}

@visibleForTesting
AlbumTrackFailure mapBridgeAlbumTrackFailure(
  bridge.QqMusicAlbumTrackPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicAlbumTrackPageLoadFailure.coreUnavailable =>
    AlbumTrackFailure.coreUnavailable,
  bridge.QqMusicAlbumTrackPageLoadFailure.network => AlbumTrackFailure.network,
  bridge.QqMusicAlbumTrackPageLoadFailure.serviceUnavailable =>
    AlbumTrackFailure.serviceUnavailable,
  bridge.QqMusicAlbumTrackPageLoadFailure.invalidResponse =>
    AlbumTrackFailure.invalidResponse,
  bridge.QqMusicAlbumTrackPageLoadFailure.cancelled =>
    AlbumTrackFailure.cancelled,
  bridge.QqMusicAlbumTrackPageLoadFailure.alreadyRunning =>
    AlbumTrackFailure.alreadyRunning,
};
