import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/search.dart' as bridge;

enum TrackSearchFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class TrackSearchPageResult {
  const TrackSearchPageResult({
    this.page = 0,
    this.total = 0,
    this.hasMore = false,
    this.tracks = const [],
    this.failure,
  });

  final int page;
  final int total;
  final bool hasMore;
  final List<PlaylistTrackSummary> tracks;
  final TrackSearchFailure? failure;
}

abstract interface class TrackSearchGateway {
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  });
}

abstract interface class TrackSearchPageLoadOperation {
  Future<TrackSearchPageResult> run();
  bool cancel();
}

typedef TrackSearchPageLoadOperationFactory =
    TrackSearchPageLoadOperation Function(String query, int page, int size);

class RustTrackSearchGateway implements TrackSearchGateway {
  const RustTrackSearchGateway({
    TrackSearchPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final TrackSearchPageLoadOperationFactory _operationFactory;

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) => _operationFactory(query, page, size);
}

TrackSearchPageLoadOperation _beginRustLoad(String query, int page, int size) =>
    _RustTrackSearchPageLoadOperation(
      bridge.beginQqMusicTrackSearchPageLoad(
        query: query,
        page: page,
        size: size,
      ),
    );

class _RustTrackSearchPageLoadOperation
    implements TrackSearchPageLoadOperation {
  const _RustTrackSearchPageLoadOperation(this._handle);

  final bridge.QqMusicTrackSearchPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<TrackSearchPageResult> run() async {
    try {
      return mapBridgeTrackSearchPage(await _handle.run());
    } on Object {
      return const TrackSearchPageResult(
        failure: TrackSearchFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
TrackSearchPageResult mapBridgeTrackSearchPage(
  bridge.QqMusicTrackSearchPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.page != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.tracks.isNotEmpty) {
      return const TrackSearchPageResult(
        failure: TrackSearchFailure.invalidResponse,
      );
    }
    return TrackSearchPageResult(failure: mapBridgeTrackSearchFailure(failure));
  }
  if (result.page <= 0 ||
      result.total < 0 ||
      result.tracks.length > result.total ||
      (result.hasMore && result.tracks.isEmpty)) {
    return const TrackSearchPageResult(
      failure: TrackSearchFailure.invalidResponse,
    );
  }
  final tracks = <PlaylistTrackSummary>[];
  for (final track in result.tracks) {
    if (track.providerId.trim().isEmpty ||
        track.opaqueId.trim().isEmpty ||
        track.title.trim().isEmpty ||
        track.artistNames.any((artist) => artist.trim().isEmpty) ||
        (track.durationSeconds != null && track.durationSeconds! < 0)) {
      return const TrackSearchPageResult(
        failure: TrackSearchFailure.invalidResponse,
      );
    }
    tracks.add(
      PlaylistTrackSummary(
        providerId: track.providerId,
        opaqueId: track.opaqueId,
        title: track.title,
        artistNames: List.unmodifiable(track.artistNames),
        subtitle: track.subtitle,
        albumTitle: track.albumTitle,
        artworkUri: track.artworkUri,
        durationSeconds: track.durationSeconds,
      ),
    );
  }
  return TrackSearchPageResult(
    page: result.page,
    total: result.total,
    hasMore: result.hasMore,
    tracks: List.unmodifiable(tracks),
  );
}

@visibleForTesting
TrackSearchFailure mapBridgeTrackSearchFailure(
  bridge.QqMusicTrackSearchPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicTrackSearchPageLoadFailure.coreUnavailable =>
    TrackSearchFailure.coreUnavailable,
  bridge.QqMusicTrackSearchPageLoadFailure.network =>
    TrackSearchFailure.network,
  bridge.QqMusicTrackSearchPageLoadFailure.serviceUnavailable =>
    TrackSearchFailure.serviceUnavailable,
  bridge.QqMusicTrackSearchPageLoadFailure.invalidResponse =>
    TrackSearchFailure.invalidResponse,
  bridge.QqMusicTrackSearchPageLoadFailure.cancelled =>
    TrackSearchFailure.cancelled,
  bridge.QqMusicTrackSearchPageLoadFailure.alreadyRunning =>
    TrackSearchFailure.alreadyRunning,
};
