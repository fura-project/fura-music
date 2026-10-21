import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/qq_session_continuation.dart';
import 'package:flutterustmusic/pagination/raw_offset_page.dart';
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
    this.continuationOffset = -1,
    this.total = 0,
    this.hasMore = false,
    this.artists = const [],
    this.omittedArtistCount = 0,
    this.failure,
  });

  final int offset;
  final int continuationOffset;
  final int total;
  final bool hasMore;
  final List<ArtistSummary> artists;
  final int omittedArtistCount;
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
typedef _FavoriteArtistPageRetryFactory =
    FavoriteArtistPageLoadOperation Function();

class RustFavoriteArtistGateway implements FavoriteArtistGateway {
  RustFavoriteArtistGateway({
    this.providerId = 'qq-music',
    CredentialVault? credentialVault,
    this.operationFactory,
    this.sessionContinuation,
  }) : _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final String providerId;
  final FavoriteArtistPageLoadOperationFactory? operationFactory;
  final QqSessionContinuationCoordinator? sessionContinuation;

  @override
  FavoriteArtistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _ContinuingFavoriteArtistPageLoadOperation(
    () =>
        operationFactory?.call(offset, size) ??
        _beginRustLoad(providerId, offset, size),
    _credentialVault,
    providerId == 'qq-music' ? sessionContinuation : null,
  );
}

FavoriteArtistPageLoadOperation _beginRustLoad(
  String providerId,
  int offset,
  int size,
) => _RustFavoriteArtistPageLoadOperation(
  bridge.beginQqMusicFavoriteArtistPageLoad(
    providerId: providerId,
    offset: offset,
    size: size,
  ),
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

class _ContinuingFavoriteArtistPageLoadOperation
    implements FavoriteArtistPageLoadOperation {
  _ContinuingFavoriteArtistPageLoadOperation(
    this._factory,
    this._credentialVault,
    this._continuation,
  ) : _active = _factory();

  final _FavoriteArtistPageRetryFactory _factory;
  final CredentialVault _credentialVault;
  final QqSessionContinuationCoordinator? _continuation;
  FavoriteArtistPageLoadOperation _active;
  bool _cancelled = false;

  @override
  bool cancel() {
    _cancelled = true;
    return _active.cancel();
  }

  @override
  Future<FavoriteArtistPageResult> run() async {
    final result = await _active.run();
    if (result.failure != FavoriteArtistFailure.credentialRejected) {
      return result;
    }
    final continuation = _continuation;
    if (continuation != null) {
      final outcome = await continuation.continueAfterReadRejection();
      if (outcome == QqSessionContinuationResult.continued && !_cancelled) {
        _active = _factory();
        return _active.run();
      }
      if (outcome != QqSessionContinuationResult.reauthenticationRequired) {
        return const FavoriteArtistPageResult(
          failure: FavoriteArtistFailure.serviceUnavailable,
        );
      }
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
        result.nextOffset != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.artists.isNotEmpty ||
        result.omittedArtistCount != 0) {
      return const FavoriteArtistPageResult(
        failure: FavoriteArtistFailure.invalidResponse,
      );
    }
    return FavoriteArtistPageResult(
      failure: mapBridgeFavoriteArtistFailure(failure),
    );
  }
  if (!isValidRawOffsetPage(
    offset: result.offset,
    continuationOffset: result.nextOffset,
    total: result.total,
    hasMore: result.hasMore,
    visibleCount: result.artists.length,
    omittedCount: result.omittedArtistCount,
  )) {
    return const FavoriteArtistPageResult(
      failure: FavoriteArtistFailure.invalidResponse,
    );
  }
  final artists = <ArtistSummary>[];
  for (final artist in result.artists) {
    if (artist.providerId.trim().isEmpty ||
        artist.opaqueId.trim().isEmpty ||
        artist.name.trim().isEmpty ||
        (artist.artworkUri?.trim().isEmpty ?? false)) {
      return const FavoriteArtistPageResult(
        failure: FavoriteArtistFailure.invalidResponse,
      );
    }
    artists.add(
      ArtistSummary(
        providerId: artist.providerId,
        opaqueId: artist.opaqueId,
        name: artist.name,
        artworkUri: artist.artworkUri,
      ),
    );
  }
  return FavoriteArtistPageResult(
    offset: result.offset,
    continuationOffset: result.nextOffset,
    total: result.total,
    hasMore: result.hasMore,
    artists: List.unmodifiable(artists),
    omittedArtistCount: result.omittedArtistCount,
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
