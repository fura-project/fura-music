import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/remote_mutation_support.dart';
import 'package:flutterustmusic/src/rust/api/track_likes.dart' as bridge;

enum TrackLikeState { liked, notLiked }

enum TrackLikeMutationFailure {
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

class TrackLikeMutationResult {
  const TrackLikeMutationResult({this.confirmedState, this.failure});

  final TrackLikeState? confirmedState;
  final TrackLikeMutationFailure? failure;
}

abstract interface class TrackLikeGateway {
  TrackLikeMutationOperation beginMutation({
    required String providerId,
    required String opaqueTrackId,
    required TrackLikeState desiredState,
  });
}

abstract interface class TrackLikeMutationOperation {
  Future<TrackLikeMutationResult> run();
  bool cancel();
}

typedef TrackLikeMutationOperationFactory = TrackLikeMutationOperation Function(
  String providerId,
  String opaqueTrackId,
  TrackLikeState desiredState,
);

class RustTrackLikeGateway implements TrackLikeGateway {
  RustTrackLikeGateway({
    CredentialVault? credentialVault,
    TrackLikeMutationOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustMutation,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final TrackLikeMutationOperationFactory _operationFactory;

  @override
  TrackLikeMutationOperation beginMutation({
    required String providerId,
    required String opaqueTrackId,
    required TrackLikeState desiredState,
  }) => _VaultCleaningTrackLikeMutationOperation(
    _operationFactory(providerId, opaqueTrackId, desiredState),
    _credentialVault,
  );
}

TrackLikeMutationOperation _beginRustMutation(
  String providerId,
  String opaqueTrackId,
  TrackLikeState desiredState,
) => _RustTrackLikeMutationOperation(
  bridge.beginTrackLikeMutation(
    providerId: providerId,
    opaqueTrackId: opaqueTrackId,
    desiredState: switch (desiredState) {
      TrackLikeState.liked => bridge.TrackLikeState.liked,
      TrackLikeState.notLiked => bridge.TrackLikeState.notLiked,
    },
  ),
);

class _RustTrackLikeMutationOperation implements TrackLikeMutationOperation {
  const _RustTrackLikeMutationOperation(this._handle);

  final bridge.TrackLikeMutationHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<TrackLikeMutationResult> run() async {
    try {
      return mapBridgeTrackLikeMutation(await _handle.run());
    } on Object {
      return const TrackLikeMutationResult(
        failure: TrackLikeMutationFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningTrackLikeMutationOperation
    implements TrackLikeMutationOperation {
  const _VaultCleaningTrackLikeMutationOperation(
    this._inner,
    this._credentialVault,
  );

  final TrackLikeMutationOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<TrackLikeMutationResult> run() async {
    final result = await _inner.run();
    return finishRemoteMutationCredentialRejection(
      result: result,
      credentialRejected:
          result.failure == TrackLikeMutationFailure.credentialRejected,
      credentialVault: _credentialVault,
      cleanupFailureResult: const TrackLikeMutationResult(
        failure:
            TrackLikeMutationFailure.credentialRejectedStorageCleanupFailed,
      ),
    );
  }
}

@visibleForTesting
TrackLikeMutationResult mapBridgeTrackLikeMutation(
  bridge.TrackLikeMutationResult result,
) {
  final failure = result.failure;
  final confirmedState = result.confirmedState;
  if ((failure == null) == (confirmedState == null)) {
    return const TrackLikeMutationResult(
      failure: TrackLikeMutationFailure.invalidResponseOutcomeUnknown,
    );
  }
  if (failure != null) {
    return TrackLikeMutationResult(
      failure: mapBridgeTrackLikeMutationFailure(failure),
    );
  }
  return TrackLikeMutationResult(
    confirmedState: switch (confirmedState!) {
      bridge.TrackLikeState.liked => TrackLikeState.liked,
      bridge.TrackLikeState.notLiked => TrackLikeState.notLiked,
    },
  );
}

@visibleForTesting
TrackLikeMutationFailure mapBridgeTrackLikeMutationFailure(
  bridge.TrackLikeMutationFailure failure,
) => switch (failure) {
  bridge.TrackLikeMutationFailure.coreUnavailable =>
    TrackLikeMutationFailure.coreUnavailable,
  bridge.TrackLikeMutationFailure.authenticationRequired =>
    TrackLikeMutationFailure.authenticationRequired,
  bridge.TrackLikeMutationFailure.credentialRejected =>
    TrackLikeMutationFailure.credentialRejected,
  bridge.TrackLikeMutationFailure.networkOutcomeUnknown =>
    TrackLikeMutationFailure.networkOutcomeUnknown,
  bridge.TrackLikeMutationFailure.serviceUnavailable =>
    TrackLikeMutationFailure.serviceUnavailable,
  bridge.TrackLikeMutationFailure.invalidRequest =>
    TrackLikeMutationFailure.invalidRequest,
  bridge.TrackLikeMutationFailure.invalidResponseOutcomeUnknown =>
    TrackLikeMutationFailure.invalidResponseOutcomeUnknown,
  bridge.TrackLikeMutationFailure.replacedOutcomeUnknown =>
    TrackLikeMutationFailure.replacedOutcomeUnknown,
  bridge.TrackLikeMutationFailure.cancelledOutcomeUnknown =>
    TrackLikeMutationFailure.cancelledOutcomeUnknown,
  bridge.TrackLikeMutationFailure.alreadyRunning =>
    TrackLikeMutationFailure.alreadyRunning,
};
