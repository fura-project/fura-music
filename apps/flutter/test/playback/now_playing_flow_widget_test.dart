import 'dart:async';
import 'dart:io';
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
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
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
    final presence = find.byKey(
      const ValueKey('now-playing-presence-transition'),
    );
    expect(presence, findsOneWidget);
    expect(tester.getSize(presence).height, 0);
    expect(
      find.byKey(const ValueKey('now-playing-open-expanded')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('now-playing-present')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));
    final enteringHeight = tester.getSize(presence).height;
    expect(enteringHeight, greaterThan(0));
    expect(enteringHeight, lessThan(88));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('now-playing-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('now-playing-artwork')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('now-playing-artwork-placeholder')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('now-playing-artwork-action')),
      findsNothing,
    );
    final trackIdentityAction = find.byKey(
      const ValueKey('now-playing-open-expanded'),
    );
    final trackIdentityRect = tester.getRect(trackIdentityAction);
    expect(
      trackIdentityRect.contains(
        tester.getCenter(find.byKey(const ValueKey('now-playing-artwork'))),
      ),
      isTrue,
    );
    expect(
      trackIdentityRect.contains(
        tester.getCenter(find.byKey(const ValueKey('now-playing-title'))),
      ),
      isTrue,
    );
    expect(
      tester.getSemantics(trackIdentityAction).label,
      'Open now playing for First track',
    );
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

  testWidgets('first mobile playback bar honors reduced motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('reduced-motion')),
      ]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
    );
    final presence = find.byKey(
      const ValueKey('now-playing-presence-transition'),
    );
    expect(tester.getSize(presence).height, 0);

    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pump();

    expect(tester.getSize(presence).height, 80);
    expect(
      find.byKey(const ValueKey('now-playing-compact-layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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
          matching: find.byKey(const ValueKey('now-playing-lyric-auxiliary')),
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

  testWidgets('quality selector persists SQ and reloads the active source', (
    tester,
  ) async {
    final settingsStorage = _MemorySettingsStorage();
    final media = _FakeMediaGateway([
      _ImmediateMediaOperation(_success('standard')),
      _ImmediateMediaOperation(
        _qualitySuccess(
          'lossless',
          format: PlaybackAudioFormat.flac,
          quality: PlaybackAudioQuality.lossless,
        ),
      ),
    ]);
    final audio = _FakeAudioEngine([_FakeAudioSession(), _FakeAudioSession()]);
    await _openDetail(
      tester,
      media: media,
      audio: audio,
      settingsStore: AppSettingsStore(storage: settingsStorage),
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();

    expect(find.text('STD'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('now-playing-quality')));
    await tester.pumpAndSettle();
    expect(find.text('SQ · FLAC lossless'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('now-playing-quality-lossless')),
    );
    await tester.pumpAndSettle();

    expect(find.text('SQ'), findsOneWidget);
    expect(find.text('Playing SQ quality.'), findsOneWidget);
    expect(media.requests, [('qq-music', 'first'), ('qq-music', 'first')]);
    expect(audio.requestedFormats, [
      ForegroundAudioFormat.mp3,
      ForegroundAudioFormat.flac,
    ]);
    expect(settingsStorage.document, contains('"playbackQuality":"lossless"'));
  });

  testWidgets(
    'lyric auxiliary selector persists pronunciation without reloading audio',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final settingsStorage = _MemorySettingsStorage();
      final media = _FakeMediaGateway([
        _ImmediateMediaOperation(_success('lyric-mode')),
      ]);
      await _openDetail(
        tester,
        media: media,
        audio: _FakeAudioEngine([_FakeAudioSession()]),
        lyrics: _FakeLyricGateway(_lyricAuxiliarySuccess()),
        settingsStore: AppSettingsStore(storage: settingsStorage),
      );
      await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('now-playing-lyric-auxiliary')),
            )
            .label,
        'Lyrics auxiliary: Auto',
      );

      await tester.tap(
        find.byKey(const ValueKey('now-playing-lyric-auxiliary')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckedPopupMenuItem<LyricAuxiliaryMode>>(
              find.byKey(
                const ValueKey('now-playing-lyric-auxiliary-romanization'),
              ),
            )
            .enabled,
        isTrue,
      );
      await tester.tap(
        find.byKey(const ValueKey('now-playing-lyric-auxiliary-romanization')),
      );
      await tester.pumpAndSettle();

      expect(
        settingsStorage.document,
        contains('"lyricAuxiliaryMode":"romanization"'),
      );
      expect(media.requests, [('qq-music', 'first')]);
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('now-playing-lyric-auxiliary')),
            )
            .label,
        'Lyrics auxiliary: Pronunciation',
      );

      await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
      await tester.pumpAndSettle();
      expect(find.text('fixture pronunciation'), findsOneWidget);
      expect(find.text('fixture translation'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'unavailable auxiliary choices stay disabled without mutating preference',
    (tester) async {
      final settingsStorage = _MemorySettingsStorage();
      await _openDetail(
        tester,
        media: _FakeMediaGateway([
          _ImmediateMediaOperation(_success('no-auxiliary')),
        ]),
        audio: _FakeAudioEngine([_FakeAudioSession()]),
        settingsStore: AppSettingsStore(storage: settingsStorage),
      );
      await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('now-playing-lyric-auxiliary')),
      );
      await tester.pumpAndSettle();
      final translation = tester
          .widget<CheckedPopupMenuItem<LyricAuxiliaryMode>>(
            find.byKey(
              const ValueKey('now-playing-lyric-auxiliary-translation'),
            ),
          );
      final romanization = tester
          .widget<CheckedPopupMenuItem<LyricAuxiliaryMode>>(
            find.byKey(
              const ValueKey('now-playing-lyric-auxiliary-romanization'),
            ),
          );
      expect(translation.enabled, isFalse);
      expect(romanization.enabled, isFalse);
      expect(settingsStorage.document, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop identity area opens lyrics before the Artist catalog chooser',
    (tester) async {
      const captureCatalogEntry = bool.fromEnvironment(
        'NOW_PLAYING_CATALOG_VISUAL_REVIEW',
      );
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
      // This fixture exposes independent Artist/Album hit targets. Activate
      // the title portion when the test intends to play the row.
      await tester.tap(find.text('First track'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('now-playing-catalog-action')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('now-playing-artwork')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('expanded-now-playing-page')),
        findsOneWidget,
      );
      if (captureCatalogEntry) {
        await expectLater(
          find.byType(MusicApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-expanded-now-playing-catalog-link.png'),
          ),
        );
      }
      await tester.tap(
        find.byKey(const ValueKey('expanded-now-playing-open-catalog')),
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
    expect(find.byKey(const ValueKey('liked-songs-page')), findsOneWidget);
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
    expect(find.byKey(const ValueKey('liked-songs-page')), findsOneWidget);

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

  testWidgets('desktop shortcuts remain active while queue sheet has focus', (
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

    expect(
      find.byKey(const ValueKey('playback-queue-wide-side-sheet')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
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

    for (var attempt = 0; attempt < 20; attempt += 1) {
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

  testWidgets('desktop shortcuts remain active in expanded lyrics and volume', (
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

    expect(find.byTooltip('Show lyrics'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('expanded-now-playing-page')),
      findsOneWidget,
    );
    await _sendControlShortcut(tester, LogicalKeyboardKey.arrowRight);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('expanded-now-playing-title')),
          )
          .data,
      'Second track',
    );

    await tester.tap(find.byTooltip('Volume'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('volume-slider')), findsOneWidget);
    await _sendControlShortcut(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.text('First track'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paused'), findsOneWidget);
  });

  testWidgets('narrow expanded lyrics and volume retain playback shortcuts', (
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

    await tester.tap(find.byKey(const ValueKey('now-playing-artwork')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('expanded-now-playing-page')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Resume'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('expanded-now-playing-compact-control-row')),
      findsOneWidget,
    );
    expect(find.byTooltip('Volume'), findsNothing);
    expect(find.byTooltip('Stop'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause'), findsOneWidget);
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

    expect(
      find.byKey(const ValueKey('playback-queue-wide-side-sheet')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
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

  testWidgets('opens synchronized lyrics from the narrow playback surface', (
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

    await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('expanded-now-playing-page')),
      findsOneWidget,
    );
    expect(find.byType(BottomSheet), findsNothing);
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

  testWidgets('wide expanded lyrics follow completion to the next track', (
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
    expect(find.byTooltip('Show lyrics'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('expanded-now-playing-page')),
      findsOneWidget,
    );
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
    await tester.pump();
    final presence = find.byKey(
      const ValueKey('now-playing-presence-transition'),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getSize(presence).height, greaterThan(0));
    expect(tester.getSize(presence).height, lessThan(80));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('now-playing-compact-layout'))),
      const Size(366, 68),
    );
    final compactSurface = tester.widget<Material>(
      find.byKey(const ValueKey('now-playing-compact-layout')),
    );
    expect(compactSurface.elevation, 0);
    final compactShape = compactSurface.shape! as RoundedRectangleBorder;
    expect(compactShape.side, BorderSide.none);
    expect(compactShape.borderRadius, BorderRadius.circular(28));
    final primaryAction = find.byKey(
      const ValueKey('now-playing-primary-action'),
    );
    final primaryColor = Theme.of(tester.element(primaryAction))
        .colorScheme
        .primary;
    expect(
      tester
          .widgetList<Material>(
            find.descendant(of: primaryAction, matching: find.byType(Material)),
          )
          .any((material) => material.color == primaryColor),
      isTrue,
    );
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsNothing);
    expect(find.byTooltip('Volume'), findsNothing);
    expect(find.byTooltip('Show queue'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('now-playing-primary-action')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('expanded-now-playing-page')),
      findsNothing,
    );
    expect(find.byTooltip('Resume'), findsOneWidget);
    await tester.tap(find.byTooltip('Show queue'));
    await tester.pumpAndSettle();
    expect(find.text('Queue'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('expanded-now-playing-page')),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(find.textContaining('Playing'), findsOneWidget);
    await tester.tap(find.byTooltip('Close queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('expanded-now-playing-compact-control-row')),
      findsOneWidget,
    );
    expect(find.byTooltip('Stop'), findsNothing);
    expect(find.byTooltip('Volume'), findsNothing);
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

    expect(find.byTooltip('Shuffle off. Turn on shuffle'), findsNothing);
    expect(find.byTooltip('Repeat off. Set repeat all'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('expanded-now-playing-compact-controls')),
      findsOneWidget,
    );
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

    expect(find.byKey(const ValueKey('now-playing-shuffle')), findsOneWidget);
    expect(find.byKey(const ValueKey('now-playing-repeat')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact expanded controls form one formula-positioned strip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _loadPlaybackControlReviewFonts(tester);

    await _openDetail(
      tester,
      media: _FakeMediaGateway([
        _ImmediateMediaOperation(_success('compact-geometry')),
      ]),
      audio: _FakeAudioEngine([_FakeAudioSession()]),
    );
    await tester.tap(find.byKey(const ValueKey('playlist-track-row-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('now-playing-open-expanded')));
    await tester.pumpAndSettle();

    for (final size in const [
      Size(430, 932),
      Size(412, 915),
      Size(390, 844),
      Size(360, 800),
      Size(320, 700),
    ]) {
      if (size.width == 320) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures.allOn;
      }
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();

      final controls = find.byKey(
        const ValueKey('expanded-now-playing-compact-controls'),
      );
      final row = find.byKey(
        const ValueKey('expanded-now-playing-compact-control-row'),
      );
      final strip = find.byKey(
        const ValueKey('expanded-now-playing-compact-control-strip'),
      );
      final primary = find.byKey(const ValueKey('now-playing-primary-action'));
      expect(controls, findsOneWidget);
      expect(strip, findsOneWidget);
      expect(
        find.descendant(of: controls, matching: find.byType(FittedBox)),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.byType(PositionedDirectional)),
        findsOneWidget,
      );
      final rowRect = tester.getRect(row);
      final stripRect = tester.getRect(strip);
      final primaryRect = tester.getRect(primary);
      final geometry = _expectedCompactControlGeometry(size.width);
      expect(rowRect.width, size.width);
      expect(rowRect.center.dx, closeTo(size.width / 2, 0.5));
      expect(stripRect.left, closeTo(rowRect.left + geometry.stripStart, 0.5));
      expect(stripRect.width, closeTo(geometry.stripExtent, 0.5));
      expect(
        primaryRect.center.dx,
        closeTo(stripRect.left + geometry.primaryCenterInsideStrip, 0.5),
      );
      expect(primaryRect.width, 48);
      expect(primaryRect.height, 48);
      expect(stripRect.left, greaterThanOrEqualTo(rowRect.left + 3.5));
      expect(stripRect.right, lessThanOrEqualTo(rowRect.right - 3.5));
      expect(stripRect.width, lessThanOrEqualTo(rowRect.width - 8));
      expect(
        find.byKey(const ValueKey('now-playing-quality')),
        geometry.showQuality ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('now-playing-lyric-auxiliary')),
        findsOneWidget,
      );
      final orderedKeys = <String>[
        if (!geometry.combineOptions) 'now-playing-lyric-auxiliary',
        if (geometry.combineOptions)
          geometry.showQuality
              ? 'now-playing-quality'
              : 'now-playing-lyric-auxiliary',
        'now-playing-shuffle',
        'now-playing-previous',
        'now-playing-primary-action',
        'now-playing-next',
        'now-playing-repeat',
        if (!geometry.combineOptions && geometry.showQuality)
          'now-playing-quality',
        'now-playing-show-queue',
      ];
      final targetRects = [
        for (final key in orderedKeys)
          tester.getRect(find.byKey(ValueKey(key))),
      ];
      for (var index = 0; index < targetRects.length; index += 1) {
        final target = targetRects[index];
        final expectedExtent =
            orderedKeys[index] == 'now-playing-primary-action' ? 48.0 : 40.0;
        expect(target.width, closeTo(expectedExtent, 0.5));
        expect(target.height, closeTo(expectedExtent, 0.5));
        if (index == 0) continue;
        final adjacentGap = target.left - targetRects[index - 1].right;
        expect(adjacentGap, closeTo(geometry.gap, 0.5));
        expect(adjacentGap, inInclusiveRange(2, 4));
      }
      if (const bool.fromEnvironment('PLAYBACK_CONTROL_VISUAL_REVIEW')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            Uri.file(
              '/tmp/fura-expanded-controls-'
              '${size.width.toInt()}x${size.height.toInt()}.png',
            ),
          ),
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('compact expanded controls remain one contiguous strip in RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const tracks = [
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:rtl:first',
        title: 'RTL first',
        artistNames: ['RTL artist'],
        durationSeconds: 120,
      ),
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:rtl:second',
        title: 'RTL second',
        artistNames: ['RTL artist'],
        durationSeconds: 120,
      ),
    ];
    final queue = _WidgetQueueGateway();
    final controller = QueuePlaybackController(
      queue,
      TrackPlaybackController(
        _FakeMediaGateway([_ImmediateMediaOperation(_success('rtl-geometry'))]),
        ForegroundPlaybackController(_FakeAudioEngine([_FakeAudioSession()])),
      ),
    );
    addTearDown(controller.dispose);
    await controller.replaceAndPlay(tracks, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            bottomNavigationBar: NowPlayingBar.expanded(
              controller: controller,
              onSignInAgain: () {},
              qualityPreference: AppPlaybackQualityPreference.standard,
              onQualityPreferenceChanged: (_) async {},
              lyricAuxiliaryMode: LyricAuxiliaryMode.auto,
              onLyricAuxiliaryModeChanged: (_) async => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rowRect = tester.getRect(
      find.byKey(const ValueKey('expanded-now-playing-compact-control-row')),
    );
    final stripRect = tester.getRect(
      find.byKey(const ValueKey('expanded-now-playing-compact-control-strip')),
    );
    final primaryRect = tester.getRect(
      find.byKey(const ValueKey('now-playing-primary-action')),
    );
    final geometry = _expectedCompactControlGeometry(rowRect.width);
    expect(stripRect.width, closeTo(geometry.stripExtent, 0.5));
    expect(stripRect.right, closeTo(rowRect.right - geometry.stripStart, 0.5));
    expect(
      rowRect.right - primaryRect.center.dx,
      closeTo(geometry.stripStart + geometry.primaryCenterInsideStrip, 0.5),
    );
    final physicalOrder = [
      'now-playing-show-queue',
      'now-playing-quality',
      'now-playing-repeat',
      'now-playing-next',
      'now-playing-primary-action',
      'now-playing-previous',
      'now-playing-shuffle',
      'now-playing-lyric-auxiliary',
    ];
    final physicalRects = [
      for (final key in physicalOrder)
        tester.getRect(find.byKey(ValueKey(key))),
    ];
    for (var index = 1; index < physicalRects.length; index += 1) {
      expect(
        physicalRects[index].left - physicalRects[index - 1].right,
        closeTo(geometry.gap, 0.5),
      );
    }
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
            nextOffset: 1,
            hotComments: [_comment('hot', 'A hot comment')],
            latestComments: [_comment('latest', 'A newest comment')],
          ),
        ),
        _ImmediateCommentOperation(
          TrackCommentPageResult(
            total: 1,
            nextOffset: 1,
            latestComments: [
              _comment(
                'wide',
                'A wide comment',
                avatarUri: 'https://example.invalid/avatar.jpg',
              ),
            ],
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
      final pageColors = Theme.of(
        tester.element(
          find.byKey(const ValueKey('expanded-now-playing-artwork-backdrop')),
        ),
      ).colorScheme;
      await tester.tap(
        find.byKey(const ValueKey('expanded-now-playing-comments')),
      );
      await tester.pumpAndSettle();
      final sideSheet = find.byKey(
        const ValueKey('track-comments-wide-side-sheet'),
      );
      expect(sideSheet, findsOneWidget);
      expect(
        find.byKey(const ValueKey('track-comments-wide-surface')),
        findsNothing,
      );
      expect(tester.getRect(sideSheet).right, 1088);
      expect(
        Theme.of(tester.element(sideSheet)).colorScheme.primary,
        pageColors.primary,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('track-comment-avatar')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      expect(find.text('A wide comment'), findsOneWidget);
      expect(comments.requests, [('first', 0, 20), ('first', 0, 20)]);
      expect(tester.takeException(), isNull);
    },
  );
}

({
  bool showQuality,
  bool combineOptions,
  double gap,
  double stripExtent,
  double primaryCenterInsideStrip,
  double stripStart,
})
_expectedCompactControlGeometry(double availableWidth) {
  const secondaryExtent = 40.0;
  const primaryExtent = 48.0;
  const minimumGap = 2.0;
  const preferredGap = 4.0;
  const horizontalInset = 4.0;
  final showQuality = availableWidth > 320;
  final combineOptions = availableWidth <= 360;
  final leadingControlCount = 3;
  final trailingControlCount = combineOptions ? 3 : 4;
  final secondaryCount = leadingControlCount + trailingControlCount;
  final gapCount = secondaryCount;
  final baseStripExtent = (secondaryCount * secondaryExtent) + primaryExtent;
  final centeredGapCapacity =
      ((availableWidth / 2) -
          horizontalInset -
          (primaryExtent / 2) -
          (trailingControlCount * secondaryExtent)) /
      trailingControlCount;
  final fitGapCapacity =
      (availableWidth - (2 * horizontalInset) - baseStripExtent) / gapCount;
  final gapCapacity = centeredGapCapacity < fitGapCapacity
      ? centeredGapCapacity
      : fitGapCapacity;
  final gap = gapCapacity.clamp(minimumGap, preferredGap).toDouble();
  final stripExtent = baseStripExtent + (gapCount * gap);
  final primaryCenterInsideStrip =
      (leadingControlCount * secondaryExtent) +
      (leadingControlCount * gap) +
      (primaryExtent / 2);
  final idealStart = (availableWidth / 2) - primaryCenterInsideStrip;
  final maximumStart = availableWidth - horizontalInset - stripExtent;
  final stripStart = idealStart
      .clamp(
        horizontalInset,
        maximumStart < horizontalInset ? horizontalInset : maximumStart,
      )
      .toDouble();
  return (
    showQuality: showQuality,
    combineOptions: combineOptions,
    gap: gap,
    stripExtent: stripExtent,
    primaryCenterInsideStrip: primaryCenterInsideStrip,
    stripStart: stripStart,
  );
}

Future<void> _loadPlaybackControlReviewFonts(WidgetTester tester) async {
  const capture = bool.fromEnvironment('PLAYBACK_CONTROL_VISUAL_REVIEW');
  const reviewFont = String.fromEnvironment('HOME_REVIEW_CJK_FONT');
  if (!capture || reviewFont.isEmpty) return;
  await tester.runAsync(() async {
    await (FontLoader('Roboto')
          ..addFont(File(reviewFont).readAsBytes().then(ByteData.sublistView)))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
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
  AppSettingsStore? settingsStore,
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
      settingsStore: settingsStore,
    ),
  );
  await tester.pumpAndSettle();
  final sidebarPlaylist = find.text('Fixture playlist');
  if (find.byKey(const ValueKey('open-liked-songs')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('primary-library-destination')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('liked-tab-playlists')));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(sidebarPlaylist.last);
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
  PlaybackQueueResult extendAndAdvanceFromTerminal(
    List<PlaylistTrackSummary> tracks,
  ) => PlaybackQueueResult(snapshot: _snapshot);

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
  providers: [
    ProviderStatus(
      id: 'qq-music',
      displayName: 'QQ Music',
      implementedCapabilities: ['Authentication', 'MediaResolution'],
    ),
  ],
  defaultProviderId: 'qq-music',
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
    nextOffset: 2,
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

TrackCommentSummary _comment(String id, String content, {String? avatarUri}) =>
    TrackCommentSummary(
      providerId: 'qq-music',
      opaqueId: 'comment:$id',
      authorDisplayName: 'Author $id',
      authorAvatarUri: avatarUri,
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

MediaResolutionResult _qualitySuccess(
  String vkey, {
  required PlaybackAudioFormat format,
  required PlaybackAudioQuality quality,
}) => MediaResolutionResult(
  source: ResolvedPlaybackSource(
    uri: Uri.parse('https://audio.example.test/source?vkey=$vkey'),
    format: format,
    quality: quality,
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

LyricLoadResult _lyricAuxiliarySuccess() => LyricLoadResult(
  lyrics: SynchronizedLyrics([
    SynchronizedLyricLine(
      text: 'fixture original',
      startMs: 1000,
      durationMs: 1500,
      translation: 'fixture translation',
      romanization: 'fixture pronunciation',
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
  final List<ForegroundAudioFormat> requestedFormats = [];
  int _next = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) async {
    requestedUris.add(source);
    requestedFormats.add(format);
    return sessions[_next++];
  }
}

class _MemorySettingsStorage implements AppSettingsDocumentStorage {
  String? document;

  @override
  Future<void> delete() async => document = null;

  @override
  Future<String?> read() async => document;

  @override
  Future<void> write(String document) async => this.document = document;
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
