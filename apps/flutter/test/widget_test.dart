import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui'
    show Clip, Locale, PointerDeviceKind, Rect, SemanticsAction, Size, Tristate;

import 'package:dynamic_color/dynamic_color.dart' show DynamicColorPlugin;
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, ValueKey;
import 'package:flutter/gestures.dart' show PointerHoverEvent, kSecondaryButton;
import 'package:flutter/material.dart'
    show
        AnimatedSwitcher,
        AppBar,
        AppLifecycleState,
        Brightness,
        BuildContext,
        Color,
        ColorScheme,
        Colors,
        CircularProgressIndicator,
        CustomScrollView,
        Divider,
        EdgeInsets,
        FadeTransition,
        FilledButton,
        Focus,
        FocusManager,
        FontWeight,
        GlobalKey,
        GridView,
        IconButton,
        InkWell,
        LinearProgressIndicator,
        ListTile,
        Material,
        MaterialApp,
        NavigationBar,
        NavigationDestination,
        NavigationRail,
        NavigationRailLabelType,
        OutlinedButton,
        Opacity,
        PageStorageKey,
        PinnedHeaderSliver,
        RadioListTile,
        SafeArea,
        Scaffold,
        Scrollable,
        ScrollableState,
        SearchBar,
        SegmentedButton,
        Semantics,
        SingleChildScrollView,
        SizedBox,
        State,
        StatefulWidget,
        TabBar,
        TabIndicatorAnimation,
        Text,
        TextButton,
        TextField,
        TextInputAction,
        Theme,
        ThemeData,
        Widget,
        kToolbarHeight;
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/album/album_page.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/authenticated_dependencies.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/authentication/netease_official_web_login.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/home/daily_recommendation_gateway.dart';
import 'package:flutterustmusic/home/recent_listening_gateway.dart';
import 'package:flutterustmusic/home/home_controller.dart';
import 'package:flutterustmusic/home/home_page.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/new_song_controller.dart';
import 'package:flutterustmusic/discover/radar_controller.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_track_gateway.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/recent_plays_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_page.dart';
import 'package:flutterustmusic/l10n/app_locale.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_page.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/settings/settings_page.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

final AppLocalizations _en = lookupAppLocalizations(englishAppLocale);
final AppLocalizations _zh = lookupAppLocalizations(simplifiedChineseAppLocale);

Future<void> _selectAdaptiveSection(
  WidgetTester tester, {
  required String control,
  required String item,
}) async {
  final itemFinder = find.byKey(ValueKey(item));
  if (itemFinder.evaluate().isEmpty) {
    await tester.tap(find.byKey(ValueKey(control)));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(itemFinder);
  await tester.tap(itemFinder);
  await tester.pumpAndSettle();
}

Future<void> _openLibrary(WidgetTester tester) async {
  final sidebarLiked = find.byKey(const ValueKey('open-liked-songs'));
  await tester.tap(
    sidebarLiked.evaluate().isNotEmpty
        ? sidebarLiked
        : find.byKey(const ValueKey('primary-library-destination')),
  );
  await tester.pumpAndSettle();
}

Future<void> _openPlaylists(WidgetTester tester) async {
  await _openLibrary(tester);
  await _selectLibrarySection(tester, 'playlists');
}

Future<void> _openSignInDialog(WidgetTester tester) async {
  final sidebarAccount = find.byKey(const ValueKey('sidebar-account'));
  if (sidebarAccount.evaluate().isNotEmpty) {
    await tester.tap(sidebarAccount);
  } else {
    await tester.tap(find.byKey(const ValueKey('sign-in')).first);
  }
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('authentication-dialog')), findsOneWidget);
}

