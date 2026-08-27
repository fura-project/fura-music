import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/remote_mutation_support.dart';
import 'package:flutterustmusic/src/rust/api/playlist_deletion.dart' as bridge;

enum PlaylistDeletionFailure {
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

class PlaylistDeletionResult {
  const PlaylistDeletionResult({this.deleted = false, this.failure});

  final bool deleted;
  final PlaylistDeletionFailure? failure;
}

abstract interface class PlaylistDeletionGateway {
  PlaylistDeletionOperation beginDeletion({
    required String providerId,
    required String opaquePlaylistId,
  });
}

abstract interface class PlaylistDeletionOperation {
  Future<PlaylistDeletionResult> run();
  bool cancel();
}

typedef PlaylistDeletionOperationFactory = PlaylistDeletionOperation Function(
  String providerId,
  String opaquePlaylistId,
);

class RustPlaylistDeletionGateway implements PlaylistDeletionGateway {
  RustPlaylistDeletionGateway({
    CredentialVault? credentialVault,
    PlaylistDeletionOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustDeletion,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final PlaylistDeletionOperationFactory _operationFactory;

  @override
  PlaylistDeletionOperation beginDeletion({
    required String providerId,
    required String opaquePlaylistId,
  }) => _VaultCleaningPlaylistDeletionOperation(
    _operationFactory(providerId, opaquePlaylistId),
    _credentialVault,
  );
}

PlaylistDeletionOperation _beginRustDeletion(
  String providerId,
  String opaquePlaylistId,
) => _RustPlaylistDeletionOperation(
  bridge.beginQqMusicPlaylistDeletion(
    providerId: providerId,
    opaquePlaylistId: opaquePlaylistId,
  ),
);

class _RustPlaylistDeletionOperation implements PlaylistDeletionOperation {
  const _RustPlaylistDeletionOperation(this._handle);

  final bridge.QqMusicPlaylistDeletionHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<PlaylistDeletionResult> run() async {
    try {
      return mapBridgePlaylistDeletion(await _handle.run());
    } on Object {
      return const PlaylistDeletionResult(
        failure: PlaylistDeletionFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningPlaylistDeletionOperation
    implements PlaylistDeletionOperation {
  const _VaultCleaningPlaylistDeletionOperation(
    this._inner,
    this._credentialVault,
  );

  final PlaylistDeletionOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<PlaylistDeletionResult> run() async {
    final result = await _inner.run();
    return finishRemoteMutationCredentialRejection(
      result: result,
      credentialRejected:
          result.failure == PlaylistDeletionFailure.credentialRejected,
      credentialVault: _credentialVault,
      cleanupFailureResult: const PlaylistDeletionResult(
        failure: PlaylistDeletionFailure.credentialRejectedStorageCleanupFailed,
      ),
    );
  }
}

@visibleForTesting
PlaylistDeletionResult mapBridgePlaylistDeletion(
  bridge.QqMusicPlaylistDeletionResult result,
) {
  final failure = result.failure;
  if (result.deleted == (failure != null)) {
    return const PlaylistDeletionResult(
      failure: PlaylistDeletionFailure.invalidResponseOutcomeUnknown,
    );
  }
  if (failure != null) {
    return PlaylistDeletionResult(
      failure: mapBridgePlaylistDeletionFailure(failure),
    );
  }
  return const PlaylistDeletionResult(deleted: true);
}

@visibleForTesting
PlaylistDeletionFailure mapBridgePlaylistDeletionFailure(
  bridge.QqMusicPlaylistDeletionFailure failure,
) => switch (failure) {
  bridge.QqMusicPlaylistDeletionFailure.coreUnavailable =>
    PlaylistDeletionFailure.coreUnavailable,
  bridge.QqMusicPlaylistDeletionFailure.authenticationRequired =>
    PlaylistDeletionFailure.authenticationRequired,
  bridge.QqMusicPlaylistDeletionFailure.credentialRejected =>
    PlaylistDeletionFailure.credentialRejected,
  bridge.QqMusicPlaylistDeletionFailure.networkOutcomeUnknown =>
    PlaylistDeletionFailure.networkOutcomeUnknown,
  bridge.QqMusicPlaylistDeletionFailure.serviceUnavailable =>
    PlaylistDeletionFailure.serviceUnavailable,
  bridge.QqMusicPlaylistDeletionFailure.invalidRequest =>
    PlaylistDeletionFailure.invalidRequest,
  bridge.QqMusicPlaylistDeletionFailure.invalidResponseOutcomeUnknown =>
    PlaylistDeletionFailure.invalidResponseOutcomeUnknown,
  bridge.QqMusicPlaylistDeletionFailure.replacedOutcomeUnknown =>
    PlaylistDeletionFailure.replacedOutcomeUnknown,
  bridge.QqMusicPlaylistDeletionFailure.cancelledOutcomeUnknown =>
    PlaylistDeletionFailure.cancelledOutcomeUnknown,
  bridge.QqMusicPlaylistDeletionFailure.alreadyRunning =>
    PlaylistDeletionFailure.alreadyRunning,
};
