import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum CollectionPlaybackFailure {
  coreUnavailable,
  authenticationRequired,
  credentialRejected,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

/// One already-validated Provider page prepared for app-lifetime playback.
///
/// The cursor remains opaque to the Queue owner beyond monotonic integer
/// progression. Raw-offset and page-number Providers both adapt their native
/// continuation before crossing this boundary; visible row counts never
/// become cursors.
class CollectionPlaybackPage {
  const CollectionPlaybackPage({
    required this.requestCursor,
    required this.nextCursor,
    required this.hasMore,
    this.tracks = const [],
    this.omittedTrackCount = 0,
    this.failure,
  });

  final int requestCursor;
  final int nextCursor;
  final bool hasMore;
  final List<PlaylistTrackSummary> tracks;
  final int omittedTrackCount;
  final CollectionPlaybackFailure? failure;
}

abstract interface class CollectionPlaybackPageOperation {
  Future<CollectionPlaybackPage> run();

  bool cancel();
}

class CallbackCollectionPlaybackPageOperation
    implements CollectionPlaybackPageOperation {
  const CallbackCollectionPlaybackPageOperation(this._run, this._cancel);

  final Future<CollectionPlaybackPage> Function() _run;
  final bool Function() _cancel;

  @override
  Future<CollectionPlaybackPage> run() => _run();

  @override
  bool cancel() => _cancel();
}

typedef CollectionPlaybackPageLoader = CollectionPlaybackPageOperation Function(
  int cursor,
);

/// Bounded source-specific behavior applied by the app-lifetime Queue owner.
///
/// Most finite collections use the default policy and load only from playback
/// or Queue viewport demand. Station-like sources may request a small startup
/// buffer without turning playback start into a load-all operation.
class CollectionPlaybackPolicy {
  const CollectionPlaybackPolicy({
    this.initialQueueTarget = 0,
    this.maxInitialPages = 0,
  }) : assert(initialQueueTarget >= 0),
       assert(maxInitialPages >= 0),
       assert(initialQueueTarget == 0 || maxInitialPages > 0);

  final int initialQueueTarget;
  final int maxInitialPages;

  bool get hasInitialFill => initialQueueTarget > 0 && maxInitialPages > 0;
}

/// A logical collection detached from its presenting page/controller.
///
/// [loader] closes over the Provider gateway operation factory, not a page
/// controller. QueuePlaybackController copies this value into its app-lifetime
/// state, so navigation and widget disposal cannot cancel playback paging.
class CollectionPlaybackSource {
  CollectionPlaybackSource({
    required this.sourceId,
    required this.providerId,
    required List<PlaylistTrackSummary> initialTracks,
    required this.nextCursor,
    required this.hasMore,
    required this.loader,
    this.policy = const CollectionPlaybackPolicy(),
  }) : initialTracks = List.unmodifiable(initialTracks);

  final String sourceId;
  final String providerId;
  final List<PlaylistTrackSummary> initialTracks;
  final int nextCursor;
  final bool hasMore;
  final CollectionPlaybackPageLoader loader;
  final CollectionPlaybackPolicy policy;
}
