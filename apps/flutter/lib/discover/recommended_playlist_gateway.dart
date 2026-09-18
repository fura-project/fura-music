import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/pagination/raw_offset_page.dart';
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
    this.continuationOffset = -1,
    this.hasMore = false,
    this.playlists = const [],
    this.omittedPlaylistCount = 0,
    this.failure,
  });

  final int offset;
  final int continuationOffset;
  final bool hasMore;
  final List<RecommendedPlaylistSummary> playlists;
  final int omittedPlaylistCount;
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
    this.providerId = 'qq-music',
    this.operationFactory,
  });

  final String providerId;
  final RecommendedPlaylistPageLoadOperationFactory? operationFactory;

  @override
  RecommendedPlaylistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) =>
      operationFactory?.call(offset, size) ??
      _beginRustLoad(providerId, offset, size);
}

RecommendedPlaylistPageLoadOperation _beginRustLoad(
  String providerId,
  int offset,
  int size,
) => _RustRecommendedPlaylistPageLoadOperation(
  bridge.beginQqMusicRecommendedPlaylistPageLoad(
    providerId: providerId,
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
    if (result.offset != 0 ||
        result.nextOffset != 0 ||
        result.hasMore ||
        result.playlists.isNotEmpty ||
        result.omittedPlaylistCount != 0) {
      return const RecommendedPlaylistPageResult(
        failure: RecommendedPlaylistFailure.invalidResponse,
      );
    }
    return RecommendedPlaylistPageResult(
      failure: mapBridgeRecommendedPlaylistFailure(failure),
    );
  }
  if (!isValidRawOffsetPage(
    offset: result.offset,
    continuationOffset: result.nextOffset,
    hasMore: result.hasMore,
    visibleCount: result.playlists.length,
    omittedCount: result.omittedPlaylistCount,
  )) {
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
    continuationOffset: result.nextOffset,
    hasMore: result.hasMore,
    playlists: List.unmodifiable(playlists),
    omittedPlaylistCount: result.omittedPlaylistCount,
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
