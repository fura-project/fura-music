import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';

class TestPlaybackQueueGateway implements PlaybackQueueGateway {
  PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot.empty();
  List<PlaylistTrackSummary> replacedTracks = const [];
  final List<PlaylistTrackSummary> pushedTracks = [];
  int? replacedIndex;

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) {
    replacedTracks = List.of(tracks);
    replacedIndex = currentIndex;
    _snapshot = _queueSnapshot(tracks, currentIndex);
    return PlaybackQueueResult(snapshot: _snapshot, playbackRequested: true);
  }

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) {
    pushedTracks.add(track);
    final tracks = [..._snapshot.tracks, track];
    final playbackRequested = _snapshot.currentIndex == null;
    _snapshot = _queueSnapshot(tracks, _snapshot.currentIndex ?? 0);
    return PlaybackQueueResult(
      snapshot: _snapshot,
      playbackRequested: playbackRequested,
    );
  }

  @override
  PlaybackQueueResult advance() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult clear() {
    _snapshot = PlaybackQueueSnapshot.empty();
    return PlaybackQueueResult(snapshot: _snapshot, playbackRequested: true);
  }

  @override
  PlaybackQueueResult completeCurrent() =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult remove(int index) =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult rewind() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult select(int index) =>
      PlaybackQueueResult(snapshot: _snapshot);
}

PlaybackQueueSnapshot _queueSnapshot(
  List<PlaylistTrackSummary> tracks,
  int? currentIndex,
) => PlaybackQueueSnapshot(
  tracks: tracks,
  currentIndex: currentIndex,
  hasPrevious: currentIndex != null && currentIndex > 0,
  hasNext: currentIndex != null && currentIndex + 1 < tracks.length,
);
