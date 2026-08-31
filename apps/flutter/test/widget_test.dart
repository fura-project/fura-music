import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind, SemanticsAction, Size, Tristate;

import 'package:flutter/foundation.dart' show ValueKey;
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart'
    show
        AppBar,
        Brightness,
        FilledButton,
        Focus,
        FocusManager,
        GridView,
        InkWell,
        ListView,
        ListTile,
        NavigationBar,
        NavigationRail,
        OutlinedButton,
        PageStorageKey,
        Scrollable,
        ScrollableState,
        Semantics,
        SizedBox,
        TextField,
        TextInputAction,
        Theme;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/album/album_page.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/home/daily_recommendation_gateway.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_track_gateway.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_page.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';

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
  await tester.tap(find.byKey(const ValueKey('primary-library-destination')));
  await tester.pumpAndSettle();
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
  testWidgets('keeps the main shell visible while sign-in uses a dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const bootstrap = BootstrapStatus(
      coreVersion: '0.1.0-test',
      provider: ProviderStatus(
        id: 'qq-music',
        displayName: 'QQ Music',
        implementedCapabilities: ['Authentication'],
      ),
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
                opaqueId: 'catalog:signed-out-home',
                title: 'Signed-out public recommendation',
                trackCount: 24,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('signed-out-main-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Signed-out public recommendation'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-daily-sign-in')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-personalized-tracks-sign-in')),
      findsOneWidget,
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
          provider: ProviderStatus(
            id: 'qq-music',
            displayName: 'QQ Music',
            implementedCapabilities: ['Authentication'],
          ),
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

  testWidgets('offers QQ QR, WeChat QR, and phone-code authorization', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final phoneSession = _WidgetPhoneSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          phoneStart: PhoneLoginStart(
            session: phoneSession,
            state: PhoneCodeState.sent,
          ),
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
      ),
    );
    await tester.pumpAndSettle();
    await _openSignInDialog(tester);

    expect(find.text('Scan with QQ'), findsOneWidget);
    expect(find.text('Scan with WeChat'), findsOneWidget);
    await tester.tap(find.text('Use phone and SMS code (experimental)'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('phone-number-field')),
      '13000000000',
    );
    await tester.tap(find.byKey(const ValueKey('send-phone-code-button')));
    await tester.pumpAndSettle();
    expect(find.text('Enter the SMS code'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('phone-verification-code-field')),
      '123456',
    );
    await tester.tap(find.byKey(const ValueKey('authorize-phone-button')));
    await tester.pumpAndSettle();
    expect(phoneSession.codes, ['123456']);
    expect(find.byKey(const ValueKey('authentication-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('user-library-page')), findsOneWidget);
  });

  testWidgets('signed-out Library keeps the shell and opens sign-in in place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = _WidgetLibraryGateway([]);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(_WaitingSession()),
        libraryGateway: library,
      ),
    );
    await tester.pumpAndSettle();

    await _openLibrary(tester);
    expect(find.byKey(const ValueKey('signed-out-library')), findsOneWidget);
    expect(find.text('Sign in to see your music'), findsOneWidget);
    expect(library._next, 0);
    expect(
      find.byKey(const ValueKey('authenticated-primary-shell')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('signed-out-library-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('authentication-dialog')), findsOneWidget);
    expect(find.text('Scan with WeChat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applies the dark Material foundation to auth and Library', (
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

    expect(find.text('Your music'), findsOneWidget);
    expect(find.text('Synthetic favorites'), findsWidgets);
    expect(
      Theme.of(tester.element(find.text('Your music'))).brightness,
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

  testWidgets('routes an authenticated account through Home into playlists', (
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
      heroRect.overlaps(tester.getRect(find.text('Synthetic recommendation'))),
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
    await tester.tap(find.byKey(const ValueKey('home-open-library')));
    await tester.pumpAndSettle();

    expect(find.text('Your music'), findsOneWidget);
    expect(find.text('Your playlists'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-playlist-table-header')),
      findsOneWidget,
    );
    expect(find.text('Playlist'), findsOneWidget);
    expect(find.text('Tracks'), findsOneWidget);
    final playlistsHeader = find.byKey(
      const ValueKey('library-playlists-header'),
    );
    expect(playlistsHeader, findsOneWidget);
    expect(
      find.descendant(
        of: playlistsHeader,
        matching: find.byTooltip('Refresh playlists'),
      ),
      findsOneWidget,
    );
    final libraryContent = find.byKey(const ValueKey('user-library-content'));
    final favoriteTitle = find.descendant(
      of: libraryContent,
      matching: find.text('Synthetic favorites'),
    );
    expect(favoriteTitle, findsOneWidget);
    expect(
      find.descendant(
        of: libraryContent,
        matching: find.text('Synthetic saved mix'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: libraryContent, matching: find.text('42 tracks')),
      findsOneWidget,
    );
    final playlistSemantics = tester.getSemantics(favoriteTitle);
    expect(playlistSemantics.label, 'Synthetic favorites, 42 tracks');
    expect(
      playlistSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
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
    expect(
      heroRect.overlaps(tester.getRect(find.text('Public hero pick'))),
      isTrue,
    );
    expect(
      radarRect.overlaps(tester.getRect(find.text('Real Radar slot'))),
      isTrue,
    );
    expect(dailyStateRect.overlaps(heroRect), isFalse);
    expect(dailyStateRect.overlaps(radarRect), isFalse);
    expect(find.text('Public secondary pick'), findsOneWidget);
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

  testWidgets('canonical synthetic Home review fixture is complete', (
    tester,
  ) async {
    const captureReviewImages = bool.fromEnvironment('HOME_VISUAL_REVIEW');
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
        radarGateway: _WidgetRadarGateway(
          RadarTrackPageResult(page: 1, tracks: [tracks.first]),
        ),
        recommendedPlaylistGateway: _WidgetRecommendedPlaylistGateway(
          RecommendedPlaylistPageResult(playlists: publicPlaylists),
        ),
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
      expect(
        find.byKey(const ValueKey('home-hot-programs-unavailable')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('home-related-tracks')), findsOneWidget);
      expect(find.text('Based on “Silver Lines”'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-open-library')), findsOneWidget);
      expect(find.text('MADE FOR YOU'), findsNothing);
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpFixture(const Size(1440, 960));
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

    await pumpFixture(const Size(390, 844));
    expect(
      find.byKey(const ValueKey('now-playing-compact-layout')),
      findsOneWidget,
    );
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
  });

  testWidgets('routes fresh QR authentication through Home to Library', (
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
    expect(find.text('Open library'), findsOneWidget);
    await _openLibrary(tester);
    expect(find.text('Your music'), findsOneWidget);
    expect(find.text('No playlists yet'), findsOneWidget);
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
    expect(find.text('Home personal playlist'), findsOneWidget);

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

    final personalEntry = find.byKey(const ValueKey('home-library-playlist-0'));
    await tester.ensureVisible(personalEntry);
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
    expect(find.text('Search QQ Music'), findsOneWidget);
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
          searchGateway: search,
          recommendedPlaylistGateway: recommendations,
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
        hasLength(4),
      );
      expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-recommendations-section')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-library-shelf')), findsOneWidget);
      expect(find.text('Compact Home playlist'), findsOneWidget);
      expect(find.byKey(const ValueKey('top-search-shortcut')), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(tester.getSize(find.byType(NavigationBar)).height, 64);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('home-recommendation-0')))
            .height,
        256,
      );
      expect(
        find.byKey(const ValueKey('home-compact-actions')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final personalizedTrack = find.byKey(
        const ValueKey('home-personalized-track-1'),
      );
      await tester.ensureVisible(personalizedTrack);
      await tester.pumpAndSettle();
      await tester.tap(personalizedTrack);
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('now-playing-compact-layout')))
            .height,
        64,
      );
      expect(queue.replacements.single.$1, [homeTrack]);
      expect(relatedSeeds.single.opaqueId, homeTrack.opaqueId);
      expect(find.text('Based on “Compact Home song”'), findsOneWidget);
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
      final searchState = tester.state(
        find.byKey(const ValueKey('track-search-page')),
      );

      await tester.tap(
        find.byKey(const ValueKey('primary-library-destination')),
      );
      await tester.pumpAndSettle();
      final retainedSearchPage = find.byKey(
        const ValueKey('track-search-page'),
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
      expect(recommendations.requests, [(0, 20)]);

      tester.view.physicalSize = const Size(1100, 760);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(
        find.byKey(const ValueKey('desktop-music-sidebar')),
        findsOneWidget,
      );
      expect(find.text('Retained discovery result'), findsOneWidget);
      expect(recommendations.requests, [(0, 20)]);
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
              widget.properties.label == 'Loading Recommended Playlists',
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

    expect(find.text('Search QQ Music'), findsOneWidget);
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
      expect(recommendations.requests, [(0, 20)]);
      expect(find.byType(GridView), findsNothing);

      tester.view.physicalSize = const Size(1000, 700);
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('Synthetic discovery'), findsOneWidget);
      expect(recommendations.requests, [(0, 20)]);

      await tester.tap(find.byKey(const ValueKey('recommendations-item-0')));
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
      expect(recommendations.requests, [(0, 20)]);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
      expect(tester.widget<Focus>(discoverEntry).focusNode?.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opens a current ranking and preserves independent Discover state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
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
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:fixtureMid:-',
        title: 'Ranked Track',
        artistNames: ['Ranking artist'],
      );
      final rankings = _WidgetRankingGateway(
        const RankingGroupResult(
          groups: [
            RankingGroup(title: 'Synthetic charts', rankings: [ranking]),
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
      expect(rankings.groupLoads, 1);

      await tester.tap(find.byKey(const ValueKey('ranking-ranking:62001')));
      await tester.pumpAndSettle();
      expect(find.text('Ranked Track'), findsOneWidget);
      expect(rankings.trackRequests, [(ranking, 0, 30)]);

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
      expect(find.text('Radar artist · Radar Album · 3:05'), findsOneWidget);
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

      await tester.tap(find.byKey(const ValueKey('radar-queue-0')));
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

  testWidgets(
    'saved collections share labeled compact loading and empty states',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
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
                widget.properties.label == 'Loading Favorite Albums',
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
      expect(find.text('No favorite albums yet'), findsOneWidget);

      await _selectLibrarySection(tester, 'artists');

      expect(
        find.byKey(const ValueKey('favorite-artists-empty')),
        findsOneWidget,
      );
      expect(find.byType(MusicContentStatePanel), findsOneWidget);
      expect(find.text('No favorite artists yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved collection failures keep one live region and exact recovery',
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

      await _selectLibrarySection(tester, 'artists');

      final artistError = find.byKey(
        const ValueKey('favorite-artists-credential-rejected'),
      );
      expect(artistError, findsOneWidget);
      expect(find.byType(MusicContentStatePanel), findsOneWidget);
      expect(
        find.descendant(
          of: artistError,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Sign in again'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Sign in again'));
      await tester.pumpAndSettle();
      expect(find.text('Scan with WeChat'), findsOneWidget);
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
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();

      await _openLibrary(tester);
      final sectionSelector = find.byKey(
        const ValueKey('library-section-selector'),
      );
      expect(favorites.requests, isEmpty);
      expect(find.text('Your music'), findsOneWidget);
      expect(sectionSelector, findsOneWidget);
      expect(find.text('Library: Playlists'), findsOneWidget);
      expect(
        tester
            .getSemantics(sectionSelector)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await _selectLibrarySection(tester, 'albums');
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('favorite-albums-content')),
        findsOneWidget,
      );
      final albumsHeader = find.byKey(const ValueKey('library-albums-header'));
      expect(albumsHeader, findsOneWidget);
      expect(find.text('Saved Album'), findsOneWidget);
      expect(favorites.requests, [(0, 20)]);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.descendant(
          of: albumsHeader,
          matching: find.byKey(const ValueKey('favorite-albums-refresh')),
        ),
        findsOneWidget,
      );

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
      expect(find.text('No playlists yet'), findsOneWidget);
      expect(find.text('Your music'), findsOneWidget);
      expect(find.text('Library: Playlists'), findsOneWidget);
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      expect(focusedContext, isNotNull);
      expect(
        find
            .ancestor(
              of: find.byElementPredicate(
                (element) => identical(element, focusedContext),
              ),
              matching: find.byKey(const ValueKey('library-section-selector')),
            )
            .evaluate(),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retains favorite Artists across compact and desktop Library sections',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const artist = ArtistSummary(
        providerId: 'qq-music',
        opaqueId: 'artist:-:fixtureFavoriteArtistMid',
        name: 'Saved Artist',
      );
      const album = AlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43001:fixtureArtistAlbumMid',
        title: 'Saved Artist Album',
      );
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:fixtureArtistTrackMid:-',
        title: 'Saved Artist Track',
        artistNames: ['Saved Artist'],
      );
      final favorites = _WidgetFavoriteArtistGateway(
        const FavoriteArtistPageResult(total: 1, artists: [artist]),
      );
      final artistTracks = _WidgetArtistGateway(
        const ArtistTrackPageResult(total: 1, tracks: [track]),
      );
      final artistAlbums = _WidgetArtistAlbumGateway(
        const ArtistAlbumPageResult(total: 1, albums: [album]),
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
          favoriteArtistGateway: favorites,
          artistTrackGateway: artistTracks,
          artistAlbumGateway: artistAlbums,
          albumTrackGateway: albumTracks,
          albumDetailsGateway: const _WidgetAlbumDetailsGateway(),
          playbackQueueGateway: _WidgetPlaybackQueueGateway(),
          lyricGateway: const _WidgetLyricGateway(),
        ),
      );
      await tester.pumpAndSettle();

      await _openLibrary(tester);
      expect(favorites.requests, isEmpty);
      expect(find.text('Your music'), findsOneWidget);
      final sectionSelector = find.byKey(
        const ValueKey('library-section-selector'),
      );
      expect(sectionSelector, findsOneWidget);
      expect(find.text('Library: Playlists'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getSemantics(sectionSelector)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await _selectLibrarySection(tester, 'artists');
      expect(
        find.byKey(const ValueKey('favorite-artists-content')),
        findsOneWidget,
      );
      final artistsHeader = find.byKey(
        const ValueKey('library-artists-header'),
      );
      expect(artistsHeader, findsOneWidget);
      expect(
        find.descendant(
          of: artistsHeader,
          matching: find.byKey(const ValueKey('favorite-artists-refresh')),
        ),
        findsOneWidget,
      );
      expect(find.byType(GridView), findsNothing);
      expect(favorites.requests, [(0, 20)]);

      final artistAction = find.byKey(const ValueKey('favorite-artist-0'));
      final artistSemantics = find.ancestor(
        of: artistAction,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Saved Artist, Artist',
        ),
      );
      expect(
        tester.widget<Semantics>(artistSemantics).properties.onTap,
        isNotNull,
      );
      await tester.tap(artistAction);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('artist-content')), findsOneWidget);
      expect(artistTracks.requests, [(artist, 0, 30)]);

      await tester.tap(find.byTooltip('Back to favorite artists'));
      await tester.pumpAndSettle();
      expect(find.text('Saved Artist'), findsOneWidget);
      expect(favorites.requests, [(0, 20)]);

      await _selectLibrarySection(tester, 'playlists');
      expect(find.text('No playlists yet'), findsOneWidget);
      await _selectLibrarySection(tester, 'artists');
      expect(find.text('Saved Artist'), findsOneWidget);
      expect(favorites.requests, [(0, 20)]);

      tester.view.physicalSize = const Size(1000, 700);
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      expect(tester.widget<InkWell>(artistAction).onTap, isNotNull);
      await tester.tap(artistAction);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('artist-content')), findsOneWidget);
      expect(artistTracks.requests, [(artist, 0, 30), (artist, 0, 30)]);

      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('artist-albums-content')),
        findsOneWidget,
      );
      expect(artistAlbums.requests, [(artist, 0, 30)]);
      await tester.tap(find.byKey(const ValueKey('artist-album-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('album-content')), findsOneWidget);
      expect(albumTracks.requests.single.$1, album);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('artist-albums-content')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back to favorite artists'));
      await tester.pumpAndSettle();
      await _selectLibrarySection(tester, 'playlists');
      expect(find.text('No playlists yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('library-section-artists')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loads new albums lazily and preserves them through Album playback return',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
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
      const track = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:fixtureTrackMid:-',
        title: 'Fresh Track',
        artistNames: ['Fresh Artist'],
      );
      final newAlbums = _WidgetNewAlbumGateway(
        const NewAlbumPageResult(
          region: NewAlbumRegion.mainlandChina,
          total: 1,
          releases: [release],
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

      await tester.tap(find.byKey(const ValueKey('new-album-0')));
      await tester.pumpAndSettle();
      expect(find.text('Fresh Track'), findsOneWidget);
      expect(albumTracks.requests.single.$1, album);
      expect(
        tester.widget<AlbumPage>(find.byType(AlbumPage)).onOpenArtist,
        isNotNull,
      );

      await tester.tap(find.text('Fresh Track'));
      await tester.pump();
      expect(queue.replacements, hasLength(1));
      expect(queue.replacements.single.$1, [track]);
      expect(queue.replacements.single.$2, 0);

      await tester.tap(find.byTooltip('Back to new albums'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-albums-content')), findsOneWidget);
      expect(find.text('Fresh Album'), findsOneWidget);
      expect(newAlbums.requests, [(NewAlbumRegion.mainlandChina, 0, 20)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loads typed new songs lazily and uses the existing queue on narrow screens',
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

      await tester.tap(find.byKey(const ValueKey('open-recommendations')));
      await tester.pumpAndSettle();
      expect(newSongs.requests, isEmpty);

      await _selectAdaptiveSection(
        tester,
        control: 'discover-type-selector',
        item: 'discover-type-new-songs',
      );
      expect(find.byKey(const ValueKey('new-songs-content')), findsOneWidget);
      expect(find.text('Latest Track'), findsOneWidget);
      expect(find.text('Latest Artist · Latest Album · 3:21'), findsOneWidget);
      expect(newSongs.requests, [NewSongCategory.latest]);

      await tester.tap(find.byKey(const ValueKey('new-song-queue-0')));
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

      await tester.tap(
        find.byKey(const ValueKey('now-playing-catalog-action')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('now-playing-catalog-selection')),
        findsOneWidget,
      );
      expect(find.text('Current Album'), findsOneWidget);
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

      final action = find.byKey(const ValueKey('now-playing-catalog-action'));
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

      await tester.tap(
        find.byKey(const ValueKey('now-playing-catalog-action')),
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
        find.byKey(const ValueKey('track-search-content')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('album-content')), findsNothing);
      expect(find.byKey(const ValueKey('artist-content')), findsNothing);
      expect(find.text('Replacement Track'), findsWidgets);
      expect(
        find.byKey(const ValueKey('now-playing-catalog-action')),
        findsNothing,
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
      expect(find.byTooltip('Volume'), findsOneWidget);
      expect(find.byTooltip('Show queue'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('now-playing-open-expanded')),
        findsNothing,
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('now-playing-primary-action')),
        ),
        const Size(56, 56),
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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();
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

    await tester.tap(find.byKey(const ValueKey('artist-back')));
    await tester.pumpAndSettle();
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
    expect(albumTracks.requests, [(album, 0, 30)]);
    expect(
      tester.widget<AlbumPage>(find.byType(AlbumPage)).onOpenArtist,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('album-open-artist')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-content')), findsOneWidget);
    expect(artistTracks.requests, [(artist, 0, 30)]);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-albums-content')), findsOneWidget);
    expect(artistAlbums.requests, [(artist, 0, 30)]);
    await tester.tap(find.byKey(const ValueKey('artist-album-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('album-content')), findsOneWidget);
    expect(albumTracks.requests, [(album, 0, 30), (nestedAlbum, 0, 30)]);

    await tester.tap(find.byTooltip('Back to Artist'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-albums-content')), findsOneWidget);
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.byKey(const ValueKey('album-content')), findsOneWidget);
    expect(find.text('Direct Album'), findsOneWidget);
    expect(albumTracks.requests, [(album, 0, 30), (nestedAlbum, 0, 30)]);

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
    await tester.tap(find.byKey(const ValueKey('track-search-artist-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-search-artist-0-0')));
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

    await tester.tap(find.byTooltip('Back to Artist'));
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

    await _openLibrary(tester);
    expect(find.text('Narrow playlist'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-playlist-table-header')),
      findsNothing,
    );
    final playlistSemantics = tester.getSemantics(find.text('Narrow playlist'));
    expect(playlistSemantics.label, 'Narrow playlist');
    expect(
      playlistSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
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
    await _openLibrary(tester);
    await tester.tap(find.text('Open me').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Synthetic track'), findsOneWidget);
    expect(find.textContaining('Artist one'), findsOneWidget);
    expect(find.text('4:05'), findsOneWidget);
    expect(find.text('Showing 1 of 2 tracks'), findsOneWidget);
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
    expect(find.text('Choose an Artist'), findsOneWidget);
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
    expect(find.byTooltip('Back to Artist'), findsOneWidget);
    expect(albumGateway.requests, hasLength(2));
    await tester.tap(find.byTooltip('Back to Artist'));
    await tester.pumpAndSettle();
    expect(find.text('Artist context album'), findsOneWidget);
    final artistHandled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(artistHandled, isTrue);
    expect(find.textContaining('Synthetic track'), findsOneWidget);
    expect(detailGateway.requests, hasLength(1));

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Second synthetic track'), findsOneWidget);
    expect(find.text('Showing 2 of 2 tracks'), findsOneWidget);
    expect(find.text('End of playlist'), findsOneWidget);
    expect(detailGateway.requests[1].offset, 1);

    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    final firstRow = find.byKey(const ValueKey('playlist-track-row-1'));
    tester.widget<InkWell>(firstRow).focusNode?.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('Open album'), findsOneWidget);
    expect(find.text('Open artist'), findsOneWidget);
    await tester.tap(find.text('Open artist'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an Artist'), findsOneWidget);
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
    expect(find.text('Your playlists'), findsOneWidget);
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
    await _openLibrary(tester);
    await tester.tap(find.text('System back playlist').last);
    await tester.pumpAndSettle();
    expect(find.text('System back track'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.text('Your playlists'), findsOneWidget);
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
    expect(find.text('Your playlists'), findsOneWidget);
    expect(tester.widget<InkWell>(playlistAction).focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('System back track'), findsOneWidget);
    await tester.sendKeyEvent(
      LogicalKeyboardKey.browserBack,
      platform: 'windows',
    );
    await tester.pumpAndSettle();
    expect(find.text('Your playlists'), findsOneWidget);
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

    await _openLibrary(tester);
    final list = find.byKey(
      const PageStorageKey<String>('user-playlist-list-desktop'),
    );
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Playlist 24'),
      500,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    await tester.tap(find.text('Playlist 24'));
    await tester.pumpAndSettle();
    expect(find.text('This playlist is empty'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to playlists'));
    await tester.pumpAndSettle();

    final after = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(after, moreOrLessEquals(before, epsilon: 1));
    final playlistAction = find.ancestor(
      of: find.text('Playlist 24'),
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

    await _openLibrary(tester);
    final list = find.byType(ListView);
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Narrow playlist 24'),
      400,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    await tester.tap(find.text('Narrow playlist 24'));
    await tester.pumpAndSettle();
    expect(find.text('This playlist is empty'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to playlists'));
    await tester.pumpAndSettle();

    final after = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(after, moreOrLessEquals(before, epsilon: 1));
    expect(find.text('Narrow playlist 24'), findsOneWidget);
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
    await _openLibrary(tester);
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
    expect(find.textContaining('previous tracks'), findsOneWidget);
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
    expect(find.text('No playlists yet'), findsOneWidget);
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
    await _openLibrary(tester);
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

  testWidgets('failed refresh keeps the complete library visible and retries', (
    tester,
  ) async {
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
          const UserLibraryResult(failure: UserLibraryFailure.network),
          const UserLibraryResult(
            playlists: [
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'favorite:fresh',
                title: 'Fresh library',
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await _openLibrary(tester);
    await tester.tap(find.byTooltip('Refresh playlists'));
    await tester.pumpAndSettle();

    expect(find.text('Current library'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-library-refresh-failure')),
      findsOneWidget,
    );
    expect(find.textContaining('previous results'), findsOneWidget);
    expect(find.text('Couldn’t reach QQ Music'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('library-refresh-retry')));
    await tester.pumpAndSettle();

    expect(find.text('Fresh library'), findsOneWidget);
    expect(find.text('Current library'), findsNothing);
    expect(
      find.byKey(const ValueKey('user-library-refresh-failure')),
      findsNothing,
    );
  });

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

  testWidgets('canonical synthetic Liked Songs review fixture is complete', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const captureReviewImages = bool.fromEnvironment(
      'LIKED_SONGS_VISUAL_REVIEW',
    );
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

    late _WidgetPlaybackQueueGateway reviewQueue;
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
        playlistDetailGateway: _WidgetDetailGateway([
          const PlaylistTrackPageResult(
            total: 1029,
            hasMore: true,
            tracks: tracks,
          ),
        ]),
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
        await _selectLibrarySection(tester, 'liked-songs');
      }
      expect(find.byKey(const ValueKey('liked-songs-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('liked-songs-title')), findsOneWidget);
      expect(find.text('播放全部'), findsOneWidget);
      expect(find.text('Mercury'), findsWidgets);
      expect(find.text('下载'), findsNothing);
      expect(find.text('批量操作'), findsNothing);
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpLikedSongs(const Size(1440, 960));
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
    await tester.tap(find.byKey(const ValueKey('liked-tab-playlists')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('liked-playlists-search')),
      findsOneWidget,
    );
    expect(find.text('自创歌单 1'), findsOneWidget);
    expect(find.text('收藏歌单 1'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('liked-tab-songs')));
    await tester.pumpAndSettle();
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
    expect(find.text('添加到队列'), findsOneWidget);
    await tester.tap(find.text('添加到队列'));
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
    await tester.tap(find.byKey(const ValueKey('liked-tab-songs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    expect(find.text('从这里播放'), findsOneWidget);
    expect(find.text('添加到队列'), findsOneWidget);
    await tester.tap(find.text('添加到队列'));
    await tester.pumpAndSettle();
    expect(reviewQueue.pushed, hasLength(1));
    semantics.dispose();
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
}

const _bootstrap = BootstrapStatus(
  coreVersion: '0.1.0-test',
  provider: ProviderStatus(
    id: 'qq-music',
    displayName: 'QQ Music',
    implementedCapabilities: ['Authentication'],
  ),
);

class _WidgetGateway
    implements
        QqMusicAuthenticationGateway,
        MultiMethodQqMusicAuthenticationGateway {
  _WidgetGateway(
    this.session, {
    this.authenticated = false,
    CredentialVerificationOperation? verificationOperation,
    List<FutureOr<CredentialSignOutResult>> signOutResults = const [
      CredentialSignOutResult.signedOut,
    ],
    this.phoneStart = const PhoneLoginStart(
      failure: LoginFailure.coreUnavailable,
    ),
  }) : _verificationOperation =
           verificationOperation ??
           const _ImmediateWidgetVerification(
             CredentialVerificationResult.noRestoredCredential,
           ),
       _signOutResults = List.of(signOutResults);

  final _WaitingSession session;
  bool authenticated;
  final CredentialVerificationOperation _verificationOperation;
  final PhoneLoginStart phoneStart;
  final List<FutureOr<CredentialSignOutResult>> _signOutResults;
  int signOutCalls = 0;

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
  PhoneLoginStartOperation beginPhoneStart({
    required String countryCode,
    required String phoneNumber,
  }) => _WidgetPhoneStartOperation(phoneStart);

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

class _WidgetPhoneStartOperation implements PhoneLoginStartOperation {
  const _WidgetPhoneStartOperation(this.result);

  final PhoneLoginStart result;

  @override
  bool cancel() => true;

  @override
  Future<PhoneLoginStart> run() async => result;
}

class _WidgetPhoneSession implements PhoneLoginSession {
  bool active = true;
  final List<String> codes = [];

  @override
  bool get isActive => active;

  @override
  Future<LoginFailure?> authorize(String verificationCode) async {
    codes.add(verificationCode);
    active = false;
    return null;
  }

  @override
  bool cancel() {
    final wasActive = active;
    active = false;
    return wasActive;
  }
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
  Future<AlbumTrackPageResult> run() async => result;
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
  Future<ArtistTrackPageResult> run() async => result;
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
  Future<ArtistAlbumPageResult> run() async => result;
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
  Future<RecommendedPlaylistPageResult> run() async => result;
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
  Future<RecommendedPlaylistPageResult> run() => result;
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
  Future<NewAlbumPageResult> run() async => result;
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
  Future<FavoriteAlbumPageResult> run() async => result;
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
  Future<FavoriteAlbumPageResult> run() => result;
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
  Future<FavoriteArtistPageResult> run() async => result;
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
  var _next = 0;

  @override
  RadarTrackPageLoadOperation beginLoad({required int page}) {
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

class _WidgetPlaybackQueueGateway implements PlaybackQueueGateway {
  _WidgetPlaybackQueueGateway({this.mutatesOnAdvance = false});

  final bool mutatesOnAdvance;
  final List<PlaylistTrackSummary> pushed = [];
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
  Future<RankingTrackPageResult> run() async => result;
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
  Future<PlaylistTrackPageResult> run() async => result;
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
