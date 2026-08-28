import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

void main() {
  test('maps a valid Bridge recommendation page into presentation data', () {
    final result = mapBridgeRecommendedPlaylistPage(
      const bridge.QqMusicRecommendedPlaylistPageLoad(
        offset: 20,
        hasMore: true,
        playlists: [
          bridge_library.LibraryPlaylistSummary(
            isLikedSongs: false,
            providerId: 'qq-music',
            opaqueId: 'catalog:81001',
            title: 'Synthetic discovery',
            artworkUri: 'https://example.invalid/discovery.jpg',
            trackCount: 27,
          ),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.offset, 20);
    expect(result.hasMore, isTrue);
    expect(result.playlists.single.opaqueId, 'catalog:81001');
    expect(result.playlists.single.title, 'Synthetic discovery');
    expect(result.playlists.single.trackCount, 27);
    expect(
      result.playlists.single.toPlaylistSummary().opaqueId,
      'catalog:81001',
    );
  });

  test('maps every failure and rejects contradictory failure data', () {
    final expected = {
      bridge.QqMusicRecommendedPlaylistPageLoadFailure.coreUnavailable:
          RecommendedPlaylistFailure.coreUnavailable,
      bridge.QqMusicRecommendedPlaylistPageLoadFailure.network:
          RecommendedPlaylistFailure.network,
      bridge.QqMusicRecommendedPlaylistPageLoadFailure.serviceUnavailable:
          RecommendedPlaylistFailure.serviceUnavailable,
      bridge.QqMusicRecommendedPlaylistPageLoadFailure.invalidResponse:
          RecommendedPlaylistFailure.invalidResponse,
      bridge.QqMusicRecommendedPlaylistPageLoadFailure.cancelled:
          RecommendedPlaylistFailure.cancelled,
      bridge.QqMusicRecommendedPlaylistPageLoadFailure.alreadyRunning:
          RecommendedPlaylistFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeRecommendedPlaylistFailure(input), output);
    }

    final conflict = mapBridgeRecommendedPlaylistPage(
      const bridge.QqMusicRecommendedPlaylistPageLoad(
        offset: 0,
        hasMore: false,
        playlists: [
          bridge_library.LibraryPlaylistSummary(
            isLikedSongs: false,
            providerId: 'qq-music',
            opaqueId: 'catalog:81001',
            title: 'must not coexist',
          ),
        ],
        failure: bridge.QqMusicRecommendedPlaylistPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, RecommendedPlaylistFailure.invalidResponse);
  });

  test('rejects malformed page and playlist fields', () {
    final nonAdvancing = mapBridgeRecommendedPlaylistPage(
      const bridge.QqMusicRecommendedPlaylistPageLoad(
        offset: 0,
        hasMore: true,
        playlists: [],
      ),
    );
    expect(nonAdvancing.failure, RecommendedPlaylistFailure.invalidResponse);

    final malformed = mapBridgeRecommendedPlaylistPage(
      const bridge.QqMusicRecommendedPlaylistPageLoad(
        offset: 0,
        hasMore: false,
        playlists: [
          bridge_library.LibraryPlaylistSummary(
            isLikedSongs: false,
            providerId: 'qq-music',
            opaqueId: 'catalog:81001',
            title: 'Synthetic',
            artworkUri: ' ',
          ),
        ],
      ),
    );
    expect(malformed.failure, RecommendedPlaylistFailure.invalidResponse);
  });

  test('forwards paging and cancellation to the operation factory', () {
    late int offset;
    late int size;
    final operation = _ImmediateOperation();
    final gateway = RustRecommendedPlaylistGateway(
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
}

class _ImmediateOperation implements RecommendedPlaylistPageLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<RecommendedPlaylistPageResult> run() async =>
      const RecommendedPlaylistPageResult(
        failure: RecommendedPlaylistFailure.cancelled,
      );
}
