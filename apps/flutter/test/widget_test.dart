import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show SemanticsAction, Size;

import 'package:flutter/foundation.dart' show ValueKey;
import 'package:flutter/material.dart'
    show
        FilledButton,
        GridView,
        IconButton,
        InkWell,
        ListView,
        Scrollable,
        ScrollableState;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';

void main() {
  testWidgets('renders truthful bootstrap state', (tester) async {
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
      ),
    );

    expect(find.text('QQ Music connected'), findsOneWidget);
    expect(find.text('qq-music'), findsOneWidget);
    expect(find.text('0.1.0-test'), findsOneWidget);
    expect(find.text('Continue with WeChat'), findsOneWidget);

    await tester.ensureVisible(find.text('Continue with WeChat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with WeChat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Scan with WeChat'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with WeChat'), findsOneWidget);
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
    await tester.ensureVisible(find.text('Continue with WeChat'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with WeChat'), findsOneWidget);
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

    expect(find.text('Checking your saved session…'), findsOneWidget);
    expect(find.text('Use a new code'), findsOneWidget);
    expect(find.text('You’re signed in'), findsNothing);

    verification.complete(CredentialVerificationResult.network);
    await tester.pumpAndSettle();
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

    await tester.ensureVisible(find.text('Continue with WeChat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with WeChat'));
    await tester.pump();
    session.complete(
      const LoginUpdate(
        failure: LoginFailure.serviceUnavailable,
        sessionActive: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('QQ Music is unavailable'), findsOneWidget);
    expect(find.text('Get a new code'), findsOneWidget);
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

    await tester.ensureVisible(find.text('Continue with WeChat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with WeChat'));
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

    expect(find.text('Saved session expired'), findsOneWidget);
    expect(find.text('Sign in again'), findsOneWidget);
    expect(find.text('This code expired'), findsNothing);
  });

  testWidgets('routes an authenticated account into its user playlists', (
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your music'), findsOneWidget);
    expect(find.text('Your playlists'), findsOneWidget);
    expect(find.text('Synthetic favorites'), findsOneWidget);
    expect(find.text('Synthetic saved mix'), findsOneWidget);
    expect(find.text('42 tracks'), findsOneWidget);
    final playlistSemantics = tester.getSemantics(
      find.text('Synthetic favorites'),
    );
    expect(playlistSemantics.label, 'Synthetic favorites, 42 tracks');
    expect(
      playlistSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
    expect(find.text('You’re signed in'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('routes fresh QR authentication into the library', (
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

    await tester.ensureVisible(find.text('Continue with WeChat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with WeChat'));
    await tester.pump();
    session.complete(
      const LoginUpdate(
        progress: LoginProgress.authenticated,
        sessionActive: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your music'), findsOneWidget);
    expect(find.text('No playlists yet'), findsOneWidget);
  });

  testWidgets('opens search from the library and restores entry focus', (
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

    await tester.tap(find.byKey(const ValueKey('track-search-back')));
    await tester.pumpAndSettle();
    expect(find.text('No playlists yet'), findsOneWidget);
    expect(tester.widget<IconButton>(searchEntry).focusNode?.hasFocus, isTrue);
  });

  testWidgets('routes verified startup restore into the library', (
    tester,
  ) async {
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

    expect(find.text('Your music'), findsOneWidget);
    expect(find.text('No playlists yet'), findsOneWidget);
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

    expect(find.text('Narrow playlist'), findsOneWidget);
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
            albumTitle: 'Synthetic album',
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
      ),
    );
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Second synthetic track'), findsOneWidget);
    expect(find.text('Showing 2 of 2 tracks'), findsOneWidget);
    expect(find.text('End of playlist'), findsOneWidget);
    expect(detailGateway.requests[1].offset, 1);

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

    final grid = find.byType(GridView);
    final scrollable = find.descendant(
      of: grid,
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

  testWidgets('sign out requires confirmation and returns to QR login', (
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
    expect(find.text('Your music'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
    await tester.pumpAndSettle();
    expect(authentication.signOutCalls, 1);
    expect(find.text('Continue with WeChat'), findsOneWidget);
    expect(find.byKey(const ValueKey('user-library-page')), findsNothing);
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
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    retry.complete(CredentialSignOutResult.signedOut);
    await tester.pumpAndSettle();
    expect(find.text('Continue with WeChat'), findsOneWidget);
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
    expect(find.text('Continue with WeChat'), findsOneWidget);
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

class _WidgetGateway implements QqMusicAuthenticationGateway {
  _WidgetGateway(
    this.session, {
    this.authenticated = false,
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
  final CredentialVerificationOperation _verificationOperation;
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

class _WidgetLibraryGateway implements UserLibraryGateway {
  _WidgetLibraryGateway(this.results);

  final List<UserLibraryResult> results;
  int _next = 0;

  @override
  UserLibraryLoadOperation beginLoad() =>
      _WidgetLibraryOperation(results[_next++]);
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
