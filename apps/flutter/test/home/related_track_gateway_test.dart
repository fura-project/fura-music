import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge_artist;
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

void main() {
  test('maps an immutable related Track list and valid absence', () {
    final available = mapBridgeRelatedTracks(
      const bridge.QqMusicRelatedTracksLoad(
        tracks: [
          bridge_library.LibraryTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:51001:0:fixture-related-mid:-',
            title: 'Synthetic related Track',
            artistNames: ['Synthetic artist'],
            artists: [
              bridge_artist.CatalogArtistSummary(
                providerId: 'qq-music',
                opaqueId: 'artist:52001:fixtureArtistMid',
                name: 'Synthetic artist',
              ),
            ],
            albumTitle: 'Synthetic album',
            durationSeconds: 245,
          ),
        ],
      ),
    );
    expect(available.failure, isNull);
    expect(available.tracks.single.title, 'Synthetic related Track');
    expect(() => available.tracks.clear(), throwsUnsupportedError);

    final absent = mapBridgeRelatedTracks(
      const bridge.QqMusicRelatedTracksLoad(tracks: []),
    );
    expect(absent.failure, isNull);
    expect(absent.tracks, isEmpty);
  });

  test('maps every Bridge failure and rejects contradictory content', () {
    final expected = {
      bridge.QqMusicRelatedTracksLoadFailure.coreUnavailable:
          RelatedTracksFailure.coreUnavailable,
      bridge.QqMusicRelatedTracksLoadFailure.invalidTrack:
          RelatedTracksFailure.invalidTrack,
      bridge.QqMusicRelatedTracksLoadFailure.network:
          RelatedTracksFailure.network,
      bridge.QqMusicRelatedTracksLoadFailure.serviceUnavailable:
          RelatedTracksFailure.serviceUnavailable,
      bridge.QqMusicRelatedTracksLoadFailure.invalidResponse:
          RelatedTracksFailure.invalidResponse,
      bridge.QqMusicRelatedTracksLoadFailure.cancelled:
          RelatedTracksFailure.cancelled,
      bridge.QqMusicRelatedTracksLoadFailure.alreadyRunning:
          RelatedTracksFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeRelatedTracksFailure(input), output);
    }

    final conflict = mapBridgeRelatedTracks(
      const bridge.QqMusicRelatedTracksLoad(
        tracks: [
          bridge_library.LibraryTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'opaque',
            title: 'must not coexist',
            artistNames: [],
            artists: [],
          ),
        ],
        failure: bridge.QqMusicRelatedTracksLoadFailure.network,
      ),
    );
    expect(conflict.failure, RelatedTracksFailure.invalidResponse);
    expect(conflict.tracks, isEmpty);
  });

  test('rejects malformed and duplicate Track summaries', () {
    final malformed = mapBridgeRelatedTracks(
      const bridge.QqMusicRelatedTracksLoad(
        tracks: [
          bridge_library.LibraryTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'opaque',
            title: 'Synthetic',
            artistNames: [' '],
            artists: [],
          ),
        ],
      ),
    );
    expect(malformed.failure, RelatedTracksFailure.invalidResponse);

    const track = bridge_library.LibraryTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:51001:0:fixture-related-mid:-',
      title: 'Synthetic',
      artistNames: ['Artist'],
      artists: [],
    );
    final duplicate = mapBridgeRelatedTracks(
      const bridge.QqMusicRelatedTracksLoad(tracks: [track, track]),
    );
    expect(duplicate.failure, RelatedTracksFailure.invalidResponse);
  });

  test('forwards the exact seed and cancellation', () async {
    const seed = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:50001:0:seed-mid:-',
      title: 'Seed',
      artistNames: ['Artist'],
    );
    final operation = _ImmediateOperation(const RelatedTracksResult());
    late PlaylistTrackSummary captured;
    final gateway = RustRelatedTracksGateway(
      operationFactory: (seed) {
        captured = seed;
        return operation;
      },
    );

    final begun = gateway.beginLoad(seed);
    expect(captured, same(seed));
    expect(begun.cancel(), isTrue);
    expect(operation.cancelCalls, 1);
    expect((await begun.run()).failure, isNull);
  });
}

class _ImmediateOperation implements RelatedTracksLoadOperation {
  _ImmediateOperation(this.result);

  final RelatedTracksResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<RelatedTracksResult> run() async => result;
}
