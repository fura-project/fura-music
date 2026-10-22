import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CredentialVault {
  Future<void> write(Uint8List secretBytes);

  Future<Uint8List?> read();

  Future<void> delete();
}

class CredentialTransactionSnapshot {
  const CredentialTransactionSnapshot({this.current, this.staged});

  final Uint8List? current;
  final Uint8List? staged;
}

/// QQ-only crash-recovery operations. All bytes remain opaque to Flutter.
abstract interface class CredentialRotationVault implements CredentialVault {
  bool get supportsStaging;

  int reserveRotation();

  bool isCurrent(int epoch);

  Future<bool> stageIfCurrent(int epoch, Uint8List secretBytes);

  Future<bool> publishIfCurrent(int epoch, Uint8List secretBytes);

  Future<bool> deleteStageIfCurrent(int epoch);

  Future<CredentialTransactionSnapshot> readTransaction();

  Future<void> publishReplacement(Uint8List secretBytes);

  Future<void> deleteTransaction();

  Future<bool> deleteTransactionIfCurrent(int epoch);
}

abstract interface class SecureStringStore {
  Future<void> write({required String key, required String value});

  Future<String?> read({required String key});

  Future<void> delete({required String key});
}

/// Orders every operation for one credential key so an old rejection cleanup
/// cannot overtake a newer credential write.
class SerializedCredentialVault implements CredentialRotationVault {
  SerializedCredentialVault(this._inner, {CredentialVault? stagedVault})
    : _staged = stagedVault;

  final CredentialVault _inner;
  final CredentialVault? _staged;
  Future<void> _tail = Future<void>.value();
  int _epoch = 0;

  @override
  bool get supportsStaging => _staged != null;

  @override
  Future<void> delete() =>
      _staged == null ? _enqueue(_inner.delete) : deleteTransaction();

  @override
  Future<Uint8List?> read() => _enqueue(_inner.read);

  @override
  Future<void> write(Uint8List secretBytes) => _staged == null
      ? _enqueue(() => _inner.write(secretBytes))
      : publishReplacement(secretBytes);

  @override
  int reserveRotation() => _epoch;

  @override
  bool isCurrent(int epoch) => epoch == _epoch;

  @override
  Future<bool> stageIfCurrent(int epoch, Uint8List secretBytes) =>
      _enqueue(() async {
        if (epoch != _epoch || _staged == null) return false;
        await _staged.write(secretBytes);
        return epoch == _epoch;
      });

  @override
  Future<bool> publishIfCurrent(int epoch, Uint8List secretBytes) =>
      _enqueue(() async {
        if (epoch != _epoch || _staged == null) return false;
        await _inner.write(secretBytes);
        return epoch == _epoch;
      });

  @override
  Future<bool> deleteStageIfCurrent(int epoch) => _enqueue(() async {
    if (epoch != _epoch || _staged == null) return false;
    await _staged.delete();
    return epoch == _epoch;
  });

  @override
  Future<CredentialTransactionSnapshot> readTransaction() => _enqueue(() async {
    final current = await _inner.read();
    try {
      return CredentialTransactionSnapshot(
        current: current,
        staged: await _staged?.read(),
      );
    } on Object {
      current?.fillRange(0, current.length, 0);
      rethrow;
    }
  });

  @override
  Future<void> publishReplacement(Uint8List secretBytes) {
    final epoch = ++_epoch;
    return _enqueue(() async {
      if (epoch != _epoch) return;
      await _staged?.delete();
      if (epoch != _epoch) return;
      await _inner.write(secretBytes);
    });
  }

  @override
  Future<void> deleteTransaction() {
    final epoch = ++_epoch;
    return _enqueue(() async {
      if (epoch != _epoch) return;
      // Delete the stage first. A crash can then leave a recoverable current
      // credential, never an orphan stage that revives a completed logout.
      await _staged?.delete();
      if (epoch != _epoch) return;
      await _inner.delete();
    });
  }

  @override
  Future<bool> deleteTransactionIfCurrent(int epoch) {
    if (epoch != _epoch) return Future<bool>.value(false);
    final invalidatedEpoch = ++_epoch;
    return _enqueue(() async {
      if (invalidatedEpoch != _epoch) return false;
      await _staged?.delete();
      if (invalidatedEpoch != _epoch) return false;
      await _inner.delete();
      return true;
    });
  }

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
  FlutterSecureStringStore({
    FlutterSecureStorage? storage,
    String platformLabel = 'QQ Music session',
  }) : _storage =
           storage ??
           FlutterSecureStorage(
             aOptions: const AndroidOptions(
               resetOnError: false,
               storageNamespace: 'flutterustmusic_auth',
             ),
             iOptions: IOSOptions(
               accountName: 'com.fura.flutterustmusic',
               accessibility: KeychainAccessibility.first_unlock_this_device,
               synchronizable: false,
               label: platformLabel,
             ),
             mOptions: MacOsOptions(
               accountName: 'com.fura.flutterustmusic',
               accessibility: KeychainAccessibility.first_unlock_this_device,
               synchronizable: false,
               label: platformLabel,
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
  PlatformCredentialVault({
    this.credentialKey = qqMusicCredentialKey,
    String? platformLabel,
    SecureStringStore? store,
  }) : _store =
           store ??
           FlutterSecureStringStore(
             platformLabel:
                 platformLabel ??
                 (credentialKey == netEaseCredentialKey
                     ? 'NetEase Cloud Music session'
                     : 'QQ Music session'),
           );

  static const qqMusicCredentialKey = 'qq_music_credential_v1';
  static const qqMusicStagedCredentialKey =
      'qq_music_credential_refresh_staged_v1';
  static const netEaseCredentialKey = 'netease_cloud_music_credential_v1';

  final SecureStringStore _store;
  final String credentialKey;

  @override
  Future<void> write(Uint8List secretBytes) =>
      _store.write(key: credentialKey, value: base64Encode(secretBytes));

  @override
  Future<Uint8List?> read() async {
    final value = await _store.read(key: credentialKey);
    return value == null ? null : base64Decode(value);
  }

  @override
  Future<void> delete() => _store.delete(key: credentialKey);
}
