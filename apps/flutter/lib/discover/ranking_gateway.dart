import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/rankings.dart' as bridge;

class RankingSummary {
  const RankingSummary({
    required this.providerId,
    required this.opaqueId,
    required this.title,
    this.period,
    this.artworkUri,
    this.trackCount,
  });

  final String providerId;
  final String opaqueId;
  final String title;
  final String? period;
  final String? artworkUri;
  final int? trackCount;
}

class RankingGroup {
  const RankingGroup({required this.title, required this.rankings});

  final String title;
  final List<RankingSummary> rankings;
}

enum RankingFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class RankingGroupResult {
  const RankingGroupResult({this.groups = const [], this.failure});

  final List<RankingGroup> groups;
  final RankingFailure? failure;
}

class RankingTrackPageResult {
  const RankingTrackPageResult({
    this.ranking,
    this.offset = 0,
    this.total = 0,
    this.hasMore = false,
    this.tracks = const [],
    this.failure,
  });

  final RankingSummary? ranking;
  final int offset;
  final int total;
  final bool hasMore;
  final List<PlaylistTrackSummary> tracks;
  final RankingFailure? failure;
}

abstract interface class RankingGateway {
  RankingGroupLoadOperation beginGroupLoad();

  RankingTrackPageLoadOperation beginTrackLoad({
    required RankingSummary ranking,
    required int offset,
    required int size,
  });
}

abstract interface class RankingGroupLoadOperation {
  Future<RankingGroupResult> run();
  bool cancel();
}

abstract interface class RankingTrackPageLoadOperation {
  Future<RankingTrackPageResult> run();
  bool cancel();
}

typedef RankingGroupLoadOperationFactory = RankingGroupLoadOperation Function();
typedef RankingTrackPageLoadOperationFactory =
    RankingTrackPageLoadOperation Function(
      RankingSummary ranking,
      int offset,
      int size,
    );

class RustRankingGateway implements RankingGateway {
  const RustRankingGateway({
    RankingGroupLoadOperationFactory? groupOperationFactory,
    RankingTrackPageLoadOperationFactory? trackOperationFactory,
  }) : _groupOperationFactory = groupOperationFactory ?? _beginRustGroupLoad,
       _trackOperationFactory = trackOperationFactory ?? _beginRustTrackLoad;

  final RankingGroupLoadOperationFactory _groupOperationFactory;
  final RankingTrackPageLoadOperationFactory _trackOperationFactory;

  @override
  RankingGroupLoadOperation beginGroupLoad() => _groupOperationFactory();

  @override
  RankingTrackPageLoadOperation beginTrackLoad({
    required RankingSummary ranking,
    required int offset,
    required int size,
  }) => _trackOperationFactory(ranking, offset, size);
}

RankingGroupLoadOperation _beginRustGroupLoad() =>
    _RustRankingGroupLoadOperation(bridge.beginQqMusicRankingGroupLoad());

RankingTrackPageLoadOperation _beginRustTrackLoad(
  RankingSummary ranking,
  int offset,
  int size,
) => _RustRankingTrackPageLoadOperation(
  ranking,
  bridge.beginQqMusicRankingTrackPageLoad(
    providerId: ranking.providerId,
    opaqueRankingId: ranking.opaqueId,
    offset: offset,
    size: size,
  ),
);

class _RustRankingGroupLoadOperation implements RankingGroupLoadOperation {
  const _RustRankingGroupLoadOperation(this._handle);

  final bridge.QqMusicRankingGroupLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<RankingGroupResult> run() async {
    try {
      return mapBridgeRankingGroups(await _handle.run());
    } on Object {
      return const RankingGroupResult(failure: RankingFailure.coreUnavailable);
    }
  }
}

