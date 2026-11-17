import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_controller.dart';
import 'package:flutterustmusic/album/album_details_controller.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/album/album_page.dart';
import 'package:flutterustmusic/artist/artist_album_controller.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_controller.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/session_catalog_gateways.dart';
import 'package:flutterustmusic/discover/ranking_controller.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/library/album_favorite_presentation_controller.dart';
import 'package:flutterustmusic/library/favorite_album_controller.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/library/paged_tracks_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_track_presentation_controller.dart';
import 'package:flutterustmusic/library/track_like_presentation_controller.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

import '../support/test_playback_queue_gateway.dart';

void main() {
  testWidgets('labels a compact loading state without visual overflow', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.dark(),
        home: const Scaffold(
          body: MusicLoadingPanel(
            key: ValueKey('loading-panel'),
            label: 'Loading Album Tracks',
          ),
        ),
      ),
    );

    expect(find.text('Loading Album Tracks'), findsOneWidget);
    expect(find.bySemanticsLabel('Loading Album Tracks'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('keeps one explicit error live region and retry action', (
    tester,
  ) async {
    var retryCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.light(),
        home: Scaffold(
          body: MusicContentStatePanel(
            key: const ValueKey('error-panel'),
            icon: Icons.cloud_off_rounded,
            title: 'Couldn’t load this Album',
            detail: 'Check your connection and try again.',
            liveRegion: true,
            action: FilledButton.tonal(
              onPressed: () => retryCount++,
              child: const Text('Try again'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Couldn’t load this Album'), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    expect(retryCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'MusicStageTransition settles immediately when TickerMode is disabled',
    (tester) async {
      var loading = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return TickerMode(
                enabled: false,
                child: MusicStageTransition(
                  child: loading
                      ? const MusicLoadingPanel(
                          key: ValueKey('stage-loading'),
                          label: 'Loading',
                        )
                      : const SizedBox(key: ValueKey('stage-content')),
                ),
              );
            },
          ),
        ),
      );

      update(() => loading = false);
      await tester.pump();

      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 1.0);
    },
  );

  testWidgets('MusicRetainedTabTransition retains visited tabs offstage', (
    tester,
  ) async {
    var index = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MusicRetainedTabTransition(
              index: index,
              children: const [
                SizedBox(key: ValueKey('tab-0')),
                SizedBox(key: ValueKey('tab-1')),
              ],
            );
          },
        ),
      ),
    );

    expect(find.byKey(const ValueKey('tab-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-1')), findsNothing);

    update(() => index = 1);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tab-0')), findsNothing);
    expect(
      find.byKey(const ValueKey('tab-0'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tab-1')), findsOneWidget);
  });

  testWidgets(
    'MusicRetainedTabTransition survives rapid mid-flight tab switches with pending async work',
    (tester) async {
      var index = 0;
      final visited = <int>{0};
      late StateSetter update;
      final tab0Completer = Completer<String>();
      final tab1Completer = Completer<String>();
      final tab2Completer = Completer<String>();
      var tab0InitCount = 0;
      var tab1InitCount = 0;
      var tab2InitCount = 0;

      void selectTab(int next) {
        update(() {
          index = next;
          visited.add(next);
        });
      }

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MusicRetainedTabTransition(
                index: index,
                children: [
                  _AsyncTabProbe(
                    key: const ValueKey('probe-0'),
                    future: tab0Completer.future,
                    onInit: () => tab0InitCount++,
                  ),
                  if (visited.contains(1))
                    _AsyncTabProbe(
                      key: const ValueKey('probe-1'),
                      future: tab1Completer.future,
                      onInit: () => tab1InitCount++,
                    )
                  else
                    const SizedBox.shrink(),
                  if (visited.contains(2))
                    _AsyncTabProbe(
                      key: const ValueKey('probe-2'),
                      future: tab2Completer.future,
                      onInit: () => tab2InitCount++,
                    )
                  else
                    const SizedBox.shrink(),
                ],
              );
            },
          ),
        ),
      );

      expect(tab0InitCount, 1);
      expect(tab1InitCount, 0);
      expect(tab2InitCount, 0);

      // Switch 0 -> 1 and advance only partway through the 140ms transition.
      selectTab(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tab1InitCount, 1);

      // Rapidly switch 1 -> 2 mid-flight, then 2 -> 0 mid-flight.
      selectTab(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      expect(tab2InitCount, 1);

      selectTab(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));

      // Resolve offstage futures while tab 0 is mid-transition.
      tab1Completer.complete('tab-1-ready');
      tab2Completer.complete('tab-2-ready');
      tab0Completer.complete('tab-0-ready');
      await tester.pumpAndSettle();

      expect(tab0InitCount, 1);
      expect(tab1InitCount, 1);
      expect(tab2InitCount, 1);
      expect(find.text('tab-0-ready'), findsOneWidget);
      expect(find.text('tab-1-ready'), findsNothing);
      expect(find.text('tab-1-ready', skipOffstage: false), findsOneWidget);
      expect(find.text('tab-2-ready', skipOffstage: false), findsOneWidget);
    },
  );

  test('session gateways and controllers resolve warm cache entries synchronously without entering loading stage', () async {
    const album = AlbumSummary(
      providerId: 'netease',
      opaqueId: 'album-1',
      title: 'Cached Album',
    );
    const artist = ArtistSummary(
      providerId: 'netease',
      opaqueId: 'artist-1',
      name: 'Artist A',
    );
    const ranking = RankingSummary(
      providerId: 'netease',
      opaqueId: 'rank-1',
      title: 'Top 100',
    );
    const playlist = UserPlaylistSummary(
      providerId: 'netease',
      opaqueId: 'playlist-1',
      title: 'Cached Playlist',
      trackCount: 1,
      ownership: UserPlaylistOwnership.owned,
    );
    const likedPlaylist = UserPlaylistSummary(
      providerId: 'netease',
      opaqueId: 'liked-1',
      title: 'Liked Songs',
      trackCount: 1,
      isLikedSongs: true,
      ownership: UserPlaylistOwnership.owned,
    );
    const track = PlaylistTrackSummary(
      providerId: 'netease',
      opaqueId: 'track-1',
      title: 'Cached Song',
      artistNames: ['Artist A'],
      albumTitle: 'Cached Album',
    );

    final albumTrackGateway = SessionAlbumTrackGateway(
      const _TestAlbumTrackGateway(track),
    );
    final albumDetailsGateway = SessionAlbumDetailsGateway(
      const _TestAlbumDetailsGateway(album, artist),
    );
    final artistTrackGateway = SessionArtistTrackGateway(
      const _TestArtistTrackGateway(track),
    );
    final artistAlbumGateway = SessionArtistAlbumGateway(
      const _TestArtistAlbumGateway(album),
    );
    final rankingDelegate = _TestRankingGateway(ranking, track);
    final rankingGateway = SessionRankingGateway(rankingDelegate);

    // Warm all caches with first-visit loads.
    final firstAlbumTrackController = AlbumController(album, albumTrackGateway);
    final firstAlbumDetailsController = AlbumDetailsController(
      album,
      albumDetailsGateway,
    );
    final firstArtistTrackController = ArtistController(
      artist,
      artistTrackGateway,
    );
    final firstArtistAlbumController = ArtistAlbumController(
      artist,
      artistAlbumGateway,
    );
    final firstRankingGroupController = RankingGroupController(rankingGateway);
    final firstRankingTrackController = RankingTrackController(
      ranking,
      rankingGateway,
    );
    await Future.wait([
      firstAlbumTrackController.load(),
      firstAlbumDetailsController.load(),
      firstArtistTrackController.load(),
      firstArtistAlbumController.load(),
      firstRankingGroupController.load(),
      firstRankingTrackController.load(),
    ]);
    firstAlbumTrackController.dispose();
    firstAlbumDetailsController.dispose();
    firstArtistTrackController.dispose();
    firstArtistAlbumController.dispose();
    firstRankingGroupController.dispose();
    firstRankingTrackController.dispose();

    // Re-instantiating controllers against warm session gateways must resolve
    // synchronously during load() before any microtask runs.
    final secondAlbumTrackController = AlbumController(
      album,
      albumTrackGateway,
    );
    unawaited(secondAlbumTrackController.load());
    expect(secondAlbumTrackController.stage, AlbumTrackStage.content);
    expect(secondAlbumTrackController.tracks, const [track]);
    secondAlbumTrackController.dispose();

    final secondAlbumDetailsController = AlbumDetailsController(
      album,
      albumDetailsGateway,
    );
    unawaited(secondAlbumDetailsController.load());
    expect(secondAlbumDetailsController.stage, AlbumDetailsStage.content);
    expect(
      secondAlbumDetailsController.details?.description,
      'Warm album details',
    );
    secondAlbumDetailsController.dispose();

    final secondArtistTrackController = ArtistController(
      artist,
      artistTrackGateway,
    );
    unawaited(secondArtistTrackController.load());
    expect(secondArtistTrackController.stage, ArtistTrackStage.content);
    expect(secondArtistTrackController.tracks, const [track]);
    secondArtistTrackController.dispose();

    final secondArtistAlbumController = ArtistAlbumController(
      artist,
      artistAlbumGateway,
    );
    unawaited(secondArtistAlbumController.load());
    expect(secondArtistAlbumController.stage, ArtistAlbumStage.content);
    expect(secondArtistAlbumController.albums, const [album]);
    secondArtistAlbumController.dispose();

    final secondRankingGroupController = RankingGroupController(rankingGateway);
    unawaited(secondRankingGroupController.load());
    expect(secondRankingGroupController.stage, RankingGroupStage.content);
    expect(rankingDelegate.groupLoads, 1);
    secondRankingGroupController.dispose();

    final secondRankingTrackController = RankingTrackController(
      ranking,
      rankingGateway,
    );
    unawaited(secondRankingTrackController.load());
    expect(secondRankingTrackController.stage, RankingTrackStage.content);
    expect(secondRankingTrackController.tracks, const [track]);
    secondRankingTrackController.dispose();

    // Verify PlaylistTrackPresentationController, TrackLikePresentationController,
    // and AlbumFavoritePresentationController warm session gateways.
    final library = UserLibraryController(
      const _TestUserLibraryGateway(
        UserLibraryResult(playlists: [playlist, likedPlaylist]),
      ),
    );
    await library.load();
    final mutations = LibraryMutationCoordinator(providerId: 'netease');
    final playlistGateway = const _TestPlaylistDetailGateway(track);
    final playlistPresentation = PlaylistTrackPresentationController(
      providerId: 'netease',
      enabled: true,
      library: library,
      gateway: playlistGateway,
      mutations: mutations,
    );
    final firstPlaylistController = PagedTracksController(
      (offset, size) => playlistPresentation.sessionGateway.beginLoad(
        playlist: playlist,
        offset: offset,
        size: size,
      ),
    );
    await firstPlaylistController.load();
    firstPlaylistController.dispose();

    final secondPlaylistController = PagedTracksController(
      (offset, size) => playlistPresentation.sessionGateway.beginLoad(
        playlist: playlist,
        offset: offset,
        size: size,
      ),
    );
    unawaited(secondPlaylistController.load());
    expect(secondPlaylistController.stage, PlaylistDetailStage.content);
    expect(secondPlaylistController.tracks, const [track]);
    secondPlaylistController.dispose();
    playlistPresentation.dispose();

    final trackLikePresentation = TrackLikePresentationController(
      providerId: 'netease',
      enabled: true,
      playlistGateway: playlistGateway,
      mutations: mutations,
    )..bindLikedPlaylist(likedPlaylist);
    await trackLikePresentation.preload();
    final likedSongsController = PagedTracksController(
      (offset, size) => trackLikePresentation.sessionGateway.beginLoad(
        playlist: likedPlaylist,
        offset: offset,
        size: size,
      ),
    );
    unawaited(likedSongsController.load());
    expect(likedSongsController.stage, PlaylistDetailStage.content);
    expect(likedSongsController.tracks, const [track]);
    likedSongsController.dispose();
    trackLikePresentation.dispose();

    final albumFavoritePresentation = AlbumFavoritePresentationController(
      providerId: 'netease',
      enabled: true,
      gateway: const _TestFavoriteAlbumGateway(album),
      mutations: mutations,
    );
    await albumFavoritePresentation.preload();
    final favoriteAlbumController = FavoriteAlbumController(
      albumFavoritePresentation.sessionGateway,
    );
    unawaited(favoriteAlbumController.load());
    expect(favoriteAlbumController.stage, FavoriteAlbumStage.content);
    expect(favoriteAlbumController.albums, const [album]);
    favoriteAlbumController.dispose();
    albumFavoritePresentation.dispose();
    mutations.dispose();
    library.dispose();
  });

  testWidgets(
    'AlbumPage renders cached content on Frame 1 without loading panel or stage fade',
    (tester) async {
      const album = AlbumSummary(
        providerId: 'netease',
        opaqueId: 'album-1',
        title: 'Instant Cached Album',
      );
      const artist = ArtistSummary(
        providerId: 'netease',
        opaqueId: 'artist-1',
        name: 'Artist A',
      );
      const track = PlaylistTrackSummary(
        providerId: 'netease',
        opaqueId: 'track-1',
        title: 'Instant Cached Track',
        artistNames: ['Artist A'],
        albumTitle: 'Instant Cached Album',
      );

      final trackGateway = SessionAlbumTrackGateway(
        const _TestAlbumTrackGateway(track),
      );
      final detailsGateway = SessionAlbumDetailsGateway(
        const _TestAlbumDetailsGateway(album, artist),
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

      // Warm the session cache.
      final warmupTracks = AlbumController(album, trackGateway);
      final warmupDetails = AlbumDetailsController(album, detailsGateway);
      await Future.wait([warmupTracks.load(), warmupDetails.load()]);
      warmupTracks.dispose();
      warmupDetails.dispose();

      // Pump AlbumPage once (Frame 1 only, no extra pump or pumpAndSettle).
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicMaterialTheme.dark(),
          home: Scaffold(
            body: AlbumPage(
              album: album,
              gateway: trackGateway,
              detailsGateway: detailsGateway,
              queuePlaybackController: playback,
              onBack: () {},
              onSignInAgain: () {},
              embedded: true,
            ),
          ),
        ),
      );

      expect(find.byType(MusicLoadingPanel), findsNothing);
      expect(find.text('Instant Cached Track'), findsOneWidget);
      final stageTransition = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(MusicStageTransition),
          matching: find.byType(Opacity),
        ),
      );
      expect(stageTransition.opacity, 1.0);
    },
  );
}

