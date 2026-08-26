import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge_artist;
import 'package:flutterustmusic/src/rust/api/search.dart' as bridge;

void main() {
  test('maps a valid Bridge page into presentation-safe Artists', () {
    final result = mapBridgeArtistSearchPage(
      const bridge.QqMusicArtistSearchPageLoad(
        page: 1,
        total: 8,
        hasMore: true,
        artists: [
          bridge_artist.CatalogArtistSummary(
            providerId: 'qq-music',
            opaqueId: 'artist:61001:fixtureArtistMid',
            name: 'Synthetic Artist',
          ),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.page, 1);
    expect(result.total, 8);
    expect(result.hasMore, isTrue);
    expect(result.artists.single.providerId, 'qq-music');
    expect(result.artists.single.name, 'Synthetic Artist');
  });

  test('maps every Bridge failure and rejects conflicting success data', () {
    final expected = {
      bridge.QqMusicArtistSearchPageLoadFailure.coreUnavailable:
          ArtistSearchFailure.coreUnavailable,
      bridge.QqMusicArtistSearchPageLoadFailure.network:
          ArtistSearchFailure.network,
      bridge.QqMusicArtistSearchPageLoadFailure.serviceUnavailable:
          ArtistSearchFailure.serviceUnavailable,
      bridge.QqMusicArtistSearchPageLoadFailure.invalidResponse:
          ArtistSearchFailure.invalidResponse,
      bridge.QqMusicArtistSearchPageLoadFailure.cancelled:
          ArtistSearchFailure.cancelled,
      bridge.QqMusicArtistSearchPageLoadFailure.alreadyRunning:
          ArtistSearchFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeArtistSearchFailure(input), output);
    }

    final conflict = mapBridgeArtistSearchPage(
      const bridge.QqMusicArtistSearchPageLoad(
        page: 1,
        total: 0,
        hasMore: false,
        artists: [],
        failure: bridge.QqMusicArtistSearchPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, ArtistSearchFailure.invalidResponse);

    final invalidIdentity = mapBridgeArtistSearchPage(
      const bridge.QqMusicArtistSearchPageLoad(
        page: 1,
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
    expect(invalidIdentity.failure, ArtistSearchFailure.invalidResponse);
  });

  test('forwards operation inputs and cancellation', () {
    late String query;
    late int page;
    late int size;
    final operation = _ImmediateOperation();
    final gateway = RustArtistSearchGateway(
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

class _ImmediateOperation implements ArtistSearchPageLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<ArtistSearchPageResult> run() async =>
      const ArtistSearchPageResult(failure: ArtistSearchFailure.cancelled);
}
