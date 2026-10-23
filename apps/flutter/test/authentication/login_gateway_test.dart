import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/authentication/netease_official_web_login.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart' as bridge;

void main() {
  test('imports vault bytes once and zeroes the mutable buffer', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    Uint8List? imported;
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: _FakeVault(result: bytes),
      credentialImporter: (secretBytes) {
        imported = secretBytes;
        expect(secretBytes, orderedEquals(<int>[1, 2, 3, 4]));
        return CredentialRestoreResult.verificationRequired;
      },
    );

    final result = await gateway.restoreCredential();

    expect(result, CredentialRestoreResult.verificationRequired);
    expect(imported, same(bytes));
    expect(bytes, everyElement(0));
  });

  test('maps malformed vault encoding without calling Rust', () async {
    var importCalls = 0;
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: _FakeVault(error: const FormatException('invalid')),
      credentialImporter: (_) {
        importCalls += 1;
        return CredentialRestoreResult.signedOut;
      },
    );

    expect(
      await gateway.restoreCredential(),
      CredentialRestoreResult.invalidStoredCredential,
    );
    expect(importCalls, 0);
  });

  test('keeps platform access failures distinct from corrupt data', () async {
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: _FakeVault(error: StateError('vault unavailable')),
      credentialImporter: (_) => CredentialRestoreResult.signedOut,
    );

    expect(
      await gateway.restoreCredential(),
      CredentialRestoreResult.storageUnavailable,
    );
  });

  test('maps a bridge failure and still zeroes loaded bytes', () async {
    final bytes = Uint8List.fromList(<int>[9, 8, 7]);
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: _FakeVault(result: bytes),
      credentialImporter: (_) => throw StateError('core unavailable'),
    );

    expect(
      await gateway.restoreCredential(),
      CredentialRestoreResult.coreUnavailable,
    );
    expect(bytes, everyElement(0));
  });

  test('removes secure storage only after an explicit rejection', () async {
    final vault = _FakeVault();
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: vault,
      verificationOperationFactory: () =>
          _FakeVerificationOperation(CredentialVerificationResult.rejected),
    );

    final result = await gateway.beginCredentialVerification().run();

    expect(result, CredentialVerificationResult.rejected);
    expect(vault.deleteCalls, 1);
  });

  test(
    'retains secure storage after a transient verification failure',
    () async {
      final vault = _FakeVault();
      final gateway = RustQqMusicAuthenticationGateway(
        credentialVault: vault,
        verificationOperationFactory: () =>
            _FakeVerificationOperation(CredentialVerificationResult.network),
      );

      final result = await gateway.beginCredentialVerification().run();

      expect(result, CredentialVerificationResult.network);
      expect(vault.deleteCalls, 0);
    },
  );

  test('reports rejected credentials whose vault cleanup fails', () async {
    final vault = _FakeVault(deleteError: StateError('vault unavailable'));
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: vault,
      verificationOperationFactory: () =>
          _FakeVerificationOperation(CredentialVerificationResult.rejected),
    );

    final result = await gateway.beginCredentialVerification().run();

    expect(result, CredentialVerificationResult.rejectedStorageCleanupFailed);
    expect(vault.deleteCalls, 1);
  });

  test('serializes rejection cleanup before later vault access', () async {
    final vault = _GatedDeleteVault();
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: vault,
      credentialImporter: (_) => CredentialRestoreResult.signedOut,
      verificationOperationFactory: () => const _FakeVerificationOperation(
        CredentialVerificationResult.rejected,
      ),
    );

    final verification = gateway.beginCredentialVerification().run();
    await vault.deleteStarted.future;
    final restore = gateway.restoreCredential();
    await pumpEventQueue();
    expect(vault.events, <String>['delete-start']);

    vault.releaseDelete.complete();
    expect(await verification, CredentialVerificationResult.rejected);
    expect(await restore, CredentialRestoreResult.signedOut);
    expect(vault.events, <String>['delete-start', 'delete-end', 'read']);
  });

  test('sign out clears Rust before deleting the serialized vault', () async {
    final events = <String>[];
    final vault = _FakeVault(events: events);
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: vault,
      credentialSignOutCore: () {
        events.add('core');
        return true;
      },
    );

    final result = await gateway.signOut();

    expect(result, CredentialSignOutResult.signedOut);
    expect(events, ['core', 'vault']);
    expect(vault.deleteCalls, 1);
  });

  test('sign out retains the vault when the Rust core cannot clear', () async {
    final vault = _FakeVault();
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: vault,
      credentialSignOutCore: () => false,
    );

    expect(await gateway.signOut(), CredentialSignOutResult.coreUnavailable);
    expect(vault.deleteCalls, 0);
  });

  test('sign out reports a vault cleanup failure after Rust cleared', () async {
    final vault = _FakeVault(deleteError: StateError('vault unavailable'));
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: vault,
      credentialSignOutCore: () => true,
    );

    expect(
      await gateway.signOut(),
      CredentialSignOutResult.storageCleanupFailed,
    );
    expect(vault.deleteCalls, 1);
  });

  test(
    'startup publishes a verified staged candidate before cleanup',
    () async {
      final current = _MemoryVault(Uint8List.fromList(<int>[1]));
      final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
      final vault = SerializedCredentialVault(current, stagedVault: staged);
      final gateway = RustQqMusicAuthenticationGateway(
        credentialVault: vault,
        credentialRotationRestorer:
            ({required currentSecretBytes, required stagedSecretBytes}) {
              expect(currentSecretBytes, orderedEquals(<int>[1]));
              expect(stagedSecretBytes, orderedEquals(<int>[2]));
              return const bridge.QqMusicStagedRecovery(
                action: bridge.QqMusicStagedRecoveryAction.verifyCandidate,
              );
            },
        verificationOperationFactory: () => const _FakeVerificationOperation(
          CredentialVerificationResult.authenticated,
        ),
        credentialExporter: () => bridge.QqMusicCredentialExport(
          secretBytes: Uint8List.fromList(<int>[2]),
        ),
      );

      expect(
        await gateway.restoreCredential(),
        CredentialRestoreResult.verificationRequired,
      );
      expect(
        await gateway.beginCredentialVerification().run(),
        CredentialVerificationResult.authenticated,
      );
      expect(await current.read(), orderedEquals(<int>[2]));
      expect(await staged.read(), isNull);
    },
  );

  test(
    'repeated restart restore sees only the converged current credential',
    () async {
      final current = _MemoryVault(Uint8List.fromList(<int>[1]));
      final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
      final vault = SerializedCredentialVault(current, stagedVault: staged);
      final firstGateway = RustQqMusicAuthenticationGateway(
        credentialVault: vault,
        credentialRotationRestorer:
            ({required currentSecretBytes, required stagedSecretBytes}) =>
                const bridge.QqMusicStagedRecovery(
                  action: bridge.QqMusicStagedRecoveryAction.verifyCandidate,
                ),
        verificationOperationFactory: () => const _FakeVerificationOperation(
          CredentialVerificationResult.authenticated,
        ),
        credentialExporter: () => bridge.QqMusicCredentialExport(
          secretBytes: Uint8List.fromList(<int>[2]),
        ),
      );

      expect(
        await firstGateway.restoreCredential(),
        CredentialRestoreResult.verificationRequired,
      );
      expect(
        await firstGateway.beginCredentialVerification().run(),
        CredentialVerificationResult.authenticated,
      );

      var stagedRecoveryCalls = 0;
      var currentRestoreCalls = 0;
      for (var restart = 0; restart < 16; restart++) {
        final restartedGateway = RustQqMusicAuthenticationGateway(
          credentialVault: vault,
          credentialRotationRestorer:
              ({required currentSecretBytes, required stagedSecretBytes}) {
                stagedRecoveryCalls++;
                return const bridge.QqMusicStagedRecovery(
                  action: bridge.QqMusicStagedRecoveryAction.stale,
                );
              },
          credentialImporter: (secretBytes) {
            currentRestoreCalls++;
            expect(secretBytes, orderedEquals(<int>[2]));
            return CredentialRestoreResult.verificationRequired;
          },
        );
        expect(
          await restartedGateway.restoreCredential(),
          CredentialRestoreResult.verificationRequired,
        );
      }

      expect(stagedRecoveryCalls, 0);
      expect(currentRestoreCalls, 16);
      expect(await current.read(), orderedEquals(<int>[2]));
      expect(await staged.read(), isNull);
    },
  );

  test('startup cleans a committed current plus matching stage', () async {
    final current = _MemoryVault(Uint8List.fromList(<int>[2]));
    final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
    var exportCalls = 0;
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: SerializedCredentialVault(current, stagedVault: staged),
      credentialRotationRestorer:
          ({required currentSecretBytes, required stagedSecretBytes}) =>
              const bridge.QqMusicStagedRecovery(
                action:
                    bridge.QqMusicStagedRecoveryAction.verifyCommittedCurrent,
              ),
      verificationOperationFactory: () => const _FakeVerificationOperation(
        CredentialVerificationResult.authenticated,
      ),
      credentialExporter: () {
        exportCalls++;
        return const bridge.QqMusicCredentialExport();
      },
    );

    expect(
      await gateway.restoreCredential(),
      CredentialRestoreResult.verificationRequired,
    );
    expect(
      await gateway.beginCredentialVerification().run(),
      CredentialVerificationResult.authenticated,
    );
    expect(exportCalls, 0);
    expect(await current.read(), orderedEquals(<int>[2]));
    expect(await staged.read(), isNull);
  });

  test('stale or malformed stage never replaces current', () async {
    for (final failure in <bridge.QqMusicCredentialRestoreFailure?>[
      null,
      bridge.QqMusicCredentialRestoreFailure.invalidDocument,
    ]) {
      final current = _MemoryVault(Uint8List.fromList(<int>[1]));
      final staged = _MemoryVault(Uint8List.fromList(<int>[9]));
      Uint8List? imported;
      final gateway = RustQqMusicAuthenticationGateway(
        credentialVault: SerializedCredentialVault(
          current,
          stagedVault: staged,
        ),
        credentialRotationRestorer:
            ({required currentSecretBytes, required stagedSecretBytes}) =>
                bridge.QqMusicStagedRecovery(
                  action: failure == null
                      ? bridge.QqMusicStagedRecoveryAction.stale
                      : null,
                  failure: failure,
                ),
        credentialImporter: (bytes) {
          imported = bytes == null ? null : Uint8List.fromList(bytes);
          return CredentialRestoreResult.verificationRequired;
        },
      );

      expect(
        await gateway.restoreCredential(),
        CredentialRestoreResult.verificationRequired,
      );
      expect(imported, orderedEquals(<int>[1]));
      expect(await current.read(), orderedEquals(<int>[1]));
      expect(await staged.read(), isNull);
    }
  });

  test(
    'malformed platform stage is discarded before restoring current',
    () async {
      final current = _MemoryVault(Uint8List.fromList(<int>[1]));
      final staged = _MemoryVault(Uint8List.fromList(<int>[2]))
        ..readError = const FormatException('malformed staged storage');
      Uint8List? imported;
      final gateway = RustQqMusicAuthenticationGateway(
        credentialVault: SerializedCredentialVault(
          current,
          stagedVault: staged,
        ),
        credentialImporter: (bytes) {
          imported = bytes == null ? null : Uint8List.fromList(bytes);
          return CredentialRestoreResult.verificationRequired;
        },
      );

      expect(
        await gateway.restoreCredential(),
        CredentialRestoreResult.verificationRequired,
      );
      expect(imported, orderedEquals(<int>[1]));
      expect(staged.value, isNull);
    },
  );

  test(
    'core-unavailable stage inspection retains both recovery slots',
    () async {
      final current = _MemoryVault(Uint8List.fromList(<int>[1]));
      final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
      final gateway = RustQqMusicAuthenticationGateway(
        credentialVault: SerializedCredentialVault(
          current,
          stagedVault: staged,
        ),
        credentialRotationRestorer:
            ({required currentSecretBytes, required stagedSecretBytes}) =>
                const bridge.QqMusicStagedRecovery(
                  failure:
                      bridge.QqMusicCredentialRestoreFailure.coreUnavailable,
                ),
      );

      expect(
        await gateway.restoreCredential(),
        CredentialRestoreResult.coreUnavailable,
      );
      expect(await current.read(), orderedEquals(<int>[1]));
      expect(await staged.read(), orderedEquals(<int>[2]));
    },
  );

  test(
    'orphan stage is removed without reviving a signed-out session',
    () async {
      final current = _MemoryVault();
      final staged = _MemoryVault(Uint8List.fromList(<int>[9]));
      final gateway = RustQqMusicAuthenticationGateway(
        credentialVault: SerializedCredentialVault(
          current,
          stagedVault: staged,
        ),
        credentialRotationRestorer:
            ({required currentSecretBytes, required stagedSecretBytes}) =>
                const bridge.QqMusicStagedRecovery(
                  action: bridge.QqMusicStagedRecoveryAction.stale,
                ),
        credentialImporter: (bytes) {
          expect(bytes, isNull);
          return CredentialRestoreResult.signedOut;
        },
      );

      expect(
        await gateway.restoreCredential(),
        CredentialRestoreResult.signedOut,
      );
      expect(await current.read(), isNull);
      expect(await staged.read(), isNull);
    },
  );

  test('transient staged verification retains both recovery slots', () async {
    final current = _MemoryVault(Uint8List.fromList(<int>[1]));
    final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: SerializedCredentialVault(current, stagedVault: staged),
      credentialRotationRestorer:
          ({required currentSecretBytes, required stagedSecretBytes}) =>
              const bridge.QqMusicStagedRecovery(
                action: bridge.QqMusicStagedRecoveryAction.verifyCandidate,
              ),
      verificationOperationFactory: () => const _FakeVerificationOperation(
        CredentialVerificationResult.network,
      ),
    );

    expect(
      await gateway.restoreCredential(),
      CredentialRestoreResult.verificationRequired,
    );
    expect(
      await gateway.beginCredentialVerification().run(),
      CredentialVerificationResult.network,
    );
    expect(await current.read(), orderedEquals(<int>[1]));
    expect(await staged.read(), orderedEquals(<int>[2]));
  });

  test('resume recovery retries a retained staged candidate', () async {
    final current = _MemoryVault(Uint8List.fromList(<int>[1]));
    final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
    var verificationCalls = 0;
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: SerializedCredentialVault(current, stagedVault: staged),
      credentialRotationRestorer:
          ({required currentSecretBytes, required stagedSecretBytes}) =>
              const bridge.QqMusicStagedRecovery(
                action: bridge.QqMusicStagedRecoveryAction.verifyCandidate,
              ),
      verificationOperationFactory: () => _FakeVerificationOperation(
        verificationCalls++ == 0
            ? CredentialVerificationResult.network
            : CredentialVerificationResult.authenticated,
      ),
      credentialExporter: () => bridge.QqMusicCredentialExport(
        secretBytes: Uint8List.fromList(<int>[2]),
      ),
    );

    expect(
      await gateway.restoreCredential(),
      CredentialRestoreResult.verificationRequired,
    );
    expect(
      await gateway.beginCredentialVerification().run(),
      CredentialVerificationResult.network,
    );
    expect(
      await gateway.recoverStagedCredentialIfPresent(),
      StagedCredentialRecoveryResult.recovered,
    );
    expect(verificationCalls, 2);
    expect(await current.read(), orderedEquals(<int>[2]));
    expect(await staged.read(), isNull);
  });

  test('resume recovery is a no-op when no stage exists', () async {
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: SerializedCredentialVault(
        _MemoryVault(Uint8List.fromList(<int>[1])),
        stagedVault: _MemoryVault(),
      ),
    );

    expect(
      await gateway.recoverStagedCredentialIfPresent(),
      StagedCredentialRecoveryResult.notNeeded,
    );
  });

  test('replacement invalidates an in-flight staged snapshot read', () async {
    final current = _MemoryVault(Uint8List.fromList(<int>[1]));
    final staged = _GatedReadVault(Uint8List.fromList(<int>[2]));
    final vault = SerializedCredentialVault(current, stagedVault: staged);
    var importerCalls = 0;
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: vault,
      credentialRotationRestorer:
          ({required currentSecretBytes, required stagedSecretBytes}) =>
              const bridge.QqMusicStagedRecovery(
                action: bridge.QqMusicStagedRecoveryAction.stale,
              ),
      credentialImporter: (_) {
        importerCalls++;
        return CredentialRestoreResult.verificationRequired;
      },
    );

    final restore = gateway.restoreCredential();
    await staged.readStarted.future;
    final replacement = vault.publishReplacement(Uint8List.fromList(<int>[9]));
    staged.releaseRead.complete();

    expect(await restore, CredentialRestoreResult.coreUnavailable);
    await replacement;
    expect(importerCalls, 0);
    expect(await current.read(), orderedEquals(<int>[9]));
    expect(await staged.read(), isNull);
  });

  test(
    'replacement wins while rejected candidate fallback is pending',
    () async {
      final current = _MemoryVault(Uint8List.fromList(<int>[1]));
      final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
      final vault = SerializedCredentialVault(current, stagedVault: staged);
      final verification = _GatedVerificationOperation(
        CredentialVerificationResult.rejected,
      );
      var verificationCalls = 0;
      var importerCalls = 0;
      final gateway = RustQqMusicAuthenticationGateway(
        credentialVault: vault,
        credentialRotationRestorer:
            ({required currentSecretBytes, required stagedSecretBytes}) =>
                const bridge.QqMusicStagedRecovery(
                  action: bridge.QqMusicStagedRecoveryAction.verifyCandidate,
                ),
        credentialImporter: (_) {
          importerCalls++;
          return CredentialRestoreResult.verificationRequired;
        },
        verificationOperationFactory: () => verificationCalls++ == 0
            ? verification
            : const _FakeVerificationOperation(
                CredentialVerificationResult.authenticated,
              ),
        credentialExporter: () => bridge.QqMusicCredentialExport(
          secretBytes: Uint8List.fromList(<int>[2]),
        ),
      );

      expect(
        await gateway.restoreCredential(),
        CredentialRestoreResult.verificationRequired,
      );
      final recovery = gateway.beginCredentialVerification().run();
      await verification.started.future;
      await vault.publishReplacement(Uint8List.fromList(<int>[9]));
      verification.release.complete();

      expect(await recovery, CredentialVerificationResult.replaced);
      expect(importerCalls, 0);
      expect(await current.read(), orderedEquals(<int>[9]));
      expect(await staged.read(), isNull);
      expect(
        await gateway.beginCredentialVerification().run(),
        CredentialVerificationResult.authenticated,
      );
      expect(verificationCalls, 2);
      expect(await current.read(), orderedEquals(<int>[9]));
    },
  );

  test('rejected staged candidate falls back to valid current', () async {
    final current = _MemoryVault(Uint8List.fromList(<int>[1]));
    final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
    var verificationCalls = 0;
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: SerializedCredentialVault(current, stagedVault: staged),
      credentialRotationRestorer:
          ({required currentSecretBytes, required stagedSecretBytes}) =>
              const bridge.QqMusicStagedRecovery(
                action: bridge.QqMusicStagedRecoveryAction.verifyCandidate,
              ),
      credentialImporter: (bytes) {
        expect(bytes, orderedEquals(<int>[1]));
        return CredentialRestoreResult.verificationRequired;
      },
      verificationOperationFactory: () => _FakeVerificationOperation(
        verificationCalls++ == 0
            ? CredentialVerificationResult.rejected
            : CredentialVerificationResult.authenticated,
      ),
    );

    expect(
      await gateway.restoreCredential(),
      CredentialRestoreResult.verificationRequired,
    );
    expect(
      await gateway.beginCredentialVerification().run(),
      CredentialVerificationResult.authenticated,
    );
    expect(verificationCalls, 2);
    expect(await current.read(), orderedEquals(<int>[1]));
    expect(await staged.read(), isNull);
  });

  test(
    'publication failure leaves the staged checkpoint recoverable',
    () async {
      final current = _MemoryVault(Uint8List.fromList(<int>[1]))
        ..failWrites = true;
      final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
      var recoveryCalls = 0;
      final gateway = RustQqMusicAuthenticationGateway(
        credentialVault: SerializedCredentialVault(
          current,
          stagedVault: staged,
        ),
        credentialRotationRestorer:
            ({required currentSecretBytes, required stagedSecretBytes}) {
              recoveryCalls++;
              return const bridge.QqMusicStagedRecovery(
                action: bridge.QqMusicStagedRecoveryAction.verifyCandidate,
              );
            },
        verificationOperationFactory: () => const _FakeVerificationOperation(
          CredentialVerificationResult.authenticated,
        ),
        credentialExporter: () => bridge.QqMusicCredentialExport(
          secretBytes: Uint8List.fromList(<int>[2]),
        ),
      );

      expect(
        await gateway.restoreCredential(),
        CredentialRestoreResult.verificationRequired,
      );
      expect(
        await gateway.beginCredentialVerification().run(),
        CredentialVerificationResult.coreUnavailable,
      );
      expect(recoveryCalls, 2);
      expect(await current.read(), orderedEquals(<int>[1]));
      expect(await staged.read(), orderedEquals(<int>[2]));
    },
  );

  test('failed recovery reclassification still zeroes both buffers', () async {
    final current = _TrackingReadVault(Uint8List.fromList(<int>[1]))
      ..failWrites = true;
    final staged = _TrackingReadVault(Uint8List.fromList(<int>[2]));
    var recoveryCalls = 0;
    final gateway = RustQqMusicAuthenticationGateway(
      credentialVault: SerializedCredentialVault(current, stagedVault: staged),
      credentialRotationRestorer:
          ({required currentSecretBytes, required stagedSecretBytes}) {
            recoveryCalls++;
            if (recoveryCalls == 2) {
              throw StateError('synthetic reclassification failure');
            }
            return const bridge.QqMusicStagedRecovery(
              action: bridge.QqMusicStagedRecoveryAction.verifyCandidate,
            );
          },
      verificationOperationFactory: () => const _FakeVerificationOperation(
        CredentialVerificationResult.authenticated,
      ),
      credentialExporter: () => bridge.QqMusicCredentialExport(
        secretBytes: Uint8List.fromList(<int>[2]),
      ),
    );

    expect(
      await gateway.restoreCredential(),
      CredentialRestoreResult.verificationRequired,
    );
    expect(
      await gateway.beginCredentialVerification().run(),
      CredentialVerificationResult.coreUnavailable,
    );
    expect(recoveryCalls, 2);
    expect(current.lastRead, isNotNull);
    expect(staged.lastRead, isNotNull);
    expect(current.lastRead, everyElement(0));
    expect(staged.lastRead, everyElement(0));
  });

  test(
    'transactional sign out removes current and staged credentials',
    () async {
      final current = _MemoryVault(Uint8List.fromList(<int>[1]));
      final staged = _MemoryVault(Uint8List.fromList(<int>[2]));
      final gateway = RustQqMusicAuthenticationGateway(
        credentialVault: SerializedCredentialVault(
          current,
          stagedVault: staged,
        ),
        credentialSignOutCore: () => true,
      );

      expect(await gateway.signOut(), CredentialSignOutResult.signedOut);
      expect(await current.read(), isNull);
      expect(await staged.read(), isNull);
    },
  );

  test('NetEase sign out clears browser state before core and vault', () async {
    final events = <String>[];
    final vault = _FakeVault(events: events);
    final broker = _FakeOfficialWebBroker(events: events);
    final gateway = RustNeteaseAuthenticationGateway(
      credentialVault: vault,
      officialWebLoginBroker: broker,
      credentialSignOutCore: () {
        events.add('core');
        return true;
      },
    );

    expect(await gateway.signOut(), CredentialSignOutResult.signedOut);
    expect(events, ['browser', 'core', 'vault']);
    expect(broker.cancelCalls, 1);
    expect(broker.clearCalls, 1);
    expect(vault.deleteCalls, 1);
  });

  test('NetEase sign out reports website cleanup independently', () async {
    final vault = _FakeVault();
    final broker = _FakeOfficialWebBroker(clearResult: false);
    final gateway = RustNeteaseAuthenticationGateway(
      credentialVault: vault,
      officialWebLoginBroker: broker,
      credentialSignOutCore: () => true,
    );

    expect(
      await gateway.signOut(),
      CredentialSignOutResult.browserCleanupFailed,
    );
    expect(vault.deleteCalls, 1);
  });
}

