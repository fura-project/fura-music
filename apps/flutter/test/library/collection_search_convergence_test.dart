import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/partial_results_notice.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_en.dart';
import 'package:flutterustmusic/l10n/app_localizations_zh.dart';
import 'package:flutterustmusic/library/album_favorite_presentation_controller.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/library/liked_songs_page.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_track_search_index.dart';
import 'package:flutterustmusic/library/recent_plays_gateway.dart';
import 'package:flutterustmusic/library/recent_plays_page.dart';
import 'package:flutterustmusic/library/track_like_gateway.dart';
import 'package:flutterustmusic/library/track_like_presentation_controller.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/provider_diagnostics.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

final _en = AppLocalizationsEn();
final _zh = AppLocalizationsZh();

void main() {
  const likedPlaylist = UserPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'owned:7001:201',
    title: 'Liked Songs',
    trackCount: 1117,
    isLikedSongs: true,
    ownership: UserPlaylistOwnership.owned,
  );

  group('Workstream A — Collection Search Convergence (S01–S10)', () {
    testWidgets(
      'S01: 1117 warm-cached Liked Songs searches deep index 1050 with 0 extra HTTP and 0 scrolling',
      (tester) async {
        final pages = _build1117Pages(targetIndex: 1050, omittedAt400: true);
        final gateway = _CountingDetailGateway(pages);
        final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
        addTearDown(mutations.dispose);
        final likes = TrackLikePresentationController(
          providerId: 'qq-music',
          enabled: true,
          playlistGateway: gateway,
          mutations: mutations,
        )..bindLikedPlaylist(likedPlaylist);
        addTearDown(likes.dispose);
        await likes.preload();
        expect(gateway.requestCount, 12);

        final queue = _buildQueueController();
        addTearDown(queue.dispose);
        final albums = AlbumFavoritePresentationController(
          providerId: 'qq-music',
          enabled: false,
          gateway: const _UnusedFavoriteAlbumGateway(),
          mutations: mutations,
        );
        addTearDown(albums.dispose);

        await tester.pumpWidget(
          _wrapApp(
            LikedSongsPage(
              playlist: likedPlaylist,
              playlists: const [likedPlaylist],
              gateway: likes.sessionGateway,
              trackLikeController: likes,
              favoriteAlbumGateway: const _UnusedFavoriteAlbumGateway(),
              albumFavoriteController: albums,
              queuePlaybackController: queue,
              onOpenPlaylist: (_) {},
              onSignInAgain: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final requestsBeforeSearch = gateway.requestCount;
        expect(requestsBeforeSearch, 12);

        // Search all 4 real-world Nevada variants without scrolling.
        for (final query in const ['neveda', 'NEVEDA', 'nevada', 'NEVADA']) {
          await tester.enterText(
            find.byKey(const ValueKey('liked-songs-search')),
            query,
          );
          await tester.pump();
          await tester.pump();
          expect(find.text('Nevada'), findsOneWidget, reason: 'query=$query');
          expect(
            gateway.requestCount,
            requestsBeforeSearch,
            reason: 'zero new HTTP for warm query=$query',
          );
        }

        // Filtered Play All stays snapshot-based and never attaches unfiltered collection continuation.
        await tester.tap(find.byKey(const ValueKey('liked-songs-play-all')));
        await tester.pumpAndSettle();
        expect(queue.tracks.map((t) => t.title), ['Nevada']);
        expect(queue.collectionSourceId, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    test('S02 & S03: cold 1117-track search covers deep match even past 20 early matches', () async {
      final pages = _build1117Pages(
        targetIndex: 1050,
        extraMatchPrefixCount: 35,
      );
      final gateway = _CountingDetailGateway(pages);
      final controller = PlaylistDetailController(
        likedPlaylist,
        gateway,
        loadAllPageInterval: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.processedCount, 100);
      expect(gateway.requestCount, 1);

      await controller.requestSearchCoverage();

      expect(controller.processedCount, 1117);
      expect(controller.hasMore, isFalse);
      expect(controller.searchScanStage, CollectionSearchScanStage.complete);
      expect(gateway.requestCount, 12);

      final index = PlaylistTrackSearchIndex()
        ..update(
          controller.tracks,
          collectionGeneration: controller.snapshotGeneration,
        );
      final result = index.search('nevada');
      // 35 early matches + 1 deep match at 1050 = 36 total (did NOT stop at 20!).
      expect(result.tracks, hasLength(36));
      expect(
        result.tracks.any((track) => track.opaqueId == 'track:1050'),
        isTrue,
      );
    });

    test('S04 & S05: rapid query replacement reuses scan and Heart preload single-flights pages', () async {
      final completers = <int, Completer<PlaylistTrackPageResult>>{
        for (var offset = 0; offset < 300; offset += 100)
          offset: Completer<PlaylistTrackPageResult>(),
      };
      final gateway = _ControlledDetailGateway(completers);
      final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
      addTearDown(mutations.dispose);
      final likes = TrackLikePresentationController(
        providerId: 'qq-music',
        enabled: true,
        playlistGateway: gateway,
        mutations: mutations,
      )..bindLikedPlaylist(likedPlaylist);
      addTearDown(likes.dispose);

      // Offset 0 completes; Heart preload immediately starts offset 100.
      completers[0]!.complete(_page(0, 300));
      await Future<void>.delayed(Duration.zero);
      expect(gateway.requestedOffsets, [0, 100]);

      // Controller opens page 0 from cache (0 extra requests), then starts search
      // which joins the pending offset 100 single-flight.
      final detail = PlaylistDetailController(
        likedPlaylist,
        likes.sessionGateway,
        loadAllPageInterval: Duration.zero,
      );
      addTearDown(detail.dispose);
      await detail.load();
      expect(gateway.requestedOffsets, [0, 100]);

      final searchFuture = detail.requestSearchCoverage();
      await Future<void>.delayed(Duration.zero);
      // Offset 100 MUST NOT be requested twice!
      expect(gateway.requestedOffsets, [0, 100]);

      // Clearing search cancels only unconsumed future search budget and NEVER
      // aborts the in-flight page needed by Heart preload.
      detail.cancelSearchScan();
      expect(gateway.cancelledOffsets, isEmpty);

      completers[100]!.complete(_page(100, 300));
      await Future<void>.delayed(Duration.zero);
      completers[200]!.complete(_page(200, 300));
      await likes.preload();
      await searchFuture;

      expect(gateway.requestedOffsets, [0, 100, 200]);
      // Next query immediately absorbs page 200 from cache with 0 extra HTTP!
      await detail.requestSearchCoverage();
      expect(detail.processedCount, 300);
      expect(detail.hasMore, isFalse);
      expect(gateway.requestedOffsets, [0, 100, 200]);
    });

    test('S06 (7A): non-cooperative delayed pre-refresh Future cannot poison new snapshot or search', () async {
      final stalePage0 = Completer<PlaylistTrackPageResult>();
      final freshPage0 = Completer<PlaylistTrackPageResult>();
      var callCount = 0;
      final gateway = _CallbackDetailGateway((playlist, offset, size) {
        callCount += 1;
        if (callCount == 1) {
          // Non-cooperative operation: ignores cancel() and resolves later!
          return _NonCooperativeOperation(stalePage0.future);
        }
        return _NonCooperativeOperation(freshPage0.future);
      });
      final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
      addTearDown(mutations.dispose);
      final likes = TrackLikePresentationController(
        providerId: 'qq-music',
        enabled: true,
        playlistGateway: gateway,
        mutations: mutations,
      )..bindLikedPlaylist(likedPlaylist);
      addTearDown(likes.dispose);

      // Start explicit refresh while stalePage0 is still pending.
      final refreshFuture = likes.refreshSnapshot();
      await Future<void>.delayed(Duration.zero);

      // Now stalePage0 resolves late with old pre-refresh data!
      stalePage0.complete(
        const PlaylistTrackPageResult(
          offset: 0,
          nextOffset: 1,
          total: 1,
          hasMore: false,
          membershipTrackOpaqueIds: ['stale-deleted-track'],
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'stale-deleted-track',
              title: 'Stale Deleted Track',
              artistNames: ['Old Artist'],
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Fresh snapshot has NOT resolved yet, so stale data MUST NOT appear in
      // cached continuation or commit refresh.
      final cachedGateway =
          likes.sessionGateway as CachedPlaylistTrackPagesGateway;
      expect(
        cachedGateway.readCachedContinuation(
          playlist: likedPlaylist,
          fromOffset: 0,
          size: 100,
        ),
        isEmpty,
      );

      // Complete the real refresh page with fresh track only.
      freshPage0.complete(
        const PlaylistTrackPageResult(
          offset: 0,
          nextOffset: 1,
          total: 1,
          hasMore: false,
          membershipTrackOpaqueIds: ['fresh-track'],
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'fresh-track',
              title: 'Fresh Track',
              artistNames: ['New Artist'],
            ),
          ],
        ),
      );
      await refreshFuture;

      expect(
        likes.stateFor(
          const PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'stale-deleted-track',
            title: 'Stale Deleted Track',
            artistNames: ['Old Artist'],
          ),
        ),
        AuthoritativeTrackLikeState.notLiked,
      );
      expect(
        likes.stateFor(
          const PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'fresh-track',
            title: 'Fresh Track',
            artistNames: ['New Artist'],
          ),
        ),
        AuthoritativeTrackLikeState.liked,
      );
      final cachedPages = cachedGateway.readCachedContinuation(
        playlist: likedPlaylist,
        fromOffset: 0,
        size: 100,
      );
      expect(cachedPages.single.tracks.single.opaqueId, 'fresh-track');
    });

    test('S07 (7B & 7C): membershipComplete != presentationComplete, invalid pages rejected, confirmed mutation drops stale cache', () async {
      // 1. NetEase-style page 0 carries all 200 membership IDs, but only 100 presentation tracks (hasMore: true).
      final pages = <int, PlaylistTrackPageResult>{
        0: PlaylistTrackPageResult(
          offset: 0,
          nextOffset: 100,
          total: 200,
          hasMore: true,
          membershipTrackOpaqueIds: [for (var i = 0; i < 200; i++) 'track:$i'],
          tracks: _page(0, 200).tracks,
        ),
        100: _page(100, 200),
      };
      final gateway = _CountingDetailGateway(pages);
      final unlikeGateway = _StaticTrackLikeGateway(
        const TrackLikeMutationResult(confirmedState: TrackLikeState.notLiked),
      );
      final mutations = LibraryMutationCoordinator(
        providerId: 'qq-music',
        trackLikeGateway: unlikeGateway,
      );
      addTearDown(mutations.dispose);
      final likes = TrackLikePresentationController(
        providerId: 'qq-music',
        enabled: true,
        playlistGateway: gateway,
        mutations: mutations,
      )..bindLikedPlaylist(likedPlaylist);
      addTearDown(likes.dispose);

      // Preload finishes membership at offset 100 (1 request) without fetching presentation offset 100.
      await likes.preload();
      expect(gateway.requestCount, 1);

      // Search MUST NOT claim complete from membershipComplete; it must fetch page 100!
      final detail = PlaylistDetailController(
        likedPlaylist,
        likes.sessionGateway,
        loadAllPageInterval: Duration.zero,
      );
      addTearDown(detail.dispose);
      await detail.load();
      expect(detail.hasMore, isTrue);
      await detail.requestSearchCoverage();
      expect(detail.processedCount, 200);
      expect(detail.hasMore, isFalse);
      expect(gateway.requestCount, 2);

      // 2. Confirmed unlike WITHOUT refreshAdditionalState MUST invalidate _sharedPages so deleted track cannot be revived.
      await likes.setLiked(track: pages[0]!.tracks.first, liked: false);
      final cachedGateway =
          likes.sessionGateway as CachedPlaylistTrackPagesGateway;
      expect(
        cachedGateway.readCachedContinuation(
          playlist: likedPlaylist,
          fromOffset: 0,
          size: 100,
        ),
        isEmpty,
      );

      // 3. Invalid pages (missing continuation -1, non-advancing cursor, wrong provider)
      // MUST NOT populate cache or complete membership.
      for (final invalid in const [
        PlaylistTrackPageResult(offset: 0, nextOffset: -1, total: 1),
        PlaylistTrackPageResult(
          offset: 0,
          nextOffset: 0,
          total: 10,
          hasMore: true,
        ),
        PlaylistTrackPageResult(
          offset: 0,
          nextOffset: 1,
          total: 1,
          tracks: [
            PlaylistTrackSummary(
              providerId: 'netease',
              opaqueId: 'foreign:1',
              title: 'Foreign',
              artistNames: ['Other'],
            ),
          ],
        ),
      ]) {
        final badGateway = _CallbackDetailGateway(
          (_, _, _) => _ImmediateDetailOp(invalid),
        );
        final badLikes = TrackLikePresentationController(
          providerId: 'qq-music',
          enabled: true,
          playlistGateway: badGateway,
          mutations: mutations,
        )..bindLikedPlaylist(likedPlaylist);
        await badLikes.preload();
        expect(
          badLikes.stateFor(
            const PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'absent-track',
              title: 'Absent',
              artistNames: ['Artist'],
            ),
          ),
          AuthoritativeTrackLikeState.unknown,
        );
        expect(
          (badLikes.sessionGateway as CachedPlaylistTrackPagesGateway)
              .readCachedContinuation(
                playlist: likedPlaylist,
                fromOffset: 0,
                size: 100,
              ),
          isEmpty,
        );
        badLikes.dispose();
      }
    });

    testWidgets(
      'S08: omitted track shows calm collection-scoped notice (non-red in Editorial & M3) and does not re-announce on query replacement',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final pages = _build1117Pages(targetIndex: 1050, omittedAt400: true);
          final gateway = _CountingDetailGateway(pages);
          final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
          addTearDown(mutations.dispose);
          final likes = TrackLikePresentationController(
            providerId: 'qq-music',
            enabled: true,
            playlistGateway: gateway,
            mutations: mutations,
          )..bindLikedPlaylist(likedPlaylist);
          addTearDown(likes.dispose);
          await likes.preload();

          final queue = _buildQueueController();
          addTearDown(queue.dispose);
          final albums = AlbumFavoritePresentationController(
            providerId: 'qq-music',
            enabled: false,
            gateway: const _UnusedFavoriteAlbumGateway(),
            mutations: mutations,
          );
          addTearDown(albums.dispose);

          // Render in Magazine Editorial Light theme + zh locale (exact scenario from Human screenshot!).
          await tester.pumpWidget(
            _wrapApp(
              LikedSongsPage(
                playlist: likedPlaylist,
                playlists: const [likedPlaylist],
                gateway: likes.sessionGateway,
                trackLikeController: likes,
                favoriteAlbumGateway: const _UnusedFavoriteAlbumGateway(),
                albumFavoriteController: albums,
                queuePlaybackController: queue,
                onOpenPlaylist: (_) {},
                onSignInAgain: () {},
              ),
              locale: const Locale('zh'),
              theme: buildEditorialTheme(Brightness.light),
            ),
          );
          await tester.pumpAndSettle();

          await tester.enterText(
            find.byKey(const ValueKey('liked-songs-search')),
            'neveda',
          );
          await tester.pump();
          await tester.pump();

          expect(find.text('Nevada'), findsOneWidget);
          expect(
            find.text(_zh.collectionSearchPartialNotice(1)),
            findsOneWidget,
          );
          // Verify Editorial styling uses calm cardSurface, NOT red tertiaryContainer!
          final noticeDecorated = tester.widget<DecoratedBox>(
            find.descendant(
              of: find.byType(PartialResultsNotice),
              matching: find.byType(DecoratedBox),
            ),
          );
          final box = noticeDecorated.decoration as BoxDecoration;
          expect(box.color, MusicEditorialTheme.editorialLight.cardSurface);
          expect(
            box.color,
            isNot(
              buildEditorialTheme(Brightness.light)
                  .colorScheme
                  .tertiaryContainer,
            ),
          );

          // Initial omission announcement settles to liveRegion: false after frame.
          await tester.pump();
          final noticeSemantics = find.byKey(
            const ValueKey('partial-results-semantics'),
          );
          expect(
            tester
                .getSemantics(noticeSemantics)
                .getSemanticsData()
                .flagsCollection
                .isLiveRegion,
            isFalse,
          );

          // Query replacement (including through empty-match -> back to match)
          // MUST NOT re-announce liveRegion for the same omission revision.
          await tester.enterText(
            find.byKey(const ValueKey('liked-songs-search')),
            'zzzznomatch',
          );
          await tester.pump();
          await tester.enterText(
            find.byKey(const ValueKey('liked-songs-search')),
            'NEVEDA',
          );
          await tester.pump();
          expect(find.text('Nevada'), findsOneWidget);
          expect(
            tester
                .getSemantics(noticeSemantics)
                .getSemanticsData()
                .flagsCollection
                .isLiveRegion,
            isFalse,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    test('7D: diagnostic networkRequests distinguishes transport, cache hit, and single-flight join', () async {
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugProviderDiagnosticsEnabledOverride = true;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() {
        debugProviderDiagnosticsEnabledOverride = null;
        debugPrint = previousDebugPrint;
      });

      final completer = Completer<PlaylistTrackPageResult>();
      final gateway = _ControlledDetailGateway({0: completer});
      final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
      addTearDown(mutations.dispose);
      final likes = TrackLikePresentationController(
        providerId: 'qq-music',
        enabled: true,
        playlistGateway: gateway,
        mutations: mutations,
      )..bindLikedPlaylist(likedPlaylist);
      addTearDown(likes.dispose);

      // bindLikedPlaylist immediately starts preload() for offset 0 -> 1 transport request
      // (network_requests=1, cache=miss, single_flight_join=false).
      // 1. Concurrent sessionGateway caller joins pending preload -> single_flight_join=true, network_requests=0.
      final op1 = likes.sessionGateway.beginLoad(
        playlist: likedPlaylist,
        offset: 0,
        size: 100,
      );
      // 2. Second concurrent caller also joins pending page -> single_flight_join=true, network_requests=0.
      final op2 = likes.sessionGateway.beginLoad(
        playlist: likedPlaylist,
        offset: 0,
        size: 100,
      );
      final f1 = op1.run();
      final f2 = op2.run();
      completer.complete(_page(0, 100));
      await Future.wait([f1, f2]);

      // 3. Post-resolution request = cache hit (network_requests=0, cache=hit)
      final op3 = likes.sessionGateway.beginLoad(
        playlist: likedPlaylist,
        offset: 0,
        size: 100,
      );
      await op3.run();

      // 4. Synchronous cached continuation read = cache hit (network_requests=0, cache=hit)
      final cached = (likes.sessionGateway as CachedPlaylistTrackPagesGateway)
          .readCachedContinuation(
            playlist: likedPlaylist,
            fromOffset: 0,
            size: 100,
          );
      expect(cached, hasLength(1));

      expect(gateway.requestedOffsets, [0]);
      final transportLogs = logs
          .where((l) => l.contains('network_requests=1'))
          .toList();
      final joinLogs = logs
          .where(
            (l) =>
                l.contains('single_flight_join=true') &&
                l.contains('network_requests=0'),
          )
          .toList();
      final hitLogs = logs
          .where(
            (l) => l.contains('cache=hit') && l.contains('network_requests=0'),
          )
          .toList();
      expect(transportLogs, hasLength(1));
      expect(joinLogs, hasLength(2));
      expect(hitLogs, hasLength(2));
    });

    testWidgets(
      'Section 13 layout hygiene: PartialResultsNotice renders cleanly without overflow across Material/Editorial and compact/desktop',
      (tester) async {
        for (final entry in <(String, ThemeData)>[
          ('m3-light', MusicMaterialTheme.light()),
          ('m3-dark', MusicMaterialTheme.dark()),
          ('editorial-light', buildEditorialTheme(Brightness.light)),
          ('editorial-dark', buildEditorialTheme(Brightness.dark)),
        ]) {
          for (final width in const [360.0, 1200.0]) {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              _wrapApp(
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: PartialResultsNotice(
                    omittedCount: 1,
                    resultRevision: 1,
                    message: _zh.collectionSearchPartialNotice(1),
                    announce: false,
                  ),
                ),
                locale: const Locale('zh'),
                theme: entry.$2,
              ),
            );
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason: 'overflow or exception in ${entry.$1} @ ${width}px',
            );
            final decorated = tester.widget<DecoratedBox>(
              find.descendant(
                of: find.byType(PartialResultsNotice),
                matching: find.byType(DecoratedBox),
              ),
            );
            final box = decorated.decoration as BoxDecoration;
            expect(
              box.color,
              isNot(entry.$2.colorScheme.tertiaryContainer),
              reason: '${entry.$1} must not use reddish tertiaryContainer',
            );
          }
        }
      },
    );

    test('S09 & paused budget: interrupted resumes exact cursor; paused never claims complete', () async {
      var failOnce = true;
      final offsets = <int>[];
      final gateway = _CallbackDetailGateway((playlist, offset, size) {
        offsets.add(offset);
        if (offset == 100 && failOnce) {
          failOnce = false;
          return const _ImmediateDetailOp(
            PlaylistTrackPageResult(failure: UserLibraryFailure.network),
          );
        }
        return _ImmediateDetailOp(_page(offset, 500));
      });
      final controller = PlaylistDetailController(
        likedPlaylist,
        gateway,
        loadAllPageInterval: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.requestSearchCoverage(maxNetworkPages: 2);
      expect(controller.searchScanStage, CollectionSearchScanStage.interrupted);
      expect(controller.processedCount, 100);
      expect(controller.hasMore, isTrue);

      // Explicit retry resumes from offset 100 (NOT 0) and pauses cleanly at budget=2 (offsets 100, 200).
      await controller.requestSearchCoverage(
        maxNetworkPages: 2,
        retryInterrupted: true,
      );
      expect(offsets, [0, 100, 100, 200]);
      expect(controller.processedCount, 300);
      expect(controller.hasMore, isTrue);
      expect(controller.searchScanStage, CollectionSearchScanStage.paused);

      // Continue search finishes remaining pages 300, 400.
      await controller.requestSearchCoverage(maxNetworkPages: 5);
      expect(offsets, [0, 100, 100, 200, 300, 400]);
      expect(controller.processedCount, 500);
      expect(controller.hasMore, isFalse);
      expect(controller.searchScanStage, CollectionSearchScanStage.complete);
    });

    testWidgets(
      'S10: RecentPlaysPage searches deep record at index 480 of 500 without scrolling and respects active cancel',
      (tester) async {
        final gateway = _RecentPlaysFixtureGateway(
          total: 500,
          targetIndex: 480,
        );
        final queue = _buildQueueController();
        addTearDown(queue.dispose);

        await tester.pumpWidget(
          _wrapApp(
            RecentPlaysPage(
              gateway: gateway,
              playback: queue,
              onSignInAgain: () {},
              active: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(gateway.requestedOffsets, [0]);

        await tester.enterText(
          find.byKey(const ValueKey('recent-plays-search')),
          'neveda',
        );
        await tester.pumpAndSettle();

        expect(gateway.requestedOffsets, [0, 100, 200, 300, 400]);
        expect(find.text('Nevada'), findsOneWidget);
        expect(find.text(_en.recentPlayFiltered(1)), findsOneWidget);

        // Query replacement does NOT re-fetch already loaded pages.
        await tester.enterText(
          find.byKey(const ValueKey('recent-plays-search')),
          'NEVADA',
        );
        await tester.pumpAndSettle();
        expect(gateway.requestedOffsets, [0, 100, 200, 300, 400]);
        expect(find.text('Nevada'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    test('optimized fuzzy Damerau-Levenshtein matches naive 2D matrix across edge pairs', () {
      const candidates = [
        'nevada',
        'neveda',
        'navada',
        'nevdaa',
        'nvada',
        'nevadda',
        'nevadab',
        'anevada',
        'nevd',
        'completelydifferent',
        'abcdefgh',
        'abcedfgh',
        'abcefdgh',
        'abcdefg',
        'abcdefghi',
        'axcdefgh',
        'axcdyfgh',
        'xyzdefgh',
      ];
      final tracks = [
        for (var i = 0; i < candidates.length; i++)
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:$i',
            title: candidates[i],
            artistNames: const ['Artist'],
          ),
      ];
      final index = PlaylistTrackSearchIndex()..update(tracks);

      for (final query in const [
        'nevada',
        'neveda',
        'nevdaa',
        'nvada',
        'nevadda',
        'abcdefgh',
        'abcedfgh',
        'axcdyfgh',
        'abcdefg',
        'abcdefghi',
      ]) {
        final actual = index.search(query).tracks.map((t) => t.title).toSet();
        final expected = <String>{};
        final maxDist = query.length >= 8 ? 2 : 1;
        for (final candidate in candidates) {
          if (candidate.contains(query) ||
              _naiveDamerauLevenshtein(query, candidate) <= maxDist) {
            expected.add(candidate);
          }
        }
        expect(actual, expected, reason: 'equivalence failed for query=$query');
      }
    });

    test('Bug 1 (7A): stale pre-refresh replaced/session failure cannot wipe active session', () async {
      final preRefreshPage0 = Completer<PlaylistTrackPageResult>();
      var callCount = 0;
      final gateway = _CallbackDetailGateway((playlist, offset, size) {
        callCount += 1;
        if (callCount == 1) {
          return _NonCooperativeOperation(preRefreshPage0.future);
        }
        return _ImmediateDetailOp(
          PlaylistTrackPageResult(
            offset: 0,
            nextOffset: 1,
            total: 1,
            hasMore: false,
            membershipTrackOpaqueIds: const ['track:fresh'],
            tracks: const [
              PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:fresh',
                title: 'Fresh Track',
                artistNames: ['Artist'],
              ),
            ],
          ),
        );
      });
      final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
      addTearDown(mutations.dispose);
      final likes = TrackLikePresentationController(
        providerId: 'qq-music',
        enabled: true,
        playlistGateway: gateway,
        mutations: mutations,
      )..bindLikedPlaylist(likedPlaylist);
      addTearDown(likes.dispose);

      await Future<void>.delayed(Duration.zero);
      // Refresh bumps _pageRevision while generation remains unchanged.
      await likes.refreshSnapshot();

      // Now the stale pre-refresh Future settles with UserLibraryFailure.replaced.
      preRefreshPage0.complete(
        const PlaylistTrackPageResult(failure: UserLibraryFailure.replaced),
      );
      await Future<void>.delayed(Duration.zero);

      // Active session MUST survive!
      expect(
        likes.stateFor(
          const PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:fresh',
            title: 'Fresh Track',
            artistNames: ['Artist'],
          ),
        ),
        AuthoritativeTrackLikeState.liked,
      );
    });

    test('Bug 2 (7C): external confirmed unlike invalidates controller search & prevents cross-snapshot mixing', () async {
      var unliked = false;
      final gateway = _CallbackDetailGateway((playlist, offset, size) {
        // Pre-mutation: 150 tracks (0..149) with track:5 titled "Nevada".
        // Post-mutation: 149 tracks (track:5 removed, indices shifted by 1).
        final all = [
          for (var i = 0; i < 150; i++)
            if (!(unliked && i == 5))
              PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:$i',
                title: i == 5
                    ? 'Nevada'
                    : i == 100
                    ? 'Boundary Track 100'
                    : 'Song $i',
                artistNames: const ['Artist'],
              ),
        ];
        final end = (offset + size).clamp(0, all.length);
        final slice = all.sublist(offset, end);
        return _ImmediateDetailOp(
          PlaylistTrackPageResult(
            offset: offset,
            nextOffset: end,
            total: all.length,
            hasMore: end < all.length,
            membershipTrackOpaqueIds: [for (final t in slice) t.opaqueId],
            tracks: slice,
          ),
        );
      });
      final unlikeGateway = _StaticTrackLikeGateway(
        const TrackLikeMutationResult(confirmedState: TrackLikeState.notLiked),
      );
      final mutations = LibraryMutationCoordinator(
        providerId: 'qq-music',
        trackLikeGateway: unlikeGateway,
      );
      addTearDown(mutations.dispose);
      final likes = TrackLikePresentationController(
        providerId: 'qq-music',
        enabled: true,
        playlistGateway: gateway,
        mutations: mutations,
      )..bindLikedPlaylist(likedPlaylist);
      addTearDown(likes.dispose);
      await likes.preload();

      // Controller loads page 0 (tracks 0..99, including Nevada at index 5).
      final detail = PlaylistDetailController(
        likedPlaylist,
        likes.sessionGateway,
        loadAllPageInterval: Duration.zero,
      );
      addTearDown(detail.dispose);
      await detail.load();
      expect(detail.tracks.any((t) => t.opaqueId == 'track:5'), isTrue);

      // User unlikes track:5 externally (e.g. from Now Playing bar, no refreshAdditionalState).
      unliked = true;
      await likes.setLiked(
        track: detail.tracks.firstWhere((t) => t.opaqueId == 'track:5'),
        liked: false,
      );

      // Searching MUST reflect confirmed mutation: deleted track:5 MUST NOT appear,
      // and shifted Boundary Track 100 MUST NOT be lost between page 0 and page 1!
      await detail.requestSearchCoverage();
      expect(detail.tracks.any((t) => t.opaqueId == 'track:5'), isFalse);
      expect(detail.tracks.any((t) => t.opaqueId == 'track:100'), isTrue);
      expect(detail.tracks.length, 149);
    });

    test('Bug 3 (7C): confirmed mutation during in-flight partial resolve does not strand loading state or skip shifted tracks', () async {
      final page1Completer = Completer<PlaylistTrackPageResult>();
      var mutated = false;
      var page1Calls = 0;
      final gateway = _CallbackDetailGateway((playlist, offset, size) {
        if (!mutated && offset == 100 && page1Calls == 0) {
          page1Calls += 1;
          return _NonCooperativeOperation(page1Completer.future);
        }
        // After mutation, track:shifted moved from offset 100 into offset 99 (page 0).
        if (mutated && offset == 0) {
          return _ImmediateDetailOp(
            const PlaylistTrackPageResult(
              offset: 0,
              nextOffset: 1,
              total: 1,
              hasMore: false,
              membershipTrackOpaqueIds: ['track:shifted'],
              tracks: [
                PlaylistTrackSummary(
                  providerId: 'qq-music',
                  opaqueId: 'track:shifted',
                  title: 'Shifted',
                  artistNames: ['Artist'],
                ),
              ],
            ),
          );
        }
        return _ImmediateDetailOp(
          PlaylistTrackPageResult(
            offset: 0,
            nextOffset: 100,
            total: 200,
            hasMore: true,
            membershipTrackOpaqueIds: [
              for (var i = 0; i < 100; i++) 'track:$i',
            ],
            tracks: _page(0, 200).tracks,
          ),
        );
      });
      final unlikeGateway = _StaticTrackLikeGateway(
        const TrackLikeMutationResult(confirmedState: TrackLikeState.notLiked),
      );
      final mutations = LibraryMutationCoordinator(
        providerId: 'qq-music',
        trackLikeGateway: unlikeGateway,
      );
      addTearDown(mutations.dispose);
      final likes = TrackLikePresentationController(
        providerId: 'qq-music',
        enabled: true,
        playlistGateway: gateway,
        mutations: mutations,
      )..bindLikedPlaylist(likedPlaylist);
      addTearDown(likes.dispose);

      const shifted = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:shifted',
        title: 'Shifted',
        artistNames: ['Artist'],
      );
      final pendingResolve = likes.resolve(shifted);
      await Future<void>.delayed(Duration.zero);
      expect(likes.stateFor(shifted), AuthoritativeTrackLikeState.loading);

      mutated = true;
      await likes.setLiked(
        track: const PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:0',
          title: 'Track 0',
          artistNames: ['Artist'],
        ),
        liked: false,
      );
      // Must not be stuck in loading!
      expect(
        likes.stateFor(shifted),
        isNot(AuthoritativeTrackLikeState.loading),
      );
      page1Completer.complete(_page(100, 200));
      await pendingResolve;

      // Next resolve must re-scan from offset 0 and discover shifted track!
      expect(await likes.resolve(shifted), AuthoritativeTrackLikeState.liked);
    });

    test('Bug 4 (7B/7D): refreshSnapshot aborted on error does not log outcome=success', () async {
      final logs = <String>[];
      final previousPrint = debugPrint;
      debugProviderDiagnosticsEnabledOverride = true;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() {
        debugProviderDiagnosticsEnabledOverride = null;
        debugPrint = previousPrint;
      });

      var fail = false;
      final gateway = _CallbackDetailGateway((playlist, offset, size) {
        if (fail) {
          return _ImmediateDetailOp(
            const PlaylistTrackPageResult(failure: UserLibraryFailure.network),
          );
        }
        return _ImmediateDetailOp(
          const PlaylistTrackPageResult(
            offset: 0,
            nextOffset: 1,
            total: 1,
            hasMore: false,
            membershipTrackOpaqueIds: ['track:1'],
            tracks: [
              PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:1',
                title: 'Track 1',
                artistNames: ['Artist'],
              ),
            ],
          ),
        );
      });
      final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
      addTearDown(mutations.dispose);
      final likes = TrackLikePresentationController(
        providerId: 'qq-music',
        enabled: true,
        playlistGateway: gateway,
        mutations: mutations,
      )..bindLikedPlaylist(likedPlaylist);
      addTearDown(likes.dispose);
      await likes.preload();
      logs.clear();

      fail = true;
      await likes.refreshSnapshot();

      expect(
        logs.any(
          (line) =>
              line.contains('phase=refresh') &&
              line.contains('outcome=success'),
        ),
        isFalse,
      );
    });

    testWidgets(
      'Bug 7a: non-search all-omitted page 0 does not render false "No matching tracks" search-empty state',
      (tester) async {
        final gateway = _CallbackDetailGateway(
          (_, _, _) => _ImmediateDetailOp(
            const PlaylistTrackPageResult(
              offset: 0,
              nextOffset: 1,
              total: 1,
              hasMore: false,
              omittedTrackCount: 1,
              membershipTrackOpaqueIds: ['track-membership:405:0'],
              tracks: [],
            ),
          ),
        );
        final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
        addTearDown(mutations.dispose);
        final likes = TrackLikePresentationController(
          providerId: 'qq-music',
          enabled: true,
          playlistGateway: gateway,
          mutations: mutations,
        )..bindLikedPlaylist(likedPlaylist);
        addTearDown(likes.dispose);
        final albumFavs = AlbumFavoritePresentationController(
          providerId: 'qq-music',
          enabled: false,
          gateway: const _UnusedFavoriteAlbumGateway(),
          mutations: mutations,
        );
        addTearDown(albumFavs.dispose);
        final queue = _buildQueueController();
        addTearDown(queue.dispose);

        await tester.pumpWidget(
          _wrapApp(
            LikedSongsPage(
              playlist: likedPlaylist,
              playlists: const [likedPlaylist],
              gateway: likes.sessionGateway,
              trackLikeController: likes,
              favoriteAlbumGateway: const _UnusedFavoriteAlbumGateway(),
              albumFavoriteController: albumFavs,
              queuePlaybackController: queue,
              onOpenPlaylist: (_) {},
              onSignInAgain: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('liked-songs-search-empty')),
          findsNothing,
        );
        expect(find.byType(PartialResultsNotice), findsOneWidget);
      },
    );

    testWidgets(
      'Bug 2 UI (7C): mounted LikedSongsPage reflects external confirmed unlike from Now Playing bar in search',
      (tester) async {
        var unliked = false;
        final gateway = _CallbackDetailGateway((playlist, offset, size) {
          final tracks = <PlaylistTrackSummary>[
            if (!unliked)
              const PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:nevada',
                title: 'Nevada',
                artistNames: ['Vicetone'],
              ),
            const PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:keep',
              title: 'Keep Me',
              artistNames: ['Artist'],
            ),
          ];
          return _ImmediateDetailOp(
            PlaylistTrackPageResult(
              offset: 0,
              nextOffset: tracks.length,
              total: tracks.length,
              hasMore: false,
              membershipTrackOpaqueIds: [for (final t in tracks) t.opaqueId],
              tracks: tracks,
            ),
          );
        });
        final unlikeGateway = _StaticTrackLikeGateway(
          const TrackLikeMutationResult(
            confirmedState: TrackLikeState.notLiked,
          ),
        );
        final mutations = LibraryMutationCoordinator(
          providerId: 'qq-music',
          trackLikeGateway: unlikeGateway,
        );
        addTearDown(mutations.dispose);
        final likes = TrackLikePresentationController(
          providerId: 'qq-music',
          enabled: true,
          playlistGateway: gateway,
          mutations: mutations,
        )..bindLikedPlaylist(likedPlaylist);
        addTearDown(likes.dispose);
        final albumFavs = AlbumFavoritePresentationController(
          providerId: 'qq-music',
          enabled: false,
          gateway: const _UnusedFavoriteAlbumGateway(),
          mutations: mutations,
        );
        addTearDown(albumFavs.dispose);
        final queue = _buildQueueController();
        addTearDown(queue.dispose);

        await tester.pumpWidget(
          _wrapApp(
            LikedSongsPage(
              playlist: likedPlaylist,
              playlists: const [likedPlaylist],
              gateway: likes.sessionGateway,
              trackLikeController: likes,
              favoriteAlbumGateway: const _UnusedFavoriteAlbumGateway(),
              albumFavoriteController: albumFavs,
              queuePlaybackController: queue,
              onOpenPlaylist: (_) {},
              onSignInAgain: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Nevada'), findsOneWidget);

        // External confirmed unlike (no refreshAdditionalState, e.g. from NowPlayingBar).
        unliked = true;
        await likes.setLiked(
          track: const PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:nevada',
            title: 'Nevada',
            artistNames: ['Vicetone'],
          ),
          liked: false,
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('liked-songs-search')),
          'nevada',
        );
        await tester.pumpAndSettle();

        // Deleted Nevada MUST NOT still appear in search results!
        expect(find.text('Nevada'), findsNothing);
        expect(
          find.byKey(const ValueKey('liked-songs-search-empty')),
          findsOneWidget,
        );
      },
    );

    test('Bug 7d: non-retryable alreadyRunning append failure keeps searchScanStage interrupted', () async {
      final gateway = _CallbackDetailGateway((playlist, offset, size) {
        if (offset == 0) {
          return _ImmediateDetailOp(_page(0, 200));
        }
        return _ImmediateDetailOp(
          const PlaylistTrackPageResult(
            failure: UserLibraryFailure.alreadyRunning,
          ),
        );
      });
      final controller = PlaylistDetailController(
        likedPlaylist,
        gateway,
        loadAllPageInterval: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.requestSearchCoverage();
      expect(controller.searchScanStage, CollectionSearchScanStage.interrupted);

      await controller.requestSearchCoverage(retryInterrupted: true);
      expect(controller.searchScanStage, CollectionSearchScanStage.interrupted);
    });

    test('Bug 4b (7B): refreshSnapshot with QQ-style full-membership page 0 keeps presentation incomplete', () async {
      final gateway = _CountingDetailGateway({
        0: PlaylistTrackPageResult(
          offset: 0,
          nextOffset: 100,
          total: 200,
          hasMore: true,
          membershipTrackOpaqueIds: [for (var i = 0; i < 200; i++) 'track:$i'],
          tracks: _page(0, 200).tracks,
        ),
        100: _page(100, 200),
      });
      final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
      addTearDown(mutations.dispose);
      final likes = TrackLikePresentationController(
        providerId: 'qq-music',
        enabled: true,
        playlistGateway: gateway,
        mutations: mutations,
      )..bindLikedPlaylist(likedPlaylist);
      addTearDown(likes.dispose);
      await likes.preload();
      await likes.refreshSnapshot();

      // Membership is authoritative (notLiked for absent track),
      // yet cached presentation only has page 0 (hasMore: true).
      expect(
        likes.stateFor(
          const PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:absent',
            title: 'Absent',
            artistNames: ['Artist'],
          ),
        ),
        AuthoritativeTrackLikeState.notLiked,
      );
      final detail = PlaylistDetailController(
        likedPlaylist,
        likes.sessionGateway,
        loadAllPageInterval: Duration.zero,
      );
      addTearDown(detail.dispose);
      await detail.load();
      expect(detail.hasMore, isTrue);
      await detail.requestSearchCoverage();
      expect(detail.processedCount, 200);
      expect(detail.hasMore, isFalse);
    });

    testWidgets(
      'Bug 2 UI inactive (7C): inactive LikedSongsPage defers external mutation refresh until active',
      (tester) async {
        var unliked = false;
        var requests = 0;
        final gateway = _CallbackDetailGateway((playlist, offset, size) {
          requests += 1;
          final tracks = <PlaylistTrackSummary>[
            if (!unliked)
              const PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:nevada',
                title: 'Nevada',
                artistNames: ['Vicetone'],
              ),
            const PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:keep',
              title: 'Keep Me',
              artistNames: ['Artist'],
            ),
          ];
          return _ImmediateDetailOp(
            PlaylistTrackPageResult(
              offset: 0,
              nextOffset: tracks.length,
              total: tracks.length,
              hasMore: false,
              membershipTrackOpaqueIds: [for (final t in tracks) t.opaqueId],
              tracks: tracks,
            ),
          );
        });
        final unlikeGateway = _StaticTrackLikeGateway(
          const TrackLikeMutationResult(
            confirmedState: TrackLikeState.notLiked,
          ),
        );
        final mutations = LibraryMutationCoordinator(
          providerId: 'qq-music',
          trackLikeGateway: unlikeGateway,
        );
        addTearDown(mutations.dispose);
        final likes = TrackLikePresentationController(
          providerId: 'qq-music',
          enabled: true,
          playlistGateway: gateway,
          mutations: mutations,
        )..bindLikedPlaylist(likedPlaylist);
        addTearDown(likes.dispose);
        final albumFavs = AlbumFavoritePresentationController(
          providerId: 'qq-music',
          enabled: false,
          gateway: const _UnusedFavoriteAlbumGateway(),
          mutations: mutations,
        );
        addTearDown(albumFavs.dispose);
        final queue = _buildQueueController();
        addTearDown(queue.dispose);

        Widget buildPage({required bool active}) => _wrapApp(
          LikedSongsPage(
            playlist: likedPlaylist,
            playlists: const [likedPlaylist],
            gateway: likes.sessionGateway,
            trackLikeController: likes,
            favoriteAlbumGateway: const _UnusedFavoriteAlbumGateway(),
            albumFavoriteController: albumFavs,
            queuePlaybackController: queue,
            onOpenPlaylist: (_) {},
            onSignInAgain: () {},
            active: active,
          ),
        );

        await tester.pumpWidget(buildPage(active: true));
        await tester.pumpAndSettle();
        final requestsAfterInitialLoad = requests;

        // Switch away (active: false), then confirm unlike externally.
        await tester.pumpWidget(buildPage(active: false));
        await tester.pumpAndSettle();
        unliked = true;
        await likes.setLiked(
          track: const PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:nevada',
            title: 'Nevada',
            artistNames: ['Vicetone'],
          ),
          liked: false,
        );
        await tester.pumpAndSettle();
        // Must NOT hit the network while inactive.
        expect(requests, requestsAfterInitialLoad);

        // Returning (active: true) refreshes and drops deleted Nevada.
        await tester.pumpWidget(buildPage(active: true));
        await tester.pumpAndSettle();
        expect(requests, requestsAfterInitialLoad + 1);
        expect(find.text('Nevada'), findsNothing);
      },
    );

    testWidgets(
      'Bug 7c: offscreen browse PartialResultsNotice still announces once when search brings it onscreen, then never re-announces',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          // 100 tracks with 1 omitted row on page 0: footer is offscreen in browse mode.
          final tracks = List.generate(
            99,
            (i) => PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:$i',
              title: i == 50 ? 'Nevada' : 'Browse Track $i',
              artistNames: [i == 50 ? 'Vicetone' : 'Artist $i'],
            ),
          );
          final gateway = _CountingDetailGateway({
            0: PlaylistTrackPageResult(
              offset: 0,
              nextOffset: 100,
              total: 100,
              hasMore: false,
              omittedTrackCount: 1,
              membershipTrackOpaqueIds: [
                for (var i = 0; i < 100; i++) 'track:$i',
              ],
              tracks: tracks,
            ),
          });
          final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
          addTearDown(mutations.dispose);
          final likes = TrackLikePresentationController(
            providerId: 'qq-music',
            enabled: true,
            playlistGateway: gateway,
            mutations: mutations,
          )..bindLikedPlaylist(likedPlaylist);
          addTearDown(likes.dispose);
          final albumFavs = AlbumFavoritePresentationController(
            providerId: 'qq-music',
            enabled: false,
            gateway: const _UnusedFavoriteAlbumGateway(),
            mutations: mutations,
          );
          addTearDown(albumFavs.dispose);
          final queue = _buildQueueController();
          addTearDown(queue.dispose);

          await tester.pumpWidget(
            _wrapApp(
              LikedSongsPage(
                playlist: likedPlaylist,
                playlists: const [likedPlaylist],
                gateway: likes.sessionGateway,
                trackLikeController: likes,
                favoriteAlbumGateway: const _UnusedFavoriteAlbumGateway(),
                albumFavoriteController: albumFavs,
                queuePlaybackController: queue,
                onOpenPlaylist: (_) {},
                onSignInAgain: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Footer was offscreen during browse mode.
          expect(find.byType(PartialResultsNotice), findsNothing);

          // Search narrows to 1 result, bringing PartialResultsNotice onscreen for the FIRST time.
          await tester.enterText(
            find.byKey(const ValueKey('liked-songs-search')),
            'neveda',
          );
          await tester.pump();
          final firstMount = tester.widget<Semantics>(
            find.byKey(const ValueKey('partial-results-semantics')),
          );
          expect(firstMount.properties.liveRegion, isTrue);

          await tester.pumpAndSettle();
          final afterFirstFrame = tester.widget<Semantics>(
            find.byKey(const ValueKey('partial-results-semantics')),
          );
          expect(afterFirstFrame.properties.liveRegion, isFalse);

          // Replacing query to 0 matches (unmounts notice) and back MUST NOT re-announce!
          await tester.enterText(
            find.byKey(const ValueKey('liked-songs-search')),
            'zzzzzz',
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('liked-songs-search')),
            'NEVEDA',
          );
          await tester.pump();
          final afterRemount = tester.widget<Semantics>(
            find.byKey(const ValueKey('partial-results-semantics')),
          );
          expect(afterRemount.properties.liveRegion, isFalse);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'Bug 7a (RecentPlays): non-search all-omitted page 0 does not show false search-empty text',
      (tester) async {
        final recentGateway = _CallbackRecentPlaysGateway(
          (offset, size) => _ImmediateDetailOp(
            const PlaylistTrackPageResult(
              offset: 0,
              nextOffset: 1,
              total: 1,
              hasMore: false,
              omittedTrackCount: 1,
              tracks: [],
            ),
          ),
        );
        final queue = _buildQueueController();
        addTearDown(queue.dispose);

        await tester.pumpWidget(
          _wrapApp(
            RecentPlaysPage(
              gateway: recentGateway,
              playback: queue,
              onSignInAgain: () {},
              active: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('No matching'), findsNothing);
        expect(find.textContaining('Searching'), findsNothing);
      },
    );
  });
}

