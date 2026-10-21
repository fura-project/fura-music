import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/qq_session_continuation.dart';
import 'package:flutterustmusic/pagination/raw_offset_page.dart';
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
    this.continuationOffset = -1,
    this.total = 0,
    this.hasMore = false,
    this.albums = const [],
    this.membershipAlbumOpaqueIds = const [],
    this.membershipIsExact = true,
    this.omittedAlbumCount = 0,
    this.failure,
  });

  final int offset;
  final int continuationOffset;
  final int total;
  final bool hasMore;
  final List<AlbumSummary> albums;
  final List<String> membershipAlbumOpaqueIds;
  final bool membershipIsExact;
  final int omittedAlbumCount;
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
typedef _FavoriteAlbumPageRetryFactory =
    FavoriteAlbumPageLoadOperation Function();

class RustFavoriteAlbumGateway implements FavoriteAlbumGateway {
  RustFavoriteAlbumGateway({
    this.providerId = 'qq-music',
    CredentialVault? credentialVault,
    this.operationFactory,
    this.sessionContinuation,
  }) : _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final String providerId;
  final FavoriteAlbumPageLoadOperationFactory? operationFactory;
  final QqSessionContinuationCoordinator? sessionContinuation;

  @override
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _ContinuingFavoriteAlbumPageLoadOperation(
    () =>
        operationFactory?.call(offset, size) ??
        _beginRustLoad(providerId, offset, size),
    _credentialVault,
    providerId == 'qq-music' ? sessionContinuation : null,
  );
}

FavoriteAlbumPageLoadOperation _beginRustLoad(
  String providerId,
  int offset,
  int size,
) => _RustFavoriteAlbumPageLoadOperation(
  bridge.beginQqMusicFavoriteAlbumPageLoad(
    providerId: providerId,
    offset: offset,
    size: size,
  ),
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

class _ContinuingFavoriteAlbumPageLoadOperation
    implements FavoriteAlbumPageLoadOperation {
  _ContinuingFavoriteAlbumPageLoadOperation(
    this._factory,
    this._credentialVault,
    this._continuation,
  ) : _active = _factory();

  final _FavoriteAlbumPageRetryFactory _factory;
  final CredentialVault _credentialVault;
  final QqSessionContinuationCoordinator? _continuation;
  FavoriteAlbumPageLoadOperation _active;
  bool _cancelled = false;

  @override
  bool cancel() {
    _cancelled = true;
    return _active.cancel();
  }

  @override
  Future<FavoriteAlbumPageResult> run() async {
    final result = await _active.run();
    if (result.failure != FavoriteAlbumFailure.credentialRejected) {
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
        return const FavoriteAlbumPageResult(
          failure: FavoriteAlbumFailure.serviceUnavailable,
        );
      }
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
        result.nextOffset != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.albums.isNotEmpty ||
        result.membershipIsExact ||
        result.membershipAlbumOpaqueIds.isNotEmpty ||
        result.omittedAlbumCount != 0) {
      return const FavoriteAlbumPageResult(
        failure: FavoriteAlbumFailure.invalidResponse,
      );
    }
    return FavoriteAlbumPageResult(
      failure: mapBridgeFavoriteAlbumFailure(failure),
    );
  }
  if (!isValidRawOffsetPage(
    offset: result.offset,
    continuationOffset: result.nextOffset,
    total: result.total,
    hasMore: result.hasMore,
    visibleCount: result.albums.length,
    omittedCount: result.omittedAlbumCount,
  )) {
    return const FavoriteAlbumPageResult(
      failure: FavoriteAlbumFailure.invalidResponse,
    );
  }
  if (result.membershipAlbumOpaqueIds.any((id) => id.trim().isEmpty)) {
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
    continuationOffset: result.nextOffset,
    total: result.total,
    hasMore: result.hasMore,
    albums: List.unmodifiable(albums),
    membershipAlbumOpaqueIds: List.unmodifiable(
      result.membershipAlbumOpaqueIds,
    ),
    membershipIsExact: result.membershipIsExact,
    omittedAlbumCount: result.omittedAlbumCount,
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
