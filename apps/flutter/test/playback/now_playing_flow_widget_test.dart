import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';

void main() {
  testWidgets('plays a row and exposes pause, resume, and stop controls', (
    tester,
  ) async {
    final media = _FakeMediaGateway([
      _ImmediateMediaOperation(_success('first')),
    ]);
    final audio = _FakeAudioEngine([_FakeAudioSession()]);
    final queue = _WidgetQueueGateway();
    await _openDetail(tester, media: media, audio: audio, queue: queue);
    expect(
      find.byKey(const ValueKey('now-playing-open-expanded')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('now-playing-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('now-playing-artwork')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('now-playing-artwork-placeholder')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Artwork for First track'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('now-playing-catalog-action')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('now-playing-open-expanded')),
      findsOneWidget,
    );
    expect(find.textContaining('Playing'), findsOneWidget);
    expect(media.requests, [('qq-music', 'first')]);
    expect(queue.replacedTracks, hasLength(2));
    expect(queue.replacedIndex, 0);
    expect(audio.requestedUris.single.queryParameters['vkey'], 'first');

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Paused'), findsOneWidget);

    await tester.tap(find.byTooltip('Resume'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Playing'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stopped'), findsOneWidget);
  });

  testWidgets(
    'desktop persistent player groups identity transport and utilities',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _openDetail(
        tester,
        media: _FakeMediaGateway([
          _ImmediateMediaOperation(_success('desktop-zones')),
        ]),
        audio: _FakeAudioEngine([_FakeAudioSession()]),
      );
      await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
      await tester.pumpAndSettle();

      final identity = find.byKey(const ValueKey('now-playing-track-zone'));
      final transport = find.byKey(
        const ValueKey('now-playing-transport-zone'),
      );
      final utilities = find.byKey(const ValueKey('now-playing-utility-zone'));
      expect(
        find.byKey(const ValueKey('now-playing-desktop-layout')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: identity,
          matching: find.byKey(const ValueKey('now-playing-title')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: transport,
          matching: find.byKey(const ValueKey('now-playing-primary-action')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: transport,
          matching: find.byKey(const ValueKey('now-playing-progress')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: utilities,
          matching: find.byKey(const ValueKey('now-playing-volume')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: utilities,
          matching: find.byKey(const ValueKey('now-playing-show-queue')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final desktopBar = tester.getRect(
        find.byKey(const ValueKey('now-playing-desktop-bar')),
      );
      final desktopLayout = tester.getRect(
        find.byKey(const ValueKey('now-playing-desktop-layout')),
      );
      final primaryAction = tester.getRect(
        find.byKey(const ValueKey('now-playing-primary-action')),
      );
      final progressRow = tester.getRect(
        find.byKey(const ValueKey('now-playing-desktop-progress-row')),
      );
      expect(desktopBar.height, 88);
      expect(desktopLayout.height, 72);
      expect(desktopLayout.top - desktopBar.top, closeTo(8, 1));
      expect(desktopBar.bottom - desktopLayout.bottom, closeTo(8, 1));
      expect(primaryAction.top - desktopLayout.top, closeTo(0, 1));
      expect(primaryAction.bottom, lessThanOrEqualTo(progressRow.top));
      expect(progressRow.bottom, desktopLayout.bottom);
      if (const bool.fromEnvironment('NOW_PLAYING_BAR_VISUAL_REVIEW')) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-now-playing-bar-desktop.png'),
          ),
        );
      }

      tester.view.physicalSize = const Size(800, 700);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('now-playing-desktop-layout')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('now-playing-title')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('now-playing-primary-action')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop artwork catalog chooser lays out with Semantics enabled',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const album = AlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43001:dialogAlbumMid',
        title: 'Dialog Album',
      );
      const artist = ArtistSummary(
        providerId: 'qq-music',
        opaqueId: 'artist:42001:dialogArtistMid',
        name: 'Dialog Artist',
      );

      await _openDetail(
        tester,
        media: _FakeMediaGateway([
          _ImmediateMediaOperation(_success('desktop-dialog')),
        ]),
        audio: _FakeAudioEngine([_FakeAudioSession()]),
        albumTitle: album.title,
        album: album,
        artists: const [artist],
      );
      await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('now-playing-catalog-action')),
      );
      await tester.pumpAndSettle();

      final selection = find.byKey(
        const ValueKey('now-playing-catalog-selection'),
      );
      expect(selection, findsOneWidget);
      expect(
        find.descendant(of: selection, matching: find.text('Dialog Album')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: selection, matching: find.text('Dialog Artist')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('now-playing-catalog-selection')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('now-playing status announces meaningful state changes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _openDetail(
      tester,
      media: _FakeMediaGateway([_ImmediateMediaOperation(_success('status'))]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    var status = tester.getSemantics(
      find.byKey(const ValueKey('now-playing-status')),
    );
    expect(status.label, 'Fixture artist · Playing');
    expect(status.getSemanticsData().flagsCollection.isLiveRegion, isTrue);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    status = tester.getSemantics(
      find.byKey(const ValueKey('now-playing-status')),
    );
    expect(status.label, 'Fixture artist · Paused');
    expect(status.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    semantics.dispose();
  });

  testWidgets('loads lyrics for the exact selected provider identity', (
    tester,
  ) async {
    final lyrics = _FakeLyricGateway(
      const LyricLoadResult(failure: LyricFailure.unavailable),
    );
    await _openDetail(
      tester,
      media: _FakeMediaGateway([_ImmediateMediaOperation(_success('first'))]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
      lyrics: lyrics,
    );

    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    expect(lyrics.requests, [('qq-music', 'first')]);
    expect(find.textContaining('Playing'), findsOneWidget);
    expect(find.text('Scan with WeChat'), findsNothing);
  });

  testWidgets('retries media resolution for the same queue position', (
    tester,
  ) async {
    final queue = _WidgetQueueGateway();
    final media = _FakeMediaGateway([
      const _ImmediateMediaOperation(
        MediaResolutionResult(failure: MediaResolutionFailure.network),
      ),
      _ImmediateMediaOperation(_success('retry-success')),
    ]);
    await _openDetail(
      tester,
      media: media,
      audio: _FakeAudioEngine([_FakeAudioSession()]),
      queue: queue,
    );

    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Couldn’t reach QQ Music'), findsOneWidget);
    expect(find.byTooltip('Try again'), findsOneWidget);
    expect(queue._snapshot.currentIndex, 0);

    await tester.tap(find.byTooltip('Try again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Playing'), findsOneWidget);
    expect(queue._snapshot.currentIndex, 0);
    expect(media.requests, [('qq-music', 'first'), ('qq-music', 'first')]);
  });

  testWidgets('shows exact progress and seeks once when a drag commits', (
    tester,
  ) async {
    final session = _FakeAudioSession();
    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('seekable')),
      ]),
      audio: _FakeAudioEngine([session]),
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    session.emitPosition(15000);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('now-playing-position')))
          .data,
      '0:15',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('now-playing-duration')))
          .data,
      '2:00',
    );

    final progress = find.byKey(const ValueKey('now-playing-progress'));
    await tester.tapAt(tester.getCenter(progress));
    await tester.pumpAndSettle();

    expect(session.seekPositions, hasLength(1));
    expect(session.seekPositions.single, closeTo(60000, 5000));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('now-playing-position')))
          .data,
      '1:00',
    );
  });

  testWidgets('does not invent progress when track duration is unknown', (
    tester,
  ) async {
    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('unknown-duration')),
      ]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
      durationSeconds: null,
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('now-playing-progress')), findsNothing);
  });

  testWidgets('artwork load failure keeps a local now-playing placeholder', (
    tester,
  ) async {
    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('artwork-fallback')),
      ]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
      artworkUri: 'https://images.example.test/missing.jpg',
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('now-playing-artwork')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('now-playing-artwork-placeholder')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Show queue'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('queue-artwork-placeholder')),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('volume commits once and applies to replacement sessions', (
    tester,
  ) async {
    final firstSession = _FakeAudioSession();
    final secondSession = _FakeAudioSession();
    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('first-volume')),
        _ImmediateMediaOperation(_success('second-volume')),
      ]),
      audio: _FakeAudioEngine([firstSession, secondSession]),
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    expect(firstSession.volumes, [1]);

    await tester.tap(find.byTooltip('Volume'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    final slider = find.byKey(const ValueKey('volume-slider'));
    await tester.tapAt(tester.getCenter(slider));
    await tester.pumpAndSettle();

    expect(firstSession.volumes, hasLength(2));
    expect(firstSession.volumes.last, closeTo(0.5, 0.05));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('volume-percent'))).data,
      '50%',
    );

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(secondSession.volumes, hasLength(1));
    expect(secondSession.volumes.single, closeTo(0.5, 0.05));
  });

  for (final failure in [
    LyricFailure.credentialRejected,
    LyricFailure.credentialRejectedStorageCleanupFailed,
  ]) {
    testWidgets('returns ${failure.name} lyrics to the existing sign-in flow', (
      tester,
    ) async {
      await _openDetail(
        tester,
        media: _FakeMediaGateway([
          _ImmediateMediaOperation(_success('must-not-start')),
        ]),
        audio: _FakeAudioEngine(const []),
        lyrics: _FakeLyricGateway(LyricLoadResult(failure: failure)),
      );

      await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
      await tester.pumpAndSettle();

      expect(find.text('Scan with WeChat'), findsOneWidget);
      expect(find.byKey(const ValueKey('user-library-page')), findsNothing);
    });
  }

  testWidgets('keeps the authenticated shell on a lyric network failure', (
    tester,
  ) async {
    await _openDetail(
      tester,
      media: _FakeMediaGateway([_ImmediateMediaOperation(_success('first'))]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
      lyrics: _FakeLyricGateway(
        const LyricLoadResult(failure: LyricFailure.network),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('user-library-page')), findsOneWidget);
    expect(find.textContaining('Playing'), findsOneWidget);
    expect(find.text('Scan with WeChat'), findsNothing);
  });

  testWidgets('switches tracks and keeps the coordinator across local back', (
    tester,
  ) async {
    final firstResult = Completer<MediaResolutionResult>();
    final first = _PendingMediaOperation(firstResult.future);
    final media = _FakeMediaGateway([
      first,
      _ImmediateMediaOperation(_success('second')),
    ]);
    final audio = _FakeAudioEngine([_FakeAudioSession(), _FakeAudioSession()]);
    await _openDetail(tester, media: media, audio: audio);

    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await first.started.future;
    await tester.pump();
    expect(find.textContaining('Finding a playable source'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('now-playing-artwork-state')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Back to playlists'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Your playlists'), findsOneWidget);
    expect(find.textContaining('Finding a playable source'), findsOneWidget);

    firstResult.complete(_success('first'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Playing'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('now-playing-artwork-state')),
      findsNothing,
    );

    final playlist = find.text('Fixture playlist').last;
    await tester.ensureVisible(playlist);
    await tester.pumpAndSettle();
    await tester.tap(playlist);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-2')));
    await tester.pumpAndSettle();

    expect(find.text('Second track'), findsNWidgets(2));
    expect(media.requests.last, ('qq-music', 'second'));
    expect(audio.requestedUris.last.queryParameters['vkey'], 'second');
  });

  testWidgets(
    'returns a rejected playback session to sign-in without URI copy',
    (tester) async {
      final privateUri =
          'https://audio.example.test/private.mp3?vkey=must-not-appear';
      final media = _FakeMediaGateway([
        const _ImmediateMediaOperation(
          MediaResolutionResult(
            failure: MediaResolutionFailure.credentialRejected,
          ),
        ),
      ]);
      await _openDetail(
        tester,
        media: media,
        audio: _FakeAudioEngine(const []),
        firstOpaqueId: privateUri,
      );

      await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Your QQ Music session was rejected and removed.'),
        findsOneWidget,
      );
      expect(find.textContaining('must-not-appear'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();
      expect(media.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('now-playing-sign-in-again')));
      await tester.pumpAndSettle();
      expect(find.text('Scan with WeChat'), findsOneWidget);
    },
  );

  testWidgets('navigates previous and next then advances on completion', (
    tester,
  ) async {
    final firstSession = _FakeAudioSession();
    final secondSession = _FakeAudioSession();
    final returnedSession = _FakeAudioSession();
    final completedSession = _FakeAudioSession();
    final media = _FakeMediaGateway([
      _ImmediateMediaOperation(_success('first')),
      _ImmediateMediaOperation(_success('second')),
      _ImmediateMediaOperation(_success('returned')),
      _ImmediateMediaOperation(_success('completed-next')),
    ]);
    await _openDetail(
      tester,
      media: media,
      audio: _FakeAudioEngine([
        firstSession,
        secondSession,
        returnedSession,
        completedSession,
      ]),
    );

    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    expect(_nowPlayingTitle(tester), 'First track');

    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(_nowPlayingTitle(tester), 'Second track');

    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();
    expect(_nowPlayingTitle(tester), 'First track');

    returnedSession.emitState(ForegroundAudioState.completed);
    await tester.pumpAndSettle();
    expect(_nowPlayingTitle(tester), 'Second track');
    expect(media.requests, [
      ('qq-music', 'first'),
      ('qq-music', 'second'),
      ('qq-music', 'first'),
      ('qq-music', 'second'),
    ]);
  });

  testWidgets('desktop shortcuts control playback and positional navigation', (
    tester,
  ) async {
    final media = _FakeMediaGateway([
      _ImmediateMediaOperation(_success('first')),
      _ImmediateMediaOperation(_success('second')),
      _ImmediateMediaOperation(_success('returned')),
    ]);
    await _openDetail(
      tester,
      media: media,
      audio: _FakeAudioEngine([
        _FakeAudioSession(),
        _FakeAudioSession(),
        _FakeAudioSession(),
      ]),
    );

    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back to playlists'));
    await tester.pumpAndSettle();
    expect(find.text('Your playlists'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paused'), findsOneWidget);

    await _sendControlShortcut(tester, LogicalKeyboardKey.space);
    expect(find.textContaining('Playing'), findsOneWidget);

    await _sendControlShortcut(tester, LogicalKeyboardKey.arrowRight);
    expect(_nowPlayingTitle(tester), 'Second track');

    final playlist = find.text('Fixture playlist').last;
    await tester.ensureVisible(playlist);
    await tester.pumpAndSettle();
    await tester.tap(playlist);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackPrevious);
    await tester.pumpAndSettle();
    expect(_nowPlayingTitle(tester), 'First track');

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaStop);
    await tester.pumpAndSettle();
    expect(find.textContaining('Stopped'), findsOneWidget);
    expect(media.requests, [
      ('qq-music', 'first'),
      ('qq-music', 'second'),
      ('qq-music', 'first'),
    ]);
  });

  testWidgets('sign out stops playback before credential cleanup completes', (
    tester,
  ) async {
    final signOut = Completer<CredentialSignOutResult>();
    final session = _FakeAudioSession();
    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('sign-out-stop')),
      ]),
      audio: _FakeAudioEngine([session]),
      authenticationGateway: _AuthenticatedGateway(
        onSignOut: () => signOut.future,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to playlists'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
    await tester.pump();

    expect(session.stopCalls, 1);
    expect(find.textContaining('Stopped'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('sign-out')))
          .onPressed,
      isNull,
    );

    signOut.complete(CredentialSignOutResult.signedOut);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('signed-out-main-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-heading')), findsOneWidget);
    expect(find.text('Scan with WeChat'), findsNothing);
  });

  testWidgets('track action semantics do not repeat visible metadata', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _openDetail(
      tester,
      media: _FakeMediaGateway(const []),
      audio: _FakeAudioEngine(const []),
    );

    final trackSemantics = tester.getSemantics(
      find.byKey(const ValueKey('playlist-track-row-1')),
    );
    expect(trackSemantics.label, 'First track, Fixture artist');
    expect(
      trackSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('desktop shortcuts remain active while queue dialog has focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final media = _FakeMediaGateway([
      _ImmediateMediaOperation(_success('first-modal-shortcut')),
      _ImmediateMediaOperation(_success('second-modal-shortcut')),
    ]);
    await _openDetail(
      tester,
      media: media,
      audio: _FakeAudioEngine([_FakeAudioSession(), _FakeAudioSession()]),
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show queue'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.skipTraversal, isTrue);
    await _sendControlShortcut(tester, LogicalKeyboardKey.arrowRight);
    expect(_nowPlayingTitle(tester), 'Second track');
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paused'), findsOneWidget);
  });

  testWidgets('desktop traversal reaches consecutive track actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openDetail(
      tester,
      media: _FakeMediaGateway(const []),
      audio: _FakeAudioEngine(const []),
    );
    final first = find.byKey(const ValueKey('playlist-track-row-1'));
    final second = find.byKey(const ValueKey('playlist-track-row-2'));

    for (var attempt = 0; attempt < 8; attempt += 1) {
      if (tester.widget<InkWell>(first).focusNode?.hasFocus ?? false) break;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(tester.widget<InkWell>(first).focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.widget<InkWell>(second).focusNode?.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Play from here'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
  });

  testWidgets('desktop shortcuts remain active in lyrics and volume dialogs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final media = _FakeMediaGateway([
      _ImmediateMediaOperation(_success('first-modal-tools')),
      _ImmediateMediaOperation(_success('second-modal-tools')),
      _ImmediateMediaOperation(_success('returned-modal-tools')),
    ]);
    await _openDetail(
      tester,
      media: media,
      audio: _FakeAudioEngine([
        _FakeAudioSession(),
        _FakeAudioSession(),
        _FakeAudioSession(),
      ]),
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show lyrics'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await _sendControlShortcut(tester, LogicalKeyboardKey.arrowRight);
    expect(_nowPlayingTitle(tester), 'Second track');

    await tester.tap(find.byTooltip('Close lyrics'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volume'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('volume-slider')), findsOneWidget);
    await _sendControlShortcut(tester, LogicalKeyboardKey.arrowLeft);
    expect(_nowPlayingTitle(tester), 'First track');
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paused'), findsOneWidget);
  });

  testWidgets('narrow lyric and volume sheets retain playback shortcuts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('narrow-modal-tools')),
      ]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show lyrics'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paused'), findsOneWidget);

    await tester.tap(find.byTooltip('Close lyrics'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volume'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(find.textContaining('Playing'), findsOneWidget);
  });

  testWidgets('desktop context actions preserve positional queue intent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final queue = _WidgetQueueGateway();
    final media = _FakeMediaGateway([
      _ImmediateMediaOperation(_success('first-context')),
      _ImmediateMediaOperation(_success('second-context')),
    ]);
    await _openDetail(
      tester,
      media: media,
      audio: _FakeAudioEngine([_FakeAudioSession(), _FakeAudioSession()]),
      queue: queue,
    );
    await tester.tap(
      find.byKey(const ValueKey('playlist-track-row-1')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('Play from here'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    final secondRow = find.byKey(const ValueKey('playlist-track-row-2'));
    await tester.tap(
      secondRow,
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('Play from here'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
    await tester.tap(find.text('Add to queue'));
    await tester.pumpAndSettle();

    expect(queue.pushedTracks, hasLength(1));
    expect(queue.pushedTracks.single.opaqueId, 'second');
    expect(queue._snapshot.tracks, hasLength(3));
    expect(queue._snapshot.currentIndex, 0);
    expect(media.requests, [('qq-music', 'first')]);
    expect(find.text('Added to queue'), findsOneWidget);

    await tester.tap(
      secondRow,
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play from here'));
    await tester.pumpAndSettle();

    expect(queue.replacedIndex, 1);
    expect(queue._snapshot.tracks, hasLength(2));
    expect(_nowPlayingTitle(tester), 'Second track');
    expect(media.requests.last, ('qq-music', 'second'));
  });

  testWidgets('mobile long press exposes the same bounded track actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final queue = _WidgetQueueGateway();
    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('mobile-queue')),
      ]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
      queue: queue,
    );

    final trackSemantics = tester.getSemantics(
      find.byKey(const ValueKey('playlist-track-row-2')),
    );
    expect(
      trackSemantics.getSemanticsData().hasAction(SemanticsAction.longPress),
      isTrue,
    );
    semantics.dispose();

    await tester.longPress(find.byKey(const ValueKey('playlist-track-row-2')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(PopupMenuItem), findsNothing);
    expect(find.text('Play from here'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);

    await tester.tap(find.text('Add to queue'));
    await tester.pumpAndSettle();
    expect(queue.pushedTracks.single.opaqueId, 'second');
    expect(queue._snapshot.currentIndex, 0);
    expect(_nowPlayingTitle(tester), 'Second track');
    expect(find.text('Added to queue'), findsOneWidget);
  });

  testWidgets('empty-queue add confirms before media resolution completes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final result = Completer<MediaResolutionResult>();
    final pending = _PendingMediaOperation(result.future);
    final queue = _WidgetQueueGateway();
    await _openDetail(
      tester,
      media: _FakeMediaGateway([pending]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
      queue: queue,
    );

    await tester.longPress(find.byKey(const ValueKey('playlist-track-row-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to queue'));
    await tester.pump();
    await pending.started.future;
    await tester.pump();

    expect(queue._snapshot.currentIndex, 0);
    expect(queue._snapshot.tracks.single.opaqueId, 'second');
    expect(find.text('Added to queue'), findsOneWidget);
    expect(_nowPlayingTitle(tester), 'Second track');

    result.complete(_success('empty-queue-pending'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Playing'), findsOneWidget);
  });

  testWidgets(
    'failed context queue action keeps playback and reports failure',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final queue = _WidgetQueueGateway()
        ..nextPushResult = const PlaybackQueueResult(
          failure: PlaybackQueueFailure.coreUnavailable,
        );
      final media = _FakeMediaGateway(const []);
      await _openDetail(
        tester,
        media: media,
        audio: _FakeAudioEngine(const []),
        queue: queue,
      );

      await tester.tap(
        find.byKey(const ValueKey('playlist-track-row-2')),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();

      expect(queue.pushedTracks, isEmpty);
      expect(queue._snapshot.tracks, isEmpty);
      expect(media.requests, isEmpty);
      expect(find.text('Couldn’t update the queue'), findsOneWidget);
    },
  );

  testWidgets('queue panel preserves and removes duplicate positions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final queue = _WidgetQueueGateway();
    final media = _FakeMediaGateway([
      _ImmediateMediaOperation(_success('duplicate')),
      _ImmediateMediaOperation(_success('selected-duplicate')),
    ]);
    await _openDetail(
      tester,
      media: media,
      audio: _FakeAudioEngine([_FakeAudioSession(), _FakeAudioSession()]),
      firstOpaqueId: 'duplicate',
      secondOpaqueId: 'duplicate',
      secondTitle: 'First track',
      queue: queue,
    );

    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show queue'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('queue-entry-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('queue-entry-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('queue-artwork-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('queue-artwork-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('queue-artwork-placeholder')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('queue-current-indicator-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('queue-current-indicator-1')),
      findsNothing,
    );
    expect(find.text('2 tracks'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('queue-entry-0'))).label,
      'First track\nFixture artist',
    );
    final currentSemantics = tester
        .getSemantics(find.byKey(const ValueKey('queue-entry-0')))
        .getSemanticsData();
    final nextSemantics = tester
        .getSemantics(find.byKey(const ValueKey('queue-entry-1')))
        .getSemanticsData();
    expect(currentSemantics.flagsCollection.isSelected, Tristate.isTrue);
    expect(currentSemantics.flagsCollection.isButton, isFalse);
    expect(currentSemantics.hasAction(SemanticsAction.tap), isFalse);
    expect(nextSemantics.flagsCollection.isSelected, Tristate.isFalse);
    expect(nextSemantics.flagsCollection.isButton, isTrue);
    expect(nextSemantics.hasAction(SemanticsAction.tap), isTrue);

    queue.nextRemoveResult = const PlaybackQueueResult(
      failure: PlaybackQueueFailure.coreUnavailable,
    );
    await tester.tap(find.byKey(const ValueKey('queue-remove-0')));
    await tester.pumpAndSettle();
    expect(find.text('2 tracks'), findsOneWidget);
    final failureSemantics = tester.getSemantics(
      find.text('The music core could not update the queue.'),
    );
    expect(
      failureSemantics.label,
      'The music core could not update the queue.',
    );
    expect(
      failureSemantics.getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('queue-entry-1')));
    await tester.pumpAndSettle();
    expect(media.requests, hasLength(2));
    expect(
      find.byKey(const ValueKey('queue-current-indicator-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('queue-current-indicator-1')),
      findsOneWidget,
    );
    final previousSemantics = tester
        .getSemantics(find.byKey(const ValueKey('queue-entry-0')))
        .getSemanticsData();
    final selectedSemantics = tester
        .getSemantics(find.byKey(const ValueKey('queue-entry-1')))
        .getSemanticsData();
    expect(previousSemantics.flagsCollection.isSelected, Tristate.isFalse);
    expect(previousSemantics.flagsCollection.isButton, isTrue);
    expect(previousSemantics.hasAction(SemanticsAction.tap), isTrue);
    expect(selectedSemantics.flagsCollection.isSelected, Tristate.isTrue);
    expect(selectedSemantics.flagsCollection.isButton, isFalse);
    expect(selectedSemantics.hasAction(SemanticsAction.tap), isFalse);

    await tester.tap(find.byKey(const ValueKey('queue-remove-0')));
    await tester.pumpAndSettle();
    expect(find.text('1 track'), findsOneWidget);
    expect(find.byKey(const ValueKey('queue-entry-1')), findsNothing);
    expect(media.requests, hasLength(2));

    await tester.tap(find.byKey(const ValueKey('queue-remove-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('The queue is empty'), findsOneWidget);
    expect(find.byKey(const ValueKey('now-playing-title')), findsNothing);
    expect(media.requests, hasLength(2));
    semantics.dispose();
  });

  testWidgets('queue rows adapt existing metadata without changing actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('queue-metadata')),
      ]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
      durationSeconds: 125,
      albumTitle: 'Fixture album',
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show queue'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('queue-entry-0')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('queue-entry-1')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Fixture artist · Fixture album · 2:05'),
      findsNWidgets(2),
    );
    expect(find.byKey(const ValueKey('queue-duration-0')), findsNothing);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('queue-entry-0'))).label,
      contains('Fixture artist · Fixture album · 2:05'),
    );
    expect(find.byKey(const ValueKey('queue-remove-0')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show queue'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Fixture artist · Fixture album'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('queue-duration-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('queue-duration-1')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('queue-entry-0')),
        matching: find.text('2:05'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('queue-entry-1')),
        matching: find.text('2:05'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('queue-remove-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('queue clear requires confirmation and keeps shortcuts active', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final queue = _WidgetQueueGateway();
    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('clear-confirmation')),
      ]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
      queue: queue,
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show queue'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('queue-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Clear queue?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('queue-clear-confirmation-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('queue-clear-confirmation-dialog')),
      findsNothing,
    );
    expect(
      find.text('This will remove all 2 tracks and stop playback.'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paused'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('queue-clear-cancel')));
    await tester.pumpAndSettle();
    expect(queue._snapshot.tracks, hasLength(2));
    expect(find.byKey(const ValueKey('now-playing-title')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('queue-clear')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('queue-clear-confirmation-sheet')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('queue-clear-confirm')));
    await tester.pumpAndSettle();
    expect(queue._snapshot.tracks, isEmpty);
    expect(find.textContaining('The queue is empty'), findsOneWidget);
    expect(find.byKey(const ValueKey('now-playing-title')), findsNothing);
  });

  testWidgets('failed confirmed clear retains the queue and reports failure', (
    tester,
  ) async {
    final queue = _WidgetQueueGateway()
      ..nextClearResult = const PlaybackQueueResult(
        failure: PlaybackQueueFailure.coreUnavailable,
      );
    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('failed-clear')),
      ]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
      queue: queue,
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('queue-clear')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('queue-clear-confirmation-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('queue-clear-confirmation-sheet')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('queue-clear-confirm')));
    await tester.pumpAndSettle();

    expect(queue._snapshot.tracks, hasLength(2));
    expect(
      find.text('The music core could not update the queue.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('now-playing-title')), findsOneWidget);
  });

  testWidgets('opens synchronized lyrics as a narrow bottom sheet', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final session = _FakeAudioSession();
    await _openDetail(
      tester,
      media: _FakeMediaGateway([_ImmediateMediaOperation(_success('narrow'))]),
      audio: _FakeAudioEngine([session]),
      lyrics: _FakeLyricGateway(_lyricSuccess('Narrow synchronized line')),
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    session.emitPosition(1250);
    await tester.pump();

    await tester.tap(find.byTooltip('Show lyrics'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Narrow synchronized line'), findsOneWidget);
    expect(find.text('First track'), findsWidgets);
    final lyricLine = find.byKey(const ValueKey('lyrics-line-0'));
    expect(
      tester
          .getSemantics(lyricLine)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(lyricLine);
    await tester.pumpAndSettle();
    expect(session.seekPositions, [1000]);

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaStop);
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(lyricLine)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('wide lyric dialog follows completion to the next track', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final firstSession = _FakeAudioSession();
    final secondSession = _FakeAudioSession();
    final lyrics = _FakeLyricGateway.scripted([
      _lyricSuccess('First synchronized line'),
      _lyricSuccess('Second synchronized line'),
    ]);
    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('first')),
        _ImmediateMediaOperation(_success('second')),
      ]),
      audio: _FakeAudioEngine([firstSession, secondSession]),
      lyrics: lyrics,
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show lyrics'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('First synchronized line'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('lyrics-track-title')))
          .data,
      'First track',
    );

    firstSession.emitState(ForegroundAudioState.completed);
    await tester.pumpAndSettle();

    expect(find.text('First synchronized line'), findsNothing);
    expect(find.text('Second synchronized line'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('lyrics-track-title')))
          .data,
      'Second track',
    );
    expect(lyrics.requests, [('qq-music', 'first'), ('qq-music', 'second')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('now-playing surface does not overflow on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openDetail(
      tester,
      media: _FakeMediaGateway([_ImmediateMediaOperation(_success('narrow'))]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byTooltip('Volume'), findsOneWidget);
    expect(find.byTooltip('Show queue'), findsOneWidget);
    await tester.tap(find.byTooltip('Volume'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('volume-slider')), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show queue'));
    await tester.pumpAndSettle();
    expect(find.text('Queue'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paused'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playback modes are reachable and stable at 360 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final queue = _WidgetQueueGateway();
    final media = _FakeMediaGateway([
      _ImmediateMediaOperation(_success('mode-controls')),
    ]);

    await _openDetail(
      tester,
      media: media,
      audio: _FakeAudioEngine([_FakeAudioSession()]),
      queue: queue,
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Shuffle off. Turn on shuffle'), findsOneWidget);
    expect(find.byTooltip('Repeat off. Set repeat all'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('now-playing-shuffle')));
    await tester.pumpAndSettle();
    expect(queue._snapshot.order, PlaybackOrder.shuffle);
    expect(find.byTooltip('Shuffle on. Turn off shuffle'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('now-playing-repeat')));
    await tester.pumpAndSettle();
    expect(queue._snapshot.repeatMode, PlaybackRepeatMode.all);
    expect(find.byTooltip('Repeat all. Set repeat one'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('now-playing-repeat')));
    await tester.pumpAndSettle();
    expect(queue._snapshot.repeatMode, PlaybackRepeatMode.one);
    expect(find.byTooltip('Repeat one. Turn off repeat'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('now-playing-repeat')));
    await tester.pumpAndSettle();
    expect(queue._snapshot.repeatMode, PlaybackRepeatMode.off);
    expect(media.requests, [('qq-music', 'first')]);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('expanded-now-playing-compact-controls')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('now-playing-shuffle')), findsOneWidget);
    expect(find.byKey(const ValueKey('now-playing-repeat')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Track comments keep playback context across compact and wide surfaces',
    (tester) async {
      tester.view.physicalSize = const Size(360, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final comments = _FakeCommentGateway([
        _ImmediateCommentOperation(
          TrackCommentPageResult(
            total: 1,
            hotComments: [_comment('hot', 'A hot comment')],
            latestComments: [_comment('latest', 'A newest comment')],
          ),
        ),
        _ImmediateCommentOperation(
          TrackCommentPageResult(
            total: 1,
            latestComments: [_comment('wide', 'A wide comment')],
          ),
        ),
      ]);

      await _openDetail(
        tester,
        media: _FakeMediaGateway([
          _ImmediateMediaOperation(_success('comments')),
        ]),
        audio: _FakeAudioEngine([_FakeAudioSession()]),
        comments: comments,
      );
      await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
      await tester.pumpAndSettle();
      final commentsButton = find.byKey(
        const ValueKey('expanded-now-playing-comments'),
      );
      await tester.ensureVisible(commentsButton);
      await tester.tap(commentsButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('track-comments-compact-surface')),
        findsOneWidget,
      );
      expect(find.text('Hot comments'), findsOneWidget);
      expect(find.text('A newest comment'), findsOneWidget);
      expect(comments.requests, [('first', 0, 20)]);
      expect(
        find.byKey(const ValueKey('expanded-now-playing-compact-layout')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('track-comments-close')));
      await tester.pumpAndSettle();
      expect(find.text('First track'), findsWidgets);

      tester.view.physicalSize = const Size(1100, 844);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('expanded-now-playing-comments')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('track-comments-wide-surface')),
        findsOneWidget,
      );
      expect(find.text('A wide comment'), findsOneWidget);
      expect(comments.requests, [('first', 0, 20), ('first', 0, 20)]);
      expect(tester.takeException(), isNull);
    },
  );
}

String? _nowPlayingTitle(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('now-playing-title'))).data;

Future<void> _sendControlShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _openDetail(
  WidgetTester tester, {
  required _FakeMediaGateway media,
  required _FakeAudioEngine audio,
  _WidgetQueueGateway? queue,
  LyricGateway? lyrics,
  String firstOpaqueId = 'first',
  String secondOpaqueId = 'second',
  String secondTitle = 'Second track',
  int? durationSeconds = 120,
  String? artworkUri,
  String? albumTitle,
  AlbumSummary? album,
  List<ArtistSummary> artists = const [],
  QqMusicAuthenticationGateway? authenticationGateway,
  TrackCommentGateway? comments,
}) async {
  await tester.pumpWidget(
    MusicApp(
      bootstrap: _bootstrap,
      authenticationGateway:
          authenticationGateway ?? const _AuthenticatedGateway(),
      libraryGateway: const _LibraryGateway(),
      playlistDetailGateway: _DetailGateway(
        firstOpaqueId,
        secondOpaqueId,
        secondTitle,
        durationSeconds,
        artworkUri,
        albumTitle,
        album,
        artists,
      ),
      mediaResolutionGateway: media,
      lyricGateway:
          lyrics ??
          _FakeLyricGateway(
            const LyricLoadResult(failure: LyricFailure.unavailable),
          ),
      playbackQueueGateway: queue ?? _WidgetQueueGateway(),
      trackCommentGateway: comments,
      audioEngine: audio,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('primary-library-destination')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Fixture playlist').last);
  await tester.pumpAndSettle();
}

class _WidgetQueueGateway implements PlaybackQueueGateway {
  PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot.empty();
  List<PlaylistTrackSummary> replacedTracks = const [];
  final List<PlaylistTrackSummary> pushedTracks = [];
  int? replacedIndex;
  PlaybackQueueResult? nextPushResult;
  PlaybackQueueResult? nextRemoveResult;
  PlaybackQueueResult? nextClearResult;

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) {
    replacedTracks = List.of(tracks);
    replacedIndex = currentIndex;
    _snapshot = _makeSnapshot(
      tracks,
      currentIndex,
      order: _snapshot.order,
      repeatMode: _snapshot.repeatMode,
    );
    return PlaybackQueueResult(snapshot: _snapshot, playbackRequested: true);
  }

  @override
  PlaybackQueueResult completeCurrent() {
    final current = _snapshot.currentIndex;
    if (current != null && _snapshot.repeatMode == PlaybackRepeatMode.one) {
      return PlaybackQueueResult(snapshot: _snapshot, playbackRequested: true);
    }
    if (current == null || current + 1 >= _snapshot.tracks.length) {
      if (current != null && _snapshot.repeatMode == PlaybackRepeatMode.all) {
        _snapshot = _makeSnapshot(
          _snapshot.tracks,
          0,
          order: _snapshot.order,
          repeatMode: _snapshot.repeatMode,
        );
        return PlaybackQueueResult(
          snapshot: _snapshot,
          playbackRequested: true,
        );
      }
      return PlaybackQueueResult(snapshot: _snapshot);
    }
    _snapshot = _makeSnapshot(
      _snapshot.tracks,
      current + 1,
      order: _snapshot.order,
      repeatMode: _snapshot.repeatMode,
    );
    return PlaybackQueueResult(snapshot: _snapshot, playbackRequested: true);
  }

  @override
  PlaybackQueueResult advance() => completeCurrent();

  @override
  PlaybackQueueResult rewind() {
    final current = _snapshot.currentIndex;
    if (current == null || current == 0) {
      return PlaybackQueueResult(snapshot: _snapshot);
    }
    _snapshot = _makeSnapshot(
      _snapshot.tracks,
      current - 1,
      order: _snapshot.order,
      repeatMode: _snapshot.repeatMode,
    );
    return PlaybackQueueResult(snapshot: _snapshot, playbackRequested: true);
  }

  @override
  PlaybackQueueResult select(int index) {
    if (index < 0 || index >= _snapshot.tracks.length) {
      return const PlaybackQueueResult(
        failure: PlaybackQueueFailure.invalidPosition,
      );
    }
    final changed = index != _snapshot.currentIndex;
    _snapshot = _makeSnapshot(
      _snapshot.tracks,
      index,
      order: _snapshot.order,
      repeatMode: _snapshot.repeatMode,
    );
    return PlaybackQueueResult(snapshot: _snapshot, playbackRequested: changed);
  }

  @override
  PlaybackQueueResult clear() {
    final override = nextClearResult;
    nextClearResult = null;
    if (override != null) return override;
    final changed = _snapshot.current != null;
    _snapshot = _makeSnapshot(
      const [],
      null,
      order: _snapshot.order,
      repeatMode: _snapshot.repeatMode,
    );
    return PlaybackQueueResult(snapshot: _snapshot, playbackRequested: changed);
  }

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) {
    final override = nextPushResult;
    nextPushResult = null;
    if (override != null) return override;
    pushedTracks.add(track);
    final tracks = [..._snapshot.tracks, track];
    final currentIndex = _snapshot.currentIndex ?? 0;
    final playbackRequested = _snapshot.currentIndex == null;
    _snapshot = _makeSnapshot(
      tracks,
      currentIndex,
      order: _snapshot.order,
      repeatMode: _snapshot.repeatMode,
    );
    return PlaybackQueueResult(
      snapshot: _snapshot,
      playbackRequested: playbackRequested,
    );
  }

  @override
  PlaybackQueueResult remove(int index) {
    final override = nextRemoveResult;
    nextRemoveResult = null;
    if (override != null) return override;
    if (index < 0 || index >= _snapshot.tracks.length) {
      return const PlaybackQueueResult(
        failure: PlaybackQueueFailure.invalidPosition,
      );
    }
    final tracks = List.of(_snapshot.tracks)..removeAt(index);
    final oldCurrent = _snapshot.currentIndex!;
    final removedCurrent = index == oldCurrent;
    final currentIndex = tracks.isEmpty
        ? null
        : index < oldCurrent
        ? oldCurrent - 1
        : index > oldCurrent
        ? oldCurrent
        : index < tracks.length
        ? index
        : tracks.length - 1;
    _snapshot = _makeSnapshot(
      tracks,
      currentIndex,
      order: _snapshot.order,
      repeatMode: _snapshot.repeatMode,
    );
    return PlaybackQueueResult(
      snapshot: _snapshot,
      playbackRequested: removedCurrent,
    );
  }

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) {
    _snapshot = _makeSnapshot(
      _snapshot.tracks,
      _snapshot.currentIndex,
      order: order,
      repeatMode: _snapshot.repeatMode,
    );
    return PlaybackQueueResult(snapshot: _snapshot);
  }

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) {
    _snapshot = _makeSnapshot(
      _snapshot.tracks,
      _snapshot.currentIndex,
      order: _snapshot.order,
      repeatMode: repeatMode,
    );
    return PlaybackQueueResult(snapshot: _snapshot);
  }
}

PlaybackQueueSnapshot _makeSnapshot(
  List<PlaylistTrackSummary> tracks,
  int? currentIndex, {
  PlaybackOrder order = PlaybackOrder.sequential,
  PlaybackRepeatMode repeatMode = PlaybackRepeatMode.off,
}) => PlaybackQueueSnapshot(
  tracks: tracks,
  currentIndex: currentIndex,
  hasPrevious:
      currentIndex != null &&
      (currentIndex > 0 || repeatMode == PlaybackRepeatMode.all),
  hasNext:
      currentIndex != null &&
      (currentIndex + 1 < tracks.length ||
          repeatMode == PlaybackRepeatMode.all),
  order: order,
  repeatMode: repeatMode,
);

const _bootstrap = BootstrapStatus(
  coreVersion: '0.1.0-test',
  provider: ProviderStatus(
    id: 'qq-music',
    displayName: 'QQ Music',
    implementedCapabilities: ['Authentication', 'MediaResolution'],
  ),
);

class _AuthenticatedGateway implements QqMusicAuthenticationGateway {
  const _AuthenticatedGateway({this.onSignOut});

  final Future<CredentialSignOutResult> Function()? onSignOut;

  @override
  bool get hasAuthenticatedCredential => true;

  @override
  LoginStartOperation beginStart() => throw StateError('not used');

  @override
  CredentialVerificationOperation beginCredentialVerification() =>
      throw StateError('not used');

  @override
  Future<CredentialPersistenceResult> persistAuthenticatedCredential() async =>
      CredentialPersistenceResult.stored;

  @override
  Future<CredentialRestoreResult> restoreCredential() async =>
      CredentialRestoreResult.signedOut;

  @override
  Future<CredentialSignOutResult> signOut() async =>
      onSignOut?.call() ?? CredentialSignOutResult.signedOut;
}

class _LibraryGateway implements UserLibraryGateway {
  const _LibraryGateway();

  @override
  UserLibraryLoadOperation beginLoad() => const _LibraryOperation();
}

class _LibraryOperation implements UserLibraryLoadOperation {
  const _LibraryOperation();

  @override
  bool cancel() => true;

  @override
  Future<UserLibraryResult> run() async => const UserLibraryResult(
    playlists: [
      UserPlaylistSummary(
        providerId: 'qq-music',
        opaqueId: 'favorite:fixture',
        title: 'Fixture playlist',
        trackCount: 2,
      ),
    ],
  );
}

class _DetailGateway implements PlaylistDetailGateway {
  const _DetailGateway(
    this.firstOpaqueId,
    this.secondOpaqueId,
    this.secondTitle,
    this.durationSeconds,
    this.artworkUri,
    this.albumTitle,
    this.album,
    this.artists,
  );

  final String firstOpaqueId;
  final String secondOpaqueId;
  final String secondTitle;
  final int? durationSeconds;
  final String? artworkUri;
  final String? albumTitle;
  final AlbumSummary? album;
  final List<ArtistSummary> artists;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) => _DetailOperation(
    firstOpaqueId,
    secondOpaqueId,
    secondTitle,
    durationSeconds,
    artworkUri,
    albumTitle,
    album,
    artists,
  );
}

class _DetailOperation implements PlaylistTrackPageLoadOperation {
  const _DetailOperation(
    this.firstOpaqueId,
    this.secondOpaqueId,
    this.secondTitle,
    this.durationSeconds,
    this.artworkUri,
    this.albumTitle,
    this.album,
    this.artists,
  );

  final String firstOpaqueId;
  final String secondOpaqueId;
  final String secondTitle;
  final int? durationSeconds;
  final String? artworkUri;
  final String? albumTitle;
  final AlbumSummary? album;
  final List<ArtistSummary> artists;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async => PlaylistTrackPageResult(
    total: 2,
    tracks: [
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: firstOpaqueId,
        title: 'First track',
        artistNames: const ['Fixture artist'],
        artists: artists,
        albumTitle: albumTitle,
        album: album,
        durationSeconds: durationSeconds,
        artworkUri: artworkUri,
      ),
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: secondOpaqueId,
        title: secondTitle,
        artistNames: const ['Fixture artist'],
        artists: artists,
        albumTitle: albumTitle,
        album: album,
        durationSeconds: durationSeconds,
        artworkUri: artworkUri,
      ),
    ],
  );
}

TrackCommentSummary _comment(String id, String content) => TrackCommentSummary(
  providerId: 'qq-music',
  opaqueId: 'comment:$id',
  authorDisplayName: 'Author $id',
  content: content,
  publishedAtUnixSeconds: 1700000000,
  praiseCount: 8,
);

class _FakeCommentGateway implements TrackCommentGateway {
  _FakeCommentGateway(this.operations);

  final List<_ImmediateCommentOperation> operations;
  final List<(String, int, int)> requests = [];
  int next = 0;

  @override
  TrackCommentPageLoadOperation beginLoad({
    required PlaylistTrackSummary track,
    required int offset,
    required int size,
  }) {
    requests.add((track.opaqueId, offset, size));
    return operations[next++];
  }
}

class _ImmediateCommentOperation implements TrackCommentPageLoadOperation {
  const _ImmediateCommentOperation(this.result);

  final TrackCommentPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<TrackCommentPageResult> run() async => result;
}

MediaResolutionResult _success(String vkey) => MediaResolutionResult(
  source: ResolvedPlaybackSource(
    uri: Uri.parse('https://audio.example.test/source.mp3?vkey=$vkey'),
    format: PlaybackAudioFormat.mp3,
    quality: PlaybackAudioQuality.standard,
    validForSeconds: 7200,
  ),
);

LyricLoadResult _lyricSuccess(String text) => LyricLoadResult(
  lyrics: SynchronizedLyrics([
    SynchronizedLyricLine(
      text: text,
      startMs: 1000,
      durationMs: 1500,
      segments: const [],
    ),
  ]),
);

class _FakeMediaGateway implements MediaResolutionGateway {
  _FakeMediaGateway(this.operations);

  final List<MediaResolutionOperation> operations;
  final List<(String, String)> requests = [];
  int _next = 0;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) {
    requests.add((providerId, opaqueTrackId));
    return operations[_next++];
  }
}

class _ImmediateMediaOperation implements MediaResolutionOperation {
  const _ImmediateMediaOperation(this.result);

  final MediaResolutionResult result;

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async => result;
}

class _FakeLyricGateway implements LyricGateway {
  _FakeLyricGateway(LyricLoadResult result) : results = [result];

  _FakeLyricGateway.scripted(this.results);

  final List<LyricLoadResult> results;
  final List<(String, String)> requests = [];
  int _next = 0;

  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) {
    requests.add((providerId, opaqueTrackId));
    final result = results.length == 1 ? results.single : results[_next++];
    return _ImmediateLyricOperation(result);
  }
}

class _ImmediateLyricOperation implements LyricLoadOperation {
  const _ImmediateLyricOperation(this.result);

  final LyricLoadResult result;

  @override
  bool cancel() => true;

  @override
  Future<LyricLoadResult> run() async => result;
}

class _PendingMediaOperation implements MediaResolutionOperation {
  _PendingMediaOperation(this.result);

  final Future<MediaResolutionResult> result;
  final Completer<void> started = Completer<void>();

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() {
    started.complete();
    return result;
  }
}

class _FakeAudioEngine implements ForegroundAudioEngine {
  _FakeAudioEngine(this.sessions);

  final List<ForegroundAudioSession> sessions;
  final List<Uri> requestedUris = [];
  int _next = 0;

  @override
  Future<ForegroundAudioSession> loadRemote(Uri source) async {
    requestedUris.add(source);
    return sessions[_next++];
  }
}

class _FakeAudioSession implements ForegroundAudioSession {
  final StreamController<ForegroundAudioState> _states =
      StreamController<ForegroundAudioState>.broadcast();
  final StreamController<ForegroundAudioFailure> _failures =
      StreamController<ForegroundAudioFailure>.broadcast();
  final StreamController<int> _positions = StreamController<int>.broadcast();
  final List<int> seekPositions = [];
  final List<double> volumes = [];
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
  Future<void> seekToMs(int positionMs) async {
    seekPositions.add(positionMs);
    _positions.add(positionMs);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

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

  void emitState(ForegroundAudioState state) => _states.add(state);

  void emitPosition(int positionMs) => _positions.add(positionMs);
}
