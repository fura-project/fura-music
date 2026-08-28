import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

void main() {
  test('maps a bounded personalized playlist list and valid absence', () {
    final available = mapBridgePersonalizedPlaylists(
      const bridge.QqMusicPersonalizedPlaylistsLoad(
        playlists: [
          bridge_library.LibraryPlaylistSummary(
            isLikedSongs: false,
            providerId: 'qq-music',
            opaqueId: 'catalog:91001',
            title: 'Personalized playlist',
            artworkUri: 'https://example.invalid/personalized.jpg',
          ),
        ],
      ),
    );
    expect(available.failure, isNull);
    expect(available.playlists.single.opaqueId, 'catalog:91001');
    expect(available.playlists.single.title, 'Personalized playlist');

    final absent = mapBridgePersonalizedPlaylists(
      const bridge.QqMusicPersonalizedPlaylistsLoad(playlists: []),
    );
    expect(absent.failure, isNull);
    expect(absent.playlists, isEmpty);
  });

  test('maps every Bridge failure and rejects contradictory content', () {
    final expected = {
      bridge.QqMusicPersonalizedPlaylistsLoadFailure.coreUnavailable:
          PersonalizedPlaylistsFailure.coreUnavailable,
      bridge.QqMusicPersonalizedPlaylistsLoadFailure.authenticationRequired:
          PersonalizedPlaylistsFailure.authenticationRequired,
      bridge.QqMusicPersonalizedPlaylistsLoadFailure.credentialRejected:
          PersonalizedPlaylistsFailure.credentialRejected,
      bridge.QqMusicPersonalizedPlaylistsLoadFailure.network:
          PersonalizedPlaylistsFailure.network,
      bridge.QqMusicPersonalizedPlaylistsLoadFailure.serviceUnavailable:
          PersonalizedPlaylistsFailure.serviceUnavailable,
      bridge.QqMusicPersonalizedPlaylistsLoadFailure.invalidResponse:
          PersonalizedPlaylistsFailure.invalidResponse,
      bridge.QqMusicPersonalizedPlaylistsLoadFailure.replaced:
          PersonalizedPlaylistsFailure.replaced,
      bridge.QqMusicPersonalizedPlaylistsLoadFailure.cancelled:
          PersonalizedPlaylistsFailure.cancelled,
      bridge.QqMusicPersonalizedPlaylistsLoadFailure.alreadyRunning:
          PersonalizedPlaylistsFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgePersonalizedPlaylistsFailure(input), output);
    }

    final conflict = mapBridgePersonalizedPlaylists(
      const bridge.QqMusicPersonalizedPlaylistsLoad(
        playlists: [
          bridge_library.LibraryPlaylistSummary(
            isLikedSongs: false,
            providerId: 'qq-music',
            opaqueId: 'catalog:1',
            title: 'must not coexist',
          ),
        ],
        failure: bridge.QqMusicPersonalizedPlaylistsLoadFailure.network,
      ),
    );
    expect(conflict.failure, PersonalizedPlaylistsFailure.invalidResponse);
    expect(conflict.playlists, isEmpty);
  });

  test('rejects malformed or duplicate playlist summaries', () {
    for (final playlists in [
      const [
        bridge_library.LibraryPlaylistSummary(
          isLikedSongs: false,
          providerId: ' ',
          opaqueId: 'catalog:1',
          title: 'Playlist',
        ),
      ],
      const [
        bridge_library.LibraryPlaylistSummary(
          isLikedSongs: false,
          providerId: 'qq-music',
          opaqueId: 'catalog:1',
          title: ' ',
        ),
      ],
      const [
        bridge_library.LibraryPlaylistSummary(
          isLikedSongs: false,
          providerId: 'qq-music',
          opaqueId: 'catalog:1',
          title: 'One',
        ),
        bridge_library.LibraryPlaylistSummary(
          isLikedSongs: false,
          providerId: 'qq-music',
          opaqueId: 'catalog:1',
          title: 'Duplicate',
        ),
      ],
    ]) {
      expect(
        mapBridgePersonalizedPlaylists(
          bridge.QqMusicPersonalizedPlaylistsLoad(playlists: playlists),
        ).failure,
        PersonalizedPlaylistsFailure.invalidResponse,
      );
    }
  });

  test('forwards cancellation and cleans vault only on rejection', () async {
    final rejectedVault = _FakeVault();
    final rejectedOperation = _ImmediateOperation(
      const PersonalizedPlaylistsResult(
        failure: PersonalizedPlaylistsFailure.credentialRejected,
      ),
    );
    final rejected = RustPersonalizedPlaylistsGateway(
      credentialVault: rejectedVault,
      operationFactory: () => rejectedOperation,
    );
    final begun = rejected.beginLoad();
    expect(begun.cancel(), isTrue);
    expect(rejectedOperation.cancelCalls, 1);
    expect(
      (await begun.run()).failure,
      PersonalizedPlaylistsFailure.credentialRejected,
    );
    expect(rejectedVault.deleteCalls, 1);

    final transientVault = _FakeVault();
    await RustPersonalizedPlaylistsGateway(
      credentialVault: transientVault,
      operationFactory: () => _ImmediateOperation(
        const PersonalizedPlaylistsResult(
          failure: PersonalizedPlaylistsFailure.network,
        ),
      ),
    ).beginLoad().run();
    expect(transientVault.deleteCalls, 0);

    final failingVault = _FakeVault(
      deleteError: StateError('synthetic vault failure'),
    );
    final cleanupFailure = await RustPersonalizedPlaylistsGateway(
      credentialVault: failingVault,
      operationFactory: () => _ImmediateOperation(
        const PersonalizedPlaylistsResult(
          failure: PersonalizedPlaylistsFailure.credentialRejected,
        ),
      ),
    ).beginLoad().run();
    expect(
      cleanupFailure.failure,
      PersonalizedPlaylistsFailure.credentialRejectedStorageCleanupFailed,
    );
    expect(failingVault.deleteCalls, 1);
  });
}

class _ImmediateOperation implements PersonalizedPlaylistsLoadOperation {
  _ImmediateOperation(this.result);

  final PersonalizedPlaylistsResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<PersonalizedPlaylistsResult> run() async => result;
}

class _FakeVault implements CredentialVault {
  _FakeVault({this.deleteError});

  final Object? deleteError;
  int deleteCalls = 0;

  @override
  Future<void> delete() async {
    deleteCalls += 1;
    final error = deleteError;
    if (error != null) throw error;
  }

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List secretBytes) async {}
}
