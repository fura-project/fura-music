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

  test(
    'keeps QQ Music and NetEase credentials in separate vault keys',
    () async {
      final store = _MemorySecureStringStore();
      final qq = PlatformCredentialVault(
        store: store,
        credentialKey: PlatformCredentialVault.qqMusicCredentialKey,
      );
      final netease = PlatformCredentialVault(
        store: store,
        credentialKey: PlatformCredentialVault.netEaseCredentialKey,
      );

      await qq.write(Uint8List.fromList(<int>[1, 2, 3]));
      await netease.write(Uint8List.fromList(<int>[7, 8, 9]));
      await qq.delete();

      expect(await qq.read(), isNull);
      expect(await netease.read(), orderedEquals(<int>[7, 8, 9]));
      expect(store.values.keys, [PlatformCredentialVault.netEaseCredentialKey]);
    },
  );

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

  test(
    'rotation epoch makes logout and replacement dominate stale writes',
    () async {
      final current = _MemoryCredentialVault();
      final staged = _MemoryCredentialVault();
      final vault = SerializedCredentialVault(current, stagedVault: staged);
      await vault.publishReplacement(Uint8List.fromList(<int>[1]));

      final refreshEpoch = vault.reserveRotation();
      expect(
        await vault.stageIfCurrent(refreshEpoch, Uint8List.fromList(<int>[2])),
        isTrue,
      );
      await vault.publishReplacement(Uint8List.fromList(<int>[9]));

      expect(
        await vault.publishIfCurrent(
          refreshEpoch,
          Uint8List.fromList(<int>[2]),
        ),
        isFalse,
      );
      expect(await current.read(), orderedEquals(<int>[9]));
      expect(await staged.read(), isNull);

      final logoutEpoch = vault.reserveRotation();
      expect(await vault.deleteTransactionIfCurrent(logoutEpoch), isTrue);
      expect(await current.read(), isNull);
      expect(await staged.read(), isNull);
    },
  );

  test('publication failure retains the staged recovery document', () async {
    final current = _MemoryCredentialVault()..failWrites = true;
    final staged = _MemoryCredentialVault();
    final vault = SerializedCredentialVault(current, stagedVault: staged);
    final epoch = vault.reserveRotation();

    await vault.stageIfCurrent(epoch, Uint8List.fromList(<int>[2]));

    expect(
      vault.publishIfCurrent(epoch, Uint8List.fromList(<int>[3])),
      throwsStateError,
    );
    expect(await staged.read(), orderedEquals(<int>[2]));
  });

  test('legacy write and delete still own both transaction slots', () async {
    final current = _MemoryCredentialVault()
      ..value = Uint8List.fromList(<int>[1]);
    final staged = _MemoryCredentialVault()
      ..value = Uint8List.fromList(<int>[2]);
    final vault = SerializedCredentialVault(current, stagedVault: staged);

    await vault.write(Uint8List.fromList(<int>[3]));
    expect(await current.read(), orderedEquals(<int>[3]));
    expect(await staged.read(), isNull);

    staged.value = Uint8List.fromList(<int>[4]);
    await vault.delete();
    expect(await current.read(), isNull);
    expect(await staged.read(), isNull);
  });

  test('failed stage read zeroes the already-loaded current bytes', () async {
    final currentBytes = Uint8List.fromList(<int>[1, 2, 3]);
    final vault = SerializedCredentialVault(
      _BorrowingCredentialVault(currentBytes),
      stagedVault: const _FailingReadCredentialVault(),
    );

    await expectLater(vault.readTransaction(), throwsA(isA<FormatException>()));
    expect(currentBytes, everyElement(0));
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

class _MemoryCredentialVault implements CredentialVault {
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

class _BorrowingCredentialVault implements CredentialVault {
  const _BorrowingCredentialVault(this.value);

  final Uint8List value;

  @override
  Future<void> delete() async {}

  @override
  Future<Uint8List?> read() async => value;

  @override
  Future<void> write(Uint8List secretBytes) async {}
}

class _FailingReadCredentialVault implements CredentialVault {
  const _FailingReadCredentialVault();

  @override
  Future<void> delete() async {}

  @override
  Future<Uint8List?> read() async =>
      throw const FormatException('malformed staged storage');

  @override
  Future<void> write(Uint8List secretBytes) async {}
}