class _CallbackRecentPlaysGateway implements RecentPlaysGateway {
  const _CallbackRecentPlaysGateway(this._handler);

  final PlaylistTrackPageLoadOperation Function(int offset, int size) _handler;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _handler(offset, size);
}

int _naiveDamerauLevenshtein(String left, String right) {
  final rows = List.generate(
    left.length + 1,
    (row) => List<int>.filled(right.length + 1, 0),
  );
  for (var r = 0; r <= left.length; r++) {
    rows[r][0] = r;
  }
  for (var c = 0; c <= right.length; c++) {
    rows[0][c] = c;
  }
  for (var r = 1; r <= left.length; r++) {
    for (var c = 1; c <= right.length; c++) {
      var best =
          rows[r - 1][c - 1] +
          (left.codeUnitAt(r - 1) == right.codeUnitAt(c - 1) ? 0 : 1);
      if (rows[r][c - 1] + 1 < best) best = rows[r][c - 1] + 1;
      if (rows[r - 1][c] + 1 < best) best = rows[r - 1][c] + 1;
      if (r > 1 &&
          c > 1 &&
          left.codeUnitAt(r - 1) == right.codeUnitAt(c - 2) &&
          left.codeUnitAt(r - 2) == right.codeUnitAt(c - 1)) {
        final trans = rows[r - 2][c - 2] + 1;
        if (trans < best) best = trans;
      }
      rows[r][c] = best;
    }
  }
  return rows[left.length][right.length];
}

