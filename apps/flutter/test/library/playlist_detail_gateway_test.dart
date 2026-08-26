import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge_album;
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge;

void main() {
  const playlist = UserPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'favorite:8001',
    title: 'Synthetic playlist',
  );

  test('deletes the vault only after explicit detail rejection', () async {
    final vault = _FakeVault();
    final gateway = RustPlaylistDetailGateway(
      credentialVault: vault,
      operationFactory: (_, _, _) => const _ImmediateDetailLoad(
        PlaylistTrackPageResult(failure: UserLibraryFailure.credentialRejected),
      ),
    );
    final result = await gateway
        .beginLoad(playlist: playlist, offset: 0, size: 100)
        .run();
    expect(result.failure, UserLibraryFailure.credentialRejected);
    expect(vault.deleteCalls, 1);
  });

  test('retains vault after transient detail failure', () async {
    final vault = _FakeVault();
    final gateway = RustPlaylistDetailGateway(
      credentialVault: vault,
      operationFactory: (_, _, _) => const _ImmediateDetailLoad(
        PlaylistTrackPageResult(failure: UserLibraryFailure.network),
      ),
    );
    await gateway.beginLoad(playlist: playlist, offset: 0, size: 100).run();
    expect(vault.deleteCalls, 0);
  });

  test('maps validated Album context and rejects malformed identity', () {
    final mapped = mapBridgeLibraryTrackSummary(
      const bridge.LibraryTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:fixtureTrackMid:-',
        title: 'Synthetic Track',
        artistNames: ['Synthetic Artist'],
        albumTitle: 'Synthetic Album',
        album: bridge_album.CatalogAlbumSummary(
          providerId: 'qq-music',
          opaqueId: 'album:43001:fixtureAlbumMid',
          title: 'Synthetic Album',
        ),
      ),
    );

    expect(mapped?.album?.opaqueId, 'album:43001:fixtureAlbumMid');
    expect(
      mapBridgeLibraryTrackSummary(
        const bridge.LibraryTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:41001:0:fixtureTrackMid:-',
          title: 'Synthetic Track',
          artistNames: ['Synthetic Artist'],
          album: bridge_album.CatalogAlbumSummary(
            providerId: 'qq-music',
            opaqueId: '',
            title: 'Synthetic Album',
          ),
        ),
      ),
      isNull,
    );
    expect(
      mapBridgeLibraryTrackSummary(
        const bridge.LibraryTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:41001:0:fixtureTrackMid:-',
          title: 'Synthetic Track',
          artistNames: ['Synthetic Artist'],
          album: bridge_album.CatalogAlbumSummary(
            providerId: 'local',
            opaqueId: 'album:foreign',
            title: 'Synthetic Album',
          ),
        ),
      ),
      isNull,
    );
  });
}

class _ImmediateDetailLoad implements PlaylistTrackPageLoadOperation {
  const _ImmediateDetailLoad(this.result);
  final PlaylistTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async => result;
}

class _FakeVault implements CredentialVault {
  int deleteCalls = 0;

  @override
  Future<void> delete() async => deleteCalls += 1;

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List secretBytes) async {}
}
