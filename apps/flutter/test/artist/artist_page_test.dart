import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/artist/artist_page.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

void main() {
  testWidgets('Artist Tracks can be queued, played, and returned from', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const artist = ArtistSummary(
      providerId: 'qq-music',
      opaqueId: 'artist:61001:fixtureArtistMid',
      name: 'Synthetic artist',
    );
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:fixtureMid:-',
      title: 'Synthetic track',
      artistNames: ['Synthetic artist'],
      albumTitle: 'Synthetic album',
    );
    final queue = _QueueGateway();
    final playback = QueuePlaybackController(
      queue,
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);
    var backCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ArtistPage(
          artist: artist,
          gateway: const _ArtistGateway(track),
          queuePlaybackController: playback,
          onBack: () => backCalls += 1,
          onSignInAgain: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Synthetic artist'), findsWidgets);
    expect(find.text('1 Track'), findsOneWidget);
    expect(find.text('Synthetic track'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('artist-queue-0')));
    await tester.pumpAndSettle();
    expect(queue.pushedTracks, [track]);
    expect(find.text('Added to queue'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('artist-track-0')));
    await tester.pumpAndSettle();
    expect(queue.replacedTracks, [track]);
    expect(queue.replacedIndex, 0);

    await tester.tap(find.byKey(const ValueKey('artist-back')));
    expect(backCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

class _ArtistGateway implements ArtistTrackGateway {
  const _ArtistGateway(this.track);

  final PlaylistTrackSummary track;

  @override
  ArtistTrackPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) => _ArtistOperation(
    ArtistTrackPageResult(offset: offset, total: 1, tracks: [track]),
  );
}

class _ArtistOperation implements ArtistTrackPageLoadOperation {
  const _ArtistOperation(this.result);

  final ArtistTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistTrackPageResult> run() async => result;
}

class _QueueGateway implements PlaybackQueueGateway {
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
    return PlaybackQueueResult(snapshot: _snapshot, currentChanged: true);
  }

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) {
    pushedTracks.add(track);
    final tracks = [..._snapshot.tracks, track];
    final currentChanged = _snapshot.currentIndex == null;
    _snapshot = _queueSnapshot(tracks, _snapshot.currentIndex ?? 0);
    return PlaybackQueueResult(
      snapshot: _snapshot,
      currentChanged: currentChanged,
    );
  }

  @override
  PlaybackQueueResult advance() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult clear() {
    _snapshot = PlaybackQueueSnapshot.empty();
    return PlaybackQueueResult(snapshot: _snapshot, currentChanged: true);
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

class _UnavailableMediaGateway implements MediaResolutionGateway {
  const _UnavailableMediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => const _UnavailableMediaOperation();
}

class _UnavailableMediaOperation implements MediaResolutionOperation {
  const _UnavailableMediaOperation();

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async =>
      const MediaResolutionResult(failure: MediaResolutionFailure.unavailable);
}

class _NeverAudioEngine implements ForegroundAudioEngine {
  const _NeverAudioEngine();

  @override
  Future<ForegroundAudioSession> loadRemote(Uri source) =>
      throw StateError('audio should not load for an unavailable source');
}
