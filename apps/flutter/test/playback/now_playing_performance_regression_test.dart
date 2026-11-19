import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authenticated_dependencies.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlists_page.dart';
import 'package:flutterustmusic/home/daily_recommendation_gateway.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_track_gateway.dart';
import 'package:flutterustmusic/home/recent_listening_gateway.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_page.dart';
import 'package:flutterustmusic/library/user_library_page.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_panel.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_page.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

void main() {
  test('QueuePlaybackController coalesces playback+lyric notifications and isolates stateListenable from position ticks', () async {
    final session = _FakeAudioSession();
    final lyricController = LyricController(
      _StaticLyricGateway(_wordTimedLyrics()),
    );
    final queue = QueuePlaybackController(
      _MutableQueueGateway(const [_trackA, _trackB]),
      TrackPlaybackController(
        const _StaticMediaGateway(),
        ForegroundPlaybackController(_SingleSessionEngine(session)),
      ),
      lyrics: lyricController,
    );
    addTearDown(queue.dispose);

    await queue.replaceAndPlay(const [_trackA, _trackB], 0);
    await Future<void>.delayed(Duration.zero);
    expect(lyricController.stage, LyricStage.content);

    var rawQueueNotifications = 0;
    var queueStateNotifications = 0;
    var currentTrackNotifications = 0;
    var playbackStateNotifications = 0;
    var playbackPositionNotifications = 0;
    queue.addListener(() => rawQueueNotifications += 1);
    queue.stateListenable.addListener(() => queueStateNotifications += 1);
    queue.currentTrackListenable.addListener(
      () => currentTrackNotifications += 1,
    );
    queue.playback.stateListenable.addListener(
      () => playbackStateNotifications += 1,
    );
    queue.playback.positionMsListenable.addListener(
      () => playbackPositionNotifications += 1,
    );

    // Emit 3 word-level position ticks inside line 0.
    session.emitPosition(1100);
    await Future<void>.delayed(Duration.zero);
    session.emitPosition(1250);
    await Future<void>.delayed(Duration.zero);
    session.emitPosition(1400);
    await Future<void>.delayed(Duration.zero);

    // Each tick must notify raw queue listeners once (not twice via lyrics),
    // positionMsListenable once, and never trigger stateListenable.
    expect(rawQueueNotifications, 3);
    expect(playbackPositionNotifications, 3);
    expect(queueStateNotifications, 0);
    expect(playbackStateNotifications, 0);
    expect(currentTrackNotifications, 0);

    // Non-position state change (pause) must notify stateListenable.
    await queue.playback.pause();
    await Future<void>.delayed(Duration.zero);
    expect(playbackStateNotifications, 1);
    expect(queueStateNotifications, 1);
  });

  testWidgets(
    'position ticks update _PlaybackProgress without rebuilding NowPlayingBar chrome, _TrackInfo, _VolumeButton, or _NowPlayingArtwork',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = _FakeAudioSession();
      final queue = _makeQueue(session);
      addTearDown(queue.dispose);
      await queue.replaceAndPlay(const [_trackA, _trackB], 0);
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicMaterialTheme.light(),
          home: Scaffold(
            bottomNavigationBar: NowPlayingBar(
              controller: queue,
              onSignInAgain: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rebuiltTypes = <String>[];
      final previousCallback = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
        rebuiltTypes.add(element.widget.runtimeType.toString());
        previousCallback?.call(element, builtOnce);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);

      for (var ms = 1000; ms <= 5000; ms += 1000) {
        session.emitPosition(ms);
        await tester.pump();
      }
      await tester.pump();

      expect(find.text('0:05'), findsOneWidget);
      expect(rebuiltTypes, isNot(contains('_DesktopNowPlayingLayout')));
      expect(rebuiltTypes, isNot(contains('_TrackInfo')));
      expect(rebuiltTypes, isNot(contains('_VolumeButton')));
      expect(rebuiltTypes, isNot(contains('_NowPlayingArtwork')));
      expect(rebuiltTypes, isNot(contains('NowPlayingBar')));
      expect(rebuiltTypes, contains('Slider'));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'position ticks do not rebuild RecommendedPlaylistsPage or PlaylistDetailPage',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = _FakeAudioSession();
      final queue = _makeQueue(session);
      addTearDown(queue.dispose);
      await queue.replaceAndPlay(const [_trackA, _trackB], 0);

      await tester.pumpWidget(
        MaterialApp(
          theme: MusicMaterialTheme.light(),
          home: Row(
            children: [
              Expanded(
                child: RecommendedPlaylistsPage(
                  embedded: true,
                  gateway: const _EmptyRecommendedPlaylistGateway(),
                  newAlbumGateway: const RustNewAlbumGateway(),
                  newSongGateway: const RustNewSongGateway(),
                  rankingGateway: const RustRankingGateway(),
                  radarGateway: RustRadarGateway(),
                  queuePlaybackController: queue,
                  onBack: () {},
                  onOpenPlaylist: (_) {},
                  onOpenRanking: (_) {},
                  onOpenAlbum: (_) {},
                  onSignInAgain: () {},
                ),
              ),
              Expanded(
                child: PlaylistDetailPage(
                  embedded: true,
                  playlist: const UserPlaylistSummary(
                    providerId: 'qq-music',
                    opaqueId: 'pl:1',
                    title: 'Regression Playlist',
                    trackCount: 1,
                  ),
                  gateway: const _SingleTrackPlaylistDetailGateway(),
                  queuePlaybackController: queue,
                  onBack: () {},
                  onSignInAgain: () {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rebuiltTypes = <String>[];
      final previousCallback = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
        rebuiltTypes.add(element.widget.runtimeType.toString());
        previousCallback?.call(element, builtOnce);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);

      for (var ms = 500; ms <= 2500; ms += 500) {
        session.emitPosition(ms);
        await tester.pump();
      }

      expect(rebuiltTypes, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'LyricPanel isolates position ticks, precomputes segmentsComposeLine, snaps initial mount, and skips intro scroll at offset 0',
    (tester) async {
      tester.view.physicalSize = const Size(500, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Precomputed segmentsComposeLine.
      final matching = SynchronizedLyricLine(
        text: 'hello world',
        startMs: 0,
        durationMs: 1000,
        segments: const [
          TimedLyricSegment(text: 'hello ', startMs: 0, durationMs: 500),
          TimedLyricSegment(text: 'world', startMs: 500, durationMs: 500),
        ],
      );
      final mismatched = SynchronizedLyricLine(
        text: 'hello world',
        startMs: 0,
        durationMs: 1000,
        segments: const [
          TimedLyricSegment(text: 'other', startMs: 0, durationMs: 500),
        ],
      );
      final plain = SynchronizedLyricLine(
        text: 'plain',
        startMs: 0,
        durationMs: 1000,
        segments: const [],
      );
      expect(matching.segmentsComposeLine, isTrue);
      expect(mismatched.segmentsComposeLine, isFalse);
      expect(plain.segmentsComposeLine, isFalse);

      // 2. Initial mount snaps immediately to line 20 without 220ms animateTo.
      final longController = LyricController(
        _StaticLyricGateway(_longWordTimedLyrics(30)),
      );
      addTearDown(longController.dispose);
      await longController.load(_trackA);
      longController.updatePositionMs(20250);
      final noisyPlaybackState = _SignalNotifier();
      addTearDown(noisyPlaybackState.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricPanel(
              controller: longController,
              playbackState: noisyPlaybackState,
              canSeek: () => true,
              onSeek: (_) async {},
              onClose: () {},
              onSignInAgain: () {},
            ),
          ),
        ),
      );
      // Only frame pumps (zero 220ms animation advancement) — snap must land on line 20.
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final listFinder = find.byKey(const ValueKey('lyrics-line-list'));
      final line20 = find.byKey(const ValueKey('lyrics-line-20'));
      expect(line20, findsOneWidget);
      expect(
        tester.getRect(line20).overlaps(tester.getRect(listFinder)),
        isTrue,
      );

      // 3. Noisy playbackState + word-level position ticks must not rebuild
      // LyricPanel, _LyricContent, or inactive _LyricLine widgets.
      final rebuiltTypes = <String>[];
      final previousCallback = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
        rebuiltTypes.add(element.widget.runtimeType.toString());
        previousCallback?.call(element, builtOnce);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);

      noisyPlaybackState.ping();
      noisyPlaybackState.ping();
      longController.updatePositionMs(20400);
      await tester.pump();
      longController.updatePositionMs(20600);
      await tester.pump();

      expect(rebuiltTypes, isNot(contains('LyricPanel')));
      expect(rebuiltTypes, isNot(contains('_LyricContent')));
      expect(rebuiltTypes, isNot(contains('_LyricLine')));
      expect(rebuiltTypes, contains('_TimedSegment'));

      // 4. Intro lyrics (activeLineIndex == null) stay at offset 0 cleanly.
      await tester.pumpWidget(const SizedBox.shrink());
      final introController = LyricController(
        _StaticLyricGateway(
          SynchronizedLyrics([
            for (var i = 0; i < 10; i += 1)
              SynchronizedLyricLine(
                text: 'intro line $i',
                startMs: 5000 + i * 1000,
                durationMs: 1000,
                segments: const [],
              ),
          ]),
        ),
      );
      addTearDown(introController.dispose);
      await introController.load(_trackA);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricPanel(
              controller: introController,
              onClose: () {},
              onSignInAgain: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('lyrics-line-list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.pixels, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ExpandedNowPlayingPage isolates backdrop and artwork with RepaintBoundary and skips AnimatedTheme on initial palette arrival',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = _FakeAudioSession();
      final queue = _makeQueue(session);
      addTearDown(queue.dispose);
      await queue.replaceAndPlay(const [_trackA, _trackB], 0);

      final firstPalette = Completer<ColorScheme>();
      final secondPalette = Completer<ColorScheme>();
      var loadCount = 0;
      final cache = ArtworkColorSchemeCache(
        artworkImageProviderBuilder: (_) => _tinyArtwork(),
        artworkColorSchemeLoader: ({required provider, required brightness}) {
          loadCount += 1;
          return loadCount == 1 ? firstPalette.future : secondPalette.future;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: MusicMaterialTheme.light(),
          home: ExpandedNowPlayingPage(
            controller: queue,
            onBack: () {},
            onSignInAgain: () {},
            artworkImageProviderBuilder: (_) => _tinyArtwork(),
            artworkColorSchemeCache: cache,
          ),
        ),
      );
      await tester.pump();

      // Verify RepaintBoundary isolation for backdrop, foreground body, and artwork.
      final backdropFinder = find.byKey(
        const ValueKey('expanded-now-playing-artwork-backdrop'),
      );
      expect(
        find.ancestor(
          of: backdropFinder,
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      final backdropCustomPaint = tester.widget<CustomPaint>(
        find.descendant(of: backdropFinder, matching: find.byType(CustomPaint)),
      );
      expect(backdropCustomPaint.isComplex, isTrue);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('expanded-now-playing-wide-layout')),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('expanded-now-playing-artwork')),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );

      final pageAnimatedTheme = find
          .ancestor(
            of: find.byKey(const ValueKey('expanded-now-playing-page')),
            matching: find.byType(AnimatedTheme),
          )
          .first;

      // Initial cold-cache palette arrival must use Duration.zero (no 240ms rebuild storm).
      expect(
        tester.widget<AnimatedTheme>(pageAnimatedTheme).duration,
        Duration.zero,
      );
      final schemeA = ColorScheme.fromSeed(
        seedColor: const Color(0xFF1D6FA5),
        brightness: Brightness.light,
      );
      firstPalette.complete(schemeA);
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<AnimatedTheme>(pageAnimatedTheme).duration,
        Duration.zero,
      );
      expect(
        Theme.of(tester.element(backdropFinder)).colorScheme.primary,
        schemeA.primary,
      );

      // Advancing frames after the snap must NOT trigger AnimatedTheme rebuilds
      // of the backdrop, lyrics panel, or expanded controls.
      final postSnapRebuilds = <String>[];
      final previousCallback = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
        postSnapRebuilds.add(element.widget.runtimeType.toString());
        previousCallback?.call(element, builtOnce);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);
      for (var step = 0; step < 4; step += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(postSnapRebuilds, isNot(contains('_ExpandedNowPlayingBackdrop')));
      expect(postSnapRebuilds, isNot(contains('LyricPanel')));
      expect(postSnapRebuilds, isNot(contains('_ExpandedPlaybackControls')));
      expect(postSnapRebuilds, isNot(contains('_ExpandedArtwork')));

      // Switching track while already open enables AnimatedTheme transition.
      await queue.advance();
      await tester.pump();
      expect(
        tester.widget<AnimatedTheme>(pageAnimatedTheme).duration,
        MusicMotion.stateChange,
      );
      secondPalette.complete(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFFA53D1D),
          brightness: Brightness.light,
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'UserLibraryPage retries palette prefetch after null, throttles observePlayback, and isolates ExpandedNowPlayingRouteTransition',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = _FakeAudioSession();
      final queue = _makeQueue(session);
      final host = _FakePlaybackHost(queue);
      addTearDown(queue.dispose);

      final recentListening = _CountingRecentListeningGateway();
      var paletteAttempts = 0;
      var allowPaletteSuccess = false;
      final paletteCache = ArtworkColorSchemeCache(
        artworkImageProviderBuilder: (_) => _tinyArtwork(),
        artworkColorSchemeLoader:
            ({required provider, required brightness}) async {
              paletteAttempts += 1;
              if (!allowPaletteSuccess) {
                throw StateError('transient artwork fetch failure');
              }
              return ColorScheme.fromSeed(
                seedColor: const Color(0xFF336699),
                brightness: brightness,
              );
            },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: MusicMaterialTheme.light(),
          home: UserLibraryPage(
            homeDependencies: AuthenticatedHomeDependencies(
              accountSummaryGateway: RustAccountSummaryGateway(),
              dailyRecommendationGateway: RustDailyRecommendationGateway(),
              personalizedPlaylistsGateway: RustPersonalizedPlaylistsGateway(),
              personalizedTracksGateway: RustPersonalizedTracksGateway(),
              relatedTracksGateway: const RustRelatedTracksGateway(),
              recentListeningFactory: () => recentListening,
            ),
            libraryDependencies: AuthenticatedLibraryDependencies(
              libraryGateway: const _IdleLibraryGateway(),
              playlistDetailGateway: const _SingleTrackPlaylistDetailGateway(),
              albumTrackGateway: const RustAlbumTrackGateway(),
              albumDetailsGateway: const RustAlbumDetailsGateway(),
              artistTrackGateway: const RustArtistTrackGateway(),
              artistAlbumGateway: const RustArtistAlbumGateway(),
              favoriteAlbumGateway: RustFavoriteAlbumGateway(),
              favoriteArtistGateway: RustFavoriteArtistGateway(),
            ),
            discoveryDependencies: AuthenticatedDiscoveryDependencies(
              trackSearchGateway: const RustTrackSearchGateway(),
              artistSearchGateway: const RustArtistSearchGateway(),
              albumSearchGateway: const RustAlbumSearchGateway(),
              playlistSearchGateway: const RustPlaylistSearchGateway(),
              recommendedPlaylistGateway:
                  const _EmptyRecommendedPlaylistGateway(),
              newAlbumGateway: const RustNewAlbumGateway(),
              newSongGateway: const RustNewSongGateway(),
              rankingGateway: const RustRankingGateway(),
              radarGateway: RustRadarGateway(),
            ),
            playbackDependencies: AuthenticatedPlaybackDependencies(
              playbackHost: host,
              trackCommentGateway: const RustTrackCommentGateway(),
            ),
            capabilities: MusicProviderCapabilities.qqMusic,
            settings: AppSettings.defaults,
            onSettingsChanged: (_) async => AppSettingsWriteResult.saved,
            authenticated: true,
            onRequestSignIn: () {},
            onSignInAgain: () {},
            onSignOut: () async => CredentialSignOutResult.signedOut,
            expandedNowPlayingPaletteCache: paletteCache,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start playback while loader fails -> prefetch returns null and clears
      // cached prefetch key so a later state transition can retry.
      await queue.replaceAndPlay(const [_trackA, _trackB], 0);
      await tester.pumpAndSettle();
      final attemptsAfterStart = paletteAttempts;
      expect(attemptsAfterStart, greaterThanOrEqualTo(1));
      expect(
        paletteCache.lookup(
          artworkUri: _trackA.artworkUri!,
          brightness: Brightness.light,
        ),
        isNull,
      );

      final observationsAfterStart = recentListening.observeCalls;

      // Emit 20 rapid 16ms position ticks (total 320ms < 1000ms threshold).
      for (var i = 1; i <= 20; i += 1) {
        session.emitPosition(i * 16);
        await tester.pump();
      }
      await tester.pump();

      // Neither observePlayback nor failed palette prefetch may spam on ticks.
      expect(recentListening.observeCalls, observationsAfterStart);
      expect(paletteAttempts, attemptsAfterStart);

      // Crossing >= 1000ms position delta forwards one bounded observation.
      session.emitPosition(1200);
      await tester.pump();
      await tester.pump();
      expect(recentListening.observeCalls, observationsAfterStart + 1);

      // Non-position state change (pause) triggers immediate observation AND
      // retries the previously failed prefetch, which now succeeds.
      allowPaletteSuccess = true;
      await queue.playback.pause();
      await tester.pumpAndSettle();
      expect(recentListening.observeCalls, observationsAfterStart + 2);
      expect(paletteAttempts, attemptsAfterStart + 1);
      expect(
        paletteCache.lookup(
          artworkUri: _trackA.artworkUri!,
          brightness: Brightness.light,
        ),
        isNotNull,
      );

      // Open Expanded Now Playing and verify RepaintBoundary + TickerMode.
      await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
      await tester.pump();
      final slideTransition = tester.widget<SlideTransition>(
        find.byKey(const ValueKey('expanded-now-playing-transition-page')),
      );
      expect(slideTransition.child, isA<RepaintBoundary>());

      await tester.pumpAndSettle();
      final baseOffstage = tester.widget<Offstage>(
        find
            .descendant(
              of: find.byKey(const ValueKey('expanded-now-playing-transition')),
              matching: find.byType(Offstage),
            )
            .first,
      );
      expect(baseOffstage.offstage, isTrue);
      final baseTickerMode = baseOffstage.child! as TickerMode;
      expect(baseTickerMode.enabled, isFalse);
      expect(baseTickerMode.child, isA<RepaintBoundary>());

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('Isolate.run Oklab clustering extracts accurate dual-role colors and handles transparent input', () async {
    const size = 64;
    final splitBytes = Uint8List(size * size * 4);
    for (var y = 0; y < size; y += 1) {
      for (var x = 0; x < size; x += 1) {
        final offset = (y * size + x) * 4;
        if (y < 40) {
          // Deep ocean blue primary area
          splitBytes[offset] = 0x14;
          splitBytes[offset + 1] = 0x48;
          splitBytes[offset + 2] = 0x60;
        } else {
          // Warm amber secondary / accent area
          splitBytes[offset] = 0xD9;
          splitBytes[offset + 1] = 0x7D;
          splitBytes[offset + 2] = 0x2B;
        }
        splitBytes[offset + 3] = 0xFF;
      }
    }

    final extracted = await clusterArtworkOklabRolesInIsolateForTest(
      splitBytes,
      size,
      size,
    );
    expect(extracted, isNotNull);
    expect(extracted!.accent, isNotNull);
    expect(extracted.secondaryAmbient, isNotNull);
    expect(extracted.primaryAmbient.$1, inInclusiveRange(0.25, 0.50));

    // Fully transparent image returns null cleanly.
    final transparent = Uint8List(16 * 16 * 4);
    expect(
      await clusterArtworkOklabRolesInIsolateForTest(transparent, 16, 16),
      isNull,
    );
  });

  test('TrackPlaybackController and LyricController expose consistent state inside positionMsListenable listeners', () async {
    final session = _FakeAudioSession();
    final playback = TrackPlaybackController(
      const _StaticMediaGateway(),
      ForegroundPlaybackController(_SingleSessionEngine(session)),
    );
    addTearDown(playback.dispose);

    await playback.playTrack(_trackA);
    await Future<void>.delayed(Duration.zero);
    expect(playback.stage, TrackPlaybackStage.playing);

    // Simultaneous position + pause state changes must expose updated stage
    // when positionMsListenable fires.
    TrackPlaybackStage? observedStageOnPosition;
    playback.positionMsListenable.addListener(() {
      observedStageOnPosition = playback.stage;
    });
    await playback.seekToMs(1500);
    await Future<void>.delayed(Duration.zero);
    expect(observedStageOnPosition, TrackPlaybackStage.playing);

    final lyricController = LyricController(
      _StaticLyricGateway(_wordTimedLyrics()),
    );
    addTearDown(lyricController.dispose);
    await lyricController.load(_trackA);
    lyricController.updatePositionMs(1200);
    expect(lyricController.activeSelection?.lineIndex, 0);

    int? observedLineIndex;
    LyricStage? observedLyricStage;
    lyricController.positionMsListenable.addListener(() {
      observedLineIndex = lyricController.activeSelection?.lineIndex;
      observedLyricStage = lyricController.stage;
    });

    // Crossing from line 0 (1000ms) to line 1 (2500ms) must already update
    // activeSelection before positionMsListenable notifies.
    lyricController.updatePositionMs(2600);
    expect(observedLineIndex, 1);
    expect(observedLyricStage, LyricStage.content);

    // clear() must already reset stage and activeSelection before resetting positionMs.
    lyricController.clear();
    expect(observedLineIndex, isNull);
    expect(observedLyricStage, LyricStage.idle);
  });

  testWidgets(
    'position ticks update _PlaybackProgress without rebuilding _ExpandedPlaybackControls',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = _FakeAudioSession();
      final queue = _makeQueue(session);
      addTearDown(queue.dispose);
      await queue.replaceAndPlay(const [_trackA, _trackB], 0);

      await tester.pumpWidget(
        MaterialApp(
          theme: MusicMaterialTheme.light(),
          home: Scaffold(
            bottomNavigationBar: NowPlayingBar.expanded(
              controller: queue,
              onSignInAgain: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rebuiltTypes = <String>[];
      final previousCallback = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
        rebuiltTypes.add(element.widget.runtimeType.toString());
        previousCallback?.call(element, builtOnce);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);

      for (var ms = 1000; ms <= 4000; ms += 1000) {
        session.emitPosition(ms);
        await tester.pump();
      }
      await tester.pump();

      expect(find.text('0:04'), findsOneWidget);
      expect(rebuiltTypes, isNot(contains('_ExpandedPlaybackControls')));
      expect(rebuiltTypes, isNot(contains('_VolumeButton')));
      expect(rebuiltTypes, isNot(contains('NowPlayingBar')));
      expect(rebuiltTypes, contains('Slider'));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ExpandedNowPlayingRouteTransition handles disableAnimations, rapid Frame-0 cancel, and mid-reverse reopen cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = _FakeAudioSession();
      final queue = _makeQueue(session);
      final host = _FakePlaybackHost(queue);
      addTearDown(queue.dispose);
      await queue.replaceAndPlay(const [_trackA, _trackB], 0);

      Widget buildApp({required bool disableAnimations}) => MediaQuery(
        data: MediaQueryData(
          size: const Size(1100, 800),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: MusicMaterialTheme.light(),
          home: UserLibraryPage(
            homeDependencies: AuthenticatedHomeDependencies(
              accountSummaryGateway: RustAccountSummaryGateway(),
              dailyRecommendationGateway: RustDailyRecommendationGateway(),
              personalizedPlaylistsGateway: RustPersonalizedPlaylistsGateway(),
              personalizedTracksGateway: RustPersonalizedTracksGateway(),
              relatedTracksGateway: const RustRelatedTracksGateway(),
              recentListeningFactory: () => _CountingRecentListeningGateway(),
            ),
            libraryDependencies: AuthenticatedLibraryDependencies(
              libraryGateway: const _IdleLibraryGateway(),
              playlistDetailGateway: const _SingleTrackPlaylistDetailGateway(),
              albumTrackGateway: const RustAlbumTrackGateway(),
              albumDetailsGateway: const RustAlbumDetailsGateway(),
              artistTrackGateway: const RustArtistTrackGateway(),
              artistAlbumGateway: const RustArtistAlbumGateway(),
              favoriteAlbumGateway: RustFavoriteAlbumGateway(),
              favoriteArtistGateway: RustFavoriteArtistGateway(),
            ),
            discoveryDependencies: AuthenticatedDiscoveryDependencies(
              trackSearchGateway: const RustTrackSearchGateway(),
              artistSearchGateway: const RustArtistSearchGateway(),
              albumSearchGateway: const RustAlbumSearchGateway(),
              playlistSearchGateway: const RustPlaylistSearchGateway(),
              recommendedPlaylistGateway:
                  const _EmptyRecommendedPlaylistGateway(),
              newAlbumGateway: const RustNewAlbumGateway(),
              newSongGateway: const RustNewSongGateway(),
              rankingGateway: const RustRankingGateway(),
              radarGateway: RustRadarGateway(),
            ),
            playbackDependencies: AuthenticatedPlaybackDependencies(
              playbackHost: host,
              trackCommentGateway: const RustTrackCommentGateway(),
            ),
            capabilities: MusicProviderCapabilities.qqMusic,
            settings: AppSettings.defaults,
            onSettingsChanged: (_) async => AppSettingsWriteResult.saved,
            authenticated: true,
            onRequestSignIn: () {},
            onSignInAgain: () {},
            onSignOut: () async => CredentialSignOutResult.signedOut,
          ),
        ),
      );

      // 1. Reduced motion (disableAnimations: true): open & close snap immediately.
      await tester.pumpWidget(buildApp(disableAnimations: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('expanded-now-playing-page')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('expanded-now-playing-page')))
            .dy,
        0,
      );

      await tester.tap(find.byKey(const ValueKey('expanded-now-playing-back')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('expanded-now-playing-page')),
        findsNothing,
      );

      // 2. Normal animations: open -> Frame 0 postFrameCallback starts forward()
      // -> close immediately before Frame 1 advances -> detail unmounts cleanly.
      await tester.pumpWidget(buildApp(disableAnimations: false));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('expanded-now-playing-page')),
        findsOneWidget,
      );
      // Close immediately while controller is at value == 0.0 (forward just started).
      final backButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('expanded-now-playing-back')),
      );
      backButton.onPressed!();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('expanded-now-playing-page')),
        findsNothing,
      );

      // 3. Open -> mid-slide -> close -> mid-reverse -> re-open -> settles open.
      await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('expanded-now-playing-back')),
          )
          .onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      // Still mid-reverse: detail is visible and sliding down, base is unlocked.
      expect(
        find.byKey(const ValueKey('expanded-now-playing-page')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('now-playing-open-expanded')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      final expandedPage = find.byKey(
        const ValueKey('expanded-now-playing-page'),
      );
      expect(expandedPage, findsOneWidget);
      expect(tester.getTopLeft(expandedPage).dy, 0);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'LyricPanel converges on 120 variable-height wrapped lines for initial snap, forward seek, and backward seek without hanging',
    (tester) async {
      tester.view.physicalSize = const Size(420, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final lyrics = SynchronizedLyrics([
        for (var i = 0; i < 120; i += 1)
          SynchronizedLyricLine(
            text: i.isEven
                ? 'Short line $i'
                : 'A much longer lyric line $i that wraps across multiple lines in a narrow viewport',
            startMs: i * 1000,
            durationMs: 1000,
            translation: i % 3 == 0
                ? 'Multi-line translation for lyric $i with enough words to vary line heights noticeably'
                : null,
            segments: const [],
          ),
      ]);

      var canSeekFlag = false;
      final controller = LyricController(_StaticLyricGateway(lyrics));
      addTearDown(controller.dispose);
      await controller.load(_trackA);
      controller.updatePositionMs(85200);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricPanel(
              controller: controller,
              canSeek: () => canSeekFlag,
              onSeek: (_) async {},
              onClose: () {},
              onSignInAgain: () {},
            ),
          ),
        ),
      );

      // Initial snap to line 85 (no 220ms animation advancement needed).
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final listFinder = find.byKey(const ValueKey('lyrics-line-list'));
      final line85 = find.byKey(const ValueKey('lyrics-line-85'));
      expect(line85, findsOneWidget);
      expect(
        tester.getRect(line85).overlaps(tester.getRect(listFinder)),
        isTrue,
      );

      // Forward seek to line 115.
      controller.updatePositionMs(115200);
      await tester.pumpAndSettle();
      final line115 = find.byKey(const ValueKey('lyrics-line-115'));
      expect(line115, findsOneWidget);
      expect(
        tester.getRect(line115).overlaps(tester.getRect(listFinder)),
        isTrue,
      );

      // Backward seek to line 10.
      controller.updatePositionMs(10200);
      await tester.pumpAndSettle();
      final line10 = find.byKey(const ValueKey('lyrics-line-10'));
      expect(line10, findsOneWidget);
      expect(
        tester.getRect(line10).overlaps(tester.getRect(listFinder)),
        isTrue,
      );

      // Dynamic canSeek refreshes on stageListenable rebuilds even without playbackState.
      canSeekFlag = true;
      await controller.load(_trackB);
      await tester.pumpAndSettle();
      final line0Semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byKey(const ValueKey('lyrics-line-0')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(line0Semantics.properties.button, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

const _trackA = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:perf-a',
  title: 'Performance Track A',
  artistNames: ['Artist A'],
  albumTitle: 'Album A',
  artworkUri: 'https://example.invalid/perf-a.jpg',
  durationSeconds: 180,
);

const _trackB = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:perf-b',
  title: 'Performance Track B',
  artistNames: ['Artist B'],
  albumTitle: 'Album B',
  artworkUri: 'https://example.invalid/perf-b.jpg',
  durationSeconds: 210,
);

MemoryImage _tinyArtwork() => MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

QueuePlaybackController _makeQueue(_FakeAudioSession session) =>
    QueuePlaybackController(
      _MutableQueueGateway(const [_trackA, _trackB]),
      TrackPlaybackController(
        const _StaticMediaGateway(),
        ForegroundPlaybackController(_SingleSessionEngine(session)),
      ),
      lyrics: LyricController(_StaticLyricGateway(_wordTimedLyrics())),
    );

SynchronizedLyrics _wordTimedLyrics() => SynchronizedLyrics([
  SynchronizedLyricLine(
    text: 'hello world',
    startMs: 1000,
    durationMs: 1000,
    segments: const [
      TimedLyricSegment(text: 'hello ', startMs: 1000, durationMs: 500),
      TimedLyricSegment(text: 'world', startMs: 1500, durationMs: 500),
    ],
  ),
  SynchronizedLyricLine(
    text: 'second line',
    startMs: 2500,
    durationMs: 1000,
    segments: const [],
  ),
]);

SynchronizedLyrics _longWordTimedLyrics(int count) => SynchronizedLyrics([
  for (var i = 0; i < count; i += 1)
    SynchronizedLyricLine(
      text: 'word $i line',
      startMs: i * 1000,
      durationMs: 1000,
      translation: 'translation $i',
      segments: [
        TimedLyricSegment(text: 'word ', startMs: i * 1000, durationMs: 400),
        TimedLyricSegment(
          text: '$i line',
          startMs: i * 1000 + 400,
          durationMs: 600,
        ),
      ],
    ),
]);

class _SignalNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _FakePlaybackHost implements AppPlaybackHost {
  _FakePlaybackHost(this.controller);

  @override
  final QueuePlaybackController controller;

  @override
  bool get systemControlsAvailable => false;

  @override
  Future<void> dispose() async {}
}

class _CountingRecentListeningGateway implements RecentListeningGateway {
  int observeCalls = 0;

  @override
  void observe(PlaylistTrackSummary? track, int positionMs, bool playing) {
    observeCalls += 1;
  }

  @override
  PlaylistTrackSummary? choose() => null;

  @override
  void dispose() {}
}

class _MutableQueueGateway implements PlaybackQueueGateway {
  _MutableQueueGateway(this._tracks);

  List<PlaylistTrackSummary> _tracks;
  int? _index = 0;
  PlaybackOrder _order = PlaybackOrder.sequential;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;

  PlaybackQueueSnapshot _current() => PlaybackQueueSnapshot(
    tracks: _tracks,
    currentIndex: _index,
    hasPrevious: _index != null && _index! > 0,
    hasNext: _index != null && _index! + 1 < _tracks.length,
    order: _order,
    repeatMode: _repeatMode,
  );

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _current());

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) {
    _tracks = List.unmodifiable(tracks);
    _index = currentIndex;
    return PlaybackQueueResult(snapshot: _current(), playbackRequested: true);
  }

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) {
    _tracks = List.unmodifiable([..._tracks, track]);
    _index ??= 0;
    return PlaybackQueueResult(snapshot: _current());
  }

  @override
  PlaybackQueueResult select(int index) {
    _index = index;
    return PlaybackQueueResult(snapshot: _current(), playbackRequested: true);
  }

  @override
  PlaybackQueueResult advance() {
    if (_index != null && _index! + 1 < _tracks.length) _index = _index! + 1;
    return PlaybackQueueResult(snapshot: _current(), playbackRequested: true);
  }

  @override
  PlaybackQueueResult rewind() {
    if (_index != null && _index! > 0) _index = _index! - 1;
    return PlaybackQueueResult(snapshot: _current(), playbackRequested: true);
  }

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) {
    _order = order;
    return PlaybackQueueResult(snapshot: _current());
  }

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) {
    _repeatMode = repeatMode;
    return PlaybackQueueResult(snapshot: _current());
  }

  @override
  PlaybackQueueResult completeCurrent() =>
      PlaybackQueueResult(snapshot: _current());

  @override
  PlaybackQueueResult extendAndAdvanceFromTerminal(
    List<PlaylistTrackSummary> tracks,
  ) => PlaybackQueueResult(snapshot: _current());

  @override
  PlaybackQueueResult remove(int index) =>
      PlaybackQueueResult(snapshot: _current());

  @override
  PlaybackQueueResult clear() {
    _tracks = const [];
    _index = null;
    return PlaybackQueueResult(snapshot: _current(), playbackRequested: true);
  }
}

class _StaticMediaGateway implements MediaResolutionGateway {
  const _StaticMediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => _ImmediateMediaOperation(
    MediaResolutionResult(
      source: ResolvedPlaybackSource(
        uri: Uri.parse('https://example.invalid/$opaqueTrackId.mp3'),
        format: PlaybackAudioFormat.mp3,
        quality: PlaybackAudioQuality.standard,
        validForSeconds: 7200,
      ),
    ),
  );
}

class _ImmediateMediaOperation implements MediaResolutionOperation {
  const _ImmediateMediaOperation(this._result);

  final MediaResolutionResult _result;

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async => _result;
}

class _SingleSessionEngine implements ForegroundAudioEngine {
  _SingleSessionEngine(this._session);

  final _FakeAudioSession _session;

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) async => _session;

  @override
  Future<void> dispose() async {}
}

class _FakeAudioSession implements ForegroundAudioSession {
  final _states = StreamController<ForegroundAudioState>.broadcast();
  final _failures = StreamController<ForegroundAudioFailure>.broadcast();
  final _positions = StreamController<int>.broadcast();

  void emitPosition(int positionMs) {
    if (!_positions.isClosed) _positions.add(positionMs);
  }

  void emitState(ForegroundAudioState state) {
    if (!_states.isClosed) _states.add(state);
  }

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> play() async => emitState(ForegroundAudioState.playing);

  @override
  Future<void> pause() async => emitState(ForegroundAudioState.paused);

  @override
  Future<void> seekToMs(int positionMs) async => emitPosition(positionMs);

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async => emitState(ForegroundAudioState.stopped);

  @override
  Future<void> dispose() async {}
}

class _StaticLyricGateway implements LyricGateway {
  const _StaticLyricGateway(this._lyrics);

  final SynchronizedLyrics _lyrics;

  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) => _ImmediateLyricOperation(LyricLoadResult(lyrics: _lyrics));
}