class _FakeOfficialWebBroker extends ChangeNotifier
    implements OfficialWebLoginBroker {
  _FakeOfficialWebBroker({this.clearResult = true, this.events});

  final bool clearResult;
  final List<String>? events;
  int cancelCalls = 0;
  int clearCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Listenable get presentationListenable => this;

  @override
  OfficialWebLoginPresentationStage get presentationStage =>
      OfficialWebLoginPresentationStage.idle;

  @override
  Widget? get activeView => null;

  @override
  Future<Uint8List?> authenticate() async => null;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<bool> clearWebsiteData() async {
    clearCalls += 1;
    events?.add('browser');
    return clearResult;
  }
}

class _FakeVault implements CredentialVault {
  _FakeVault({this.result, this.error, this.deleteError, this.events});

  final Uint8List? result;
  final Object? error;
  final Object? deleteError;
  final List<String>? events;
  int deleteCalls = 0;

  @override
  Future<Uint8List?> read() async {
    final error = this.error;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<void> write(Uint8List secretBytes) async {}

  @override
  Future<void> delete() async {
    deleteCalls += 1;
    events?.add('vault');
    final deleteError = this.deleteError;
    if (deleteError != null) throw deleteError;
  }
}

class _FakeVerificationOperation implements CredentialVerificationOperation {
  const _FakeVerificationOperation(this.result);

