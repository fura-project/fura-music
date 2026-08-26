import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/src/rust/api/favorite_artists.dart' as bridge;

enum FavoriteArtistFailure {
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

class FavoriteArtistPageResult {
  const FavoriteArtistPageResult({
    this.offset = 0,
    this.total = 0,
    this.hasMore = false,
    this.artists = const [],
    this.failure,
  });

  final int offset;
  final int total;
  final bool hasMore;
  final List<ArtistSummary> artists;
  final FavoriteArtistFailure? failure;
}

abstract interface class FavoriteArtistGateway {
  FavoriteArtistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  });
}

abstract interface class FavoriteArtistPageLoadOperation {
  Future<FavoriteArtistPageResult> run();
  bool cancel();
}

typedef FavoriteArtistPageLoadOperationFactory =
    FavoriteArtistPageLoadOperation Function(int offset, int size);

class RustFavoriteArtistGateway implements FavoriteArtistGateway {
  RustFavoriteArtistGateway({
    CredentialVault? credentialVault,
    FavoriteArtistPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final FavoriteArtistPageLoadOperationFactory _operationFactory;

  @override
  FavoriteArtistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _VaultCleaningFavoriteArtistPageLoadOperation(
    _operationFactory(offset, size),
    _credentialVault,
  );
}

FavoriteArtistPageLoadOperation _beginRustLoad(int offset, int size) =>
    _RustFavoriteArtistPageLoadOperation(
      bridge.beginQqMusicFavoriteArtistPageLoad(offset: offset, size: size),
    );

class _RustFavoriteArtistPageLoadOperation
    implements FavoriteArtistPageLoadOperation {
  const _RustFavoriteArtistPageLoadOperation(this._handle);

  final bridge.QqMusicFavoriteArtistPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<FavoriteArtistPageResult> run() async {
    try {
      return mapBridgeFavoriteArtistPage(await _handle.run());
    } on Object {
      return const FavoriteArtistPageResult(
        failure: FavoriteArtistFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningFavoriteArtistPageLoadOperation
    implements FavoriteArtistPageLoadOperation {
  const _VaultCleaningFavoriteArtistPageLoadOperation(
    this._inner,
    this._credentialVault,
  );

  final FavoriteArtistPageLoadOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<FavoriteArtistPageResult> run() async {
    final result = await _inner.run();
    if (result.failure != FavoriteArtistFailure.credentialRejected) {
      return result;
    }
    try {
      await _credentialVault.delete();
      return result;
    } on Object {
      return const FavoriteArtistPageResult(
        failure: FavoriteArtistFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}

@visibleForTesting
FavoriteArtistPageResult mapBridgeFavoriteArtistPage(
  bridge.QqMusicFavoriteArtistPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.offset != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.artists.isNotEmpty) {
      return const FavoriteArtistPageResult(
        failure: FavoriteArtistFailure.invalidResponse,
      );
    }
    return FavoriteArtistPageResult(
      failure: mapBridgeFavoriteArtistFailure(failure),
    );
  }
  final pageEnd = result.offset + result.artists.length;
  if (result.offset < 0 ||
      result.total < 0 ||
      pageEnd > result.total ||
      (result.hasMore && (result.artists.isEmpty || pageEnd >= result.total)) ||
      (!result.hasMore && pageEnd != result.total)) {
    return const FavoriteArtistPageResult(
      failure: FavoriteArtistFailure.invalidResponse,
    );
  }
  final artists = <ArtistSummary>[];
  for (final artist in result.artists) {
    if (artist.providerId.trim().isEmpty ||
        artist.opaqueId.trim().isEmpty ||
        artist.name.trim().isEmpty) {
      return const FavoriteArtistPageResult(
        failure: FavoriteArtistFailure.invalidResponse,
      );
    }
    artists.add(
      ArtistSummary(
        providerId: artist.providerId,
        opaqueId: artist.opaqueId,
        name: artist.name,
      ),
    );
  }
  return FavoriteArtistPageResult(
    offset: result.offset,
    total: result.total,
    hasMore: result.hasMore,
    artists: List.unmodifiable(artists),
  );
}

@visibleForTesting
FavoriteArtistFailure mapBridgeFavoriteArtistFailure(
  bridge.QqMusicFavoriteArtistPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicFavoriteArtistPageLoadFailure.coreUnavailable =>
    FavoriteArtistFailure.coreUnavailable,
  bridge.QqMusicFavoriteArtistPageLoadFailure.authenticationRequired =>
    FavoriteArtistFailure.authenticationRequired,
  bridge.QqMusicFavoriteArtistPageLoadFailure.credentialRejected =>
    FavoriteArtistFailure.credentialRejected,
  bridge.QqMusicFavoriteArtistPageLoadFailure.network =>
    FavoriteArtistFailure.network,
  bridge.QqMusicFavoriteArtistPageLoadFailure.serviceUnavailable =>
    FavoriteArtistFailure.serviceUnavailable,
  bridge.QqMusicFavoriteArtistPageLoadFailure.invalidResponse =>
    FavoriteArtistFailure.invalidResponse,
  bridge.QqMusicFavoriteArtistPageLoadFailure.replaced =>
    FavoriteArtistFailure.replaced,
  bridge.QqMusicFavoriteArtistPageLoadFailure.cancelled =>
    FavoriteArtistFailure.cancelled,
  bridge.QqMusicFavoriteArtistPageLoadFailure.alreadyRunning =>
    FavoriteArtistFailure.alreadyRunning,
};
