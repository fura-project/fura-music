import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/search.dart' as bridge;

enum ArtistSearchFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class ArtistSearchPageResult {
  const ArtistSearchPageResult({
    this.page = 0,
    this.total = 0,
    this.hasMore = false,
    this.artists = const [],
    this.failure,
  });

  final int page;
  final int total;
  final bool hasMore;
  final List<ArtistSummary> artists;
  final ArtistSearchFailure? failure;
}

abstract interface class ArtistSearchGateway {
  ArtistSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  });
}

abstract interface class ArtistSearchPageLoadOperation {
  Future<ArtistSearchPageResult> run();
  bool cancel();
}

typedef ArtistSearchPageLoadOperationFactory =
    ArtistSearchPageLoadOperation Function(String query, int page, int size);

class RustArtistSearchGateway implements ArtistSearchGateway {
  const RustArtistSearchGateway({
    ArtistSearchPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final ArtistSearchPageLoadOperationFactory _operationFactory;

  @override
  ArtistSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) => _operationFactory(query, page, size);
}

ArtistSearchPageLoadOperation _beginRustLoad(
  String query,
  int page,
  int size,
) => _RustArtistSearchPageLoadOperation(
  bridge.beginQqMusicArtistSearchPageLoad(query: query, page: page, size: size),
);

class _RustArtistSearchPageLoadOperation
    implements ArtistSearchPageLoadOperation {
  const _RustArtistSearchPageLoadOperation(this._handle);

  final bridge.QqMusicArtistSearchPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<ArtistSearchPageResult> run() async {
    try {
      return mapBridgeArtistSearchPage(await _handle.run());
    } on Object {
      return const ArtistSearchPageResult(
        failure: ArtistSearchFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
ArtistSearchPageResult mapBridgeArtistSearchPage(
  bridge.QqMusicArtistSearchPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.page != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.artists.isNotEmpty) {
      return const ArtistSearchPageResult(
        failure: ArtistSearchFailure.invalidResponse,
      );
    }
    return ArtistSearchPageResult(
      failure: mapBridgeArtistSearchFailure(failure),
    );
  }
  if (result.page <= 0 ||
      result.total < 0 ||
      result.artists.length > result.total ||
      (result.hasMore && result.artists.isEmpty)) {
    return const ArtistSearchPageResult(
      failure: ArtistSearchFailure.invalidResponse,
    );
  }
  final artists = <ArtistSummary>[];
  for (final artist in result.artists) {
    if (artist.providerId.trim().isEmpty ||
        artist.opaqueId.trim().isEmpty ||
        artist.name.trim().isEmpty) {
      return const ArtistSearchPageResult(
        failure: ArtistSearchFailure.invalidResponse,
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
  return ArtistSearchPageResult(
    page: result.page,
    total: result.total,
    hasMore: result.hasMore,
    artists: List.unmodifiable(artists),
  );
}

@visibleForTesting
ArtistSearchFailure mapBridgeArtistSearchFailure(
  bridge.QqMusicArtistSearchPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicArtistSearchPageLoadFailure.coreUnavailable =>
    ArtistSearchFailure.coreUnavailable,
  bridge.QqMusicArtistSearchPageLoadFailure.network =>
    ArtistSearchFailure.network,
  bridge.QqMusicArtistSearchPageLoadFailure.serviceUnavailable =>
    ArtistSearchFailure.serviceUnavailable,
  bridge.QqMusicArtistSearchPageLoadFailure.invalidResponse =>
    ArtistSearchFailure.invalidResponse,
  bridge.QqMusicArtistSearchPageLoadFailure.cancelled =>
    ArtistSearchFailure.cancelled,
  bridge.QqMusicArtistSearchPageLoadFailure.alreadyRunning =>
    ArtistSearchFailure.alreadyRunning,
};
