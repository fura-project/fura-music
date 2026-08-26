import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/src/rust/api/favorite_albums.dart' as bridge;

enum FavoriteAlbumFailure {
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

class FavoriteAlbumPageResult {
  const FavoriteAlbumPageResult({
    this.offset = 0,
    this.total = 0,
    this.hasMore = false,
    this.albums = const [],
    this.failure,
  });

  final int offset;
  final int total;
  final bool hasMore;
  final List<AlbumSummary> albums;
  final FavoriteAlbumFailure? failure;
}

abstract interface class FavoriteAlbumGateway {
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  });
}

abstract interface class FavoriteAlbumPageLoadOperation {
  Future<FavoriteAlbumPageResult> run();
  bool cancel();
}

typedef FavoriteAlbumPageLoadOperationFactory =
    FavoriteAlbumPageLoadOperation Function(int offset, int size);

class RustFavoriteAlbumGateway implements FavoriteAlbumGateway {
  RustFavoriteAlbumGateway({
    CredentialVault? credentialVault,
    FavoriteAlbumPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final FavoriteAlbumPageLoadOperationFactory _operationFactory;

  @override
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _VaultCleaningFavoriteAlbumPageLoadOperation(
    _operationFactory(offset, size),
    _credentialVault,
  );
}

FavoriteAlbumPageLoadOperation _beginRustLoad(int offset, int size) =>
    _RustFavoriteAlbumPageLoadOperation(
      bridge.beginQqMusicFavoriteAlbumPageLoad(offset: offset, size: size),
    );

class _RustFavoriteAlbumPageLoadOperation
    implements FavoriteAlbumPageLoadOperation {
  const _RustFavoriteAlbumPageLoadOperation(this._handle);

  final bridge.QqMusicFavoriteAlbumPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<FavoriteAlbumPageResult> run() async {
    try {
      return mapBridgeFavoriteAlbumPage(await _handle.run());
    } on Object {
      return const FavoriteAlbumPageResult(
        failure: FavoriteAlbumFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningFavoriteAlbumPageLoadOperation
    implements FavoriteAlbumPageLoadOperation {
  const _VaultCleaningFavoriteAlbumPageLoadOperation(
    this._inner,
    this._credentialVault,
  );

  final FavoriteAlbumPageLoadOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<FavoriteAlbumPageResult> run() async {
    final result = await _inner.run();
    if (result.failure != FavoriteAlbumFailure.credentialRejected) {
      return result;
    }
    try {
      await _credentialVault.delete();
      return result;
    } on Object {
      return const FavoriteAlbumPageResult(
        failure: FavoriteAlbumFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}

@visibleForTesting
FavoriteAlbumPageResult mapBridgeFavoriteAlbumPage(
  bridge.QqMusicFavoriteAlbumPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.offset != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.albums.isNotEmpty) {
      return const FavoriteAlbumPageResult(
        failure: FavoriteAlbumFailure.invalidResponse,
      );
    }
    return FavoriteAlbumPageResult(
      failure: mapBridgeFavoriteAlbumFailure(failure),
    );
  }
  final pageEnd = result.offset + result.albums.length;
  if (result.offset < 0 ||
      result.total < 0 ||
      pageEnd > result.total ||
      (result.hasMore && (result.albums.isEmpty || pageEnd >= result.total)) ||
      (!result.hasMore && pageEnd != result.total)) {
    return const FavoriteAlbumPageResult(
      failure: FavoriteAlbumFailure.invalidResponse,
    );
  }
  final albums = <AlbumSummary>[];
  for (final album in result.albums) {
    if (album.providerId.trim().isEmpty ||
        album.opaqueId.trim().isEmpty ||
        album.title.trim().isEmpty ||
        (album.artworkUri?.trim().isEmpty ?? false)) {
      return const FavoriteAlbumPageResult(
        failure: FavoriteAlbumFailure.invalidResponse,
      );
    }
    albums.add(
      AlbumSummary(
        providerId: album.providerId,
        opaqueId: album.opaqueId,
        title: album.title,
        artworkUri: album.artworkUri,
      ),
    );
  }
  return FavoriteAlbumPageResult(
    offset: result.offset,
    total: result.total,
    hasMore: result.hasMore,
    albums: List.unmodifiable(albums),
  );
}

@visibleForTesting
FavoriteAlbumFailure mapBridgeFavoriteAlbumFailure(
  bridge.QqMusicFavoriteAlbumPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicFavoriteAlbumPageLoadFailure.coreUnavailable =>
    FavoriteAlbumFailure.coreUnavailable,
  bridge.QqMusicFavoriteAlbumPageLoadFailure.authenticationRequired =>
    FavoriteAlbumFailure.authenticationRequired,
  bridge.QqMusicFavoriteAlbumPageLoadFailure.credentialRejected =>
    FavoriteAlbumFailure.credentialRejected,
  bridge.QqMusicFavoriteAlbumPageLoadFailure.network =>
    FavoriteAlbumFailure.network,
  bridge.QqMusicFavoriteAlbumPageLoadFailure.serviceUnavailable =>
    FavoriteAlbumFailure.serviceUnavailable,
  bridge.QqMusicFavoriteAlbumPageLoadFailure.invalidResponse =>
    FavoriteAlbumFailure.invalidResponse,
  bridge.QqMusicFavoriteAlbumPageLoadFailure.replaced =>
    FavoriteAlbumFailure.replaced,
  bridge.QqMusicFavoriteAlbumPageLoadFailure.cancelled =>
    FavoriteAlbumFailure.cancelled,
  bridge.QqMusicFavoriteAlbumPageLoadFailure.alreadyRunning =>
    FavoriteAlbumFailure.alreadyRunning,
};
