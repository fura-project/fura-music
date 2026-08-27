import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/comments.dart' as bridge;

class TrackCommentSummary {
  const TrackCommentSummary({
    required this.providerId,
    required this.opaqueId,
    required this.authorDisplayName,
    required this.content,
    required this.publishedAtUnixSeconds,
    required this.praiseCount,
  });

  final String providerId;
  final String opaqueId;
  final String authorDisplayName;
  final String content;
  final int publishedAtUnixSeconds;
  final int praiseCount;
}

enum TrackCommentFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

class TrackCommentPageResult {
  const TrackCommentPageResult({
    this.offset = 0,
    this.total = 0,
    this.hasMore = false,
    this.hotComments = const [],
    this.latestComments = const [],
    this.failure,
  });

  final int offset;
  final int total;
  final bool hasMore;
  final List<TrackCommentSummary> hotComments;
  final List<TrackCommentSummary> latestComments;
  final TrackCommentFailure? failure;
}

abstract interface class TrackCommentGateway {
  TrackCommentPageLoadOperation beginLoad({
    required PlaylistTrackSummary track,
    required int offset,
    required int size,
  });
}

abstract interface class TrackCommentPageLoadOperation {
  Future<TrackCommentPageResult> run();
  bool cancel();
}

typedef TrackCommentPageLoadOperationFactory =
    TrackCommentPageLoadOperation Function(
      String providerId,
      String opaqueTrackId,
      int offset,
      int size,
    );

class RustTrackCommentGateway implements TrackCommentGateway {
  const RustTrackCommentGateway({
    TrackCommentPageLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final TrackCommentPageLoadOperationFactory _operationFactory;

  @override
  TrackCommentPageLoadOperation beginLoad({
    required PlaylistTrackSummary track,
    required int offset,
    required int size,
  }) => _operationFactory(track.providerId, track.opaqueId, offset, size);
}

TrackCommentPageLoadOperation _beginRustLoad(
  String providerId,
  String opaqueTrackId,
  int offset,
  int size,
) => _RustTrackCommentPageLoadOperation(
  bridge.beginQqMusicTrackCommentPageLoad(
    providerId: providerId,
    opaqueTrackId: opaqueTrackId,
    offset: offset,
    size: size,
  ),
);

class _RustTrackCommentPageLoadOperation
    implements TrackCommentPageLoadOperation {
  const _RustTrackCommentPageLoadOperation(this._handle);

  final bridge.QqMusicTrackCommentPageLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<TrackCommentPageResult> run() async {
    try {
      return mapBridgeTrackCommentPage(await _handle.run());
    } on Object {
      return const TrackCommentPageResult(
        failure: TrackCommentFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
TrackCommentPageResult mapBridgeTrackCommentPage(
  bridge.QqMusicTrackCommentPageLoad result,
) {
  final failure = result.failure;
  if (failure != null) {
    if (result.offset != 0 ||
        result.total != 0 ||
        result.hasMore ||
        result.hotComments.isNotEmpty ||
        result.latestComments.isNotEmpty) {
      return const TrackCommentPageResult(
        failure: TrackCommentFailure.invalidResponse,
      );
    }
    return TrackCommentPageResult(
      failure: mapBridgeTrackCommentFailure(failure),
    );
  }
  final pageEnd = result.offset + result.latestComments.length;
  if (result.offset < 0 ||
      result.total < 0 ||
      pageEnd > result.total ||
      (result.offset > 0 && result.hotComments.isNotEmpty) ||
      (result.hasMore &&
          (result.latestComments.isEmpty || pageEnd >= result.total)) ||
      (!result.hasMore &&
          result.latestComments.isNotEmpty &&
          pageEnd < result.total)) {
    return const TrackCommentPageResult(
      failure: TrackCommentFailure.invalidResponse,
    );
  }
  final hotComments = _mapComments(result.hotComments);
  final latestComments = _mapComments(result.latestComments);
  if (hotComments == null || latestComments == null) {
    return const TrackCommentPageResult(
      failure: TrackCommentFailure.invalidResponse,
    );
  }
  return TrackCommentPageResult(
    offset: result.offset,
    total: result.total,
    hasMore: result.hasMore,
    hotComments: hotComments,
    latestComments: latestComments,
  );
}

List<TrackCommentSummary>? _mapComments(
  List<bridge.TrackCommentSummary> comments,
) {
  final mapped = <TrackCommentSummary>[];
  for (final comment in comments) {
    if (comment.providerId.trim().isEmpty ||
        comment.opaqueId.trim().isEmpty ||
        comment.authorDisplayName.trim().isEmpty ||
        comment.content.trim().isEmpty ||
        comment.publishedAtUnixSeconds <= 0 ||
        comment.praiseCount < 0) {
      return null;
    }
    mapped.add(
      TrackCommentSummary(
        providerId: comment.providerId,
        opaqueId: comment.opaqueId,
        authorDisplayName: comment.authorDisplayName,
        content: comment.content,
        publishedAtUnixSeconds: comment.publishedAtUnixSeconds,
        praiseCount: comment.praiseCount,
      ),
    );
  }
  return List.unmodifiable(mapped);
}

@visibleForTesting
TrackCommentFailure mapBridgeTrackCommentFailure(
  bridge.QqMusicTrackCommentPageLoadFailure failure,
) => switch (failure) {
  bridge.QqMusicTrackCommentPageLoadFailure.coreUnavailable =>
    TrackCommentFailure.coreUnavailable,
  bridge.QqMusicTrackCommentPageLoadFailure.network =>
    TrackCommentFailure.network,
  bridge.QqMusicTrackCommentPageLoadFailure.serviceUnavailable =>
    TrackCommentFailure.serviceUnavailable,
  bridge.QqMusicTrackCommentPageLoadFailure.invalidResponse =>
    TrackCommentFailure.invalidResponse,
  bridge.QqMusicTrackCommentPageLoadFailure.cancelled =>
    TrackCommentFailure.cancelled,
  bridge.QqMusicTrackCommentPageLoadFailure.alreadyRunning =>
    TrackCommentFailure.alreadyRunning,
};
