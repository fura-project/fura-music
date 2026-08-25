import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge;

class PlaylistTrackSummary {
  const PlaylistTrackSummary({
    required this.providerId,
    required this.opaqueId,
    required this.title,
    required this.artistNames,
    this.subtitle,
    this.albumTitle,
    this.artworkUri,
    this.durationSeconds,
  });

  final String providerId;
  final String opaqueId;
  final String title;
  final List<String> artistNames;
  final String? subtitle;
  final String? albumTitle;
  final String? artworkUri;
  final int? durationSeconds;
}

class PlaylistTrackPageResult {
  const PlaylistTrackPageResult({
    this.offset = 0,
    this.total = 0,
    this.hasMore = false,
    this.tracks = const [],
    this.failure,
  });

  final int offset;
  final int total;
  final bool hasMore;
  final List<PlaylistTrackSummary> tracks;
  final UserLibraryFailure? failure;
}

abstract interface class PlaylistDetailGateway {
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  });
}

abstract interface class PlaylistTrackPageLoadOperation {
  Future<PlaylistTrackPageResult> run();
  bool cancel();
}

typedef PlaylistTrackPageLoadOperationFactory =
    PlaylistTrackPageLoadOperation Function(
      UserPlaylistSummary playlist,
      int offset,
      int size,
    );

class RustPlaylistDetailGateway implements PlaylistDetailGateway {
  RustPlaylistDetailGateway({
    CredentialVault? credentialVault,
    PlaylistTrackPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final PlaylistTrackPageLoadOperationFactory _operationFactory;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) => _VaultCleaningTrackPageLoadOperation(
    _operationFactory(playlist, offset, size),
    _credentialVault,
  );
}

PlaylistTrackPageLoadOperation _beginRustLoad(
  UserPlaylistSummary playlist,
  int offset,
  int size,
) => _RustTrackPageLoadOperation(
  bridge.beginQqMusicPlaylistTrackPageLoad(
    providerId: playlist.providerId,
    opaquePlaylistId: playlist.opaqueId,
    offset: offset,
    size: size,
  ),
);

class _RustTrackPageLoadOperation implements PlaylistTrackPageLoadOperation {
  const _RustTrackPageLoadOperation(this._handle);

  final bridge.QqMusicPlaylistTrackPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<PlaylistTrackPageResult> run() async {
    try {
      final result = await _handle.run();
      final failure = result.failure;
      return PlaylistTrackPageResult(
        offset: result.offset,
        total: result.total,
        hasMore: result.hasMore,
        tracks: failure == null
            ? result.tracks
                  .map(
                    (track) => PlaylistTrackSummary(
                      providerId: track.providerId,
                      opaqueId: track.opaqueId,
                      title: track.title,
                      artistNames: List.unmodifiable(track.artistNames),
                      subtitle: track.subtitle,
                      albumTitle: track.albumTitle,
                      artworkUri: track.artworkUri,
                      durationSeconds: track.durationSeconds,
                    ),
                  )
                  .toList(growable: false)
            : const [],
        failure: failure == null ? null : _mapFailure(failure),
      );
    } catch (_) {
      return const PlaylistTrackPageResult(
        failure: UserLibraryFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningTrackPageLoadOperation
    implements PlaylistTrackPageLoadOperation {
  const _VaultCleaningTrackPageLoadOperation(this._inner, this._vault);

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
