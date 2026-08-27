import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
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

  testWidgets('Artist Albums load lazily, adapt, and preserve Track state', (
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
      title: 'Preserved track',
      artistNames: ['Synthetic artist'],
    );
    const album = AlbumSummary(
      providerId: 'qq-music',
      opaqueId: 'album:43001:fixtureAlbumMid',
      title: 'Synthetic album',
    );
    final albumGateway = _ArtistAlbumGateway(album);
    AlbumSummary? openedAlbum;
    final playback = QueuePlaybackController(
      _QueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ArtistPage(
          artist: artist,
          gateway: const _ArtistGateway(track),
          albumGateway: albumGateway,
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (value) => openedAlbum = value,
          onSignInAgain: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(albumGateway.requests, isEmpty);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(albumGateway.requests, [(artist, 0, 30)]);
    expect(find.byType(SliverList), findsOneWidget);
    expect(find.text('1 Album'), findsOneWidget);
    expect(find.text('Synthetic album'), findsOneWidget);

    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(albumGateway.requests, [(artist, 0, 30)]);

    await tester.tap(find.byKey(const ValueKey('artist-album-0')));
    expect(openedAlbum, album);

    await tester.tap(find.text('Tracks'));
    await tester.pumpAndSettle();
    expect(find.text('Preserved track'), findsOneWidget);
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(albumGateway.requests, [(artist, 0, 30)]);
    expect(find.text('Synthetic album'), findsOneWidget);
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

class _ArtistAlbumGateway implements ArtistAlbumGateway {
  _ArtistAlbumGateway(this.album);

  final AlbumSummary album;
  final List<(ArtistSummary, int, int)> requests = [];

  @override
  ArtistAlbumPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) {
    requests.add((artist, offset, size));
    return _ArtistAlbumOperation(
      ArtistAlbumPageResult(offset: offset, total: 1, albums: [album]),
    );
  }
}

class _ArtistAlbumOperation implements ArtistAlbumPageLoadOperation {
  const _ArtistAlbumOperation(this.result);

  final ArtistAlbumPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistAlbumPageResult> run() async => result;
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
