import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as library_bridge;
import 'package:flutterustmusic/src/rust/api/listening.dart' as bridge;

abstract interface class RecentListeningGateway {
  void observe(PlaylistTrackSummary? track, int positionMs, bool playing);
  PlaylistTrackSummary? choose();
  void dispose();
}

class RustRecentListeningGateway implements RecentListeningGateway {
  bridge.RecentListeningHandle? _handle;
  bool _disposed = false;

  @override
  void observe(PlaylistTrackSummary? track, int positionMs, bool playing) {
    if (_disposed || (track == null && _handle == null)) return;
    try {
      final handle = _handle ??= bridge.createRecentListening();
      handle.observe(
        track: track == null
            ? null
            : library_bridge.LibraryTrackSummary(
                providerId: track.providerId,
                opaqueId: track.opaqueId,
                membershipOpaqueId: track.membershipIdentity,
                title: track.title,
                subtitle: track.subtitle,
                artistNames: track.artistNames,
                artists: const [],
                albumTitle: track.albumTitle,
                album: null,
                artworkUri: track.artworkUri,
                durationSeconds: track.durationSeconds,
              ),
        positionMs: positionMs.clamp(0, 0xffffffff),
        playing: playing,
      );
    } on Object {
      // Recommendation context must never interrupt playback when Core is absent.
    }
  }

  @override
  PlaylistTrackSummary? choose() {
    if (_disposed) return null;
    try {
      final track = _handle?.choose();
      return track == null ? null : mapBridgeLibraryTrackSummary(track);
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _handle = null;
  }
}
