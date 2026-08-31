import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

enum RelatedTracksFailure {
  coreUnavailable,
  invalidTrack,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class RelatedTracksResult {
  const RelatedTracksResult({this.tracks = const [], this.failure});

  final List<PlaylistTrackSummary> tracks;
  final RelatedTracksFailure? failure;
}

abstract interface class RelatedTracksGateway {
  RelatedTracksLoadOperation beginLoad(PlaylistTrackSummary seed);
}

abstract interface class RelatedTracksLoadOperation {
  Future<RelatedTracksResult> run();
  bool cancel();
}

typedef RelatedTracksLoadOperationFactory = RelatedTracksLoadOperation Function(
  PlaylistTrackSummary seed,
);

class RustRelatedTracksGateway implements RelatedTracksGateway {
  const RustRelatedTracksGateway({
    RelatedTracksLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final RelatedTracksLoadOperationFactory _operationFactory;

  @override
  RelatedTracksLoadOperation beginLoad(PlaylistTrackSummary seed) =>
      _operationFactory(seed);
}

RelatedTracksLoadOperation _beginRustLoad(PlaylistTrackSummary seed) =>
    _RustRelatedTracksLoadOperation(
      bridge.beginQqMusicRelatedTracksLoad(
        providerId: seed.providerId,
        opaqueId: seed.opaqueId,
      ),
    );

class _RustRelatedTracksLoadOperation implements RelatedTracksLoadOperation {
  const _RustRelatedTracksLoadOperation(this._handle);

  final bridge.QqMusicRelatedTracksLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<RelatedTracksResult> run() async {
    try {
      return mapBridgeRelatedTracks(await _handle.run());
    } on Object {
      return const RelatedTracksResult(
        failure: RelatedTracksFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
RelatedTracksResult mapBridgeRelatedTracks(
  bridge.QqMusicRelatedTracksLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.tracks.isNotEmpty) {
      return const RelatedTracksResult(
        failure: RelatedTracksFailure.invalidResponse,
      );
    }
    return RelatedTracksResult(failure: mapBridgeRelatedTracksFailure(failure));
  }

  final identities = <String>{};
  final tracks = <PlaylistTrackSummary>[];
  for (final track in result.tracks) {
    final mapped = mapBridgeLibraryTrackSummary(track);
    if (mapped == null ||
        !identities.add('${mapped.providerId}\u0000${mapped.opaqueId}')) {
      return const RelatedTracksResult(
        failure: RelatedTracksFailure.invalidResponse,
      );
    }
    tracks.add(mapped);
  }
  return RelatedTracksResult(tracks: List.unmodifiable(tracks));
}

@visibleForTesting
RelatedTracksFailure mapBridgeRelatedTracksFailure(
  bridge.QqMusicRelatedTracksLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicRelatedTracksLoadFailure.coreUnavailable =>
    RelatedTracksFailure.coreUnavailable,
  bridge.QqMusicRelatedTracksLoadFailure.invalidTrack =>
    RelatedTracksFailure.invalidTrack,
  bridge.QqMusicRelatedTracksLoadFailure.network =>
    RelatedTracksFailure.network,
  bridge.QqMusicRelatedTracksLoadFailure.serviceUnavailable =>
    RelatedTracksFailure.serviceUnavailable,
  bridge.QqMusicRelatedTracksLoadFailure.invalidResponse =>
    RelatedTracksFailure.invalidResponse,
  bridge.QqMusicRelatedTracksLoadFailure.cancelled =>
    RelatedTracksFailure.cancelled,
  bridge.QqMusicRelatedTracksLoadFailure.alreadyRunning =>
    RelatedTracksFailure.alreadyRunning,
};