Map<int, PlaylistTrackPageResult> _build1117Pages({
  required int targetIndex,
  bool omittedAt400 = false,
  int extraMatchPrefixCount = 0,
}) {
  const total = 1117;
  final pages = <int, PlaylistTrackPageResult>{};
  for (var offset = 0; offset < total; offset += 100) {
    final end = (offset + 100).clamp(0, total);
    final tracks = <PlaylistTrackSummary>[];
    final membership = <String>[];
    var omitted = 0;
    for (var i = offset; i < end; i++) {
      membership.add('track-membership:$i:0');
      if (omittedAt400 && i == 405) {
        omitted += 1;
        continue;
      }
      final title = i == targetIndex
          ? 'Nevada'
          : i < extraMatchPrefixCount
          ? 'Nevada Remix $i'
          : 'Synthetic Track $i';
      tracks.add(
        PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:$i',
          membershipOpaqueId: 'track-membership:$i:0',
          title: title,
          artistNames: [i == targetIndex ? 'Vicetone' : 'Artist $i'],
        ),
      );
    }
    pages[offset] = PlaylistTrackPageResult(
      offset: offset,
      nextOffset: end,
      total: total,
      hasMore: end < total,
      omittedTrackCount: omitted,
      membershipTrackOpaqueIds: membership,
      tracks: tracks,
    );
  }
  return pages;
}

