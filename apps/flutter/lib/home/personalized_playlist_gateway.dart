import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

enum PersonalizedPlaylistsFailure {
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

class PersonalizedPlaylistsResult {
  const PersonalizedPlaylistsResult({
    this.playlists = const [],
    this.omittedPlaylistCount = 0,
    this.failure,
  });

  final List<RecommendedPlaylistSummary> playlists;
  final int omittedPlaylistCount;
  final PersonalizedPlaylistsFailure? failure;
}

abstract interface class PersonalizedPlaylistsGateway {
  PersonalizedPlaylistsLoadOperation beginLoad();
}

abstract interface class PersonalizedPlaylistsLoadOperation {
  Future<PersonalizedPlaylistsResult> run();
  bool cancel();
}

typedef PersonalizedPlaylistsLoadOperationFactory =
    PersonalizedPlaylistsLoadOperation Function();

class RustPersonalizedPlaylistsGateway implements PersonalizedPlaylistsGateway {
  RustPersonalizedPlaylistsGateway({
    this.providerId = 'qq-music',
    CredentialVault? credentialVault,
    this.operationFactory,
  }) : _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final String providerId;
  final PersonalizedPlaylistsLoadOperationFactory? operationFactory;

  @override
  PersonalizedPlaylistsLoadOperation beginLoad() =>
      _VaultCleaningPersonalizedPlaylistsLoadOperation(
        operationFactory?.call() ?? _beginRustLoad(providerId),
        _credentialVault,
      );
}

PersonalizedPlaylistsLoadOperation _beginRustLoad(String providerId) =>
    _RustPersonalizedPlaylistsLoadOperation(
      bridge.beginQqMusicPersonalizedPlaylistsLoad(providerId: providerId),
    );

class _RustPersonalizedPlaylistsLoadOperation
    implements PersonalizedPlaylistsLoadOperation {
  const _RustPersonalizedPlaylistsLoadOperation(this._handle);

  final bridge.QqMusicPersonalizedPlaylistsLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<PersonalizedPlaylistsResult> run() async {
    try {
      return mapBridgePersonalizedPlaylists(await _handle.run());
    } on Object {
      return const PersonalizedPlaylistsResult(
        failure: PersonalizedPlaylistsFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningPersonalizedPlaylistsLoadOperation
    implements PersonalizedPlaylistsLoadOperation {
  const _VaultCleaningPersonalizedPlaylistsLoadOperation(
    this._inner,
    this._vault,
  );

  final PersonalizedPlaylistsLoadOperation _inner;
  final CredentialVault _vault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<PersonalizedPlaylistsResult> run() async {
    final result = await _inner.run();
    if (result.failure != PersonalizedPlaylistsFailure.credentialRejected) {
      return result;
    }
    try {
      await _vault.delete();
      return result;
    } on Object {
      return const PersonalizedPlaylistsResult(
        failure:
            PersonalizedPlaylistsFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}

@visibleForTesting
PersonalizedPlaylistsResult mapBridgePersonalizedPlaylists(
  bridge.QqMusicPersonalizedPlaylistsLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.playlists.isNotEmpty || result.omittedPlaylistCount != 0) {
      return const PersonalizedPlaylistsResult(
        failure: PersonalizedPlaylistsFailure.invalidResponse,
      );
    }
    return PersonalizedPlaylistsResult(
      failure: mapBridgePersonalizedPlaylistsFailure(failure),
    );
  }
  if (result.omittedPlaylistCount < 0) {
    return const PersonalizedPlaylistsResult(
      failure: PersonalizedPlaylistsFailure.invalidResponse,
    );
  }

  final seenIdentities = <String>{};
  final playlists = <RecommendedPlaylistSummary>[];
  for (final playlist in result.playlists) {
    final identity = '${playlist.providerId}\u0000${playlist.opaqueId}';
    if (playlist.providerId.trim().isEmpty ||
        playlist.opaqueId.trim().isEmpty ||
        playlist.title.trim().isEmpty ||
        (playlist.artworkUri != null && playlist.artworkUri!.trim().isEmpty) ||
        (playlist.trackCount != null && playlist.trackCount! < 0) ||
        !seenIdentities.add(identity)) {
      return const PersonalizedPlaylistsResult(
        failure: PersonalizedPlaylistsFailure.invalidResponse,
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
  return PersonalizedPlaylistsResult(
    playlists: List.unmodifiable(playlists),
    omittedPlaylistCount: result.omittedPlaylistCount,
  );
}

@visibleForTesting
PersonalizedPlaylistsFailure mapBridgePersonalizedPlaylistsFailure(
  bridge.QqMusicPersonalizedPlaylistsLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicPersonalizedPlaylistsLoadFailure.coreUnavailable =>
    PersonalizedPlaylistsFailure.coreUnavailable,
  bridge.QqMusicPersonalizedPlaylistsLoadFailure.authenticationRequired =>
    PersonalizedPlaylistsFailure.authenticationRequired,
  bridge.QqMusicPersonalizedPlaylistsLoadFailure.credentialRejected =>
    PersonalizedPlaylistsFailure.credentialRejected,
  bridge.QqMusicPersonalizedPlaylistsLoadFailure.network =>
    PersonalizedPlaylistsFailure.network,
  bridge.QqMusicPersonalizedPlaylistsLoadFailure.serviceUnavailable =>
    PersonalizedPlaylistsFailure.serviceUnavailable,
  bridge.QqMusicPersonalizedPlaylistsLoadFailure.invalidResponse =>
    PersonalizedPlaylistsFailure.invalidResponse,
  bridge.QqMusicPersonalizedPlaylistsLoadFailure.replaced =>
    PersonalizedPlaylistsFailure.replaced,
  bridge.QqMusicPersonalizedPlaylistsLoadFailure.cancelled =>
    PersonalizedPlaylistsFailure.cancelled,
  bridge.QqMusicPersonalizedPlaylistsLoadFailure.alreadyRunning =>
    PersonalizedPlaylistsFailure.alreadyRunning,
};
