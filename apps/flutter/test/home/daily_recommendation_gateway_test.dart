import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/home/daily_recommendation_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/recommendations.dart' as bridge;

void main() {
  test('maps an optional valid Daily 30 playlist', () {
    final available = mapBridgeDailyRecommendation(
      const bridge.QqMusicDailyRecommendationLoad(
        playlist: bridge_library.LibraryPlaylistSummary(
          isLikedSongs: false,
          providerId: 'qq-music',
          opaqueId: 'catalog:7251579717',
          title: 'Daily 30',
          artworkUri: 'https://example.invalid/daily.jpg',
        ),
      ),
    );
    expect(available.failure, isNull);
    expect(available.playlist?.opaqueId, 'catalog:7251579717');
    expect(available.playlist?.title, 'Daily 30');
    expect(
      available.playlist?.toPlaylistSummary().opaqueId,
      'catalog:7251579717',
    );

    final absent = mapBridgeDailyRecommendation(
      const bridge.QqMusicDailyRecommendationLoad(),
    );
    expect(absent.failure, isNull);
    expect(absent.playlist, isNull);
  });

  test('maps every Bridge failure and rejects contradictory content', () {
    final expected = {
      bridge.QqMusicDailyRecommendationLoadFailure.coreUnavailable:
          DailyRecommendationFailure.coreUnavailable,
      bridge.QqMusicDailyRecommendationLoadFailure.authenticationRequired:
          DailyRecommendationFailure.authenticationRequired,
      bridge.QqMusicDailyRecommendationLoadFailure.credentialRejected:
          DailyRecommendationFailure.credentialRejected,
      bridge.QqMusicDailyRecommendationLoadFailure.network:
          DailyRecommendationFailure.network,
      bridge.QqMusicDailyRecommendationLoadFailure.serviceUnavailable:
          DailyRecommendationFailure.serviceUnavailable,
      bridge.QqMusicDailyRecommendationLoadFailure.invalidResponse:
          DailyRecommendationFailure.invalidResponse,
      bridge.QqMusicDailyRecommendationLoadFailure.replaced:
          DailyRecommendationFailure.replaced,
      bridge.QqMusicDailyRecommendationLoadFailure.cancelled:
          DailyRecommendationFailure.cancelled,
      bridge.QqMusicDailyRecommendationLoadFailure.alreadyRunning:
          DailyRecommendationFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeDailyRecommendationFailure(input), output);
    }

    final conflict = mapBridgeDailyRecommendation(
      const bridge.QqMusicDailyRecommendationLoad(
        playlist: bridge_library.LibraryPlaylistSummary(
          isLikedSongs: false,
          providerId: 'qq-music',
          opaqueId: 'catalog:1',
          title: 'must not coexist',
        ),
        failure: bridge.QqMusicDailyRecommendationLoadFailure.network,
      ),
    );
    expect(conflict.failure, DailyRecommendationFailure.invalidResponse);
    expect(conflict.playlist, isNull);
  });

  test('rejects malformed playlist fields', () {
    for (final playlist in [
      const bridge_library.LibraryPlaylistSummary(
        isLikedSongs: false,
        providerId: ' ',
        opaqueId: 'catalog:1',
        title: 'Daily',
      ),
      const bridge_library.LibraryPlaylistSummary(
        isLikedSongs: false,
        providerId: 'qq-music',
        opaqueId: '',
        title: 'Daily',
      ),
      const bridge_library.LibraryPlaylistSummary(
        isLikedSongs: false,
        providerId: 'qq-music',
        opaqueId: 'catalog:1',
        title: ' ',
      ),
      const bridge_library.LibraryPlaylistSummary(
        isLikedSongs: false,
        providerId: 'qq-music',
        opaqueId: 'catalog:1',
        title: 'Daily',
        artworkUri: ' ',
      ),
    ]) {
      expect(
        mapBridgeDailyRecommendation(
          bridge.QqMusicDailyRecommendationLoad(playlist: playlist),
        ).failure,
        DailyRecommendationFailure.invalidResponse,
      );
    }
  });

  test(
    'forwards cancellation and cleans the vault only on rejection',
    () async {
      final rejectedVault = _FakeVault();
      final rejectedOperation = _ImmediateOperation(
        const DailyRecommendationResult(
          failure: DailyRecommendationFailure.credentialRejected,
        ),
      );
      final rejected = RustDailyRecommendationGateway(
        credentialVault: rejectedVault,
        operationFactory: () => rejectedOperation,
      );
      final begun = rejected.beginLoad();
      expect(begun.cancel(), isTrue);
      expect(rejectedOperation.cancelCalls, 1);
      expect(
        (await begun.run()).failure,
        DailyRecommendationFailure.credentialRejected,
      );
      expect(rejectedVault.deleteCalls, 1);

      final transientVault = _FakeVault();
      final transient = RustDailyRecommendationGateway(
        credentialVault: transientVault,
        operationFactory: () => _ImmediateOperation(
          const DailyRecommendationResult(
            failure: DailyRecommendationFailure.network,
          ),
        ),
      );
      await transient.beginLoad().run();
      expect(transientVault.deleteCalls, 0);

      final failingVault = _FakeVault(
        deleteError: StateError('synthetic vault failure'),
      );
      final cleanupFailure = RustDailyRecommendationGateway(
        credentialVault: failingVault,
        operationFactory: () => _ImmediateOperation(
          const DailyRecommendationResult(
            failure: DailyRecommendationFailure.credentialRejected,
          ),
        ),
      );
      expect(
        (await cleanupFailure.beginLoad().run()).failure,
        DailyRecommendationFailure.credentialRejectedStorageCleanupFailed,
      );
      expect(failingVault.deleteCalls, 1);
    },
  );
}

class _ImmediateOperation implements DailyRecommendationLoadOperation {
  _ImmediateOperation(this.result);

  final DailyRecommendationResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<DailyRecommendationResult> run() async => result;
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
