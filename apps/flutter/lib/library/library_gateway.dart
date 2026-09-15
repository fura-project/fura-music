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

enum UserPlaylistOwnership { unspecified, owned, saved }

class UserPlaylistSummary {
  const UserPlaylistSummary({
    required this.providerId,
    required this.opaqueId,
    required this.title,
    this.artworkUri,
    this.trackCount,
    this.isLikedSongs = false,
    this.ownership = UserPlaylistOwnership.unspecified,
  });

  final String providerId;
  final String opaqueId;
  final String title;
  final String? artworkUri;
  final int? trackCount;
  final bool isLikedSongs;
  final UserPlaylistOwnership ownership;
}

class UserLibraryResult {
  const UserLibraryResult({
    this.playlists = const [],
    this.omittedPlaylistCount = 0,
    this.failure,
  });

  final List<UserPlaylistSummary> playlists;
  final int omittedPlaylistCount;
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
    this.providerId = 'qq-music',
    CredentialVault? credentialVault,
    this.operationFactory,
  }) : _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final String providerId;
  final UserLibraryLoadOperationFactory? operationFactory;

  @override
  UserLibraryLoadOperation beginLoad() => _VaultCleaningLibraryLoadOperation(
    operationFactory?.call() ?? _beginRustUserLibraryLoad(providerId),
    _credentialVault,
  );
}

UserLibraryLoadOperation _beginRustUserLibraryLoad(String providerId) =>
    _RustUserLibraryLoadOperation(
      bridge.beginQqMusicUserPlaylistLoad(providerId: providerId),
    );

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
      if (failure != null &&
          (result.playlists.isNotEmpty || result.omittedPlaylistCount != 0)) {
        return const UserLibraryResult(
          failure: UserLibraryFailure.invalidResponse,
        );
      }
      if (result.omittedPlaylistCount < 0) {
        return const UserLibraryResult(
          failure: UserLibraryFailure.invalidResponse,
        );
      }
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
                      isLikedSongs: playlist.isLikedSongs,
                      ownership: switch (playlist.ownership) {
                        null => UserPlaylistOwnership.unspecified,
                        bridge.LibraryPlaylistOwnership.unspecified =>
                          UserPlaylistOwnership.unspecified,
                        bridge.LibraryPlaylistOwnership.owned =>
                          UserPlaylistOwnership.owned,
                        bridge.LibraryPlaylistOwnership.saved =>
                          UserPlaylistOwnership.saved,
                      },
                    ),
                  )
                  .toList(growable: false)
            : const [],
        omittedPlaylistCount: failure == null ? result.omittedPlaylistCount : 0,
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
