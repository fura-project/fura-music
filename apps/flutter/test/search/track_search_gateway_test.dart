import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge_album;
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/search.dart' as bridge;

void main() {
  test('maps a valid Bridge page into presentation-safe Tracks', () {
    final result = mapBridgeTrackSearchPage(
      const bridge.QqMusicTrackSearchPageLoad(
        page: 1,
        total: 31,
        hasMore: true,
        items: [
          bridge.QqMusicTrackSearchItem(
            track: bridge_library.LibraryTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:41001:0:fixtureMid:-',
              title: 'Synthetic track',
              artistNames: ['Artist one'],
              albumTitle: 'Synthetic album',
              durationSeconds: 245,
            ),
            album: bridge_album.CatalogAlbumSummary(
              providerId: 'qq-music',
              opaqueId: 'album:51001:fixtureAlbumMid',
              title: 'Synthetic album',
            ),
          ),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.page, 1);
    expect(result.total, 31);
    expect(result.hasMore, isTrue);
    expect(result.items.single.track.providerId, 'qq-music');
    expect(result.items.single.track.title, 'Synthetic track');
    expect(result.items.single.track.artistNames, ['Artist one']);
    expect(result.items.single.album?.opaqueId, 'album:51001:fixtureAlbumMid');
  });

  test('maps every Bridge failure and rejects conflicting success data', () {
    final expected = {
      bridge.QqMusicTrackSearchPageLoadFailure.coreUnavailable:
          TrackSearchFailure.coreUnavailable,
      bridge.QqMusicTrackSearchPageLoadFailure.network:
          TrackSearchFailure.network,
      bridge.QqMusicTrackSearchPageLoadFailure.serviceUnavailable:
          TrackSearchFailure.serviceUnavailable,
      bridge.QqMusicTrackSearchPageLoadFailure.invalidResponse:
          TrackSearchFailure.invalidResponse,
      bridge.QqMusicTrackSearchPageLoadFailure.cancelled:
          TrackSearchFailure.cancelled,
      bridge.QqMusicTrackSearchPageLoadFailure.alreadyRunning:
          TrackSearchFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeTrackSearchFailure(input), output);
    }

    final conflict = mapBridgeTrackSearchPage(
      const bridge.QqMusicTrackSearchPageLoad(
        page: 1,
        total: 0,
        hasMore: false,
        items: [],
        failure: bridge.QqMusicTrackSearchPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, TrackSearchFailure.invalidResponse);
  });

  test('forwards normalized operation inputs and cancellation', () {
    late String query;
    late int page;
    late int size;
    final operation = _ImmediateOperation();
    final gateway = RustTrackSearchGateway(
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

class _ImmediateOperation implements TrackSearchPageLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<TrackSearchPageResult> run() async =>
      const TrackSearchPageResult(failure: TrackSearchFailure.cancelled);
}