PlaylistTrackPageResult _page(int offset, int total) {
  final end = (offset + 100).clamp(0, total);
  return PlaylistTrackPageResult(
    offset: offset,
    nextOffset: end,
    total: total,
    hasMore: end < total,
    membershipTrackOpaqueIds: [for (var i = offset; i < end; i++) 'track:$i'],
    tracks: [
      for (var i = offset; i < end; i++)
        PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:$i',
          title: 'Track $i',
          artistNames: const ['Artist'],
        ),
    ],
  );
}

Widget _wrapApp(
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) => MaterialApp(
  locale: locale,
  theme: theme ?? MusicMaterialTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

QueuePlaybackController _buildQueueController() => QueuePlaybackController(
  _InMemoryQueueGateway(),
  TrackPlaybackController(
    const _NoopMediaGateway(),
    ForegroundPlaybackController(const _NoopAudioEngine()),
  ),
);

class _CountingDetailGateway implements PlaylistDetailGateway {
  _CountingDetailGateway(this.pages);

  final Map<int, PlaylistTrackPageResult> pages;
  int requestCount = 0;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    requestCount += 1;
    return _ImmediateDetailOp(pages[offset]!);
  }
}

class _ControlledDetailGateway implements PlaylistDetailGateway {
  _ControlledDetailGateway(this.completers);

