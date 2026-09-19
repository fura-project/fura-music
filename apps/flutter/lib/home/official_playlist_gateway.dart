import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

class OfficialPlaylistSummary {
  const OfficialPlaylistSummary({
    required this.providerId,
    required this.opaqueId,
    required this.title,
    this.artworkUri,
    this.creator,
    this.playCount,
    this.categories = const [],
  });

  final String providerId;
  final String opaqueId;
  final String title;
  final String? artworkUri;
  final String? creator;
  final BigInt? playCount;
  final List<String> categories;

  RecommendedPlaylistSummary toRecommendationSummary() =>
      RecommendedPlaylistSummary(
        providerId: providerId,
        opaqueId: opaqueId,
        title: title,
        artworkUri: artworkUri,
      );
}

enum OfficialPlaylistFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class OfficialPlaylistPageResult {
  const OfficialPlaylistPageResult({
    this.page = 0,
    this.nextPage = 0,
    this.total = 0,
    this.hasMore = false,
    this.playlists = const [],
    this.omittedPlaylistCount = 0,
    this.failure,
  });

  final int page;
  final int nextPage;
  final int total;
  final bool hasMore;
  final List<OfficialPlaylistSummary> playlists;
  final int omittedPlaylistCount;
  final OfficialPlaylistFailure? failure;
}

abstract interface class OfficialPlaylistGateway {
  OfficialPlaylistPageLoadOperation beginLoad({
    required int page,
    required int size,
  });
}

abstract interface class OfficialPlaylistPageLoadOperation {
  Future<OfficialPlaylistPageResult> run();
  bool cancel();
}

typedef OfficialPlaylistPageLoadOperationFactory =
    OfficialPlaylistPageLoadOperation Function(int page, int size);

class RustOfficialPlaylistGateway implements OfficialPlaylistGateway {
  const RustOfficialPlaylistGateway({
    this.providerId = 'qq-music',
    this.operationFactory,
  });

  final String providerId;
  final OfficialPlaylistPageLoadOperationFactory? operationFactory;

  @override
  OfficialPlaylistPageLoadOperation beginLoad({
    required int page,
    required int size,
  }) =>
      operationFactory?.call(page, size) ??
      _beginRustLoad(providerId, page, size);
}

class UnsupportedOfficialPlaylistGateway implements OfficialPlaylistGateway {
  const UnsupportedOfficialPlaylistGateway();

  @override
  OfficialPlaylistPageLoadOperation beginLoad({
    required int page,
    required int size,
  }) => const _UnsupportedOfficialPlaylistPageLoadOperation();
}

OfficialPlaylistPageLoadOperation _beginRustLoad(
  String providerId,
  int page,
  int size,
) => _RustOfficialPlaylistPageLoadOperation(
  bridge.beginQqMusicOfficialPlaylistPageLoad(
    providerId: providerId,
    page: page,
    size: size,
  ),
);

class _RustOfficialPlaylistPageLoadOperation
    implements OfficialPlaylistPageLoadOperation {
  const _RustOfficialPlaylistPageLoadOperation(this._handle);

  final bridge.QqMusicOfficialPlaylistPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<OfficialPlaylistPageResult> run() async {
    try {
      return mapBridgeOfficialPlaylistPage(await _handle.run());
    } on Object {
      return const OfficialPlaylistPageResult(
        failure: OfficialPlaylistFailure.coreUnavailable,
      );
    }
  }
}

class _UnsupportedOfficialPlaylistPageLoadOperation
    implements OfficialPlaylistPageLoadOperation {
  const _UnsupportedOfficialPlaylistPageLoadOperation();

  @override
  bool cancel() => false;

  @override
  Future<OfficialPlaylistPageResult> run() async =>
      const OfficialPlaylistPageResult(
        failure: OfficialPlaylistFailure.coreUnavailable,
      );
}

@visibleForTesting
OfficialPlaylistPageResult mapBridgeOfficialPlaylistPage(
  bridge.QqMusicOfficialPlaylistPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.page != 0 ||
        result.nextPage != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.playlists.isNotEmpty ||
        result.omittedPlaylistCount != 0) {
      return const OfficialPlaylistPageResult(
        failure: OfficialPlaylistFailure.invalidResponse,
      );
    }
    return OfficialPlaylistPageResult(
      failure: mapBridgeOfficialPlaylistFailure(failure),
    );
  }
  if (result.page < 1 ||
      result.nextPage != result.page + 1 ||
      result.total < 0 ||
      result.omittedPlaylistCount < 0 ||
      (result.hasMore &&
          result.playlists.isEmpty &&
          result.omittedPlaylistCount == 0)) {
    return const OfficialPlaylistPageResult(
      failure: OfficialPlaylistFailure.invalidResponse,
    );
  }
  final playlists = <OfficialPlaylistSummary>[];
  for (final item in result.playlists) {
    final playlist = item.playlist;
    if (playlist.providerId.trim().isEmpty ||
        playlist.opaqueId.trim().isEmpty ||
        playlist.title.trim().isEmpty ||
        (playlist.artworkUri != null && playlist.artworkUri!.trim().isEmpty) ||
        (item.creator != null && item.creator!.trim().isEmpty) ||
        (item.playCount != null && item.playCount! < BigInt.zero) ||
        item.categories.any((category) => category.trim().isEmpty)) {
      return const OfficialPlaylistPageResult(
        failure: OfficialPlaylistFailure.invalidResponse,
      );
    }
    playlists.add(
      OfficialPlaylistSummary(
        providerId: playlist.providerId,
        opaqueId: playlist.opaqueId,
        title: playlist.title,
        artworkUri: playlist.artworkUri,
        creator: item.creator,
        playCount: item.playCount,
        categories: List.unmodifiable(item.categories),
      ),
    );
  }
  return OfficialPlaylistPageResult(
    page: result.page,
    nextPage: result.nextPage,
    total: result.total,
    hasMore: result.hasMore,
    playlists: List.unmodifiable(playlists),
    omittedPlaylistCount: result.omittedPlaylistCount,
  );
}

@visibleForTesting
OfficialPlaylistFailure mapBridgeOfficialPlaylistFailure(
  bridge.QqMusicOfficialPlaylistPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicOfficialPlaylistPageLoadFailure.coreUnavailable =>
    OfficialPlaylistFailure.coreUnavailable,
  bridge.QqMusicOfficialPlaylistPageLoadFailure.network =>
    OfficialPlaylistFailure.network,
  bridge.QqMusicOfficialPlaylistPageLoadFailure.serviceUnavailable =>
    OfficialPlaylistFailure.serviceUnavailable,
  bridge.QqMusicOfficialPlaylistPageLoadFailure.invalidResponse =>
    OfficialPlaylistFailure.invalidResponse,
  bridge.QqMusicOfficialPlaylistPageLoadFailure.cancelled =>
    OfficialPlaylistFailure.cancelled,
  bridge.QqMusicOfficialPlaylistPageLoadFailure.alreadyRunning =>
    OfficialPlaylistFailure.alreadyRunning,
};
