import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/remote_mutation_support.dart';
import 'package:flutterustmusic/src/rust/api/playlist_tracks.dart' as bridge;

enum PlaylistTrackState { present, absent }

enum PlaylistTrackMutationFailure {
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

class PlaylistTrackMutationResult {
  const PlaylistTrackMutationResult({this.confirmedState, this.failure});

  final PlaylistTrackState? confirmedState;
  final PlaylistTrackMutationFailure? failure;
}

abstract interface class PlaylistTrackGateway {
  PlaylistTrackMutationOperation beginMutation({
    required String providerId,
    required String opaquePlaylistId,
    required String opaqueTrackId,
    required PlaylistTrackState desiredState,
  });
}

abstract interface class PlaylistTrackMutationOperation {
  Future<PlaylistTrackMutationResult> run();
  bool cancel();
}

typedef PlaylistTrackMutationOperationFactory =
    PlaylistTrackMutationOperation Function(
      String providerId,
      String opaquePlaylistId,
      String opaqueTrackId,
      PlaylistTrackState desiredState,
    );

class RustPlaylistTrackGateway implements PlaylistTrackGateway {
  RustPlaylistTrackGateway({
    CredentialVault? credentialVault,
    PlaylistTrackMutationOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustMutation,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final PlaylistTrackMutationOperationFactory _operationFactory;

  @override
  PlaylistTrackMutationOperation beginMutation({
    required String providerId,
    required String opaquePlaylistId,
    required String opaqueTrackId,
    required PlaylistTrackState desiredState,
  }) => _VaultCleaningPlaylistTrackMutationOperation(
    _operationFactory(
      providerId,
      opaquePlaylistId,
      opaqueTrackId,
      desiredState,
    ),
    _credentialVault,
  );
}

PlaylistTrackMutationOperation _beginRustMutation(
  String providerId,
  String opaquePlaylistId,
  String opaqueTrackId,
  PlaylistTrackState desiredState,
) => _RustPlaylistTrackMutationOperation(
  bridge.beginPlaylistTrackMutation(
    providerId: providerId,
    opaquePlaylistId: opaquePlaylistId,
    opaqueTrackId: opaqueTrackId,
    desiredState: switch (desiredState) {
      PlaylistTrackState.present => bridge.PlaylistTrackState.present,
      PlaylistTrackState.absent => bridge.PlaylistTrackState.absent,
    },
  ),
);

class _RustPlaylistTrackMutationOperation
    implements PlaylistTrackMutationOperation {
  const _RustPlaylistTrackMutationOperation(this._handle);

  final bridge.PlaylistTrackMutationHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<PlaylistTrackMutationResult> run() async {
    try {
      return mapBridgePlaylistTrackMutation(await _handle.run());
    } on Object {
      return const PlaylistTrackMutationResult(
        failure: PlaylistTrackMutationFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningPlaylistTrackMutationOperation
    implements PlaylistTrackMutationOperation {
  const _VaultCleaningPlaylistTrackMutationOperation(
    this._inner,
    this._credentialVault,
  );

  final PlaylistTrackMutationOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<PlaylistTrackMutationResult> run() async {
    final result = await _inner.run();
    return finishRemoteMutationCredentialRejection(
      result: result,
      credentialRejected:
          result.failure == PlaylistTrackMutationFailure.credentialRejected,
      credentialVault: _credentialVault,
      cleanupFailureResult: const PlaylistTrackMutationResult(
        failure:
            PlaylistTrackMutationFailure.credentialRejectedStorageCleanupFailed,
      ),
    );
  }
}

@visibleForTesting
PlaylistTrackMutationResult mapBridgePlaylistTrackMutation(
  bridge.PlaylistTrackMutationResult result,
) {
  final failure = result.failure;
  final confirmedState = result.confirmedState;
  if ((failure == null) == (confirmedState == null)) {
    return const PlaylistTrackMutationResult(
      failure: PlaylistTrackMutationFailure.invalidResponseOutcomeUnknown,
    );
  }
  if (failure != null) {
    return PlaylistTrackMutationResult(
      failure: mapBridgePlaylistTrackMutationFailure(failure),
    );
  }
  return PlaylistTrackMutationResult(
    confirmedState: switch (confirmedState!) {
      bridge.PlaylistTrackState.present => PlaylistTrackState.present,
      bridge.PlaylistTrackState.absent => PlaylistTrackState.absent,
    },
  );
}

@visibleForTesting
PlaylistTrackMutationFailure mapBridgePlaylistTrackMutationFailure(
  bridge.PlaylistTrackMutationFailure failure,
) => switch (failure) {
  bridge.PlaylistTrackMutationFailure.coreUnavailable =>
    PlaylistTrackMutationFailure.coreUnavailable,
  bridge.PlaylistTrackMutationFailure.authenticationRequired =>
    PlaylistTrackMutationFailure.authenticationRequired,
  bridge.PlaylistTrackMutationFailure.credentialRejected =>
    PlaylistTrackMutationFailure.credentialRejected,
  bridge.PlaylistTrackMutationFailure.networkOutcomeUnknown =>
    PlaylistTrackMutationFailure.networkOutcomeUnknown,
  bridge.PlaylistTrackMutationFailure.serviceUnavailable =>
    PlaylistTrackMutationFailure.serviceUnavailable,
  bridge.PlaylistTrackMutationFailure.invalidRequest =>
    PlaylistTrackMutationFailure.invalidRequest,
  bridge.PlaylistTrackMutationFailure.invalidResponseOutcomeUnknown =>
    PlaylistTrackMutationFailure.invalidResponseOutcomeUnknown,
  bridge.PlaylistTrackMutationFailure.replacedOutcomeUnknown =>
    PlaylistTrackMutationFailure.replacedOutcomeUnknown,
  bridge.PlaylistTrackMutationFailure.cancelledOutcomeUnknown =>
    PlaylistTrackMutationFailure.cancelledOutcomeUnknown,
  bridge.PlaylistTrackMutationFailure.alreadyRunning =>
    PlaylistTrackMutationFailure.alreadyRunning,
};
