import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/authentication/qq_session_continuation.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart' as bridge;

void main() {
  test('stages verifies publishes commits and then removes stage', () async {
    final current = _MemoryVault()..value = Uint8List.fromList(<int>[1]);
    final staged = _MemoryVault();
    final vault = SerializedCredentialVault(current, stagedVault: staged);
    var verificationCalls = 0;
    var commitCalls = 0;
    final coordinator = QqSessionContinuationCoordinator(
      vault,
      prepareAfterReadRejection: () async => bridge.QqMusicRefreshPreparation(
        reservationId: 7,
        stagedSecretBytes: Uint8List.fromList(<int>[2]),
        reusedNewGeneration: false,
      ),
      verify: ({required reservationId}) async {
        expect(reservationId, 7);
        verificationCalls++;
        expect(await staged.read(), orderedEquals(<int>[2]));
        return bridge.QqMusicRefreshVerification(
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
    expect(verificationCalls, 1);
    expect(commitCalls, 1);
    expect(await current.read(), orderedEquals(<int>[3]));
    expect(await staged.read(), isNull);
  });

  test('current publication failure leaves stage and never commits', () async {
    final current = _MemoryVault()
      ..value = Uint8List.fromList(<int>[1])
      ..failWrites = true;
    final staged = _MemoryVault();
    final vault = SerializedCredentialVault(current, stagedVault: staged);
    var commitCalls = 0;
    var abortCalls = 0;
    final coordinator = QqSessionContinuationCoordinator(
      vault,
      prepareAfterReadRejection: () async => bridge.QqMusicRefreshPreparation(
        reservationId: 8,
        stagedSecretBytes: Uint8List.fromList(<int>[2]),
        reusedNewGeneration: false,
      ),
      verify: ({required reservationId}) async =>
          bridge.QqMusicRefreshVerification(
            currentSecretBytes: Uint8List.fromList(<int>[3]),
          ),
      commit: ({required reservationId}) {
        commitCalls++;
        return null;
      },
      abort: ({required reservationId}) {
        abortCalls++;
        return null;
      },
    );

    expect(
      await coordinator.continueAfterReadRejection(),
      QqSessionContinuationResult.temporarilyUnavailable,
    );
    expect(commitCalls, 0);
    expect(abortCalls, 1);
    expect(await current.read(), orderedEquals(<int>[1]));
    expect(await staged.read(), orderedEquals(<int>[2]));
  });

  test('stage write failure never verifies or installs candidate', () async {
    final current = _MemoryVault()..value = Uint8List.fromList(<int>[1]);
    final staged = _MemoryVault()..failWrites = true;
    final vault = SerializedCredentialVault(current, stagedVault: staged);
    var verifyCalls = 0;
    var commitCalls = 0;
    final coordinator = QqSessionContinuationCoordinator(
      vault,
      prepareAfterReadRejection: () async => bridge.QqMusicRefreshPreparation(
        reservationId: 81,
        stagedSecretBytes: Uint8List.fromList(<int>[2]),
        reusedNewGeneration: false,
      ),
      verify: ({required reservationId}) async {
        verifyCalls++;
        return const bridge.QqMusicRefreshVerification();
      },
      commit: ({required reservationId}) {
        commitCalls++;
        return null;
      },
      abort: ({required reservationId}) => null,
    );

    expect(
      await coordinator.continueAfterReadRejection(),
      QqSessionContinuationResult.temporarilyUnavailable,
    );
    expect(verifyCalls, 0);
    expect(commitCalls, 0);
    expect(await current.read(), orderedEquals(<int>[1]));
    expect(await staged.read(), isNull);
  });

  test('commit failure keeps published current and staged recovery', () async {
    final current = _MemoryVault()..value = Uint8List.fromList(<int>[1]);
    final staged = _MemoryVault();
    final vault = SerializedCredentialVault(current, stagedVault: staged);
    final coordinator = QqSessionContinuationCoordinator(
      vault,
      prepareAfterReadRejection: () async => bridge.QqMusicRefreshPreparation(
        reservationId: 82,
        stagedSecretBytes: Uint8List.fromList(<int>[2]),
        reusedNewGeneration: false,
      ),
      verify: ({required reservationId}) async =>
          bridge.QqMusicRefreshVerification(
            currentSecretBytes: Uint8List.fromList(<int>[2]),
          ),
      commit: ({required reservationId}) =>
          bridge.QqMusicRefreshFailure.replaced,
      abort: ({required reservationId}) => null,
    );

    expect(
      await coordinator.continueAfterReadRejection(),
      QqSessionContinuationResult.replaced,
    );
    expect(await current.read(), orderedEquals(<int>[2]));
    expect(await staged.read(), orderedEquals(<int>[2]));
  });

  test('replacement epoch wins while verification is pending', () async {
    final current = _MemoryVault()..value = Uint8List.fromList(<int>[1]);
    final staged = _MemoryVault();
    final vault = SerializedCredentialVault(current, stagedVault: staged);
    final releaseVerification = Completer<void>();
    var commitCalls = 0;
    final coordinator = QqSessionContinuationCoordinator(
      vault,
      prepareAfterReadRejection: () async => bridge.QqMusicRefreshPreparation(
        reservationId: 9,
        stagedSecretBytes: Uint8List.fromList(<int>[2]),
        reusedNewGeneration: false,
      ),
      verify: ({required reservationId}) async {
        await releaseVerification.future;
        return bridge.QqMusicRefreshVerification(
          currentSecretBytes: Uint8List.fromList(<int>[3]),
        );
      },
      commit: ({required reservationId}) {
        commitCalls++;
        return null;
      },
      abort: ({required reservationId}) => null,
    );

    final continuation = coordinator.continueAfterReadRejection();
    await Future<void>.delayed(Duration.zero);
    await vault.publishReplacement(Uint8List.fromList(<int>[9]));
    releaseVerification.complete();

    expect(await continuation, QqSessionContinuationResult.replaced);
    expect(commitCalls, 0);
    expect(await current.read(), orderedEquals(<int>[9]));
    expect(await staged.read(), isNull);
  });

  test(
    'disabled production gate requires reauthentication after rejection',
    () async {
      final current = _MemoryVault()..value = Uint8List.fromList(<int>[1]);
      final staged = _MemoryVault()..value = Uint8List.fromList(<int>[2]);
      final vault = SerializedCredentialVault(current, stagedVault: staged);
      final coordinator = QqSessionContinuationCoordinator(
        vault,
        prepareAfterReadRejection: () async =>
            const bridge.QqMusicRefreshPreparation(
              reusedNewGeneration: false,
              failure: bridge.QqMusicRefreshFailure.productionGateDisabled,
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

  test(
    'disabled checkpoint never erases an otherwise recoverable session',
    () async {
      final current = _MemoryVault()..value = Uint8List.fromList(<int>[1]);
      final staged = _MemoryVault()..value = Uint8List.fromList(<int>[2]);
      final vault = SerializedCredentialVault(current, stagedVault: staged);
      var rejectionPrepareCalls = 0;
      final coordinator = QqSessionContinuationCoordinator(
        vault,
        prepareAfterReadRejection: () async {
          rejectionPrepareCalls++;
          return const bridge.QqMusicRefreshPreparation(
            reusedNewGeneration: false,
            failure: bridge.QqMusicRefreshFailure.productionGateDisabled,
          );
        },
        prepareCheckpoint: () async => const bridge.QqMusicRefreshPreparation(
          reusedNewGeneration: false,
          failure: bridge.QqMusicRefreshFailure.productionGateDisabled,
        ),
      );

      expect(
        await coordinator.checkpoint(),
        QqSessionContinuationResult.notNeeded,
      );
      expect(rejectionPrepareCalls, 0);
      expect(await current.read(), orderedEquals(<int>[1]));
      expect(await staged.read(), orderedEquals(<int>[2]));
    },
  );

  test(
    'checkpoint recovers a retained stage before preparing refresh',
    () async {
      final vault = SerializedCredentialVault(
        _MemoryVault(),
        stagedVault: _MemoryVault(),
      );
      var prepareCalls = 0;
      var recoveryCalls = 0;
      final coordinator = QqSessionContinuationCoordinator(
        vault,
        recoverStagedCredential: () async {
          recoveryCalls++;
          return StagedCredentialRecoveryResult.recovered;
        },
        prepareCheckpoint: () async {
          prepareCalls++;
          return const bridge.QqMusicRefreshPreparation(
            reusedNewGeneration: false,
            failure: bridge.QqMusicRefreshFailure.notDue,
          );
        },
      );

      expect(
        await coordinator.checkpoint(),
        QqSessionContinuationResult.continued,
      );
      expect(recoveryCalls, 1);
      expect(prepareCalls, 0);
    },
  );

  test(
    'checkpoint prepares refresh only when no retained stage exists',
    () async {
      final vault = SerializedCredentialVault(
        _MemoryVault(),
        stagedVault: _MemoryVault(),
      );
      var prepareCalls = 0;
      final coordinator = QqSessionContinuationCoordinator(
        vault,
        recoverStagedCredential: () async =>
            StagedCredentialRecoveryResult.notNeeded,
        prepareCheckpoint: () async {
          prepareCalls++;
          return const bridge.QqMusicRefreshPreparation(
            reusedNewGeneration: false,
            failure: bridge.QqMusicRefreshFailure.notDue,
          );
        },
      );

      expect(
        await coordinator.checkpoint(),
        QqSessionContinuationResult.notNeeded,
      );
      expect(prepareCalls, 1);
    },
  );

  test(
    'read rejection and resume checkpoints serialize as one owner',
    () async {
      final vault = SerializedCredentialVault(
        _MemoryVault(),
        stagedVault: _MemoryVault(),
      );
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var checkpointPrepareCalls = 0;
      final coordinator = QqSessionContinuationCoordinator(
        vault,
        recoverStagedCredential: () async =>
            StagedCredentialRecoveryResult.notNeeded,
        prepareAfterReadRejection: () async {
          firstStarted.complete();
          await releaseFirst.future;
          return const bridge.QqMusicRefreshPreparation(
            reusedNewGeneration: true,
          );
        },
        prepareCheckpoint: () async {
          checkpointPrepareCalls++;
          return const bridge.QqMusicRefreshPreparation(
            reusedNewGeneration: false,
            failure: bridge.QqMusicRefreshFailure.notDue,
          );
        },
      );

      final rejection = coordinator.continueAfterReadRejection();
      await firstStarted.future;
      final checkpoint = coordinator.checkpoint();
      await pumpEventQueue();
      expect(checkpointPrepareCalls, 0);

      releaseFirst.complete();
      expect(await rejection, QqSessionContinuationResult.continued);
      expect(await checkpoint, QqSessionContinuationResult.notNeeded);
      expect(checkpointPrepareCalls, 1);
    },
  );

  test(
    'repeated resume checkpoints serialize and leave no orphan stage',
    () async {
      final current = _MemoryVault()..value = Uint8List.fromList(<int>[1]);
      final staged = _MemoryVault();
      final vault = SerializedCredentialVault(current, stagedVault: staged);
      var prepareCalls = 0;
      var activePreparations = 0;
      var maximumActivePreparations = 0;
      var verificationCalls = 0;
      var commitCalls = 0;
      final coordinator = QqSessionContinuationCoordinator(
        vault,
        recoverStagedCredential: () async =>
            StagedCredentialRecoveryResult.notNeeded,
        prepareCheckpoint: () async {
          final call = prepareCalls++;
          activePreparations++;
          if (activePreparations > maximumActivePreparations) {
            maximumActivePreparations = activePreparations;
          }
          await Future<void>.delayed(Duration.zero);
          activePreparations--;
          return call == 0
              ? bridge.QqMusicRefreshPreparation(
                  reservationId: 17,
                  stagedSecretBytes: Uint8List.fromList(<int>[2]),
                  reusedNewGeneration: false,
                )
              : const bridge.QqMusicRefreshPreparation(
                  reusedNewGeneration: false,
                  failure: bridge.QqMusicRefreshFailure.notDue,
                );
        },
        verify: ({required reservationId}) async {
          expect(reservationId, 17);
          verificationCalls++;
          return bridge.QqMusicRefreshVerification(
            currentSecretBytes: Uint8List.fromList(<int>[3]),
          );
        },
        commit: ({required reservationId}) {
          expect(reservationId, 17);
          commitCalls++;
          return null;
        },
        abort: ({required reservationId}) => null,
      );

      final results = await Future.wait(
        List<Future<QqSessionContinuationResult>>.generate(
          32,
          (_) => coordinator.checkpoint(),
        ),
      );

      expect(
        results.where(
          (result) => result == QqSessionContinuationResult.continued,
        ),
        hasLength(1),
      );
      expect(
        results.where(
          (result) => result == QqSessionContinuationResult.notNeeded,
        ),
        hasLength(31),
      );
      expect(maximumActivePreparations, 1);
      expect(verificationCalls, 1);
      expect(commitCalls, 1);
      expect(await current.read(), orderedEquals(<int>[3]));
      expect(await staged.read(), isNull);
    },
  );
}

class _MemoryVault implements CredentialVault {
  Uint8List? value;
  bool failWrites = false;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<Uint8List?> read() async =>
      value == null ? null : Uint8List.fromList(value!);

  @override
  Future<void> write(Uint8List secretBytes) async {
    if (failWrites) throw StateError('synthetic write failure');
    value = Uint8List.fromList(secretBytes);
  }
}
