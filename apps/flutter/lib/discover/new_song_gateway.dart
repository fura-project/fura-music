import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/new_songs.dart' as bridge;

enum NewSongCategory {
  mainlandChina,
  western,
  japan,
  korea,
  latest,
  hongKongTaiwan,
}

enum NewSongFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class NewSongResult {
  const NewSongResult({
    required this.category,
    this.tracks = const [],
    this.failure,
  });

  final NewSongCategory category;
  final List<PlaylistTrackSummary> tracks;
  final NewSongFailure? failure;
}

abstract interface class NewSongGateway {
  NewSongLoadOperation beginLoad({required NewSongCategory category});
}

abstract interface class NewSongLoadOperation {
  Future<NewSongResult> run();
  bool cancel();
}

typedef NewSongLoadOperationFactory = NewSongLoadOperation Function(
  NewSongCategory category,
);

class RustNewSongGateway implements NewSongGateway {
  const RustNewSongGateway({NewSongLoadOperationFactory? operationFactory})
    : _operationFactory = operationFactory ?? _beginRustLoad;

  final NewSongLoadOperationFactory _operationFactory;

  @override
  NewSongLoadOperation beginLoad({required NewSongCategory category}) =>
      _operationFactory(category);
}

NewSongLoadOperation _beginRustLoad(NewSongCategory category) =>
    _RustNewSongLoadOperation(
      category,
      bridge.beginQqMusicNewSongsLoad(category: _bridgeCategory(category)),
    );

class _RustNewSongLoadOperation implements NewSongLoadOperation {
  const _RustNewSongLoadOperation(this._expectedCategory, this._handle);

  final NewSongCategory _expectedCategory;
  final bridge.QqMusicNewSongsLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<NewSongResult> run() async {
    try {
      return mapBridgeNewSongs(await _handle.run(), _expectedCategory);
    } on Object {
      return NewSongResult(
        category: _expectedCategory,
        failure: NewSongFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
NewSongResult mapBridgeNewSongs(
  bridge.QqMusicNewSongsLoad result,
  NewSongCategory expectedCategory,
) {
  final category = mapBridgeNewSongCategory(result.category);
  if (category != expectedCategory) {
    return NewSongResult(
      category: expectedCategory,
      failure: NewSongFailure.invalidResponse,
    );
  }
  final failure = result.failure;
  if (failure != null) {
    if (result.tracks.isNotEmpty) {
      return NewSongResult(
        category: category,
        failure: NewSongFailure.invalidResponse,
      );
    }
    return NewSongResult(
      category: category,
      failure: mapBridgeNewSongFailure(failure),
    );
  }

  final tracks = <PlaylistTrackSummary>[];
  for (final track in result.tracks) {
    final mapped = mapBridgeLibraryTrackSummary(track);
    if (mapped == null) {
      return NewSongResult(
        category: category,
        failure: NewSongFailure.invalidResponse,
      );
    }
    tracks.add(mapped);
  }
  return NewSongResult(category: category, tracks: List.unmodifiable(tracks));
}

@visibleForTesting
NewSongCategory mapBridgeNewSongCategory(
  bridge.QqMusicNewSongCategory category,
) => switch (category) {
  bridge.QqMusicNewSongCategory.mainlandChina => NewSongCategory.mainlandChina,
  bridge.QqMusicNewSongCategory.western => NewSongCategory.western,
  bridge.QqMusicNewSongCategory.japan => NewSongCategory.japan,
  bridge.QqMusicNewSongCategory.korea => NewSongCategory.korea,
  bridge.QqMusicNewSongCategory.latest => NewSongCategory.latest,
  bridge.QqMusicNewSongCategory.hongKongTaiwan =>
    NewSongCategory.hongKongTaiwan,
};

bridge.QqMusicNewSongCategory _bridgeCategory(NewSongCategory category) =>
    switch (category) {
      NewSongCategory.mainlandChina =>
        bridge.QqMusicNewSongCategory.mainlandChina,
      NewSongCategory.western => bridge.QqMusicNewSongCategory.western,
      NewSongCategory.japan => bridge.QqMusicNewSongCategory.japan,
      NewSongCategory.korea => bridge.QqMusicNewSongCategory.korea,
      NewSongCategory.latest => bridge.QqMusicNewSongCategory.latest,
      NewSongCategory.hongKongTaiwan =>
        bridge.QqMusicNewSongCategory.hongKongTaiwan,
    };

@visibleForTesting
NewSongFailure mapBridgeNewSongFailure(
  bridge.QqMusicNewSongsLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicNewSongsLoadFailure.coreUnavailable =>
    NewSongFailure.coreUnavailable,
  bridge.QqMusicNewSongsLoadFailure.network => NewSongFailure.network,
  bridge.QqMusicNewSongsLoadFailure.serviceUnavailable =>
    NewSongFailure.serviceUnavailable,
  bridge.QqMusicNewSongsLoadFailure.invalidResponse =>
    NewSongFailure.invalidResponse,
  bridge.QqMusicNewSongsLoadFailure.cancelled => NewSongFailure.cancelled,
  bridge.QqMusicNewSongsLoadFailure.alreadyRunning =>
    NewSongFailure.alreadyRunning,
};