class _RustRankingTrackPageLoadOperation
    implements RankingTrackPageLoadOperation {
  const _RustRankingTrackPageLoadOperation(this._expected, this._handle);

  final RankingSummary _expected;
  final bridge.QqMusicRankingTrackPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<RankingTrackPageResult> run() async {
    try {
      return mapBridgeRankingTrackPage(await _handle.run(), _expected);
    } on Object {
      return const RankingTrackPageResult(
        failure: RankingFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
RankingGroupResult mapBridgeRankingGroups(
  bridge.QqMusicRankingGroupLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.groups.isNotEmpty) {
      return const RankingGroupResult(failure: RankingFailure.invalidResponse);
    }
    return RankingGroupResult(failure: mapBridgeRankingFailure(failure));
  }
  final groups = <RankingGroup>[];
  for (final group in result.groups) {
    if (group.title.trim().isEmpty || group.rankings.isEmpty) {
      return const RankingGroupResult(failure: RankingFailure.invalidResponse);
    }
    final rankings = <RankingSummary>[];
    for (final ranking in group.rankings) {
      final mapped = _mapSummary(ranking);
      if (mapped == null) {
        return const RankingGroupResult(
          failure: RankingFailure.invalidResponse,
        );
      }
      rankings.add(mapped);
    }
    groups.add(
      RankingGroup(title: group.title, rankings: List.unmodifiable(rankings)),
    );
  }
  return RankingGroupResult(groups: List.unmodifiable(groups));
}

@visibleForTesting
RankingTrackPageResult mapBridgeRankingTrackPage(
  bridge.QqMusicRankingTrackPageLoad result,
  RankingSummary expected,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.ranking != null ||
        result.offset != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.tracks.isNotEmpty) {
      return const RankingTrackPageResult(
        failure: RankingFailure.invalidResponse,
      );
    }
    return RankingTrackPageResult(failure: mapBridgeRankingFailure(failure));
  }
  final ranking = result.ranking == null ? null : _mapSummary(result.ranking!);
  if (ranking == null ||
      ranking.providerId != expected.providerId ||
      ranking.opaqueId != expected.opaqueId ||
      result.offset < 0 ||
      result.total < 0 ||
      result.offset + result.tracks.length > result.total ||
      (result.hasMore && result.tracks.isEmpty)) {
    return const RankingTrackPageResult(
      failure: RankingFailure.invalidResponse,
    );
  }
  final tracks = <PlaylistTrackSummary>[];
  for (final track in result.tracks) {
    final mapped = mapBridgeLibraryTrackSummary(track);
    if (mapped == null) {
      return const RankingTrackPageResult(
        failure: RankingFailure.invalidResponse,
      );
    }
    tracks.add(mapped);
  }
  return RankingTrackPageResult(
    ranking: ranking,
    offset: result.offset,
    total: result.total,
    hasMore: result.hasMore,
    tracks: List.unmodifiable(tracks),
  );
}

RankingSummary? _mapSummary(bridge.CatalogRankingSummary ranking) {
  if (ranking.providerId.trim().isEmpty ||
      ranking.opaqueId.trim().isEmpty ||
      ranking.title.trim().isEmpty ||
      (ranking.period != null && ranking.period!.trim().isEmpty) ||
      (ranking.artworkUri != null && ranking.artworkUri!.trim().isEmpty) ||
      (ranking.trackCount != null && ranking.trackCount! < 0)) {
    return null;
  }
  return RankingSummary(
    providerId: ranking.providerId,
    opaqueId: ranking.opaqueId,
    title: ranking.title,
    period: ranking.period,
    artworkUri: ranking.artworkUri,
    trackCount: ranking.trackCount,
  );
}

@visibleForTesting
RankingFailure mapBridgeRankingFailure(
  bridge.QqMusicRankingLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicRankingLoadFailure.coreUnavailable =>
    RankingFailure.coreUnavailable,
  bridge.QqMusicRankingLoadFailure.network => RankingFailure.network,
  bridge.QqMusicRankingLoadFailure.serviceUnavailable =>
    RankingFailure.serviceUnavailable,
  bridge.QqMusicRankingLoadFailure.invalidResponse =>
    RankingFailure.invalidResponse,
  bridge.QqMusicRankingLoadFailure.cancelled => RankingFailure.cancelled,
  bridge.QqMusicRankingLoadFailure.alreadyRunning =>
    RankingFailure.alreadyRunning,
};
