import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_page.dart';

void main() {
  testWidgets('search result can be queued or handed to playback', (
    tester,
  ) async {
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:searchMid:-',
      title: 'Search result',
      artistNames: ['Search artist'],
      albumTitle: 'Search album',
      durationSeconds: 180,
    );
    final search = _SearchGateway(track);
    final queue = _QueueGateway();
    final playback = QueuePlaybackController(
      queue,
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);
    ArtistSummary? openedArtist;

    await tester.pumpWidget(
      MaterialApp(
        home: TrackSearchPage(
          gateway: search,
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (_) {},
          onOpenArtist: (artist) => openedArtist = artist,
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('track-search-field')),
      '  search words  ',
    );
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(search.requests, [('search words', 1, 30)]);
    expect(find.text('Search result'), findsOneWidget);
    expect(find.text('Search artist · Search album'), findsOneWidget);
    expect(find.text('1 result for “search words”'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('track-search-artist-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-search-artist-0-1')));
    await tester.pumpAndSettle();
    expect(openedArtist?.name, 'Second artist');

    await tester.tap(find.byKey(const ValueKey('track-search-queue-0')));
    await tester.pumpAndSettle();
    expect(queue.pushedTracks, [track]);
    expect(find.text('Added to queue'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('track-search-result-0')));
    await tester.pumpAndSettle();
    expect(queue.replacedTracks, [track]);
    expect(queue.replacedIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tracks, Artists, and Albums preserve independent Search state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:searchMid:-',
      title: 'Track result',
      artistNames: ['Track credit'],
    );
    final trackSearch = _SearchGateway(track);
    final artistSearch = _ArtistSearchGateway();
    final albumSearch = _AlbumSearchGateway();
    final playback = QueuePlaybackController(
      _QueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);
    ArtistSummary? openedArtist;
    AlbumSummary? openedAlbum;

    await tester.pumpWidget(
      MaterialApp(
        home: TrackSearchPage(
          gateway: trackSearch,
          artistGateway: artistSearch,
          albumGateway: albumSearch,
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (album) => openedAlbum = album,
          onOpenArtist: (artist) => openedArtist = artist,
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );

    final field = find.byKey(const ValueKey('track-search-field'));
    await tester.enterText(field, 'track query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Track result'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('search-types')),
        matching: find.text('Artists'),
      ),
    );
    await tester.pumpAndSettle();
    expect(artistSearch.requests, [('track query', 1, 30)]);
    expect(find.text('Artist for track query'), findsOneWidget);

    await tester.enterText(field, 'artist query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(artistSearch.requests.last, ('artist query', 1, 30));
    expect(find.text('Artist for artist query'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('artist-search-result-0')));
    await tester.pumpAndSettle();
    expect(openedArtist?.name, 'Artist for artist query');

    final albumsChoice = find.descendant(
      of: find.byKey(const ValueKey('search-types')),
      matching: find.text('Albums'),
    );
    await tester.ensureVisible(albumsChoice);
    await tester.pumpAndSettle();
    await tester.tap(albumsChoice);
    await tester.pumpAndSettle();
    expect(albumSearch.requests, [('artist query', 1, 30)]);
    expect(find.text('Album for artist query'), findsOneWidget);

    await tester.enterText(field, 'album query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(albumSearch.requests.last, ('album query', 1, 30));
    expect(find.text('Album for album query'), findsOneWidget);

    final tracksChoice = find.descendant(
      of: find.byKey(const ValueKey('search-types')),
      matching: find.text('Tracks'),
    );
    await tester.ensureVisible(tracksChoice);
    await tester.pumpAndSettle();
    await tester.tap(tracksChoice);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller?.text, 'track query');
    expect(find.text('Track result'), findsOneWidget);

    final artistsChoice = find.descendant(
      of: find.byKey(const ValueKey('search-types')),
      matching: find.text('Artists'),
    );
    await tester.ensureVisible(artistsChoice);
    await tester.pumpAndSettle();
    await tester.tap(artistsChoice);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller?.text, 'artist query');
    expect(artistSearch.requests.length, 2);

    await tester.ensureVisible(albumsChoice);
    await tester.pumpAndSettle();
    await tester.tap(albumsChoice);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller?.text, 'album query');
    expect(albumSearch.requests.length, 2);
    await tester.tap(find.byKey(const ValueKey('album-search-result-0')));
    await tester.pumpAndSettle();
    expect(openedAlbum?.title, 'Album for album query');
    expect(tester.takeException(), isNull);
  });
}

class _SearchGateway implements TrackSearchGateway {
  _SearchGateway(this.track);

  final PlaylistTrackSummary track;
  final List<(String, int, int)> requests = [];

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return _SearchOperation(
      TrackSearchPageResult(
        page: page,
        total: 1,
        items: [
          TrackSearchItem(
            track: track,
            artists: const [
              ArtistSummary(
                providerId: 'qq-music',
                opaqueId: 'artist:61001:firstArtistMid',
                name: 'First artist',
              ),
              ArtistSummary(
                providerId: 'qq-music',
                opaqueId: 'artist:61002:secondArtistMid',
                name: 'Second artist',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchOperation implements TrackSearchPageLoadOperation {
  const _SearchOperation(this.result);

  final TrackSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<TrackSearchPageResult> run() async => result;
}

class _ArtistSearchGateway implements ArtistSearchGateway {
  final List<(String, int, int)> requests = [];

  @override
  ArtistSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return _ArtistSearchOperation(
      ArtistSearchPageResult(
        page: page,
        total: 1,
        artists: [
          ArtistSummary(
            providerId: 'qq-music',
            opaqueId: 'artist:61001:fixtureArtistMid',
            name: 'Artist for $query',
          ),
        ],
      ),
    );
  }
}

class _ArtistSearchOperation implements ArtistSearchPageLoadOperation {
  const _ArtistSearchOperation(this.result);

  final ArtistSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistSearchPageResult> run() async => result;
}

class _AlbumSearchGateway implements AlbumSearchGateway {
  final List<(String, int, int)> requests = [];

  @override
  AlbumSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return _AlbumSearchOperation(
      AlbumSearchPageResult(
        page: page,
        total: 1,
        albums: [
          AlbumSummary(
            providerId: 'qq-music',
            opaqueId: 'album:43001:fixtureAlbumMid',
            title: 'Album for $query',
          ),
        ],
      ),
    );
  }
}

class _AlbumSearchOperation implements AlbumSearchPageLoadOperation {
  const _AlbumSearchOperation(this.result);

  final AlbumSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumSearchPageResult> run() async => result;
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
