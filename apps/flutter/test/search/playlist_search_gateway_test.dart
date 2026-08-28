import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/search.dart' as bridge;

void main() {
  test('maps a valid Bridge page into presentation-safe playlists', () {
    final result = mapBridgePlaylistSearchPage(
      const bridge.QqMusicPlaylistSearchPageLoad(
        page: 1,
        total: 25,
        hasMore: true,
        playlists: [
          bridge_library.LibraryPlaylistSummary(
            isLikedSongs: false,
            providerId: 'qq-music',
            opaqueId: 'catalog:81001',
            title: 'Synthetic Playlist',
            artworkUri: 'https://example.invalid/playlist.jpg',
            trackCount: 12,
          ),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.page, 1);
    expect(result.total, 25);
    expect(result.hasMore, isTrue);
    expect(result.playlists.single.providerId, 'qq-music');
    expect(result.playlists.single.title, 'Synthetic Playlist');
    expect(result.playlists.single.trackCount, 12);
  });

  test('maps every Bridge failure and rejects conflicting success data', () {
    final expected = {
      bridge.QqMusicPlaylistSearchPageLoadFailure.coreUnavailable:
          SearchFailure.coreUnavailable,
      bridge.QqMusicPlaylistSearchPageLoadFailure.network:
          SearchFailure.network,
      bridge.QqMusicPlaylistSearchPageLoadFailure.serviceUnavailable:
          SearchFailure.serviceUnavailable,
      bridge.QqMusicPlaylistSearchPageLoadFailure.invalidResponse:
          SearchFailure.invalidResponse,
      bridge.QqMusicPlaylistSearchPageLoadFailure.cancelled:
          SearchFailure.cancelled,
      bridge.QqMusicPlaylistSearchPageLoadFailure.alreadyRunning:
          SearchFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeSearchFailure(input), output);
    }

    final conflict = mapBridgePlaylistSearchPage(
      const bridge.QqMusicPlaylistSearchPageLoad(
        page: 1,
        total: 0,
        hasMore: false,
        playlists: [],
        failure: bridge.QqMusicPlaylistSearchPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, SearchFailure.invalidResponse);

    final invalidIdentity = mapBridgePlaylistSearchPage(
      const bridge.QqMusicPlaylistSearchPageLoad(
        page: 1,
        total: 1,
        hasMore: false,
        playlists: [
          bridge_library.LibraryPlaylistSummary(
            isLikedSongs: false,
            providerId: 'qq-music',
            opaqueId: '',
            title: 'Synthetic Playlist',
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
    final gateway = RustPlaylistSearchGateway(
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

class _ImmediateOperation implements PlaylistSearchPageLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<PlaylistSearchPageResult> run() async =>
      const PlaylistSearchPageResult(failure: SearchFailure.cancelled);
}
