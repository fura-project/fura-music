import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/home/official_playlist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

void main() {
  test('maps official playlist metadata through its distinct Bridge type', () {
    final result = mapBridgeOfficialPlaylistPage(
      bridge.QqMusicOfficialPlaylistPageLoad(
        page: 1,
        nextPage: 2,
        total: 736,
        hasMore: true,
        omittedPlaylistCount: 0,
        playlists: [
          bridge.QqMusicOfficialPlaylistSummary(
            playlist: const bridge_library.LibraryPlaylistSummary(
              isLikedSongs: false,
              providerId: 'qq-music',
              opaqueId: 'catalog:82001',
              title: 'Synthetic official playlist',
              artworkUri: 'https://example.invalid/official.jpg',
            ),
            creator: 'Synthetic editor',
            playCount: BigInt.from(98765),
            categories: const ['Synthetic category'],
          ),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.page, 1);
    expect(result.nextPage, 2);
    expect(result.total, 736);
    expect(result.hasMore, isTrue);
    expect(result.playlists.single.opaqueId, 'catalog:82001');
    expect(result.playlists.single.creator, 'Synthetic editor');
    expect(result.playlists.single.playCount, BigInt.from(98765));
    expect(result.playlists.single.categories, ['Synthetic category']);
    expect(
      result.playlists.single.toRecommendationSummary().opaqueId,
      'catalog:82001',
    );
  });

  test('maps failures and rejects contradictory or malformed results', () {
    final expected = {
      bridge.QqMusicOfficialPlaylistPageLoadFailure.coreUnavailable:
          OfficialPlaylistFailure.coreUnavailable,
      bridge.QqMusicOfficialPlaylistPageLoadFailure.network:
          OfficialPlaylistFailure.network,
      bridge.QqMusicOfficialPlaylistPageLoadFailure.serviceUnavailable:
          OfficialPlaylistFailure.serviceUnavailable,
      bridge.QqMusicOfficialPlaylistPageLoadFailure.invalidResponse:
          OfficialPlaylistFailure.invalidResponse,
      bridge.QqMusicOfficialPlaylistPageLoadFailure.cancelled:
          OfficialPlaylistFailure.cancelled,
      bridge.QqMusicOfficialPlaylistPageLoadFailure.alreadyRunning:
          OfficialPlaylistFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeOfficialPlaylistFailure(input), output);
    }

    final conflict = mapBridgeOfficialPlaylistPage(
      const bridge.QqMusicOfficialPlaylistPageLoad(
        page: 0,
        nextPage: 0,
        total: 0,
        hasMore: false,
        omittedPlaylistCount: 0,
        playlists: [
          bridge.QqMusicOfficialPlaylistSummary(
            playlist: bridge_library.LibraryPlaylistSummary(
              isLikedSongs: false,
              providerId: 'qq-music',
              opaqueId: 'catalog:82001',
              title: 'must not coexist',
            ),
            categories: [],
          ),
        ],
        failure: bridge.QqMusicOfficialPlaylistPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, OfficialPlaylistFailure.invalidResponse);

    final malformed = mapBridgeOfficialPlaylistPage(
      const bridge.QqMusicOfficialPlaylistPageLoad(
        page: 1,
        nextPage: 2,
        total: 1,
        hasMore: false,
        omittedPlaylistCount: 0,
        playlists: [
          bridge.QqMusicOfficialPlaylistSummary(
            playlist: bridge_library.LibraryPlaylistSummary(
              isLikedSongs: false,
              providerId: 'qq-music',
              opaqueId: 'catalog:82001',
              title: 'Synthetic',
            ),
            creator: ' ',
            categories: [],
          ),
        ],
      ),
    );
    expect(malformed.failure, OfficialPlaylistFailure.invalidResponse);
  });

  test('forwards page, size and cancellation to the operation factory', () {
    late int page;
    late int size;
    final operation = _ImmediateOperation();
    final gateway = RustOfficialPlaylistGateway(
      operationFactory: (inputPage, inputSize) {
        page = inputPage;
        size = inputSize;
        return operation;
      },
    );

    final begun = gateway.beginLoad(page: 1, size: 8);
    expect(begun.cancel(), isTrue);
    expect(page, 1);
    expect(size, 8);
    expect(operation.cancelCalls, 1);
  });
}

class _ImmediateOperation implements OfficialPlaylistPageLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<OfficialPlaylistPageResult> run() async =>
      const OfficialPlaylistPageResult(
        failure: OfficialPlaylistFailure.cancelled,
      );
}
