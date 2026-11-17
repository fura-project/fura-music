import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/authentication/netease_session_continuation.dart';
import 'package:flutterustmusic/authentication/qq_session_continuation.dart';
import 'package:flutterustmusic/src/rust/api/netease_authentication.dart'
    as bridge;

void main() {
  test(
    'stage verify publish commit and cleanup remain one transaction',
    () async {
      final current = _MemoryVault(Uint8List.fromList(<int>[1]));
      final staged = _MemoryVault();
      final vault = SerializedCredentialVault(current, stagedVault: staged);
      var verifyCalls = 0;
      var commitCalls = 0;
      final coordinator = NeteaseSessionContinuationCoordinator(
        vault,
        prepareAfterReadRejection: () async => bridge.NeteaseRefreshPreparation(
          reservationId: 7,
          stagedSecretBytes: Uint8List.fromList(<int>[2]),
          reusedNewGeneration: false,
        ),
        verify: ({required reservationId}) async {
          expect(reservationId, 7);
          expect(await staged.read(), orderedEquals(<int>[2]));
          verifyCalls++;
          return bridge.NeteaseRefreshVerification(
            currentSecretBytes: Uint8List.fromList(<int>[3]),
          );
        },
        commit: ({required reservationId}) {
          expect(reservationId, 7);
          commitCalls++;
          return null;
        },
        abort: ({required reservationId}) => null,
      );

      expect(
        await coordinator.continueAfterReadRejection(),
        QqSessionContinuationResult.continued,
      );
      expect(verifyCalls, 1);
      expect(commitCalls, 1);
      expect(await current.read(), orderedEquals(<int>[3]));
      expect(await staged.read(), isNull);
    },
  );

  test(
    'transient refresh failure preserves current and staged slots',
    () async {
      final current = _MemoryVault(Uint8List.fromList(<int>[1]));
      final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
      final vault = SerializedCredentialVault(current, stagedVault: staged);
      final coordinator = NeteaseSessionContinuationCoordinator(
        vault,
        prepareAfterReadRejection: () async =>
            const bridge.NeteaseRefreshPreparation(
              reusedNewGeneration: false,
              failure: bridge.NeteaseRefreshFailure.network,
            ),
      );

      expect(
        await coordinator.continueAfterReadRejection(),
        QqSessionContinuationResult.temporarilyUnavailable,
      );
      expect(await current.read(), orderedEquals(<int>[1]));
      expect(await staged.read(), orderedEquals(<int>[2]));
    },
  );

  test(
    'definitive nonrefreshable rejection removes exact transaction',
    () async {
      final current = _MemoryVault(Uint8List.fromList(<int>[1]));
      final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
      final vault = SerializedCredentialVault(current, stagedVault: staged);
      final coordinator = NeteaseSessionContinuationCoordinator(
        vault,
        prepareAfterReadRejection: () async =>
            const bridge.NeteaseRefreshPreparation(
              reusedNewGeneration: false,
              failure: bridge.NeteaseRefreshFailure.notRefreshable,
            ),
      );

      expect(
        await coordinator.continueAfterReadRejection(),
        QqSessionContinuationResult.reauthenticationRequired,
      );
      expect(await current.read(), isNull);
      expect(await staged.read(), isNull);
    },
  );

  test('resume checkpoint never erases a disabled active session', () async {
    final current = _MemoryVault(Uint8List.fromList(<int>[1]));
    final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
    final vault = SerializedCredentialVault(current, stagedVault: staged);
    final coordinator = NeteaseSessionContinuationCoordinator(
      vault,
      prepareCheckpoint: () async => const bridge.NeteaseRefreshPreparation(
        reusedNewGeneration: false,
        failure: bridge.NeteaseRefreshFailure.productionGateDisabled,
      ),
    );

    expect(
      await coordinator.checkpoint(),
      QqSessionContinuationResult.notNeeded,
    );
    expect(await current.read(), orderedEquals(<int>[1]));
    expect(await staged.read(), orderedEquals(<int>[2]));
  });

  test('staged recovery precedes a new checkpoint decision', () async {
    final vault = SerializedCredentialVault(
      _MemoryVault(),
      stagedVault: _MemoryVault(),
    );
    var prepareCalls = 0;
    final coordinator = NeteaseSessionContinuationCoordinator(
      vault,
      recoverStagedCredential: () async =>
          StagedCredentialRecoveryResult.recovered,
      prepareCheckpoint: () async {
        prepareCalls++;
        return const bridge.NeteaseRefreshPreparation(
          reusedNewGeneration: false,
          failure: bridge.NeteaseRefreshFailure.notDue,
        );
      },
    );

    expect(
      await coordinator.checkpoint(),
      QqSessionContinuationResult.continued,
    );
    expect(prepareCalls, 0);
  });

  test('read rejection and resume are serialized by one owner', () async {
    final vault = SerializedCredentialVault(
      _MemoryVault(),
      stagedVault: _MemoryVault(),
    );
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var checkpointCalls = 0;
    final coordinator = NeteaseSessionContinuationCoordinator(
      vault,
      recoverStagedCredential: () async =>
          StagedCredentialRecoveryResult.notNeeded,
      prepareAfterReadRejection: () async {
        firstStarted.complete();
        await releaseFirst.future;
        return const bridge.NeteaseRefreshPreparation(
          reusedNewGeneration: true,
        );
      },
      prepareCheckpoint: () async {
        checkpointCalls++;
        return const bridge.NeteaseRefreshPreparation(
          reusedNewGeneration: false,
          failure: bridge.NeteaseRefreshFailure.notDue,
        );
      },
    );

    final rejection = coordinator.continueAfterReadRejection();
    await firstStarted.future;
    final checkpoint = coordinator.checkpoint();
    await pumpEventQueue();
    expect(checkpointCalls, 0);
    releaseFirst.complete();
    expect(await rejection, QqSessionContinuationResult.continued);
    expect(await checkpoint, QqSessionContinuationResult.notNeeded);
    expect(checkpointCalls, 1);
  });
}

class _MemoryVault implements CredentialVault {
  _MemoryVault([this.value]);

  Uint8List? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<Uint8List?> read() async =>
      value == null ? null : Uint8List.fromList(value!);

  @override
  Future<void> write(Uint8List secretBytes) async =>
      value = Uint8List.fromList(secretBytes);
}