  final Map<int, Completer<PlaylistTrackPageResult>> completers;
  final List<int> requestedOffsets = [];
  final List<int> cancelledOffsets = [];

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    requestedOffsets.add(offset);
    return _TrackingPendingOp(
      completers[offset]!.future,
      onCancel: () => cancelledOffsets.add(offset),
    );
  }
}

class _CallbackDetailGateway implements PlaylistDetailGateway {
  _CallbackDetailGateway(this._callback);
  final PlaylistTrackPageLoadOperation Function(
    UserPlaylistSummary playlist,
    int offset,
    int size,
  )
  _callback;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) => _callback(playlist, offset, size);
}

class _ImmediateDetailOp implements PlaylistTrackPageLoadOperation {
  const _ImmediateDetailOp(this.result);
  final PlaylistTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async => result;
}

class _TrackingPendingOp implements PlaylistTrackPageLoadOperation {
  _TrackingPendingOp(this.future, {required this.onCancel});

  final Future<PlaylistTrackPageResult> future;
  final VoidCallback onCancel;

  @override
  bool cancel() {
    onCancel();
    return true;
  }

  @override
  Future<PlaylistTrackPageResult> run() => future;
}

class _NonCooperativeOperation implements PlaylistTrackPageLoadOperation {
  _NonCooperativeOperation(this.future);
  final Future<PlaylistTrackPageResult> future;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() => future;
}

