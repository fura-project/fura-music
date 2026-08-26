import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/album/album_page.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

void main() {
  testWidgets('Album Tracks can be queued, played, and returned from', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const album = AlbumSummary(
      providerId: 'qq-music',
      opaqueId: 'album:51001:fixtureAlbumMid',
      title: 'Synthetic album',
    );
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:fixtureMid:-',
      title: 'Synthetic track',
      artistNames: ['Album artist'],
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
    ArtistSummary? openedArtist;

    await tester.pumpWidget(
      MaterialApp(
        home: AlbumPage(
          album: album,
          gateway: const _AlbumGateway(track),
          detailsGateway: const _AlbumDetailsGateway(),
          queuePlaybackController: playback,
          onBack: () => backCalls += 1,
          onOpenArtist: (artist) => openedArtist = artist,
          onSignInAgain: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Canonical album'), findsOneWidget);
    expect(find.text('Canonical artist'), findsOneWidget);
    expect(find.textContaining('2026-08-26'), findsOneWidget);
    expect(find.text('1 Track'), findsOneWidget);
    expect(find.text('Synthetic track'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('album-open-artist')));
    await tester.pumpAndSettle();
    expect(openedArtist?.name, 'Canonical artist');

    await tester.tap(find.byKey(const ValueKey('album-about')));
    await tester.pumpAndSettle();
    expect(find.text('Canonical description'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('album-queue-0')));
    await tester.pumpAndSettle();
    expect(queue.pushedTracks, [track]);
    expect(find.text('Added to queue'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('album-track-0')));
    await tester.pumpAndSettle();
    expect(queue.replacedTracks, [track]);
    expect(queue.replacedIndex, 0);

    await tester.tap(find.byKey(const ValueKey('album-back')));
    expect(backCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Album detail failure leaves desktop Tracks usable and retries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const album = AlbumSummary(
      providerId: 'qq-music',
      opaqueId: 'album:51001:fixtureAlbumMid',
      title: 'Summary album',
    );
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:fixtureMid:-',
      title: 'Still playable Track',
      artistNames: ['Album artist'],
    );
    final details = _ScriptedAlbumDetailsGateway([
      const AlbumDetailsResult(failure: AlbumDetailsFailure.network),
      const AlbumDetailsResult(
        details: AlbumDetails(
          album: AlbumSummary(
            providerId: 'qq-music',
            opaqueId: 'album:51001:fixtureAlbumMid',
            title: 'Retried canonical album',
          ),
          artists: [
            ArtistSummary(
              providerId: 'qq-music',
              opaqueId: 'artist:52001:firstArtistMid',
              name: 'First Artist',
            ),
            ArtistSummary(
              providerId: 'qq-music',
              opaqueId: 'artist:52002:secondArtistMid',
              name: 'Second Artist',
            ),
          ],
          description: 'Desktop canonical description',
        ),
      ),
    ]);
    final playback = QueuePlaybackController(
      _QueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);
    ArtistSummary? openedArtist;

    await tester.pumpWidget(
      MaterialApp(
        home: AlbumPage(
          album: album,
          gateway: const _AlbumGateway(track),
          detailsGateway: details,
          queuePlaybackController: playback,
          onBack: () {},
          onOpenArtist: (artist) => openedArtist = artist,
          onSignInAgain: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Still playable Track'), findsOneWidget);
    expect(find.text('Album details are offline.'), findsOneWidget);
    expect(find.byKey(const ValueKey('album-open-artist')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('album-details-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Retried canonical album'), findsOneWidget);
    expect(find.text('Still playable Track'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('album-open-artist')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('album-artist-1')));
    await tester.pumpAndSettle();
    expect(openedArtist?.name, 'Second Artist');

    await tester.tap(find.byKey(const ValueKey('album-about')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Desktop canonical description'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _AlbumDetailsGateway implements AlbumDetailsGateway {
  const _AlbumDetailsGateway();

  @override
  AlbumDetailsLoadOperation beginLoad(AlbumSummary album) =>
      const _AlbumDetailsOperation();
}

class _AlbumDetailsOperation implements AlbumDetailsLoadOperation {
  const _AlbumDetailsOperation();

  @override
  bool cancel() => true;

  @override
  Future<AlbumDetailsResult> run() async => const AlbumDetailsResult(
    details: AlbumDetails(
      album: AlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:51001:fixtureAlbumMid',
        title: 'Canonical album',
      ),
      artists: [
        ArtistSummary(
          providerId: 'qq-music',
          opaqueId: 'artist:52001:fixtureArtistMid',
          name: 'Canonical artist',
        ),
      ],
      subtitle: 'Canonical subtitle',
      releaseDate: '2026-08-26',
      description: 'Canonical description',
      language: 'Synthetic language',
      albumType: 'Synthetic type',
      genre: 'Synthetic genre',
      company: 'Synthetic company',
    ),
  );
}

class _ScriptedAlbumDetailsGateway implements AlbumDetailsGateway {
  _ScriptedAlbumDetailsGateway(this.results);

  final List<AlbumDetailsResult> results;
  int _next = 0;

  @override
  AlbumDetailsLoadOperation beginLoad(AlbumSummary album) =>
      _ScriptedAlbumDetailsOperation(results[_next++]);
}

class _ScriptedAlbumDetailsOperation implements AlbumDetailsLoadOperation {
  const _ScriptedAlbumDetailsOperation(this.result);

  final AlbumDetailsResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumDetailsResult> run() async => result;
}

class _AlbumGateway implements AlbumTrackGateway {
  const _AlbumGateway(this.track);

  final PlaylistTrackSummary track;

  @override
  AlbumTrackPageLoadOperation beginLoad({
    required AlbumSummary album,
    required int offset,
    required int size,
  }) => _AlbumOperation(
    AlbumTrackPageResult(offset: offset, total: 1, tracks: [track]),
  );
}

class _AlbumOperation implements AlbumTrackPageLoadOperation {
  const _AlbumOperation(this.result);

  final AlbumTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumTrackPageResult> run() async => result;
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
