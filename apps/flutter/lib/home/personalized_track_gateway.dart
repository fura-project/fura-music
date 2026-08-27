import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

enum PersonalizedTracksFailure {
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

class PersonalizedTracksResult {
  const PersonalizedTracksResult({this.tracks = const [], this.failure});

  final List<PlaylistTrackSummary> tracks;
  final PersonalizedTracksFailure? failure;
}

abstract interface class PersonalizedTracksGateway {
  PersonalizedTracksLoadOperation beginLoad();
}

abstract interface class PersonalizedTracksLoadOperation {
  Future<PersonalizedTracksResult> run();
  bool cancel();
}

typedef PersonalizedTracksLoadOperationFactory =
    PersonalizedTracksLoadOperation Function();

class RustPersonalizedTracksGateway implements PersonalizedTracksGateway {
  RustPersonalizedTracksGateway({
    CredentialVault? credentialVault,
    PersonalizedTracksLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final PersonalizedTracksLoadOperationFactory _operationFactory;

  @override
  PersonalizedTracksLoadOperation beginLoad() =>
      _VaultCleaningPersonalizedTracksLoadOperation(
        _operationFactory(),
        _credentialVault,
      );
}

PersonalizedTracksLoadOperation _beginRustLoad() =>
    _RustPersonalizedTracksLoadOperation(
      bridge.beginQqMusicPersonalizedTracksLoad(),
    );

class _RustPersonalizedTracksLoadOperation
    implements PersonalizedTracksLoadOperation {
  const _RustPersonalizedTracksLoadOperation(this._handle);

  final bridge.QqMusicPersonalizedTracksLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<PersonalizedTracksResult> run() async {
    try {
      return mapBridgePersonalizedTracks(await _handle.run());
    } on Object {
      return const PersonalizedTracksResult(
        failure: PersonalizedTracksFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningPersonalizedTracksLoadOperation
    implements PersonalizedTracksLoadOperation {
  const _VaultCleaningPersonalizedTracksLoadOperation(this._inner, this._vault);

  final PersonalizedTracksLoadOperation _inner;
  final CredentialVault _vault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<PersonalizedTracksResult> run() async {
    final result = await _inner.run();
    if (result.failure != PersonalizedTracksFailure.credentialRejected) {
      return result;
    }
    try {
      await _vault.delete();
      return result;
    } on Object {
      return const PersonalizedTracksResult(
        failure:
            PersonalizedTracksFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}

@visibleForTesting
PersonalizedTracksResult mapBridgePersonalizedTracks(
  bridge.QqMusicPersonalizedTracksLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.tracks.isNotEmpty) {
      return const PersonalizedTracksResult(
        failure: PersonalizedTracksFailure.invalidResponse,
      );
    }
    return PersonalizedTracksResult(
      failure: mapBridgePersonalizedTracksFailure(failure),
    );
  }

  final identities = <String>{};
  final tracks = <PlaylistTrackSummary>[];
  for (final track in result.tracks) {
    final mapped = mapBridgeLibraryTrackSummary(track);
    if (mapped == null ||
        !identities.add('${mapped.providerId}\u0000${mapped.opaqueId}')) {
      return const PersonalizedTracksResult(
        failure: PersonalizedTracksFailure.invalidResponse,
      );
    }
    tracks.add(mapped);
  }
  return PersonalizedTracksResult(tracks: List.unmodifiable(tracks));
}

@visibleForTesting
PersonalizedTracksFailure mapBridgePersonalizedTracksFailure(
  bridge.QqMusicPersonalizedTracksLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicPersonalizedTracksLoadFailure.coreUnavailable =>
    PersonalizedTracksFailure.coreUnavailable,
  bridge.QqMusicPersonalizedTracksLoadFailure.authenticationRequired =>
    PersonalizedTracksFailure.authenticationRequired,
  bridge.QqMusicPersonalizedTracksLoadFailure.credentialRejected =>
    PersonalizedTracksFailure.credentialRejected,
  bridge.QqMusicPersonalizedTracksLoadFailure.network =>
    PersonalizedTracksFailure.network,
  bridge.QqMusicPersonalizedTracksLoadFailure.serviceUnavailable =>
    PersonalizedTracksFailure.serviceUnavailable,
  bridge.QqMusicPersonalizedTracksLoadFailure.invalidResponse =>
    PersonalizedTracksFailure.invalidResponse,
  bridge.QqMusicPersonalizedTracksLoadFailure.replaced =>
    PersonalizedTracksFailure.replaced,
  bridge.QqMusicPersonalizedTracksLoadFailure.cancelled =>
    PersonalizedTracksFailure.cancelled,
  bridge.QqMusicPersonalizedTracksLoadFailure.alreadyRunning =>
    PersonalizedTracksFailure.alreadyRunning,
};
