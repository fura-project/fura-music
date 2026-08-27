import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/album_favorite_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album_favorites.dart' as bridge;

void main() {
  test('maps confirmed states and every typed failure', () {
    for (final pair in [
      (bridge.QqMusicAlbumFavoriteState.favorite, AlbumFavoriteState.favorite),
      (
        bridge.QqMusicAlbumFavoriteState.notFavorite,
        AlbumFavoriteState.notFavorite,
      ),
    ]) {
      final result = mapBridgeAlbumFavoriteMutation(
        bridge.QqMusicAlbumFavoriteMutationResult(confirmedState: pair.$1),
      );
      expect(result.confirmedState, pair.$2);
      expect(result.failure, isNull);
    }

    final failures = {
      bridge.QqMusicAlbumFavoriteMutationFailure.coreUnavailable:
          AlbumFavoriteMutationFailure.coreUnavailable,
      bridge.QqMusicAlbumFavoriteMutationFailure.authenticationRequired:
          AlbumFavoriteMutationFailure.authenticationRequired,
      bridge.QqMusicAlbumFavoriteMutationFailure.credentialRejected:
          AlbumFavoriteMutationFailure.credentialRejected,
      bridge.QqMusicAlbumFavoriteMutationFailure.networkOutcomeUnknown:
          AlbumFavoriteMutationFailure.networkOutcomeUnknown,
      bridge.QqMusicAlbumFavoriteMutationFailure.serviceUnavailable:
          AlbumFavoriteMutationFailure.serviceUnavailable,
      bridge.QqMusicAlbumFavoriteMutationFailure.invalidRequest:
          AlbumFavoriteMutationFailure.invalidRequest,
      bridge.QqMusicAlbumFavoriteMutationFailure.invalidResponseOutcomeUnknown:
          AlbumFavoriteMutationFailure.invalidResponseOutcomeUnknown,
      bridge.QqMusicAlbumFavoriteMutationFailure.replacedOutcomeUnknown:
          AlbumFavoriteMutationFailure.replacedOutcomeUnknown,
      bridge.QqMusicAlbumFavoriteMutationFailure.cancelledOutcomeUnknown:
          AlbumFavoriteMutationFailure.cancelledOutcomeUnknown,
      bridge.QqMusicAlbumFavoriteMutationFailure.alreadyRunning:
          AlbumFavoriteMutationFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: expected) in failures.entries) {
      final result = mapBridgeAlbumFavoriteMutation(
        bridge.QqMusicAlbumFavoriteMutationResult(failure: input),
      );
      expect(result.confirmedState, isNull);
      expect(result.failure, expected);
    }
  });

  test('rejects contradictory or empty bridge results', () {
    for (final result in [
      const bridge.QqMusicAlbumFavoriteMutationResult(),
      const bridge.QqMusicAlbumFavoriteMutationResult(
        confirmedState: bridge.QqMusicAlbumFavoriteState.favorite,
        failure: bridge.QqMusicAlbumFavoriteMutationFailure.serviceUnavailable,
      ),
    ]) {
      expect(
        mapBridgeAlbumFavoriteMutation(result).failure,
        AlbumFavoriteMutationFailure.invalidResponseOutcomeUnknown,
      );
    }
  });

  test('forwards opaque Album identity and desired state', () async {
    late String providerId;
    late String opaqueAlbumId;
    late AlbumFavoriteState desiredState;
    final gateway = RustAlbumFavoriteGateway(
      credentialVault: _Vault(),
      operationFactory: (provider, opaque, desired) {
        providerId = provider;
        opaqueAlbumId = opaque;
        desiredState = desired;
        return const _Operation(
          AlbumFavoriteMutationResult(
            confirmedState: AlbumFavoriteState.notFavorite,
          ),
        );
      },
    );

    final result = await gateway
        .beginMutation(
          providerId: 'qq-music',
          opaqueAlbumId: 'album:43001:fixtureAlbumMid',
          desiredState: AlbumFavoriteState.notFavorite,
        )
        .run();

    expect(providerId, 'qq-music');
    expect(opaqueAlbumId, 'album:43001:fixtureAlbumMid');
    expect(desiredState, AlbumFavoriteState.notFavorite);
    expect(result.confirmedState, AlbumFavoriteState.notFavorite);
  });

  test('cleans rejected credentials and exposes cleanup failure', () async {
    final deleted = _Vault();
    final rejected = RustAlbumFavoriteGateway(
      credentialVault: deleted,
      operationFactory: (_, _, _) => const _Operation(
        AlbumFavoriteMutationResult(
          failure: AlbumFavoriteMutationFailure.credentialRejected,
        ),
      ),
    );
    expect(
      (await rejected
              .beginMutation(
                providerId: 'qq-music',
                opaqueAlbumId: 'album:43001:fixtureAlbumMid',
                desiredState: AlbumFavoriteState.favorite,
              )
              .run())
          .failure,
      AlbumFavoriteMutationFailure.credentialRejected,
    );
    expect(deleted.deleteCount, 1);

    final cleanupFailure = RustAlbumFavoriteGateway(
      credentialVault: _Vault(failDelete: true),
      operationFactory: (_, _, _) => const _Operation(
        AlbumFavoriteMutationResult(
          failure: AlbumFavoriteMutationFailure.credentialRejected,
        ),
      ),
    );
    expect(
      (await cleanupFailure
              .beginMutation(
                providerId: 'qq-music',
                opaqueAlbumId: 'album:43001:fixtureAlbumMid',
                desiredState: AlbumFavoriteState.favorite,
              )
              .run())
          .failure,
      AlbumFavoriteMutationFailure.credentialRejectedStorageCleanupFailed,
    );
  });
}

class _Operation implements AlbumFavoriteMutationOperation {
  const _Operation(this.result);

  final AlbumFavoriteMutationResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumFavoriteMutationResult> run() async => result;
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
