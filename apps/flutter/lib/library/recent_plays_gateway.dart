import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge;

/// Account-scoped cloud history. No playlist identity or local recommendation
/// seed is a substitute for this source. A production adapter requires verified
/// QQ read/continuation semantics and credential-generation isolation in Core.
abstract interface class RecentPlaysGateway {
  PlaylistTrackPageLoadOperation beginLoad({
    required int offset,
    required int size,
  });
}

typedef RecentTrackPageLoadOperationFactory =
    PlaylistTrackPageLoadOperation Function(int offset, int size);

class RustRecentPlaysGateway implements RecentPlaysGateway {
  RustRecentPlaysGateway({
    CredentialVault? credentialVault,
    RecentTrackPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final RecentTrackPageLoadOperationFactory _operationFactory;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _VaultCleaningRecentTrackPageLoadOperation(
    _operationFactory(offset, size),
    _credentialVault,
  );
}

PlaylistTrackPageLoadOperation _beginRustLoad(int offset, int size) =>
    _RustRecentTrackPageLoadOperation(
      bridge.beginQqMusicRecentTrackPageLoad(offset: offset, size: size),
    );

class _RustRecentTrackPageLoadOperation
    implements PlaylistTrackPageLoadOperation {
  const _RustRecentTrackPageLoadOperation(this._handle);

  final bridge.QqMusicRecentTrackPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<PlaylistTrackPageResult> run() async {
    try {
      final result = await _handle.run();
      final failure = result.failure;
      if (failure != null) {
        return PlaylistTrackPageResult(failure: _mapFailure(failure));
      }
      final tracks = <PlaylistTrackSummary>[];
      for (final track in result.tracks) {
        final mapped = mapBridgeLibraryTrackSummary(track);
        if (mapped == null) {
          return const PlaylistTrackPageResult(
            failure: UserLibraryFailure.invalidResponse,
          );
        }
        tracks.add(mapped);
      }
      return PlaylistTrackPageResult(
        offset: result.offset,
        nextOffset: result.nextOffset,
        total: result.total,
        totalIsExact: result.totalIsExact,
        hasMore: result.hasMore,
        omittedTrackCount: result.omittedTrackCount,
        tracks: List.unmodifiable(tracks),
      );
    } catch (_) {
      return const PlaylistTrackPageResult(
        failure: UserLibraryFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningRecentTrackPageLoadOperation
    implements PlaylistTrackPageLoadOperation {
  const _VaultCleaningRecentTrackPageLoadOperation(this._inner, this._vault);

  final PlaylistTrackPageLoadOperation _inner;
  final CredentialVault _vault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<PlaylistTrackPageResult> run() async {
    final result = await _inner.run();
    if (result.failure != UserLibraryFailure.credentialRejected) return result;
    try {
      await _vault.delete();
      return result;
    } catch (_) {
      return const PlaylistTrackPageResult(
        failure: UserLibraryFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}

UserLibraryFailure _mapFailure(
  bridge.QqMusicPlaylistTrackPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicPlaylistTrackPageLoadFailure.coreUnavailable =>
    UserLibraryFailure.coreUnavailable,
  bridge.QqMusicPlaylistTrackPageLoadFailure.authenticationRequired =>
    UserLibraryFailure.authenticationRequired,
  bridge.QqMusicPlaylistTrackPageLoadFailure.credentialRejected =>
    UserLibraryFailure.credentialRejected,
  bridge.QqMusicPlaylistTrackPageLoadFailure.network =>
    UserLibraryFailure.network,
  bridge.QqMusicPlaylistTrackPageLoadFailure.serviceUnavailable =>
    UserLibraryFailure.serviceUnavailable,
  bridge.QqMusicPlaylistTrackPageLoadFailure.invalidResponse =>
    UserLibraryFailure.invalidResponse,
  bridge.QqMusicPlaylistTrackPageLoadFailure.replaced =>
    UserLibraryFailure.replaced,
  bridge.QqMusicPlaylistTrackPageLoadFailure.cancelled =>
    UserLibraryFailure.cancelled,
  bridge.QqMusicPlaylistTrackPageLoadFailure.alreadyRunning =>
    UserLibraryFailure.alreadyRunning,
};
