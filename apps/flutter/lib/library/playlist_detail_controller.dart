import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/paged_tracks_controller.dart';

export 'package:flutterustmusic/library/paged_tracks_controller.dart'
    show CollectionSearchScanStage, PlaylistDetailStage;

/// Playlist identity adapter over the common track-page scheduler.
class PlaylistDetailController extends PagedTracksController {
  PlaylistDetailController(
    this.playlist,
    PlaylistDetailGateway gateway, {
    super.loadAllPageInterval,
    super.postTransientPageInterval,
    super.transientRetryDelays,
    super.delay,
  }) : super(
         (offset, size) =>
             gateway.beginLoad(playlist: playlist, offset: offset, size: size),
         readCachedContinuation: gateway is CachedPlaylistTrackPagesGateway
             ? (fromOffset, size) =>
                   (gateway as CachedPlaylistTrackPagesGateway)
                       .readCachedContinuation(
                         playlist: playlist,
                         fromOffset: fromOffset,
                         size: size,
                       )
             : null,
         readCachedSnapshotRevision: gateway is CachedPlaylistTrackPagesGateway
             ? () => (gateway as CachedPlaylistTrackPagesGateway)
                   .cachedSnapshotRevision(playlist: playlist)
             : null,
       );

  static const pageSize = PagedTracksController.pageSize;
  final UserPlaylistSummary playlist;
}
