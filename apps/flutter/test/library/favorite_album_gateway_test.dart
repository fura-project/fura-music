import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge_album;
import 'package:flutterustmusic/src/rust/api/favorite_albums.dart' as bridge;

void main() {
  test('maps a valid favorite-Album page into immutable summaries', () {
    final result = mapBridgeFavoriteAlbumPage(
      const bridge.QqMusicFavoriteAlbumPageLoad(
        offset: 20,
        total: 21,
        hasMore: false,
        albums: [
          bridge_album.CatalogAlbumSummary(
            providerId: 'qq-music',
            opaqueId: 'album:43001:fixtureAlbumMid',
            title: 'Synthetic Album',
            artworkUri: 'https://example.invalid/album.jpg',
          ),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.offset, 20);
    expect(result.total, 21);
    expect(result.hasMore, isFalse);
    expect(result.albums.single.title, 'Synthetic Album');
    expect(() => result.albums.clear(), throwsUnsupportedError);
  });

  test('maps every Bridge failure and rejects contradictory content', () {
    final expected = {
      bridge.QqMusicFavoriteAlbumPageLoadFailure.coreUnavailable:
          FavoriteAlbumFailure.coreUnavailable,
      bridge.QqMusicFavoriteAlbumPageLoadFailure.authenticationRequired:
          FavoriteAlbumFailure.authenticationRequired,
      bridge.QqMusicFavoriteAlbumPageLoadFailure.credentialRejected:
          FavoriteAlbumFailure.credentialRejected,
      bridge.QqMusicFavoriteAlbumPageLoadFailure.network:
          FavoriteAlbumFailure.network,
      bridge.QqMusicFavoriteAlbumPageLoadFailure.serviceUnavailable:
          FavoriteAlbumFailure.serviceUnavailable,
      bridge.QqMusicFavoriteAlbumPageLoadFailure.invalidResponse:
          FavoriteAlbumFailure.invalidResponse,
      bridge.QqMusicFavoriteAlbumPageLoadFailure.replaced:
          FavoriteAlbumFailure.replaced,
      bridge.QqMusicFavoriteAlbumPageLoadFailure.cancelled:
          FavoriteAlbumFailure.cancelled,
      bridge.QqMusicFavoriteAlbumPageLoadFailure.alreadyRunning:
          FavoriteAlbumFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeFavoriteAlbumFailure(input), output);
    }

    final conflict = mapBridgeFavoriteAlbumPage(
      const bridge.QqMusicFavoriteAlbumPageLoad(
        offset: 0,
        total: 1,
        hasMore: false,
        albums: [
          bridge_album.CatalogAlbumSummary(
            providerId: 'qq-music',
            opaqueId: 'opaque',
            title: 'must not coexist',
          ),
        ],
        failure: bridge.QqMusicFavoriteAlbumPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, FavoriteAlbumFailure.invalidResponse);

    final malformed = mapBridgeFavoriteAlbumPage(
      const bridge.QqMusicFavoriteAlbumPageLoad(
        offset: 0,
        total: 1,
        hasMore: false,
        albums: [
          bridge_album.CatalogAlbumSummary(
            providerId: 'qq-music',
            opaqueId: '',
            title: 'Synthetic Album',
          ),
        ],
      ),
    );
    expect(malformed.failure, FavoriteAlbumFailure.invalidResponse);

    final contradictoryPagination = mapBridgeFavoriteAlbumPage(
      const bridge.QqMusicFavoriteAlbumPageLoad(
        offset: 0,
        total: 2,
        hasMore: false,
        albums: [
          bridge_album.CatalogAlbumSummary(
            providerId: 'qq-music',
            opaqueId: 'opaque',
            title: 'Synthetic Album',
          ),
        ],
      ),
    );
    expect(
      contradictoryPagination.failure,
      FavoriteAlbumFailure.invalidResponse,
    );
  });

  test('forwards exact paging and cancellation', () {
    late int offset;
    late int size;
    final operation = _ImmediateOperation(
      const FavoriteAlbumPageResult(failure: FavoriteAlbumFailure.cancelled),
    );
    final gateway = RustFavoriteAlbumGateway(
      credentialVault: _FakeVault(),
      operationFactory: (inputOffset, inputSize) {
        offset = inputOffset;
        size = inputSize;
        return operation;
      },
    );

    final begun = gateway.beginLoad(offset: 40, size: 20);
    expect(begun.cancel(), isTrue);
    expect(offset, 40);
    expect(size, 20);
    expect(operation.cancelCalls, 1);
  });

  test('deletes the shared vault only after explicit rejection', () async {
    final rejectedVault = _FakeVault();
    final rejected = RustFavoriteAlbumGateway(
      credentialVault: rejectedVault,
      operationFactory: (_, _) => _ImmediateOperation(
        const FavoriteAlbumPageResult(
          failure: FavoriteAlbumFailure.credentialRejected,
        ),
      ),
    );
    final rejectedResult = await rejected.beginLoad(offset: 0, size: 20).run();
    expect(rejectedResult.failure, FavoriteAlbumFailure.credentialRejected);
    expect(rejectedVault.deleteCalls, 1);

    final transientVault = _FakeVault();
    final transient = RustFavoriteAlbumGateway(
      credentialVault: transientVault,
      operationFactory: (_, _) => _ImmediateOperation(
        const FavoriteAlbumPageResult(failure: FavoriteAlbumFailure.network),
      ),
    );
    await transient.beginLoad(offset: 0, size: 20).run();
    expect(transientVault.deleteCalls, 0);

    final failedVault = _FakeVault(
      deleteError: StateError('synthetic cleanup failure'),
    );
    final cleanupFailure = RustFavoriteAlbumGateway(
      credentialVault: failedVault,
      operationFactory: (_, _) => _ImmediateOperation(
        const FavoriteAlbumPageResult(
          failure: FavoriteAlbumFailure.credentialRejected,
        ),
      ),
    );
    final cleanupResult = await cleanupFailure
        .beginLoad(offset: 0, size: 20)
        .run();
    expect(
      cleanupResult.failure,
      FavoriteAlbumFailure.credentialRejectedStorageCleanupFailed,
    );
    expect(failedVault.deleteCalls, 1);
  });
}

class _ImmediateOperation implements FavoriteAlbumPageLoadOperation {
  _ImmediateOperation(this.result);

  final FavoriteAlbumPageResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<FavoriteAlbumPageResult> run() async => result;
}

class _FakeVault implements CredentialVault {
  _FakeVault({this.deleteError});

  final Object? deleteError;
  int deleteCalls = 0;

  @override
  Future<void> delete() async {
    deleteCalls += 1;
    final error = deleteError;
    if (error != null) throw error;
  }

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List secretBytes) async {}
}
