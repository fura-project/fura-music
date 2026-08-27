import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/playlist_track_gateway.dart';
import 'package:flutterustmusic/src/rust/api/playlist_tracks.dart' as bridge;

void main() {
  test('maps confirmed states and every typed failure', () {
    for (final pair in [
      (bridge.QqMusicPlaylistTrackState.present, PlaylistTrackState.present),
      (bridge.QqMusicPlaylistTrackState.absent, PlaylistTrackState.absent),
    ]) {
      final result = mapBridgePlaylistTrackMutation(
        bridge.QqMusicPlaylistTrackMutationResult(confirmedState: pair.$1),
      );
      expect(result.confirmedState, pair.$2);
      expect(result.failure, isNull);
    }

    final failures = {
      bridge.QqMusicPlaylistTrackMutationFailure.coreUnavailable:
          PlaylistTrackMutationFailure.coreUnavailable,
      bridge.QqMusicPlaylistTrackMutationFailure.authenticationRequired:
          PlaylistTrackMutationFailure.authenticationRequired,
      bridge.QqMusicPlaylistTrackMutationFailure.credentialRejected:
          PlaylistTrackMutationFailure.credentialRejected,
      bridge.QqMusicPlaylistTrackMutationFailure.networkOutcomeUnknown:
          PlaylistTrackMutationFailure.networkOutcomeUnknown,
      bridge.QqMusicPlaylistTrackMutationFailure.serviceUnavailable:
          PlaylistTrackMutationFailure.serviceUnavailable,
      bridge.QqMusicPlaylistTrackMutationFailure.invalidRequest:
          PlaylistTrackMutationFailure.invalidRequest,
      bridge.QqMusicPlaylistTrackMutationFailure.invalidResponseOutcomeUnknown:
          PlaylistTrackMutationFailure.invalidResponseOutcomeUnknown,
      bridge.QqMusicPlaylistTrackMutationFailure.replacedOutcomeUnknown:
          PlaylistTrackMutationFailure.replacedOutcomeUnknown,
      bridge.QqMusicPlaylistTrackMutationFailure.cancelledOutcomeUnknown:
          PlaylistTrackMutationFailure.cancelledOutcomeUnknown,
      bridge.QqMusicPlaylistTrackMutationFailure.alreadyRunning:
          PlaylistTrackMutationFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: expected) in failures.entries) {
      final result = mapBridgePlaylistTrackMutation(
        bridge.QqMusicPlaylistTrackMutationResult(failure: input),
      );
      expect(result.confirmedState, isNull);
      expect(result.failure, expected);
    }
  });

  test('rejects contradictory or empty bridge results', () {
    for (final result in [
      const bridge.QqMusicPlaylistTrackMutationResult(),
      const bridge.QqMusicPlaylistTrackMutationResult(
        confirmedState: bridge.QqMusicPlaylistTrackState.present,
        failure: bridge.QqMusicPlaylistTrackMutationFailure.serviceUnavailable,
      ),
    ]) {
      expect(
        mapBridgePlaylistTrackMutation(result).failure,
        PlaylistTrackMutationFailure.invalidResponseOutcomeUnknown,
      );
    }
  });

  test('forwards opaque playlist, Track, and desired state', () async {
    late String providerId;
    late String opaquePlaylistId;
    late String opaqueTrackId;
    late PlaylistTrackState desiredState;
    final gateway = RustPlaylistTrackGateway(
      credentialVault: _Vault(),
      operationFactory: (provider, playlist, track, desired) {
        providerId = provider;
        opaquePlaylistId = playlist;
        opaqueTrackId = track;
        desiredState = desired;
        return const _Operation(
          PlaylistTrackMutationResult(
            confirmedState: PlaylistTrackState.absent,
          ),
        );
      },
    );

    final result = await gateway
        .beginMutation(
          providerId: 'qq-music',
          opaquePlaylistId: 'owned:7002:902',
          opaqueTrackId: 'track:41001:7:fixtureTrackMid:fixtureFileMid',
          desiredState: PlaylistTrackState.absent,
        )
        .run();

    expect(providerId, 'qq-music');
    expect(opaquePlaylistId, 'owned:7002:902');
    expect(opaqueTrackId, 'track:41001:7:fixtureTrackMid:fixtureFileMid');
    expect(desiredState, PlaylistTrackState.absent);
    expect(result.confirmedState, PlaylistTrackState.absent);
  });

  test('cleans rejected credentials and exposes cleanup failure', () async {
    final deleted = _Vault();
    final rejected = RustPlaylistTrackGateway(
      credentialVault: deleted,
      operationFactory: (_, _, _, _) => const _Operation(
        PlaylistTrackMutationResult(
          failure: PlaylistTrackMutationFailure.credentialRejected,
        ),
      ),
    );
    expect(
      (await rejected
              .beginMutation(
                providerId: 'qq-music',
                opaquePlaylistId: 'owned:7002:902',
                opaqueTrackId: 'opaque',
                desiredState: PlaylistTrackState.present,
              )
              .run())
          .failure,
      PlaylistTrackMutationFailure.credentialRejected,
    );
    expect(deleted.deleteCount, 1);

    final cleanupFailure = RustPlaylistTrackGateway(
      credentialVault: _Vault(failDelete: true),
      operationFactory: (_, _, _, _) => const _Operation(
        PlaylistTrackMutationResult(
          failure: PlaylistTrackMutationFailure.credentialRejected,
        ),
      ),
    );
    expect(
      (await cleanupFailure
              .beginMutation(
                providerId: 'qq-music',
                opaquePlaylistId: 'owned:7002:902',
                opaqueTrackId: 'opaque',
                desiredState: PlaylistTrackState.present,
              )
              .run())
          .failure,
      PlaylistTrackMutationFailure.credentialRejectedStorageCleanupFailed,
    );
  });
}

class _Operation implements PlaylistTrackMutationOperation {
  const _Operation(this.result);

  final PlaylistTrackMutationResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackMutationResult> run() async => result;
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
