import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge_album;
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge_artist;
import 'package:flutterustmusic/src/rust/api/new_albums.dart' as bridge;

void main() {
  test('maps a valid regional new Album page', () {
    final result = mapBridgeNewAlbumPage(
      const bridge.QqMusicNewAlbumPageLoad(
        region: bridge.QqMusicNewAlbumRegion.japan,
        offset: 5,
        total: 11,
        hasMore: true,
        releases: [
          bridge.CatalogNewAlbumRelease(
            album: bridge_album.CatalogAlbumSummary(
              providerId: 'qq-music',
              opaqueId: 'album:43001:fixtureAlbumMid',
              title: 'Synthetic Album',
              artworkUri: 'https://example.invalid/album.jpg',
            ),
            artists: [
              bridge_artist.CatalogArtistSummary(
                providerId: 'qq-music',
                opaqueId: 'artist:42001:fixtureArtistMid',
                name: 'Synthetic Artist',
              ),
            ],
            releaseDate: '2026-08-26',
          ),
        ],
      ),
      NewAlbumRegion.japan,
    );

    expect(result.failure, isNull);
    expect(result.region, NewAlbumRegion.japan);
    expect(result.offset, 5);
    expect(result.total, 11);
    expect(result.hasMore, isTrue);
    expect(result.releases.single.album.title, 'Synthetic Album');
    expect(result.releases.single.artists.single.name, 'Synthetic Artist');
    expect(result.releases.single.releaseDate, '2026-08-26');
  });

  test('maps every failure and rejects region or content conflicts', () {
    final expected = {
      bridge.QqMusicNewAlbumPageLoadFailure.coreUnavailable:
          NewAlbumFailure.coreUnavailable,
      bridge.QqMusicNewAlbumPageLoadFailure.network: NewAlbumFailure.network,
      bridge.QqMusicNewAlbumPageLoadFailure.serviceUnavailable:
          NewAlbumFailure.serviceUnavailable,
      bridge.QqMusicNewAlbumPageLoadFailure.invalidResponse:
          NewAlbumFailure.invalidResponse,
      bridge.QqMusicNewAlbumPageLoadFailure.cancelled:
          NewAlbumFailure.cancelled,
      bridge.QqMusicNewAlbumPageLoadFailure.alreadyRunning:
          NewAlbumFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeNewAlbumFailure(input), output);
    }

    final mismatched = mapBridgeNewAlbumPage(
      const bridge.QqMusicNewAlbumPageLoad(
        region: bridge.QqMusicNewAlbumRegion.korea,
        offset: 0,
        total: 0,
        hasMore: false,
        releases: [],
      ),
      NewAlbumRegion.japan,
    );
    expect(mismatched.failure, NewAlbumFailure.invalidResponse);

    final conflict = mapBridgeNewAlbumPage(
      const bridge.QqMusicNewAlbumPageLoad(
        region: bridge.QqMusicNewAlbumRegion.western,
        offset: 0,
        total: 1,
        hasMore: false,
        releases: [],
        failure: bridge.QqMusicNewAlbumPageLoadFailure.network,
      ),
      NewAlbumRegion.western,
    );
    expect(conflict.failure, NewAlbumFailure.invalidResponse);

    final malformed = mapBridgeNewAlbumPage(
      const bridge.QqMusicNewAlbumPageLoad(
        region: bridge.QqMusicNewAlbumRegion.western,
        offset: 0,
        total: 1,
        hasMore: false,
        releases: [
          bridge.CatalogNewAlbumRelease(
            album: bridge_album.CatalogAlbumSummary(
              providerId: 'qq-music',
              opaqueId: '',
              title: 'Synthetic Album',
            ),
            artists: [],
          ),
        ],
      ),
      NewAlbumRegion.western,
    );
    expect(malformed.failure, NewAlbumFailure.invalidResponse);
  });

  test('forwards typed region, paging, and cancellation', () {
    late NewAlbumRegion region;
    late int offset;
    late int size;
    final operation = _ImmediateOperation();
    final gateway = RustNewAlbumGateway(
      operationFactory: (inputRegion, inputOffset, inputSize) {
        region = inputRegion;
        offset = inputOffset;
        size = inputSize;
        return operation;
      },
    );

    final begun = gateway.beginLoad(
      region: NewAlbumRegion.hongKongTaiwan,
      offset: 20,
      size: 20,
    );
    expect(begun.cancel(), isTrue);
    expect(region, NewAlbumRegion.hongKongTaiwan);
    expect(offset, 20);
    expect(size, 20);
    expect(operation.cancelCalls, 1);
  });
}

class _ImmediateOperation implements NewAlbumPageLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<NewAlbumPageResult> run() async => const NewAlbumPageResult(
    region: NewAlbumRegion.hongKongTaiwan,
    failure: NewAlbumFailure.cancelled,
  );
}
