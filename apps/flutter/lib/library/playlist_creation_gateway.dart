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
  String providerId,
  String name,
);

class RustPlaylistCreationGateway implements PlaylistCreationGateway {
  RustPlaylistCreationGateway({
    this.providerId = 'qq-music',
    CredentialVault? credentialVault,
    PlaylistCreationOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustCreation,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final String providerId;
  final PlaylistCreationOperationFactory _operationFactory;

  @override
  PlaylistCreationOperation beginCreation({required String name}) =>
      _VaultCleaningPlaylistCreationOperation(
        _operationFactory(providerId, name),
        _credentialVault,
      );
}

PlaylistCreationOperation _beginRustCreation(String providerId, String name) =>
    _RustPlaylistCreationOperation(
      bridge.beginPlaylistCreation(providerId: providerId, name: name),
    );

class _RustPlaylistCreationOperation implements PlaylistCreationOperation {
  const _RustPlaylistCreationOperation(this._handle);

  final bridge.PlaylistCreationHandle _handle;

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
  bridge.PlaylistCreationResult result,
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
  bridge.PlaylistCreationFailure failure,
) => switch (failure) {
  bridge.PlaylistCreationFailure.coreUnavailable =>
    PlaylistCreationFailure.coreUnavailable,
  bridge.PlaylistCreationFailure.authenticationRequired =>
    PlaylistCreationFailure.authenticationRequired,
  bridge.PlaylistCreationFailure.credentialRejected =>
    PlaylistCreationFailure.credentialRejected,
  bridge.PlaylistCreationFailure.networkOutcomeUnknown =>
    PlaylistCreationFailure.networkOutcomeUnknown,
  bridge.PlaylistCreationFailure.serviceUnavailable =>
    PlaylistCreationFailure.serviceUnavailable,
  bridge.PlaylistCreationFailure.invalidRequest =>
    PlaylistCreationFailure.invalidRequest,
  bridge.PlaylistCreationFailure.invalidResponseOutcomeUnknown =>
    PlaylistCreationFailure.invalidResponseOutcomeUnknown,
  bridge.PlaylistCreationFailure.replacedOutcomeUnknown =>
    PlaylistCreationFailure.replacedOutcomeUnknown,
  bridge.PlaylistCreationFailure.cancelledOutcomeUnknown =>
    PlaylistCreationFailure.cancelledOutcomeUnknown,
  bridge.PlaylistCreationFailure.alreadyRunning =>
    PlaylistCreationFailure.alreadyRunning,
};
