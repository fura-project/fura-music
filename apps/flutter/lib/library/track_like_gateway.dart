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
  bridge.beginQqMusicTrackLikeMutation(
    providerId: providerId,
    opaqueTrackId: opaqueTrackId,
    desiredState: switch (desiredState) {
      TrackLikeState.liked => bridge.QqMusicTrackLikeState.liked,
      TrackLikeState.notLiked => bridge.QqMusicTrackLikeState.notLiked,
    },
  ),
);

class _RustTrackLikeMutationOperation implements TrackLikeMutationOperation {
  const _RustTrackLikeMutationOperation(this._handle);

  final bridge.QqMusicTrackLikeMutationHandle _handle;

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
  bridge.QqMusicTrackLikeMutationResult result,
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
      bridge.QqMusicTrackLikeState.liked => TrackLikeState.liked,
      bridge.QqMusicTrackLikeState.notLiked => TrackLikeState.notLiked,
    },
  );
}

@visibleForTesting
TrackLikeMutationFailure mapBridgeTrackLikeMutationFailure(
  bridge.QqMusicTrackLikeMutationFailure failure,
) => switch (failure) {
  bridge.QqMusicTrackLikeMutationFailure.coreUnavailable =>
    TrackLikeMutationFailure.coreUnavailable,
  bridge.QqMusicTrackLikeMutationFailure.authenticationRequired =>
    TrackLikeMutationFailure.authenticationRequired,
  bridge.QqMusicTrackLikeMutationFailure.credentialRejected =>
    TrackLikeMutationFailure.credentialRejected,
  bridge.QqMusicTrackLikeMutationFailure.networkOutcomeUnknown =>
    TrackLikeMutationFailure.networkOutcomeUnknown,
  bridge.QqMusicTrackLikeMutationFailure.serviceUnavailable =>
    TrackLikeMutationFailure.serviceUnavailable,
  bridge.QqMusicTrackLikeMutationFailure.invalidRequest =>
    TrackLikeMutationFailure.invalidRequest,
  bridge.QqMusicTrackLikeMutationFailure.invalidResponseOutcomeUnknown =>
    TrackLikeMutationFailure.invalidResponseOutcomeUnknown,
  bridge.QqMusicTrackLikeMutationFailure.replacedOutcomeUnknown =>
    TrackLikeMutationFailure.replacedOutcomeUnknown,
  bridge.QqMusicTrackLikeMutationFailure.cancelledOutcomeUnknown =>
    TrackLikeMutationFailure.cancelledOutcomeUnknown,
  bridge.QqMusicTrackLikeMutationFailure.alreadyRunning =>
    TrackLikeMutationFailure.alreadyRunning,
};