class _StaticTrackLikeGateway implements TrackLikeGateway {
  const _StaticTrackLikeGateway(this.result);
  final TrackLikeMutationResult result;

  @override
  TrackLikeMutationOperation beginMutation({
    required String providerId,
    required String opaqueTrackId,
    required TrackLikeState desiredState,
  }) => _StaticTrackLikeOp(result);
}

class _StaticTrackLikeOp implements TrackLikeMutationOperation {
  const _StaticTrackLikeOp(this.result);
  final TrackLikeMutationResult result;

  @override
  bool cancel() => true;

  @override
  Future<TrackLikeMutationResult> run() async => result;
}

class _UnusedFavoriteAlbumGateway implements FavoriteAlbumGateway {
  const _UnusedFavoriteAlbumGateway();

  @override
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => const _EmptyAlbumOp();
}

class _EmptyAlbumOp implements FavoriteAlbumPageLoadOperation {
  const _EmptyAlbumOp();

  @override
  bool cancel() => true;

  @override
  Future<FavoriteAlbumPageResult> run() async =>
      const FavoriteAlbumPageResult(continuationOffset: 0);
}

class _RecentPlaysFixtureGateway implements RecentPlaysGateway {
  _RecentPlaysFixtureGateway({required this.total, required this.targetIndex});

