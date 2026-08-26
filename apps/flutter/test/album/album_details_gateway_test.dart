import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge;
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge_artist;

void main() {
  const expectedAlbum = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'album:-:fixtureAlbumMid',
    title: 'Summary title',
  );

  test('maps canonical Album metadata and every coarse failure', () {
    final result = mapBridgeAlbumDetails(
      const bridge.QqMusicAlbumDetailsLoad(
        details: bridge.CatalogAlbumDetails(
          album: bridge.CatalogAlbumSummary(
            providerId: 'qq-music',
            opaqueId: 'album:43001:fixtureAlbumMid',
            title: 'Canonical title',
            artworkUri: 'https://example.invalid/album.jpg',
          ),
          artists: [
            bridge_artist.CatalogArtistSummary(
              providerId: 'qq-music',
              opaqueId: 'artist:42001:fixtureArtistMid',
              name: 'Canonical artist',
            ),
          ],
          subtitle: 'Canonical subtitle',
          releaseDate: '2026-08-26',
          description: 'Canonical description',
          language: 'Canonical language',
          albumType: 'Canonical type',
          genre: 'Canonical genre',
          company: 'Canonical company',
        ),
      ),
      expectedAlbum,
    );

    expect(result.failure, isNull);
    expect(result.details?.album.title, 'Canonical title');
    expect(result.details?.album.opaqueId, 'album:43001:fixtureAlbumMid');
    expect(result.details?.artists.single.name, 'Canonical artist');
    expect(result.details?.description, 'Canonical description');

    final expected = {
      bridge.QqMusicAlbumDetailsLoadFailure.coreUnavailable:
          AlbumDetailsFailure.coreUnavailable,
      bridge.QqMusicAlbumDetailsLoadFailure.network:
          AlbumDetailsFailure.network,
      bridge.QqMusicAlbumDetailsLoadFailure.serviceUnavailable:
          AlbumDetailsFailure.serviceUnavailable,
      bridge.QqMusicAlbumDetailsLoadFailure.invalidResponse:
          AlbumDetailsFailure.invalidResponse,
      bridge.QqMusicAlbumDetailsLoadFailure.cancelled:
          AlbumDetailsFailure.cancelled,
      bridge.QqMusicAlbumDetailsLoadFailure.alreadyRunning:
          AlbumDetailsFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeAlbumDetailsFailure(input), output);
    }
  });

  test('rejects missing, conflicting, or malformed detail content', () {
    final missing = mapBridgeAlbumDetails(
      const bridge.QqMusicAlbumDetailsLoad(),
      expectedAlbum,
    );
    expect(missing.failure, AlbumDetailsFailure.invalidResponse);

    final conflicting = mapBridgeAlbumDetails(
      const bridge.QqMusicAlbumDetailsLoad(
        details: bridge.CatalogAlbumDetails(
          album: bridge.CatalogAlbumSummary(
            providerId: 'qq-music',
            opaqueId: 'album:43001:fixtureAlbumMid',
            title: 'Canonical title',
          ),
          artists: [],
        ),
        failure: bridge.QqMusicAlbumDetailsLoadFailure.network,
      ),
      expectedAlbum,
    );
    expect(conflicting.failure, AlbumDetailsFailure.invalidResponse);

    final malformed = mapBridgeAlbumDetails(
      const bridge.QqMusicAlbumDetailsLoad(
        details: bridge.CatalogAlbumDetails(
          album: bridge.CatalogAlbumSummary(
            providerId: 'local',
            opaqueId: 'album:43001:fixtureAlbumMid',
            title: 'Canonical title',
          ),
          artists: [],
          description: '   ',
        ),
      ),
      expectedAlbum,
    );
    expect(malformed.failure, AlbumDetailsFailure.invalidResponse);
  });

  test('forwards opaque Album identity and cancellation unchanged', () {
    late AlbumSummary forwarded;
    final operation = _ImmediateOperation();
    final gateway = RustAlbumDetailsGateway(
      operationFactory: (album) {
        forwarded = album;
        return operation;
      },
    );

    final begun = gateway.beginLoad(expectedAlbum);
    expect(begun.cancel(), isTrue);
    expect(forwarded, same(expectedAlbum));
    expect(operation.cancelCalls, 1);
  });
}

class _ImmediateOperation implements AlbumDetailsLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<AlbumDetailsResult> run() async =>
      const AlbumDetailsResult(failure: AlbumDetailsFailure.cancelled);
}