class _AsyncTabProbe extends StatefulWidget {
  const _AsyncTabProbe({super.key, required this.future, required this.onInit});

  final Future<String> future;
  final VoidCallback onInit;

  @override
  State<_AsyncTabProbe> createState() => _AsyncTabProbeState();
}

class _AsyncTabProbeState extends State<_AsyncTabProbe> {
  String _status = 'loading';

  @override
  void initState() {
    super.initState();
    widget.onInit();
    unawaited(
      widget.future.then((value) {
        if (!mounted) return;
        setState(() => _status = value);
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Text(_status);
}

class _TestAlbumTrackGateway implements AlbumTrackGateway {
  const _TestAlbumTrackGateway(this.track);
  final PlaylistTrackSummary track;

  @override
  AlbumTrackPageLoadOperation beginLoad({
    required AlbumSummary album,
    required int offset,
    required int size,
  }) => _TestAlbumTrackOperation(
    AlbumTrackPageResult(
      offset: offset,
      continuationOffset: 1,
      total: 1,
      tracks: [track],
    ),
  );
}

class _TestAlbumTrackOperation implements AlbumTrackPageLoadOperation {
  const _TestAlbumTrackOperation(this.result);
  final AlbumTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumTrackPageResult> run() async => result;
}

class _TestAlbumDetailsGateway implements AlbumDetailsGateway {
  const _TestAlbumDetailsGateway(this.album, this.artist);
  final AlbumSummary album;
  final ArtistSummary artist;

  @override
  AlbumDetailsLoadOperation beginLoad(AlbumSummary _) =>
      _TestAlbumDetailsOperation(
        AlbumDetailsResult(
          details: AlbumDetails(
            album: album,
            artists: [artist],
            description: 'Warm album details',
          ),
        ),
      );
}

class _TestAlbumDetailsOperation implements AlbumDetailsLoadOperation {
  const _TestAlbumDetailsOperation(this.result);
  final AlbumDetailsResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumDetailsResult> run() async => result;
}

class _TestArtistTrackGateway implements ArtistTrackGateway {
  const _TestArtistTrackGateway(this.track);
  final PlaylistTrackSummary track;

  @override
  ArtistTrackPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) => _TestArtistTrackOperation(
    ArtistTrackPageResult(
      offset: offset,
      continuationOffset: 1,
      total: 1,
      tracks: [track],
    ),
  );
}

class _TestArtistTrackOperation implements ArtistTrackPageLoadOperation {
  const _TestArtistTrackOperation(this.result);
  final ArtistTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistTrackPageResult> run() async => result;
}

class _TestArtistAlbumGateway implements ArtistAlbumGateway {
  const _TestArtistAlbumGateway(this.album);
  final AlbumSummary album;

  @override
  ArtistAlbumPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) => _TestArtistAlbumOperation(
    ArtistAlbumPageResult(
      offset: offset,
      continuationOffset: 1,
      total: 1,
      albums: [album],
    ),
  );
}

class _TestArtistAlbumOperation implements ArtistAlbumPageLoadOperation {
  const _TestArtistAlbumOperation(this.result);
  final ArtistAlbumPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistAlbumPageResult> run() async => result;
}

class _TestRankingGateway implements RankingGateway {
  _TestRankingGateway(this.ranking, this.track);
  final RankingSummary ranking;
  final PlaylistTrackSummary track;
  int groupLoads = 0;

  @override
  RankingGroupLoadOperation beginGroupLoad() => _TestRankingGroupOperation(() {
    groupLoads++;
    return RankingGroupResult(
      groups: [
        RankingGroup(title: 'Official', rankings: [ranking]),
      ],
    );
  });

  @override
  RankingTrackPageLoadOperation beginTrackLoad({
    required RankingSummary ranking,
    required int offset,
    required int size,
  }) => _TestRankingTrackOperation(
    RankingTrackPageResult(
      ranking: ranking,
      offset: offset,
      continuationOffset: 1,
      total: 1,
      tracks: [track],
    ),
  );
}

class _TestRankingGroupOperation implements RankingGroupLoadOperation {
  const _TestRankingGroupOperation(this.buildResult);
  final RankingGroupResult Function() buildResult;

  @override
  bool cancel() => true;

  @override
  Future<RankingGroupResult> run() async => buildResult();
}

class _TestRankingTrackOperation implements RankingTrackPageLoadOperation {
  const _TestRankingTrackOperation(this.result);
  final RankingTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<RankingTrackPageResult> run() async => result;
}

class _TestUserLibraryGateway implements UserLibraryGateway {
  const _TestUserLibraryGateway(this.result);
  final UserLibraryResult result;

  @override
  UserLibraryLoadOperation beginLoad() => _TestUserLibraryOperation(result);
}

class _TestUserLibraryOperation implements UserLibraryLoadOperation {
  const _TestUserLibraryOperation(this.result);
  final UserLibraryResult result;

  @override
  bool cancel() => true;

  @override
  Future<UserLibraryResult> run() async => result;
}

class _TestPlaylistDetailGateway implements PlaylistDetailGateway {
  const _TestPlaylistDetailGateway(this.track);
  final PlaylistTrackSummary track;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) => _TestPlaylistTrackPageOperation(
    PlaylistTrackPageResult(
      offset: offset,
      nextOffset: 1,
      total: 1,
      tracks: [track],
      membershipTrackOpaqueIds: [track.opaqueId],
    ),
  );
}

class _TestPlaylistTrackPageOperation
    implements PlaylistTrackPageLoadOperation {
  const _TestPlaylistTrackPageOperation(this.result);
  final PlaylistTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async => result;
}

class _TestFavoriteAlbumGateway implements FavoriteAlbumGateway {
  const _TestFavoriteAlbumGateway(this.album);
  final AlbumSummary album;

  @override
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _TestFavoriteAlbumOperation(
    FavoriteAlbumPageResult(
      offset: offset,
      continuationOffset: 1,
      total: 1,
      albums: [album],
      membershipAlbumOpaqueIds: [album.opaqueId],
    ),
  );
}

class _TestFavoriteAlbumOperation implements FavoriteAlbumPageLoadOperation {
  const _TestFavoriteAlbumOperation(this.result);
  final FavoriteAlbumPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<FavoriteAlbumPageResult> run() async => result;
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
