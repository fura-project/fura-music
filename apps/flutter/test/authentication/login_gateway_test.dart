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
}

class _FakeVault implements CredentialVault {
  _FakeVault({this.result, this.error});

  final Uint8List? result;
  final Object? error;

  @override
  Future<Uint8List?> read() async {
    final error = this.error;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<void> write(Uint8List secretBytes) async {}

  @override
  Future<void> delete() async {}
}
