import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge;

enum UserLibraryFailure {
  coreUnavailable,
  authenticationRequired,
  credentialRejected,
  credentialRejectedStorageCleanupFailed,
  network,
  serviceUnavailable,
  invalidResponse,
  replaced,
  cancelled,
  alreadyRunning,
}

class UserPlaylistSummary {
  const UserPlaylistSummary({
    required this.providerId,
    required this.opaqueId,
    required this.title,
    this.artworkUri,
    this.trackCount,
  });

  final String providerId;
  final String opaqueId;
  final String title;
  final String? artworkUri;
  final int? trackCount;
}

class UserLibraryResult {
  const UserLibraryResult({this.playlists = const [], this.failure});

  final List<UserPlaylistSummary> playlists;
  final UserLibraryFailure? failure;
}

abstract interface class UserLibraryGateway {
  UserLibraryLoadOperation beginLoad();
}

abstract interface class UserLibraryLoadOperation {
  Future<UserLibraryResult> run();
  bool cancel();
}

typedef UserLibraryLoadOperationFactory = UserLibraryLoadOperation Function();

class RustUserLibraryGateway implements UserLibraryGateway {
  RustUserLibraryGateway({
    CredentialVault? credentialVault,
    UserLibraryLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustUserLibraryLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final UserLibraryLoadOperationFactory _operationFactory;

  @override
  UserLibraryLoadOperation beginLoad() =>
      _VaultCleaningLibraryLoadOperation(_operationFactory(), _credentialVault);
}

UserLibraryLoadOperation _beginRustUserLibraryLoad() =>
    _RustUserLibraryLoadOperation(bridge.beginQqMusicUserPlaylistLoad());

class _RustUserLibraryLoadOperation implements UserLibraryLoadOperation {
  const _RustUserLibraryLoadOperation(this._handle);

  final bridge.QqMusicUserPlaylistLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<UserLibraryResult> run() async {
    try {
      final result = await _handle.run();
      final failure = result.failure;
      return UserLibraryResult(
        playlists: failure == null
            ? result.playlists
                  .map(
                    (playlist) => UserPlaylistSummary(
                      providerId: playlist.providerId,
                      opaqueId: playlist.opaqueId,
                      title: playlist.title,
                      artworkUri: playlist.artworkUri,
                      trackCount: playlist.trackCount,
                    ),
                  )
                  .toList(growable: false)
            : const [],
        failure: failure == null ? null : _mapFailure(failure),
      );
    } catch (_) {
      return const UserLibraryResult(
        failure: UserLibraryFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningLibraryLoadOperation implements UserLibraryLoadOperation {
  const _VaultCleaningLibraryLoadOperation(this._inner, this._credentialVault);

  final UserLibraryLoadOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<UserLibraryResult> run() async {
    final result = await _inner.run();
    if (result.failure != UserLibraryFailure.credentialRejected) return result;
    try {
      await _credentialVault.delete();
      return result;
    } catch (_) {
      return const UserLibraryResult(
        failure: UserLibraryFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}

UserLibraryFailure _mapFailure(
  bridge.QqMusicUserPlaylistLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicUserPlaylistLoadFailure.coreUnavailable =>
    UserLibraryFailure.coreUnavailable,
  bridge.QqMusicUserPlaylistLoadFailure.authenticationRequired =>
    UserLibraryFailure.authenticationRequired,
  bridge.QqMusicUserPlaylistLoadFailure.credentialRejected =>
    UserLibraryFailure.credentialRejected,
  bridge.QqMusicUserPlaylistLoadFailure.network => UserLibraryFailure.network,
  bridge.QqMusicUserPlaylistLoadFailure.serviceUnavailable =>
    UserLibraryFailure.serviceUnavailable,
  bridge.QqMusicUserPlaylistLoadFailure.invalidResponse =>
    UserLibraryFailure.invalidResponse,
  bridge.QqMusicUserPlaylistLoadFailure.replaced => UserLibraryFailure.replaced,
  bridge.QqMusicUserPlaylistLoadFailure.cancelled =>
    UserLibraryFailure.cancelled,
  bridge.QqMusicUserPlaylistLoadFailure.alreadyRunning =>
    UserLibraryFailure.alreadyRunning,
};