Future<void> _selectLibrarySection(WidgetTester tester, String section) async {
  final likedTab = find.byKey(
    ValueKey(switch (section) {
      'liked-songs' => 'liked-tab-songs',
      'playlists' => 'liked-tab-playlists',
      'albums' => 'liked-tab-albums',
      _ => 'liked-tab-unavailable',
    }),
  );
  if (likedTab.evaluate().isNotEmpty) {
    if (likedTab.hitTestable().evaluate().isEmpty) {
      final tabScroll = find.descendant(
        of: find.byKey(const ValueKey('liked-songs-tabs')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(likedTab, 80, scrollable: tabScroll);
    }
    await tester.tap(likedTab);
    if (section == 'albums') {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
    return;
  }
  final control = find.byKey(const ValueKey('library-section-selector'));
  final itemFinder = find.byKey(ValueKey('library-section-$section'));
  if (tester.widget(control) is OutlinedButton) {
    await tester.tap(control);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.ensureVisible(itemFinder);
  await tester.tap(itemFinder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  testWidgets(
    'recent plays retains transient refresh data and clears rejected account data',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = _ScriptedRecentPlaysGateway([
        PlaylistTrackPageResult(
          total: 1,
          totalIsExact: false,
          tracks: [_SyntheticRecentPlaysGateway.trackAt(0)],
        ),
        const PlaylistTrackPageResult(failure: UserLibraryFailure.network),
        const PlaylistTrackPageResult(
          failure: UserLibraryFailure.credentialRejected,
        ),
      ]);
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          recentPlaysGateway: source,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-recent-plays')));
      await tester.pumpAndSettle();
      expect(find.text('Evening Shore'), findsOneWidget);
      expect(find.text(_en.recentSongsTabApproximate(1)), findsOneWidget);
      expect(
        find.text(
          _en.recentProcessedStatus(_en.recentLoadedAction, '', '', 1, ''),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('recent-plays-refresh')));
      await tester.pumpAndSettle();
      expect(find.text(_en.recentRefreshSnapshotFailure), findsOneWidget);
      expect(find.text('Evening Shore'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('recent-plays-refresh')));
      await tester.pumpAndSettle();
      expect(find.text(_en.recentSignInTitle), findsOneWidget);
      expect(find.text('Evening Shore'), findsNothing);
      expect(find.text(_en.recentSongsTab(1)), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recent plays stays unavailable without a cloud adapter at every size',
    (tester) async {
      await _loadRecentReviewFonts(tester);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-recent-plays')));
      await tester.pumpAndSettle();
      for (final width in [1440.0, 900.0, 390.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpAndSettle();
        expect(find.text(_en.recentUnavailableTitle), findsOneWidget);
        expect(find.text(_en.recentEmptyTitle), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('recent-plays-play')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('recent-plays-refresh')),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.byKey(const ValueKey('recent-plays-track-0')),
          findsNothing,
        );
        if (const bool.fromEnvironment('RECENT_PLAYS_VISUAL_REVIEW')) {
          await expectLater(
            find.byType(MusicApp),
            matchesGoldenFile(
              Uri.file('/tmp/fura-recent-plays-unavailable-$width.png'),
            ),
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('primary-home-destination')));
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
    },
  );

  testWidgets(
    'recent plays shares paging search and retained navigation with a synthetic source',
    (tester) async {
      const capture = bool.fromEnvironment('RECENT_PLAYS_VISUAL_REVIEW');
      await _loadRecentReviewFonts(tester);
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = _SyntheticRecentPlaysGateway();
      final queue = _WidgetPlaybackQueueGateway()
        ..replace(
          tracks: [_SyntheticRecentPlaysGateway.trackAt(0)],
          currentIndex: 0,
        );
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          recentPlaysGateway: source,
          accountSummaryGateway: const _WidgetAccountSummaryGateway(
            AccountSummaryLoadResult(
              summary: AuthenticatedAccountSummary(
                displayName: 'Review listener',
              ),
            ),
          ),
          playbackQueueGateway: queue,
          mediaResolutionGateway: const _UnavailableMediaGateway(),
          lyricGateway: const _WidgetLyricGateway(),
          initialSettings: const AppSettings(theme: AppThemePreference.light),
        ),
      );
      await tester.pumpAndSettle();
      expect(source.offsets, isEmpty);
      await tester.tap(find.byKey(const ValueKey('open-recent-plays')));
      await tester.pumpAndSettle();
      expect(source.offsets, [0]);
      expect(find.text(_en.recentSongsTab(250)), findsOneWidget);
      expect(find.text(_en.likedPlayAll), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('recent-plays-track-0')),
          matching: find.text('Evening Shore'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('recent-plays-track-80')), findsNothing);
      if (capture) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(Uri.file('/tmp/fura-recent-plays-desktop.png')),
        );
      }
      await tester.tap(
        find.byKey(const ValueKey('recent-plays-track-1')),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.recentAddToQueue));
      await tester.pumpAndSettle();
      expect(queue.snapshot().snapshot!.tracks.last.title, 'Mercury');
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (capture) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(Uri.file('/tmp/fura-recent-plays-mobile.png')),
        );
      }
      tester.view.physicalSize = const Size(1440, 960);
      await tester.pumpAndSettle();
      final recentScroll = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('recent-plays-tracks')),
          )
          .controller!;
      final collapsedTitle = find.byKey(
        const ValueKey('recent-plays-collapsed-title'),
      );
      final topSearch = find.byKey(const ValueKey('top-search-shortcut'));
      final desktopShellTop = tester.getTopLeft(find.byType(AppBar)).dy;
      recentScroll.jumpTo(180);
      await tester.pumpAndSettle();
      expect(collapsedTitle, findsOneWidget);
      expect(
        find.byKey(const ValueKey('recent-plays-collapsed-header')),
        findsOneWidget,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(topSearch, findsNothing);
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('recent-plays-collapsed-header')),
            )
            .dy,
        closeTo(desktopShellTop, 1),
      );
      final recentPlayRect = tester.getRect(
        find.byKey(const ValueKey('recent-plays-play')),
      );
      final recentRefreshRect = tester.getRect(
        find.byKey(const ValueKey('recent-plays-refresh')),
      );
      expect(recentRefreshRect.left - recentPlayRect.right, closeTo(8, 1));
      await tester.drag(
        find.byKey(const PageStorageKey('recent-plays-tracks')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
      expect(collapsedTitle, findsNothing);
      expect(topSearch, findsOneWidget);
      await tester.tap(topSearch);
      await tester.pumpAndSettle();
      final searchFocus = FocusManager.instance.primaryFocus;
      recentScroll.jumpTo(260);
      await tester.pumpAndSettle();
      expect(collapsedTitle, findsNothing);
      expect(FocusManager.instance.primaryFocus, same(searchFocus));
      searchFocus!.unfocus();
      await tester.pumpAndSettle();
      expect(collapsedTitle, findsOneWidget);
      expect(topSearch, findsNothing);
      expect(recentScroll.offset, 260);
      expect(tester.getTopLeft(collapsedTitle).dy, lessThan(kToolbarHeight));
      expect(
        find.byKey(const ValueKey('recent-plays-search')).hitTestable(),
        findsOneWidget,
      );
      if (capture) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-recent-plays-desktop-collapsed.png'),
          ),
        );
      }
      tester.view.physicalSize = const Size(900, 844);
      await tester.pumpAndSettle();
      tester.binding.handlePointerEvent(
        const PointerHoverEvent(position: Offset.zero),
      );
      await tester.pumpAndSettle();
      expect(collapsedTitle, findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(tester.takeException(), isNull);
      if (capture) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-recent-plays-medium-collapsed.png'),
          ),
        );
      }
      tester.view.physicalSize = const Size(1440, 960);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('primary-home-destination')));
      await tester.pumpAndSettle();
      expect(collapsedTitle, findsNothing);
      await tester.tap(find.byKey(const ValueKey('open-recent-plays')));
      await tester.pumpAndSettle();
      expect(collapsedTitle, findsOneWidget);
      expect(recentScroll.offset, 260);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(collapsedTitle, findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(
        find.byKey(ValueKey('shell-top-bar-title-${_en.navRecentPlays}')),
        findsOneWidget,
      );
      final settingsRect = tester.getRect(
        find.byKey(const ValueKey('open-settings')),
      );
      final signOutRect = tester.getRect(
        find.byKey(const ValueKey('sign-out')),
      );
      expect(settingsRect.right, closeTo(signOutRect.left, 1));
      expect(signOutRect.right, greaterThan(380));
      expect(
        settingsRect.center.dy,
        closeTo(tester.getRect(find.byType(AppBar)).center.dy, 1),
      );
      final mobileRecentPlayRect = tester.getRect(
        find.byKey(const ValueKey('recent-plays-play')),
      );
      final mobileRecentRefreshRect = tester.getRect(
        find.byKey(const ValueKey('recent-plays-refresh')),
      );
      expect(
        mobileRecentRefreshRect.left - mobileRecentPlayRect.right,
        closeTo(8, 1),
      );
      if (capture) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-recent-plays-mobile-collapsed.png'),
          ),
        );
      }
      await tester.drag(
        find.byKey(const PageStorageKey('recent-plays-tracks')),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      expect(collapsedTitle, findsNothing);
      tester.view.physicalSize = const Size(1440, 960);
      await tester.pumpAndSettle();
      expect(topSearch, findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('recent-plays-search')),
        'Hidden Horizon',
      );
      await tester.pumpAndSettle();
      expect(source.offsets, [0, 100, 200]);
      expect(find.text(_en.recentPlayFiltered(1)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('recent-plays-track-0')),
          matching: find.text('Hidden Horizon'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          _en.recentProcessedStatus(
            _en.recentSearchedAction,
            '',
            '',
            250,
            _en.recentTotalPart(250),
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('recent-plays-track-0')));
      await tester.pumpAndSettle();
      expect(queue.snapshot().snapshot?.current?.title, 'Hidden Horizon');
      await tester.tap(find.byKey(const ValueKey('primary-home-destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-recent-plays')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('recent-plays-search')),
            )
            .controller!
            .text,
        'Hidden Horizon',
      );
      expect(source.offsets, [0, 100, 200]);
      await tester.tap(find.byKey(const ValueKey('recent-plays-refresh')));
      await tester.pumpAndSettle();
      expect(source.offsets, [0, 100, 200, 0, 100, 200]);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('recent-plays-track-0')),
          matching: find.text('Hidden Horizon'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('sidebar-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-recent-plays')), findsNothing);
      expect(
        find.byKey(const ValueKey('recent-plays-page'), skipOffstage: false),
        findsNothing,
      );
      expect(find.text('MY MUSIC'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recent plays retained collapsed header adapts during a narrow resize',
    (tester) async {
      const capture = bool.fromEnvironment('RECENT_PLAYS_VISUAL_REVIEW');
      await _loadRecentReviewFonts(tester);
      tester.view.physicalSize = const Size(1440, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          recentPlaysGateway: _SyntheticRecentPlaysGateway(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-recent-plays')));
      await tester.pumpAndSettle();

      final scrollFinder = find.byKey(
        const PageStorageKey('recent-plays-tracks'),
      );
      final scroll = tester.widget<CustomScrollView>(scrollFinder).controller!;
      scroll.jumpTo(180);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recent-plays-collapsed-row')),
        findsOneWidget,
      );

      // Start expanding so AnimatedSwitcher retains the desktop collapsed row,
      // then resize before its 240 ms outgoing transition has completed.
      await tester.drag(scrollFinder, const Offset(0, 500));
      await tester.pump();
      tester.view.physicalSize = const Size(520, 844);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('recent-plays-collapsed-column')),
        findsOneWidget,
      );
      if (capture) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-recent-plays-narrow-resize-transition.png'),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recent plays collapse supports dark reduced motion and short windows',
    (tester) async {
      const capture = bool.fromEnvironment('RECENT_PLAYS_VISUAL_REVIEW');
      await _loadRecentReviewFonts(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures.allOn;
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          recentPlaysGateway: _SyntheticRecentPlaysGateway(),
          initialSettings: const AppSettings(theme: AppThemePreference.dark),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-recent-plays')));
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('recent-plays-tracks')),
          )
          .controller!;
      scroll.jumpTo(180);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recent-plays-collapsed-title')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AnimatedSwitcher>(
              find.byKey(const ValueKey('recent-plays-header-transition')),
            )
            .duration,
        Duration.zero,
      );
      expect(scroll.offset, 180);
      if (capture) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-recent-plays-dark-collapsed.png'),
          ),
        );
      }
      // A keyboard / short viewport must let the controls scroll instead of
      // pinning a panel larger than the available song viewport.
      tester.view.physicalSize = const Size(390, 430);
      await tester.pumpAndSettle();
      expect(find.byType(PinnedHeaderSliver), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('recent-plays-search')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recent-plays-search')).hitTestable(),
        findsOneWidget,
      );
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recent-plays-collapsed-title')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home refresh and rotation run only while visible and foreground',
    (tester) async {
      final public = _WidgetRecommendedPlaylistGateway(
        const RecommendedPlaylistPageResult(
          playlists: [
            RecommendedPlaylistSummary(
              providerId: 'qq-music',
              opaqueId: 'catalog:1',
              title: 'Public one',
            ),
            RecommendedPlaylistSummary(
              providerId: 'qq-music',
              opaqueId: 'catalog:2',
              title: 'Public two',
            ),
          ],
        ),
      );
      final recommendations = RecommendedPlaylistController(public);
      final home = HomeController(
        const _WidgetAccountSummaryGateway(AccountSummaryLoadResult()),
        const _WidgetDailyRecommendationGateway(DailyRecommendationResult()),
        const _WidgetPersonalizedPlaylistsGateway(
          PersonalizedPlaylistsResult(),
        ),
        const _WidgetPersonalizedTracksGateway(PersonalizedTracksResult()),
        _WidgetRelatedTracksGateway(const RelatedTracksResult()),
      );
      final songs = NewSongController(
        _WidgetNewSongGateway({
          NewSongCategory.latest: const NewSongResult(
            category: NewSongCategory.latest,
          ),
        }),
      );
      final radar = RadarController(
        _WidgetRadarGateway(const RadarTrackPageResult(page: 1)),
      );
      final engine = ForegroundPlaybackController(
        AudioplayersForegroundAudioEngine(),
      );
      final playback = TrackPlaybackController(
        const _UnavailableMediaGateway(),
        engine,
      );
      final queue = QueuePlaybackController(
        _WidgetPlaybackQueueGateway(),
        playback,
      );
      addTearDown(() {
        queue.dispose();
        radar.dispose();
        songs.dispose();
        recommendations.dispose();
        home.dispose();
      });
      await recommendations.load();
      await songs.load();
      var now = DateTime(2026, 9, 8);
      Future<void> show(bool active) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomePage(
                homeController: home,
                recommendationController: recommendations,
                newSongController: songs,
                radarController: radar,
                queuePlaybackController: queue,
                authenticated: false,
                active: active,
                now: () => now,
                onOpenDiscover: () {},
                onOpenLibrary: () {},
                onOpenRecommendation: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      String title() => tester
          .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
          .data!;
      await show(true);
      final first = title();
      await show(false);
      now = now.add(const Duration(minutes: 20));
      await tester.pump(const Duration(minutes: 20));
      expect(public.requests, hasLength(1));
      expect(title(), first);
      await show(true);
      expect(public.requests, hasLength(2));
      final refresh = find.byKey(
        const ValueKey('home-refresh-recommendations'),
      );
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(public.requests, hasLength(3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 20));
      await tester.pump(const Duration(minutes: 20));
      expect(public.requests, hasLength(3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(public.requests, hasLength(4));
      await show(true);
      expect(public.requests, hasLength(4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Home playlist refresh remains stable and only reloads its owned shelf',
    (tester) async {
      const initialPlaylists = PersonalizedPlaylistsResult(
        playlists: [
          RecommendedPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'owned:home:1',
            title: 'Initial Home shelf',
          ),
        ],
      );
      const refreshedPlaylists = PersonalizedPlaylistsResult(
        playlists: [
          RecommendedPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'owned:home:2',
            title: 'Refreshed Home shelf',
          ),
        ],
      );
      final pendingRefresh = Completer<PersonalizedPlaylistsResult>();
      final personalized = _ScriptedWidgetPersonalizedPlaylistsGateway([
        Future.value(initialPlaylists),
        pendingRefresh.future,
      ]);
      final public = _WidgetRecommendedPlaylistGateway(
        const RecommendedPlaylistPageResult(
          playlists: [
            RecommendedPlaylistSummary(
              providerId: 'qq-music',
              opaqueId: 'catalog:home:1',
              title: 'Unrelated public shelf',
            ),
          ],
        ),
      );
      final songsGateway = _WidgetNewSongGateway({
        NewSongCategory.latest: const NewSongResult(
          category: NewSongCategory.latest,
        ),
      });
      final home = HomeController(
        const _WidgetAccountSummaryGateway(AccountSummaryLoadResult()),
        const _WidgetDailyRecommendationGateway(DailyRecommendationResult()),
        personalized,
        const _WidgetPersonalizedTracksGateway(PersonalizedTracksResult()),
        _WidgetRelatedTracksGateway(const RelatedTracksResult()),
      );
      final recommendations = RecommendedPlaylistController(public);
      final songs = NewSongController(songsGateway);
      final radar = RadarController(
        _WidgetRadarGateway(const RadarTrackPageResult(page: 1)),
      );
      final playback = TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(AudioplayersForegroundAudioEngine()),
      );
      final queue = QueuePlaybackController(
        _WidgetPlaybackQueueGateway(),
        playback,
      );
      addTearDown(() {
        queue.dispose();
        radar.dispose();
        songs.dispose();
        recommendations.dispose();
        home.dispose();
      });
      await Future.wait([home.load(), recommendations.load(), songs.load()]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(
              homeController: home,
              recommendationController: recommendations,
              newSongController: songs,
              radarController: radar,
              radarEnabled: false,
              queuePlaybackController: queue,
              authenticated: true,
              onOpenDiscover: () {},
              onOpenLibrary: () {},
              onOpenRecommendation: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Initial Home shelf'), findsWidgets);
      expect(personalized.requests, 1);
      expect(public.requests, [(0, 20)]);
      expect(songsGateway.requests, [NewSongCategory.latest]);

      final refresh = find.byKey(
        const ValueKey('home-refresh-recommendations'),
      );
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pump();

      expect(refresh, findsOneWidget);
      expect(tester.widget<TextButton>(refresh).onPressed, isNull);
      expect(
        find.descendant(
          of: refresh,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text(_en.homeRefreshing), findsOneWidget);
      expect(personalized.requests, 2);
      expect(public.requests, [(0, 20)]);
      expect(songsGateway.requests, [NewSongCategory.latest]);

      pendingRefresh.complete(refreshedPlaylists);
      await tester.pumpAndSettle();
      expect(find.text('Refreshed Home shelf'), findsWidgets);
      expect(tester.widget<TextButton>(refresh).onPressed, isNotNull);
      expect(find.text(_en.homeRefreshing), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('keeps the main shell visible while sign-in uses a dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const bootstrap = BootstrapStatus(
      coreVersion: '0.1.0-test',
      providers: [
        ProviderStatus(
          id: 'qq-music',
          displayName: 'QQ Music',
          implementedCapabilities: ['Authentication'],
        ),
      ],
      defaultProviderId: 'qq-music',
    );

    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: bootstrap,
        authenticationGateway: _WidgetGateway(session),
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          const RecommendedPlaylistPageResult(
            playlists: [
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:signed-out-hero',
                title: 'Public listening pick',
                trackCount: 24,
              ),
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:signed-out-popular',
                title: 'Million-play favorites',
                trackCount: 80,
              ),
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:signed-out-shelf',
                title: 'Open-air playlist',
                trackCount: 36,
              ),
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:signed-out-more',
                title: 'Public supporting pick',
                trackCount: 42,
              ),
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:signed-out-shelf-more',
                title: 'Public shelf pick',
                trackCount: 28,
              ),
            ],
          ),
        ),
        newSongGateway: _WidgetNewSongGateway({
          NewSongCategory.latest: const NewSongResult(
            category: NewSongCategory.latest,
            tracks: [
              PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:guest:new-song',
                title: 'Fresh release',
                artistNames: ['Public artist'],
                durationSeconds: 192,
              ),
            ],
          ),
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('signed-out-main-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(find.text('fura music'), findsOneWidget);
    expect(find.text('Sign in to QQ Music'), findsOneWidget);
    expect(find.text('Public listening pick'), findsOneWidget);
    expect(find.text('Public shelf pick'), findsOneWidget);
    expect(find.text('Fresh release'), findsWidgets);
    expect(find.text('Popular playlists'), findsOneWidget);
    expect(find.text('New songs'), findsWidgets);
    expect(
      find.byKey(const ValueKey('home-guest-playlists-shelf')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-daily-sign-in')), findsNothing);
    expect(
      find.byKey(const ValueKey('home-personalized-tracks-sign-in')),
      findsNothing,
    );
    expect(find.text('Scan with WeChat'), findsNothing);

    await _openSignInDialog(tester);
    expect(find.text('Scan with WeChat'), findsOneWidget);

    await tester.tap(find.text('Scan with WeChat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Scan with WeChat'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('close-authentication-dialog')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('authentication-dialog')), findsNothing);
    expect(find.text('Scan with WeChat'), findsNothing);
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(session.cancelCalls, 1);
  });

  testWidgets(
    'signed-out Home renders public playlists and playable new songs',
    (tester) async {
      const captureReviewImages = bool.fromEnvironment(
        'SIGNED_OUT_HOME_VISUAL_REVIEW',
      );
      final publicPlaylists = List.generate(
        8,
        (index) => RecommendedPlaylistSummary(
          providerId: 'qq-music',
          opaqueId: 'catalog:guest:${index + 1}',
          title: [
            'Weekend listening',
            'Million-play favorites',
            'Fresh pop discoveries',
            'Late-night city songs',
            'Acoustic mornings',
            'Electronic focus',
            'Mandopop essentials',
            'Road-trip favorites',
          ][index],
          trackCount: 24 + index * 7,
        ),
      );
      final newSongs = List.generate(
        6,
        (index) => PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:guest:${index + 1}',
          title: [
            'First Light',
            'City Summer',
            'Soft Horizon',
            'Parallel Roads',
            'After the Rain',
            'Moving North',
          ][index],
          artistNames: [
            [
              'Open Coast',
              'River North',
              'Quiet Signals',
              'Aster Field',
              'Blue Lantern',
              'Night Avenue',
            ][index],
          ],
          durationSeconds: 176 + index * 9,
        ),
      );

      Future<_WidgetPlaybackQueueGateway> pumpFixture(Size size) async {
        final queue = _WidgetPlaybackQueueGateway();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MusicApp(
            bootstrap: _bootstrap,
            authenticationGateway: _WidgetGateway(_WaitingSession()),
            recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
              RecommendedPlaylistPageResult(playlists: publicPlaylists),
            ),
            newSongGateway: _WidgetNewSongGateway({
              NewSongCategory.latest: NewSongResult(
                category: NewSongCategory.latest,
                tracks: newSongs,
              ),
            }),
            playbackQueueGateway: queue,
            mediaResolutionGateway: const _UnavailableMediaGateway(),
            lyricGateway: const _WidgetLyricGateway(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Popular playlist'), findsOneWidget);
        expect(find.text('Acoustic mornings'), findsOneWidget);
        expect(find.text('Popular playlists'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('home-guest-playlists-shelf')),
          findsOneWidget,
        );
        expect(find.text('New songs'), findsWidgets);
        expect(
          find.byKey(const ValueKey('home-guest-new-songs')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('home-daily-sign-in')), findsNothing);
        expect(find.text('Daily recommendation'), findsNothing);
        expect(find.text('Radar'), findsNothing);
        expect(find.text('Your playlist treasures'), findsNothing);
        expect(find.text('Songs picked for you'), findsNothing);
        expect(
          find.byKey(const ValueKey('home-personalized-tracks-sign-in')),
          findsNothing,
        );
        expect(
          (tester
                      .widget<SingleChildScrollView>(
                        find.byKey(const PageStorageKey('home-scroll')),
                      )
                      .padding
                  as EdgeInsets)
              .bottom,
          24,
        );
        expect(tester.takeException(), isNull);
        return queue;
      }

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final desktopQueue = await pumpFixture(const Size(1440, 960));
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-home-guest-desktop.png'),
          ),
        );
      }
      await tester.ensureVisible(
        find.byKey(const ValueKey('home-guest-new-song-1')),
      );
      await tester.tap(find.byKey(const ValueKey('home-guest-new-song-1')));
      await tester.pump();
      expect(desktopQueue.replacements.single.$1, newSongs);
      expect(desktopQueue.replacements.single.$2, 0);

      await pumpFixture(const Size(390, 844));
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-home-guest-mobile.png'),
          ),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uses a scrollable single-column layout on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: const BootstrapStatus(
          coreVersion: '0.1.0-test',
          providers: [
            ProviderStatus(
              id: 'qq-music',
              displayName: 'QQ Music',
              implementedCapabilities: ['Authentication'],
            ),
          ],
          defaultProviderId: 'qq-music',
        ),
        authenticationGateway: _WidgetGateway(session),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(find.text('Scan with WeChat'), findsNothing);
    await _openSignInDialog(tester);
    expect(find.text('Scan with WeChat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers only QQ and WeChat QR authorization', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(_WaitingSession()),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
      ),
    );
    await tester.pumpAndSettle();
    await _openSignInDialog(tester);

    expect(find.text('Scan with QQ'), findsOneWidget);
    expect(find.text('Scan with WeChat'), findsOneWidget);
    expect(find.textContaining('SMS'), findsNothing);
    expect(find.byKey(const ValueKey('phone-number-field')), findsNothing);
    expect(
      find.byKey(const ValueKey('phone-verification-code-field')),
      findsNothing,
    );
  });

  testWidgets('offers desktop QQ account quick authorization beside QR login', (
    tester,
  ) async {
    const captureReviewImage = bool.fromEnvironment(
      'DESKTOP_QUICK_LOGIN_VISUAL_REVIEW',
    );
    await _loadRecentReviewFonts(tester, enabled: captureReviewImage);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final quickSession = _WidgetDesktopQuickLoginSession();
    final authenticationGateway = _WidgetGateway(
      _WaitingSession(),
      desktopQuickStart: DesktopQuickLoginStart(
        session: quickSession,
        accounts: const [
          DesktopQuickLoginAccount(
            selectionId: 0,
            displayName: 'Synthetic QQ account',
            accountHint: '21••••90',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: authenticationGateway,
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        desktopQuickLoginEnabled: true,
      ),
    );
    await tester.pumpAndSettle();
    await _openSignInDialog(tester);

    expect(find.text('Scan with QQ'), findsOneWidget);
    expect(find.text('Scan with WeChat'), findsOneWidget);
    expect(find.text('Quick login'), findsNothing);
    expect(authenticationGateway.desktopQuickStartCalls, 0);

    await tester.tap(find.text('Scan with QQ'));
    await tester.pumpAndSettle();
    expect(authenticationGateway.desktopQuickStartCalls, 1);

    expect(find.text('Quick login'), findsOneWidget);
    expect(find.text('Synthetic QQ account'), findsOneWidget);
    expect(find.text('21••••90'), findsOneWidget);
    expect(find.text('Scan with QQ'), findsOneWidget);
    expect(find.text('QQ login'), findsOneWidget);
    expect(find.text('WeChat login'), findsOneWidget);
    final quickMethod = tester.getRect(
      find.byKey(const ValueKey('desktop-quick-login-method')),
    );
    final qrMethod = tester.getRect(
      find.byKey(const ValueKey('qr-login-method')),
    );
    expect(quickMethod.right, lessThan(qrMethod.left));
    expect(quickMethod.top, qrMethod.top);
    if (captureReviewImage) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(Uri.file('/tmp/fura-desktop-qq-quick-login.png')),
      );
    }

    await tester.tap(find.byKey(const ValueKey('desktop-quick-account-0')));
    await tester.pumpAndSettle();

    expect(quickSession.selections, [0]);
    expect(find.byKey(const ValueKey('authentication-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('user-library-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'signed-out navigation hides personal music at every breakpoint',
    (tester) async {
      await _loadRecentReviewFonts(tester);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = _WidgetLibraryGateway([]);
      for (final width in [390.0, 900.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          MusicApp(
            key: ValueKey('guest-navigation-$width'),
            bootstrap: _bootstrap,
            authenticationGateway: _WidgetGateway(_WaitingSession()),
            libraryGateway: library,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('MY MUSIC'), findsNothing);
        expect(find.text('YOUR PLAYLISTS'), findsNothing);
        expect(find.byKey(const ValueKey('open-liked-songs')), findsNothing);
        expect(
          find.byKey(const ValueKey('primary-library-destination')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('signed-out-library')), findsNothing);
        expect(library._next, 0);
        expect(
          find.byKey(const ValueKey('authenticated-primary-shell')),
          findsOneWidget,
        );
        if (const bool.fromEnvironment('RECENT_PLAYS_VISUAL_REVIEW')) {
          await expectLater(
            find.byType(MusicApp),
            matchesGoldenFile(
              Uri.file('/tmp/fura-guest-navigation-$width.png'),
            ),
          );
        }
        await tester.tap(find.byKey(const ValueKey('open-track-search')));
        await tester.pumpAndSettle();
        expect(find.byType(TrackSearchPage), findsOneWidget);
        await _openSignInDialog(tester);
        expect(
          find.byKey(const ValueKey('authentication-dialog')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('applies the dark Material foundation to auth and Liked', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        key: const ValueKey('dark-auth-app'),
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(_WaitingSession()),
      ),
    );

    await _openSignInDialog(tester);
    final authTheme = Theme.of(tester.element(find.text('Scan with WeChat')));
    expect(authTheme.brightness, Brightness.dark);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MusicApp(
        key: const ValueKey('dark-library-app'),
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            playlists: [
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'owned:7001:201',
                title: 'Synthetic favorites',
                trackCount: 42,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    await _openLibrary(tester);

    expect(find.text(_en.likedPlaylistUnavailableTitle), findsOneWidget);
    expect(find.text('Library'), findsNothing);
    expect(
      Theme.of(tester.element(find.text(_en.likedPlaylistUnavailableTitle)))
          .brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not present an unverified restored session as signed in', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final session = _WaitingSession();
    final verification = _PendingWidgetVerification();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          session,
          verificationOperation: verification,
        ),
        initialCredentialRestore: CredentialRestoreResult.verificationRequired,
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('authentication-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('signed-out-main-page')), findsOneWidget);
    expect(find.text('You’re signed in'), findsNothing);

    verification.complete(CredentialVerificationResult.network);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('authentication-dialog')), findsNothing);

    await _openSignInDialog(tester);
    expect(find.text('Couldn’t reach QQ Music'), findsOneWidget);
    expect(find.text('Try verification again'), findsOneWidget);
    expect(find.text('You’re signed in'), findsNothing);
    final failureSemantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Couldn’t reach QQ Music')),
    );
    expect(failureSemantics.label, contains('Couldn’t reach QQ Music'));
    expect(failureSemantics.flagsCollection.isLiveRegion, isTrue);
    expect(
      failureSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('announces a terminal QR sign-in failure', (tester) async {
    final semantics = tester.ensureSemantics();
    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(session),
      ),
    );

    await _openSignInDialog(tester);
    await tester.tap(find.text('Scan with WeChat'));
    await tester.pump();
    session.complete(
      const LoginUpdate(
        failure: LoginFailure.serviceUnavailable,
        sessionActive: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('QQ Music is unavailable'), findsOneWidget);
    expect(find.text('Choose a sign-in method'), findsOneWidget);
    final failureSemantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('QQ Music is unavailable')),
    );
    expect(failureSemantics.label, contains('QQ Music is unavailable'));
    expect(failureSemantics.flagsCollection.isLiveRegion, isTrue);
    expect(
      failureSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('announces QR scan progress without merging controls', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(session),
      ),
    );

    await _openSignInDialog(tester);
    await tester.tap(find.text('Scan with WeChat'));
    await tester.pumpAndSettle();
    session.complete(
      const LoginUpdate(
        progress: LoginProgress.scannedAwaitingConfirmation,
        sessionActive: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm on your phone'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('New code'), findsOneWidget);
    final progressSemantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Confirm on your phone')),
    );
    expect(progressSemantics.label, contains('Confirm on your phone'));
    expect(progressSemantics.flagsCollection.isLiveRegion, isTrue);
    expect(
      progressSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('shows an explicitly rejected restored session', (tester) async {
    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          session,
          verificationOperation: const _ImmediateWidgetVerification(
            CredentialVerificationResult.rejected,
          ),
        ),
        initialCredentialRestore: CredentialRestoreResult.verificationRequired,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('authentication-dialog')), findsNothing);
    await _openSignInDialog(tester);
    expect(find.text('Saved session was rejected'), findsOneWidget);
    expect(find.text('Try verification again'), findsNothing);
    expect(find.text('Sign in again'), findsOneWidget);
  });

  testWidgets('presents a locally expired stored session separately', (
    tester,
  ) async {
    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(session),
        initialCredentialRestore: CredentialRestoreResult.locallyExpired,
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('authentication-dialog')), findsNothing);
    await _openSignInDialog(tester);
    expect(find.text('Saved session expired'), findsOneWidget);
    expect(find.text('Sign in again'), findsOneWidget);
    expect(find.text('This code expired'), findsNothing);
  });

  testWidgets('routes an authenticated account through Home into Liked', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            playlists: [
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'owned:7001:201',
                title: 'Synthetic favorites',
                trackCount: 42,
                isLikedSongs: true,
                ownership: UserPlaylistOwnership.owned,
              ),
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'favorite:8001',
                title: 'Synthetic saved mix',
              ),
            ],
          ),
        ]),
        accountSummaryGateway: const _WidgetAccountSummaryGateway(
          AccountSummaryLoadResult(
            summary: AuthenticatedAccountSummary(
              displayName: 'Synthetic listener',
            ),
          ),
        ),
        dailyRecommendationGateway: const _WidgetDailyRecommendationGateway(
          DailyRecommendationResult(
            playlist: RecommendedPlaylistSummary(
              providerId: 'qq-music',
              opaqueId: 'daily:30',
              title: 'Synthetic Daily 30',
              trackCount: 30,
            ),
          ),
        ),
        personalizedTracksGateway: const _WidgetPersonalizedTracksGateway(
          PersonalizedTracksResult(
            tracks: [
              PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:41003:0:fixtureMid:-',
                title: 'Synthetic song pick',
                artistNames: ['Synthetic artist'],
                durationSeconds: 202,
              ),
            ],
          ),
        ),
        radarGateway: _WidgetRadarGateway(
          const RadarTrackPageResult(
            page: 1,
            tracks: [
              PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:41004:0:radarMid:-',
                title: 'Synthetic Radar pick',
                artistNames: ['Radar artist'],
                durationSeconds: 196,
              ),
            ],
          ),
        ),
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          const RecommendedPlaylistPageResult(
            playlists: [
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:81001',
                title: 'Synthetic recommendation',
                trackCount: 20,
              ),
            ],
          ),
        ),
        personalizedPlaylistsGateway: _WidgetPersonalizedPlaylistsGateway(
          const PersonalizedPlaylistsResult(
            playlists: [
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'owned:7001:201',
                title: 'Synthetic favorites',
                trackCount: 42,
              ),
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'favorite:8001',
                title: 'Synthetic saved mix',
              ),
            ],
          ),
        ),
        playlistDetailGateway: _WidgetDetailGateway([
          const PlaylistTrackPageResult(total: 42),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-recommendations-section')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-library-section')), findsOneWidget);
    expect(find.text('Synthetic recommendation'), findsOneWidget);
    expect(find.text('For Synthetic listener today'), findsNothing);
    expect(find.text('Synthetic Daily 30'), findsOneWidget);
    expect(find.text('Synthetic Radar pick'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-radar-recommendation')),
      findsOneWidget,
    );
    expect(find.text('Synthetic song pick'), findsOneWidget);
    expect(find.text('Synthetic favorites'), findsWidgets);
    expect(find.byKey(const ValueKey('home-library-shelf')), findsOneWidget);
    final heroRect = tester.getRect(
      find.byKey(const ValueKey('home-recommendation-0')),
    );
    final dailyRect = tester.getRect(
      find.byKey(const ValueKey('home-daily-recommendation')),
    );
    expect(heroRect.height, 280);
    expect(heroRect.width / dailyRect.width, closeTo(2, 0.1));
    expect(
      heroRect.overlaps(
        tester.getRect(find.byKey(const ValueKey('home-spotlight-title'))),
      ),
      isTrue,
    );
    expect(
      dailyRect.overlaps(tester.getRect(find.text('Synthetic Daily 30'))),
      isTrue,
    );
    expect(find.text('Daily recommendation'), findsOneWidget);
    expect(find.text('MADE FOR YOU'), findsNothing);
    expect(find.byKey(const ValueKey('home-daily-heading')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-programs-heading')), findsNothing);
    expect(
      find.byKey(const ValueKey('home-listening-one-heading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-recommended-playlists-heading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-listening-two-heading')),
      findsOneWidget,
    );
    final sectionTops =
        [
              'home-daily-heading',
              'home-library-heading',
              'home-listening-one-heading',
              'home-recommended-playlists-heading',
              'home-listening-two-heading',
            ]
            .map((key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy)
            .toList(growable: false);
    for (var index = 1; index < sectionTops.length; index++) {
      expect(sectionTops[index], greaterThan(sectionTops[index - 1]));
    }
    expect(find.byKey(const ValueKey('home-open-search')), findsNothing);
    expect(find.byKey(const ValueKey('music-sidebar-brand')), findsOneWidget);
    expect(find.byKey(const ValueKey('top-search-shortcut')), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    final sidebar = find.byKey(const ValueKey('desktop-music-sidebar'));
    expect(sidebar, findsOneWidget);
    final railRect = tester.getRect(sidebar);
    final appBarRect = tester.getRect(find.byType(AppBar));
    expect(railRect.top, 0);
    expect(railRect.height, 900);
    expect(appBarRect.left, greaterThanOrEqualTo(railRect.right));
    expect(appBarRect.top, 0);
    expect(find.byKey(const ValueKey('home-open-library')), findsNothing);
    expect(
      find.byKey(const ValueKey('home-refresh-recommendations')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('open-liked-songs')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('liked-songs-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('liked-songs-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('liked-songs-tabs')), findsOneWidget);
    expect(find.text('Library'), findsNothing);
    semantics.dispose();
    expect(find.text('You’re signed in'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps an unavailable Daily slot separate from public picks', (
    tester,
  ) async {
    final queue = _WidgetPlaybackQueueGateway();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        accountSummaryGateway: const _WidgetAccountSummaryGateway(
          AccountSummaryLoadResult(
            summary: AuthenticatedAccountSummary(displayName: 'Listener'),
          ),
        ),
        dailyRecommendationGateway: const _WidgetDailyRecommendationGateway(
          DailyRecommendationResult(),
        ),
        personalizedPlaylistsGateway: const _WidgetPersonalizedPlaylistsGateway(
          PersonalizedPlaylistsResult(
            failure: PersonalizedPlaylistsFailure.invalidResponse,
          ),
        ),
        personalizedTracksGateway: const _WidgetPersonalizedTracksGateway(
          PersonalizedTracksResult(),
        ),
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          const RecommendedPlaylistPageResult(
            playlists: [
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:81001',
                title: 'Public hero pick',
              ),
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:81002',
                title: 'Public secondary pick',
              ),
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:81003',
                title: 'Public tertiary pick',
              ),
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:81004',
                title: 'Public shelf pick',
              ),
            ],
          ),
        ),
        radarGateway: _WidgetRadarGateway(
          const RadarTrackPageResult(
            page: 1,
            tracks: [
              PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:41004:0:radarMid:-',
                title: 'Real Radar slot',
                artistNames: ['Radar artist'],
              ),
            ],
          ),
        ),
        playbackQueueGateway: queue,
        mediaResolutionGateway: const _UnavailableMediaGateway(),
        lyricGateway: const _WidgetLyricGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final heroRect = tester.getRect(
      find.byKey(const ValueKey('home-recommendation-0')),
    );
    final radarRect = tester.getRect(
      find.byKey(const ValueKey('home-radar-recommendation')),
    );
    final dailyStateRect = tester.getRect(
      find.byKey(const ValueKey('home-daily-recommendation-state')),
    );
    final firstPublicTitleRect = tester.getRect(find.text('Public hero pick'));
    expect(heroRect.overlaps(firstPublicTitleRect), isTrue);
    expect(
      radarRect.overlaps(tester.getRect(find.text('Real Radar slot'))),
      isTrue,
    );
    expect(dailyStateRect.overlaps(heroRect), isFalse);
    expect(dailyStateRect.overlaps(radarRect), isFalse);
    expect(find.text('Public shelf pick'), findsOneWidget);
    expect(find.text('Daily recommendation'), findsOneWidget);
    expect(find.text('Daily 30 is unavailable right now.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-daily-recommendation')),
      findsNothing,
    );
    expect(find.text('MADE FOR YOU'), findsNothing);
    expect(
      find.text('Personalized playlist response not recognized'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No account content was recorded.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('home-radar-recommendation')));
    await tester.pumpAndSettle();
    expect(queue.snapshot().snapshot?.current?.title, 'Real Radar slot');
    expect(tester.takeException(), isNull);
  });

  testWidgets('top search suggests in place before opening Track results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const resultTrack = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:top-search:fixture',
      title: 'Top search result',
      artistNames: ['Search artist'],
    );
    final search = _WidgetSearchGateway(
      const TrackSearchPageResult(
        page: 1,
        total: 1,
        items: [TrackSearchItem(track: resultTrack)],
      ),
    );
    const suggestionTrack = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:top-search:suggestion',
      title: 'Direct suggested query',
      artistNames: ['Suggestion artist'],
    );
    final suggestions = _WidgetSearchGateway(
      const TrackSearchPageResult(
        page: 1,
        total: 1,
        items: [TrackSearchItem(track: suggestionTrack)],
      ),
    );

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        searchGateway: search,
        searchSuggestionGateway: suggestions,
      ),
    );
    await tester.pumpAndSettle();

    final topSearch = find.byKey(const ValueKey('top-search-shortcut'));
    expect(topSearch, findsOneWidget);
    await tester.tap(topSearch);
    await tester.pump();
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    await tester.enterText(topSearch, 'direct song');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    expect(suggestions.requests, [('direct song', 1, 8)]);
    expect(
      find.byKey(const ValueKey('top-search-suggestions')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('top-search-suggestion-raw')),
      findsOneWidget,
    );
    expect(find.text('Search “direct song”'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('top-search-suggestions')))
          .width,
      closeTo(tester.getSize(topSearch).width, 1),
    );
    if (const bool.fromEnvironment('SEARCH_VISUAL_REVIEW')) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-home-search-suggestions.png'),
        ),
      );
    }
    await tester.tapAt(const Offset(1100, 850));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('top-search-suggestions')), findsNothing);
    await tester.tap(topSearch);
    await tester.enterText(topSearch, '');
    await tester.enterText(topSearch, 'direct song');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('top-search-suggestions')),
      findsOneWidget,
    );
    final topSearchFocus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(topSearchFocus));
    expect(
      tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('top-search-suggestion-0')),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .selected,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(search.requests, [('Direct suggested query', 1, 30)]);
    expect(find.byKey(const ValueKey('track-search-content')), findsOneWidget);
    expect(find.text('Top search result'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('primary-destination-transition')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('track-search-field')))
          .controller
          ?.text,
      'Direct suggested query',
    );
  });

  testWidgets('canonical synthetic Home review fixture is complete', (
    tester,
  ) async {
    const captureReviewImages = bool.fromEnvironment('HOME_VISUAL_REVIEW');
    const reviewFont = String.fromEnvironment('HOME_REVIEW_FONT');
    const reviewCjkFont = String.fromEnvironment('HOME_REVIEW_CJK_FONT');
    if (captureReviewImages && reviewFont.isNotEmpty) {
      await tester.runAsync(() async {
        final font = FontLoader('Roboto')
          ..addFont(
            File(reviewFont)
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)),
          );
        if (reviewCjkFont.isNotEmpty) {
          font.addFont(
            File(reviewCjkFont)
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)),
          );
        }
        await font.load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
    }
    final publicPlaylists = List.generate(
      10,
      (index) => RecommendedPlaylistSummary(
        providerId: 'qq-music',
        opaqueId: 'catalog:${81000 + index}',
        title: const [
          'Ambient Landscapes',
          'Fresh electronic focus',
          'Late-night city pop',
          'Warm acoustic mornings',
          'Independent favorites',
          'Weekend road songs',
          'Quiet piano rooms',
          'Modern R&B selection',
          'Mandopop essentials',
          'Acoustic discoveries',
        ][index],
        trackCount: 18 + index,
      ),
    );
    final personalPlaylists = List.generate(
      6,
      (index) => RecommendedPlaylistSummary(
        providerId: 'qq-music',
        opaqueId: 'owned:${7000 + index}:201',
        title: const [
          'Piano Classics',
          'Morning Acoustic',
          'Deep Focus',
          'Jazz Vibes',
          'Chill Lo-Fi',
          'Night Drive',
        ][index],
        trackCount: 24 + index * 7,
      ),
    );
    final tracks = List.generate(
      6,
      (index) => PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:${41000 + index}:0:syntheticMid:-',
        title: const [
          'Silver Lines',
          'Night Transit',
          'Violet Morning',
          'Moving Quietly',
          'Green Signal',
          'Clouds Over Water',
        ][index],
        artistNames: [
          const [
            'North Harbor',
            'Cinder Avenue',
            'Mira Vale',
            'Juniper',
            'Signal Coast',
            'Aster Field',
          ][index],
        ],
        durationSeconds: 184 + index * 13,
      ),
    );
    final relatedTracks = List.generate(
      6,
      (index) => PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:${51000 + index}:0:syntheticRelatedMid:-',
        title: const [
          'Harbor Echo',
          'City After Rain',
          'Quiet Signals',
          'Distant Windows',
          'Parallel Skies',
          'Last Train Home',
        ][index],
        artistNames: [
          const [
            'Coastline',
            'Lantern District',
            'Low Tide',
            'Night Letters',
            'Luma Field',
            'Northern Line',
          ][index],
        ],
        durationSeconds: 176 + index * 11,
      ),
    );
    final newSongs = List.generate(
      6,
      (index) => PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:${61000 + index}:0:syntheticNewMid:-',
        title: const [
          'First Daylight',
          'New Constellation',
          'Bright City',
          'Open Water',
          'Summer Signal',
          'September Air',
        ][index],
        artistNames: [
          const [
            'Clear Harbor',
            'Nova Lane',
            'City Glass',
            'Blue Current',
            'Sunroom',
            'North Wind',
          ][index],
        ],
        durationSeconds: 171 + index * 12,
      ),
    );

    MusicApp fixture() {
      final queue = _WidgetPlaybackQueueGateway()
        ..replace(tracks: tracks, currentIndex: 0);
      return MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          UserLibraryResult(
            playlists: personalPlaylists
                .map((playlist) => playlist.toPlaylistSummary())
                .toList(growable: false),
          ),
        ]),
        accountSummaryGateway: const _WidgetAccountSummaryGateway(
          AccountSummaryLoadResult(
            summary: AuthenticatedAccountSummary(
              displayName: 'Synthetic listener',
            ),
          ),
        ),
        dailyRecommendationGateway: const _WidgetDailyRecommendationGateway(
          DailyRecommendationResult(
            playlist: RecommendedPlaylistSummary(
              providerId: 'qq-music',
              opaqueId: 'daily:30',
              title: 'Daily 30',
              trackCount: 30,
            ),
          ),
        ),
        personalizedPlaylistsGateway: _WidgetPersonalizedPlaylistsGateway(
          PersonalizedPlaylistsResult(playlists: personalPlaylists),
        ),
        personalizedTracksGateway: _WidgetPersonalizedTracksGateway(
          PersonalizedTracksResult(tracks: tracks),
        ),
        relatedTracksGateway: _WidgetRelatedTracksGateway(
          RelatedTracksResult(tracks: relatedTracks),
        ),
        recentListeningFactory: () => _WidgetRecentListening(tracks.first),
        radarGateway: _WidgetRadarGateway(
          RadarTrackPageResult(page: 1, tracks: [tracks.first]),
        ),
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          RecommendedPlaylistPageResult(playlists: publicPlaylists),
        ),
        newSongGateway: _WidgetNewSongGateway({
          NewSongCategory.latest: NewSongResult(
            category: NewSongCategory.latest,
            tracks: newSongs,
          ),
        }),
        playbackQueueGateway: queue,
        mediaResolutionGateway: const _UnavailableMediaGateway(),
        lyricGateway: const _WidgetLyricGateway(),
      );
    }

    Future<void> pumpFixture(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(fixture());
      await tester.pumpAndSettle();
      expect(find.text('Daily recommendation'), findsOneWidget);
      expect(find.text('Daily 30'), findsOneWidget);
      expect(find.text('Silver Lines'), findsWidgets);
      expect(
        find.byKey(const ValueKey('home-radar-recommendation')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-library-shelf')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-personalized-tracks')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-public-playlists-shelf')),
        findsOneWidget,
      );
      expect(find.text('Fresh releases'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-new-songs')), findsOneWidget);
      expect(find.text('First Daylight'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-hot-programs-unavailable')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('home-related-tracks')), findsOneWidget);
      expect(
        find.text('Because you listened to “Silver Lines”'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-open-library')), findsNothing);
      expect(
        find.byKey(const ValueKey('home-refresh-recommendations')),
        findsOneWidget,
      );
      expect(find.text('MADE FOR YOU'), findsNothing);
      expect(
        find.byKey(const ValueKey('home-spotlight-previous')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-spotlight-next')), findsOneWidget);
      if (!tester.platformDispatcher.accessibilityFeatures.disableAnimations) {
        expect(
          find.byKey(const ValueKey('home-spotlight-auto-play')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('home-spotlight-progress')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpFixture(const Size(1440, 960));
    final initialSpotlight = publicPlaylists.first;
    final nextSpotlight = publicPlaylists[1];
    final hero = find.byKey(const ValueKey('home-recommendation-0'));
    final sceneSwitcher = find.byKey(
      const ValueKey('home-spotlight-scene-switcher'),
    );
    final heroRect = tester.getRect(hero);
    expect(
      tester
          .getRect(hero)
          .overlaps(
            tester.getRect(find.byKey(const ValueKey('home-spotlight-title'))),
          ),
      isTrue,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
          .data,
      initialSpotlight.title,
    );
    if (!tester.platformDispatcher.accessibilityFeatures.disableAnimations) {
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('home-spotlight-progress')),
            )
            .value,
        greaterThan(0),
      );
    }
    await tester.tap(find.byKey(const ValueKey('home-spotlight-next')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getRect(hero), heroRect);
    final outgoingNext = find.descendant(
      of: sceneSwitcher,
      matching: find.text(initialSpotlight.title),
    );
    final incomingNext = find.descendant(
      of: sceneSwitcher,
      matching: find.text(nextSpotlight.title),
    );
    expect(outgoingNext, findsOneWidget);
    expect(incomingNext, findsOneWidget);
    expect(
      tester.getCenter(outgoingNext).dx,
      lessThan(tester.getCenter(incomingNext).dx),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(hero)
          .overlaps(
            tester.getRect(find.byKey(const ValueKey('home-spotlight-title'))),
          ),
      isTrue,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
          .data,
      nextSpotlight.title,
    );
    await tester.tap(find.byKey(const ValueKey('home-spotlight-previous')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getRect(hero), heroRect);
    final incomingPrevious = find.descendant(
      of: sceneSwitcher,
      matching: find.text(initialSpotlight.title),
    );
    final outgoingPrevious = find.descendant(
      of: sceneSwitcher,
      matching: find.text(nextSpotlight.title),
    );
    expect(incomingPrevious, findsOneWidget);
    expect(outgoingPrevious, findsOneWidget);
    expect(
      tester.getCenter(incomingPrevious).dx,
      lessThan(tester.getCenter(outgoingPrevious).dx),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-spotlight-auto-play')));
    await tester.pump();
    final pausedProgress = tester
        .widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('home-spotlight-progress')),
        )
        .value;
    await tester.pump(const Duration(seconds: 13));
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('home-spotlight-progress')),
          )
          .value,
      pausedProgress,
    );
    expect(
      tester
          .getRect(hero)
          .overlaps(
            tester.getRect(find.byKey(const ValueKey('home-spotlight-title'))),
          ),
      isTrue,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
          .data,
      initialSpotlight.title,
    );
    await tester.tap(find.byKey(const ValueKey('home-spotlight-auto-play')));
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(hero)
          .overlaps(
            tester.getRect(find.byKey(const ValueKey('home-spotlight-title'))),
          ),
      isTrue,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
          .data,
      nextSpotlight.title,
    );
    await tester.tap(find.byKey(const ValueKey('home-spotlight-previous')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('home-library-playlist-0'))),
      const Size.square(164),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('home-personalized-track-1')))
          .height,
      60,
    );
    expect(
      find.byKey(const ValueKey('now-playing-desktop-layout')),
      findsOneWidget,
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-home-desktop-canonical.png'),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('home-personalized-track-1')),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-home-desktop-content.png'),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('home-related-track-1')),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-home-desktop-lower.png'),
        ),
      );
    }

    await pumpFixture(const Size(1000, 900));
    final shelf = find.byKey(const ValueKey('home-library-shelf'));
    await tester.ensureVisible(shelf);
    await tester.pumpAndSettle();
    final shelfList = find.descendant(
      of: shelf,
      matching: find.byType(Scrollable),
    );
    final shelfPosition = tester.state<ScrollableState>(shelfList).position;
    expect(shelfPosition.maxScrollExtent, greaterThan(0));
    final nextShelf = find.byKey(const ValueKey('home-library-shelf-next'));
    expect(nextShelf, findsOneWidget);
    expect(find.descendant(of: shelf, matching: nextShelf), findsNothing);
    await tester.ensureVisible(nextShelf);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(nextShelf).onPressed, isNotNull);
    final firstCard = tester.getRect(
      find.byKey(const ValueKey('home-library-playlist-0')),
    );
    await tester.tap(nextShelf);
    await tester.pumpAndSettle();
    final lastCard = tester.getRect(
      find.byKey(const ValueKey('home-library-playlist-5')),
    );
    expect(lastCard.top, closeTo(firstCard.top, 0.1));
    expect(
      lastCard.right,
      lessThanOrEqualTo(tester.getRect(shelf).right + 0.5),
    );
    expect(shelfPosition.pixels, greaterThan(0));
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-home-medium-shelf.png'),
        ),
      );
    }

    await pumpFixture(const Size(390, 844));
    expect(find.text(_en.homeRecommendTab), findsNothing);
    expect(find.text(_en.homeMusicTab), findsNothing);
    expect(find.text(_en.homeAudiobooksTab), findsNothing);
    expect(find.text(_en.homePodcastsTab), findsNothing);
    expect(
      find.byKey(const ValueKey('shell-top-bar-title-Home')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-library-playlist-0'))),
      const Size.square(136),
    );
    expect(
      find.byKey(const ValueKey('now-playing-compact-layout')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-library-shelf-next')), findsNothing);
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-home-mobile-canonical.png'),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('home-library-shelf')),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-home-mobile-library.png'),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('home-personalized-track-1')),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-home-mobile-content.png'),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('home-related-track-1')),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-home-mobile-lower.png'),
        ),
      );
    }

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpFixture(const Size(1440, 960));
    expect(
      find.byKey(const ValueKey('home-spotlight-auto-play')),
      findsNothing,
    );
  });

  testWidgets('routes fresh QR authentication through Home to Liked', (
    tester,
  ) async {
    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(session),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
      ),
    );

    await _openSignInDialog(tester);
    await tester.tap(find.text('Scan with WeChat'));
    await tester.pump();
    session.complete(
      const LoginUpdate(
        progress: LoginProgress.authenticated,
        sessionActive: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-refresh-recommendations')),
      findsOneWidget,
    );
    await _openLibrary(tester);
    expect(find.text(_en.likedPlaylistUnavailableTitle), findsOneWidget);
    expect(find.text('Library'), findsNothing);
  });

  testWidgets('opens real Home content and restores its exact entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const recommendation = RecommendedPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'catalog:81001',
      title: 'Home recommendation',
      trackCount: 12,
    );
    const personal = RecommendedPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'owned:7001:201',
      title: 'Home personal playlist',
      trackCount: 2,
    );
    final detail = _WidgetDetailGateway([
      const PlaylistTrackPageResult(
        total: 1,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:41001:0:fixtureMid:-',
            title: 'Recommended Home track',
            artistNames: ['Discovery artist'],
          ),
        ],
      ),
      const PlaylistTrackPageResult(
        total: 1,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:41002:0:fixtureMid:-',
            title: 'Personal Home track',
            artistNames: ['Library artist'],
          ),
        ],
      ),
    ]);
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        personalizedPlaylistsGateway: _WidgetPersonalizedPlaylistsGateway(
          const PersonalizedPlaylistsResult(playlists: [personal]),
        ),
        playlistDetailGateway: detail,
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          const RecommendedPlaylistPageResult(playlists: [recommendation]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home recommendation'), findsOneWidget);
    expect(find.text('Home personal playlist'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('home-recommendation-0')));
    await tester.pumpAndSettle();
    expect(find.text('Recommended Home track'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to playlists'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'last Home recommendation',
    );

    final personalShelf = find.byKey(const ValueKey('home-library-shelf'));
    final personalEntry = find.descendant(
      of: personalShelf,
      matching: find.text('Home personal playlist'),
    );
    await tester.ensureVisible(personalShelf);
    await tester.pumpAndSettle();
    await tester.tap(personalEntry);
    await tester.pumpAndSettle();
    expect(find.text('Personal Home track'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to playlists'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'last Home recommendation',
    );
    expect(detail.requests.map((request) => request.playlist.opaqueId), [
      'catalog:81001',
      'owned:7001:201',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returns from Search to Home and restores entry focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        searchGateway: const _UnusedSearchGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final searchEntry = find.byKey(const ValueKey('open-track-search'));
    await tester.tap(searchEntry);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('shell-top-bar-title-Search')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('track-search-field')), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(tester.widget<Focus>(searchEntry).focusNode?.hasFocus, isTrue);
  });

  testWidgets(
    'adapts primary navigation and retains Search and Discover state',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:fixtureMid:-',
        title: 'Retained search result',
        artistNames: ['Artist'],
      );
      const homeTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41002:0:homeFixtureMid:-',
        title: 'Compact Home song',
        artistNames: ['Home artist'],
      );
      const relatedTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:51002:0:relatedFixtureMid:-',
        title: 'Related Home song',
        artistNames: ['Related artist'],
      );
      const compactPlaylist = UserPlaylistSummary(
        providerId: 'qq-music',
        opaqueId: 'owned:7001:201',
        title: 'Compact Home playlist',
        trackCount: 8,
      );
      final search = _WidgetSearchGateway(
        const TrackSearchPageResult(
          page: 1,
          total: 1,
          items: [TrackSearchItem(track: track)],
        ),
      );
      final recommendations = _WidgetRecommendedPlaylistGateway(
        const RecommendedPlaylistPageResult(
          playlists: [
            RecommendedPlaylistSummary(
              providerId: 'qq-music',
              opaqueId: 'catalog:81001',
              title: 'Retained discovery result',
              trackCount: 1,
            ),
          ],
        ),
      );
      final queue = _WidgetPlaybackQueueGateway();
      final relatedSeeds = <PlaylistTrackSummary>[];
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([
            const UserLibraryResult(playlists: [compactPlaylist]),
          ]),
          personalizedPlaylistsGateway: _WidgetPersonalizedPlaylistsGateway(
            const PersonalizedPlaylistsResult(
              playlists: [
                RecommendedPlaylistSummary(
                  providerId: 'qq-music',
                  opaqueId: 'owned:7001:201',
                  title: 'Compact Home playlist',
                  trackCount: 8,
                ),
              ],
            ),
          ),
          personalizedTracksGateway: const _WidgetPersonalizedTracksGateway(
            PersonalizedTracksResult(tracks: [homeTrack]),
          ),
          relatedTracksGateway: _WidgetRelatedTracksGateway(
            const RelatedTracksResult(tracks: [relatedTrack]),
            seeds: relatedSeeds,
          ),
          recentListeningFactory: () => _WidgetRecentListening(homeTrack),
          searchGateway: search,
          recommendedPlaylistGateway: recommendations,
          newSongGateway: _WidgetNewSongGateway({
            NewSongCategory.latest: const NewSongResult(
              category: NewSongCategory.latest,
            ),
          }),
          playbackQueueGateway: queue,
          mediaResolutionGateway: const _UnavailableMediaGateway(),
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
        hasLength(5),
      );
      expect(
        (tester
                    .widget<NavigationBar>(find.byType(NavigationBar))
                    .destinations
                    .last
                as NavigationDestination)
            .label,
        _en.navRecentPlays,
      );
      expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-recommendations-section')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-library-shelf')), findsOneWidget);
      expect(find.text('Compact Home playlist'), findsWidgets);
      expect(find.byKey(const ValueKey('top-search-shortcut')), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('shell-top-bar-title-Home')),
        findsOneWidget,
      );
      expect(tester.getSize(find.byType(NavigationBar)).height, 72);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('home-recommendation-0')))
            .height,
        208,
      );
      expect(find.byKey(const ValueKey('home-compact-actions')), findsNothing);
      expect(tester.takeException(), isNull);

      final personalizedTrack = find.byKey(
        const ValueKey('home-personalized-track-1'),
      );
      await tester.ensureVisible(personalizedTrack);
      await tester.pumpAndSettle();
      final queueAction = find.byKey(
        const ValueKey('home-personalized-track-queue-1'),
      );
      expect(tester.getSize(queueAction), const Size.square(48));
      await tester.tap(queueAction);
      await tester.pumpAndSettle();
      expect(queue.pushed, [homeTrack]);
      expect(find.text(_en.queueAddedMessage), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(personalizedTrack);
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('now-playing-compact-layout')))
            .height,
        68,
      );
      expect(
        (tester
                    .widget<SingleChildScrollView>(
                      find.byKey(const PageStorageKey('home-scroll')),
                    )
                    .padding
                as EdgeInsets)
            .bottom,
        104,
      );
      expect(queue.replacements.single.$1, [homeTrack]);
      expect(relatedSeeds.single.opaqueId, homeTrack.opaqueId);
      expect(
        find.text('Because you listened to “Compact Home song”'),
        findsOneWidget,
      );
      expect(find.text('Related Home song'), findsOneWidget);

      final homeSearch = find.byKey(const ValueKey('open-track-search'));
      await tester.ensureVisible(homeSearch);
      await tester.pumpAndSettle();
      await tester.tap(homeSearch);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('track-search-field')),
        'retained query',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Retained search result'), findsOneWidget);
      expect(search.requests, [('retained query', 1, 30)]);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('now-playing-compact-layout')))
            .height,
        68,
      );
      expect(tester.getSize(find.byType(NavigationBar)).height, 72);
      final searchState = tester.state(find.byType(TrackSearchPage));

      await tester.tap(
        find.byKey(const ValueKey('primary-library-destination')),
      );
      await tester.pumpAndSettle();
      final retainedSearchPage = find.byType(
        TrackSearchPage,
        skipOffstage: false,
      );
      expect(retainedSearchPage, findsOneWidget);
      expect(tester.state(retainedSearchPage), same(searchState));
      await tester.tap(find.byKey(const ValueKey('open-track-search')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('track-search-field')))
            .controller
            ?.text,
        'retained query',
      );
      expect(find.text('Retained search result'), findsOneWidget);
      expect(search.requests, [('retained query', 1, 30)]);

      await tester.tap(find.byKey(const ValueKey('open-recommendations')));
      await tester.pumpAndSettle();
      expect(find.text('Retained discovery result'), findsOneWidget);
      expect(recommendations.requests, [(0, 20), (0, 20)]);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('now-playing-compact-layout')))
            .height,
        68,
      );

      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-new-songs',
      );
      expect(find.byKey(const ValueKey('new-songs-empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('primary-home-destination')));
      await tester.pumpAndSettle();
      final seeAllPlaylists = find.byKey(
        const ValueKey('home-open-more-recommendations'),
      );
      await tester.ensureVisible(seeAllPlaylists);
      await tester.tap(seeAllPlaylists);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recommendations-content')),
        findsOneWidget,
      );
      expect(find.text('Retained discovery result'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-songs-content')), findsNothing);
      expect(recommendations.requests, [(0, 20), (0, 20)]);

      tester.view.physicalSize = const Size(1100, 760);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(
        find.byKey(const ValueKey('desktop-music-sidebar')),
        findsOneWidget,
      );
      expect(find.text('Retained discovery result'), findsOneWidget);
      expect(recommendations.requests, [(0, 20), (0, 20)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('labels the compact Discover loading state', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recommendations = _ControlledWidgetRecommendedPlaylistGateway();

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        recommendedPlaylistGateway: recommendations,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-recommendations')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('recommendations-loading')),
      findsOneWidget,
    );
    expect(find.byType(MusicLoadingPanel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('recommendations-loading')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == _en.discoverLoadingRecommendations,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    recommendations.complete(const RecommendedPlaylistPageResult());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recommendations-empty')), findsOneWidget);
  });

  testWidgets('all compact Discover sections use shared empty states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          const RecommendedPlaylistPageResult(),
        ),
        rankingGateway: _WidgetRankingGateway(
          const RankingGroupResult(),
          const RankingTrackPageResult(),
        ),
        radarGateway: _WidgetRadarGateway(const RadarTrackPageResult(page: 1)),
        newAlbumGateway: _WidgetNewAlbumGateway(
          const NewAlbumPageResult(region: NewAlbumRegion.mainlandChina),
        ),
        newSongGateway: _WidgetNewSongGateway({
          NewSongCategory.latest: const NewSongResult(
            category: NewSongCategory.latest,
          ),
        }),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-recommendations')));
    await tester.pumpAndSettle();

    for (final (type, stateKey) in [
      ('playlists', 'recommendations-empty'),
      ('rankings', 'rankings-empty'),
      ('radar', 'radar-empty'),
      ('new-albums', 'new-albums-empty'),
      ('new-songs', 'new-songs-empty'),
    ]) {
      if (type != 'playlists') {
        await _selectAdaptiveSection(
          tester,
          control: 'discover-type-selector',
          item: 'discover-type-$type',
        );
      }
      expect(find.byKey(ValueKey(stateKey)), findsOneWidget);
      expect(find.byType(MusicContentStatePanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    expect(
      find.byKey(const ValueKey('new-song-category-selector')),
      findsOneWidget,
    );
    await _selectAdaptiveSection(
      tester,
      control: 'discover-type-selector',
      item: 'discover-type-new-albums',
    );
    expect(
      find.byKey(const ValueKey('new-album-region-selector')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('New Songs keeps one stable selector while switching', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final newSongs = _TransitionWidgetNewSongGateway();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          const RecommendedPlaylistPageResult(),
        ),
        newSongGateway: newSongs,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-recommendations')));
    await tester.pumpAndSettle();
    await _selectAdaptiveSection(
      tester,
      control: 'discover-type-selector',
      item: 'discover-type-new-songs',
    );

    await tester.tap(find.byKey(const ValueKey('new-song-category-western')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('new-song-category-selector')),
      findsOneWidget,
    );
    expect(find.byType(SegmentedButton<NewSongCategory>), findsNothing);
    expect(
      find.byKey(const ValueKey('new-song-category-western')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('new-songs-loading')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact New Songs exposes every category and keeps Play stable while loading',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final newSongs = _TransitionWidgetNewSongGateway();
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
            const RecommendedPlaylistPageResult(),
          ),
          newSongGateway: newSongs,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-recommendations')));
      await tester.pumpAndSettle();
      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-new-songs',
      );

      final categoryMenu = find.byKey(
        const ValueKey('new-song-category-selector'),
      );
      final play = find.byKey(const ValueKey('new-songs-play-all'));
      expect(categoryMenu, findsOneWidget);
      expect(play, findsOneWidget);
      for (final category in NewSongCategory.values) {
        expect(
          find.byKey(ValueKey('new-song-category-${category.name}')),
          findsOneWidget,
        );
      }

      await tester.drag(categoryMenu, const Offset(-220, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-song-category-western')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('new-songs-loading')), findsOneWidget);
      expect(play, findsOneWidget);
      expect(tester.widget<FilledButton>(play).onPressed, isNull);
      expect(tester.getSize(play).height, greaterThanOrEqualTo(48));

      newSongs.western.complete(
        const NewSongResult(category: NewSongCategory.western),
      );
      await tester.pumpAndSettle();
      expect(play, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Radar rejection keeps one live region and sign-in recovery', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          const RecommendedPlaylistPageResult(),
        ),
        radarGateway: _ScriptedWidgetRadarGateway([
          const RadarTrackPageResult(page: 1),
          const RadarTrackPageResult(failure: RadarFailure.credentialRejected),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-recommendations')));
    await tester.pumpAndSettle();
    await _selectAdaptiveSection(
      tester,
      control: 'discover-type-selector',
      item: 'discover-type-radar',
    );

    expect(find.byKey(const ValueKey('radar-error')), findsOneWidget);
    expect(find.byType(MusicContentStatePanel), findsOneWidget);
    expect(find.text('Sign in again'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('radar-error')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Sign in again'));
    await tester.pumpAndSettle();
    expect(find.text('Scan with WeChat'), findsOneWidget);
  });

  testWidgets('activates desktop primary navigation from the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        searchGateway: const _UnusedSearchGateway(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const ValueKey('desktop-music-sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-sidebar-brand')), findsOneWidget);
    expect(find.byKey(const ValueKey('top-search-shortcut')), findsOneWidget);
    final searchEntry = find.byKey(const ValueKey('open-track-search'));
    final searchTile = find.descendant(
      of: searchEntry,
      matching: find.byType(ListTile),
    );
    tester.widget<ListTile>(searchTile).focusNode?.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('shell-top-bar-title-Search')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('track-search-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opens a recommendation through existing detail and preserves discovery',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const playlist = RecommendedPlaylistSummary(
        providerId: 'qq-music',
        opaqueId: 'catalog:81001',
        title: 'Synthetic discovery',
        trackCount: 1,
      );
      final recommendations = _WidgetRecommendedPlaylistGateway(
        const RecommendedPlaylistPageResult(playlists: [playlist]),
      );
      final detail = _WidgetDetailGateway([
        const PlaylistTrackPageResult(
          total: 1,
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:41001:0:fixtureMid:-',
              title: 'Recommended track',
              artistNames: ['Discovery artist'],
            ),
          ],
        ),
      ]);
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          playlistDetailGateway: detail,
          recommendedPlaylistGateway: recommendations,
        ),
      );
      await tester.pumpAndSettle();

      final discoverEntry = find.byKey(const ValueKey('open-recommendations'));
      await tester.tap(discoverEntry);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recommendations-content')),
        findsOneWidget,
      );
      expect(find.text('Synthetic discovery'), findsOneWidget);
      expect(recommendations.requests, [(0, 20), (0, 20)]);
      expect(find.byType(GridView), findsNothing);
      final compactRecommendation = tester.getSize(
        find.byKey(const ValueKey('recommendations-item-0')),
      );
      expect(
        compactRecommendation.height,
        greaterThan(compactRecommendation.width),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('recommendations-artwork-0'))),
        Size.square(compactRecommendation.width),
      );

      tester.view.physicalSize = const Size(1000, 700);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey<String>('recommended-playlist-grid')),
        findsOneWidget,
      );
      final mediumRecommendation = tester.getSize(
        find.byKey(const ValueKey('recommendations-item-0')),
      );
      expect(
        mediumRecommendation.height,
        greaterThan(mediumRecommendation.width),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('recommendations-artwork-0'))),
        Size.square(mediumRecommendation.width),
      );
      expect(find.text('Synthetic discovery'), findsOneWidget);
      expect(recommendations.requests, [(0, 20), (0, 20)]);

      await tester.tap(find.text('Synthetic discovery'));
      await tester.pumpAndSettle();
      expect(find.text('Recommended track'), findsOneWidget);
      expect(
        tester
            .widget<PlaylistDetailPage>(find.byType(PlaylistDetailPage))
            .onOpenAlbum,
        isNotNull,
      );
      expect(
        tester
            .widget<PlaylistDetailPage>(find.byType(PlaylistDetailPage))
            .onOpenArtist,
        isNotNull,
      );
      expect(detail.requests.single.playlist.opaqueId, 'catalog:81001');

      await tester.tap(find.byTooltip('Back to playlists'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic discovery'), findsOneWidget);
      expect(recommendations.requests, [(0, 20), (0, 20)]);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
      expect(tester.widget<Focus>(discoverEntry).focusNode?.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Discover content remains bounded across critical widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 900);
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          const RecommendedPlaylistPageResult(
            playlists: [
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:responsive',
                title: 'Responsive discovery card with a long title',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-recommendations')));
    await tester.pumpAndSettle();

    for (final width in <double>[
      320,
      390,
      520,
      599,
      600,
      639,
      640,
      759,
      760,
      819,
      820,
      839,
      840,
      1099,
      1100,
      1440,
    ]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      final item = tester.getRect(
        find.byKey(const ValueKey('recommendations-item-0')),
      );
      expect(item.left, greaterThanOrEqualTo(0));
      expect(item.right, lessThanOrEqualTo(width));
      expect(
        find.byKey(const ValueKey('recommendations-content')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('recommendations-artwork-0')))
            .width,
        lessThanOrEqualTo(176.01),
        reason: 'artwork width $width',
      );
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets(
    'canonical Discover header, grid, and player overlay are coherent',
    (tester) async {
      const captureReviewImages = bool.fromEnvironment(
        'DISCOVER_VISUAL_REVIEW',
      );
      await _loadRecentReviewFonts(tester, enabled: captureReviewImages);
      final playlists = List.generate(
        10,
        (index) => RecommendedPlaylistSummary(
          providerId: 'qq-music',
          opaqueId: 'discover-review-$index',
          title: const [
            'Quiet hours for focused listening',
            'Fresh voices across the city',
            'Late-night electronic discoveries',
            'Warm acoustic weekend',
            'Piano rooms and soft rain',
            'Songs for the long way home',
            'Indie colors after sunset',
            'Bright pop for a new morning',
            'Unhurried jazz selections',
            'A small universe of sound',
          ][index],
          trackCount: 24 + index * 9,
        ),
      );
      final radarTracks = List.generate(
        10,
        (index) => PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:radar-review-$index',
          title: const [
            'Signals after midnight',
            'Slow orbit',
            'Glass city',
            'Summer radio',
            'Paper constellation',
            'Small hours',
            'Open windows',
            'Distant headlights',
            'New frequencies',
            'Before the morning',
          ][index],
          artistNames: ['Radar artist ${index + 1}'],
          albumTitle: 'Radar dispatch ${index + 1}',
          durationSeconds: 176 + index * 7,
        ),
      );
      final newSongTracks = List.generate(
        10,
        (index) => PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:new-song-review-$index',
          title: 'New release ${index + 1}',
          artistNames: ['Fresh artist ${index + 1}'],
          albumTitle: 'First light',
          durationSeconds: 188 + index * 5,
        ),
      );
      final newAlbumReleases = List.generate(
        8,
        (index) => NewAlbumRelease(
          album: AlbumSummary(
            providerId: 'qq-music',
            opaqueId: 'album:new-review-$index',
            title: 'New album ${index + 1}',
          ),
          artists: [
            ArtistSummary(
              providerId: 'qq-music',
              opaqueId: 'artist:new-review-$index',
              name: 'Album artist ${index + 1}',
            ),
          ],
          releaseDate: '2026-09-${(index + 1).toString().padLeft(2, '0')}',
        ),
      );
      const rankingGroups = RankingGroupResult(
        groups: [
          RankingGroup(
            title: 'Popular now',
            rankings: [
              RankingSummary(
                providerId: 'qq-music',
                opaqueId: 'ranking:review-hot',
                title: 'Hot Songs',
                period: 'This week',
                trackCount: 100,
              ),
              RankingSummary(
                providerId: 'qq-music',
                opaqueId: 'ranking:review-new',
                title: 'New Music',
                period: 'Today',
                trackCount: 100,
              ),
              RankingSummary(
                providerId: 'qq-music',
                opaqueId: 'ranking:review-global',
                title: 'Global Picks',
                period: 'This week',
                trackCount: 50,
              ),
            ],
          ),
          RankingGroup(
            title: 'Genres and scenes',
            rankings: [
              RankingSummary(
                providerId: 'qq-music',
                opaqueId: 'ranking:review-electronic',
                title: 'Electronic',
                period: 'This week',
                trackCount: 50,
              ),
              RankingSummary(
                providerId: 'qq-music',
                opaqueId: 'ranking:review-indie',
                title: 'Indie discoveries',
                period: 'This week',
                trackCount: 50,
              ),
            ],
          ),
        ],
      );
      const currentTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:discover-review',
        title: 'After the rain',
        artistNames: ['Harbor Lights'],
        albumTitle: 'City reflections',
        durationSeconds: 218,
      );

      MusicApp fixture() {
        final queue = _WidgetPlaybackQueueGateway()
          ..replace(tracks: const [currentTrack], currentIndex: 0);
        return MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
            RecommendedPlaylistPageResult(playlists: playlists),
          ),
          rankingGateway: _WidgetRankingGateway(
            rankingGroups,
            const RankingTrackPageResult(),
          ),
          radarGateway: _WidgetRadarGateway(
            RadarTrackPageResult(page: 1, tracks: radarTracks),
          ),
          newAlbumGateway: _WidgetNewAlbumGateway(
            NewAlbumPageResult(
              region: NewAlbumRegion.mainlandChina,
              total: newAlbumReleases.length,
              releases: newAlbumReleases,
            ),
          ),
          newSongGateway: _WidgetNewSongGateway({
            NewSongCategory.latest: NewSongResult(
              category: NewSongCategory.latest,
              tracks: newSongTracks,
            ),
          }),
          playbackQueueGateway: queue,
          mediaResolutionGateway: const _UnavailableMediaGateway(),
          lyricGateway: const _WidgetLyricGateway(),
          initialSettings: const AppSettings(theme: AppThemePreference.light),
        );
      }

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(fixture());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-recommendations')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('discover-expanded-header')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('discover-heading')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('discover-type-selector')),
        findsOneWidget,
      );
      final playlistTab = find.byKey(const ValueKey('discover-type-playlists'));
      final albumTab = find.byKey(const ValueKey('discover-type-new-albums'));
      final playlistTabCenter = tester.getCenter(playlistTab);
      final albumTabCenter = tester.getCenter(albumTab);
      await tester.tap(find.byKey(const ValueKey('discover-type-rankings')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('discover-body-playlists')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('discover-body-rankings')),
        findsOneWidget,
      );
      expect(tester.getCenter(playlistTab), playlistTabCenter);
      expect(tester.getCenter(albumTab), albumTabCenter);
      await tester.pumpAndSettle();
      await tester.tap(playlistTab);
      await tester.pumpAndSettle();
      final recommendationCard = tester.getSize(
        find.byKey(const ValueKey('recommendations-item-0')),
      );
      expect(recommendationCard.width, 169);
      expect(recommendationCard.height, greaterThan(recommendationCard.width));
      expect(
        tester.getSize(find.byKey(const ValueKey('recommendations-artwork-0'))),
        const Size.square(169),
      );
      expect(
        find.byKey(const ValueKey('compact-player-overlay-shell')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Scaffold>(
              find.byKey(const ValueKey('authenticated-content-shell')),
            )
            .bottomNavigationBar,
        isA<NavigationBar>(),
      );
      final discoverGrid = find.byKey(
        const PageStorageKey<String>('recommended-playlist-grid'),
      );
      final compactPlayer = find.byKey(
        const ValueKey('now-playing-compact-layout'),
      );
      expect(
        tester.getBottomLeft(discoverGrid).dy,
        greaterThan(tester.getTopLeft(compactPlayer).dy),
      );
      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-new-albums',
      );
      expect(find.byType(SegmentedButton<NewAlbumRegion>), findsNothing);
      expect(
        find.byKey(const ValueKey('new-album-region-mainlandChina')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('stable-selector-edge-affordance')),
        findsOneWidget,
      );
      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-rankings',
      );
      expect(find.text(_en.trackCount(50)), findsWidgets);
      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-playlists',
      );
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-discover-mobile-canonical.png'),
          ),
        );
        await _selectAdaptiveSection(
          tester,
          control: 'discover-type-selector',
          item: 'discover-type-radar',
        );
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-discover-mobile-radar.png'),
          ),
        );
        for (final (item, path) in [
          (
            'discover-type-rankings',
            '/tmp/flutterustmusic-discover-mobile-rankings.png',
          ),
          (
            'discover-type-new-albums',
            '/tmp/flutterustmusic-discover-mobile-new-albums.png',
          ),
          (
            'discover-type-new-songs',
            '/tmp/flutterustmusic-discover-mobile-new-songs.png',
          ),
          (
            'discover-type-playlists',
            '/tmp/flutterustmusic-discover-mobile-canonical.png',
          ),
        ]) {
          await _selectAdaptiveSection(
            tester,
            control: 'discover-type-selector',
            item: item,
          );
          if (item != 'discover-type-playlists') {
            await expectLater(
              find.byType(MusicApp),
              matchesGoldenFile(Uri.file(path)),
            );
          }
        }
      }

      await tester.drag(discoverGrid, const Offset(0, -220));
      await tester.pump();
      // Scroll-derived header state is committed after the notification frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final transitioningShellTitle = find.byKey(
        const ValueKey('shell-top-bar-title-Discover'),
      );
      expect(transitioningShellTitle, findsOneWidget);
      final transitionalOpacities = tester
          .widgetList<FadeTransition>(
            find.ancestor(
              of: transitioningShellTitle,
              matching: find.byType(FadeTransition),
            ),
          )
          .map((widget) => widget.opacity.value);
      expect(
        transitionalOpacities,
        contains(predicate<double>((value) => value > 0 && value < 1)),
      );
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-discover-mobile-transition.png'),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('discover-collapsed-header')),
        findsOneWidget,
      );
      final collapsedHeadingOpacities = tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byKey(const ValueKey('discover-heading')),
              matching: find.byType(Opacity),
            ),
          )
          .map((widget) => widget.opacity);
      expect(collapsedHeadingOpacities, contains(0));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('primary-shell-top-bar')),
          matching: find.text('Discover'),
        ),
        findsOneWidget,
      );
      final collapsedTitle = tester.widget<Text>(transitioningShellTitle);
      expect(collapsedTitle.style?.fontWeight, FontWeight.w700);
      expect(
        collapsedTitle.style?.fontSize,
        Theme.of(tester.element(transitioningShellTitle))
            .textTheme
            .titleLarge
            ?.fontSize,
      );
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-discover-mobile-collapsed.png'),
          ),
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpWidget(fixture());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-recommendations')));
      await tester.pumpAndSettle();
      final desktopRecommendation = tester.getSize(
        find.byKey(const ValueKey('recommendations-item-0')),
      );
      expect(
        desktopRecommendation.height,
        greaterThan(desktopRecommendation.width),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('recommendations-artwork-0'))),
        Size.square(desktopRecommendation.width),
      );
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-discover-desktop-canonical.png'),
          ),
        );
        for (final (item, path) in [
          (
            'discover-type-rankings',
            '/tmp/flutterustmusic-discover-desktop-rankings.png',
          ),
          (
            'discover-type-radar',
            '/tmp/flutterustmusic-discover-desktop-radar.png',
          ),
          (
            'discover-type-new-albums',
            '/tmp/flutterustmusic-discover-desktop-new-albums.png',
          ),
          (
            'discover-type-new-songs',
            '/tmp/flutterustmusic-discover-desktop-new-songs.png',
          ),
        ]) {
          await _selectAdaptiveSection(
            tester,
            control: 'discover-type-selector',
            item: item,
          );
          await expectLater(
            find.byType(MusicApp),
            matchesGoldenFile(Uri.file(path)),
          );
        }
        await _selectAdaptiveSection(
          tester,
          control: 'discover-type-selector',
          item: 'discover-type-playlists',
        );
        final desktopGrid = find.byKey(
          const PageStorageKey<String>('recommended-playlist-grid'),
        );
        await tester.drag(desktopGrid, const Offset(0, -220));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-discover-desktop-collapsed.png'),
          ),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opens a current ranking and preserves independent Discover state',
    (tester) async {
      const captureCollectionDetails = bool.fromEnvironment(
        'COLLECTION_DETAIL_VISUAL_REVIEW',
      );
      await _loadRecentReviewFonts(tester, enabled: captureCollectionDetails);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const ranking = RankingSummary(
        providerId: 'qq-music',
        opaqueId: 'ranking:62001',
        title: 'Synthetic ranking',
        period: 'fixture-period',
        trackCount: 1,
      );
      const rankingTwo = RankingSummary(
        providerId: 'qq-music',
        opaqueId: 'ranking:62002',
        title: 'Synthetic ranking two',
        period: 'fixture-period-2',
      );
      const rankingThree = RankingSummary(
        providerId: 'qq-music',
        opaqueId: 'ranking:62003',
        title: 'Synthetic ranking three',
        period: 'fixture-period-3',
      );
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:fixtureMid:-',
        title: 'Ranked Track',
        artistNames: ['Ranking artist'],
      );
      final rankings = _WidgetRankingGateway(
        const RankingGroupResult(
          groups: [
            RankingGroup(
              title: 'Synthetic charts',
              rankings: [ranking, rankingTwo, rankingThree],
            ),
          ],
        ),
        const RankingTrackPageResult(
          ranking: ranking,
          total: 1,
          tracks: [track],
        ),
      );
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          playlistDetailGateway: _WidgetDetailGateway([]),
          recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
            const RecommendedPlaylistPageResult(),
          ),
          rankingGateway: rankings,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-recommendations')));
      await tester.pumpAndSettle();
      expect(rankings.groupLoads, 0);

      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-rankings',
      );
      expect(find.byKey(const ValueKey('rankings-content')), findsOneWidget);
      expect(find.text('Synthetic charts'), findsOneWidget);
      expect(find.text('Synthetic ranking'), findsOneWidget);
      expect(
        find.text(_en.discoverRankingIssue('fixture-period')),
        findsOneWidget,
      );
      expect(rankings.groupLoads, 1);

      Rect rankingRect(String id) =>
          tester.getRect(find.byKey(ValueKey('ranking-$id')));
      final wideFirst = rankingRect('ranking:62001');
      final wideSecond = rankingRect('ranking:62002');
      final wideThird = rankingRect('ranking:62003');
      expect(wideSecond.top, closeTo(wideFirst.top, 0.1));
      expect(wideThird.top, closeTo(wideFirst.top, 0.1));

      tester.view.physicalSize = const Size(1100, 900);
      await tester.pumpAndSettle();
      final mediumFirst = rankingRect('ranking:62001');
      final mediumSecond = rankingRect('ranking:62002');
      final mediumThird = rankingRect('ranking:62003');
      expect(mediumSecond.top, closeTo(mediumFirst.top, 0.1));
      expect(mediumThird.top, greaterThan(mediumFirst.bottom));

      tester.view.physicalSize = const Size(759, 900);
      await tester.pumpAndSettle();
      expect(
        rankingRect('ranking:62002').top,
        greaterThan(rankingRect('ranking:62001').bottom),
      );
      expect(
        rankingRect('ranking:62003').top,
        greaterThan(rankingRect('ranking:62002').bottom),
      );
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ranking-ranking:62001')));
      await tester.pumpAndSettle();
      expect(find.text('Ranked Track'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop-music-sidebar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('embedded-ranking-detail')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ranking-track-table-header')),
        findsOneWidget,
      );
      expect(rankings.trackRequests, [(ranking, 0, 30)]);
      if (captureCollectionDetails) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-ranking-detail-desktop.png'),
          ),
        );
      }

      await tester.tap(find.byKey(const ValueKey('ranking-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rankings-content')), findsOneWidget);
      expect(rankings.groupLoads, 1);

      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-playlists',
      );
      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-rankings',
      );
      expect(find.text('Synthetic ranking'), findsOneWidget);
      expect(rankings.groupLoads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loads Home Radar and keeps Discover Radar queue behavior on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const album = AlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43001:fixtureRadarAlbumMid',
        title: 'Radar Album',
      );
      const artist = ArtistSummary(
        providerId: 'qq-music',
        opaqueId: 'artist:42001:fixtureRadarArtistMid',
        name: 'Radar artist',
      );
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:fixtureRadarMid:-',
        title: 'Radar Track',
        artistNames: ['Radar artist'],
        artists: [artist],
        albumTitle: 'Radar Album',
        album: album,
        durationSeconds: 185,
      );
      final radar = _WidgetRadarGateway(
        const RadarTrackPageResult(page: 1, tracks: [track]),
      );
      final albums = _WidgetAlbumGateway(
        const AlbumTrackPageResult(total: 1, tracks: [track]),
      );
      final queue = _WidgetPlaybackQueueGateway();
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
            const RecommendedPlaylistPageResult(),
          ),
          radarGateway: radar,
          albumTrackGateway: albums,
          albumDetailsGateway: const _WidgetAlbumDetailsGateway(),
          playbackQueueGateway: queue,
          mediaResolutionGateway: const _UnavailableMediaGateway(),
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-recommendations')));
      await tester.pumpAndSettle();
      expect(radar.pages, [1]);

      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-radar',
      );
      expect(find.byKey(const ValueKey('radar-content')), findsOneWidget);
      expect(find.text('Radar Track'), findsOneWidget);
      expect(find.text('Radar artist'), findsOneWidget);
      expect(find.text('Radar Album'), findsOneWidget);
      expect(find.text('3:05'), findsOneWidget);
      expect(radar.pages, [1, 1]);

      await tester.tap(find.byKey(const ValueKey('radar-context-0')));
      await tester.pumpAndSettle();
      expect(find.text('Open album'), findsOneWidget);
      expect(find.text('Open artist'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('track-context-album')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('album-content')), findsOneWidget);
      expect(albums.requests, [(album, 0, 30)]);

      await tester.tap(find.byKey(const ValueKey('album-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('radar-content')), findsOneWidget);
      expect(radar.pages, [1, 1]);

      await tester.tap(find.byKey(const ValueKey('radar-context-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await tester.pump();
      expect(queue.pushed, [track]);

      await tester.tap(find.byKey(const ValueKey('radar-track-0')));
      await tester.pump();
      expect(queue.replacements, hasLength(1));
      expect(queue.replacements.single.$1, [track]);
      expect(queue.replacements.single.$2, 0);

      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-playlists',
      );
      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-radar',
      );
      expect(find.byKey(const ValueKey('radar-track-0')), findsOneWidget);
      expect(radar.pages, [1, 1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Discover Radar prefetches the next page while scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<PlaylistTrackSummary> tracks(String page, int count) => List.generate(
      count,
      (index) => PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:radar-$page-$index',
        title: 'Radar $page track $index',
        artistNames: const ['Radar artist'],
        durationSeconds: 180,
      ),
    );
    final radar = _ScriptedWidgetRadarGateway([
      RadarTrackPageResult(page: 1, tracks: tracks('home', 1)),
      RadarTrackPageResult(page: 1, hasMore: true, tracks: tracks('first', 20)),
      RadarTrackPageResult(page: 2, tracks: tracks('second', 10)),
    ]);
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          const RecommendedPlaylistPageResult(),
        ),
        radarGateway: radar,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-recommendations')));
    await tester.pumpAndSettle();
    await _selectAdaptiveSection(
      tester,
      control: 'discover-type-selector',
      item: 'discover-type-radar',
    );
    expect(radar.pages, [1, 1]);

    await tester.drag(
      find.byKey(const PageStorageKey<String>('radar-tracks')),
      const Offset(0, -480),
    );
    await tester.pumpAndSettle();

    expect(radar.pages, [1, 1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Radar manual continuation requests exactly one bounded page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<PlaylistTrackSummary> tracks(String page, int count) => List.generate(
      count,
      (index) => PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:manual-$page-$index',
        title: 'Manual Radar $page track $index',
        artistNames: const ['Radar artist'],
      ),
    );
    final radar = _ScriptedWidgetRadarGateway([
      RadarTrackPageResult(page: 1, tracks: tracks('home', 1)),
      RadarTrackPageResult(page: 1, hasMore: true, tracks: tracks('first', 1)),
      RadarTrackPageResult(page: 2, hasMore: true, tracks: tracks('second', 1)),
      RadarTrackPageResult(page: 3, hasMore: true, tracks: tracks('third', 1)),
      RadarTrackPageResult(page: 4, tracks: tracks('fourth', 1)),
    ]);
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          const RecommendedPlaylistPageResult(),
        ),
        radarGateway: radar,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-recommendations')));
    await tester.pumpAndSettle();
    await _selectAdaptiveSection(
      tester,
      control: 'discover-type-selector',
      item: 'discover-type-radar',
    );

    expect(radar.pages, [1, 1, 2, 3]);
    final loadMore = find.byKey(const ValueKey('radar-load-more'));
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    expect(radar.pages, [1, 1, 2, 3, 4]);
    expect(find.text('Manual Radar fourth track 0'), findsOneWidget);
    expect(find.byKey(const ValueKey('radar-load-more')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'favorite Albums keep labeled compact loading and empty states in Liked',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final albums = _ControlledWidgetFavoriteAlbumGateway();

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          favoriteAlbumGateway: albums,
          favoriteArtistGateway: _WidgetFavoriteArtistGateway(
            const FavoriteArtistPageResult(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _openLibrary(tester);
      await _selectLibrarySection(tester, 'albums');
      await tester.pump();

      expect(
        find.byKey(const ValueKey('favorite-albums-loading')),
        findsOneWidget,
      );
      expect(find.byType(MusicLoadingPanel), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('favorite-albums-loading')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == _en.favoriteAlbumsLoading,
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      albums.complete(const FavoriteAlbumPageResult());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('favorite-albums-empty')),
        findsOneWidget,
      );
      expect(find.byType(MusicContentStatePanel), findsOneWidget);
      expect(find.text(_en.favoriteAlbumsEmptyTitle), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'favorite Album failures keep one live region and exact recovery',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final albums = _ScriptedWidgetFavoriteAlbumGateway([
        const FavoriteAlbumPageResult(failure: FavoriteAlbumFailure.network),
        const FavoriteAlbumPageResult(),
      ]);

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          favoriteAlbumGateway: albums,
          favoriteArtistGateway: _WidgetFavoriteArtistGateway(
            const FavoriteArtistPageResult(
              failure: FavoriteArtistFailure.credentialRejected,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _openLibrary(tester);
      await _selectLibrarySection(tester, 'albums');

      final albumError = find.byKey(const ValueKey('favorite-albums-error'));
      expect(albumError, findsOneWidget);
      expect(find.byType(MusicContentStatePanel), findsOneWidget);
      expect(
        find.descendant(
          of: albumError,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Sign in again'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('favorite-albums-empty')),
        findsOneWidget,
      );
      expect(albums.requests, [(0, 20), (0, 20)]);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opens favorite Albums lazily and preserves the collection through playback return',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const album = AlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43001:fixtureFavoriteAlbumMid',
        title: 'Saved Album',
      );
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:fixtureTrackMid:-',
        title: 'Saved Album Track',
        artistNames: ['Saved Artist'],
      );
      final favorites = _WidgetFavoriteAlbumGateway(
        const FavoriteAlbumPageResult(total: 1, albums: [album]),
      );
      final albumTracks = _WidgetAlbumGateway(
        const AlbumTrackPageResult(total: 1, tracks: [track]),
      );
      final queue = _WidgetPlaybackQueueGateway();

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          favoriteAlbumGateway: favorites,
          albumTrackGateway: albumTracks,
          albumDetailsGateway: const _WidgetAlbumDetailsGateway(),
          playbackQueueGateway: queue,
          mediaResolutionGateway: const _UnavailableMediaGateway(),
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();

      await _openLibrary(tester);
      expect(favorites.requests, isEmpty);
      expect(find.byKey(const ValueKey('liked-songs-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('liked-songs-tabs')), findsOneWidget);
      expect(find.text('Library'), findsNothing);
      expect(tester.takeException(), isNull);
      await _selectLibrarySection(tester, 'albums');
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('favorite-albums-content')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('liked-albums-search')), findsOneWidget);
      expect(find.text('Saved Album'), findsOneWidget);
      expect(favorites.requests, [(0, 20)]);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('primary-home-destination')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isFalse);
      await _openLibrary(tester);
      expect(find.text('Saved Album'), findsOneWidget);
      expect(favorites.requests, [(0, 20)]);

      tester.view.physicalSize = const Size(1000, 700);
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      expect(favorites.requests, [(0, 20)]);

      await tester.tap(
        find.byKey(
          const ValueKey('favorite-album-album:43001:fixtureFavoriteAlbumMid'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved Album Track'), findsOneWidget);
      expect(albumTracks.requests.single.$1, album);
      expect(
        tester.widget<AlbumPage>(find.byType(AlbumPage)).onOpenArtist,
        isNotNull,
      );

      await tester.tap(find.text('Saved Album Track'));
      await tester.pump();
      expect(queue.replacements, hasLength(1));
      expect(queue.replacements.single.$1, [track]);
      expect(queue.replacements.single.$2, 0);

      await tester.tap(find.byTooltip('Back to favorite albums'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('favorite-albums-content')),
        findsOneWidget,
      );
      expect(find.text('Saved Album'), findsOneWidget);
      expect(favorites.requests, [(0, 20)]);

      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Liked does not expose the removed favorite-Artist root', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final favorites = _WidgetFavoriteArtistGateway(
      const FavoriteArtistPageResult(
        total: 1,
        artists: [
          ArtistSummary(
            providerId: 'qq-music',
            opaqueId: 'artist:-:fixtureFavoriteArtistMid',
            name: 'Saved Artist',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        favoriteArtistGateway: favorites,
      ),
    );
    await tester.pumpAndSettle();
    await _openLibrary(tester);

    expect(find.byKey(const ValueKey('liked-songs-page')), findsOneWidget);
    expect(find.text('Library'), findsNothing);
    expect(find.byKey(const ValueKey('library-section-artists')), findsNothing);
    expect(
      find.byKey(const ValueKey('favorite-artists-content')),
      findsNothing,
    );
    expect(favorites.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loads new albums lazily and preserves them through Album playback return',
    (tester) async {
      const captureCollectionDetails = bool.fromEnvironment(
        'COLLECTION_DETAIL_VISUAL_REVIEW',
      );
      await _loadRecentReviewFonts(tester, enabled: captureCollectionDetails);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const album = AlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43001:fixtureNewAlbumMid',
        title: 'Fresh Album',
      );
      const release = NewAlbumRelease(
        album: album,
        artists: [
          ArtistSummary(
            providerId: 'qq-music',
            opaqueId: 'artist:42001:fixtureArtistMid',
            name: 'Fresh Artist',
          ),
        ],
        releaseDate: '2026-08-26',
      );
      const longRelease = NewAlbumRelease(
        album: AlbumSummary(
          providerId: 'qq-music',
          opaqueId: 'album:43002:fixtureLongAlbumMid',
          title:
              'A deliberately long second album title that occupies two lines',
        ),
        artists: [
          ArtistSummary(
            providerId: 'qq-music',
            opaqueId: 'artist:42002:fixtureLongArtistMid',
            name: 'A very long independent artist collective name',
          ),
        ],
      );
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:fixtureTrackMid:-',
        title: 'Fresh Track',
        artistNames: ['Fresh Artist'],
      );
      final newAlbums = _WidgetNewAlbumGateway(
        const NewAlbumPageResult(
          region: NewAlbumRegion.mainlandChina,
          total: 2,
          releases: [release, longRelease],
        ),
      );
      final albumTracks = _WidgetAlbumGateway(
        const AlbumTrackPageResult(total: 1, tracks: [track]),
      );
      final queue = _WidgetPlaybackQueueGateway();

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
            const RecommendedPlaylistPageResult(),
          ),
          newAlbumGateway: newAlbums,
          albumTrackGateway: albumTracks,
          albumDetailsGateway: const _WidgetAlbumDetailsGateway(),
          playbackQueueGateway: queue,
          mediaResolutionGateway: const _UnavailableMediaGateway(),
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-recommendations')));
      await tester.pumpAndSettle();
      expect(newAlbums.requests, isEmpty);

      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-new-albums',
      );
      expect(find.byKey(const ValueKey('new-albums-content')), findsOneWidget);
      expect(find.text('Fresh Album'), findsOneWidget);
      expect(find.textContaining('Fresh Artist'), findsOneWidget);
      expect(newAlbums.requests, [(NewAlbumRegion.mainlandChina, 0, 20)]);

      final desktopArtwork0 = tester.getSize(
        find.byKey(const ValueKey('new-album-artwork-0')),
      );
      final desktopArtwork1 = tester.getSize(
        find.byKey(const ValueKey('new-album-artwork-1')),
      );
      expect(desktopArtwork0.width, closeTo(desktopArtwork0.height, 0.1));
      expect(desktopArtwork1, desktopArtwork0);

      tester.view.physicalSize = const Size(390, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      final compactArtwork0 = tester.getSize(
        find.byKey(const ValueKey('new-album-artwork-0')),
      );
      final compactArtwork1 = tester.getSize(
        find.byKey(const ValueKey('new-album-artwork-1')),
      );
      expect(compactArtwork0.width, closeTo(compactArtwork0.height, 0.1));
      expect(compactArtwork1, compactArtwork0);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1440, 900);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fresh Album'));
      await tester.pumpAndSettle();
      expect(find.text('Fresh Track'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop-music-sidebar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('embedded-album-detail')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('album-track-table-header')),
        findsOneWidget,
      );
      expect(albumTracks.requests.single.$1, album);
      expect(
        tester.widget<AlbumPage>(find.byType(AlbumPage)).onOpenArtist,
        isNotNull,
      );
      if (captureCollectionDetails) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-album-detail-desktop.png'),
          ),
        );
      }

      await tester.tap(find.text('Fresh Track'));
      await tester.pump();
      expect(queue.replacements, hasLength(1));
      expect(queue.replacements.single.$1, [track]);
      expect(queue.replacements.single.$2, 0);

      await tester.tap(find.byTooltip(_en.shellBackToNewAlbums));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-albums-content')), findsOneWidget);
      expect(find.text('Fresh Album'), findsOneWidget);
      expect(newAlbums.requests, [(NewAlbumRegion.mainlandChina, 0, 20)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loads Home and Discover new songs independently on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const latestTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:fixtureLatestMid:-',
        title: 'Latest Track',
        artistNames: ['Latest Artist'],
        albumTitle: 'Latest Album',
        durationSeconds: 201,
      );
      const japanTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41002:0:fixtureJapanMid:-',
        title: 'Japan Track',
        artistNames: ['Japan Artist'],
      );
      final newSongs = _WidgetNewSongGateway({
        NewSongCategory.latest: const NewSongResult(
          category: NewSongCategory.latest,
          tracks: [latestTrack],
        ),
        NewSongCategory.japan: const NewSongResult(
          category: NewSongCategory.japan,
          tracks: [japanTrack],
        ),
      });
      final queue = _WidgetPlaybackQueueGateway();

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
            const RecommendedPlaylistPageResult(),
          ),
          newSongGateway: newSongs,
          playbackQueueGateway: queue,
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();
      expect(newSongs.requests, [NewSongCategory.latest]);

      await tester.tap(find.byKey(const ValueKey('open-recommendations')));
      await tester.pumpAndSettle();
      expect(newSongs.requests, [NewSongCategory.latest]);

      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-new-songs',
      );
      expect(find.byKey(const ValueKey('new-songs-content')), findsOneWidget);
      expect(find.text('Latest Track'), findsOneWidget);
      expect(find.text('Latest Artist'), findsOneWidget);
      expect(find.text('Latest Album'), findsOneWidget);
      expect(find.text('3:21'), findsOneWidget);
      expect(newSongs.requests, [
        NewSongCategory.latest,
        NewSongCategory.latest,
      ]);

      await tester.tap(find.byKey(const ValueKey('new-song-context-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await tester.pump();
      expect(queue.pushed, [latestTrack]);
      await tester.tap(find.byKey(const ValueKey('new-song-track-0')));
      await tester.pump();
      expect(queue.replacements.single.$1, [latestTrack]);
      expect(queue.replacements.single.$2, 0);

      final japanCategory = find.byKey(
        const ValueKey('new-song-category-japan'),
      );
      await tester.ensureVisible(japanCategory);
      await tester.tap(japanCategory);
      await tester.pumpAndSettle();
      expect(find.text('Japan Track'), findsOneWidget);
      expect(newSongs.requests, [
        NewSongCategory.latest,
        NewSongCategory.latest,
        NewSongCategory.japan,
      ]);

      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-playlists',
      );
      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-new-songs',
      );
      expect(find.text('Japan Track'), findsOneWidget);
      expect(newSongs.requests, [
        NewSongCategory.latest,
        NewSongCategory.latest,
        NewSongCategory.japan,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('returns from Album to the preserved Search query and results', (
    tester,
  ) async {
    const album = AlbumSummary(
      providerId: 'qq-music',
      opaqueId: 'album:51001:fixtureAlbumMid',
      title: 'Synthetic album',
    );
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:fixtureMid:-',
      title: 'Synthetic track',
      artistNames: ['Artist'],
      albumTitle: 'Synthetic album',
    );
    final search = _WidgetSearchGateway(
      const TrackSearchPageResult(
        page: 1,
        total: 1,
        items: [TrackSearchItem(track: track, album: album)],
      ),
    );
    final albumTracks = _WidgetAlbumGateway(
      const AlbumTrackPageResult(offset: 0, total: 1, tracks: [track]),
    );
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        searchGateway: search,
        albumTrackGateway: albumTracks,
        albumDetailsGateway: const _WidgetAlbumDetailsGateway(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-track-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('track-search-field')),
      'album query',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(search.requests, [('album query', 1, 30)]);

    await tester.tap(find.byKey(const ValueKey('track-search-more-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-search-album-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('album-content')), findsOneWidget);
    expect(albumTracks.requests, [(album, 0, 30)]);

    await tester.tap(find.byKey(const ValueKey('album-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('track-search-content')), findsOneWidget);
    expect(find.text('Synthetic track'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('track-search-field')))
          .controller
          ?.text,
      'album query',
    );
    expect(search.requests, [('album query', 1, 30)]);
  });

  testWidgets('selects a credited Artist and preserves Search on return', (
    tester,
  ) async {
    const firstArtist = ArtistSummary(
      providerId: 'qq-music',
      opaqueId: 'artist:61001:firstArtistMid',
      name: 'First artist',
    );
    const secondArtist = ArtistSummary(
      providerId: 'qq-music',
      opaqueId: 'artist:61002:secondArtistMid',
      name: 'Second artist',
    );
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:fixtureMid:-',
      title: 'Synthetic collaboration',
      artistNames: ['First artist', 'Second artist'],
    );
    final search = _WidgetSearchGateway(
      const TrackSearchPageResult(
        page: 1,
        total: 1,
        items: [
          TrackSearchItem(track: track, artists: [firstArtist, secondArtist]),
        ],
      ),
    );
    final artistTracks = _WidgetArtistGateway(
      const ArtistTrackPageResult(offset: 0, total: 1, tracks: [track]),
    );
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        searchGateway: search,
        artistTrackGateway: artistTracks,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-track-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('track-search-field')),
      'artist query',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('track-search-more-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-search-artist-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-search-artist-0-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-content')), findsOneWidget);
    expect(artistTracks.requests, [(secondArtist, 0, 30)]);

    await tester.tap(find.byKey(const ValueKey('artist-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('track-search-content')), findsOneWidget);
    expect(find.text('Synthetic collaboration'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('track-search-field')))
          .controller
          ?.text,
      'artist query',
    );
    expect(search.requests, [('artist query', 1, 30)]);
  });

  testWidgets(
    'opens current Track catalog globally and restores the exact Search state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const currentAlbum = AlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43001:currentAlbumMid',
        title: 'Current Album',
      );
      const nestedAlbum = AlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43002:nestedAlbumMid',
        title: 'Nested Album',
      );
      const firstArtist = ArtistSummary(
        providerId: 'qq-music',
        opaqueId: 'artist:42001:firstArtistMid',
        name: 'First credit',
      );
      const secondArtist = ArtistSummary(
        providerId: 'qq-music',
        opaqueId: 'artist:42002:secondArtistMid',
        name: 'Second credit',
      );
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:currentTrackMid:-',
        title: 'Current Track',
        artistNames: ['First credit', 'Second credit'],
        artists: [firstArtist, secondArtist],
        albumTitle: 'Current Album',
        album: currentAlbum,
      );
      final search = _WidgetSearchGateway(
        const TrackSearchPageResult(
          page: 1,
          total: 1,
          items: [
            TrackSearchItem(
              track: track,
              artists: [firstArtist, secondArtist],
              album: currentAlbum,
            ),
          ],
        ),
      );
      final artistTracks = _WidgetArtistGateway(
        const ArtistTrackPageResult(total: 1, tracks: [track]),
      );
      final artistAlbums = _WidgetArtistAlbumGateway(
        const ArtistAlbumPageResult(total: 1, albums: [nestedAlbum]),
      );
      final albumTracks = _WidgetAlbumGateway(
        const AlbumTrackPageResult(total: 1, tracks: [track]),
      );
      final queue = _WidgetPlaybackQueueGateway();

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          searchGateway: search,
          artistTrackGateway: artistTracks,
          artistAlbumGateway: artistAlbums,
          albumTrackGateway: albumTracks,
          albumDetailsGateway: const _WidgetAlbumDetailsGateway(),
          playbackQueueGateway: queue,
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-track-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('track-search-field')),
        'current context query',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('track-search-result-0')));
      await tester.pumpAndSettle();
      expect(queue.replacements.single.$1, [track]);

      expect(
        find.byKey(const ValueKey('now-playing-catalog-action')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('expanded-now-playing-open-catalog')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('now-playing-catalog-selection')),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('now-playing-catalog-selection')),
          matching: find.byType(SafeArea),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('now-playing-catalog-selection')),
          matching: find.text('Current Album'),
        ),
        findsOneWidget,
      );
      expect(find.text('First credit'), findsWidgets);
      expect(find.text('Second credit'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('now-playing-open-artist-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('artist-content')), findsOneWidget);
      expect(artistTracks.requests, [(secondArtist, 0, 30)]);
      expect(
        find.byKey(const ValueKey('now-playing-catalog-action')),
        findsNothing,
      );

      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('artist-album-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('album-content')), findsOneWidget);
      expect(albumTracks.requests.single.$1, nestedAlbum);

      final albumBackHandled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(albumBackHandled, isTrue);
      expect(
        find.byKey(const ValueKey('artist-albums-content')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('artist-back')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('track-search-content')),
        findsOneWidget,
      );
      expect(find.text('Current Track'), findsWidgets);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('track-search-field')))
            .controller
            ?.text,
        'current context query',
      );
      expect(search.requests, [('current context query', 1, 30)]);
      expect(queue.replacements, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opens the only current Track catalog destination without a chooser',
    (tester) async {
      const album = AlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43001:onlyAlbumMid',
        title: 'Only Album',
      );
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:onlyTrackMid:-',
        title: 'Only-context Track',
        artistNames: ['Unidentified credit'],
        albumTitle: 'Only Album',
        album: album,
      );
      final search = _WidgetSearchGateway(
        const TrackSearchPageResult(
          page: 1,
          total: 1,
          items: [TrackSearchItem(track: track, album: album)],
        ),
      );
      final albumTracks = _WidgetAlbumGateway(
        const AlbumTrackPageResult(total: 1, tracks: [track]),
      );

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          searchGateway: search,
          albumTrackGateway: albumTracks,
          albumDetailsGateway: const _WidgetAlbumDetailsGateway(),
          playbackQueueGateway: _WidgetPlaybackQueueGateway(),
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-track-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('track-search-field')),
        'single destination query',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('track-search-result-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
      await tester.pumpAndSettle();
      final action = find.byKey(
        const ValueKey('expanded-now-playing-open-catalog'),
      );
      final semantics = tester.getSemantics(action);
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      var actionFocused = false;
      for (var attempt = 0; attempt < 24; attempt += 1) {
        final focusedContext = FocusManager.instance.primaryFocus?.context;
        if (focusedContext != null &&
            find
                .ancestor(
                  of: find.byElementPredicate(
                    (element) => identical(element, focusedContext),
                  ),
                  matching: action,
                )
                .evaluate()
                .isNotEmpty) {
          actionFocused = true;
          break;
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(actionFocused, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('now-playing-catalog-selection')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('album-content')), findsOneWidget);
      expect(albumTracks.requests.single.$1, album);
      await tester.tap(find.byKey(const ValueKey('album-back')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('track-search-content')),
        findsOneWidget,
      );
      expect(search.requests, [('single destination query', 1, 30)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'does not open stale catalog context after the current Track changes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const album = AlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43001:staleAlbumMid',
        title: 'Stale Album',
      );
      const artist = ArtistSummary(
        providerId: 'qq-music',
        opaqueId: 'artist:42001:staleArtistMid',
        name: 'Stale Artist',
      );
      const firstTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:staleTrackMid:-',
        title: 'Original Track',
        artistNames: ['Stale Artist'],
        artists: [artist],
        albumTitle: 'Stale Album',
        album: album,
      );
      const replacementTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41002:0:replacementTrackMid:-',
        title: 'Replacement Track',
        artistNames: ['Unidentified credit'],
      );
      final search = _WidgetSearchGateway(
        const TrackSearchPageResult(
          page: 1,
          total: 2,
          items: [
            TrackSearchItem(track: firstTrack, artists: [artist], album: album),
            TrackSearchItem(track: replacementTrack),
          ],
        ),
      );
      final queue = _WidgetPlaybackQueueGateway(mutatesOnAdvance: true);

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          searchGateway: search,
          mediaResolutionGateway: const _UnavailableMediaGateway(),
          playbackQueueGateway: queue,
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-track-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('track-search-field')),
        'stale context query',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('track-search-result-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('expanded-now-playing-open-catalog')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('now-playing-catalog-selection')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('now-playing-open-album')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('expanded-now-playing-page')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('album-content')), findsNothing);
      expect(find.byKey(const ValueKey('artist-content')), findsNothing);
      expect(find.text('Replacement Track'), findsWidgets);
      expect(
        find.byKey(const ValueKey('expanded-now-playing-open-catalog')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('expanded-now-playing-back')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('track-search-content')),
        findsOneWidget,
      );
      expect(search.requests, [('stale context query', 1, 30)]);
      expect(queue.replacements, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expands current Track on compact layout and preserves Search through clear',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const firstTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:51001:0:expandedFirstMid:-',
        title: 'Expanded First',
        artistNames: ['First Artist'],
        albumTitle: 'First Album',
      );
      const replacementTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:51002:0:expandedSecondMid:-',
        title: 'Expanded Replacement',
        artistNames: ['Second Artist'],
        albumTitle: 'Second Album',
      );
      final search = _WidgetSearchGateway(
        const TrackSearchPageResult(
          page: 1,
          total: 2,
          items: [
            TrackSearchItem(track: firstTrack),
            TrackSearchItem(track: replacementTrack),
          ],
        ),
      );
      final queue = _WidgetPlaybackQueueGateway(mutatesOnAdvance: true);

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          searchGateway: search,
          mediaResolutionGateway: const _UnavailableMediaGateway(),
          playbackQueueGateway: queue,
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-track-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('track-search-field')),
        'expanded compact query',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('track-search-result-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('expanded-now-playing-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expanded-now-playing-compact-layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expanded-now-playing-controls')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expanded-now-playing-compact-controls')),
        findsOneWidget,
      );
      expect(find.text('Expanded First'), findsWidgets);
      expect(find.text('First Album'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('expanded-now-playing-artwork')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('now-playing-artwork')), findsNothing);
      expect(find.byKey(const ValueKey('now-playing-title')), findsNothing);
      expect(find.byTooltip('Close lyrics'), findsNothing);
      expect(find.byTooltip('Show lyrics'), findsNothing);
      expect(find.byTooltip('Volume'), findsNothing);
      expect(
        find.byKey(const ValueKey('expanded-now-playing-compact-control-row')),
        findsOneWidget,
      );
      expect(find.byTooltip('Show queue'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('now-playing-open-expanded')),
        findsNothing,
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('now-playing-primary-action')),
        ),
        const Size(48, 48),
      );
      expect(tester.takeException(), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await tester.pumpAndSettle();
      expect(find.text('Expanded Replacement'), findsWidgets);
      expect(find.text('Second Album'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('now-playing-show-queue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('queue-clear')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('queue-clear-confirmation-sheet')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('queue-clear-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close queue'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('expanded-now-playing-empty')),
        findsOneWidget,
      );
      expect(find.text('Nothing is playing'), findsOneWidget);
      expect(find.byKey(const ValueKey('now-playing-title')), findsNothing);

      final backHandled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(backHandled, isTrue);
      expect(
        find.byKey(const ValueKey('track-search-content')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('track-search-field')))
            .controller
            ?.text,
        'expanded compact query',
      );
      expect(search.requests, [('expanded compact query', 1, 30)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opens immersive now playing with desktop keyboard and returns exactly',
    (tester) async {
      const captureTransition = bool.fromEnvironment(
        'NOW_PLAYING_TRANSITION_VISUAL_REVIEW',
      );
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:52001:0:expandedDesktopMid:-',
        title: 'Expanded Desktop Track',
        artistNames: ['Desktop Artist'],
        albumTitle: 'Desktop Album',
      );
      final search = _WidgetSearchGateway(
        const TrackSearchPageResult(
          page: 1,
          total: 1,
          items: [TrackSearchItem(track: track)],
        ),
      );

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          searchGateway: search,
          playbackQueueGateway: _WidgetPlaybackQueueGateway(),
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-track-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('track-search-field')),
        'expanded desktop query',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('track-search-result-0')));
      await tester.pumpAndSettle();

      final action = find.byKey(const ValueKey('now-playing-open-expanded'));
      expect(
        tester
            .getSemantics(action)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      var actionFocused = false;
      for (var attempt = 0; attempt < 24; attempt += 1) {
        final focusedContext = FocusManager.instance.primaryFocus?.context;
        if (focusedContext != null &&
            find
                .ancestor(
                  of: find.byElementPredicate(
                    (element) => identical(element, focusedContext),
                  ),
                  matching: action,
                )
                .evaluate()
                .isNotEmpty) {
          actionFocused = true;
          break;
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(actionFocused, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      final expandedPage = find.byKey(
        const ValueKey('expanded-now-playing-page'),
      );
      final enteringTop = tester.getTopLeft(expandedPage).dy;
      expect(enteringTop, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 180));
      final enteringMidpoint = tester.getTopLeft(expandedPage).dy;
      expect(enteringMidpoint, lessThan(enteringTop));
      expect(enteringMidpoint, greaterThan(0));
      if (captureTransition) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-now-playing-enter.png'),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(expandedPage).dy, 0);

      expect(
        find.byKey(const ValueKey('expanded-now-playing-wide-layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expanded-now-playing-controls')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expanded-now-playing-wide-controls')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expanded-now-playing-artwork')),
        findsOneWidget,
      );
      expect(find.text('Expanded Desktop Track'), findsWidgets);
      expect(find.text('Desktop Album'), findsOneWidget);
      expect(find.byKey(const ValueKey('now-playing-artwork')), findsNothing);
      expect(find.byKey(const ValueKey('now-playing-title')), findsNothing);
      expect(find.byTooltip('Show lyrics'), findsNothing);
      expect(find.byTooltip('Volume'), findsOneWidget);
      expect(find.byTooltip('Show queue'), findsOneWidget);
      expect(
        tester.getSize(
          find.byKey(const ValueKey('now-playing-primary-action')),
        ),
        const Size(56, 56),
      );
      expect(
        find.byKey(const ValueKey('now-playing-open-expanded')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('expanded-now-playing-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(expandedPage, findsOneWidget);
      expect(tester.getTopLeft(expandedPage).dy, greaterThan(0));
      if (captureTransition) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-now-playing-exit.png'),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(expandedPage, findsNothing);
      expect(
        find.byKey(const ValueKey('track-search-content')),
        findsOneWidget,
      );
      expect(search.requests, [('expanded desktop query', 1, 30)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opens a direct Artist result and preserves Artist Search', (
    tester,
  ) async {
    const artist = ArtistSummary(
      providerId: 'qq-music',
      opaqueId: 'artist:61001:fixtureArtistMid',
      name: 'Direct Artist',
    );
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:fixtureMid:-',
      title: 'Artist Track',
      artistNames: ['Direct Artist'],
    );
    final artistSearch = _WidgetArtistSearchGateway(
      const ArtistSearchPageResult(page: 1, total: 1, artists: [artist]),
    );
    final artistTracks = _WidgetArtistGateway(
      const ArtistTrackPageResult(offset: 0, total: 1, tracks: [track]),
    );
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        searchGateway: const _UnusedSearchGateway(),
        artistSearchGateway: artistSearch,
        artistTrackGateway: artistTracks,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-track-search')));
    await tester.pumpAndSettle();
    await _selectAdaptiveSection(
      tester,
      control: 'search-types',
      item: 'search-type-artists',
    );
    await tester.enterText(
      find.byKey(const ValueKey('track-search-field')),
      'direct Artist query',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(artistSearch.requests, [('direct Artist query', 1, 30)]);
    await tester.tap(find.byKey(const ValueKey('artist-search-result-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-content')), findsOneWidget);
    expect(artistTracks.requests, [(artist, 0, 30)]);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('artist-back')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('artist-search-content')), findsOneWidget);
    expect(find.text('Direct Artist'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('track-search-field')))
          .controller
          ?.text,
      'direct Artist query',
    );
    expect(artistSearch.requests, [('direct Artist query', 1, 30)]);
  });

  testWidgets('opens a direct Album result and preserves Album Search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const album = AlbumSummary(
      providerId: 'qq-music',
      opaqueId: 'album:43001:fixtureAlbumMid',
      title: 'Direct Album',
    );
    const artist = ArtistSummary(
      providerId: 'qq-music',
      opaqueId: 'artist:42001:directAlbumArtistMid',
      name: 'Direct Album Artist',
    );
    const nestedAlbum = AlbumSummary(
      providerId: 'qq-music',
      opaqueId: 'album:43002:nestedAlbumMid',
      title: 'Nested Artist Album',
    );
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:fixtureMid:-',
      title: 'Album Track',
      artistNames: ['Album Artist'],
    );
    final albumSearch = _WidgetAlbumSearchGateway(
      const AlbumSearchPageResult(page: 1, total: 1, albums: [album]),
    );
    final albumTracks = _WidgetAlbumGateway(
      const AlbumTrackPageResult(offset: 0, total: 1, tracks: [track]),
    );
    final artistTracks = _WidgetArtistGateway(
      const ArtistTrackPageResult(offset: 0, total: 1, tracks: [track]),
    );
    final artistAlbums = _WidgetArtistAlbumGateway(
      const ArtistAlbumPageResult(offset: 0, total: 1, albums: [nestedAlbum]),
    );
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        searchGateway: const _UnusedSearchGateway(),
        albumSearchGateway: albumSearch,
        albumTrackGateway: albumTracks,
        albumDetailsGateway: const _WidgetAlbumDetailsGateway(
          artists: [artist],
        ),
        artistTrackGateway: artistTracks,
        artistAlbumGateway: artistAlbums,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-track-search')));
    await tester.pumpAndSettle();
    await _selectAdaptiveSection(
      tester,
      control: 'search-types',
      item: 'search-type-albums',
    );
    await tester.enterText(
      find.byKey(const ValueKey('track-search-field')),
      'direct Album query',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(albumSearch.requests, [('direct Album query', 1, 30)]);
    await tester.tap(find.byKey(const ValueKey('album-search-result-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('album-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-music-sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('embedded-album-detail')), findsOneWidget);
    expect(albumTracks.requests, [(album, 0, 30)]);
    expect(
      tester.widget<AlbumPage>(find.byType(AlbumPage)).onOpenArtist,
      isNotNull,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('album-open-artist')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-content')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('embedded-artist-detail')),
      findsOneWidget,
    );
    expect(artistTracks.requests, [(artist, 0, 30)]);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-albums-content')), findsOneWidget);
    expect(artistAlbums.requests, [(artist, 0, 30)]);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('artist-album-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('album-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-music-sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('embedded-album-detail')), findsOneWidget);
    expect(albumTracks.requests, [(album, 0, 30), (nestedAlbum, 0, 30)]);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip(_en.shellBackToArtist));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-albums-content')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.byKey(const ValueKey('album-content')), findsOneWidget);
    expect(find.text('Direct Album'), findsOneWidget);
    expect(albumTracks.requests, [(album, 0, 30), (nestedAlbum, 0, 30)]);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('album-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('album-search-content')), findsOneWidget);
    expect(find.text('Direct Album'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('track-search-field')))
          .controller
          ?.text,
      'direct Album query',
    );
    expect(albumSearch.requests, [('direct Album query', 1, 30)]);
  });

  testWidgets(
    'opens a direct Playlist result and preserves Playlist Search on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const playlist = UserPlaylistSummary(
        providerId: 'qq-music',
        opaqueId: 'catalog:81001',
        title: 'Direct Playlist',
        trackCount: 1,
      );
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:fixtureMid:-',
        title: 'Playlist Track',
        artistNames: ['Playlist Artist'],
      );
      final playlistSearch = _WidgetPlaylistSearchGateway(
        const PlaylistSearchPageResult(
          page: 1,
          total: 1,
          playlists: [playlist],
        ),
      );
      final playlistDetail = _WidgetDetailGateway([
        const PlaylistTrackPageResult(offset: 0, total: 1, tracks: [track]),
      ]);
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          searchGateway: const _UnusedSearchGateway(),
          playlistSearchGateway: playlistSearch,
          playlistDetailGateway: playlistDetail,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-track-search')));
      await tester.pumpAndSettle();
      await _selectAdaptiveSection(
        tester,
        control: 'search-types',
        item: 'search-type-playlists',
      );
      await tester.enterText(
        find.byKey(const ValueKey('track-search-field')),
        'direct Playlist query',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(playlistSearch.requests, [('direct Playlist query', 1, 30)]);
      await tester.tap(find.byKey(const ValueKey('playlist-search-result-0')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('playlist-detail-content')),
        findsOneWidget,
      );
      expect(playlistDetail.requests.single.playlist.opaqueId, 'catalog:81001');
      expect(find.text('Playlist Track'), findsOneWidget);
      expect(
        tester
            .widget<PlaylistDetailPage>(find.byType(PlaylistDetailPage))
            .onOpenAlbum,
        isNotNull,
      );
      expect(
        tester
            .widget<PlaylistDetailPage>(find.byType(PlaylistDetailPage))
            .onOpenArtist,
        isNotNull,
      );

      await tester.tap(find.byKey(const ValueKey('playlist-detail-back')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('playlist-search-content')),
        findsOneWidget,
      );
      expect(find.text('Direct Playlist'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('track-search-field')))
            .controller
            ?.text,
        'direct Playlist query',
      );
      expect(playlistSearch.requests, [('direct Playlist query', 1, 30)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nests Album navigation inside a preserved Artist and Search', (
    tester,
  ) async {
    const artist = ArtistSummary(
      providerId: 'qq-music',
      opaqueId: 'artist:61001:fixtureArtistMid',
      name: 'Synthetic artist',
    );
    const album = AlbumSummary(
      providerId: 'qq-music',
      opaqueId: 'album:51001:fixtureAlbumMid',
      title: 'Artist album',
    );
    const searchTrack = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:searchMid:-',
      title: 'Search track',
      artistNames: ['Synthetic artist'],
    );
    const albumTrack = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41002:0:albumMid:-',
      title: 'Album track',
      artistNames: ['Synthetic artist'],
      albumTitle: 'Artist album',
    );
    final search = _WidgetSearchGateway(
      const TrackSearchPageResult(
        page: 1,
        total: 1,
        items: [
          TrackSearchItem(track: searchTrack, artists: [artist]),
        ],
      ),
    );
    final artistTracks = _WidgetArtistGateway(
      const ArtistTrackPageResult(offset: 0, total: 1, tracks: [searchTrack]),
    );
    final artistAlbums = _WidgetArtistAlbumGateway(
      const ArtistAlbumPageResult(offset: 0, total: 1, albums: [album]),
    );
    final albumTracks = _WidgetAlbumGateway(
      const AlbumTrackPageResult(offset: 0, total: 1, tracks: [albumTrack]),
    );
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        searchGateway: search,
        artistTrackGateway: artistTracks,
        artistAlbumGateway: artistAlbums,
        albumTrackGateway: albumTracks,
        albumDetailsGateway: const _WidgetAlbumDetailsGateway(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-track-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('track-search-field')),
      'nested query',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-search-more-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-search-artist-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-content')), findsOneWidget);
    expect(artistAlbums.requests, isEmpty);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-albums-content')), findsOneWidget);
    expect(artistAlbums.requests, [(artist, 0, 30)]);

    await tester.tap(find.byKey(const ValueKey('artist-album-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('album-content')), findsOneWidget);
    expect(find.text('Album track'), findsOneWidget);
    expect(albumTracks.requests, [(album, 0, 30)]);

    await tester.tap(find.byTooltip(_en.shellBackToArtist));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-albums-content')), findsOneWidget);
    expect(find.text('Artist album'), findsOneWidget);
    expect(artistAlbums.requests, [(artist, 0, 30)]);

    await tester.tap(find.byKey(const ValueKey('artist-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('track-search-content')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('track-search-field')))
          .controller
          ?.text,
      'nested query',
    );
    expect(search.requests, [('nested query', 1, 30)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('routes verified startup restore into Home', (tester) async {
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          verificationOperation: const _ImmediateWidgetVerification(
            CredentialVerificationResult.authenticated,
          ),
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        initialCredentialRestore: CredentialRestoreResult.verificationRequired,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(find.byKey(const ValueKey('authentication-dialog')), findsNothing);
    expect(find.text('No playlists yet'), findsNothing);
  });

  testWidgets('updates desktop sidebar when the library load completes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = _PendingWidgetLibraryGateway();

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: library,
      ),
    );
    await tester.pump();

    expect(find.text('Appears without another click'), findsNothing);
    library.complete(
      const UserLibraryResult(
        playlists: [
          UserPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'owned:7002:202',
            title: 'Appears without another click',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Appears without another click'), findsOneWidget);
    expect(library.loadCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders user playlists without overflow on a narrow screen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            playlists: [
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'owned:7002:202',
                title: 'Narrow playlist',
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await _openPlaylists(tester);
    expect(find.text('Narrow playlist'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-playlist-table-header')),
      findsNothing,
    );
    final playlistSemantics = tester.getSemantics(find.text('Narrow playlist'));
    expect(
      playlistSemantics.label,
      _en.likedPlaylistSemantics('Narrow playlist'),
    );
    expect(
      playlistSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the desktop shell while opening a playlist detail', (
    tester,
  ) async {
    await _loadRecentReviewFonts(tester);
    const captureReviewImages = bool.fromEnvironment('SHELL_NAV_VISUAL_REVIEW');
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const playlist = UserPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'favorite:shell-playlist',
      title: 'Shell playlist',
      trackCount: 1,
    );
    final detailResult = PlaylistTrackPageResult(
      total: 12,
      tracks: List.generate(
        12,
        (index) => PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:shell-playlist:$index',
          title: index == 0 ? 'Shell track' : 'Shell track ${index + 1}',
          artistNames: const ['Shell artist'],
          albumTitle: 'Shell album ${index + 1}',
          durationSeconds: 185,
        ),
      ),
    );
    final detailGateway = _WidgetDetailGateway([detailResult, detailResult]);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(playlists: [playlist]),
        ]),
        playlistDetailGateway: detailGateway,
      ),
    );
    await tester.pumpAndSettle();
    final likedTile = find.descendant(
      of: find.byKey(const ValueKey('open-liked-songs')),
      matching: find.byType(ListTile),
    );
    final selectedPlaylist = find.byKey(
      const ValueKey('sidebar-playlist-favorite:shell-playlist'),
    );
    await tester.tap(find.byKey(const ValueKey('open-liked-songs')));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(likedTile).selected, isTrue);
    await tester.tap(selectedPlaylist);
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byKey(const ValueKey('shell-detail-transition')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('desktop-music-sidebar')), findsOneWidget);
    expect(tester.widget<ListTile>(likedTile).selected, isFalse);
    expect(tester.widget<ListTile>(selectedPlaylist).selected, isTrue);
    final playlistSurface = find.byKey(
      const ValueKey('collection-detail-opaque-surface'),
    );
    expect(playlistSurface, findsOneWidget);
    expect(
      tester.widget<Material>(playlistSurface).color,
      Theme.of(tester.element(playlistSurface)).scaffoldBackgroundColor,
    );
    expect(
      find.descendant(
        of: playlistSurface,
        matching: find.byKey(const ValueKey('embedded-playlist-detail')),
      ),
      findsOneWidget,
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-playlist-shell-transition.png'),
        ),
      );
    }
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('embedded-playlist-detail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('playlist-detail-table-header')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('playlist-track-row-1')), findsOneWidget);
    expect(find.text('Shell track'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('embedded-playlist-detail')),
        matching: find.byKey(const ValueKey('locate-current-track')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('authenticated-primary-shell')),
      findsOneWidget,
    );
    final expandedArtwork = tester.getSize(
      find.byKey(const ValueKey('collection-detail-artwork')),
    );
    final expandedSearchCenter = tester.getCenter(
      find.byKey(const ValueKey('top-search-shortcut')),
    );
    final detailList = find.byKey(
      const PageStorageKey<String>('playlist-detail-track-list'),
    );
    final detailScroll = tester
        .state<ScrollableState>(
          find.descendant(of: detailList, matching: find.byType(Scrollable)),
        )
        .position;
    detailScroll.jumpTo(180);
    await tester.pumpAndSettle();
    final collapsedArtwork = tester.getSize(
      find.byKey(const ValueKey('collection-detail-artwork')),
    );
    expect(collapsedArtwork.width, lessThan(expandedArtwork.width));
    expect(collapsedArtwork.width, lessThan(100));
    expect(
      find.byKey(const ValueKey('shell-top-bar-title-Shell playlist')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('collection-detail-shell-back')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('collection-detail-shell-refresh')),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('top-search-shortcut'))),
      expandedSearchCenter,
    );
    final refreshRect = tester.getRect(
      find.byKey(const ValueKey('collection-detail-shell-refresh')),
    );
    final searchRect = tester.getRect(
      find.byKey(const ValueKey('top-search-shortcut')),
    );
    expect(refreshRect.left, greaterThan(searchRect.right));
    expect(refreshRect.right, greaterThan(tester.view.physicalSize.width - 64));
    await tester.tap(
      find.byKey(const ValueKey('collection-detail-shell-refresh')),
    );
    await tester.pumpAndSettle();
    expect(detailGateway.requests, hasLength(2));
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-playlist-shell-desktop-collapsed.png'),
        ),
      );
    }

    // At the exact medium-layout handoff, the page-local toolbar must already
    // be gone before the Shell Back/Refresh controls become interactive.
    detailScroll.jumpTo(0);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(700, 404);
    await tester.pumpAndSettle();
    final mediumDetailScroll = tester
        .state<ScrollableState>(
          find.descendant(of: detailList, matching: find.byType(Scrollable)),
        )
        .position;
    mediumDetailScroll.jumpTo(80);
    await tester.pumpAndSettle();
    expect(mediumDetailScroll.pixels, greaterThanOrEqualTo(72));
    expect(
      find.byKey(const ValueKey('collection-detail-shell-back')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('collection-detail-shell-back')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('playlist-detail-back')).hitTestable(),
      findsNothing,
    );
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('collection-detail-local-toolbar-region'),
            ),
          )
          .height,
      0,
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-playlist-shell-medium-handoff.png'),
        ),
      );
    }

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('desktop-music-sidebar')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      find.byKey(const ValueKey('embedded-playlist-detail')),
      findsOneWidget,
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-playlist-shell-mobile.png'),
        ),
      );
    }

    await tester.tap(find.byKey(const ValueKey('primary-home-destination')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('embedded-playlist-detail')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(detailGateway.requests, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens an adaptive playlist detail and returns to the library', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detailGateway = _WidgetDetailGateway([
      const PlaylistTrackPageResult(
        total: 2,
        hasMore: true,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:41001:0:1:opaque-mid',
            title: 'Synthetic track',
            subtitle: 'Fixture version',
            artistNames: ['Artist one', 'Artist two'],
            artists: [
              ArtistSummary(
                providerId: 'qq-music',
                opaqueId: 'artist:42001:artistOneMid',
                name: 'Artist one',
              ),
              ArtistSummary(
                providerId: 'qq-music',
                opaqueId: 'artist:42002:artistTwoMid',
                name: 'Artist two',
              ),
            ],
            albumTitle: 'Synthetic album',
            album: AlbumSummary(
              providerId: 'qq-music',
              opaqueId: 'album:43001:fixtureAlbumMid',
              title: 'Synthetic album',
            ),
            durationSeconds: 245,
          ),
        ],
      ),
      const PlaylistTrackPageResult(
        offset: 1,
        total: 2,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:41002:0:1:second-mid',
            title: 'Second synthetic track',
            artistNames: ['Artist three'],
            durationSeconds: 120,
          ),
        ],
      ),
    ]);
    final albumGateway = _WidgetAlbumGateway(
      const AlbumTrackPageResult(
        total: 1,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:album-context',
            title: 'Album context track',
            artistNames: ['Artist one'],
          ),
        ],
      ),
    );
    final artistGateway = _WidgetArtistGateway(
      const ArtistTrackPageResult(
        total: 1,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:artist-context',
            title: 'Artist context track',
            artistNames: ['Artist two'],
          ),
        ],
      ),
    );
    final artistAlbumGateway = _WidgetArtistAlbumGateway(
      const ArtistAlbumPageResult(
        total: 1,
        albums: [
          AlbumSummary(
            providerId: 'qq-music',
            opaqueId: 'album:43002:artistAlbumMid',
            title: 'Artist context album',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            playlists: [
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'favorite:8001',
                title: 'Open me',
                trackCount: 2,
              ),
            ],
          ),
        ]),
        playlistDetailGateway: detailGateway,
        albumTrackGateway: albumGateway,
        albumDetailsGateway: const _WidgetAlbumDetailsGateway(),
        artistTrackGateway: artistGateway,
        artistAlbumGateway: artistAlbumGateway,
      ),
    );
    await tester.pumpAndSettle();
    await _openPlaylists(tester);
    await tester.tap(find.text('Open me').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Synthetic track'), findsOneWidget);
    expect(find.textContaining('Artist one'), findsOneWidget);
    expect(find.text('4:05'), findsOneWidget);
    expect(find.text(_en.libraryShowingTracks(1, 2)), findsOneWidget);
    expect(find.text('Load more'), findsOneWidget);
    expect(detailGateway.requests.single.playlist.opaqueId, 'favorite:8001');
    expect(detailGateway.requests.single.offset, 0);
    expect(tester.takeException(), isNull);

    await tester.longPress(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    expect(find.text('Open album'), findsOneWidget);
    await tester.tap(find.text('Open album'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back to playlist'), findsOneWidget);
    expect(find.text('Album context track'), findsOneWidget);
    expect(
      tester.widget<AlbumPage>(find.byType(AlbumPage)).onOpenArtist,
      isNotNull,
    );
    expect(
      albumGateway.requests.single.$1.opaqueId,
      'album:43001:fixtureAlbumMid',
    );
    expect(detailGateway.requests, hasLength(1));

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.textContaining('Synthetic track'), findsOneWidget);
    expect(detailGateway.requests, hasLength(1));

    await tester.longPress(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    expect(find.text('Open artist'), findsOneWidget);
    await tester.tap(find.text('Open artist'));
    await tester.pumpAndSettle();
    expect(find.text(_en.albumChooseArtistTitle), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlist-track-artist-1')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back to playlist'), findsOneWidget);
    expect(find.text('Artist context track'), findsOneWidget);
    expect(
      artistGateway.requests.single.$1.opaqueId,
      'artist:42002:artistTwoMid',
    );
    expect(detailGateway.requests, hasLength(1));

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.text('Artist context album'), findsOneWidget);
    expect(artistAlbumGateway.requests, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('artist-album-0')));
    await tester.pumpAndSettle();
    expect(find.byTooltip(_en.shellBackToArtist), findsOneWidget);
    expect(albumGateway.requests, hasLength(2));
    await tester.tap(find.byTooltip(_en.shellBackToArtist));
    await tester.pumpAndSettle();
    expect(find.text('Artist context album'), findsOneWidget);
    final artistHandled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(artistHandled, isTrue);
    expect(find.textContaining('Synthetic track'), findsOneWidget);
    expect(detailGateway.requests, hasLength(1));

    await tester.drag(
      find.byKey(const PageStorageKey<String>('playlist-detail-track-list')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Second synthetic track'), findsOneWidget);
    expect(find.text('Showing 2 of 2 tracks'), findsOneWidget);
    expect(find.text('End of playlist'), findsOneWidget);
    expect(detailGateway.requests[1].offset, 1);

    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    final firstRow = find.byKey(const ValueKey('playlist-track-row-1'));
    final firstRowInk = find
        .descendant(of: firstRow, matching: find.byType(InkWell))
        .first;
    tester.widget<InkWell>(firstRowInk).focusNode?.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('Open album'), findsOneWidget);
    expect(find.text('Open artist'), findsOneWidget);
    await tester.tap(find.text('Open artist'));
    await tester.pumpAndSettle();
    expect(find.text(_en.albumChooseArtistTitle), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlist-track-artist-0')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back to playlist'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to playlist'));
    await tester.pumpAndSettle();

    await tester.tap(
      firstRow,
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('Open album'), findsOneWidget);
    await tester.tap(find.text('Open album'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back to playlist'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to playlist'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Second synthetic track'), findsOneWidget);
    expect(detailGateway.requests, hasLength(2));

    await tester.tap(find.byTooltip('Back to playlists'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('liked-songs-page')), findsOneWidget);
  });

  testWidgets('system and desktop back return to the existing library', (
    tester,
  ) async {
    final libraryGateway = _WidgetLibraryGateway([
      const UserLibraryResult(
        playlists: [
          UserPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'favorite:system-back',
            title: 'System back playlist',
          ),
        ],
      ),
    ]);
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: libraryGateway,
        playlistDetailGateway: _WidgetDetailGateway(
          List.filled(
            3,
            const PlaylistTrackPageResult(
              total: 1,
              tracks: [
                PlaylistTrackSummary(
                  providerId: 'qq-music',
                  opaqueId: 'track:system-back',
                  title: 'System back track',
                  artistNames: [],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openPlaylists(tester);
    await tester.tap(find.text('System back playlist').last);
    await tester.pumpAndSettle();
    expect(find.text('System back track'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.byKey(const ValueKey('liked-songs-page')), findsOneWidget);
    expect(find.text('System back playlist'), findsOneWidget);
    expect(libraryGateway._next, 1);
    expect(find.text('System back track'), findsNothing);
    final playlistAction = find.ancestor(
      of: find.text('System back playlist'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(playlistAction).focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('System back track'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('liked-songs-page')), findsOneWidget);
    expect(tester.widget<InkWell>(playlistAction).focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('System back track'), findsOneWidget);
    await tester.sendKeyEvent(
      LogicalKeyboardKey.browserBack,
      platform: 'windows',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('liked-songs-page')), findsOneWidget);
    expect(libraryGateway._next, 1);
    expect(tester.widget<InkWell>(playlistAction).focusNode?.hasFocus, isTrue);
  });

  testWidgets('detail return preserves desktop playlist position and focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playlists = List.generate(
      30,
      (index) => UserPlaylistSummary(
        providerId: 'qq-music',
        opaqueId: 'favorite:scroll-$index',
        title: 'Playlist $index',
      ),
    );

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          UserLibraryResult(playlists: playlists),
        ]),
        playlistDetailGateway: _WidgetDetailGateway([
          const PlaylistTrackPageResult(),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await _openPlaylists(tester);
    final list = find.byKey(
      const PageStorageKey<String>('liked-playlists-grid'),
    );
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    final desktopScrollState = tester.state<ScrollableState>(scrollable);
    desktopScrollState.position.jumpTo(
      desktopScrollState.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    await tester.tap(find.text('Playlist 29'));
    await tester.pumpAndSettle();
    expect(find.text('This playlist is empty'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to playlists'));
    await tester.pumpAndSettle();

    final after = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(after, moreOrLessEquals(before, epsilon: 1));
    final playlistAction = find.ancestor(
      of: find.text('Playlist 29'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(playlistAction).focusNode?.hasFocus, isTrue);
  });

  testWidgets('detail return preserves narrow playlist position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playlists = List.generate(
      30,
      (index) => UserPlaylistSummary(
        providerId: 'qq-music',
        opaqueId: 'favorite:narrow-scroll-$index',
        title: 'Narrow playlist $index',
      ),
    );

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          UserLibraryResult(playlists: playlists),
        ]),
        playlistDetailGateway: _WidgetDetailGateway([
          const PlaylistTrackPageResult(),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await _openPlaylists(tester);
    final list = find.byKey(
      const PageStorageKey<String>('liked-playlists-grid'),
    );
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    final mobileScrollState = tester.state<ScrollableState>(scrollable);
    mobileScrollState.position.jumpTo(
      mobileScrollState.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    await tester.tap(find.text('Narrow playlist 29'));
    await tester.pumpAndSettle();
    expect(find.text('This playlist is empty'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to playlists'));
    await tester.pumpAndSettle();

    final after = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(after, moreOrLessEquals(before, epsilon: 1));
    expect(find.text('Narrow playlist 29'), findsOneWidget);
  });

  testWidgets('failed detail refresh keeps tracks visible and retries', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detailGateway = _WidgetDetailGateway([
      const PlaylistTrackPageResult(
        total: 1,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:current',
            title: 'Current track',
            artistNames: ['Current artist'],
          ),
        ],
      ),
      const PlaylistTrackPageResult(failure: UserLibraryFailure.network),
      const PlaylistTrackPageResult(
        total: 1,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:fresh',
            title: 'Fresh track',
            artistNames: ['Fresh artist'],
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            playlists: [
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'favorite:refresh',
                title: 'Refresh me',
              ),
            ],
          ),
        ]),
        playlistDetailGateway: detailGateway,
      ),
    );
    await tester.pumpAndSettle();
    await _openPlaylists(tester);
    await tester.tap(find.text('Refresh me').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Refresh playlist'));
    await tester.pumpAndSettle();

    expect(find.text('Current track'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('playlist-detail-refresh-failure')),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('playlist-detail-refresh-failure')),
          )
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
    expect(find.text(_en.libraryRefreshPlaylistFailure), findsOneWidget);
    expect(find.text('Couldn’t reach QQ Music'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('library-refresh-retry')));
    await tester.pumpAndSettle();

    expect(find.text('Fresh track'), findsOneWidget);
    expect(find.text('Current track'), findsNothing);
    expect(
      find.byKey(const ValueKey('playlist-detail-refresh-failure')),
      findsNothing,
    );
  });

  testWidgets('playlist detail keeps safe rows when one raw row is omitted', (
    tester,
  ) async {
    const playlist = UserPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'favorite:partial-playlist',
      title: 'Partial playlist',
    );
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(playlists: [playlist]),
        ]),
        playlistDetailGateway: _WidgetDetailGateway([
          const PlaylistTrackPageResult(
            nextOffset: 3,
            total: 3,
            omittedTrackCount: 1,
            tracks: [
              PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:partial:a',
                title: 'Safe playlist track A',
                artistNames: ['Artist A'],
              ),
              PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:partial:b',
                title: 'Safe playlist track B',
                artistNames: ['Artist B'],
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await _openPlaylists(tester);
    await tester.tap(find.text('Partial playlist').last);
    await tester.pumpAndSettle();

    expect(find.text('Safe playlist track A'), findsOneWidget);
    expect(find.text('Safe playlist track B'), findsOneWidget);
    expect(find.text(_en.partialResultsNotice(1)), findsOneWidget);
    expect(find.byKey(const ValueKey('playlist-detail-error')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries a transient library failure', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(failure: UserLibraryFailure.network),
          const UserLibraryResult(),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await _openLibrary(tester);
    expect(find.text('Couldn’t reach QQ Music'), findsOneWidget);
    expect(find.text('Sign in again'), findsNothing);
    final failureSemantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Couldn’t reach QQ Music')),
    );
    expect(failureSemantics.label, contains('Couldn’t reach QQ Music'));
    expect(
      failureSemantics.getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(
      failureSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text(_en.libraryNoPlaylistsTitle), findsOneWidget);
  });

  testWidgets('transient detail failure does not discard the active session', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            playlists: [
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'favorite:transient-detail',
                title: 'Transient detail',
              ),
            ],
          ),
        ]),
        playlistDetailGateway: _WidgetDetailGateway([
          const PlaylistTrackPageResult(failure: UserLibraryFailure.network),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await _openPlaylists(tester);
    await tester.tap(find.text('Transient detail').last);
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t reach QQ Music'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Sign in again'), findsNothing);
    expect(find.byTooltip('Back to playlists'), findsOneWidget);
    final failureSemantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Couldn’t reach QQ Music')),
    );
    expect(failureSemantics.label, contains('Couldn’t reach QQ Music'));
    expect(
      failureSemantics.getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(
      failureSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets(
    'Liked fallback keeps playlists when its built-in list is absent',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([
            const UserLibraryResult(
              playlists: [
                UserPlaylistSummary(
                  providerId: 'qq-music',
                  opaqueId: 'favorite:current',
                  title: 'Current library',
                ),
              ],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await _openLibrary(tester);
      expect(
        find.byKey(const ValueKey('liked-songs-unavailable')),
        findsOneWidget,
      );
      await _selectLibrarySection(tester, 'playlists');
      expect(find.text('Current library'), findsOneWidget);
      expect(find.text('Library'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sign out requires confirmation and keeps the signed-out shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authentication = _WidgetGateway(
      _WaitingSession(),
      authenticated: true,
    );
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: authentication,
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out on this device?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sign-out-confirmation-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sign-out-confirmation-dialog')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('sign-out-cancel')));
    await tester.pumpAndSettle();
    expect(authentication.signOutCalls, 0);
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
    await tester.pumpAndSettle();
    expect(authentication.signOutCalls, 1);
    expect(find.byKey(const ValueKey('signed-out-main-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(find.text('Scan with WeChat'), findsNothing);
    expect(find.byKey(const ValueKey('user-library-page')), findsNothing);

    await _openSignInDialog(tester);
    expect(find.text('Scan with WeChat'), findsOneWidget);
  });

  testWidgets('failed sign-out vault cleanup remains explicit and retryable', (
    tester,
  ) async {
    final retry = Completer<CredentialSignOutResult>();
    final authentication = _WidgetGateway(
      _WaitingSession(),
      authenticated: true,
      signOutResults: [
        CredentialSignOutResult.storageCleanupFailed,
        retry.future,
      ],
    );
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: authentication,
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Signed out, but saved session remains'), findsOneWidget);
    expect(find.text('Try removing it again'), findsOneWidget);
    expect(find.byKey(const ValueKey('user-library-page')), findsNothing);

    await tester.ensureVisible(find.text('Try removing it again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try removing it again'));
    await tester.pump();
    expect(authentication.signOutCalls, 2);
    expect(find.text('Removing saved session…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('retry-sign-out-storage-cleanup')),
          )
          .onPressed,
      isNull,
    );

    retry.complete(CredentialSignOutResult.signedOut);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('signed-out-main-page')), findsOneWidget);
    expect(find.text('Scan with WeChat'), findsNothing);
  });

  testWidgets('core sign-out failure keeps the authenticated library', (
    tester,
  ) async {
    final authentication = _WidgetGateway(
      _WaitingSession(),
      authenticated: true,
      signOutResults: [CredentialSignOutResult.coreUnavailable],
    );
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: authentication,
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('user-library-page')), findsOneWidget);
    expect(
      find.text('Couldn’t sign out. Your local session is unchanged.'),
      findsOneWidget,
    );
    expect(authentication.signOutCalls, 1);
  });

  testWidgets('Liked search loads the remaining playlist before filtering', (
    tester,
  ) async {
    const likedPlaylist = UserPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'liked-search-all-pages',
      title: 'Liked search fixture',
      trackCount: 2,
      isLikedSongs: true,
      ownership: UserPlaylistOwnership.owned,
    );
    final detail = _WidgetDetailGateway([
      const PlaylistTrackPageResult(
        total: 2,
        hasMore: true,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:loaded:first',
            title: 'Already loaded',
            artistNames: ['First artist'],
          ),
        ],
      ),
      const PlaylistTrackPageResult(
        offset: 1,
        total: 2,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:loaded:second',
            title: 'Found on the final page',
            artistNames: ['Second artist'],
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(playlists: [likedPlaylist]),
        ]),
        playlistDetailGateway: detail,
      ),
    );
    await tester.pumpAndSettle();
    await _openLibrary(tester);

    final search = find.byKey(const ValueKey('liked-songs-search'));
    expect(
      tester.widget<TextField>(search).decoration?.hintText,
      _en.likedSearchEntirePlaylist,
    );
    await tester.enterText(search, 'final page');
    await tester.pumpAndSettle();

    expect(find.text('Found on the final page'), findsOneWidget);
    expect(find.text('Already loaded'), findsNothing);
    expect(detail.requests.map((request) => request.offset), [0, 1]);
    expect(
      find.text(_en.likedSearchCompleteStatus(_en.likedExactResults(1), 2)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Liked page keeps safe rows when one raw row is omitted', (
    tester,
  ) async {
    const likedPlaylist = UserPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'liked:partial',
      title: 'Partial liked songs',
      isLikedSongs: true,
      ownership: UserPlaylistOwnership.owned,
    );
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(playlists: [likedPlaylist]),
        ]),
        playlistDetailGateway: _WidgetDetailGateway([
          const PlaylistTrackPageResult(
            nextOffset: 3,
            total: 3,
            omittedTrackCount: 1,
            tracks: [
              PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:liked:a',
                title: 'Safe liked track A',
                artistNames: ['Artist A'],
              ),
              PlaylistTrackSummary(
                providerId: 'qq-music',
                opaqueId: 'track:liked:b',
                title: 'Safe liked track B',
                artistNames: ['Artist B'],
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await _openLibrary(tester);

    expect(find.text('Safe liked track A'), findsOneWidget);
    expect(find.text('Safe liked track B'), findsOneWidget);
    expect(find.text(_en.partialResultsNotice(1)), findsOneWidget);
    expect(find.byKey(const ValueKey('liked-songs-error')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Liked search adopts an early scroll prefetch without repeating its page',
    (tester) async {
      const playlist = UserPlaylistSummary(
        providerId: 'qq-music',
        opaqueId: 'liked-prefetch-fixture',
        title: 'Liked prefetch fixture',
        trackCount: 200,
        isLikedSongs: true,
        ownership: UserPlaylistOwnership.owned,
      );
      PlaylistTrackPageResult page(int offset) => PlaylistTrackPageResult(
        offset: offset,
        nextOffset: offset + 100,
        total: 200,
        hasMore: offset == 0,
        tracks: List.generate(
          100,
          (index) => PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'prefetch:${offset + index}',
            title: 'Prefetch row ${offset + index}',
            artistNames: const ['Fixture'],
          ),
        ),
      );
      final next = Completer<PlaylistTrackPageResult>();
      final detail = _DeferredWidgetDetailGateway([
        Future.value(page(0)),
        next.future,
      ]);
      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([
            const UserLibraryResult(playlists: [playlist]),
          ]),
          playlistDetailGateway: detail,
        ),
      );
      await tester.pumpAndSettle();
      await _openLibrary(tester);
      final list = find.byKey(
        const PageStorageKey<String>('liked-songs-track-list'),
      );
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          )
          .position;
      position.jumpTo(position.maxScrollExtent * 0.5);
      await tester.pump();
      expect(position.extentAfter, greaterThan(720));
      expect(detail.requests.map((request) => request.offset), [0, 100]);
      // Let the existing expanded/collapsed header transition remove its
      // outgoing search field while the network page remains deliberately pending.
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('liked-songs-search')),
        'Prefetch row 150',
      );
      await tester.pump();
      expect(detail.requests.map((request) => request.offset), [0, 100]);
      next.complete(page(100));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: list, matching: find.text('Prefetch row 150')),
        findsOneWidget,
      );
      expect(detail.requests.map((request) => request.offset), [0, 100]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Liked search offers a bounded spelling-tolerant result', (
    tester,
  ) async {
    const likedPlaylist = UserPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'liked-search-spelling',
      title: 'Liked spelling fixture',
      trackCount: 1,
      isLikedSongs: true,
      ownership: UserPlaylistOwnership.owned,
    );
    final detail = _WidgetDetailGateway([
      const PlaylistTrackPageResult(
        total: 1,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:nevada',
            title: 'Nevada',
            artistNames: ['Vicetone'],
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(playlists: [likedPlaylist]),
        ]),
        playlistDetailGateway: detail,
      ),
    );
    await tester.pumpAndSettle();
    await _openLibrary(tester);

    await tester.enterText(
      find.byKey(const ValueKey('liked-songs-search')),
      'neveda',
    );
    await tester.pumpAndSettle();

    expect(find.text('Nevada'), findsOneWidget);
    expect(
      find.text(_en.likedApproximateOnlyStatus(_en.likedApproximateResults(1))),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Liked search publishes a later-page match before loading ends', (
    tester,
  ) async {
    const likedPlaylist = UserPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'liked-search-progressive',
      title: 'Liked progressive fixture',
      trackCount: 3,
      isLikedSongs: true,
      ownership: UserPlaylistOwnership.owned,
    );
    final secondPage = Completer<PlaylistTrackPageResult>();
    final finalPage = Completer<PlaylistTrackPageResult>();
    final detail = _DeferredWidgetDetailGateway([
      Future.value(
        const PlaylistTrackPageResult(
          total: 3,
          hasMore: true,
          tracks: [
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:first',
              title: 'Already loaded',
              artistNames: ['First artist'],
            ),
          ],
        ),
      ),
      secondPage.future,
      finalPage.future,
    ]);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(playlists: [likedPlaylist]),
        ]),
        playlistDetailGateway: detail,
      ),
    );
    await tester.pumpAndSettle();
    await _openLibrary(tester);

    await tester.enterText(
      find.byKey(const ValueKey('liked-songs-search')),
      'neveda',
    );
    await tester.pump();
    secondPage.complete(
      const PlaylistTrackPageResult(
        offset: 1,
        total: 3,
        hasMore: true,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:nevada',
            title: 'Nevada',
            artistNames: ['Vicetone'],
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Nevada'), findsOneWidget);
    expect(
      find.text(_en.likedSearchingStatus(2, _en.likedApproximateResults(1), 3)),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 180));
    finalPage.complete(
      const PlaylistTrackPageResult(
        offset: 2,
        total: 3,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:last',
            title: 'Final unrelated track',
            artistNames: ['Last artist'],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nevada'), findsOneWidget);
    expect(
      find.text(_en.likedApproximateOnlyStatus(_en.likedApproximateResults(1))),
      findsOneWidget,
    );
    expect(detail.requests.map((request) => request.offset), [0, 1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Liked search retry resumes the same page after backoff', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const likedPlaylist = UserPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'liked-search-retry',
      title: 'Liked search retry fixture',
      trackCount: 2,
      isLikedSongs: true,
      ownership: UserPlaylistOwnership.owned,
    );
    final detail = _WidgetDetailGateway([
      const PlaylistTrackPageResult(
        total: 2,
        hasMore: true,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:loaded:first',
            title: 'Already loaded',
            artistNames: ['First artist'],
          ),
        ],
      ),
      const PlaylistTrackPageResult(
        failure: UserLibraryFailure.serviceUnavailable,
      ),
      const PlaylistTrackPageResult(
        offset: 1,
        nextOffset: 2,
        total: 2,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:loaded:second',
            title: 'Found after retry',
            artistNames: ['Second artist'],
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(playlists: [likedPlaylist]),
        ]),
        playlistDetailGateway: detail,
      ),
    );
    await tester.pumpAndSettle();
    await _openLibrary(tester);

    await tester.enterText(
      find.byKey(const ValueKey('liked-songs-search')),
      'after retry',
    );
    await tester.pumpAndSettle();

    expect(find.text(_en.likedSearchInterruptedTitle), findsOneWidget);
    expect(detail.requests.map((request) => request.offset), [0, 1]);

    await tester.tap(find.text(_en.likedContinueSearch));
    await tester.pumpAndSettle();

    expect(find.text('Found after retry'), findsOneWidget);
    expect(find.text(_en.likedSearchInterruptedTitle), findsNothing);
    expect(detail.requests.map((request) => request.offset), [0, 1, 1]);
    expect(
      find.text(_en.likedSearchCompleteStatus(_en.likedExactResults(1), 2)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('canonical synthetic Liked Songs review fixture is complete', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const captureReviewImages = bool.fromEnvironment(
      'LIKED_SONGS_VISUAL_REVIEW',
    );
    await _loadRecentReviewFonts(tester, enabled: captureReviewImages);
    const likedPlaylist = UserPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'synthetic-liked-songs',
      title: 'Synthetic liked songs',
      trackCount: 1029,
      isLikedSongs: true,
      ownership: UserPlaylistOwnership.owned,
    );
    const favoriteAlbum = AlbumSummary(
      providerId: 'qq-music',
      opaqueId: 'album:43001:likedFixtureAlbum',
      title: 'Midnight Letters',
    );
    const tracks = [
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:liked:1',
        title: 'Evening Shore',
        artistNames: ['Sergei Parkin'],
        albumTitle: 'Evening Shore',
        durationSeconds: 261,
      ),
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:liked:2',
        title: 'Mercury',
        artistNames: ['DASHI DANCE'],
        albumTitle: 'Spectacle.',
        durationSeconds: 404,
      ),
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:liked:3',
        title: 'Take me hand',
        artistNames: ['Cecile Corbel'],
        albumTitle: 'Take me hand',
        durationSeconds: 215,
      ),
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:liked:4',
        title: 'Messy',
        artistNames: ['ROSÉ'],
        albumTitle: 'F1 The Album',
        durationSeconds: 239,
      ),
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:liked:5',
        title: 'Violet Memory',
        artistNames: ['North Harbor'],
        albumTitle: 'City after rain',
        durationSeconds: 198,
      ),
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:liked:6',
        title: 'Night Transit',
        artistNames: ['Cinder Avenue'],
        albumTitle: 'Moving Quietly',
        durationSeconds: 226,
      ),
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:liked:7',
        title: 'Green Signal',
        artistNames: ['Signal Coast'],
        albumTitle: 'After Hours',
        durationSeconds: 187,
      ),
    ];
    final continuationTracks = List.generate(
      1029 - tracks.length,
      (index) => PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:liked:${index + tracks.length + 1}',
        title: 'Continuation Track ${index + 1}',
        artistNames: const ['Pagination Artist'],
        albumTitle: 'Large library continuation',
        durationSeconds: 180,
      ),
      growable: false,
    );

    List<PlaylistTrackPageResult> detailPages() {
      final pages = <PlaylistTrackPageResult>[
        PlaylistTrackPageResult(total: 1029, hasMore: true, tracks: tracks),
      ];
      for (var start = 0; start < continuationTracks.length; start += 100) {
        final candidateEnd = start + 100;
        final end = candidateEnd < continuationTracks.length
            ? candidateEnd
            : continuationTracks.length;
        pages.add(
          PlaylistTrackPageResult(
            offset: tracks.length + start,
            total: 1029,
            hasMore: end < continuationTracks.length,
            tracks: continuationTracks.sublist(start, end),
          ),
        );
      }
      return pages;
    }

    late _WidgetPlaybackQueueGateway reviewQueue;
    late _WidgetDetailGateway reviewDetail;
    MusicApp fixture() {
      final queue = reviewQueue = _WidgetPlaybackQueueGateway()
        ..replace(tracks: tracks, currentIndex: 1);
      return MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            playlists: [
              likedPlaylist,
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'synthetic-playlist',
                title: 'A dream',
                trackCount: 18,
                ownership: UserPlaylistOwnership.owned,
              ),
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'synthetic-saved-playlist',
                title: 'Collected evenings',
                trackCount: 24,
                ownership: UserPlaylistOwnership.saved,
              ),
            ],
          ),
        ]),
        playlistDetailGateway: reviewDetail = _WidgetDetailGateway(
          detailPages(),
        ),
        favoriteAlbumGateway: _WidgetFavoriteAlbumGateway(
          const FavoriteAlbumPageResult(total: 1, albums: [favoriteAlbum]),
        ),
        playbackQueueGateway: queue,
        mediaResolutionGateway: const _UnavailableMediaGateway(),
        lyricGateway: const _WidgetLyricGateway(),
        initialSettings: const AppSettings(theme: AppThemePreference.light),
      );
    }

    Future<void> pumpLikedSongs(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(fixture());
      await tester.pumpAndSettle();
      if (size.width >= 1100) {
        await tester.tap(find.byKey(const ValueKey('open-liked-songs')));
        await tester.pumpAndSettle();
      } else {
        await _openLibrary(tester);
      }
      expect(find.byKey(const ValueKey('liked-songs-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('liked-songs-title')), findsOneWidget);
      expect(find.text(_en.likedPlayAll), findsOneWidget);
      expect(find.text('Mercury'), findsWidgets);
      expect(find.text('下载'), findsNothing);
      expect(find.text('批量操作'), findsNothing);
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpLikedSongs(const Size(1440, 960));
    expect(find.text('Library'), findsNothing);
    expect(
      find.byKey(const ValueKey('primary-library-destination')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('liked-songs-table-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('now-playing-desktop-layout')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('liked-songs-title'))).dx,
      closeTo(
        tester
            .getTopLeft(find.byKey(const ValueKey('liked-songs-table-header')))
            .dx,
        1,
      ),
    );
    final likedTabs = tester.widget<TabBar>(
      find.byKey(const ValueKey('liked-songs-tabs')),
    );
    expect(likedTabs.indicatorAnimation, TabIndicatorAnimation.elastic);
    expect(
      likedTabs.controller!.animationDuration,
      const Duration(milliseconds: 300),
    );
    expect(
      find.byKey(const ValueKey('liked-collection-pages')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('liked-songs-expanded-header')),
      findsOneWidget,
    );
    final desktopShellTop = tester.getTopLeft(find.byType(AppBar)).dy;
    tester.view.physicalSize = const Size(1440, 720);
    await tester.pumpAndSettle();
    final desktopLikedList = find.byKey(
      const PageStorageKey<String>('liked-songs-track-list'),
    );
    await tester.drag(desktopLikedList, const Offset(0, -180));
    await tester.pumpAndSettle();
    // Lookahead is now speed/latency-dependent: one or two bounded pages,
    // without an extra request merely because a ScrollEnd arrives.
    expect(reviewDetail.requests.length, inInclusiveRange(2, 3));
    expect(reviewDetail.requests.map((request) => request.offset), [
      0,
      tracks.length,
      if (reviewDetail.requests.length == 3) tracks.length + 100,
    ]);
    expect(find.text(_en.likedSongsTab(1029)), findsOneWidget);
    expect(
      find.byKey(const ValueKey('liked-songs-collapsed-header')),
      findsOneWidget,
    );
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('top-search-shortcut')), findsNothing);
    expect(find.byKey(const ValueKey('sign-out')), findsOneWidget);
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('liked-songs-collapsed-header')),
          )
          .dy,
      closeTo(desktopShellTop, 1),
    );
    expect(
      (tester.getCenter(find.byKey(const ValueKey('liked-songs-title'))).dy -
              tester
                  .getCenter(find.byKey(const ValueKey('liked-songs-search')))
                  .dy)
          .abs(),
      lessThan(8),
    );
    final desktopLikedPlayRect = tester.getRect(
      find.byKey(const ValueKey('liked-songs-play-all')),
    );
    final desktopLikedRefreshRect = tester.getRect(
      find.byKey(const ValueKey('liked-songs-refresh-compact')),
    );
    expect(
      desktopLikedRefreshRect.left - desktopLikedPlayRect.right,
      closeTo(8, 1),
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-liked-desktop-collapsed.png'),
        ),
      );
    }
    await tester.drag(desktopLikedList, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('liked-songs-expanded-header')),
      findsOneWidget,
    );
    tester.view.physicalSize = const Size(1440, 960);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('liked-tab-playlists')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('liked-playlists-search')),
      findsOneWidget,
    );
    expect(
      find.text(_en.likedPlaylistSectionCount(1, _en.likedCreatedPlaylists)),
      findsOneWidget,
    );
    expect(
      find.text(_en.likedPlaylistSectionCount(1, _en.likedSavedPlaylists)),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('liked-playlist-synthetic-playlist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('liked-playlist-synthetic-saved-playlist')),
      findsOneWidget,
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-liked-playlists-desktop.png'),
        ),
      );
    }

    await tester.enterText(
      find.byKey(const ValueKey('liked-playlists-search')),
      'Collected',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('liked-playlist-synthetic-saved-playlist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('liked-playlist-synthetic-playlist')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('liked-tab-albums')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('liked-albums-search')), findsOneWidget);
    expect(find.text('Midnight Letters'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('favorite-albums-content')),
      findsOneWidget,
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-liked-albums-desktop.png'),
        ),
      );
    }

    await tester.enterText(
      find.byKey(const ValueKey('liked-albums-search')),
      'Missing',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('favorite-albums-search-empty')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('liked-tab-programs')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('liked-programs-search')),
          )
          .enabled,
      isFalse,
    );
    expect(
      find.byKey(const ValueKey('liked-programs-unavailable')),
      findsOneWidget,
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-liked-programs-desktop.png'),
        ),
      );
    }
    await tester.tap(find.byKey(const ValueKey('liked-tab-videos')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('liked-videos-search')))
          .enabled,
      isFalse,
    );
    expect(
      find.byKey(const ValueKey('liked-videos-unavailable')),
      findsOneWidget,
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-liked-videos-desktop.png'),
        ),
      );
    }
    await _selectLibrarySection(tester, 'liked-songs');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('liked-songs-page')),
        matching: find.byKey(const ValueKey('locate-current-track')),
      ),
      findsOneWidget,
    );
    final currentRowSemantics = tester
        .getSemantics(find.byKey(const ValueKey('liked-track-row-2')))
        .getSemanticsData();
    expect(currentRowSemantics.label, contains('Mercury'));
    expect(currentRowSemantics.flagsCollection.isSelected, Tristate.isTrue);
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-liked-desktop-canonical.png'),
        ),
      );
    }
    await tester.tap(find.byKey(const ValueKey('liked-songs-play-all')));
    await tester.pumpAndSettle();
    expect(reviewQueue.replacements, hasLength(2));
    expect(reviewQueue.replacements.last.$2, 0);

    await tester.enterText(
      find.byKey(const ValueKey('liked-songs-search')),
      'Messy',
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('liked-track-row-1')),
        matching: find.text('Messy'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('liked-songs-page')),
        matching: find.text('Evening Shore'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('liked-track-row-1')),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text(_en.commonAddToQueue), findsOneWidget);
    await tester.tap(find.text(_en.commonAddToQueue));
    await tester.pumpAndSettle();
    expect(reviewQueue.pushed.single.title, 'Messy');

    await pumpLikedSongs(const Size(390, 844));
    expect(
      find.byKey(const ValueKey('liked-songs-table-header')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('now-playing-compact-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('liked-songs-expanded-header')),
      findsOneWidget,
    );
    final mobileShellTop = tester.getTopLeft(find.byType(AppBar)).dy;
    final mobileLikedList = find.byKey(
      const PageStorageKey<String>('liked-songs-track-list'),
    );
    await tester.drag(mobileLikedList, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('liked-songs-collapsed-header')),
      findsOneWidget,
    );
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('open-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-out')), findsOneWidget);
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('liked-songs-collapsed-header')),
          )
          .dy,
      closeTo(mobileShellTop, 1),
    );
    expect(
      (tester.getCenter(find.byKey(const ValueKey('liked-songs-title'))).dy -
              tester
                  .getCenter(find.byKey(const ValueKey('liked-songs-search')))
                  .dy)
          .abs(),
      lessThan(8),
    );
    final mobileLikedPlayRect = tester.getRect(
      find.byKey(const ValueKey('liked-songs-play-all')),
    );
    final mobileLikedRefreshRect = tester.getRect(
      find.byKey(const ValueKey('liked-songs-refresh-compact')),
    );
    expect(
      mobileLikedRefreshRect.left - mobileLikedPlayRect.right,
      closeTo(8, 1),
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-liked-mobile-collapsed.png'),
        ),
      );
    }
    await tester.drag(mobileLikedList, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('liked-songs-expanded-header')),
      findsOneWidget,
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-liked-mobile-canonical.png'),
        ),
      );
    }
    await tester.tap(find.byKey(const ValueKey('liked-tab-playlists')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('liked-playlists-search')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('liked-playlist-synthetic-playlist')),
      findsOneWidget,
    );
    if (captureReviewImages) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-liked-playlists-mobile.png'),
        ),
      );
    }
    await _selectLibrarySection(tester, 'liked-songs');
    await tester.tap(find.byTooltip(_en.commonMoreActions).first);
    await tester.pumpAndSettle();
    expect(find.text(_en.commonPlayFromHere), findsOneWidget);
    expect(find.text(_en.commonAddToQueue), findsOneWidget);
    await tester.tap(find.text(_en.commonAddToQueue));
    await tester.pumpAndSettle();
    expect(reviewQueue.pushed, hasLength(1));

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpLikedSongs(const Size(390, 844));
    await tester.drag(
      find.byKey(const PageStorageKey<String>('liked-songs-track-list')),
      const Offset(0, -180),
    );
    await tester.pump();
    // The scroll notification records intent; presentation changes next frame.
    await tester.pump();
    expect(
      find.byKey(const ValueKey('liked-songs-collapsed-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('liked-songs-expanded-header')),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('applies detected system colors without replacing brand mode', (
    tester,
  ) async {
    const accent = Color(0xFF6750A4);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, (
      call,
    ) async {
      if (call.method == DynamicColorPlugin.methodName) return null;
      if (call.method == DynamicColorPlugin.accentColorMethodName) {
        return accent.toARGB32();
      }
      return null;
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, null),
    );

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(_WaitingSession()),
        initialSettings: const AppSettings(
          theme: AppThemePreference.light,
          colorSource: AppColorSourcePreference.system,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final systemApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      systemApp.theme!.colorScheme.primary,
      ColorScheme.fromSeed(seedColor: accent).primary,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(_WaitingSession()),
        initialSettings: const AppSettings(
          theme: AppThemePreference.light,
          colorSource: AppColorSourcePreference.brand,
          musicProvider: AppMusicProvider.netEaseCloudMusic,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final brandApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      brandApp.theme!.colorScheme.primary,
      MusicMaterialTheme.light(seed: MusicMaterialTheme.netEaseSeedColor)
          .colorScheme
          .primary,
    );
    expect(
      brandApp.theme!.colorScheme.primary,
      isNot(ColorScheme.fromSeed(seedColor: accent).primary),
    );
  });

  testWidgets(
    'Settings distinguishes a system palette from the explicit brand fallback',
    (tester) async {
      final writes = <AppSettings>[];
      const settings = AppSettings(
        theme: AppThemePreference.light,
        colorSource: AppColorSourcePreference.system,
      );

      Widget page(ColorScheme? systemScheme) => MaterialApp(
        locale: englishAppLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        ),
        home: Scaffold(
          body: SettingsPage(
            settings: settings,
            embedded: true,
            showToolbar: false,
            systemLightColorScheme: systemScheme,
            onBack: () {},
            onCompactSectionSelected: (_) {},
            onSettingsChanged: (next) async {
              writes.add(next);
              return AppSettingsWriteResult.saved;
            },
          ),
        ),
      );

      await tester.pumpWidget(
        page(ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4))),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-system-colors-available')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-system-colors-unavailable')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-color-source-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-color-source-brand')),
      );
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(writes.single.colorSource, AppColorSourcePreference.brand);

      await tester.pumpWidget(page(null));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-system-colors-unavailable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-system-colors-available')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keeps the complete playlist sidebar clipped with pinned settings',
    (tester) async {
      const captureReviewImages = bool.fromEnvironment(
        'SIDEBAR_SETTINGS_VISUAL_REVIEW',
      );
      await _loadRecentReviewFonts(tester, enabled: captureReviewImages);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final playlists = List.generate(
        14,
        (index) => UserPlaylistSummary(
          providerId: 'qq-music',
          opaqueId: 'sidebar:$index',
          title: 'Personal playlist ${index + 1}',
          trackCount: index + 1,
        ),
      );
      final settingsStorage = _WidgetSettingsDocumentStorage();

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([
            UserLibraryResult(playlists: playlists),
          ]),
          accountSummaryGateway: const _WidgetAccountSummaryGateway(
            AccountSummaryLoadResult(
              summary: AuthenticatedAccountSummary(
                displayName: 'Fura listener',
              ),
            ),
          ),
          settingsStore: AppSettingsStore(storage: settingsStorage),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('fura music'), findsOneWidget);
      expect(find.text('Fura listener'), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-account')), findsOneWidget);
      final clipMaterial = tester.widget<Material>(
        find.byKey(const ValueKey('sidebar-scroll-clip')),
      );
      expect(clipMaterial.clipBehavior, Clip.hardEdge);
      expect(find.byKey(const ValueKey('open-settings')), findsOneWidget);

      final sidebarScroll = find.descendant(
        of: find.byKey(const ValueKey('sidebar-scroll-clip')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Personal playlist 14'),
        320,
        scrollable: sidebarScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('Personal playlist 14'), findsOneWidget);
      expect(find.byKey(const ValueKey('open-settings')), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('open-settings'))).dy,
        lessThanOrEqualTo(900),
      );

      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(Uri.file('/tmp/fura-music-sidebar-desktop.png')),
        );
      }

      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('embedded-settings-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-theme-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-color-source-selector')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(settingsStorage.document, contains('"theme":"dark"'));
      expect(
        Theme.of(tester.element(find.byKey(const ValueKey('settings-content'))))
            .brightness,
        Brightness.dark,
      );

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('desktop-music-sidebar')), findsNothing);
      expect(
        find.byKey(const ValueKey('embedded-settings-page')),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('settings-toolbar')),
          matching: find.byType(SafeArea),
        ),
        findsOneWidget,
      );
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(Uri.file('/tmp/fura-music-settings-compact.png')),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings shell replaces navigation and top actions with symmetric motion',
    (tester) async {
      await _loadRecentReviewFonts(tester);
      const captureReviewImage =
          bool.fromEnvironment('SETTINGS_SHELL_VISUAL_REVIEW') ||
          bool.fromEnvironment('BUILT_IN_PROVIDER_VISUAL_REVIEW');
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(
            _WaitingSession(),
            authenticated: true,
          ),
          libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
          accountSummaryGateway: const _WidgetAccountSummaryGateway(
            AccountSummaryLoadResult(
              summary: AuthenticatedAccountSummary(
                displayName: 'Fura listener',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('desktop-music-sidebar')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sidebar-account')), findsOneWidget);
      final signOut = find.byKey(const ValueKey('sign-out'));
      expect(signOut, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sidebar-account')),
          matching: signOut,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('music-shell-actions')),
          matching: signOut,
        ),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('top-search-shortcut')), findsOneWidget);
      final homeSearchCenter = tester.getCenter(
        find.byKey(const ValueKey('top-search-shortcut')),
      );

      await tester.tap(signOut);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sign-out-confirmation-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('sign-out-cancel')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('music-navigation-transition-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-navigation-transition-page')),
        findsOneWidget,
      );
      final detailSurface = find.byKey(
        const ValueKey('settings-detail-opaque-surface'),
      );
      expect(detailSurface, findsOneWidget);
      expect(
        tester.widget<Material>(detailSurface).color,
        Theme.of(tester.element(detailSurface)).scaffoldBackgroundColor,
      );
      expect(
        find.descendant(
          of: detailSurface,
          matching: find.byKey(const ValueKey('embedded-settings-page')),
        ),
        findsOneWidget,
      );
      if (captureReviewImage) {
        await tester.pump(const Duration(milliseconds: 120));
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-settings-shell-desktop-transition.png'),
          ),
        );
      }
      expect(
        find.byKey(const ValueKey('primary-shell-top-bar')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('top-search-shortcut')), findsNothing);
      expect(find.byKey(const ValueKey('settings-search')), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const ValueKey('settings-search'))),
        homeSearchCenter,
      );
      expect(find.byKey(const ValueKey('sign-out')), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('desktop-music-sidebar')), findsNothing);
      expect(
        find.byKey(const ValueKey('desktop-settings-sidebar')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sidebar-account')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-sidebar-back')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-nav-appearance')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-nav-musicService')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-nav-playback')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sign-out')), findsNothing);
      expect(find.byKey(const ValueKey('sign-in')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-shell-actions')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('top-search-shortcut')), findsNothing);
      final settingsSearch = find.byKey(const ValueKey('settings-search'));
      expect(settingsSearch, findsOneWidget);
      expect(
        tester.widget<SearchBar>(settingsSearch).hintText,
        'Search settings',
      );
      expect(find.byKey(const ValueKey('settings-toolbar')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-theme-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-color-source-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-quality-selector')),
        findsNothing,
      );
      if (captureReviewImage) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(Uri.file('/tmp/fura-settings-shell-desktop.png')),
        );
      }

      await tester.tap(find.byKey(const ValueKey('settings-nav-musicService')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('settings-appearance-section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-music-service-section')),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.byKey(const ValueKey('settings-appearance-section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-music-service-section')),
        findsNothing,
      );
      if (captureReviewImage) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-settings-section-outgoing.png'),
          ),
        );
      }
      await tester.pump(const Duration(milliseconds: 32));
      expect(
        find.byKey(const ValueKey('settings-music-service-section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-appearance-section')),
        findsNothing,
      );
      if (captureReviewImage) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-settings-section-incoming.png'),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-provider-selector')),
        findsOneWidget,
      );
      if (captureReviewImage) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-provider-settings-desktop.png'),
          ),
        );
      }

      await tester.tap(find.byKey(const ValueKey('settings-nav-playback')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-theme-selector')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-quality-selector')),
        findsOneWidget,
      );

      await tester.enterText(settingsSearch, 'dark');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-search-summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-theme-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-quality-selector')),
        findsNothing,
      );

      await tester.enterText(settingsSearch, 'not-a-setting');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-search-empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-theme-selector')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-quality-selector')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('settings-sidebar-back')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('music-navigation-transition-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-navigation-transition-page')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('desktop-music-sidebar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-settings-sidebar')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('sidebar-account')), findsOneWidget);
      expect(find.byKey(const ValueKey('sign-out')), findsOneWidget);
      expect(find.byKey(const ValueKey('top-search-shortcut')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-search')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile settings navigate from categories into searchable detail pages',
    (tester) async {
      await _loadRecentReviewFonts(tester);
      const captureReviewImages =
          bool.fromEnvironment('MOBILE_SETTINGS_VISUAL_REVIEW') ||
          bool.fromEnvironment('BUILT_IN_PROVIDER_VISUAL_REVIEW');
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settingsStorage = _WidgetSettingsDocumentStorage();

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _bootstrap,
          authenticationGateway: _WidgetGateway(_WaitingSession()),
          settingsStore: AppSettingsStore(storage: settingsStorage),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-recommendations')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-compact-menu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-compact-detail')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-compact-appearance')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-compact-musicService')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-compact-playback')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-compact-search')),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const ValueKey('sign-in')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-theme-selector')),
        findsNothing,
      );
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(Uri.file('/tmp/fura-settings-mobile-menu.png')),
        );
      }

      await tester.tap(
        find.byKey(const ValueKey('settings-compact-appearance')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('settings-compact-menu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-compact-detail')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-compact-menu')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-theme-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-compact-title-appearance')),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-settings-mobile-appearance.png'),
          ),
        );
      }

      await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(settingsStorage.document, contains('"theme":"dark"'));
      await tester.tap(
        find.byKey(const ValueKey('settings-color-source-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-color-source-system')),
      );
      await tester.pumpAndSettle();
      expect(settingsStorage.document, contains('"colorSource":"system"'));
      expect(
        find.byKey(const ValueKey('app-dynamic-color-loader')),
        findsOneWidget,
      );
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-settings-mobile-system-colors.png'),
          ),
        );
      }
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('settings-compact-menu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-compact-detail')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(find.text('Dark theme · System colors'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('settings-compact-musicService')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-provider-selector')),
        findsOneWidget,
      );
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-provider-settings-compact.png'),
          ),
        );
      }
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('settings-compact-playback')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-quality-selector')),
        findsOneWidget,
      );
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-compact-menu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-quality-selector')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('settings-compact-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'quality');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-compact-search-result-playback')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-compact-search-result-appearance')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-compact-search-result-playback')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-quality-selector')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pumpAndSettle();

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-page')), findsNothing);
      expect(
        find.byKey(const ValueKey('recommended-playlists-page')),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile settings hierarchy honors reduced motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(_WaitingSession()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-recommendations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-settings')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('settings-compact-appearance')));
    await tester.pump();
    expect(find.byKey(const ValueKey('settings-compact-menu')), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-compact-detail')),
      findsOneWidget,
    );
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('settings-back')));
    await tester.pump();
    expect(find.byKey(const ValueKey('settings-compact-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-compact-detail')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-out settings shell hides every login affordance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(_WaitingSession()),
      ),
    );
    await tester.pumpAndSettle();
    final signIn = find.byKey(const ValueKey('sign-in'));
    expect(signIn, findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-account')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sidebar-account')),
        matching: signIn,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('music-shell-actions')),
        matching: signIn,
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('open-settings')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-settings-sidebar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sidebar-account')), findsNothing);
    expect(find.byKey(const ValueKey('sign-in')), findsNothing);
    expect(find.byKey(const ValueKey('sign-out')), findsNothing);
    expect(find.byKey(const ValueKey('settings-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings reuses the navigation rail at medium desktop widths', (
    tester,
  ) async {
    const captureMediumRail = bool.fromEnvironment('MEDIUM_RAIL_VISUAL_REVIEW');
    tester.view.physicalSize = const Size(960, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(_WaitingSession()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('music-navigation-rail')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-navigation-rail')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    final mediumSettings = find.byKey(const ValueKey('open-settings'));
    expect(mediumSettings, findsOneWidget);
    final settingsEntryRail = tester.widget<NavigationRail>(
      find.byKey(const ValueKey('settings-entry-navigation-rail')),
    );
    expect(settingsEntryRail.labelType, NavigationRailLabelType.all);
    expect(settingsEntryRail.selectedIndex, isNull);
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.getCenter(mediumSettings).dy, greaterThan(720));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('music-navigation-rail-shell')),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
    if (captureMediumRail) {
      await expectLater(
        find.byType(MusicApp),
        matchesGoldenFile(
          Uri.file('/tmp/fura-medium-rail-settings-bottom.png'),
        ),
      );
    }

    await tester.tap(find.byKey(const ValueKey('open-settings')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('music-navigation-transition-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-navigation-transition-page')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('music-navigation-rail')), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-navigation-rail')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings-rail-back')), findsOneWidget);
    expect(find.text('Appearance'), findsWidgets);
    expect(find.byKey(const ValueKey('settings-nav-playback')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-toolbar')), findsNothing);
    expect(find.byKey(const ValueKey('sign-in')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-nav-playback')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-quality-selector')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('settings-rail-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('music-navigation-rail')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-navigation-rail')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings shell honors reduced motion in both directions', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(_WaitingSession()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-settings')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('desktop-settings-sidebar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('desktop-music-sidebar')), findsNothing);
    expect(find.byKey(const ValueKey('primary-shell-top-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('top-search-shortcut')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-sidebar-back')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('desktop-settings-sidebar')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('desktop-music-sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('primary-shell-top-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-search')), findsNothing);
    expect(find.byKey(const ValueKey('top-search-shortcut')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returns rejected library credentials to sign-in', (
    tester,
  ) async {
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            failure: UserLibraryFailure.credentialRejected,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your saved session was rejected'), findsOneWidget);
    await tester.tap(find.text('Sign in again'));
    await tester.pumpAndSettle();
    expect(find.text('Scan with WeChat'), findsOneWidget);
  });

  testWidgets(
    'provider switch cancels an open QR session and replaces auth UI',
    (tester) async {
      final qqSession = _WaitingSession();
      final harnessKey = GlobalKey<_LoginProviderHarnessState>();
      final qq = _providerFixture(
        authenticationGateway: _WidgetGateway(qqSession),
        capabilities: MusicProviderCapabilities.qqMusic,
        providerId: 'qq-music',
        accountName: 'QQ Account',
        searchGateway: _WidgetSearchGateway(const TrackSearchPageResult()),
      );
      final netEase = _providerFixture(
        authenticationGateway: _ProviderWidgetGateway(
          providerId: 'netease-cloud-music',
        ),
        capabilities: MusicProviderCapabilities.netEaseCloudMusic,
        providerId: 'netease-cloud-music',
        accountName: 'NetEase Account',
        searchGateway: _WidgetSearchGateway(const TrackSearchPageResult()),
      );

      await tester.pumpWidget(
        _LoginProviderHarness(key: harnessKey, qq: qq, netEase: netEase),
      );
      await tester.pumpAndSettle();
      await _openSignInDialog(tester);
      await tester.tap(find.byKey(const ValueKey('start-qq-login-button')));
      await tester.pump();
      expect(find.text('Scan with QQ'), findsWidgets);

      harnessKey.currentState!.select(AppMusicProvider.netEaseCloudMusic);
      await tester.pumpAndSettle();

      expect(qqSession.cancelCalls, 1);
      expect(find.byKey(const ValueKey('authentication-dialog')), findsNothing);
      expect(
        find.byKey(const ValueKey('signed-out-main-page')),
        findsOneWidget,
      );
      await _openSignInDialog(tester);
      expect(find.text('Scan with NetEase Cloud Music'), findsOneWidget);
      expect(find.text('Scan with QQ'), findsNothing);
      expect(find.text('Scan with WeChat'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'provider switch replaces catalog state but preserves provider-owned playback',
    (tester) async {
      const captureReviewImages = bool.fromEnvironment(
        'BUILT_IN_PROVIDER_VISUAL_REVIEW',
      );
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const qqTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'same-opaque-id',
        title: 'QQ Queue Survivor',
        artistNames: ['QQ artist'],
        durationSeconds: 181,
      );
      const netEaseTrack = PlaylistTrackSummary(
        providerId: 'netease-cloud-music',
        opaqueId: 'same-opaque-id',
        title: 'NetEase Personal FM Track',
        artistNames: ['NetEase artist'],
        durationSeconds: 202,
      );
      final staleQqRecommendations =
          _ControlledWidgetRecommendedPlaylistGateway();
      final qqSearch = _WidgetSearchGateway(
        const TrackSearchPageResult(
          page: 1,
          total: 1,
          items: [TrackSearchItem(track: qqTrack)],
        ),
      );
      final netEaseSearch = _WidgetSearchGateway(
        const TrackSearchPageResult(
          page: 1,
          total: 1,
          items: [TrackSearchItem(track: netEaseTrack)],
        ),
      );
      final queue = _WidgetPlaybackQueueGateway();
      final settingsStorage = _WidgetSettingsDocumentStorage();

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _dualProviderBootstrap,
          providerDependencies: BuiltInProviderDependencies(
            qqMusic: _providerFixture(
              authenticationGateway: _ProviderWidgetGateway(
                providerId: 'qq-music',
                authenticated: true,
              ),
              capabilities: MusicProviderCapabilities.qqMusic,
              providerId: 'qq-music',
              accountName: 'QQ Account',
              searchGateway: qqSearch,
              recommendedPlaylistGateway: staleQqRecommendations,
              personalizedTracks: const [qqTrack],
            ),
            netEase: _providerFixture(
              authenticationGateway: _ProviderWidgetGateway(
                providerId: 'netease-cloud-music',
                authenticated: true,
              ),
              capabilities: MusicProviderCapabilities.netEaseCloudMusic,
              providerId: 'netease-cloud-music',
              accountName: 'NetEase Account',
              searchGateway: netEaseSearch,
              personalizedTracks: const [netEaseTrack],
              dailyTracks: const [netEaseTrack],
            ),
          ),
          playbackQueueGateway: queue,
          mediaResolutionGateway: const _UnavailableMediaGateway(),
          lyricGateway: const _WidgetLyricGateway(),
          settingsStore: AppSettingsStore(storage: settingsStorage),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('QQ Account'), findsOneWidget);
      expect(find.text('Songs picked for you'), findsOneWidget);
      expect(find.byKey(const ValueKey('open-recent-plays')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-personalized-track-1')));
      await tester.pumpAndSettle();
      expect(queue.replacements.single.$1.single.providerId, 'qq-music');

      await _switchProviderFromDesktopSettings(
        tester,
        const ValueKey('settings-provider-netease'),
        reviewImagePath: captureReviewImages
            ? '/tmp/fura-provider-settings-desktop-integration.png'
            : null,
      );
      expect(find.text('NetEase Account'), findsOneWidget);
      expect(find.text('Personal FM'), findsOneWidget);
      expect(find.text('Daily tracks'), findsWidgets);
      expect(find.text('NetEase Personal FM Track'), findsWidgets);
      expect(find.byKey(const ValueKey('open-liked-songs')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-recent-plays')), findsNothing);
      expect(find.text('QQ Queue Survivor'), findsOneWidget);
      if (captureReviewImages) {
        await tester.tap(find.byKey(const ValueKey('open-liked-songs')));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(Uri.file('/tmp/fura-netease-library-desktop.png')),
        );
        await tester.tap(
          find.byKey(const ValueKey('primary-home-destination')),
        );
        await tester.pumpAndSettle();
      }

      staleQqRecommendations.complete(
        const RecommendedPlaylistPageResult(
          playlists: [
            RecommendedPlaylistSummary(
              providerId: 'qq-music',
              opaqueId: 'stale',
              title: 'Stale QQ result must stay hidden',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stale QQ result must stay hidden'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('open-recommendations')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('discover-type-radar')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('open-track-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('track-search-field')),
        'same id',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('NetEase Personal FM Track'), findsWidgets);
      expect(netEaseSearch.requests, hasLength(1));
      expect(qqSearch.requests, isEmpty);
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(Uri.file('/tmp/fura-netease-search-desktop.png')),
        );
      }

      await _switchProviderFromDesktopSettings(
        tester,
        const ValueKey('settings-provider-qq-music'),
      );
      expect(find.text('QQ Account'), findsOneWidget);
      expect(find.text('QQ Queue Survivor'), findsWidgets);
      expect(find.byKey(const ValueKey('open-recent-plays')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'signed-out NetEase keeps public shell and exposes only official web login',
    (tester) async {
      const captureReviewImages = bool.fromEnvironment(
        'BUILT_IN_PROVIDER_VISUAL_REVIEW',
      );
      await _loadRecentReviewFonts(tester, enabled: captureReviewImages);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const publicTrack = PlaylistTrackSummary(
        providerId: 'netease-cloud-music',
        opaqueId: 'public-track',
        title: 'NetEase Public Track',
        artistNames: ['Public artist'],
      );

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _dualProviderBootstrap,
          initialSettings: const AppSettings(
            theme: AppThemePreference.system,
            musicProvider: AppMusicProvider.netEaseCloudMusic,
          ),
          providerDependencies: BuiltInProviderDependencies(
            qqMusic: _providerFixture(
              authenticationGateway: _ProviderWidgetGateway(
                providerId: 'qq-music',
              ),
              capabilities: MusicProviderCapabilities.qqMusic,
              providerId: 'qq-music',
              accountName: 'QQ Account',
              searchGateway: _WidgetSearchGateway(
                const TrackSearchPageResult(),
              ),
            ),
            netEase: _providerFixture(
              authenticationGateway: _OfficialWebProviderWidgetGateway(
                providerId: 'netease-cloud-music',
              ),
              capabilities: MusicProviderCapabilities.netEaseCloudMusic,
              providerId: 'netease-cloud-music',
              accountName: 'NetEase Account',
              searchGateway: _WidgetSearchGateway(
                const TrackSearchPageResult(
                  page: 1,
                  total: 1,
                  items: [TrackSearchItem(track: publicTrack)],
                ),
              ),
              newSongs: const [publicTrack],
            ),
          ),
          mediaResolutionGateway: const _UnavailableMediaGateway(),
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('signed-out-main-page')),
        findsOneWidget,
      );
      expect(find.text('NetEase Public Track'), findsWidgets);
      expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
      expect(find.text('Radar'), findsNothing);
      expect(find.byKey(const ValueKey('open-recent-plays')), findsNothing);
      if (captureReviewImages) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-netease-signed-out-compact.png'),
          ),
        );
      }

      await _openSignInDialog(tester);
      expect(find.text('Complete sign-in with NetEase'), findsOneWidget);
      expect(find.text('Scan with QQ'), findsNothing);
      expect(find.text('Scan with WeChat'), findsNothing);
      expect(find.text('Quick login'), findsNothing);
      expect(find.text('Use phone code'), findsNothing);
      expect(find.byKey(const ValueKey('start-qq-login-button')), findsNothing);
      expect(find.byKey(const ValueKey('show-sms-login-button')), findsNothing);
      expect(
        find.byKey(const ValueKey('start-official-web-login-button')),
        findsOneWidget,
      );
      if (captureReviewImages) {
        await expectLater(
          find.byKey(const ValueKey('authentication-dialog')),
          matchesGoldenFile(
            Uri.file('/tmp/fura-netease-web-only-auth-compact.png'),
          ),
        );
      }

      await tester.tap(
        find.byKey(const ValueKey('start-official-web-login-button')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('official-web-login-surface')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fake-official-webview')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'NetEase official website login uses a visible full-size owned surface',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _OfficialWebProviderWidgetGateway(
        providerId: 'netease-cloud-music',
      );
      const playingTrack = PlaylistTrackSummary(
        providerId: 'netease-cloud-music',
        opaqueId: 'official-web-playback',
        title: 'Playback survives official login',
        artistNames: ['Fixture artist'],
        durationSeconds: 180,
      );
      final queue = _WidgetPlaybackQueueGateway()
        ..replace(tracks: const [playingTrack], currentIndex: 0);
      final audioSession = _WidgetAudioSession();
      final media = _SuccessfulWidgetMediaGateway();
      final playbackHost = createForegroundAppPlaybackHost(
        playbackQueueGateway: queue,
        mediaResolutionGateway: media,
        lyricGateway: const _WidgetLyricGateway(),
        audioEngine: _WidgetAudioEngine(audioSession),
      );
      addTearDown(playbackHost.dispose);
      final playbackOwner = playbackHost.controller;
      await playbackOwner.playback.playTrack(playingTrack);

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _dualProviderBootstrap,
          initialSettings: const AppSettings(
            theme: AppThemePreference.light,
            localePreference: AppLocalePreference.english,
            musicProvider: AppMusicProvider.netEaseCloudMusic,
          ),
          providerDependencies: BuiltInProviderDependencies(
            qqMusic: _providerFixture(
              authenticationGateway: _ProviderWidgetGateway(
                providerId: 'qq-music',
              ),
              capabilities: MusicProviderCapabilities.qqMusic,
              providerId: 'qq-music',
              accountName: 'QQ Account',
              searchGateway: _WidgetSearchGateway(
                const TrackSearchPageResult(),
              ),
            ),
            netEase: _providerFixture(
              authenticationGateway: gateway,
              capabilities: MusicProviderCapabilities.netEaseCloudMusic,
              providerId: 'netease-cloud-music',
              accountName: 'NetEase Account',
              searchGateway: _WidgetSearchGateway(
                const TrackSearchPageResult(),
              ),
            ),
          ),
          mediaResolutionGateway: media,
          lyricGateway: const _WidgetLyricGateway(),
          playbackHost: playbackHost,
        ),
      );
      await tester.pumpAndSettle();
      expect(playbackOwner.playback.stage, TrackPlaybackStage.playing);

      await _openSignInDialog(tester);
      await tester.tap(
        find.byKey(const ValueKey('start-official-web-login-button')),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('official-web-login-surface')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fake-official-webview')),
        findsOneWidget,
      );
      expect(find.text('music.163.com'), findsOneWidget);
      expect(
        find.text(
          'Complete sign-in on the official page. Fura will verify the '
          'resulting session before saving it.',
        ),
        findsOneWidget,
      );
      expect(gateway.operation, isNotNull);
      expect(playbackHost.controller, same(playbackOwner));
      expect(playbackOwner.current, same(playingTrack));
      expect(playbackOwner.playback.stage, TrackPlaybackStage.playing);
      expect(audioSession.stopCalls, 0);

      await tester.tap(
        find.byKey(const ValueKey('close-authentication-dialog')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('authentication-dialog')), findsNothing);
      expect(gateway.operation!.cancelCalls, 1);
      expect(playbackHost.controller, same(playbackOwner));
      expect(playbackOwner.current, same(playingTrack));
      expect(playbackOwner.playback.stage, TrackPlaybackStage.playing);
      expect(audioSession.stopCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'runtime locale switching preserves provider auth catalog queue and playback owners',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      const currentTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'locale-stable-track',
        title: 'Upstream Track Stays Put',
        artistNames: ['Upstream Artist'],
        durationSeconds: 240,
      );
      final queue = _WidgetPlaybackQueueGateway()
        ..replace(tracks: const [currentTrack], currentIndex: 0);
      final playbackHost = createForegroundAppPlaybackHost(
        playbackQueueGateway: queue,
        mediaResolutionGateway: const _UnavailableMediaGateway(),
        lyricGateway: const _WidgetLyricGateway(),
        audioEngine: AudioplayersForegroundAudioEngine(),
      );
      final qqAuth = _ProviderWidgetGateway(
        providerId: 'qq-music',
        authenticated: true,
      );
      final recommendations = _WidgetRecommendedPlaylistGateway(
        const RecommendedPlaylistPageResult(),
      );
      final search = _WidgetSearchGateway(
        const TrackSearchPageResult(
          page: 1,
          total: 1,
          items: [TrackSearchItem(track: currentTrack)],
        ),
      );
      final storage = _WidgetSettingsDocumentStorage();

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _dualProviderBootstrap,
          initialSettings: const AppSettings(
            theme: AppThemePreference.light,
            localePreference: AppLocalePreference.english,
          ),
          settingsStore: AppSettingsStore(storage: storage),
          providerDependencies: BuiltInProviderDependencies(
            qqMusic: _providerFixture(
              authenticationGateway: qqAuth,
              capabilities: MusicProviderCapabilities.qqMusic,
              providerId: 'qq-music',
              accountName: 'Locale Stable Account',
              searchGateway: search,
              recommendedPlaylistGateway: recommendations,
              personalizedTracks: const [currentTrack],
            ),
            netEase: _providerFixture(
              authenticationGateway: _ProviderWidgetGateway(
                providerId: 'netease-cloud-music',
                authenticated: true,
              ),
              capabilities: MusicProviderCapabilities.netEaseCloudMusic,
              providerId: 'netease-cloud-music',
              accountName: 'Unused NetEase Account',
              searchGateway: _WidgetSearchGateway(
                const TrackSearchPageResult(),
              ),
            ),
          ),
          playbackHost: playbackHost,
        ),
      );
      await tester.pumpAndSettle();

      final controller = playbackHost.controller;
      final initialTrack = controller.current;
      final initialStage = controller.playback.stage;
      expect(find.text(_en.navHome), findsOneWidget);
      expect(find.text(_zh.navHome), findsNothing);
      expect(find.text('Locale Stable Account'), findsOneWidget);
      expect(find.text(currentTrack.title), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('open-track-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('track-search-field')),
        'locale stable',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text(currentTrack.title), findsWidgets);
      final initialSearchRequests = List.of(search.requests);
      final initialRecommendationRequests = List.of(recommendations.requests);
      expect(initialSearchRequests, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-language')));
      await tester.pumpAndSettle();
      expect(find.text(_en.settingsTitle), findsOneWidget);

      await _changeLanguagePreference(
        tester,
        AppLocalePreference.simplifiedChinese,
      );
      expect(find.text(_zh.settingsTitle), findsWidgets);
      expect(find.text(_zh.settingsLanguageLabel), findsWidgets);
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      await tester.pumpAndSettle();
      expect(find.text(_zh.settingsTitle), findsWidgets);

      await _changeLanguagePreference(tester, AppLocalePreference.english);
      expect(find.text(_en.settingsTitle), findsWidgets);
      tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
      await tester.pumpAndSettle();
      expect(find.text(_en.settingsTitle), findsWidgets);

      await _changeLanguagePreference(tester, AppLocalePreference.system);
      expect(find.text(_zh.settingsTitle), findsWidgets);
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      await tester.pumpAndSettle();
      expect(find.text(_en.settingsTitle), findsWidgets);

      expect(playbackHost.controller, same(controller));
      expect(controller.current, same(initialTrack));
      expect(controller.playback.stage, initialStage);
      expect(controller.tracks, const [currentTrack]);
      expect(qqAuth.authenticated, isTrue);
      expect(qqAuth.signOutCalls, 0);
      expect(search.requests, initialSearchRequests);
      expect(recommendations.requests, initialRecommendationRequests);

      await tester.tap(find.byKey(const ValueKey('settings-sidebar-back')));
      await tester.pumpAndSettle();
      expect(find.text('Locale Stable Account'), findsOneWidget);
      expect(find.text(currentTrack.title), findsWidgets);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('track-search-field')))
            .controller
            ?.text,
        'locale stable',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'NetEase locale switching preserves auth loaded search queue and playback owners',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const currentTrack = PlaylistTrackSummary(
        providerId: 'netease-cloud-music',
        opaqueId: 'netease-locale-stable-track',
        title: 'NetEase Upstream Track Stays Put',
        artistNames: ['Upstream Artist'],
        durationSeconds: 210,
      );
      final queue = _WidgetPlaybackQueueGateway()
        ..replace(tracks: const [currentTrack], currentIndex: 0);
      final playbackHost = createForegroundAppPlaybackHost(
        playbackQueueGateway: queue,
        mediaResolutionGateway: const _UnavailableMediaGateway(),
        lyricGateway: const _WidgetLyricGateway(),
        audioEngine: AudioplayersForegroundAudioEngine(),
      );
      final netEaseAuth = _ProviderWidgetGateway(
        providerId: 'netease-cloud-music',
        authenticated: true,
      );
      final recommendations = _WidgetRecommendedPlaylistGateway(
        const RecommendedPlaylistPageResult(),
      );
      final search = _WidgetSearchGateway(
        const TrackSearchPageResult(
          page: 1,
          total: 1,
          items: [TrackSearchItem(track: currentTrack)],
        ),
      );

      await tester.pumpWidget(
        MusicApp(
          bootstrap: _dualProviderBootstrap,
          initialSettings: const AppSettings(
            theme: AppThemePreference.light,
            musicProvider: AppMusicProvider.netEaseCloudMusic,
            localePreference: AppLocalePreference.english,
          ),
          settingsStore: AppSettingsStore(
            storage: _WidgetSettingsDocumentStorage(),
          ),
          providerDependencies: BuiltInProviderDependencies(
            qqMusic: _providerFixture(
              authenticationGateway: _ProviderWidgetGateway(
                providerId: 'qq-music',
                authenticated: true,
              ),
              capabilities: MusicProviderCapabilities.qqMusic,
              providerId: 'qq-music',
              accountName: 'Unused QQ Account',
              searchGateway: _WidgetSearchGateway(
                const TrackSearchPageResult(),
              ),
            ),
            netEase: _providerFixture(
              authenticationGateway: netEaseAuth,
              capabilities: MusicProviderCapabilities.netEaseCloudMusic,
              providerId: 'netease-cloud-music',
              accountName: 'NetEase Locale Stable Account',
              searchGateway: search,
              recommendedPlaylistGateway: recommendations,
              personalizedTracks: const [currentTrack],
              dailyTracks: const [currentTrack],
            ),
          ),
          playbackHost: playbackHost,
        ),
      );
      await tester.pumpAndSettle();

      final controller = playbackHost.controller;
      final initialTrack = controller.current;
      final initialStage = controller.playback.stage;
      await tester.tap(find.byKey(const ValueKey('open-track-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('track-search-field')),
        'netease locale stable',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text(currentTrack.title), findsWidgets);
      final initialSearchRequests = List.of(search.requests);
      final initialRecommendationRequests = List.of(recommendations.requests);

      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-language')));
      await tester.pumpAndSettle();
      await _changeLanguagePreference(
        tester,
        AppLocalePreference.simplifiedChinese,
      );
      expect(find.text(_zh.settingsTitle), findsWidgets);
      await _changeLanguagePreference(tester, AppLocalePreference.english);
      expect(find.text(_en.settingsTitle), findsWidgets);

      expect(playbackHost.controller, same(controller));
      expect(controller.current, same(initialTrack));
      expect(controller.playback.stage, initialStage);
      expect(controller.tracks, const [currentTrack]);
      expect(netEaseAuth.authenticated, isTrue);
      expect(netEaseAuth.signOutCalls, 0);
      expect(search.requests, initialSearchRequests);
      expect(recommendations.requests, initialRecommendationRequests);

      await tester.tap(find.byKey(const ValueKey('settings-sidebar-back')));
      await tester.pumpAndSettle();
      expect(find.text('NetEase Locale Stable Account'), findsOneWidget);
      expect(find.text(currentTrack.title), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  for (final provider in AppMusicProvider.values) {
    for (final localePreference in const [
      AppLocalePreference.english,
      AppLocalePreference.simplifiedChinese,
    ]) {
      final providerSlug = provider == AppMusicProvider.qqMusic
          ? 'qq'
          : 'netease';
      final localeSlug = localePreference == AppLocalePreference.english
          ? 'en'
          : 'zh-hans';
      testWidgets(
        '$providerSlug $localeSlug localizes signed-in surfaces and signed-out authentication',
        (tester) async {
          const capture = bool.fromEnvironment('LOCALIZATION_VISUAL_REVIEW');
          final semantics = tester.ensureSemantics();
          tester.view.physicalSize = const Size(1100, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await _loadRecentReviewFonts(tester, enabled: capture);

          final l10n = localePreference == AppLocalePreference.english
              ? _en
              : _zh;
          final providerId = provider == AppMusicProvider.qqMusic
              ? 'qq-music'
              : 'netease-cloud-music';
          final providerName = provider == AppMusicProvider.qqMusic
              ? l10n.providerQqMusic
              : l10n.providerNeteaseCloudMusic;
          final accountName = '$providerSlug Account Fixture';
          final currentTrack = PlaylistTrackSummary(
            providerId: providerId,
            opaqueId: '$providerSlug-current-track',
            title: '$providerSlug Upstream Track',
            artistNames: const ['Upstream Artist'],
            durationSeconds: 210,
          );
          final queue = _WidgetPlaybackQueueGateway()
            ..replace(tracks: [currentTrack], currentIndex: 0);

          MusicProviderDependencies signedInProvider(AppMusicProvider target) {
            final isQq = target == AppMusicProvider.qqMusic;
            final id = isQq ? 'qq-music' : 'netease-cloud-music';
            return _providerFixture(
              authenticationGateway: _ProviderWidgetGateway(
                providerId: id,
                authenticated: true,
              ),
              capabilities: isQq
                  ? MusicProviderCapabilities.qqMusic
                  : MusicProviderCapabilities.netEaseCloudMusic,
              providerId: id,
              accountName: target == provider
                  ? accountName
                  : 'Other Provider Account',
              searchGateway: _WidgetSearchGateway(
                const TrackSearchPageResult(),
              ),
              personalizedTracks: target == provider
                  ? [currentTrack]
                  : const [],
            );
          }

          await tester.pumpWidget(
            MusicApp(
              key: ValueKey(
                'locale-matrix-$providerSlug-$localeSlug-signed-in',
              ),
              bootstrap: _dualProviderBootstrap,
              initialSettings: AppSettings(
                theme: AppThemePreference.light,
                musicProvider: provider,
                localePreference: localePreference,
              ),
              providerDependencies: BuiltInProviderDependencies(
                qqMusic: signedInProvider(AppMusicProvider.qqMusic),
                netEase: signedInProvider(AppMusicProvider.netEaseCloudMusic),
              ),
              playbackQueueGateway: queue,
              mediaResolutionGateway: const _UnavailableMediaGateway(),
              lyricGateway: const _WidgetLyricGateway(),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text(l10n.navHome), findsOneWidget);
          expect(find.text(accountName), findsOneWidget);
          expect(find.text(currentTrack.title), findsWidgets);
          final showQueue = find.byTooltip(l10n.playbackShowQueue);
          expect(showQueue, findsOneWidget);
          expect(
            tester.getSemantics(showQueue).tooltip,
            l10n.playbackShowQueue,
          );
          if (capture) {
            await expectLater(
              find.byType(MusicApp),
              matchesGoldenFile(
                Uri.file(
                  '/tmp/fura-l10n-$providerSlug-$localeSlug-home-desktop.png',
                ),
              ),
            );
          }

          await tester.tap(
            find.byKey(const ValueKey('now-playing-open-expanded')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('expanded-now-playing-page')),
            findsOneWidget,
          );
          expect(find.text(l10n.nowPlayingTitle), findsOneWidget);
          if (capture) {
            await expectLater(
              find.byType(MusicApp),
              matchesGoldenFile(
                Uri.file(
                  '/tmp/fura-l10n-$providerSlug-$localeSlug-now-playing-desktop.png',
                ),
              ),
            );
          }
          await tester.tap(
            find.byKey(const ValueKey('expanded-now-playing-back')),
          );
          await tester.pumpAndSettle();

          await tester.tap(showQueue);
          await tester.pumpAndSettle();
          expect(find.text(l10n.queueTitle), findsOneWidget);
          final closeQueue = find.byTooltip(l10n.queueClose);
          expect(tester.getSemantics(closeQueue).tooltip, l10n.queueClose);
          await tester.tap(closeQueue);
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const ValueKey('open-track-search')));
          await tester.pumpAndSettle();
          expect(
            find.text(l10n.searchFindTracksTitle(providerName)),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('track-search-field')),
            findsOneWidget,
          );
          expect(find.bySemanticsLabel(l10n.searchSongHint), findsOneWidget);
          if (capture &&
              localePreference == AppLocalePreference.simplifiedChinese) {
            await expectLater(
              find.byType(MusicApp),
              matchesGoldenFile(
                Uri.file('/tmp/fura-l10n-$providerSlug-zh-hans-search.png'),
              ),
            );
          }

          await _openLibrary(tester);
          expect(find.text(l10n.likedTitle), findsWidgets);
          if (capture &&
              localePreference == AppLocalePreference.simplifiedChinese) {
            await expectLater(
              find.byType(MusicApp),
              matchesGoldenFile(
                Uri.file('/tmp/fura-l10n-$providerSlug-zh-hans-library.png'),
              ),
            );
          }

          await tester.tap(find.byKey(const ValueKey('open-settings')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('settings-nav-language')));
          await tester.pumpAndSettle();
          expect(find.text(l10n.settingsTitle), findsWidgets);
          final backToMusic = find.byTooltip(l10n.shellBackToMusic);
          expect(backToMusic, findsOneWidget);
          expect(
            tester.getSemantics(backToMusic).tooltip,
            l10n.shellBackToMusic,
          );
          if (capture) {
            await expectLater(
              find.byType(MusicApp),
              matchesGoldenFile(
                Uri.file(
                  '/tmp/fura-l10n-$providerSlug-$localeSlug-settings-desktop.png',
                ),
              ),
            );
          }

          tester.view.physicalSize = const Size(390, 844);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (capture && provider == AppMusicProvider.qqMusic) {
            await expectLater(
              find.byType(MusicApp),
              matchesGoldenFile(
                Uri.file('/tmp/fura-l10n-$localeSlug-settings-compact.png'),
              ),
            );
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();

          MusicProviderDependencies signedOutProvider(AppMusicProvider target) {
            final isQq = target == AppMusicProvider.qqMusic;
            final id = isQq ? 'qq-music' : 'netease-cloud-music';
            return _providerFixture(
              authenticationGateway: isQq
                  ? _WidgetGateway(_WaitingSession())
                  : _ProviderWidgetGateway(providerId: id),
              capabilities: isQq
                  ? MusicProviderCapabilities.qqMusic
                  : MusicProviderCapabilities.netEaseCloudMusic,
              providerId: id,
              accountName: 'Signed-out fixture',
              searchGateway: _WidgetSearchGateway(
                const TrackSearchPageResult(),
              ),
            );
          }

          await tester.pumpWidget(
            MusicApp(
              key: ValueKey(
                'locale-matrix-$providerSlug-$localeSlug-signed-out',
              ),
              bootstrap: _dualProviderBootstrap,
              initialSettings: AppSettings(
                theme: AppThemePreference.light,
                musicProvider: provider,
                localePreference: localePreference,
              ),
              providerDependencies: BuiltInProviderDependencies(
                qqMusic: signedOutProvider(AppMusicProvider.qqMusic),
                netEase: signedOutProvider(AppMusicProvider.netEaseCloudMusic),
              ),
              mediaResolutionGateway: const _UnavailableMediaGateway(),
              lyricGateway: const _WidgetLyricGateway(),
            ),
          );
          await tester.pumpAndSettle();
          await _openSignInDialog(tester);
          expect(find.text(l10n.authSignInTitle(providerName)), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('start-qq-login-button')));
          await tester.pumpAndSettle();
          final qrMethod = find.byKey(const ValueKey('qr-login-method'));
          expect(qrMethod, findsOneWidget);
          await tester.ensureVisible(qrMethod);
          await tester.pumpAndSettle();
          final qrSemantics = provider == AppMusicProvider.qqMusic
              ? l10n.authQqQrSemantics
              : l10n.authProviderQrSemantics(providerName);
          expect(find.bySemanticsLabel(qrSemantics), findsOneWidget);
          if (capture &&
              localePreference == AppLocalePreference.simplifiedChinese) {
            await expectLater(
              find.byType(MusicApp),
              matchesGoldenFile(
                Uri.file('/tmp/fura-l10n-$providerSlug-zh-hans-auth.png'),
              ),
            );
          }
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }

  for (final localePreference in const [
    AppLocalePreference.english,
    AppLocalePreference.simplifiedChinese,
  ]) {
    testWidgets(
      '${localePreference.name} compact settings and auth tolerate large text',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final l10n = localePreference == AppLocalePreference.english
            ? _en
            : _zh;

        await tester.pumpWidget(
          MusicApp(
            bootstrap: _bootstrap,
            initialSettings: AppSettings(
              theme: AppThemePreference.light,
              localePreference: localePreference,
            ),
            authenticationGateway: _WidgetGateway(_WaitingSession()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-recommendations')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-settings')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('settings-compact-language')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-language-selector')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('settings-back')));
        await tester.pumpAndSettle();
        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        await _openSignInDialog(tester);
        expect(
          find.text(l10n.authSignInTitle(l10n.providerQqMusic)),
          findsOneWidget,
        );
        expect(find.byTooltip(l10n.authCloseTooltip), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _changeLanguagePreference(
  WidgetTester tester,
  AppLocalePreference preference,
) async {
  await tester.tap(find.byKey(const ValueKey('settings-language-selector')));
  await tester.pumpAndSettle();
  final option = find.byWidgetPredicate(
    (widget) =>
        widget is RadioListTile<AppLocalePreference> &&
        widget.value == preference,
  );
  expect(option, findsOneWidget);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _switchProviderFromDesktopSettings(
  WidgetTester tester,
  ValueKey<String> providerKey, {
  String? reviewImagePath,
}) async {
  await tester.tap(find.byKey(const ValueKey('open-settings')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('settings-nav-musicService')));
  await tester.pumpAndSettle();
  if (reviewImagePath != null) {
    await expectLater(
      find.byType(MusicApp),
      matchesGoldenFile(Uri.file(reviewImagePath)),
    );
  }
  await tester.tap(find.byKey(const ValueKey('settings-provider-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(providerKey));
  await tester.pumpAndSettle();
}

const _bootstrap = BootstrapStatus(
  coreVersion: '0.1.0-test',
  providers: [
    ProviderStatus(
      id: 'qq-music',
      displayName: 'QQ Music',
      implementedCapabilities: ['Authentication'],
    ),
  ],
  defaultProviderId: 'qq-music',
);

const _dualProviderBootstrap = BootstrapStatus(
  coreVersion: '0.1.0-test',
  providers: [
    ProviderStatus(
      id: 'qq-music',
      displayName: 'QQ Music',
      implementedCapabilities: ['Authentication', 'Search'],
    ),
    ProviderStatus(
      id: 'netease-cloud-music',
      displayName: 'NetEase Cloud Music',
      implementedCapabilities: ['Authentication', 'Search'],
    ),
  ],
  defaultProviderId: 'qq-music',
);

MusicProviderDependencies _providerFixture({
  required QqMusicAuthenticationGateway authenticationGateway,
  required MusicProviderCapabilities capabilities,
  required String providerId,
  required String accountName,
  required TrackSearchGateway searchGateway,
  RecommendedPlaylistGateway? recommendedPlaylistGateway,
  List<PlaylistTrackSummary> personalizedTracks = const [],
  List<PlaylistTrackSummary> dailyTracks = const [],
  List<PlaylistTrackSummary> newSongs = const [],
}) {
  final initialAlbumRegion = capabilities.supportedNewAlbumRegions.first;
  final initialNewSongCategory =
      capabilities.supportedNewSongCategories.contains(NewSongCategory.latest)
      ? NewSongCategory.latest
      : capabilities.supportedNewSongCategories.first;
  final libraryResult = UserLibraryResult(
    playlists: [
      UserPlaylistSummary(
        providerId: providerId,
        opaqueId: 'liked',
        title: 'Liked on $accountName',
        isLikedSongs: true,
        trackCount: 0,
      ),
    ],
  );
  return MusicProviderDependencies(
    authenticationGateway: authenticationGateway,
    home: AuthenticatedHomeDependencies(
      accountSummaryGateway: _WidgetAccountSummaryGateway(
        AccountSummaryLoadResult(
          summary: AuthenticatedAccountSummary(displayName: accountName),
        ),
      ),
      dailyRecommendationGateway: _WidgetDailyRecommendationGateway(
        DailyRecommendationResult(tracks: dailyTracks),
      ),
      personalizedPlaylistsGateway: const _WidgetPersonalizedPlaylistsGateway(
        PersonalizedPlaylistsResult(),
      ),
      personalizedTracksGateway: _WidgetPersonalizedTracksGateway(
        PersonalizedTracksResult(tracks: personalizedTracks),
      ),
      relatedTracksGateway: const _WidgetRelatedTracksGateway(
        RelatedTracksResult(),
      ),
    ),
    library: AuthenticatedLibraryDependencies(
      libraryGateway: _WidgetLibraryGateway([
        libraryResult,
        libraryResult,
        libraryResult,
      ]),
      playlistDetailGateway: _WidgetDetailGateway([
        const PlaylistTrackPageResult(),
      ]),
      albumTrackGateway: _WidgetAlbumGateway(const AlbumTrackPageResult()),
      albumDetailsGateway: const _WidgetAlbumDetailsGateway(),
      artistTrackGateway: _WidgetArtistGateway(const ArtistTrackPageResult()),
      artistAlbumGateway: _WidgetArtistAlbumGateway(
        const ArtistAlbumPageResult(),
      ),
      favoriteAlbumGateway: _WidgetFavoriteAlbumGateway(
        const FavoriteAlbumPageResult(),
      ),
      favoriteArtistGateway: _WidgetFavoriteArtistGateway(
        const FavoriteArtistPageResult(),
      ),
    ),
    discovery: AuthenticatedDiscoveryDependencies(
      trackSearchGateway: searchGateway,
      artistSearchGateway: _WidgetArtistSearchGateway(
        const ArtistSearchPageResult(),
      ),
      albumSearchGateway: _WidgetAlbumSearchGateway(
        const AlbumSearchPageResult(),
      ),
      playlistSearchGateway: _WidgetPlaylistSearchGateway(
        const PlaylistSearchPageResult(),
      ),
      recommendedPlaylistGateway:
          recommendedPlaylistGateway ??
          _WidgetRecommendedPlaylistGateway(
            RecommendedPlaylistPageResult(
              playlists: [
                RecommendedPlaylistSummary(
                  providerId: providerId,
                  opaqueId: 'public-playlist',
                  title: '$accountName Public Playlist',
                  trackCount: 20,
                ),
              ],
            ),
          ),
      newAlbumGateway: _WidgetNewAlbumGateway(
        NewAlbumPageResult(region: initialAlbumRegion),
      ),
      newSongGateway: _WidgetNewSongGateway({
        initialNewSongCategory: NewSongResult(
          category: initialNewSongCategory,
          tracks: newSongs,
        ),
      }),
      rankingGateway: _WidgetRankingGateway(
        const RankingGroupResult(),
        const RankingTrackPageResult(),
      ),
      radarGateway: _WidgetRadarGateway(const RadarTrackPageResult(page: 1)),
    ),
    capabilities: capabilities,
    initialCredentialRestore: CredentialRestoreResult.signedOut,
  );
}

class _LoginProviderHarness extends StatefulWidget {
  const _LoginProviderHarness({
    required this.qq,
    required this.netEase,
    super.key,
  });

  final MusicProviderDependencies qq;
  final MusicProviderDependencies netEase;

  @override
  State<_LoginProviderHarness> createState() => _LoginProviderHarnessState();
}

class _LoginProviderHarnessState extends State<_LoginProviderHarness> {
  AppMusicProvider _provider = AppMusicProvider.qqMusic;
  late final AuthenticatedPlaybackDependencies _playback =
      AuthenticatedPlaybackDependencies(
        playbackHost: createForegroundAppPlaybackHost(
          mediaResolutionGateway: const _UnavailableMediaGateway(),
          lyricGateway: const _WidgetLyricGateway(),
          playbackQueueGateway: _WidgetPlaybackQueueGateway(),
          audioEngine: AudioplayersForegroundAudioEngine(),
        ),
        trackCommentGateway: const RustTrackCommentGateway(),
      );

  void select(AppMusicProvider provider) =>
      setState(() => _provider = provider);

  @override
  void dispose() {
    unawaited(_playback.playbackHost.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = switch (_provider) {
      AppMusicProvider.qqMusic => widget.qq,
      AppMusicProvider.netEaseCloudMusic => widget.netEase,
    };
    final settings = AppSettings.defaults.copyWith(musicProvider: _provider);
    return MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: LoginPage(
        bootstrap: _dualProviderBootstrap,
        authenticationGateway: dependencies.authenticationGateway,
        homeDependencies: dependencies.home,
        libraryDependencies: dependencies.library,
        discoveryDependencies: dependencies.discovery,
        playbackDependencies: _playback,
        capabilities: dependencies.capabilities,
        desktopQuickLoginEnabled: dependencies.desktopQuickLoginEnabled,
        settings: settings,
        onSettingsChanged: (next) async {
          select(next.musicProvider);
          return AppSettingsWriteResult.saved;
        },
        initialCredentialRestore: dependencies.initialCredentialRestore,
      ),
    );
  }
}

class _WidgetSettingsDocumentStorage implements AppSettingsDocumentStorage {
  String? document;

  @override
  Future<void> delete() async => document = null;

  @override
  Future<String?> read() async => document;

  @override
  Future<void> write(String document) async => this.document = document;
}

class _WidgetGateway
    implements
        QqMusicAuthenticationGateway,
        MultiMethodQqMusicAuthenticationGateway,
        DesktopQuickQqMusicAuthenticationGateway {
  _WidgetGateway(
    this.session, {
    this.authenticated = false,
    this.desktopQuickStart = const DesktopQuickLoginStart(
      failure: DesktopQuickLoginFailure.clientUnavailable,
    ),
    CredentialVerificationOperation? verificationOperation,
    List<FutureOr<CredentialSignOutResult>> signOutResults = const [
      CredentialSignOutResult.signedOut,
    ],
  }) : _verificationOperation =
           verificationOperation ??
           const _ImmediateWidgetVerification(
             CredentialVerificationResult.noRestoredCredential,
           ),
       _signOutResults = List.of(signOutResults);

  final _WaitingSession session;
  bool authenticated;
  final DesktopQuickLoginStart desktopQuickStart;
  final CredentialVerificationOperation _verificationOperation;
  final List<FutureOr<CredentialSignOutResult>> _signOutResults;
  int signOutCalls = 0;
  int desktopQuickStartCalls = 0;

  @override
  DesktopQuickLoginStartOperation beginDesktopQuickLoginStart() {
    desktopQuickStartCalls += 1;
    return _WidgetDesktopQuickLoginStartOperation(desktopQuickStart);
  }

  @override
  bool get hasAuthenticatedCredential => authenticated;

  @override
  LoginStartOperation beginStart() => _WidgetStartOperation(
    LoginStart(
      session: session,
      challenge: LoginChallenge(
        imageFormat: LoginImageFormat.png,
        imageBytes: Uint8List.fromList(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
            'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        ),
      ),
    ),
  );

  @override
  LoginStartOperation beginQrStart(LoginQrChannel channel) => beginStart();

  @override
  CredentialVerificationOperation beginCredentialVerification() =>
      _verificationOperation;

  @override
  Future<CredentialPersistenceResult> persistAuthenticatedCredential() async =>
      CredentialPersistenceResult.stored;

  @override
  Future<CredentialRestoreResult> restoreCredential() async =>
      CredentialRestoreResult.signedOut;

  @override
  Future<CredentialSignOutResult> signOut() async {
    final result = await _signOutResults[signOutCalls++];
    if (result != CredentialSignOutResult.coreUnavailable) {
      authenticated = false;
    }
    return result;
  }
}

class _ProviderWidgetGateway
    implements
        QqMusicAuthenticationGateway,
        ProviderAuthenticationPresentation {
  _ProviderWidgetGateway({
    required this.providerId,
    this.authenticated = false,
  });

  @override
  final String providerId;

  bool authenticated;
  int restoreCalls = 0;
  int signOutCalls = 0;

  @override
  bool get hasAuthenticatedCredential => authenticated;

  @override
  LoginStartOperation beginStart() => _WidgetStartOperation(
    LoginStart(
      session: _WaitingSession(),
      challenge: LoginChallenge(
        imageFormat: LoginImageFormat.png,
        imageBytes: Uint8List.fromList(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
            'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        ),
        externalConfirmationUri: providerId == 'netease-cloud-music'
            ? Uri.parse(
                'https://music.163.com/st/platform/scanlogin?'
                'codekey=synthetic-key&chainId=synthetic-chain&'
                'hdw_device=web&hdw_appid=web&hitExp=1',
              )
            : null,
      ),
    ),
  );

  @override
  CredentialVerificationOperation beginCredentialVerification() =>
      const _ImmediateWidgetVerification(
        CredentialVerificationResult.noRestoredCredential,
      );

  @override
  Future<CredentialPersistenceResult> persistAuthenticatedCredential() async =>
      CredentialPersistenceResult.stored;

  @override
  Future<CredentialRestoreResult> restoreCredential() async {
    restoreCalls += 1;
    return CredentialRestoreResult.signedOut;
  }

  @override
  Future<CredentialSignOutResult> signOut() async {
    signOutCalls += 1;
    authenticated = false;
    return CredentialSignOutResult.signedOut;
  }
}

class _OfficialWebProviderWidgetGateway extends _ProviderWidgetGateway
    implements
        OfficialWebAuthenticationGateway,
        OfficialWebOnlyAuthenticationGateway,
        OfficialWebAuthenticationPresentation {
  _OfficialWebProviderWidgetGateway({required super.providerId});

  final ChangeNotifier _presentation = ChangeNotifier();
  OfficialWebLoginPresentationStage _stage =
      OfficialWebLoginPresentationStage.idle;
  Widget? _view;
  _PendingWidgetOfficialWebOperation? operation;

  @override
  bool get supportsOfficialWebLogin => true;

  @override
  Listenable get officialWebPresentationListenable => _presentation;

  @override
  OfficialWebLoginPresentationStage get officialWebPresentationStage => _stage;

  @override
  Widget? get officialWebLoginView => _view;

  @override
  OfficialWebAuthenticationOperation beginOfficialWebLogin() {
    _stage = OfficialWebLoginPresentationStage.waitingForSignIn;
    _view = const SizedBox(key: ValueKey('fake-official-webview'));
    _presentation.notifyListeners();
    return operation = _PendingWidgetOfficialWebOperation(this);
  }

  void cancelPresentation() {
    _stage = OfficialWebLoginPresentationStage.idle;
    _view = null;
    _presentation.notifyListeners();
  }
}

class _PendingWidgetOfficialWebOperation
    implements OfficialWebAuthenticationOperation {
  _PendingWidgetOfficialWebOperation(this.gateway);

  final _OfficialWebProviderWidgetGateway gateway;
  final Completer<OfficialWebAuthenticationOutcome> _result =
      Completer<OfficialWebAuthenticationOutcome>();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    gateway.cancelPresentation();
    if (!_result.isCompleted) {
      _result.complete(
        const OfficialWebAuthenticationOutcome(
          authenticated: false,
          failure: OfficialWebAuthenticationFailure.cancelled,
        ),
      );
    }
    return true;
  }

  @override
  Future<OfficialWebAuthenticationOutcome> run() => _result.future;
}

class _WidgetDesktopQuickLoginStartOperation
    implements DesktopQuickLoginStartOperation {
  _WidgetDesktopQuickLoginStartOperation(this.result);

  final DesktopQuickLoginStart result;
  bool active = true;

  @override
  bool cancel() {
    final wasActive = active;
    active = false;
    return wasActive;
  }

  @override
  Future<DesktopQuickLoginStart> run() async => result;
}

class _WidgetDesktopQuickLoginSession implements DesktopQuickLoginSession {
  final List<int> selections = [];
  bool active = true;

  @override
  Future<DesktopQuickLoginUpdate> authorize(int selectionId) async {
    selections.add(selectionId);
    active = false;
    return const DesktopQuickLoginUpdate(
      authenticated: true,
      sessionActive: false,
    );
  }

  @override
  bool cancel() {
    final wasActive = active;
    active = false;
    return wasActive;
  }

  @override
  bool get isActive => active;
}

class _WidgetLibraryGateway implements UserLibraryGateway {
  _WidgetLibraryGateway(this.results);

  final List<UserLibraryResult> results;
  int _next = 0;

  @override
  UserLibraryLoadOperation beginLoad() =>
      _WidgetLibraryOperation(results[_next++]);
}

class _PendingWidgetLibraryGateway implements UserLibraryGateway {
  final Completer<UserLibraryResult> _result = Completer<UserLibraryResult>();
  int loadCalls = 0;

  void complete(UserLibraryResult result) => _result.complete(result);

  @override
  UserLibraryLoadOperation beginLoad() {
    loadCalls += 1;
    return _PendingWidgetLibraryOperation(_result.future);
  }
}

class _PendingWidgetLibraryOperation implements UserLibraryLoadOperation {
  const _PendingWidgetLibraryOperation(this.result);

  final Future<UserLibraryResult> result;

  @override
  bool cancel() => true;

  @override
  Future<UserLibraryResult> run() => result;
}

class _WidgetLibraryOperation implements UserLibraryLoadOperation {
  const _WidgetLibraryOperation(this.result);

  final UserLibraryResult result;

  @override
  bool cancel() => true;

  @override
  Future<UserLibraryResult> run() async => result;
}

class _UnusedSearchGateway implements TrackSearchGateway {
  const _UnusedSearchGateway();

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) => throw StateError('search should not run in this navigation test');
}

class _WidgetSearchGateway implements TrackSearchGateway {
  _WidgetSearchGateway(this.result);

  final TrackSearchPageResult result;
  final List<(String, int, int)> requests = [];

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return _WidgetSearchOperation(result);
  }
}

AlbumTrackPageResult _withAlbumContinuation(AlbumTrackPageResult result) =>
    result.continuationOffset >= 0
    ? result
    : AlbumTrackPageResult(
        offset: result.offset,
        continuationOffset:
            result.offset + result.tracks.length + result.omittedTrackCount,
        total: result.total,
        hasMore: result.hasMore,
        tracks: result.tracks,
        omittedTrackCount: result.omittedTrackCount,
        failure: result.failure,
      );

ArtistTrackPageResult _withArtistTrackContinuation(
  ArtistTrackPageResult result,
) => result.continuationOffset >= 0
    ? result
    : ArtistTrackPageResult(
        offset: result.offset,
        continuationOffset:
            result.offset + result.tracks.length + result.omittedTrackCount,
        total: result.total,
        hasMore: result.hasMore,
        tracks: result.tracks,
        omittedTrackCount: result.omittedTrackCount,
        failure: result.failure,
      );

ArtistAlbumPageResult _withArtistAlbumContinuation(
  ArtistAlbumPageResult result,
) => result.continuationOffset >= 0
    ? result
    : ArtistAlbumPageResult(
        offset: result.offset,
        continuationOffset:
            result.offset + result.albums.length + result.omittedAlbumCount,
        total: result.total,
        hasMore: result.hasMore,
        albums: result.albums,
        omittedAlbumCount: result.omittedAlbumCount,
        failure: result.failure,
      );

RecommendedPlaylistPageResult _withRecommendationContinuation(
  RecommendedPlaylistPageResult result,
) => result.continuationOffset >= 0
    ? result
    : RecommendedPlaylistPageResult(
        offset: result.offset,
        continuationOffset:
            result.offset +
            result.playlists.length +
            result.omittedPlaylistCount,
        hasMore: result.hasMore,
        playlists: result.playlists,
        omittedPlaylistCount: result.omittedPlaylistCount,
        failure: result.failure,
      );

NewAlbumPageResult _withNewAlbumContinuation(NewAlbumPageResult result) =>
    result.continuationOffset >= 0
    ? result
    : NewAlbumPageResult(
        region: result.region,
        offset: result.offset,
        continuationOffset:
            result.offset + result.releases.length + result.omittedReleaseCount,
        total: result.total,
        hasMore: result.hasMore,
        releases: result.releases,
        omittedReleaseCount: result.omittedReleaseCount,
        failure: result.failure,
      );

FavoriteAlbumPageResult _withFavoriteAlbumContinuation(
  FavoriteAlbumPageResult result,
) => result.continuationOffset >= 0
    ? result
    : FavoriteAlbumPageResult(
        offset: result.offset,
        continuationOffset:
            result.offset + result.albums.length + result.omittedAlbumCount,
        total: result.total,
        hasMore: result.hasMore,
        albums: result.albums,
        omittedAlbumCount: result.omittedAlbumCount,
        failure: result.failure,
      );

FavoriteArtistPageResult _withFavoriteArtistContinuation(
  FavoriteArtistPageResult result,
) => result.continuationOffset >= 0
    ? result
    : FavoriteArtistPageResult(
        offset: result.offset,
        continuationOffset:
            result.offset + result.artists.length + result.omittedArtistCount,
        total: result.total,
        hasMore: result.hasMore,
        artists: result.artists,
        omittedArtistCount: result.omittedArtistCount,
        failure: result.failure,
      );

RankingTrackPageResult _withRankingContinuation(
  RankingTrackPageResult result,
) => result.continuationOffset >= 0
    ? result
    : RankingTrackPageResult(
        ranking: result.ranking,
        offset: result.offset,
        continuationOffset:
            result.offset + result.tracks.length + result.omittedTrackCount,
        total: result.total,
        hasMore: result.hasMore,
        tracks: result.tracks,
        omittedTrackCount: result.omittedTrackCount,
        failure: result.failure,
      );

PlaylistTrackPageResult _withPlaylistContinuation(
  PlaylistTrackPageResult result,
) => result.nextOffset >= 0
    ? result
    : PlaylistTrackPageResult(
        offset: result.offset,
        nextOffset:
            result.offset + result.tracks.length + result.omittedTrackCount,
        total: result.total,
        totalIsExact: result.totalIsExact,
        hasMore: result.hasMore,
        omittedTrackCount: result.omittedTrackCount,
        tracks: result.tracks,
        failure: result.failure,
      );

class _WidgetSearchOperation implements TrackSearchPageLoadOperation {
  const _WidgetSearchOperation(this.result);

  final TrackSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<TrackSearchPageResult> run() async => result;
}

class _WidgetAlbumGateway implements AlbumTrackGateway {
  _WidgetAlbumGateway(this.result);

  final AlbumTrackPageResult result;
  final List<(AlbumSummary, int, int)> requests = [];

  @override
  AlbumTrackPageLoadOperation beginLoad({
    required AlbumSummary album,
    required int offset,
    required int size,
  }) {
    requests.add((album, offset, size));
    return _WidgetAlbumOperation(result);
  }
}

class _WidgetAlbumDetailsGateway implements AlbumDetailsGateway {
  const _WidgetAlbumDetailsGateway({this.artists = const []});

  final List<ArtistSummary> artists;

  @override
  AlbumDetailsLoadOperation beginLoad(AlbumSummary album) =>
      _WidgetAlbumDetailsOperation(
        AlbumDetailsResult(
          details: AlbumDetails(album: album, artists: artists),
        ),
      );
}

class _WidgetAlbumDetailsOperation implements AlbumDetailsLoadOperation {
  const _WidgetAlbumDetailsOperation(this.result);

  final AlbumDetailsResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumDetailsResult> run() async => result;
}

class _WidgetArtistSearchGateway implements ArtistSearchGateway {
  _WidgetArtistSearchGateway(this.result);

  final ArtistSearchPageResult result;
  final List<(String, int, int)> requests = [];

  @override
  ArtistSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return _WidgetArtistSearchOperation(result);
  }
}

class _WidgetArtistSearchOperation implements ArtistSearchPageLoadOperation {
  const _WidgetArtistSearchOperation(this.result);

  final ArtistSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistSearchPageResult> run() async => result;
}

class _WidgetAlbumSearchGateway implements AlbumSearchGateway {
  _WidgetAlbumSearchGateway(this.result);

  final AlbumSearchPageResult result;
  final List<(String, int, int)> requests = [];

  @override
  AlbumSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return _WidgetAlbumSearchOperation(result);
  }
}

class _WidgetAlbumSearchOperation implements AlbumSearchPageLoadOperation {
  const _WidgetAlbumSearchOperation(this.result);

  final AlbumSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumSearchPageResult> run() async => result;
}

class _WidgetPlaylistSearchGateway implements PlaylistSearchGateway {
  _WidgetPlaylistSearchGateway(this.result);

  final PlaylistSearchPageResult result;
  final List<(String, int, int)> requests = [];

  @override
  PlaylistSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return _WidgetPlaylistSearchOperation(result);
  }
}

class _WidgetPlaylistSearchOperation
    implements PlaylistSearchPageLoadOperation {
  const _WidgetPlaylistSearchOperation(this.result);

  final PlaylistSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistSearchPageResult> run() async => result;
}

class _WidgetAlbumOperation implements AlbumTrackPageLoadOperation {
  const _WidgetAlbumOperation(this.result);

  final AlbumTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumTrackPageResult> run() async => _withAlbumContinuation(result);
}

class _WidgetArtistGateway implements ArtistTrackGateway {
  _WidgetArtistGateway(this.result);

  final ArtistTrackPageResult result;
  final List<(ArtistSummary, int, int)> requests = [];

  @override
  ArtistTrackPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) {
    requests.add((artist, offset, size));
    return _WidgetArtistOperation(result);
  }
}

class _WidgetArtistOperation implements ArtistTrackPageLoadOperation {
  const _WidgetArtistOperation(this.result);

  final ArtistTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistTrackPageResult> run() async =>
      _withArtistTrackContinuation(result);
}

class _WidgetArtistAlbumGateway implements ArtistAlbumGateway {
  _WidgetArtistAlbumGateway(this.result);

  final ArtistAlbumPageResult result;
  final List<(ArtistSummary, int, int)> requests = [];

  @override
  ArtistAlbumPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) {
    requests.add((artist, offset, size));
    return _WidgetArtistAlbumOperation(result);
  }
}

class _WidgetArtistAlbumOperation implements ArtistAlbumPageLoadOperation {
  const _WidgetArtistAlbumOperation(this.result);

  final ArtistAlbumPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistAlbumPageResult> run() async =>
      _withArtistAlbumContinuation(result);
}

class _WidgetAccountSummaryGateway implements AccountSummaryGateway {
  const _WidgetAccountSummaryGateway(this.result);

  final AccountSummaryLoadResult result;

  @override
  AccountSummaryLoadOperation beginLoad() =>
      _WidgetAccountSummaryOperation(result);
}

class _WidgetAccountSummaryOperation implements AccountSummaryLoadOperation {
  const _WidgetAccountSummaryOperation(this.result);

  final AccountSummaryLoadResult result;

  @override
  bool cancel() => true;

  @override
  Future<AccountSummaryLoadResult> run() async => result;
}

class _WidgetDailyRecommendationGateway implements DailyRecommendationGateway {
  const _WidgetDailyRecommendationGateway(this.result);

  final DailyRecommendationResult result;

  @override
  DailyRecommendationLoadOperation beginLoad() =>
      _WidgetDailyRecommendationOperation(result);
}

class _WidgetDailyRecommendationOperation
    implements DailyRecommendationLoadOperation {
  const _WidgetDailyRecommendationOperation(this.result);

  final DailyRecommendationResult result;

  @override
  bool cancel() => true;

  @override
  Future<DailyRecommendationResult> run() async => result;
}

class _WidgetPersonalizedPlaylistsGateway
    implements PersonalizedPlaylistsGateway {
  const _WidgetPersonalizedPlaylistsGateway(this.result);

  final PersonalizedPlaylistsResult result;

  @override
  PersonalizedPlaylistsLoadOperation beginLoad() =>
      _WidgetPersonalizedPlaylistsOperation(result);
}

class _WidgetPersonalizedPlaylistsOperation
    implements PersonalizedPlaylistsLoadOperation {
  const _WidgetPersonalizedPlaylistsOperation(this.result);

  final PersonalizedPlaylistsResult result;

  @override
  bool cancel() => true;

  @override
  Future<PersonalizedPlaylistsResult> run() async => result;
}

class _ScriptedWidgetPersonalizedPlaylistsGateway
    implements PersonalizedPlaylistsGateway {
  _ScriptedWidgetPersonalizedPlaylistsGateway(this.results);

  final List<Future<PersonalizedPlaylistsResult>> results;
  int requests = 0;

  @override
  PersonalizedPlaylistsLoadOperation beginLoad() {
    final index = requests++;
    return _FutureWidgetPersonalizedPlaylistsOperation(results[index]);
  }
}

class _FutureWidgetPersonalizedPlaylistsOperation
    implements PersonalizedPlaylistsLoadOperation {
  const _FutureWidgetPersonalizedPlaylistsOperation(this.result);

  final Future<PersonalizedPlaylistsResult> result;

  @override
  bool cancel() => true;

  @override
  Future<PersonalizedPlaylistsResult> run() => result;
}

class _WidgetPersonalizedTracksGateway implements PersonalizedTracksGateway {
  const _WidgetPersonalizedTracksGateway(this.result);

  final PersonalizedTracksResult result;

  @override
  PersonalizedTracksLoadOperation beginLoad() =>
      _WidgetPersonalizedTracksOperation(result);
}

class _WidgetPersonalizedTracksOperation
    implements PersonalizedTracksLoadOperation {
  const _WidgetPersonalizedTracksOperation(this.result);

  final PersonalizedTracksResult result;

  @override
  bool cancel() => true;

  @override
  Future<PersonalizedTracksResult> run() async => result;
}

class _WidgetRecentListening implements RecentListeningGateway {
  _WidgetRecentListening(this.seed);
  final PlaylistTrackSummary seed;
  @override
  PlaylistTrackSummary? choose() => seed;
  @override
  void observe(PlaylistTrackSummary? track, int positionMs, bool playing) {}
  @override
  void dispose() {}
}

class _WidgetRelatedTracksGateway implements RelatedTracksGateway {
  const _WidgetRelatedTracksGateway(this.result, {this.seeds});

  final RelatedTracksResult result;
  final List<PlaylistTrackSummary>? seeds;

  @override
  RelatedTracksLoadOperation beginLoad(PlaylistTrackSummary seed) {
    seeds?.add(seed);
    return _WidgetRelatedTracksOperation(result);
  }
}

class _WidgetRelatedTracksOperation implements RelatedTracksLoadOperation {
  const _WidgetRelatedTracksOperation(this.result);

  final RelatedTracksResult result;

  @override
  bool cancel() => true;

  @override
  Future<RelatedTracksResult> run() async => result;
}

class _WidgetRecommendedPlaylistGateway implements RecommendedPlaylistGateway {
  _WidgetRecommendedPlaylistGateway(this.result);

  final RecommendedPlaylistPageResult result;
  final List<(int, int)> requests = [];

  @override
  RecommendedPlaylistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return _WidgetRecommendedPlaylistOperation(result);
  }
}

class _WidgetRecommendedPlaylistOperation
    implements RecommendedPlaylistPageLoadOperation {
  const _WidgetRecommendedPlaylistOperation(this.result);

  final RecommendedPlaylistPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<RecommendedPlaylistPageResult> run() async =>
      _withRecommendationContinuation(result);
}

class _ControlledWidgetRecommendedPlaylistGateway
    implements RecommendedPlaylistGateway {
  final Completer<RecommendedPlaylistPageResult> _completer = Completer();

  void complete(RecommendedPlaylistPageResult result) =>
      _completer.complete(result);

  @override
  RecommendedPlaylistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _FutureWidgetRecommendedPlaylistOperation(_completer.future);
}

class _FutureWidgetRecommendedPlaylistOperation
    implements RecommendedPlaylistPageLoadOperation {
  const _FutureWidgetRecommendedPlaylistOperation(this.result);

  final Future<RecommendedPlaylistPageResult> result;

  @override
  bool cancel() => true;

  @override
  Future<RecommendedPlaylistPageResult> run() async =>
      _withRecommendationContinuation(await result);
}

class _WidgetNewAlbumGateway implements NewAlbumGateway {
  _WidgetNewAlbumGateway(this.result);

  final NewAlbumPageResult result;
  final List<(NewAlbumRegion, int, int)> requests = [];

  @override
  NewAlbumPageLoadOperation beginLoad({
    required NewAlbumRegion region,
    required int offset,
    required int size,
  }) {
    requests.add((region, offset, size));
    return _WidgetNewAlbumOperation(result);
  }
}

class _WidgetNewAlbumOperation implements NewAlbumPageLoadOperation {
  const _WidgetNewAlbumOperation(this.result);

  final NewAlbumPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<NewAlbumPageResult> run() async => _withNewAlbumContinuation(result);
}

class _WidgetNewSongGateway implements NewSongGateway {
  _WidgetNewSongGateway(this.results);

  final Map<NewSongCategory, NewSongResult> results;
  final List<NewSongCategory> requests = [];

  @override
  NewSongLoadOperation beginLoad({required NewSongCategory category}) {
    requests.add(category);
    return _WidgetNewSongOperation(results[category]!);
  }
}

class _WidgetNewSongOperation implements NewSongLoadOperation {
  const _WidgetNewSongOperation(this.result);

  final NewSongResult result;

  @override
  bool cancel() => true;

  @override
  Future<NewSongResult> run() async => result;
}

class _TransitionWidgetNewSongGateway implements NewSongGateway {
  final Completer<NewSongResult> western = Completer<NewSongResult>();

  @override
  NewSongLoadOperation beginLoad({required NewSongCategory category}) {
    if (category == NewSongCategory.latest) {
      return const _WidgetNewSongOperation(
        NewSongResult(category: NewSongCategory.latest),
      );
    }
    if (category == NewSongCategory.western) {
      return _FutureWidgetNewSongOperation(western.future);
    }
    return _WidgetNewSongOperation(NewSongResult(category: category));
  }
}

class _FutureWidgetNewSongOperation implements NewSongLoadOperation {
  const _FutureWidgetNewSongOperation(this.result);

  final Future<NewSongResult> result;

  @override
  bool cancel() => true;

  @override
  Future<NewSongResult> run() => result;
}

class _WidgetFavoriteAlbumGateway implements FavoriteAlbumGateway {
  _WidgetFavoriteAlbumGateway(this.result);

  final FavoriteAlbumPageResult result;
  final List<(int, int)> requests = [];

  @override
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return _WidgetFavoriteAlbumOperation(result);
  }
}

class _WidgetFavoriteAlbumOperation implements FavoriteAlbumPageLoadOperation {
  const _WidgetFavoriteAlbumOperation(this.result);

  final FavoriteAlbumPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<FavoriteAlbumPageResult> run() async =>
      _withFavoriteAlbumContinuation(result);
}

class _ControlledWidgetFavoriteAlbumGateway implements FavoriteAlbumGateway {
  final Completer<FavoriteAlbumPageResult> _completer = Completer();

  void complete(FavoriteAlbumPageResult result) => _completer.complete(result);

  @override
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _FutureWidgetFavoriteAlbumOperation(_completer.future);
}

class _FutureWidgetFavoriteAlbumOperation
    implements FavoriteAlbumPageLoadOperation {
  const _FutureWidgetFavoriteAlbumOperation(this.result);

  final Future<FavoriteAlbumPageResult> result;

  @override
  bool cancel() => true;

  @override
  Future<FavoriteAlbumPageResult> run() async =>
      _withFavoriteAlbumContinuation(await result);
}

class _ScriptedWidgetFavoriteAlbumGateway implements FavoriteAlbumGateway {
  _ScriptedWidgetFavoriteAlbumGateway(this.results);

  final List<FavoriteAlbumPageResult> results;
  final List<(int, int)> requests = [];
  int _index = 0;

  @override
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return _WidgetFavoriteAlbumOperation(results[_index++]);
  }
}

class _WidgetFavoriteArtistGateway implements FavoriteArtistGateway {
  _WidgetFavoriteArtistGateway(this.result);

  final FavoriteArtistPageResult result;
  final List<(int, int)> requests = [];

  @override
  FavoriteArtistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return _WidgetFavoriteArtistOperation(result);
  }
}

class _WidgetFavoriteArtistOperation
    implements FavoriteArtistPageLoadOperation {
  const _WidgetFavoriteArtistOperation(this.result);

  final FavoriteArtistPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<FavoriteArtistPageResult> run() async =>
      _withFavoriteArtistContinuation(result);
}

class _WidgetRadarGateway implements RadarGateway {
  _WidgetRadarGateway(this.result);

  final RadarTrackPageResult result;
  final List<int> pages = [];

  @override
  RadarTrackPageLoadOperation beginLoad({required int page}) {
    pages.add(page);
    return _WidgetRadarOperation(result);
  }
}

class _WidgetRadarOperation implements RadarTrackPageLoadOperation {
  const _WidgetRadarOperation(this.result);

  final RadarTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<RadarTrackPageResult> run() async => result;
}

class _ScriptedWidgetRadarGateway implements RadarGateway {
  _ScriptedWidgetRadarGateway(this.results);

  final List<RadarTrackPageResult> results;
  final List<int> pages = [];
  var _next = 0;

  @override
  RadarTrackPageLoadOperation beginLoad({required int page}) {
    pages.add(page);
    final index = _next < results.length ? _next++ : results.length - 1;
    return _WidgetRadarOperation(results[index]);
  }
}

class _WidgetLyricGateway implements LyricGateway {
  const _WidgetLyricGateway();

  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) => const _WidgetLyricOperation();
}

class _WidgetLyricOperation implements LyricLoadOperation {
  const _WidgetLyricOperation();

  @override
  bool cancel() => true;

  @override
  Future<LyricLoadResult> run() async =>
      const LyricLoadResult(failure: LyricFailure.unavailable);
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

class _SuccessfulWidgetMediaGateway implements MediaResolutionGateway {
  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => const _SuccessfulWidgetMediaOperation();
}

class _SuccessfulWidgetMediaOperation implements MediaResolutionOperation {
  const _SuccessfulWidgetMediaOperation();

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async => MediaResolutionResult(
    source: ResolvedPlaybackSource(
      uri: Uri.parse('https://audio.example.test/fixture.mp3'),
      format: PlaybackAudioFormat.mp3,
      quality: PlaybackAudioQuality.standard,
      validForSeconds: 300,
    ),
  );
}

class _WidgetAudioEngine implements ForegroundAudioEngine {
  const _WidgetAudioEngine(this.session);

  final ForegroundAudioSession session;

  @override
  Future<void> dispose() async {}

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) async => session;
}

class _WidgetAudioSession implements ForegroundAudioSession {
  final StreamController<ForegroundAudioState> _states =
      StreamController<ForegroundAudioState>.broadcast();
  final StreamController<ForegroundAudioFailure> _failures =
      StreamController<ForegroundAudioFailure>.broadcast();
  final StreamController<int> _positions = StreamController<int>.broadcast();
  int stopCalls = 0;

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> play() async => _states.add(ForegroundAudioState.playing);

  @override
  Future<void> pause() async => _states.add(ForegroundAudioState.paused);

  @override
  Future<void> seekToMs(int positionMs) async => _positions.add(positionMs);

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {
    stopCalls += 1;
    _states.add(ForegroundAudioState.stopped);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _failures.close();
    await _positions.close();
  }
}

class _WidgetPlaybackQueueGateway
    implements PlaybackQueueGateway, PlaybackQueueBatchGateway {
  _WidgetPlaybackQueueGateway({this.mutatesOnAdvance = false});

  final bool mutatesOnAdvance;
  final List<PlaylistTrackSummary> pushed = [];
  final List<List<PlaylistTrackSummary>> extensions = [];
  final List<(List<PlaylistTrackSummary>, int?)> replacements = [];
  PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot.empty();

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) {
    pushed.add(track);
    _snapshot = PlaybackQueueSnapshot(
      tracks: [..._snapshot.tracks, track],
      currentIndex: _snapshot.currentIndex ?? 0,
      hasPrevious: false,
      hasNext: false,
    );
    return PlaybackQueueResult(snapshot: _snapshot);
  }

  @override
  PlaybackQueueResult extend(List<PlaylistTrackSummary> tracks) {
    extensions.add(List.of(tracks));
    final currentIndex = _snapshot.currentIndex;
    _snapshot = PlaybackQueueSnapshot(
      tracks: [..._snapshot.tracks, ...tracks],
      currentIndex: currentIndex,
      hasPrevious: currentIndex != null && currentIndex > 0,
      hasNext:
          currentIndex != null &&
          currentIndex + 1 < _snapshot.tracks.length + tracks.length,
    );
    return PlaybackQueueResult(snapshot: _snapshot);
  }

  @override
  PlaybackQueueResult extendAndAdvanceFromTerminal(
    List<PlaylistTrackSummary> tracks,
  ) {
    extensions.add(List.of(tracks));
    final nextIndex = _snapshot.tracks.length;
    _snapshot = PlaybackQueueSnapshot(
      tracks: [..._snapshot.tracks, ...tracks],
      currentIndex: nextIndex,
      hasPrevious: nextIndex > 0,
      hasNext: tracks.length > 1,
    );
    return PlaybackQueueResult(
      snapshot: _snapshot,
      playbackRequested: tracks.isNotEmpty,
    );
  }

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) {
    replacements.add((List.of(tracks), currentIndex));
    _snapshot = PlaybackQueueSnapshot(
      tracks: tracks,
      currentIndex: currentIndex,
      hasPrevious: currentIndex != null && currentIndex > 0,
      hasNext: currentIndex != null && currentIndex + 1 < tracks.length,
    );
    return PlaybackQueueResult(snapshot: _snapshot);
  }

  @override
  PlaybackQueueResult advance() {
    final currentIndex = _snapshot.currentIndex;
    if (!mutatesOnAdvance ||
        currentIndex == null ||
        currentIndex + 1 >= _snapshot.tracks.length) {
      return PlaybackQueueResult(snapshot: _snapshot);
    }
    final nextIndex = currentIndex + 1;
    _snapshot = PlaybackQueueSnapshot(
      tracks: _snapshot.tracks,
      currentIndex: nextIndex,
      hasPrevious: true,
      hasNext: nextIndex + 1 < _snapshot.tracks.length,
    );
    return PlaybackQueueResult(snapshot: _snapshot, playbackRequested: true);
  }

  @override
  PlaybackQueueResult clear() {
    _snapshot = PlaybackQueueSnapshot.empty();
    return PlaybackQueueResult(snapshot: _snapshot);
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

class _WidgetRankingGateway implements RankingGateway {
  _WidgetRankingGateway(this.groupResult, this.trackResult);

  final RankingGroupResult groupResult;
  final RankingTrackPageResult trackResult;
  final List<(RankingSummary, int, int)> trackRequests = [];
  int groupLoads = 0;

  @override
  RankingGroupLoadOperation beginGroupLoad() {
    groupLoads += 1;
    return _WidgetRankingGroupOperation(groupResult);
  }

  @override
  RankingTrackPageLoadOperation beginTrackLoad({
    required RankingSummary ranking,
    required int offset,
    required int size,
  }) {
    trackRequests.add((ranking, offset, size));
    return _WidgetRankingTrackOperation(trackResult);
  }
}

class _WidgetRankingGroupOperation implements RankingGroupLoadOperation {
  const _WidgetRankingGroupOperation(this.result);
  final RankingGroupResult result;
  @override
  bool cancel() => true;
  @override
  Future<RankingGroupResult> run() async => result;
}

class _WidgetRankingTrackOperation implements RankingTrackPageLoadOperation {
  const _WidgetRankingTrackOperation(this.result);
  final RankingTrackPageResult result;
  @override
  bool cancel() => true;
  @override
  Future<RankingTrackPageResult> run() async =>
      _withRankingContinuation(result);
}

class _DetailRequest {
  const _DetailRequest(this.playlist, this.offset, this.size);
  final UserPlaylistSummary playlist;
  final int offset;
  final int size;
}

class _WidgetDetailGateway implements PlaylistDetailGateway {
  _WidgetDetailGateway(this.results);

  final List<PlaylistTrackPageResult> results;
  final List<_DetailRequest> requests = [];
  int _next = 0;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    requests.add(_DetailRequest(playlist, offset, size));
    return _WidgetDetailOperation(results[_next++]);
  }
}

class _WidgetDetailOperation implements PlaylistTrackPageLoadOperation {
  const _WidgetDetailOperation(this.result);
  final PlaylistTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async =>
      _withPlaylistContinuation(result);
}

class _DeferredWidgetDetailGateway implements PlaylistDetailGateway {
  _DeferredWidgetDetailGateway(this.results);

  final List<Future<PlaylistTrackPageResult>> results;
  final List<_DetailRequest> requests = [];
  int _next = 0;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    requests.add(_DetailRequest(playlist, offset, size));
    return _DeferredWidgetDetailOperation(results[_next++]);
  }
}

class _DeferredWidgetDetailOperation implements PlaylistTrackPageLoadOperation {
  const _DeferredWidgetDetailOperation(this.result);

  final Future<PlaylistTrackPageResult> result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async =>
      _withPlaylistContinuation(await result);
}

class _WidgetStartOperation implements LoginStartOperation {
  const _WidgetStartOperation(this.result);

  final LoginStart result;

  @override
  bool cancel() => true;

  @override
  Future<LoginStart> run() async => result;
}

class _ImmediateWidgetVerification implements CredentialVerificationOperation {
  const _ImmediateWidgetVerification(this.result);

  final CredentialVerificationResult result;

  @override
  bool cancel() => true;

  @override
  Future<CredentialVerificationResult> run() async => result;
}

class _PendingWidgetVerification implements CredentialVerificationOperation {
  final Completer<CredentialVerificationResult> _result =
      Completer<CredentialVerificationResult>();

  @override
  bool cancel() => true;

  @override
  Future<CredentialVerificationResult> run() => _result.future;

  void complete(CredentialVerificationResult result) =>
      _result.complete(result);
}

class _WaitingSession implements LoginSession {
  final List<Completer<LoginUpdate>> _advances = <Completer<LoginUpdate>>[];
  bool _active = true;
  int cancelCalls = 0;

  @override
  bool get isActive => _active;

  @override
  Future<LoginUpdate> advance() {
    final advance = Completer<LoginUpdate>();
    _advances.add(advance);
    return advance.future.then((update) {
      _active = update.sessionActive;
      return update;
    });
  }

  void complete(LoginUpdate update) {
    _advances.firstWhere((advance) => !advance.isCompleted).complete(update);
  }

  @override
  bool cancel() {
    cancelCalls += 1;
    final wasActive = _active;
    _active = false;
    return wasActive;
  }
}

class _SyntheticRecentPlaysGateway implements RecentPlaysGateway {
  final offsets = <int>[];
  static PlaylistTrackSummary trackAt(int position) => PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'synthetic-history:$position',
    title: position == 237
        ? 'Hidden Horizon'
        : position < 7
        ? const [
            'Evening Shore',
            'Mercury',
            'Take my hand',
            'Violet Memory',
            'Night Transit',
            'Green Signal',
            'After the Rain',
          ][position]
        : 'Archive Track $position',
    artistNames: [
      const ['North Harbor', 'Cinder Avenue', 'Signal Coast'][position % 3],
    ],
    albumTitle: const [
      'City after rain',
      'Moving Quietly',
      'After Hours',
    ][position % 3],
    durationSeconds: 180 + position,
  );
  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    offsets.add(offset);
    final count = (250 - offset).clamp(0, size);
    return _WidgetDetailOperation(
      PlaylistTrackPageResult(
        offset: offset,
        nextOffset: offset + count,
        total: 250,
        hasMore: offset + count < 250,
        tracks: List.generate(count, (index) => trackAt(offset + index)),
      ),
    );
  }
}

Future<void> _loadRecentReviewFonts(
  WidgetTester tester, {
  bool? enabled,
}) async {
  const recentCapture = bool.fromEnvironment('RECENT_PLAYS_VISUAL_REVIEW');
  const reviewFont = String.fromEnvironment('HOME_REVIEW_CJK_FONT');
  if (!(enabled ?? recentCapture) || reviewFont.isEmpty) return;
  await tester.runAsync(() async {
    await (FontLoader('Roboto')
          ..addFont(File(reviewFont).readAsBytes().then(ByteData.sublistView)))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
}

class _ScriptedRecentPlaysGateway implements RecentPlaysGateway {
  _ScriptedRecentPlaysGateway(this.results);
  final List<PlaylistTrackPageResult> results;
  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _WidgetDetailOperation(results.removeAt(0));
}
