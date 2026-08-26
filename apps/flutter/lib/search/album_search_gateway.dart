import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/src/rust/api/search.dart' as bridge;

enum AlbumSearchFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class AlbumSearchPageResult {
  const AlbumSearchPageResult({
    this.page = 0,
    this.total = 0,
    this.hasMore = false,
    this.albums = const [],
    this.failure,
  });

  final int page;
  final int total;
  final bool hasMore;
  final List<AlbumSummary> albums;
  final AlbumSearchFailure? failure;
}

abstract interface class AlbumSearchGateway {
  AlbumSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  });
}

abstract interface class AlbumSearchPageLoadOperation {
  Future<AlbumSearchPageResult> run();
  bool cancel();
}

typedef AlbumSearchPageLoadOperationFactory =
    AlbumSearchPageLoadOperation Function(String query, int page, int size);

class RustAlbumSearchGateway implements AlbumSearchGateway {
  const RustAlbumSearchGateway({
    AlbumSearchPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final AlbumSearchPageLoadOperationFactory _operationFactory;

  @override
  AlbumSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) => _operationFactory(query, page, size);
}

AlbumSearchPageLoadOperation _beginRustLoad(String query, int page, int size) =>
    _RustAlbumSearchPageLoadOperation(
      bridge.beginQqMusicAlbumSearchPageLoad(
        query: query,
        page: page,
        size: size,
      ),
    );

class _RustAlbumSearchPageLoadOperation
    implements AlbumSearchPageLoadOperation {
  const _RustAlbumSearchPageLoadOperation(this._handle);

  final bridge.QqMusicAlbumSearchPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<AlbumSearchPageResult> run() async {
    try {
      return mapBridgeAlbumSearchPage(await _handle.run());
    } on Object {
      return const AlbumSearchPageResult(
        failure: AlbumSearchFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
AlbumSearchPageResult mapBridgeAlbumSearchPage(
  bridge.QqMusicAlbumSearchPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.page != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.albums.isNotEmpty) {
      return const AlbumSearchPageResult(
        failure: AlbumSearchFailure.invalidResponse,
      );
    }
    return AlbumSearchPageResult(failure: mapBridgeAlbumSearchFailure(failure));
  }
  if (result.page <= 0 ||
      result.total < 0 ||
      result.albums.length > result.total ||
      (result.hasMore && result.albums.isEmpty)) {
    return const AlbumSearchPageResult(
      failure: AlbumSearchFailure.invalidResponse,
    );
  }
  final albums = <AlbumSummary>[];
  for (final album in result.albums) {
    if (album.providerId.trim().isEmpty ||
        album.opaqueId.trim().isEmpty ||
        album.title.trim().isEmpty ||
        (album.artworkUri?.trim().isEmpty ?? false)) {
      return const AlbumSearchPageResult(
        failure: AlbumSearchFailure.invalidResponse,
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
  return AlbumSearchPageResult(
    page: result.page,
    total: result.total,
    hasMore: result.hasMore,
    albums: List.unmodifiable(albums),
  );
}

@visibleForTesting
AlbumSearchFailure mapBridgeAlbumSearchFailure(
  bridge.QqMusicAlbumSearchPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicAlbumSearchPageLoadFailure.coreUnavailable =>
    AlbumSearchFailure.coreUnavailable,
  bridge.QqMusicAlbumSearchPageLoadFailure.network =>
    AlbumSearchFailure.network,
  bridge.QqMusicAlbumSearchPageLoadFailure.serviceUnavailable =>
    AlbumSearchFailure.serviceUnavailable,
  bridge.QqMusicAlbumSearchPageLoadFailure.invalidResponse =>
    AlbumSearchFailure.invalidResponse,
  bridge.QqMusicAlbumSearchPageLoadFailure.cancelled =>
    AlbumSearchFailure.cancelled,
  bridge.QqMusicAlbumSearchPageLoadFailure.alreadyRunning =>
    AlbumSearchFailure.alreadyRunning,
};
