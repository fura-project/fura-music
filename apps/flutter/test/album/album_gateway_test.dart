import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge;
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge_artist;
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;

void main() {
  const album = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'album:51001:fixtureAlbumMid',
    title: 'Synthetic album',
  );

  test('maps a valid Bridge Album page into presentation-safe Tracks', () {
    final result = mapBridgeAlbumTrackPage(
      const bridge.QqMusicAlbumTrackPageLoad(
        offset: 0,
        total: 31,
        hasMore: true,
        tracks: [
          bridge_library.LibraryTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:41001:0:fixtureMid:-',
            title: 'Synthetic track',
            artistNames: ['Artist one'],
            artists: [
              bridge_artist.CatalogArtistSummary(
                providerId: 'qq-music',
                opaqueId: 'artist:42001:fixtureArtistMid',
                name: 'Artist one',
              ),
            ],
            albumTitle: 'Synthetic album',
            durationSeconds: 245,
          ),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.offset, 0);
    expect(result.total, 31);
    expect(result.hasMore, isTrue);
    expect(result.tracks.single.title, 'Synthetic track');
    expect(result.tracks.single.artistNames, ['Artist one']);
    expect(
      result.tracks.single.artists.single.opaqueId,
      'artist:42001:fixtureArtistMid',
    );
  });

  test('maps failures and rejects success data beside a failure', () {
    final expected = {
      bridge.QqMusicAlbumTrackPageLoadFailure.coreUnavailable:
          AlbumTrackFailure.coreUnavailable,
      bridge.QqMusicAlbumTrackPageLoadFailure.network:
          AlbumTrackFailure.network,
      bridge.QqMusicAlbumTrackPageLoadFailure.serviceUnavailable:
          AlbumTrackFailure.serviceUnavailable,
      bridge.QqMusicAlbumTrackPageLoadFailure.invalidResponse:
          AlbumTrackFailure.invalidResponse,
      bridge.QqMusicAlbumTrackPageLoadFailure.cancelled:
          AlbumTrackFailure.cancelled,
      bridge.QqMusicAlbumTrackPageLoadFailure.alreadyRunning:
          AlbumTrackFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeAlbumTrackFailure(input), output);
    }

    final conflict = mapBridgeAlbumTrackPage(
      const bridge.QqMusicAlbumTrackPageLoad(
        offset: 0,
        total: 1,
        hasMore: false,
        tracks: [],
        failure: bridge.QqMusicAlbumTrackPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, AlbumTrackFailure.invalidResponse);
  });

  test('forwards provider identity, paging, and cancellation', () {
    late AlbumSummary requestedAlbum;
    late int offset;
    late int size;
    final operation = _ImmediateOperation();
    final gateway = RustAlbumTrackGateway(
      operationFactory: (inputAlbum, inputOffset, inputSize) {
        requestedAlbum = inputAlbum;
        offset = inputOffset;
        size = inputSize;
        return operation;
      },
    );

    final begun = gateway.beginLoad(album: album, offset: 30, size: 30);
    expect(begun.cancel(), isTrue);
    expect(requestedAlbum, same(album));
    expect(offset, 30);
    expect(size, 30);
    expect(operation.cancelCalls, 1);
  });
}

class _ImmediateOperation implements AlbumTrackPageLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<AlbumTrackPageResult> run() async =>
      const AlbumTrackPageResult(failure: AlbumTrackFailure.cancelled);
}
