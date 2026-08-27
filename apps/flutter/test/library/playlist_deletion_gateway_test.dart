import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/playlist_deletion_gateway.dart';
import 'package:flutterustmusic/src/rust/api/playlist_deletion.dart' as bridge;

void main() {
  test('maps only one confirmed deletion', () {
    final result = mapBridgePlaylistDeletion(
      const bridge.QqMusicPlaylistDeletionResult(deleted: true),
    );

    expect(result.deleted, isTrue);
    expect(result.failure, isNull);
  });

  test('maps every typed failure and rejects contradictory results', () {
    final failures = {
      bridge.QqMusicPlaylistDeletionFailure.coreUnavailable:
          PlaylistDeletionFailure.coreUnavailable,
      bridge.QqMusicPlaylistDeletionFailure.authenticationRequired:
          PlaylistDeletionFailure.authenticationRequired,
      bridge.QqMusicPlaylistDeletionFailure.credentialRejected:
          PlaylistDeletionFailure.credentialRejected,
      bridge.QqMusicPlaylistDeletionFailure.networkOutcomeUnknown:
          PlaylistDeletionFailure.networkOutcomeUnknown,
      bridge.QqMusicPlaylistDeletionFailure.serviceUnavailable:
          PlaylistDeletionFailure.serviceUnavailable,
      bridge.QqMusicPlaylistDeletionFailure.invalidRequest:
          PlaylistDeletionFailure.invalidRequest,
      bridge.QqMusicPlaylistDeletionFailure.invalidResponseOutcomeUnknown:
          PlaylistDeletionFailure.invalidResponseOutcomeUnknown,
      bridge.QqMusicPlaylistDeletionFailure.replacedOutcomeUnknown:
          PlaylistDeletionFailure.replacedOutcomeUnknown,
      bridge.QqMusicPlaylistDeletionFailure.cancelledOutcomeUnknown:
          PlaylistDeletionFailure.cancelledOutcomeUnknown,
      bridge.QqMusicPlaylistDeletionFailure.alreadyRunning:
          PlaylistDeletionFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: expected) in failures.entries) {
      final result = mapBridgePlaylistDeletion(
        bridge.QqMusicPlaylistDeletionResult(deleted: false, failure: input),
      );
      expect(result.deleted, isFalse);
      expect(result.failure, expected);
    }

    for (final result in [
      const bridge.QqMusicPlaylistDeletionResult(deleted: false),
      const bridge.QqMusicPlaylistDeletionResult(
        deleted: true,
        failure: bridge.QqMusicPlaylistDeletionFailure.serviceUnavailable,
      ),
    ]) {
      final mapped = mapBridgePlaylistDeletion(result);
      expect(mapped.deleted, isFalse);
      expect(
        mapped.failure,
        PlaylistDeletionFailure.invalidResponseOutcomeUnknown,
      );
    }
  });

  test('forwards exact opaque target and confirmed result', () async {
    late String requestedProvider;
    late String requestedPlaylist;
    final gateway = RustPlaylistDeletionGateway(
      credentialVault: _Vault(),
      operationFactory: (providerId, opaquePlaylistId) {
        requestedProvider = providerId;
        requestedPlaylist = opaquePlaylistId;
        return const _Operation(PlaylistDeletionResult(deleted: true));
      },
    );

    final result = await gateway
        .beginDeletion(
          providerId: 'qq-music',
          opaquePlaylistId: 'owned:7002:902',
        )
        .run();

    expect(requestedProvider, 'qq-music');
    expect(requestedPlaylist, 'owned:7002:902');
    expect(result.deleted, isTrue);
  });

  test('cleans rejected credentials and exposes cleanup failure', () async {
    final deleted = _Vault();
    final rejected = RustPlaylistDeletionGateway(
      credentialVault: deleted,
      operationFactory: (_, _) => const _Operation(
        PlaylistDeletionResult(
          failure: PlaylistDeletionFailure.credentialRejected,
        ),
      ),
    );
    expect(
      (await rejected
              .beginDeletion(
                providerId: 'qq-music',
                opaquePlaylistId: 'owned:7002:902',
              )
              .run())
          .failure,
      PlaylistDeletionFailure.credentialRejected,
    );
    expect(deleted.deleteCount, 1);

    final cleanupFailure = RustPlaylistDeletionGateway(
      credentialVault: _Vault(failDelete: true),
      operationFactory: (_, _) => const _Operation(
        PlaylistDeletionResult(
          failure: PlaylistDeletionFailure.credentialRejected,
        ),
      ),
    );
    expect(
      (await cleanupFailure
              .beginDeletion(
                providerId: 'qq-music',
                opaquePlaylistId: 'owned:7002:902',
              )
              .run())
          .failure,
      PlaylistDeletionFailure.credentialRejectedStorageCleanupFailed,
    );
  });
}

class _Operation implements PlaylistDeletionOperation {
  const _Operation(this.result);

  final PlaylistDeletionResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistDeletionResult> run() async => result;
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
