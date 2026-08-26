import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

void main() {
  test('maps a valid Radar page into immutable presentation Tracks', () {
    final result = mapBridgeRadarTrackPage(
      const bridge.QqMusicRadarTrackPageLoad(
        page: 2,
        hasMore: true,
        tracks: [
          bridge_library.LibraryTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:41001:0:fixture-mid:-',
            title: 'Synthetic Radar Track',
            artistNames: ['Synthetic artist'],
            albumTitle: 'Synthetic album',
            durationSeconds: 245,
          ),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.page, 2);
    expect(result.hasMore, isTrue);
    expect(result.tracks.single.title, 'Synthetic Radar Track');
    expect(result.tracks.single.artistNames, ['Synthetic artist']);
    expect(() => result.tracks.clear(), throwsUnsupportedError);
    expect(
      () => result.tracks.single.artistNames.clear(),
      throwsUnsupportedError,
    );
  });

  test('maps every Bridge failure and rejects contradictory data', () {
    final expected = {
      bridge.QqMusicRadarTrackPageLoadFailure.coreUnavailable:
          RadarFailure.coreUnavailable,
      bridge.QqMusicRadarTrackPageLoadFailure.authenticationRequired:
          RadarFailure.authenticationRequired,
      bridge.QqMusicRadarTrackPageLoadFailure.credentialRejected:
          RadarFailure.credentialRejected,
      bridge.QqMusicRadarTrackPageLoadFailure.network: RadarFailure.network,
      bridge.QqMusicRadarTrackPageLoadFailure.serviceUnavailable:
          RadarFailure.serviceUnavailable,
      bridge.QqMusicRadarTrackPageLoadFailure.invalidResponse:
          RadarFailure.invalidResponse,
      bridge.QqMusicRadarTrackPageLoadFailure.replaced: RadarFailure.replaced,
      bridge.QqMusicRadarTrackPageLoadFailure.cancelled: RadarFailure.cancelled,
      bridge.QqMusicRadarTrackPageLoadFailure.alreadyRunning:
          RadarFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeRadarFailure(input), output);
    }

    final conflict = mapBridgeRadarTrackPage(
      const bridge.QqMusicRadarTrackPageLoad(
        page: 0,
        hasMore: false,
        tracks: [
          bridge_library.LibraryTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'opaque',
            title: 'must not coexist',
            artistNames: [],
          ),
        ],
        failure: bridge.QqMusicRadarTrackPageLoadFailure.network,
      ),
    );
    expect(conflict.failure, RadarFailure.invalidResponse);
  });

  test('rejects invalid pagination and malformed Track fields', () {
    final invalidPages = [
      const bridge.QqMusicRadarTrackPageLoad(
        page: 0,
        hasMore: false,
        tracks: [],
      ),
      const bridge.QqMusicRadarTrackPageLoad(
        page: 1,
        hasMore: true,
        tracks: [],
      ),
      const bridge.QqMusicRadarTrackPageLoad(
        page: 1,
        hasMore: false,
        tracks: [
          bridge_library.LibraryTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'opaque',
            title: 'Synthetic',
            artistNames: [' '],
          ),
        ],
      ),
    ];
    for (final result in invalidPages) {
      expect(
        mapBridgeRadarTrackPage(result).failure,
        RadarFailure.invalidResponse,
      );
    }
  });

  test('forwards the exact page and cancellation', () {
    late int page;
    final operation = _ImmediateOperation(
      const RadarTrackPageResult(failure: RadarFailure.cancelled),
    );
    final gateway = RustRadarGateway(
      credentialVault: _FakeVault(),
      operationFactory: (inputPage) {
        page = inputPage;
        return operation;
      },
    );

    final begun = gateway.beginLoad(page: 3);
    expect(begun.cancel(), isTrue);
    expect(page, 3);
    expect(operation.cancelCalls, 1);
  });

  test('deletes the shared vault only after explicit rejection', () async {
    final rejectedVault = _FakeVault();
    final rejected = RustRadarGateway(
      credentialVault: rejectedVault,
      operationFactory: (_) => _ImmediateOperation(
        const RadarTrackPageResult(failure: RadarFailure.credentialRejected),
      ),
    );
    final rejectedResult = await rejected.beginLoad(page: 1).run();
    expect(rejectedResult.failure, RadarFailure.credentialRejected);
    expect(rejectedVault.deleteCalls, 1);

    final transientVault = _FakeVault();
    final transient = RustRadarGateway(
      credentialVault: transientVault,
      operationFactory: (_) => _ImmediateOperation(
        const RadarTrackPageResult(failure: RadarFailure.network),
      ),
    );
    await transient.beginLoad(page: 1).run();
    expect(transientVault.deleteCalls, 0);

    final failingVault = _FakeVault(
      deleteError: StateError('synthetic vault failure'),
    );
    final cleanupFailure = RustRadarGateway(
      credentialVault: failingVault,
      operationFactory: (_) => _ImmediateOperation(
        const RadarTrackPageResult(failure: RadarFailure.credentialRejected),
      ),
    );
    final cleanupResult = await cleanupFailure.beginLoad(page: 1).run();
    expect(
      cleanupResult.failure,
      RadarFailure.credentialRejectedStorageCleanupFailed,
    );
    expect(failingVault.deleteCalls, 1);
  });
}

class _ImmediateOperation implements RadarTrackPageLoadOperation {
  _ImmediateOperation(this.result);

  final RadarTrackPageResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<RadarTrackPageResult> run() async => result;
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
