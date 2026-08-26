import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge_album;
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge;

void main() {
  const artist = ArtistSummary(
    providerId: 'qq-music',
    opaqueId: 'artist:61001:fixtureArtistMid',
    name: 'Synthetic artist',
  );

  test('maps a valid Bridge Artist Album page', () {
    final result = mapBridgeArtistAlbumPage(
      const bridge.QqMusicArtistAlbumPageLoad(
        offset: 0,
        total: 31,
        hasMore: true,
        albums: [
          bridge_album.CatalogAlbumSummary(
            providerId: 'qq-music',
            opaqueId: 'album:43001:fixtureAlbumMid',
            title: 'Synthetic album',
            artworkUri: 'https://example.invalid/cover.jpg',
          ),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.offset, 0);
    expect(result.total, 31);
    expect(result.hasMore, isTrue);
    expect(result.albums.single.title, 'Synthetic album');
    expect(result.albums.single.opaqueId, 'album:43001:fixtureAlbumMid');
  });

  test('maps failures and rejects success data beside a failure', () {
    final expected = {
      bridge.QqMusicArtistAlbumPageLoadFailure.coreUnavailable:
          ArtistAlbumFailure.coreUnavailable,
      bridge.QqMusicArtistAlbumPageLoadFailure.network:
          ArtistAlbumFailure.network,
      bridge.QqMusicArtistAlbumPageLoadFailure.serviceUnavailable:
          ArtistAlbumFailure.serviceUnavailable,
      bridge.QqMusicArtistAlbumPageLoadFailure.invalidResponse:
          ArtistAlbumFailure.invalidResponse,
      bridge.QqMusicArtistAlbumPageLoadFailure.cancelled:
          ArtistAlbumFailure.cancelled,
      bridge.QqMusicArtistAlbumPageLoadFailure.alreadyRunning:
          ArtistAlbumFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeArtistAlbumFailure(input), output);
    }

    final conflict = mapBridgeArtistAlbumPage(
      const bridge.QqMusicArtistAlbumPageLoad(
        offset: 0,
        total: 1,
        hasMore: false,
        albums: [],
        failure: bridge.QqMusicArtistAlbumPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, ArtistAlbumFailure.invalidResponse);

    final malformed = mapBridgeArtistAlbumPage(
      const bridge.QqMusicArtistAlbumPageLoad(
        offset: 0,
        total: 1,
        hasMore: false,
        albums: [
          bridge_album.CatalogAlbumSummary(
            providerId: 'qq-music',
            opaqueId: '',
            title: 'Synthetic album',
          ),
        ],
      ),
    );
    expect(malformed.failure, ArtistAlbumFailure.invalidResponse);
  });

  test('forwards provider identity, paging, and cancellation', () {
    late ArtistSummary requestedArtist;
    late int offset;
    late int size;
    final operation = _ImmediateOperation();
    final gateway = RustArtistAlbumGateway(
      operationFactory: (inputArtist, inputOffset, inputSize) {
        requestedArtist = inputArtist;
        offset = inputOffset;
        size = inputSize;
        return operation;
      },
    );

    final begun = gateway.beginLoad(artist: artist, offset: 30, size: 30);
    expect(begun.cancel(), isTrue);
    expect(requestedArtist, same(artist));
    expect(offset, 30);
    expect(size, 30);
    expect(operation.cancelCalls, 1);
  });
}

class _ImmediateOperation implements ArtistAlbumPageLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<ArtistAlbumPageResult> run() async =>
      const ArtistAlbumPageResult(failure: ArtistAlbumFailure.cancelled);
}