  final CredentialVerificationResult result;

  @override
  bool cancel() => true;

  @override
  Future<CredentialVerificationResult> run() async => result;
}

class _GatedVerificationOperation implements CredentialVerificationOperation {
  _GatedVerificationOperation(this.result);

  final CredentialVerificationResult result;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  bool cancel() => true;

  @override
  Future<CredentialVerificationResult> run() async {
    started.complete();
    await release.future;
    return result;
  }
}

class _GatedDeleteVault implements CredentialVault {
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> releaseDelete = Completer<void>();
  final List<String> events = <String>[];

  @override
  Future<void> delete() async {
    events.add('delete-start');
    deleteStarted.complete();
    await releaseDelete.future;
    events.add('delete-end');
  }

  @override
  Future<Uint8List?> read() async {
    events.add('read');
    return null;
  }

  @override
  Future<void> write(Uint8List secretBytes) async {
    events.add('write');
  }
}

class _MemoryVault implements CredentialVault {
  _MemoryVault([this.value]);

  Uint8List? value;
  bool failWrites = false;
  Object? readError;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<Uint8List?> read() async {
    final error = readError;
    if (error != null) throw error;
    return value == null ? null : Uint8List.fromList(value!);
  }

  @override
  Future<void> write(Uint8List secretBytes) async {
    if (failWrites) throw StateError('synthetic write failure');
    value = Uint8List.fromList(secretBytes);
  }
}

class _TrackingReadVault extends _MemoryVault {
  _TrackingReadVault(super.value);

  Uint8List? lastRead;

  @override
  Future<Uint8List?> read() async {
    lastRead = await super.read();
    return lastRead;
  }
}

class _GatedReadVault extends _MemoryVault {
  _GatedReadVault(super.value);

  final Completer<void> readStarted = Completer<void>();
  final Completer<void> releaseRead = Completer<void>();
  var _gated = false;

  @override
  Future<Uint8List?> read() async {
    if (!_gated) {
      _gated = true;
      readStarted.complete();
      await releaseRead.future;
    }
    return super.read();
  }
}
