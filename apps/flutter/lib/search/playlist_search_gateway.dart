import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/search/search_failure.dart';
import 'package:flutterustmusic/src/rust/api/search.dart' as bridge;

export 'package:flutterustmusic/search/search_failure.dart';

class PlaylistSearchPageResult {
  const PlaylistSearchPageResult({
    this.page = 0,
    this.total = 0,
    this.hasMore = false,
    this.playlists = const [],
    this.failure,
  });

  final int page;
  final int total;
  final bool hasMore;
  final List<UserPlaylistSummary> playlists;
  final SearchFailure? failure;
}

abstract interface class PlaylistSearchGateway {
  PlaylistSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  });
}

abstract interface class PlaylistSearchPageLoadOperation {
  Future<PlaylistSearchPageResult> run();
  bool cancel();
}

typedef PlaylistSearchPageLoadOperationFactory =
    PlaylistSearchPageLoadOperation Function(String query, int page, int size);

class RustPlaylistSearchGateway implements PlaylistSearchGateway {
  const RustPlaylistSearchGateway({
    PlaylistSearchPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final PlaylistSearchPageLoadOperationFactory _operationFactory;

  @override
  PlaylistSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) => _operationFactory(query, page, size);
}

PlaylistSearchPageLoadOperation _beginRustLoad(
  String query,
  int page,
  int size,
) => _RustPlaylistSearchPageLoadOperation(
  bridge.beginQqMusicPlaylistSearchPageLoad(
    query: query,
    page: page,
    size: size,
  ),
);

class _RustPlaylistSearchPageLoadOperation
    implements PlaylistSearchPageLoadOperation {
  const _RustPlaylistSearchPageLoadOperation(this._handle);

  final bridge.QqMusicPlaylistSearchPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<PlaylistSearchPageResult> run() async {
    try {
      return mapBridgePlaylistSearchPage(await _handle.run());
    } on Object {
      return const PlaylistSearchPageResult(
        failure: SearchFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
PlaylistSearchPageResult mapBridgePlaylistSearchPage(
  bridge.QqMusicPlaylistSearchPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.page != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.playlists.isNotEmpty) {
      return const PlaylistSearchPageResult(
        failure: SearchFailure.invalidResponse,
      );
    }
    return PlaylistSearchPageResult(failure: mapBridgeSearchFailure(failure));
  }
  if (result.page <= 0 ||
      result.total < 0 ||
      result.playlists.length > result.total ||
      (result.hasMore && result.playlists.isEmpty)) {
    return const PlaylistSearchPageResult(
      failure: SearchFailure.invalidResponse,
    );
  }
  final playlists = <UserPlaylistSummary>[];
  for (final playlist in result.playlists) {
    if (playlist.providerId.trim().isEmpty ||
        playlist.opaqueId.trim().isEmpty ||
        playlist.title.trim().isEmpty ||
        (playlist.artworkUri?.trim().isEmpty ?? false) ||
        (playlist.trackCount != null && playlist.trackCount! < 0)) {
      return const PlaylistSearchPageResult(
        failure: SearchFailure.invalidResponse,
      );
    }
    playlists.add(
      UserPlaylistSummary(
        providerId: playlist.providerId,
        opaqueId: playlist.opaqueId,
        title: playlist.title,
        artworkUri: playlist.artworkUri,
        trackCount: playlist.trackCount,
      ),
    );
  }
  return PlaylistSearchPageResult(
    page: result.page,
    total: result.total,
    hasMore: result.hasMore,
    playlists: List.unmodifiable(playlists),
  );
}

@visibleForTesting
SearchFailure mapBridgeSearchFailure(
  bridge.QqMusicPlaylistSearchPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicPlaylistSearchPageLoadFailure.coreUnavailable =>
    SearchFailure.coreUnavailable,
  bridge.QqMusicPlaylistSearchPageLoadFailure.network => SearchFailure.network,
  bridge.QqMusicPlaylistSearchPageLoadFailure.serviceUnavailable =>
    SearchFailure.serviceUnavailable,
  bridge.QqMusicPlaylistSearchPageLoadFailure.invalidResponse =>
    SearchFailure.invalidResponse,
  bridge.QqMusicPlaylistSearchPageLoadFailure.cancelled =>
    SearchFailure.cancelled,
  bridge.QqMusicPlaylistSearchPageLoadFailure.alreadyRunning =>
    SearchFailure.alreadyRunning,
};
