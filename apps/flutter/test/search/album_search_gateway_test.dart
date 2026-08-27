import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge_album;
import 'package:flutterustmusic/src/rust/api/search.dart' as bridge;

void main() {
  test('maps a valid Bridge page into presentation-safe Albums', () {
    final result = mapBridgeAlbumSearchPage(
      const bridge.QqMusicAlbumSearchPageLoad(
        page: 1,
        total: 25,
        hasMore: true,
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
    expect(result.page, 1);
    expect(result.total, 25);
    expect(result.hasMore, isTrue);
    expect(result.albums.single.providerId, 'qq-music');
    expect(result.albums.single.title, 'Synthetic Album');
  });

  test('maps every Bridge failure and rejects conflicting success data', () {
    final expected = {
      bridge.QqMusicAlbumSearchPageLoadFailure.coreUnavailable:
          SearchFailure.coreUnavailable,
      bridge.QqMusicAlbumSearchPageLoadFailure.network: SearchFailure.network,
      bridge.QqMusicAlbumSearchPageLoadFailure.serviceUnavailable:
          SearchFailure.serviceUnavailable,
      bridge.QqMusicAlbumSearchPageLoadFailure.invalidResponse:
          SearchFailure.invalidResponse,
      bridge.QqMusicAlbumSearchPageLoadFailure.cancelled:
          SearchFailure.cancelled,
      bridge.QqMusicAlbumSearchPageLoadFailure.alreadyRunning:
          SearchFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeSearchFailure(input), output);
    }

    final conflict = mapBridgeAlbumSearchPage(
      const bridge.QqMusicAlbumSearchPageLoad(
        page: 1,
        total: 0,
        hasMore: false,
        albums: [],
        failure: bridge.QqMusicAlbumSearchPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, SearchFailure.invalidResponse);

    final invalidIdentity = mapBridgeAlbumSearchPage(
      const bridge.QqMusicAlbumSearchPageLoad(
        page: 1,
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
    expect(invalidIdentity.failure, SearchFailure.invalidResponse);
  });

  test('forwards operation inputs and cancellation', () {
    late String query;
    late int page;
    late int size;
    final operation = _ImmediateOperation();
    final gateway = RustAlbumSearchGateway(
      operationFactory: (inputQuery, inputPage, inputSize) {
        query = inputQuery;
        page = inputPage;
        size = inputSize;
        return operation;
      },
    );

    final begun = gateway.beginLoad(query: 'query', page: 2, size: 30);
    expect(begun.cancel(), isTrue);
    expect(query, 'query');
    expect(page, 2);
    expect(size, 30);
    expect(operation.cancelCalls, 1);
  });
}

class _ImmediateOperation implements AlbumSearchPageLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<AlbumSearchPageResult> run() async =>
      const AlbumSearchPageResult(failure: SearchFailure.cancelled);
}
