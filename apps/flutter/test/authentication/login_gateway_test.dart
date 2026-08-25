import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';

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
}

class _FakeVault implements CredentialVault {
  _FakeVault({this.result, this.error, this.deleteError});

  final Uint8List? result;
  final Object? error;
  final Object? deleteError;
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
