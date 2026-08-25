import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/library_gateway.dart';

void main() {
  test('deletes the vault only after explicit library rejection', () async {
    final vault = _FakeVault();
    final gateway = RustUserLibraryGateway(
      credentialVault: vault,
      operationFactory: () => const _ImmediateLoad(
        UserLibraryResult(failure: UserLibraryFailure.credentialRejected),
      ),
    );

    final result = await gateway.beginLoad().run();

    expect(result.failure, UserLibraryFailure.credentialRejected);
    expect(vault.deleteCalls, 1);
  });

  test('retains the vault after a transient library failure', () async {
    final vault = _FakeVault();
    final gateway = RustUserLibraryGateway(
      credentialVault: vault,
      operationFactory: () => const _ImmediateLoad(
        UserLibraryResult(failure: UserLibraryFailure.network),
      ),
    );

    final result = await gateway.beginLoad().run();

    expect(result.failure, UserLibraryFailure.network);
    expect(vault.deleteCalls, 0);
  });

  test('reports rejected credentials whose cleanup fails', () async {
    final vault = _FakeVault(deleteError: StateError('vault unavailable'));
    final gateway = RustUserLibraryGateway(
      credentialVault: vault,
      operationFactory: () => const _ImmediateLoad(
        UserLibraryResult(failure: UserLibraryFailure.credentialRejected),
      ),
    );

    final result = await gateway.beginLoad().run();

    expect(
      result.failure,
      UserLibraryFailure.credentialRejectedStorageCleanupFailed,
    );
    expect(vault.deleteCalls, 1);
  });
}

class _ImmediateLoad implements UserLibraryLoadOperation {
  const _ImmediateLoad(this.result);

  final UserLibraryResult result;

  @override
  bool cancel() => true;

  @override
  Future<UserLibraryResult> run() async => result;
}

class _FakeVault implements CredentialVault {
  _FakeVault({this.deleteError});

  final Object? deleteError;
  int deleteCalls = 0;

  @override
  Future<void> delete() async {
    deleteCalls += 1;
    final deleteError = this.deleteError;
    if (deleteError != null) throw deleteError;
  }

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List secretBytes) async {}
}