  final int total;
  final int targetIndex;
  final List<int> requestedOffsets = [];

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    requestedOffsets.add(offset);
    final end = (offset + size).clamp(0, total);
    return _ImmediateDetailOp(
      PlaylistTrackPageResult(
        offset: offset,
        nextOffset: end,
        total: total,
        hasMore: end < total,
        tracks: [
          for (var i = offset; i < end; i++)
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'recent:$i',
              title: i == targetIndex ? 'Nevada' : 'Recent Track $i',
              artistNames: [i == targetIndex ? 'Vicetone' : 'Artist $i'],
            ),
        ],
      ),
    );
  }
}

class _InMemoryQueueGateway
    implements PlaybackQueueGateway, PlaybackQueueBatchGateway {
  List<PlaylistTrackSummary> _tracks = const [];
  int? _current;
  PlaybackOrder _order = PlaybackOrder.sequential;
  PlaybackRepeatMode _repeat = PlaybackRepeatMode.off;

  PlaybackQueueResult _ok({bool changed = false}) => PlaybackQueueResult(
    snapshot: PlaybackQueueSnapshot(
      tracks: List.unmodifiable(_tracks),
      currentIndex: _current,
      hasPrevious: _current != null && _current! > 0,
      hasNext: _current != null && _current! + 1 < _tracks.length,
      order: _order,
      repeatMode: _repeat,
    ),
    playbackRequested: changed,
  );

  @override
  PlaybackQueueResult snapshot() => _ok();

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    int? currentIndex,
  }) {
    _tracks = List.of(tracks);
    _current = currentIndex;
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) {
    _tracks = [..._tracks, track];
    final changed = _current == null;
    _current ??= 0;
    return _ok(changed: changed);
  }

  @override
  PlaybackQueueResult extend(List<PlaylistTrackSummary> tracks) {
    _tracks = [..._tracks, ...tracks];
    return _ok();
  }

  @override
  PlaybackQueueResult extendAndAdvanceFromTerminal(
    List<PlaylistTrackSummary> tracks,
  ) {
    final next = _tracks.length;
    _tracks = [..._tracks, ...tracks];
    _current = next;
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult select(int index) {
    _current = index;
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult advance() {
    if (_current != null && _current! + 1 < _tracks.length) {
      _current = _current! + 1;
      return _ok(changed: true);
    }
    return _ok();
  }

  @override
  PlaybackQueueResult rewind() {
    if (_current != null && _current! > 0) {
      _current = _current! - 1;
      return _ok(changed: true);
    }
    return _ok();
  }

  @override
  PlaybackQueueResult completeCurrent() => advance();

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) {
    _order = order;
    return _ok();
  }

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) {
    _repeat = repeatMode;
    return _ok();
  }

  @override
  PlaybackQueueResult remove(int index) {
    final list = List<PlaylistTrackSummary>.of(_tracks)..removeAt(index);
    _tracks = list;
    _current = list.isEmpty ? null : 0;
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult clear() {
    _tracks = const [];
    _current = null;
    return _ok(changed: true);
  }
}

class _NoopMediaGateway implements MediaResolutionGateway {
  const _NoopMediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => const _NoopMediaOp();
}

class _NoopMediaOp implements MediaResolutionOperation {
  const _NoopMediaOp();

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async =>
      const MediaResolutionResult(failure: MediaResolutionFailure.unavailable);
}

class _NoopAudioEngine implements ForegroundAudioEngine {
  const _NoopAudioEngine();

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) async => _NoopAudioSession();

  @override
  Future<void> dispose() async {}
}

class _NoopAudioSession implements ForegroundAudioSession {
  final _states = StreamController<ForegroundAudioState>.broadcast();
  final _failures = StreamController<ForegroundAudioFailure>.broadcast();
  final _positions = StreamController<int>.broadcast();

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekToMs(int positionMs) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _states.close();
    await _failures.close();
    await _positions.close();
  }
}
