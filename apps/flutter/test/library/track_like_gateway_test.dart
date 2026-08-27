import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/track_like_gateway.dart';
import 'package:flutterustmusic/src/rust/api/track_likes.dart' as bridge;

void main() {
  test('maps confirmed states and every typed failure', () {
    for (final pair in [
      (bridge.QqMusicTrackLikeState.liked, TrackLikeState.liked),
      (bridge.QqMusicTrackLikeState.notLiked, TrackLikeState.notLiked),
    ]) {
      final result = mapBridgeTrackLikeMutation(
        bridge.QqMusicTrackLikeMutationResult(confirmedState: pair.$1),
      );
      expect(result.confirmedState, pair.$2);
      expect(result.failure, isNull);
    }

    final failures = {
      bridge.QqMusicTrackLikeMutationFailure.coreUnavailable:
          TrackLikeMutationFailure.coreUnavailable,
      bridge.QqMusicTrackLikeMutationFailure.authenticationRequired:
          TrackLikeMutationFailure.authenticationRequired,
      bridge.QqMusicTrackLikeMutationFailure.credentialRejected:
          TrackLikeMutationFailure.credentialRejected,
      bridge.QqMusicTrackLikeMutationFailure.networkOutcomeUnknown:
          TrackLikeMutationFailure.networkOutcomeUnknown,
      bridge.QqMusicTrackLikeMutationFailure.serviceUnavailable:
          TrackLikeMutationFailure.serviceUnavailable,
      bridge.QqMusicTrackLikeMutationFailure.invalidRequest:
          TrackLikeMutationFailure.invalidRequest,
      bridge.QqMusicTrackLikeMutationFailure.invalidResponseOutcomeUnknown:
          TrackLikeMutationFailure.invalidResponseOutcomeUnknown,
      bridge.QqMusicTrackLikeMutationFailure.replacedOutcomeUnknown:
          TrackLikeMutationFailure.replacedOutcomeUnknown,
      bridge.QqMusicTrackLikeMutationFailure.cancelledOutcomeUnknown:
          TrackLikeMutationFailure.cancelledOutcomeUnknown,
      bridge.QqMusicTrackLikeMutationFailure.alreadyRunning:
          TrackLikeMutationFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: expected) in failures.entries) {
      final result = mapBridgeTrackLikeMutation(
        bridge.QqMusicTrackLikeMutationResult(failure: input),
      );
      expect(result.confirmedState, isNull);
      expect(result.failure, expected);
    }
  });

  test('rejects contradictory or empty bridge results', () {
    for (final result in [
      const bridge.QqMusicTrackLikeMutationResult(),
      const bridge.QqMusicTrackLikeMutationResult(
        confirmedState: bridge.QqMusicTrackLikeState.liked,
        failure: bridge.QqMusicTrackLikeMutationFailure.serviceUnavailable,
      ),
    ]) {
      expect(
        mapBridgeTrackLikeMutation(result).failure,
        TrackLikeMutationFailure.invalidResponseOutcomeUnknown,
      );
    }
  });

  test('forwards opaque identity and desired state', () async {
    late String providerId;
    late String opaqueTrackId;
    late TrackLikeState desiredState;
    final gateway = RustTrackLikeGateway(
      credentialVault: _Vault(),
      operationFactory: (provider, opaque, desired) {
        providerId = provider;
        opaqueTrackId = opaque;
        desiredState = desired;
        return const _Operation(
          TrackLikeMutationResult(confirmedState: TrackLikeState.notLiked),
        );
      },
    );

    final result = await gateway
        .beginMutation(
          providerId: 'qq-music',
          opaqueTrackId: 'track:41001:7:fixtureTrackMid:fixtureFileMid',
          desiredState: TrackLikeState.notLiked,
        )
        .run();

    expect(providerId, 'qq-music');
    expect(opaqueTrackId, 'track:41001:7:fixtureTrackMid:fixtureFileMid');
    expect(desiredState, TrackLikeState.notLiked);
    expect(result.confirmedState, TrackLikeState.notLiked);
  });

  test('cleans rejected credentials and exposes cleanup failure', () async {
    final deleted = _Vault();
    final rejected = RustTrackLikeGateway(
      credentialVault: deleted,
      operationFactory: (_, _, _) => const _Operation(
        TrackLikeMutationResult(
          failure: TrackLikeMutationFailure.credentialRejected,
        ),
      ),
    );
    expect(
      (await rejected
              .beginMutation(
                providerId: 'qq-music',
                opaqueTrackId: 'opaque',
                desiredState: TrackLikeState.liked,
              )
              .run())
          .failure,
      TrackLikeMutationFailure.credentialRejected,
    );
    expect(deleted.deleteCount, 1);

    final cleanupFailure = RustTrackLikeGateway(
      credentialVault: _Vault(failDelete: true),
      operationFactory: (_, _, _) => const _Operation(
        TrackLikeMutationResult(
          failure: TrackLikeMutationFailure.credentialRejected,
        ),
      ),
    );
    expect(
      (await cleanupFailure
              .beginMutation(
                providerId: 'qq-music',
                opaqueTrackId: 'opaque',
                desiredState: TrackLikeState.liked,
              )
              .run())
          .failure,
      TrackLikeMutationFailure.credentialRejectedStorageCleanupFailed,
    );
  });
}

class _Operation implements TrackLikeMutationOperation {
  const _Operation(this.result);

  final TrackLikeMutationResult result;

  @override
  bool cancel() => true;

  @override
  Future<TrackLikeMutationResult> run() async => result;
}

class _Vault implements CredentialVault {
  _Vault({this.failDelete = false});

  final bool failDelete;
  int deleteCount = 0;

  @override
  Future<void> delete() async {
    deleteCount += 1;
    if (failDelete) {
      throw StateError('synthetic cleanup failure');
    }
  }

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List document) async {}
}
