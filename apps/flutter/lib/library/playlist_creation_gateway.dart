import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/remote_mutation_support.dart';
import 'package:flutterustmusic/src/rust/api/playlist_creation.dart' as bridge;

enum PlaylistCreationFailure {
  coreUnavailable,
  authenticationRequired,
  credentialRejected,
  credentialRejectedStorageCleanupFailed,
  networkOutcomeUnknown,
  serviceUnavailable,
  invalidRequest,
  invalidResponseOutcomeUnknown,
  replacedOutcomeUnknown,
  cancelledOutcomeUnknown,
  alreadyRunning,
}

class PlaylistCreationResult {
  const PlaylistCreationResult({this.createdPlaylist, this.failure});

  final UserPlaylistSummary? createdPlaylist;
  final PlaylistCreationFailure? failure;
}

abstract interface class PlaylistCreationGateway {
  PlaylistCreationOperation beginCreation({required String name});
}

abstract interface class PlaylistCreationOperation {
  Future<PlaylistCreationResult> run();
  bool cancel();
}

typedef PlaylistCreationOperationFactory = PlaylistCreationOperation Function(
  String name,
);

class RustPlaylistCreationGateway implements PlaylistCreationGateway {
  RustPlaylistCreationGateway({
    CredentialVault? credentialVault,
    PlaylistCreationOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustCreation,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final PlaylistCreationOperationFactory _operationFactory;

  @override
  PlaylistCreationOperation beginCreation({required String name}) =>
      _VaultCleaningPlaylistCreationOperation(
        _operationFactory(name),
        _credentialVault,
      );
}

PlaylistCreationOperation _beginRustCreation(String name) =>
    _RustPlaylistCreationOperation(
      bridge.beginQqMusicPlaylistCreation(name: name),
    );

class _RustPlaylistCreationOperation implements PlaylistCreationOperation {
  const _RustPlaylistCreationOperation(this._handle);

  final bridge.QqMusicPlaylistCreationHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<PlaylistCreationResult> run() async {
    try {
      return mapBridgePlaylistCreation(await _handle.run());
    } on Object {
      return const PlaylistCreationResult(
        failure: PlaylistCreationFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningPlaylistCreationOperation
    implements PlaylistCreationOperation {
  const _VaultCleaningPlaylistCreationOperation(
    this._inner,
    this._credentialVault,
  );

  final PlaylistCreationOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<PlaylistCreationResult> run() async {
    final result = await _inner.run();
    return finishRemoteMutationCredentialRejection(
      result: result,
      credentialRejected:
          result.failure == PlaylistCreationFailure.credentialRejected,
      credentialVault: _credentialVault,
      cleanupFailureResult: const PlaylistCreationResult(
        failure: PlaylistCreationFailure.credentialRejectedStorageCleanupFailed,
      ),
    );
  }
}

@visibleForTesting
PlaylistCreationResult mapBridgePlaylistCreation(
  bridge.QqMusicPlaylistCreationResult result,
) {
  final failure = result.failure;
  final created = result.createdPlaylist;
  if ((failure == null) == (created == null)) {
    return const PlaylistCreationResult(
      failure: PlaylistCreationFailure.invalidResponseOutcomeUnknown,
    );
  }
  if (failure != null) {
    return PlaylistCreationResult(
      failure: mapBridgePlaylistCreationFailure(failure),
    );
  }
  return PlaylistCreationResult(
    createdPlaylist: UserPlaylistSummary(
      providerId: created!.providerId,
      opaqueId: created.opaqueId,
      title: created.title,
      artworkUri: created.artworkUri,
      trackCount: created.trackCount,
      ownership: UserPlaylistOwnership.owned,
    ),
  );
}

@visibleForTesting
PlaylistCreationFailure mapBridgePlaylistCreationFailure(
  bridge.QqMusicPlaylistCreationFailure failure,
) => switch (failure) {
  bridge.QqMusicPlaylistCreationFailure.coreUnavailable =>
    PlaylistCreationFailure.coreUnavailable,
  bridge.QqMusicPlaylistCreationFailure.authenticationRequired =>
    PlaylistCreationFailure.authenticationRequired,
  bridge.QqMusicPlaylistCreationFailure.credentialRejected =>
    PlaylistCreationFailure.credentialRejected,
  bridge.QqMusicPlaylistCreationFailure.networkOutcomeUnknown =>
    PlaylistCreationFailure.networkOutcomeUnknown,
  bridge.QqMusicPlaylistCreationFailure.serviceUnavailable =>
    PlaylistCreationFailure.serviceUnavailable,
  bridge.QqMusicPlaylistCreationFailure.invalidRequest =>
    PlaylistCreationFailure.invalidRequest,
  bridge.QqMusicPlaylistCreationFailure.invalidResponseOutcomeUnknown =>
    PlaylistCreationFailure.invalidResponseOutcomeUnknown,
  bridge.QqMusicPlaylistCreationFailure.replacedOutcomeUnknown =>
    PlaylistCreationFailure.replacedOutcomeUnknown,
  bridge.QqMusicPlaylistCreationFailure.cancelledOutcomeUnknown =>
    PlaylistCreationFailure.cancelledOutcomeUnknown,
  bridge.QqMusicPlaylistCreationFailure.alreadyRunning =>
    PlaylistCreationFailure.alreadyRunning,
};
