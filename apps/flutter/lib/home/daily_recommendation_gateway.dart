import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

enum DailyRecommendationFailure {
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

class DailyRecommendationResult {
  const DailyRecommendationResult({this.playlist, this.failure});

  final RecommendedPlaylistSummary? playlist;
  final DailyRecommendationFailure? failure;
}

abstract interface class DailyRecommendationGateway {
  DailyRecommendationLoadOperation beginLoad();
}

abstract interface class DailyRecommendationLoadOperation {
  Future<DailyRecommendationResult> run();
  bool cancel();
}

typedef DailyRecommendationLoadOperationFactory =
    DailyRecommendationLoadOperation Function();

class RustDailyRecommendationGateway implements DailyRecommendationGateway {
  RustDailyRecommendationGateway({
    CredentialVault? credentialVault,
    DailyRecommendationLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final DailyRecommendationLoadOperationFactory _operationFactory;

  @override
  DailyRecommendationLoadOperation beginLoad() =>
      _VaultCleaningDailyRecommendationLoadOperation(
        _operationFactory(),
        _credentialVault,
      );
}

DailyRecommendationLoadOperation _beginRustLoad() =>
    _RustDailyRecommendationLoadOperation(
      bridge.beginQqMusicDailyRecommendationLoad(),
    );

class _RustDailyRecommendationLoadOperation
    implements DailyRecommendationLoadOperation {
  const _RustDailyRecommendationLoadOperation(this._handle);

  final bridge.QqMusicDailyRecommendationLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<DailyRecommendationResult> run() async {
    try {
      return mapBridgeDailyRecommendation(await _handle.run());
    } on Object {
      return const DailyRecommendationResult(
        failure: DailyRecommendationFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningDailyRecommendationLoadOperation
    implements DailyRecommendationLoadOperation {
  const _VaultCleaningDailyRecommendationLoadOperation(
    this._inner,
    this._vault,
  );

  final DailyRecommendationLoadOperation _inner;
  final CredentialVault _vault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<DailyRecommendationResult> run() async {
    final result = await _inner.run();
    if (result.failure != DailyRecommendationFailure.credentialRejected) {
      return result;
    }
    try {
      await _vault.delete();
      return result;
    } on Object {
      return const DailyRecommendationResult(
        failure:
            DailyRecommendationFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}

@visibleForTesting
DailyRecommendationResult mapBridgeDailyRecommendation(
  bridge.QqMusicDailyRecommendationLoad result,
) {
  final failure = result.failure;
  final playlist = result.playlist;
  if (failure != null) {
    if (playlist != null) {
      return const DailyRecommendationResult(
        failure: DailyRecommendationFailure.invalidResponse,
      );
    }
    return DailyRecommendationResult(
      failure: mapBridgeDailyRecommendationFailure(failure),
    );
  }
  if (playlist == null) return const DailyRecommendationResult();
  if (playlist.providerId.trim().isEmpty ||
      playlist.opaqueId.trim().isEmpty ||
      playlist.title.trim().isEmpty ||
      (playlist.artworkUri != null && playlist.artworkUri!.trim().isEmpty) ||
      (playlist.trackCount != null && playlist.trackCount! < 0)) {
    return const DailyRecommendationResult(
      failure: DailyRecommendationFailure.invalidResponse,
    );
  }
  return DailyRecommendationResult(
    playlist: RecommendedPlaylistSummary(
      providerId: playlist.providerId,
      opaqueId: playlist.opaqueId,
      title: playlist.title,
      artworkUri: playlist.artworkUri,
      trackCount: playlist.trackCount,
    ),
  );
}

@visibleForTesting
DailyRecommendationFailure mapBridgeDailyRecommendationFailure(
  bridge.QqMusicDailyRecommendationLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicDailyRecommendationLoadFailure.coreUnavailable =>
    DailyRecommendationFailure.coreUnavailable,
  bridge.QqMusicDailyRecommendationLoadFailure.authenticationRequired =>
    DailyRecommendationFailure.authenticationRequired,
  bridge.QqMusicDailyRecommendationLoadFailure.credentialRejected =>
    DailyRecommendationFailure.credentialRejected,
  bridge.QqMusicDailyRecommendationLoadFailure.network =>
    DailyRecommendationFailure.network,
  bridge.QqMusicDailyRecommendationLoadFailure.serviceUnavailable =>
    DailyRecommendationFailure.serviceUnavailable,
  bridge.QqMusicDailyRecommendationLoadFailure.invalidResponse =>
    DailyRecommendationFailure.invalidResponse,
  bridge.QqMusicDailyRecommendationLoadFailure.replaced =>
    DailyRecommendationFailure.replaced,
  bridge.QqMusicDailyRecommendationLoadFailure.cancelled =>
    DailyRecommendationFailure.cancelled,
  bridge.QqMusicDailyRecommendationLoadFailure.alreadyRunning =>
    DailyRecommendationFailure.alreadyRunning,
};
