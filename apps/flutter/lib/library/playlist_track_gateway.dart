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
  bridge.beginQqMusicPlaylistTrackMutation(
    providerId: providerId,
    opaquePlaylistId: opaquePlaylistId,
    opaqueTrackId: opaqueTrackId,
    desiredState: switch (desiredState) {
      PlaylistTrackState.present => bridge.QqMusicPlaylistTrackState.present,
      PlaylistTrackState.absent => bridge.QqMusicPlaylistTrackState.absent,
    },
  ),
);

class _RustPlaylistTrackMutationOperation
    implements PlaylistTrackMutationOperation {
  const _RustPlaylistTrackMutationOperation(this._handle);

  final bridge.QqMusicPlaylistTrackMutationHandle _handle;

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
  bridge.QqMusicPlaylistTrackMutationResult result,
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
      bridge.QqMusicPlaylistTrackState.present => PlaylistTrackState.present,
      bridge.QqMusicPlaylistTrackState.absent => PlaylistTrackState.absent,
    },
  );
}

@visibleForTesting
PlaylistTrackMutationFailure mapBridgePlaylistTrackMutationFailure(
  bridge.QqMusicPlaylistTrackMutationFailure failure,
) => switch (failure) {
  bridge.QqMusicPlaylistTrackMutationFailure.coreUnavailable =>
    PlaylistTrackMutationFailure.coreUnavailable,
  bridge.QqMusicPlaylistTrackMutationFailure.authenticationRequired =>
    PlaylistTrackMutationFailure.authenticationRequired,
  bridge.QqMusicPlaylistTrackMutationFailure.credentialRejected =>
    PlaylistTrackMutationFailure.credentialRejected,
  bridge.QqMusicPlaylistTrackMutationFailure.networkOutcomeUnknown =>
    PlaylistTrackMutationFailure.networkOutcomeUnknown,
  bridge.QqMusicPlaylistTrackMutationFailure.serviceUnavailable =>
    PlaylistTrackMutationFailure.serviceUnavailable,
  bridge.QqMusicPlaylistTrackMutationFailure.invalidRequest =>
    PlaylistTrackMutationFailure.invalidRequest,
  bridge.QqMusicPlaylistTrackMutationFailure.invalidResponseOutcomeUnknown =>
    PlaylistTrackMutationFailure.invalidResponseOutcomeUnknown,
  bridge.QqMusicPlaylistTrackMutationFailure.replacedOutcomeUnknown =>
    PlaylistTrackMutationFailure.replacedOutcomeUnknown,
  bridge.QqMusicPlaylistTrackMutationFailure.cancelledOutcomeUnknown =>
    PlaylistTrackMutationFailure.cancelledOutcomeUnknown,
  bridge.QqMusicPlaylistTrackMutationFailure.alreadyRunning =>
    PlaylistTrackMutationFailure.alreadyRunning,
};
