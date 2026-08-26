import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

class RecommendedPlaylistSummary {
  const RecommendedPlaylistSummary({
    required this.providerId,
    required this.opaqueId,
    required this.title,
    this.artworkUri,
    this.trackCount,
  });

  final String providerId;
  final String opaqueId;
  final String title;
  final String? artworkUri;
  final int? trackCount;

  UserPlaylistSummary toPlaylistSummary() => UserPlaylistSummary(
    providerId: providerId,
    opaqueId: opaqueId,
    title: title,
    artworkUri: artworkUri,
    trackCount: trackCount,
  );
}

enum RecommendedPlaylistFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class RecommendedPlaylistPageResult {
  const RecommendedPlaylistPageResult({
    this.offset = 0,
    this.hasMore = false,
    this.playlists = const [],
    this.failure,
  });

  final int offset;
  final bool hasMore;
  final List<RecommendedPlaylistSummary> playlists;
  final RecommendedPlaylistFailure? failure;
}

abstract interface class RecommendedPlaylistGateway {
  RecommendedPlaylistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  });
}

abstract interface class RecommendedPlaylistPageLoadOperation {
  Future<RecommendedPlaylistPageResult> run();
  bool cancel();
}

typedef RecommendedPlaylistPageLoadOperationFactory =
    RecommendedPlaylistPageLoadOperation Function(int offset, int size);

class RustRecommendedPlaylistGateway implements RecommendedPlaylistGateway {
  const RustRecommendedPlaylistGateway({
    RecommendedPlaylistPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final RecommendedPlaylistPageLoadOperationFactory _operationFactory;

  @override
  RecommendedPlaylistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _operationFactory(offset, size);
}

RecommendedPlaylistPageLoadOperation _beginRustLoad(int offset, int size) =>
    _RustRecommendedPlaylistPageLoadOperation(
      bridge.beginQqMusicRecommendedPlaylistPageLoad(
        offset: offset,
        size: size,
      ),
    );

class _RustRecommendedPlaylistPageLoadOperation
    implements RecommendedPlaylistPageLoadOperation {
  const _RustRecommendedPlaylistPageLoadOperation(this._handle);

  final bridge.QqMusicRecommendedPlaylistPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<RecommendedPlaylistPageResult> run() async {
    try {
      return mapBridgeRecommendedPlaylistPage(await _handle.run());
    } on Object {
      return const RecommendedPlaylistPageResult(
        failure: RecommendedPlaylistFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
RecommendedPlaylistPageResult mapBridgeRecommendedPlaylistPage(
  bridge.QqMusicRecommendedPlaylistPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.offset != 0 || result.hasMore || result.playlists.isNotEmpty) {
      return const RecommendedPlaylistPageResult(
        failure: RecommendedPlaylistFailure.invalidResponse,
      );
    }
    return RecommendedPlaylistPageResult(
      failure: mapBridgeRecommendedPlaylistFailure(failure),
    );
  }
  if (result.offset < 0 || (result.hasMore && result.playlists.isEmpty)) {
    return const RecommendedPlaylistPageResult(
      failure: RecommendedPlaylistFailure.invalidResponse,
    );
  }
  final playlists = <RecommendedPlaylistSummary>[];
  for (final playlist in result.playlists) {
    if (playlist.providerId.trim().isEmpty ||
        playlist.opaqueId.trim().isEmpty ||
        playlist.title.trim().isEmpty ||
        (playlist.artworkUri != null && playlist.artworkUri!.trim().isEmpty) ||
        (playlist.trackCount != null && playlist.trackCount! < 0)) {
      return const RecommendedPlaylistPageResult(
        failure: RecommendedPlaylistFailure.invalidResponse,
      );
    }
    playlists.add(
      RecommendedPlaylistSummary(
        providerId: playlist.providerId,
        opaqueId: playlist.opaqueId,
        title: playlist.title,
        artworkUri: playlist.artworkUri,
        trackCount: playlist.trackCount,
      ),
    );
  }
  return RecommendedPlaylistPageResult(
    offset: result.offset,
    hasMore: result.hasMore,
    playlists: List.unmodifiable(playlists),
  );
}

@visibleForTesting
RecommendedPlaylistFailure mapBridgeRecommendedPlaylistFailure(
  bridge.QqMusicRecommendedPlaylistPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicRecommendedPlaylistPageLoadFailure.coreUnavailable =>
    RecommendedPlaylistFailure.coreUnavailable,
  bridge.QqMusicRecommendedPlaylistPageLoadFailure.network =>
    RecommendedPlaylistFailure.network,
  bridge.QqMusicRecommendedPlaylistPageLoadFailure.serviceUnavailable =>
    RecommendedPlaylistFailure.serviceUnavailable,
  bridge.QqMusicRecommendedPlaylistPageLoadFailure.invalidResponse =>
    RecommendedPlaylistFailure.invalidResponse,
  bridge.QqMusicRecommendedPlaylistPageLoadFailure.cancelled =>
    RecommendedPlaylistFailure.cancelled,
  bridge.QqMusicRecommendedPlaylistPageLoadFailure.alreadyRunning =>
    RecommendedPlaylistFailure.alreadyRunning,
};
