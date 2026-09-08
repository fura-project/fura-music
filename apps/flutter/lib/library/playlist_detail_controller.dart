import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/paged_tracks_controller.dart';

export 'package:flutterustmusic/library/paged_tracks_controller.dart'
    show PlaylistDetailStage;

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
       );

  static const pageSize = PagedTracksController.pageSize;
  final UserPlaylistSummary playlist;
}
