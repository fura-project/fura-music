import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_creation_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as library_bridge;
import 'package:flutterustmusic/src/rust/api/playlist_creation.dart' as bridge;

void main() {
  test('maps one confirmed created playlist', () {
    final result = mapBridgePlaylistCreation(
      const bridge.QqMusicPlaylistCreationResult(
        createdPlaylist: library_bridge.LibraryPlaylistSummary(
          providerId: 'qq-music',
          opaqueId: 'owned:7002:902',
          title: 'Server playlist',
          trackCount: 0,
        ),
      ),
    );

    expect(result.failure, isNull);
    expect(result.createdPlaylist?.providerId, 'qq-music');
    expect(result.createdPlaylist?.opaqueId, 'owned:7002:902');
    expect(result.createdPlaylist?.title, 'Server playlist');
    expect(result.createdPlaylist?.trackCount, 0);
  });

  test('maps every typed failure and rejects contradictory results', () {
    final failures = {
      bridge.QqMusicPlaylistCreationFailure.coreUnavailable:
          PlaylistCreationFailure.coreUnavailable,
      bridge.QqMusicPlaylistCreationFailure.authenticationRequired:
          PlaylistCreationFailure.authenticationRequired,
      bridge.QqMusicPlaylistCreationFailure.credentialRejected:
          PlaylistCreationFailure.credentialRejected,
      bridge.QqMusicPlaylistCreationFailure.networkOutcomeUnknown:
          PlaylistCreationFailure.networkOutcomeUnknown,
      bridge.QqMusicPlaylistCreationFailure.serviceUnavailable:
          PlaylistCreationFailure.serviceUnavailable,
      bridge.QqMusicPlaylistCreationFailure.invalidRequest:
          PlaylistCreationFailure.invalidRequest,
      bridge.QqMusicPlaylistCreationFailure.invalidResponseOutcomeUnknown:
          PlaylistCreationFailure.invalidResponseOutcomeUnknown,
      bridge.QqMusicPlaylistCreationFailure.replacedOutcomeUnknown:
          PlaylistCreationFailure.replacedOutcomeUnknown,
      bridge.QqMusicPlaylistCreationFailure.cancelledOutcomeUnknown:
          PlaylistCreationFailure.cancelledOutcomeUnknown,
      bridge.QqMusicPlaylistCreationFailure.alreadyRunning:
          PlaylistCreationFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: expected) in failures.entries) {
      final result = mapBridgePlaylistCreation(
        bridge.QqMusicPlaylistCreationResult(failure: input),
      );
      expect(result.createdPlaylist, isNull);
      expect(result.failure, expected);
    }

    for (final result in [
      const bridge.QqMusicPlaylistCreationResult(),
      const bridge.QqMusicPlaylistCreationResult(
        createdPlaylist: library_bridge.LibraryPlaylistSummary(
          providerId: 'qq-music',
          opaqueId: 'owned:7002:902',
          title: 'Server playlist',
        ),
        failure: bridge.QqMusicPlaylistCreationFailure.serviceUnavailable,
      ),
    ]) {
      expect(
        mapBridgePlaylistCreation(result).failure,
        PlaylistCreationFailure.invalidResponseOutcomeUnknown,
      );
    }
  });

  test('forwards requested name and confirmed result', () async {
    late String requestedName;
    final gateway = RustPlaylistCreationGateway(
      credentialVault: _Vault(),
      operationFactory: (name) {
        requestedName = name;
        return _Operation(
          PlaylistCreationResult(
            createdPlaylist: UserPlaylistSummary(
              providerId: 'qq-music',
              opaqueId: 'owned:7002:902',
              title: 'Server playlist',
            ),
          ),
        );
      },
    );

    final result = await gateway
        .beginCreation(name: 'Requested playlist')
        .run();

    expect(requestedName, 'Requested playlist');
    expect(result.createdPlaylist?.title, 'Server playlist');
  });

  test('cleans rejected credentials and exposes cleanup failure', () async {
    final deleted = _Vault();
    final rejected = RustPlaylistCreationGateway(
      credentialVault: deleted,
      operationFactory: (_) => const _Operation(
        PlaylistCreationResult(
          failure: PlaylistCreationFailure.credentialRejected,
        ),
      ),
    );
    expect(
      (await rejected.beginCreation(name: 'Requested playlist').run()).failure,
      PlaylistCreationFailure.credentialRejected,
    );
    expect(deleted.deleteCount, 1);

    final cleanupFailure = RustPlaylistCreationGateway(
      credentialVault: _Vault(failDelete: true),
      operationFactory: (_) => const _Operation(
        PlaylistCreationResult(
          failure: PlaylistCreationFailure.credentialRejected,
        ),
      ),
    );
    expect(
      (await cleanupFailure.beginCreation(name: 'Requested playlist').run())
          .failure,
      PlaylistCreationFailure.credentialRejectedStorageCleanupFailed,
    );
  });
}

class _Operation implements PlaylistCreationOperation {
  const _Operation(this.result);

  final PlaylistCreationResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistCreationResult> run() async => result;
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
