import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/home/personalized_track_gateway.dart';
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge_artist;
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

void main() {
  test('maps an immutable personalized Track list and valid absence', () {
    final available = mapBridgePersonalizedTracks(
      const bridge.QqMusicPersonalizedTracksLoad(
        tracks: [
          bridge_library.LibraryTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:41001:0:fixture-mid:-',
            title: 'Synthetic personalized Track',
            artistNames: ['Synthetic artist'],
            artists: [
              bridge_artist.CatalogArtistSummary(
                providerId: 'qq-music',
                opaqueId: 'artist:42001:fixtureArtistMid',
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
    expect(available.tracks.single.title, 'Synthetic personalized Track');
    expect(available.tracks.single.artistNames, ['Synthetic artist']);
    expect(() => available.tracks.clear(), throwsUnsupportedError);

    final absent = mapBridgePersonalizedTracks(
      const bridge.QqMusicPersonalizedTracksLoad(tracks: []),
    );
    expect(absent.failure, isNull);
    expect(absent.tracks, isEmpty);
  });

  test('maps every Bridge failure and rejects contradictory content', () {
    final expected = {
      bridge.QqMusicPersonalizedTracksLoadFailure.coreUnavailable:
          PersonalizedTracksFailure.coreUnavailable,
      bridge.QqMusicPersonalizedTracksLoadFailure.authenticationRequired:
          PersonalizedTracksFailure.authenticationRequired,
      bridge.QqMusicPersonalizedTracksLoadFailure.credentialRejected:
          PersonalizedTracksFailure.credentialRejected,
      bridge.QqMusicPersonalizedTracksLoadFailure.network:
          PersonalizedTracksFailure.network,
      bridge.QqMusicPersonalizedTracksLoadFailure.serviceUnavailable:
          PersonalizedTracksFailure.serviceUnavailable,
      bridge.QqMusicPersonalizedTracksLoadFailure.invalidResponse:
          PersonalizedTracksFailure.invalidResponse,
      bridge.QqMusicPersonalizedTracksLoadFailure.replaced:
          PersonalizedTracksFailure.replaced,
      bridge.QqMusicPersonalizedTracksLoadFailure.cancelled:
          PersonalizedTracksFailure.cancelled,
      bridge.QqMusicPersonalizedTracksLoadFailure.alreadyRunning:
          PersonalizedTracksFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgePersonalizedTracksFailure(input), output);
    }

    final conflict = mapBridgePersonalizedTracks(
      const bridge.QqMusicPersonalizedTracksLoad(
        tracks: [
          bridge_library.LibraryTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'opaque',
            title: 'must not coexist',
            artistNames: [],
            artists: [],
          ),
        ],
        failure: bridge.QqMusicPersonalizedTracksLoadFailure.network,
      ),
    );
    expect(conflict.failure, PersonalizedTracksFailure.invalidResponse);
    expect(conflict.tracks, isEmpty);
  });

  test('rejects malformed and duplicate Track summaries', () {
    final malformed = mapBridgePersonalizedTracks(
      const bridge.QqMusicPersonalizedTracksLoad(
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
    expect(malformed.failure, PersonalizedTracksFailure.invalidResponse);

    const track = bridge_library.LibraryTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:fixture-mid:-',
      title: 'Synthetic',
      artistNames: ['Artist'],
      artists: [],
    );
    final duplicate = mapBridgePersonalizedTracks(
      const bridge.QqMusicPersonalizedTracksLoad(tracks: [track, track]),
    );
    expect(duplicate.failure, PersonalizedTracksFailure.invalidResponse);
  });

  test('forwards cancellation and cleans vault only on rejection', () async {
    final rejectedVault = _FakeVault();
    final rejectedOperation = _ImmediateOperation(
      const PersonalizedTracksResult(
        failure: PersonalizedTracksFailure.credentialRejected,
      ),
    );
    final rejected = RustPersonalizedTracksGateway(
      credentialVault: rejectedVault,
      operationFactory: () => rejectedOperation,
    );
    final begun = rejected.beginLoad();
    expect(begun.cancel(), isTrue);
    expect(rejectedOperation.cancelCalls, 1);
    expect(
      (await begun.run()).failure,
      PersonalizedTracksFailure.credentialRejected,
    );
    expect(rejectedVault.deleteCalls, 1);

    final transientVault = _FakeVault();
    await RustPersonalizedTracksGateway(
      credentialVault: transientVault,
      operationFactory: () => _ImmediateOperation(
        const PersonalizedTracksResult(
          failure: PersonalizedTracksFailure.network,
        ),
      ),
    ).beginLoad().run();
    expect(transientVault.deleteCalls, 0);

    final failingVault = _FakeVault(
      deleteError: StateError('synthetic vault failure'),
    );
    final cleanupFailure = await RustPersonalizedTracksGateway(
      credentialVault: failingVault,
      operationFactory: () => _ImmediateOperation(
        const PersonalizedTracksResult(
          failure: PersonalizedTracksFailure.credentialRejected,
        ),
      ),
    ).beginLoad().run();
    expect(
      cleanupFailure.failure,
      PersonalizedTracksFailure.credentialRejectedStorageCleanupFailed,
    );
    expect(failingVault.deleteCalls, 1);
  });
}

class _ImmediateOperation implements PersonalizedTracksLoadOperation {
  _ImmediateOperation(this.result);

  final PersonalizedTracksResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<PersonalizedTracksResult> run() async => result;
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
