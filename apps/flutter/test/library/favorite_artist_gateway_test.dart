import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge_artist;
import 'package:flutterustmusic/src/rust/api/favorite_artists.dart' as bridge;

void main() {
  test('maps a valid favorite-Artist page into immutable summaries', () {
    final result = mapBridgeFavoriteArtistPage(
      const bridge.QqMusicFavoriteArtistPageLoad(
        offset: 20,
        total: 21,
        hasMore: false,
        artists: [
          bridge_artist.CatalogArtistSummary(
            providerId: 'qq-music',
            opaqueId: 'artist:-:fixtureArtistMid',
            name: 'Synthetic Artist',
            artworkUri: 'https://example.invalid/artist.jpg',
          ),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.offset, 20);
    expect(result.total, 21);
    expect(result.hasMore, isFalse);
    expect(result.artists.single.name, 'Synthetic Artist');
    expect(
      result.artists.single.artworkUri,
      'https://example.invalid/artist.jpg',
    );
    expect(() => result.artists.clear(), throwsUnsupportedError);
  });

  test('maps every Bridge failure and rejects contradictory content', () {
    final expected = {
      bridge.QqMusicFavoriteArtistPageLoadFailure.coreUnavailable:
          FavoriteArtistFailure.coreUnavailable,
      bridge.QqMusicFavoriteArtistPageLoadFailure.authenticationRequired:
          FavoriteArtistFailure.authenticationRequired,
      bridge.QqMusicFavoriteArtistPageLoadFailure.credentialRejected:
          FavoriteArtistFailure.credentialRejected,
      bridge.QqMusicFavoriteArtistPageLoadFailure.network:
          FavoriteArtistFailure.network,
      bridge.QqMusicFavoriteArtistPageLoadFailure.serviceUnavailable:
          FavoriteArtistFailure.serviceUnavailable,
      bridge.QqMusicFavoriteArtistPageLoadFailure.invalidResponse:
          FavoriteArtistFailure.invalidResponse,
      bridge.QqMusicFavoriteArtistPageLoadFailure.replaced:
          FavoriteArtistFailure.replaced,
      bridge.QqMusicFavoriteArtistPageLoadFailure.cancelled:
          FavoriteArtistFailure.cancelled,
      bridge.QqMusicFavoriteArtistPageLoadFailure.alreadyRunning:
          FavoriteArtistFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeFavoriteArtistFailure(input), output);
    }

    final conflict = mapBridgeFavoriteArtistPage(
      const bridge.QqMusicFavoriteArtistPageLoad(
        offset: 0,
        total: 1,
        hasMore: false,
        artists: [
          bridge_artist.CatalogArtistSummary(
            providerId: 'qq-music',
            opaqueId: 'artist:-:fixtureArtistMid',
            name: 'must not coexist',
          ),
        ],
        failure: bridge.QqMusicFavoriteArtistPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, FavoriteArtistFailure.invalidResponse);

    final malformed = mapBridgeFavoriteArtistPage(
      const bridge.QqMusicFavoriteArtistPageLoad(
        offset: 0,
        total: 1,
        hasMore: false,
        artists: [
          bridge_artist.CatalogArtistSummary(
            providerId: 'qq-music',
            opaqueId: '',
            name: 'Synthetic Artist',
          ),
        ],
      ),
    );
    expect(malformed.failure, FavoriteArtistFailure.invalidResponse);

    final blankArtwork = mapBridgeFavoriteArtistPage(
      const bridge.QqMusicFavoriteArtistPageLoad(
        offset: 0,
        total: 1,
        hasMore: false,
        artists: [
          bridge_artist.CatalogArtistSummary(
            providerId: 'qq-music',
            opaqueId: 'artist:-:fixtureArtistMid',
            name: 'Synthetic Artist',
            artworkUri: '   ',
          ),
        ],
      ),
    );
    expect(blankArtwork.failure, FavoriteArtistFailure.invalidResponse);

    final contradictoryPagination = mapBridgeFavoriteArtistPage(
      const bridge.QqMusicFavoriteArtistPageLoad(
        offset: 0,
        total: 2,
        hasMore: false,
        artists: [
          bridge_artist.CatalogArtistSummary(
            providerId: 'qq-music',
            opaqueId: 'artist:-:fixtureArtistMid',
            name: 'Synthetic Artist',
          ),
        ],
      ),
    );
    expect(
      contradictoryPagination.failure,
      FavoriteArtistFailure.invalidResponse,
    );
  });

  test('forwards exact paging and cancellation', () {
    late int offset;
    late int size;
    final operation = _ImmediateOperation(
      const FavoriteArtistPageResult(failure: FavoriteArtistFailure.cancelled),
    );
    final gateway = RustFavoriteArtistGateway(
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
    final rejected = RustFavoriteArtistGateway(
      credentialVault: rejectedVault,
      operationFactory: (_, _) => _ImmediateOperation(
        const FavoriteArtistPageResult(
          failure: FavoriteArtistFailure.credentialRejected,
        ),
      ),
    );
    final rejectedResult = await rejected.beginLoad(offset: 0, size: 20).run();
    expect(rejectedResult.failure, FavoriteArtistFailure.credentialRejected);
    expect(rejectedVault.deleteCalls, 1);

    final transientVault = _FakeVault();
    final transient = RustFavoriteArtistGateway(
      credentialVault: transientVault,
      operationFactory: (_, _) => _ImmediateOperation(
        const FavoriteArtistPageResult(failure: FavoriteArtistFailure.network),
      ),
    );
    await transient.beginLoad(offset: 0, size: 20).run();
    expect(transientVault.deleteCalls, 0);

    final failedVault = _FakeVault(
      deleteError: StateError('synthetic cleanup failure'),
    );
    final cleanupFailure = RustFavoriteArtistGateway(
      credentialVault: failedVault,
      operationFactory: (_, _) => _ImmediateOperation(
        const FavoriteArtistPageResult(
          failure: FavoriteArtistFailure.credentialRejected,
        ),
      ),
    );
    final cleanupResult = await cleanupFailure
        .beginLoad(offset: 0, size: 20)
        .run();
    expect(
      cleanupResult.failure,
      FavoriteArtistFailure.credentialRejectedStorageCleanupFailed,
    );
    expect(failedVault.deleteCalls, 1);
  });
}

class _ImmediateOperation implements FavoriteArtistPageLoadOperation {
  _ImmediateOperation(this.result);

  final FavoriteArtistPageResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<FavoriteArtistPageResult> run() async => result;
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
