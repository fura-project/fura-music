import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

enum RadarFailure {
  coreUnavailable,
  authenticationRequired,
  credentialRejected,
  credentialRejectedStorageCleanupFailed,
  network,
  serviceUnavailable,
  invalidResponse,
  replaced,
  cancelled,
  alreadyRunning,
}

class RadarTrackPageResult {
  const RadarTrackPageResult({
    this.page = 0,
    this.hasMore = false,
    this.tracks = const [],
    this.failure,
  });

  final int page;
  final bool hasMore;
  final List<PlaylistTrackSummary> tracks;
  final RadarFailure? failure;
}

abstract interface class RadarGateway {
  RadarTrackPageLoadOperation beginLoad({required int page});
}

abstract interface class RadarTrackPageLoadOperation {
  Future<RadarTrackPageResult> run();
  bool cancel();
}

typedef RadarTrackPageLoadOperationFactory =
    RadarTrackPageLoadOperation Function(int page);

class RustRadarGateway implements RadarGateway {
  RustRadarGateway({
    CredentialVault? credentialVault,
    RadarTrackPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final RadarTrackPageLoadOperationFactory _operationFactory;

  @override
  RadarTrackPageLoadOperation beginLoad({required int page}) =>
      _VaultCleaningRadarTrackPageLoadOperation(
        _operationFactory(page),
        _credentialVault,
      );
}

RadarTrackPageLoadOperation _beginRustLoad(int page) =>
    _RustRadarTrackPageLoadOperation(
      bridge.beginQqMusicRadarTrackPageLoad(page: page),
    );

class _RustRadarTrackPageLoadOperation implements RadarTrackPageLoadOperation {
  const _RustRadarTrackPageLoadOperation(this._handle);

  final bridge.QqMusicRadarTrackPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<RadarTrackPageResult> run() async {
    try {
      return mapBridgeRadarTrackPage(await _handle.run());
    } on Object {
      return const RadarTrackPageResult(failure: RadarFailure.coreUnavailable);
    }
  }
}

class _VaultCleaningRadarTrackPageLoadOperation
    implements RadarTrackPageLoadOperation {
  const _VaultCleaningRadarTrackPageLoadOperation(this._inner, this._vault);

  final RadarTrackPageLoadOperation _inner;
  final CredentialVault _vault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<RadarTrackPageResult> run() async {
    final result = await _inner.run();
    if (result.failure != RadarFailure.credentialRejected) return result;
    try {
      await _vault.delete();
      return result;
    } on Object {
      return const RadarTrackPageResult(
        failure: RadarFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}

@visibleForTesting
RadarTrackPageResult mapBridgeRadarTrackPage(
  bridge.QqMusicRadarTrackPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.page != 0 || result.hasMore || result.tracks.isNotEmpty) {
      return const RadarTrackPageResult(failure: RadarFailure.invalidResponse);
    }
    return RadarTrackPageResult(failure: mapBridgeRadarFailure(failure));
  }
  if (result.page <= 0 || (result.hasMore && result.tracks.isEmpty)) {
    return const RadarTrackPageResult(failure: RadarFailure.invalidResponse);
  }

  final tracks = <PlaylistTrackSummary>[];
  for (final track in result.tracks) {
    final mapped = mapBridgeLibraryTrackSummary(track);
    if (mapped == null) {
      return const RadarTrackPageResult(failure: RadarFailure.invalidResponse);
    }
    tracks.add(mapped);
  }
  return RadarTrackPageResult(
    page: result.page,
    hasMore: result.hasMore,
    tracks: List.unmodifiable(tracks),
  );
}

@visibleForTesting
RadarFailure mapBridgeRadarFailure(
  bridge.QqMusicRadarTrackPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicRadarTrackPageLoadFailure.coreUnavailable =>
    RadarFailure.coreUnavailable,
  bridge.QqMusicRadarTrackPageLoadFailure.authenticationRequired =>
    RadarFailure.authenticationRequired,
  bridge.QqMusicRadarTrackPageLoadFailure.credentialRejected =>
    RadarFailure.credentialRejected,
  bridge.QqMusicRadarTrackPageLoadFailure.network => RadarFailure.network,
  bridge.QqMusicRadarTrackPageLoadFailure.serviceUnavailable =>
    RadarFailure.serviceUnavailable,
  bridge.QqMusicRadarTrackPageLoadFailure.invalidResponse =>
    RadarFailure.invalidResponse,
  bridge.QqMusicRadarTrackPageLoadFailure.replaced => RadarFailure.replaced,
  bridge.QqMusicRadarTrackPageLoadFailure.cancelled => RadarFailure.cancelled,
  bridge.QqMusicRadarTrackPageLoadFailure.alreadyRunning =>
    RadarFailure.alreadyRunning,
};
