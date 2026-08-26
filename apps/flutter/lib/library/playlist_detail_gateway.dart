import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge_album;
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge;

class PlaylistTrackSummary {
  const PlaylistTrackSummary({
    required this.providerId,
    required this.opaqueId,
    required this.title,
    required this.artistNames,
    this.subtitle,
    this.albumTitle,
    this.album,
    this.artworkUri,
    this.durationSeconds,
  });

  final String providerId;
  final String opaqueId;
  final String title;
  final List<String> artistNames;
  final String? subtitle;
  final String? albumTitle;
  final AlbumSummary? album;
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
        total: result.total,
        hasMore: result.hasMore,
        tracks: List.unmodifiable(tracks),
      );
    } catch (_) {
      return const PlaylistTrackPageResult(
        failure: UserLibraryFailure.coreUnavailable,
      );
    }
  }
}

PlaylistTrackSummary? mapBridgeLibraryTrackSummary(
  bridge.LibraryTrackSummary track,
) {
  final providerId = track.providerId;
  final validProvider = _validProviderId(providerId);
  final album = track.album;
  AlbumSummary? mappedAlbum;
  if (album != null) {
    if (!_validBridgeAlbum(album, providerId)) return null;
    mappedAlbum = AlbumSummary(
      providerId: album.providerId,
      opaqueId: album.opaqueId,
      title: album.title,
      artworkUri: album.artworkUri,
    );
  }
  if (!validProvider ||
      track.opaqueId.trim().isEmpty ||
      track.title.trim().isEmpty ||
      track.artistNames.any((artist) => artist.trim().isEmpty) ||
      _blank(track.subtitle) ||
      _blank(track.albumTitle) ||
      _blank(track.artworkUri) ||
      (track.durationSeconds != null && track.durationSeconds! < 0)) {
    return null;
  }
  return PlaylistTrackSummary(
    providerId: providerId,
    opaqueId: track.opaqueId,
    title: track.title,
    artistNames: List.unmodifiable(track.artistNames),
    subtitle: track.subtitle,
    albumTitle: track.albumTitle,
    album: mappedAlbum,
    artworkUri: track.artworkUri,
    durationSeconds: track.durationSeconds,
  );
}

bool _validBridgeAlbum(
  bridge_album.CatalogAlbumSummary album,
  String trackProviderId,
) =>
    _validProviderId(album.providerId) &&
    album.providerId == trackProviderId &&
    album.opaqueId.trim().isNotEmpty &&
    album.title.trim().isNotEmpty &&
    !_blank(album.artworkUri);

bool _validProviderId(String value) =>
    value.isNotEmpty &&
    value.codeUnits.every(
      (unit) =>
          unit >= 97 && unit <= 122 || unit >= 48 && unit <= 57 || unit == 45,
    );

bool _blank(String? value) => value != null && value.trim().isEmpty;

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
