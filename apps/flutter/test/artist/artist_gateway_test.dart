import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge;
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;

void main() {
  const artist = ArtistSummary(
    providerId: 'qq-music',
    opaqueId: 'artist:61001:fixtureArtistMid',
    name: 'Synthetic artist',
  );

  test('maps a valid Bridge Artist page into presentation-safe Tracks', () {
    final result = mapBridgeArtistTrackPage(
      const bridge.QqMusicArtistTrackPageLoad(
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
              bridge.CatalogArtistSummary(
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
  });

  test('maps failures and rejects success data beside a failure', () {
    final expected = {
      bridge.QqMusicArtistTrackPageLoadFailure.coreUnavailable:
          ArtistTrackFailure.coreUnavailable,
      bridge.QqMusicArtistTrackPageLoadFailure.network:
          ArtistTrackFailure.network,
      bridge.QqMusicArtistTrackPageLoadFailure.serviceUnavailable:
          ArtistTrackFailure.serviceUnavailable,
      bridge.QqMusicArtistTrackPageLoadFailure.invalidResponse:
          ArtistTrackFailure.invalidResponse,
      bridge.QqMusicArtistTrackPageLoadFailure.cancelled:
          ArtistTrackFailure.cancelled,
      bridge.QqMusicArtistTrackPageLoadFailure.alreadyRunning:
          ArtistTrackFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeArtistTrackFailure(input), output);
    }

    final conflict = mapBridgeArtistTrackPage(
      const bridge.QqMusicArtistTrackPageLoad(
        offset: 0,
        total: 1,
        hasMore: false,
        tracks: [],
        failure: bridge.QqMusicArtistTrackPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, ArtistTrackFailure.invalidResponse);
  });

  test('forwards provider identity, paging, and cancellation', () {
    late ArtistSummary requestedArtist;
    late int offset;
    late int size;
    final operation = _ImmediateOperation();
    final gateway = RustArtistTrackGateway(
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

class _ImmediateOperation implements ArtistTrackPageLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<ArtistTrackPageResult> run() async =>
      const ArtistTrackPageResult(failure: ArtistTrackFailure.cancelled);
}
