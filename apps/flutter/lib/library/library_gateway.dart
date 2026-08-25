import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge;

enum OwnedLibraryFailure {
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

class OwnedPlaylistSummary {
  const OwnedPlaylistSummary({
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

class OwnedLibraryResult {
  const OwnedLibraryResult({this.playlists = const [], this.failure});

  final List<OwnedPlaylistSummary> playlists;
  final OwnedLibraryFailure? failure;
}

abstract interface class OwnedLibraryGateway {
  OwnedLibraryLoadOperation beginLoad();
}

abstract interface class OwnedLibraryLoadOperation {
  Future<OwnedLibraryResult> run();
  bool cancel();
}

typedef OwnedLibraryLoadOperationFactory = OwnedLibraryLoadOperation Function();

class RustOwnedLibraryGateway implements OwnedLibraryGateway {
  RustOwnedLibraryGateway({
    CredentialVault? credentialVault,
    OwnedLibraryLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustOwnedLibraryLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final OwnedLibraryLoadOperationFactory _operationFactory;

  @override
  OwnedLibraryLoadOperation beginLoad() =>
      _VaultCleaningLibraryLoadOperation(_operationFactory(), _credentialVault);
}

OwnedLibraryLoadOperation _beginRustOwnedLibraryLoad() =>
    _RustOwnedLibraryLoadOperation(bridge.beginQqMusicOwnedPlaylistLoad());

class _RustOwnedLibraryLoadOperation implements OwnedLibraryLoadOperation {
  const _RustOwnedLibraryLoadOperation(this._handle);

  final bridge.QqMusicOwnedPlaylistLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<OwnedLibraryResult> run() async {
    try {
      final result = await _handle.run();
      final failure = result.failure;
      return OwnedLibraryResult(
        playlists: failure == null
            ? result.playlists
                  .map(
                    (playlist) => OwnedPlaylistSummary(
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
      return const OwnedLibraryResult(
        failure: OwnedLibraryFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningLibraryLoadOperation implements OwnedLibraryLoadOperation {
  const _VaultCleaningLibraryLoadOperation(this._inner, this._credentialVault);

  final OwnedLibraryLoadOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<OwnedLibraryResult> run() async {
    final result = await _inner.run();
    if (result.failure != OwnedLibraryFailure.credentialRejected) return result;
    try {
      await _credentialVault.delete();
      return result;
    } catch (_) {
      return const OwnedLibraryResult(
        failure: OwnedLibraryFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}

OwnedLibraryFailure _mapFailure(
  bridge.QqMusicOwnedPlaylistLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicOwnedPlaylistLoadFailure.coreUnavailable =>
    OwnedLibraryFailure.coreUnavailable,
  bridge.QqMusicOwnedPlaylistLoadFailure.authenticationRequired =>
    OwnedLibraryFailure.authenticationRequired,
  bridge.QqMusicOwnedPlaylistLoadFailure.credentialRejected =>
    OwnedLibraryFailure.credentialRejected,
  bridge.QqMusicOwnedPlaylistLoadFailure.network => OwnedLibraryFailure.network,
  bridge.QqMusicOwnedPlaylistLoadFailure.serviceUnavailable =>
    OwnedLibraryFailure.serviceUnavailable,
  bridge.QqMusicOwnedPlaylistLoadFailure.invalidResponse =>
    OwnedLibraryFailure.invalidResponse,
  bridge.QqMusicOwnedPlaylistLoadFailure.replaced =>
    OwnedLibraryFailure.replaced,
  bridge.QqMusicOwnedPlaylistLoadFailure.cancelled =>
    OwnedLibraryFailure.cancelled,
  bridge.QqMusicOwnedPlaylistLoadFailure.alreadyRunning =>
    OwnedLibraryFailure.alreadyRunning,
};
