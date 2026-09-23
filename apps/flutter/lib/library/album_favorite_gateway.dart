import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/remote_mutation_support.dart';
import 'package:flutterustmusic/src/rust/api/album_favorites.dart' as bridge;

enum AlbumFavoriteState { favorite, notFavorite }

enum AlbumFavoriteMutationFailure {
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

class AlbumFavoriteMutationResult {
  const AlbumFavoriteMutationResult({this.confirmedState, this.failure});

  final AlbumFavoriteState? confirmedState;
  final AlbumFavoriteMutationFailure? failure;
}

abstract interface class AlbumFavoriteGateway {
  AlbumFavoriteMutationOperation beginMutation({
    required String providerId,
    required String opaqueAlbumId,
    required AlbumFavoriteState desiredState,
  });
}

abstract interface class AlbumFavoriteMutationOperation {
  Future<AlbumFavoriteMutationResult> run();
  bool cancel();
}

typedef AlbumFavoriteMutationOperationFactory =
    AlbumFavoriteMutationOperation Function(
      String providerId,
      String opaqueAlbumId,
      AlbumFavoriteState desiredState,
    );

class RustAlbumFavoriteGateway implements AlbumFavoriteGateway {
  RustAlbumFavoriteGateway({
    CredentialVault? credentialVault,
    AlbumFavoriteMutationOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustMutation,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final AlbumFavoriteMutationOperationFactory _operationFactory;

  @override
  AlbumFavoriteMutationOperation beginMutation({
    required String providerId,
    required String opaqueAlbumId,
    required AlbumFavoriteState desiredState,
  }) => _VaultCleaningAlbumFavoriteMutationOperation(
    _operationFactory(providerId, opaqueAlbumId, desiredState),
    _credentialVault,
  );
}

AlbumFavoriteMutationOperation _beginRustMutation(
  String providerId,
  String opaqueAlbumId,
  AlbumFavoriteState desiredState,
) => _RustAlbumFavoriteMutationOperation(
  bridge.beginAlbumFavoriteMutation(
    providerId: providerId,
    opaqueAlbumId: opaqueAlbumId,
    desiredState: switch (desiredState) {
      AlbumFavoriteState.favorite => bridge.AlbumFavoriteState.favorite,
      AlbumFavoriteState.notFavorite => bridge.AlbumFavoriteState.notFavorite,
    },
  ),
);

class _RustAlbumFavoriteMutationOperation
    implements AlbumFavoriteMutationOperation {
  const _RustAlbumFavoriteMutationOperation(this._handle);

  final bridge.AlbumFavoriteMutationHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<AlbumFavoriteMutationResult> run() async {
    try {
      return mapBridgeAlbumFavoriteMutation(await _handle.run());
    } on Object {
      return const AlbumFavoriteMutationResult(
        failure: AlbumFavoriteMutationFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningAlbumFavoriteMutationOperation
    implements AlbumFavoriteMutationOperation {
  const _VaultCleaningAlbumFavoriteMutationOperation(
    this._inner,
    this._credentialVault,
  );

  final AlbumFavoriteMutationOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<AlbumFavoriteMutationResult> run() async {
    final result = await _inner.run();
    return finishRemoteMutationCredentialRejection(
      result: result,
      credentialRejected:
          result.failure == AlbumFavoriteMutationFailure.credentialRejected,
      credentialVault: _credentialVault,
      cleanupFailureResult: const AlbumFavoriteMutationResult(
        failure:
            AlbumFavoriteMutationFailure.credentialRejectedStorageCleanupFailed,
      ),
    );
  }
}

@visibleForTesting
AlbumFavoriteMutationResult mapBridgeAlbumFavoriteMutation(
  bridge.AlbumFavoriteMutationResult result,
) {
  final failure = result.failure;
  final confirmedState = result.confirmedState;
  if ((failure == null) == (confirmedState == null)) {
    return const AlbumFavoriteMutationResult(
      failure: AlbumFavoriteMutationFailure.invalidResponseOutcomeUnknown,
    );
  }
  if (failure != null) {
    return AlbumFavoriteMutationResult(
      failure: mapBridgeAlbumFavoriteMutationFailure(failure),
    );
  }
  return AlbumFavoriteMutationResult(
    confirmedState: switch (confirmedState!) {
      bridge.AlbumFavoriteState.favorite => AlbumFavoriteState.favorite,
      bridge.AlbumFavoriteState.notFavorite => AlbumFavoriteState.notFavorite,
    },
  );
}

@visibleForTesting
AlbumFavoriteMutationFailure mapBridgeAlbumFavoriteMutationFailure(
  bridge.AlbumFavoriteMutationFailure failure,
) => switch (failure) {
  bridge.AlbumFavoriteMutationFailure.coreUnavailable =>
    AlbumFavoriteMutationFailure.coreUnavailable,
  bridge.AlbumFavoriteMutationFailure.authenticationRequired =>
    AlbumFavoriteMutationFailure.authenticationRequired,
  bridge.AlbumFavoriteMutationFailure.credentialRejected =>
    AlbumFavoriteMutationFailure.credentialRejected,
  bridge.AlbumFavoriteMutationFailure.networkOutcomeUnknown =>
    AlbumFavoriteMutationFailure.networkOutcomeUnknown,
  bridge.AlbumFavoriteMutationFailure.serviceUnavailable =>
    AlbumFavoriteMutationFailure.serviceUnavailable,
  bridge.AlbumFavoriteMutationFailure.invalidRequest =>
    AlbumFavoriteMutationFailure.invalidRequest,
  bridge.AlbumFavoriteMutationFailure.invalidResponseOutcomeUnknown =>
    AlbumFavoriteMutationFailure.invalidResponseOutcomeUnknown,
  bridge.AlbumFavoriteMutationFailure.replacedOutcomeUnknown =>
    AlbumFavoriteMutationFailure.replacedOutcomeUnknown,
  bridge.AlbumFavoriteMutationFailure.cancelledOutcomeUnknown =>
    AlbumFavoriteMutationFailure.cancelledOutcomeUnknown,
  bridge.AlbumFavoriteMutationFailure.alreadyRunning =>
    AlbumFavoriteMutationFailure.alreadyRunning,
};
