import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/artist/artist_page.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_locale.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

import '../support/test_playback_queue_gateway.dart';

final AppLocalizations _en = lookupAppLocalizations(englishAppLocale);

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
    final queue = TestPlaybackQueueGateway();
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
    expect(find.text(_en.artistTrackCount(1)), findsOneWidget);
    expect(find.text('Synthetic track'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('artist-context-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.commonAddToQueue));
    await tester.pumpAndSettle();
    expect(queue.pushedTracks, [track]);
    expect(find.text(_en.queueAddedMessage), findsOneWidget);

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
      TestPlaybackQueueGateway(),
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

    await tester.tap(find.text(_en.artistAlbumsSection));
    await tester.pumpAndSettle();
    expect(albumGateway.requests, [(artist, 0, 30)]);
    expect(find.byType(SliverList), findsOneWidget);
    expect(find.text(_en.artistAlbumCount(1)), findsOneWidget);
    expect(find.text('Synthetic album'), findsOneWidget);

    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(albumGateway.requests, [(artist, 0, 30)]);

    await tester.tap(find.byKey(const ValueKey('artist-album-0')));
    expect(openedAlbum, album);

    await tester.tap(find.text(_en.artistTracksSection));
    await tester.pumpAndSettle();
    expect(find.text('Preserved track'), findsOneWidget);
    await tester.tap(find.text(_en.artistAlbumsSection));
    await tester.pumpAndSettle();
    expect(albumGateway.requests, [(artist, 0, 30)]);
    expect(find.text('Synthetic album'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded Artist header continuously follows Track scrolling', (
    tester,
  ) async {
    const captureReviewImages = bool.fromEnvironment(
      'ARTIST_HEADER_VISUAL_REVIEW',
    );
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const artist = ArtistSummary(
      providerId: 'qq-music',
      opaqueId: 'artist:61002:adaptiveArtistMid',
      name: 'Adaptive artist',
    );
    final tracks = List.generate(
      40,
      (index) => PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:${42000 + index}:0:adaptiveMid$index:-',
        title: 'Adaptive track ${index + 1}',
        artistNames: const ['Adaptive artist'],
      ),
    );
    final playback = QueuePlaybackController(
      TestPlaybackQueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);
    final collapsedStates = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: ArtistPage(
          artist: artist,
          gateway: _ArtistListGateway(tracks),
          queuePlaybackController: playback,
          onBack: () {},
          onSignInAgain: () {},
          onHeaderCollapsedChanged: collapsedStates.add,
          embedded: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('collection-detail-artwork')))
          .width,
      156,
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(ArtistPage),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-artist-header-expanded.png'),
        ),
      );
    }
    final list = find.byKey(const PageStorageKey('artist-tracks'));
    tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position
        .jumpTo(180);
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('collection-detail-artwork')))
          .width,
      64,
    );
    expect(collapsedStates, contains(true));
    if (captureReviewImages) {
      await expectLater(
        find.byType(ArtistPage),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-artist-header-collapsed.png'),
        ),
      );
    }
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

class _ArtistListGateway implements ArtistTrackGateway {
  const _ArtistListGateway(this.tracks);

  final List<PlaylistTrackSummary> tracks;

  @override
  ArtistTrackPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) => _ArtistOperation(
    ArtistTrackPageResult(
      offset: offset,
      total: tracks.length,
      tracks: tracks.skip(offset).take(size).toList(growable: false),
    ),
  );
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
  Future<void> dispose() async {}

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) => throw StateError('audio should not load for an unavailable source');
}
