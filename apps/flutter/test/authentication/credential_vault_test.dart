import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';

void main() {
  test(
    'round-trips opaque credential bytes through one namespaced key',
    () async {
      final store = _MemorySecureStringStore();
      final vault = PlatformCredentialVault(store: store);
      final secret = Uint8List.fromList(<int>[0, 1, 2, 127, 128, 255]);

      await vault.write(secret);

      expect(store.values, hasLength(1));
      expect(store.values.values.single, base64Encode(secret));
      expect(await vault.read(), orderedEquals(secret));
    },
  );

  test('returns null when no credential is stored', () async {
    final vault = PlatformCredentialVault(store: _MemorySecureStringStore());

    expect(await vault.read(), isNull);
  });

  test('rejects a malformed stored payload instead of guessing', () async {
    final store = _MemorySecureStringStore();
    final vault = PlatformCredentialVault(store: store);
    await store.write(key: 'qq_music_credential_v1', value: 'not base64%%%');

    expect(vault.read(), throwsA(isA<FormatException>()));
  });

  test('deletes the stored credential', () async {
    final store = _MemorySecureStringStore();
    final vault = PlatformCredentialVault(store: store);
    await vault.write(Uint8List.fromList(<int>[1, 2, 3]));

    await vault.delete();

    expect(await vault.read(), isNull);
  });

  test('orders operations shared by independently wrapped gateways', () async {
    final inner = _GatedCredentialVault();
    final shared = SerializedCredentialVault(inner);
    final authenticationVault = SerializedCredentialVault(shared);
    final libraryVault = SerializedCredentialVault(shared);

    final staleRejectionCleanup = libraryVault.delete();
    await inner.deleteStarted.future;
    final freshLoginWrite = authenticationVault.write(
      Uint8List.fromList(<int>[4, 5, 6]),
    );

    await Future<void>.delayed(Duration.zero);
    expect(inner.events, <String>['delete-start']);

    inner.allowDelete.complete();
    await Future.wait(<Future<void>>[staleRejectionCleanup, freshLoginWrite]);

    expect(inner.events, <String>['delete-start', 'delete-end', 'write']);
    expect(inner.value, orderedEquals(<int>[4, 5, 6]));
  });
}

class _MemorySecureStringStore implements SecureStringStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class _GatedCredentialVault implements CredentialVault {
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> allowDelete = Completer<void>();
  final List<String> events = <String>[];
  Uint8List? value;

  @override
  Future<void> delete() async {
    events.add('delete-start');
    deleteStarted.complete();
    await allowDelete.future;
    value = null;
    events.add('delete-end');
  }

  @override
  Future<Uint8List?> read() async => value;

  @override
  Future<void> write(Uint8List secretBytes) async {
    value = Uint8List.fromList(secretBytes);
    events.add('write');
  }
}
