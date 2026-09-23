import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge;

/// Account-scoped cloud history. No playlist identity or local recommendation
/// seed is a substitute for this source. A production adapter requires verified
/// Provider read/continuation semantics and credential-generation isolation in
/// Core. `totalIsExact` remains false for bounded upstream snapshots.
abstract interface class RecentPlaysGateway {
  PlaylistTrackPageLoadOperation beginLoad({
    required int offset,
    required int size,
  });
}

typedef RecentTrackPageLoadOperationFactory =
    PlaylistTrackPageLoadOperation Function(
      String providerId,
      int offset,
      int size,
    );

class RustRecentPlaysGateway implements RecentPlaysGateway {
  RustRecentPlaysGateway({
    required this.providerId,
    CredentialVault? credentialVault,
    RecentTrackPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final String providerId;
  final RecentTrackPageLoadOperationFactory _operationFactory;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _VaultCleaningRecentTrackPageLoadOperation(
    _operationFactory(providerId, offset, size),
    _credentialVault,
  );
}

PlaylistTrackPageLoadOperation _beginRustLoad(
  String providerId,
  int offset,
  int size,
) => _RustRecentTrackPageLoadOperation(
  bridge.beginRecentTrackPageLoad(
    providerId: providerId,
    offset: offset,
    size: size,
  ),
);

class _RustRecentTrackPageLoadOperation
    implements PlaylistTrackPageLoadOperation {
  const _RustRecentTrackPageLoadOperation(this._handle);

  final bridge.RecentTrackPageLoadHandle _handle;

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
  bridge.PlaylistTrackPageLoadFailure failure,
) => switch (failure) {
  bridge.PlaylistTrackPageLoadFailure.coreUnavailable =>
    UserLibraryFailure.coreUnavailable,
  bridge.PlaylistTrackPageLoadFailure.authenticationRequired =>
    UserLibraryFailure.authenticationRequired,
  bridge.PlaylistTrackPageLoadFailure.credentialRejected =>
    UserLibraryFailure.credentialRejected,
  bridge.PlaylistTrackPageLoadFailure.network => UserLibraryFailure.network,
  bridge.PlaylistTrackPageLoadFailure.serviceUnavailable =>
    UserLibraryFailure.serviceUnavailable,
  bridge.PlaylistTrackPageLoadFailure.invalidResponse =>
    UserLibraryFailure.invalidResponse,
  bridge.PlaylistTrackPageLoadFailure.replaced => UserLibraryFailure.replaced,
  bridge.PlaylistTrackPageLoadFailure.cancelled => UserLibraryFailure.cancelled,
  bridge.PlaylistTrackPageLoadFailure.alreadyRunning =>
    UserLibraryFailure.alreadyRunning,
};