class _ImmediateLyricOperation implements LyricLoadOperation {
  const _ImmediateLyricOperation(this._result);

  final LyricLoadResult _result;

  @override
  bool cancel() => true;

  @override
  Future<LyricLoadResult> run() async => _result;
}

class _EmptyRecommendedPlaylistGateway implements RecommendedPlaylistGateway {
  const _EmptyRecommendedPlaylistGateway();

  @override
  RecommendedPlaylistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => const _ImmediateRecommendedPlaylistOperation();
}

class _ImmediateRecommendedPlaylistOperation
    implements RecommendedPlaylistPageLoadOperation {
  const _ImmediateRecommendedPlaylistOperation();

  @override
  bool cancel() => true;

  @override
  Future<RecommendedPlaylistPageResult> run() async =>
      const RecommendedPlaylistPageResult();
}

class _SingleTrackPlaylistDetailGateway implements PlaylistDetailGateway {
  const _SingleTrackPlaylistDetailGateway();

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) => const _ImmediatePlaylistDetailOperation();
}

class _ImmediatePlaylistDetailOperation
    implements PlaylistTrackPageLoadOperation {
  const _ImmediatePlaylistDetailOperation();

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async => const PlaylistTrackPageResult(
    tracks: [_trackA],
    total: 1,
    offset: 0,
    nextOffset: 1,
    hasMore: false,
  );
}

class _IdleLibraryGateway implements UserLibraryGateway {
  const _IdleLibraryGateway();

  @override
  UserLibraryLoadOperation beginLoad() => const _ImmediateLibraryOperation();
}

class _ImmediateLibraryOperation implements UserLibraryLoadOperation {
  const _ImmediateLibraryOperation();

  @override
  bool cancel() => true;

  @override
  Future<UserLibraryResult> run() async => const UserLibraryResult();
}
