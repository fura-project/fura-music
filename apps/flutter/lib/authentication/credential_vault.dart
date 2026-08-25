import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CredentialVault {
  Future<void> write(Uint8List secretBytes);

  Future<Uint8List?> read();

  Future<void> delete();
}

abstract interface class SecureStringStore {
  Future<void> write({required String key, required String value});

  Future<String?> read({required String key});

  Future<void> delete({required String key});
}

/// Orders every operation for one credential key so an old rejection cleanup
/// cannot overtake a newer credential write.
class SerializedCredentialVault implements CredentialVault {
  SerializedCredentialVault(this._inner);

  final CredentialVault _inner;
  Future<void> _tail = Future<void>.value();

  @override
  Future<void> delete() => _enqueue(_inner.delete);

  @override
  Future<Uint8List?> read() => _enqueue(_inner.read);

  @override
  Future<void> write(Uint8List secretBytes) =>
      _enqueue(() => _inner.write(secretBytes));

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

class FlutterSecureStringStore implements SecureStringStore {
  FlutterSecureStringStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: false,
              storageNamespace: 'flutterustmusic_auth',
            ),
            iOptions: IOSOptions(
              accountName: 'dev.axiaobo.flutterustmusic',
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
              label: 'QQ Music session',
            ),
            mOptions: MacOsOptions(
              accountName: 'dev.axiaobo.flutterustmusic',
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
              label: 'QQ Music session',
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

class PlatformCredentialVault implements CredentialVault {
  PlatformCredentialVault({SecureStringStore? store})
    : _store = store ?? FlutterSecureStringStore();

  static const _credentialKey = 'qq_music_credential_v1';

  final SecureStringStore _store;

  @override
  Future<void> write(Uint8List secretBytes) =>
      _store.write(key: _credentialKey, value: base64Encode(secretBytes));

  @override
  Future<Uint8List?> read() async {
    final value = await _store.read(key: _credentialKey);
    return value == null ? null : base64Decode(value);
  }

  @override
  Future<void> delete() => _store.delete(key: _credentialKey);
}
