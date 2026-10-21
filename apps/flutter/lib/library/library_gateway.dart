import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/qq_session_continuation.dart';
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
    this.sessionContinuation,
  }) : _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final String providerId;
  final UserLibraryLoadOperationFactory? operationFactory;
  final QqSessionContinuationCoordinator? sessionContinuation;

  @override
  UserLibraryLoadOperation beginLoad() => _ContinuingLibraryLoadOperation(
    () => operationFactory?.call() ?? _beginRustUserLibraryLoad(providerId),
    _credentialVault,
    providerId == 'qq-music' ? sessionContinuation : null,
  );
}

UserLibraryLoadOperation _beginRustUserLibraryLoad(String providerId) =>
    _RustUserLibraryLoadOperation(
      bridge.beginUserPlaylistLoad(providerId: providerId),
    );

class _RustUserLibraryLoadOperation implements UserLibraryLoadOperation {
  const _RustUserLibraryLoadOperation(this._handle);

  final bridge.UserPlaylistLoadHandle _handle;

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

class _ContinuingLibraryLoadOperation implements UserLibraryLoadOperation {
  _ContinuingLibraryLoadOperation(
    this._factory,
    this._credentialVault,
    this._continuation,
  ) : _active = _factory();

  final UserLibraryLoadOperationFactory _factory;
  final CredentialVault _credentialVault;
  final QqSessionContinuationCoordinator? _continuation;
  UserLibraryLoadOperation _active;
  bool _cancelled = false;

  @override
  bool cancel() {
    _cancelled = true;
    return _active.cancel();
  }

  @override
  Future<UserLibraryResult> run() async {
    var result = await _active.run();
    if (result.failure != UserLibraryFailure.credentialRejected) return result;
    final continuation = _continuation;
    if (continuation != null) {
      final outcome = await continuation.continueAfterReadRejection();
      if (outcome == QqSessionContinuationResult.continued && !_cancelled) {
        _active = _factory();
        return _active.run();
      }
      if (outcome != QqSessionContinuationResult.reauthenticationRequired) {
        return const UserLibraryResult(
          failure: UserLibraryFailure.serviceUnavailable,
        );
      }
      return result;
    }
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

UserLibraryFailure _mapFailure(bridge.UserPlaylistLoadFailure failure) =>
    switch (failure) {
      bridge.UserPlaylistLoadFailure.coreUnavailable =>
        UserLibraryFailure.coreUnavailable,
      bridge.UserPlaylistLoadFailure.authenticationRequired =>
        UserLibraryFailure.authenticationRequired,
      bridge.UserPlaylistLoadFailure.credentialRejected =>
        UserLibraryFailure.credentialRejected,
      bridge.UserPlaylistLoadFailure.network => UserLibraryFailure.network,
      bridge.UserPlaylistLoadFailure.serviceUnavailable =>
        UserLibraryFailure.serviceUnavailable,
      bridge.UserPlaylistLoadFailure.invalidResponse =>
        UserLibraryFailure.invalidResponse,
      bridge.UserPlaylistLoadFailure.replaced => UserLibraryFailure.replaced,
      bridge.UserPlaylistLoadFailure.cancelled => UserLibraryFailure.cancelled,
      bridge.UserPlaylistLoadFailure.alreadyRunning =>
        UserLibraryFailure.alreadyRunning,
    };
