import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/catalog/music_artwork_placeholder.dart';
import 'package:flutterustmusic/discover/new_song_controller.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/radar_controller.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/daily_recommendation_gateway.dart';
import 'package:flutterustmusic/home/home_controller.dart';
import 'package:flutterustmusic/home/home_page.dart';
import 'package:flutterustmusic/home/home_spotlight_controller.dart';
import 'package:flutterustmusic/home/official_playlist_controller.dart';
import 'package:flutterustmusic/home/official_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_track_gateway.dart';
import 'package:flutterustmusic/home/recent_listening_gateway.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

Future<ui.Image> _createSolidImage(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  picture.dispose();
  return image;
}

class _ControlledArtworkBank {
  final Map<String, Completer<ui.Image>> _completers =
      <String, Completer<ui.Image>>{};
  final List<String> requestedUris = <String>[];

  ImageProvider<Object> providerFor(String uri) {
    final completer = _completers.putIfAbsent(uri, Completer<ui.Image>.new);
    return _BankImageProvider(
      uri,
      completer,
      onLoad: () {
        requestedUris.add(uri);
      },
    );
  }

  Future<void> complete(WidgetTester tester, String uri, Color color) async {
    final completer = _completers.putIfAbsent(uri, Completer<ui.Image>.new);
    if (completer.isCompleted) return;
    final image = await tester.runAsync(() => _createSolidImage(color));
    completer.complete(image!);
  }

  void fail(String uri) {
    final completer = _completers.putIfAbsent(uri, Completer<ui.Image>.new);
    if (completer.isCompleted) return;
    completer.completeError(StateError('Simulated artwork failure for $uri'));
  }

  void reset() {
    _completers.clear();
    requestedUris.clear();
  }
}

class _BankImageProvider extends ImageProvider<_BankImageProvider> {
  const _BankImageProvider(this.uri, this.completer, {required this.onLoad});

  final String uri;
  final Completer<ui.Image> completer;
  final VoidCallback onLoad;

  @override
  Future<_BankImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_BankImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _BankImageProvider key,
    ImageDecoderCallback decode,
  ) {
    onLoad();
    return OneFrameImageStreamCompleter(
      completer.future.then((image) => ImageInfo(image: image)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _BankImageProvider && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

class _HomeHarness {
  _HomeHarness({
    required this.homeController,
    required this.officialController,
    required this.publicController,
    required this.spotlightController,
    required this.newSongController,
    required this.radarController,
    required this.queueController,
  });

  final HomeController homeController;
  final OfficialPlaylistController officialController;
  final RecommendedPlaylistController publicController;
  final HomeSpotlightController spotlightController;
  final NewSongController newSongController;
  final RadarController radarController;
  final QueuePlaybackController queueController;

  void dispose() {
    spotlightController.dispose();
    officialController.dispose();
    publicController.dispose();
    newSongController.dispose();
    radarController.dispose();
    homeController.dispose();
    queueController.dispose();
  }
}

Future<_HomeHarness> _createHarness() async {
  final officialController = OfficialPlaylistController(
    const _OfficialGateway(
      OfficialPlaylistPageResult(
        page: 1,
        nextPage: 2,
        total: 3,
        playlists: [
          OfficialPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'official:A',
            title: 'Hero A',
            artworkUri: 'https://example.invalid/hero-a.jpg',
          ),
          OfficialPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'official:B',
            title: 'Hero B',
            artworkUri: 'https://example.invalid/hero-b.jpg',
          ),
          OfficialPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'official:C',
            title: 'Hero C',
            artworkUri: 'https://example.invalid/hero-c.jpg',
          ),
        ],
      ),
    ),
  );
  final publicController = RecommendedPlaylistController(
    const _PublicGateway(RecommendedPlaylistPageResult()),
  );
  final spotlightController = HomeSpotlightController(
    officialController,
    publicController,
  );
  final newSongController = NewSongController(const _NewSongGateway());
  final radarController = RadarController(const _RadarGateway());
  final homeController = HomeController(
    const _AccountGateway(),
    const _DailyGateway(),
    const _PersonalizedPlaylistsGateway(),
    const _PersonalizedTracksGateway(),
    const _RelatedTracksGateway(),
    recentListening: const _RecentListeningGateway(),
  );
  final queueController = QueuePlaybackController(
    _StubQueueGateway(),
    TrackPlaybackController(
      const _StubMediaGateway(),
      ForegroundPlaybackController(const _StubAudioEngine()),
    ),
  );
  await spotlightController.load();
  return _HomeHarness(
    homeController: homeController,
    officialController: officialController,
    publicController: publicController,
    spotlightController: spotlightController,
    newSongController: newSongController,
    radarController: radarController,
    queueController: queueController,
  );
}

Widget _wrapHome(
  _HomeHarness harness,
  _ControlledArtworkBank bank, {
  Duration rotationInterval = const Duration(seconds: 12),
  Duration preloadTimeout = const Duration(milliseconds: 1500),
  bool active = true,
}) => MaterialApp(
  theme: MusicMaterialTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: HomePage(
      homeController: harness.homeController,
      spotlightController: harness.spotlightController,
      recommendationController: harness.publicController,
      newSongController: harness.newSongController,
      radarController: harness.radarController,
      queuePlaybackController: harness.queueController,
      authenticated: false,
      active: active,
      onOpenDiscover: () {},
      onOpenLibrary: () {},
      onOpenRecommendation: (_) {},
      spotlightRotationInterval: rotationInterval,
      spotlightPreloadTimeout: preloadTimeout,
      spotlightImageProviderBuilder: bank.providerFor,
    ),
  ),
);

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
    'proactively preloads adjacent Hero covers and switches without placeholder flash once warm',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final bank = _ControlledArtworkBank();

      await tester.pumpWidget(_wrapHome(harness, bank));
      await tester.pump();

      // Home proactively kicks off preloading for next (B) and previous (C)
      // alongside the visible current Hero (A).
      expect(
        bank.requestedUris,
        containsAll(<String>[
          'https://example.invalid/hero-a.jpg',
          'https://example.invalid/hero-b.jpg',
          'https://example.invalid/hero-c.jpg',
        ]),
      );

      // Decode A and B before switching, and let A's initial 120ms reveal settle.
      await bank.complete(
        tester,
        'https://example.invalid/hero-a.jpg',
        Colors.indigo,
      );
      await bank.complete(
        tester,
        'https://example.invalid/hero-b.jpg',
        Colors.teal,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Next: B is already warm in ImageCache, so it switches immediately
      // with zero placeholder shown inside the Hero switcher or incoming scene.
      await tester.tap(find.byKey(const ValueKey('home-spotlight-next')));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-spotlight-scene-switcher')),
          matching: find.text('Hero B'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-spotlight-scene-switcher')),
          matching: find.byType(MusicArtworkPlaceholder),
        ),
        findsNothing,
      );

      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'defers Hero switch until target cover finishes preloading on manual next and auto-rotation timer',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final bank = _ControlledArtworkBank();

      await tester.pumpWidget(_wrapHome(harness, bank));
      await bank.complete(
        tester,
        'https://example.invalid/hero-a.jpg',
        Colors.indigo,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Next while B is still loading: Hero retains A instead of sliding in
      // an empty placeholder.
      await tester.tap(find.byKey(const ValueKey('home-spotlight-next')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero A',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-spotlight-scene-switcher')),
          matching: find.byType(MusicArtworkPlaceholder),
        ),
        findsNothing,
      );

      // Complete B: Hero commits the switch with B already decoded.
      await bank.complete(
        tester,
        'https://example.invalid/hero-b.jpg',
        Colors.teal,
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-spotlight-scene-switcher')),
          matching: find.text('Hero B'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-spotlight-scene-switcher')),
          matching: find.byType(MusicArtworkPlaceholder),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();

      // Auto-rotation timer fires while C is still loading: Hero retains B
      // until C finishes decoding.
      await tester.pump(const Duration(seconds: 12));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero B',
      );
      await bank.complete(
        tester,
        'https://example.invalid/hero-c.jpg',
        Colors.amber,
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-spotlight-scene-switcher')),
          matching: find.text('Hero C'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-spotlight-scene-switcher')),
          matching: find.byType(MusicArtworkPlaceholder),
        ),
        findsNothing,
      );

      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rapid double-click advances pending target cleanly without showing stale slide',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final bank = _ControlledArtworkBank();

      await tester.pumpWidget(_wrapHome(harness, bank));
      await bank.complete(
        tester,
        'https://example.invalid/hero-a.jpg',
        Colors.indigo,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Next twice while both B and C are still loading -> pending target is C.
      await tester.tap(find.byKey(const ValueKey('home-spotlight-next')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('home-spotlight-next')));
      await tester.pump(const Duration(milliseconds: 50));

      // Stale B completing must NOT hijack the pending transition to C.
      await bank.complete(
        tester,
        'https://example.invalid/hero-b.jpg',
        Colors.teal,
      );
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero A',
      );

      // Completing C commits directly to C.
      await bank.complete(
        tester,
        'https://example.invalid/hero-c.jpg',
        Colors.amber,
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero C',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'falls back cleanly on artwork error or preload timeout and cancels pending auto-rotation on pause/dispose',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final bank = _ControlledArtworkBank();

      await tester.pumpWidget(
        _wrapHome(
          harness,
          bank,
          preloadTimeout: const Duration(milliseconds: 900),
        ),
      );
      await bank.complete(
        tester,
        'https://example.invalid/hero-a.jpg',
        Colors.indigo,
      );
      await tester.pump();

      // Failing cover B still allows switching to B without throwing or stalling.
      await tester.tap(find.byKey(const ValueKey('home-spotlight-next')));
      await tester.pump();
      bank.fail('https://example.invalid/hero-b.jpg');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero B',
      );
      expect(tester.takeException(), isNull);

      // Auto-rotation fires for stalled cover C, then user pauses before the
      // 900ms preloadTimeout: pausing cancels pending auto-rotation so Hero
      // stays on B even if C later finishes decoding.
      await tester.pump(const Duration(seconds: 12));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero B',
      );
      await tester.tap(find.byKey(const ValueKey('home-spotlight-auto-play')));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero B',
      );

      // Manual tap to stalled cover C must STILL wait for preloadTimeout (900ms)
      // because pausing auto-rotation cancelled C's preload rather than failing it.
      await tester.tap(find.byKey(const ValueKey('home-spotlight-next')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero B',
      );
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero C',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling a pending cover via rapid tap or warm supersede does not blacklist it from preloading later',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final bank = _ControlledArtworkBank();

      await tester.pumpWidget(_wrapHome(harness, bank));
      await bank.complete(
        tester,
        'https://example.invalid/hero-a.jpg',
        Colors.indigo,
      );
      // Warm C beforehand while leaving B uncached.
      await bank.complete(
        tester,
        'https://example.invalid/hero-c.jpg',
        Colors.amber,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Next (starts pending preload for B), then immediately tap Next
      // again (supersedes B with warm C, which switches synchronously).
      await tester.tap(find.byKey(const ValueKey('home-spotlight-next')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('home-spotlight-next')));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-spotlight-scene-switcher')),
          matching: find.text('Hero C'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-spotlight-scene-switcher')),
          matching: find.byType(MusicArtworkPlaceholder),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();

      // Now tap Previous to go from C back to B: B was cancelled, NOT failed,
      // so Home must still defer the switch until B finishes decoding instead
      // of flashing a placeholder immediately.
      await tester.tap(find.byKey(const ValueKey('home-spotlight-previous')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero C',
      );

      await bank.complete(
        tester,
        'https://example.invalid/hero-b.jpg',
        Colors.teal,
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-spotlight-scene-switcher')),
          matching: find.text('Hero B'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-spotlight-scene-switcher')),
          matching: find.byType(MusicArtworkPlaceholder),
        ),
        findsNothing,
      );

      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    're-warms evicted Hero covers when Home becomes active again after ImageCache eviction',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final bank = _ControlledArtworkBank();

      final providerBuilder = bank.providerFor;
      Widget buildHome({required bool active}) => MaterialApp(
        theme: MusicMaterialTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HomePage(
            homeController: harness.homeController,
            spotlightController: harness.spotlightController,
            recommendationController: harness.publicController,
            newSongController: harness.newSongController,
            radarController: harness.radarController,
            queuePlaybackController: harness.queueController,
            authenticated: false,
            active: active,
            onOpenDiscover: () {},
            onOpenLibrary: () {},
            onOpenRecommendation: (_) {},
            spotlightImageProviderBuilder: providerBuilder,
          ),
        ),
      );

      await tester.pumpWidget(buildHome(active: true));
      await bank.complete(
        tester,
        'https://example.invalid/hero-a.jpg',
        Colors.indigo,
      );
      await bank.complete(
        tester,
        'https://example.invalid/hero-b.jpg',
        Colors.teal,
      );
      await bank.complete(
        tester,
        'https://example.invalid/hero-c.jpg',
        Colors.amber,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Leave Home tab, evict ImageCache (simulating memory pressure / browsing
      // other screens), then return to Home with the same providerBuilder.
      await tester.pumpWidget(buildHome(active: false));
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      bank.reset();

      await tester.pumpWidget(buildHome(active: true));
      await tester.pump();

      expect(
        bank.requestedUris,
        containsAll(<String>[
          'https://example.invalid/hero-b.jpg',
          'https://example.invalid/hero-c.jpg',
        ]),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'delayed auto-rotation preload resynchronizes next auto-rotation interval from commit time',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final bank = _ControlledArtworkBank();

      await tester.pumpWidget(
        _wrapHome(
          harness,
          bank,
          rotationInterval: const Duration(seconds: 2),
          preloadTimeout: const Duration(milliseconds: 1500),
        ),
      );
      await bank.complete(
        tester,
        'https://example.invalid/hero-a.jpg',
        Colors.indigo,
      );
      await bank.complete(
        tester,
        'https://example.invalid/hero-c.jpg',
        Colors.amber,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // First auto-rotation fires at 2s, but B takes 800ms to decode.
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero A',
      );
      await tester.pump(const Duration(milliseconds: 800));
      await bank.complete(
        tester,
        'https://example.invalid/hero-b.jpg',
        Colors.teal,
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero B',
      );

      // 1.0s after B settled (~1.4s total since commit) must still stay on B,
      // proving the 2s interval restarted at commit rather than drifting.
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero B',
      );

      // Advancing past the remaining interval switches cleanly to warm C.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-spotlight-title')))
            .data,
        'Hero C',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _OfficialGateway implements OfficialPlaylistGateway {
  const _OfficialGateway(this.result);
  final OfficialPlaylistPageResult result;

  @override
  OfficialPlaylistPageLoadOperation beginLoad({
    required int page,
    required int size,
  }) => _OfficialOperation(result);
}

class _OfficialOperation implements OfficialPlaylistPageLoadOperation {
  const _OfficialOperation(this.result);
  final OfficialPlaylistPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<OfficialPlaylistPageResult> run() async => result;
}

class _PublicGateway implements RecommendedPlaylistGateway {
  const _PublicGateway(this.result);
  final RecommendedPlaylistPageResult result;

  @override
  RecommendedPlaylistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => _PublicOperation(result);
}

class _PublicOperation implements RecommendedPlaylistPageLoadOperation {
  const _PublicOperation(this.result);
  final RecommendedPlaylistPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<RecommendedPlaylistPageResult> run() async => result;
}

class _NewSongGateway implements NewSongGateway {
  const _NewSongGateway();

  @override
  NewSongLoadOperation beginLoad({required NewSongCategory category}) =>
      _NewSongOperation(category);
}

class _NewSongOperation implements NewSongLoadOperation {
  const _NewSongOperation(this.category);

  final NewSongCategory category;

  @override
  bool cancel() => true;

  @override
  Future<NewSongResult> run() async => NewSongResult(category: category);
}

class _RadarGateway implements RadarGateway {
  const _RadarGateway();

  @override
  RadarTrackPageLoadOperation beginLoad({required int page}) =>
      const _RadarOperation();
}

class _RadarOperation implements RadarTrackPageLoadOperation {
  const _RadarOperation();

  @override
  bool cancel() => true;

  @override
  Future<RadarTrackPageResult> run() async => const RadarTrackPageResult();
}

class _AccountGateway implements AccountSummaryGateway {
  const _AccountGateway();

  @override
  AccountSummaryLoadOperation beginLoad() => const _AccountOperation();
}

class _AccountOperation implements AccountSummaryLoadOperation {
  const _AccountOperation();

  @override
  bool cancel() => true;

  @override
  Future<AccountSummaryLoadResult> run() async =>
      const AccountSummaryLoadResult();
}

class _DailyGateway implements DailyRecommendationGateway {
  const _DailyGateway();

  @override
  DailyRecommendationLoadOperation beginLoad() => const _DailyOperation();
}

class _DailyOperation implements DailyRecommendationLoadOperation {
  const _DailyOperation();

  @override
  bool cancel() => true;

  @override
  Future<DailyRecommendationResult> run() async =>
      const DailyRecommendationResult();
}

class _PersonalizedPlaylistsGateway implements PersonalizedPlaylistsGateway {
  const _PersonalizedPlaylistsGateway();

  @override
  PersonalizedPlaylistsLoadOperation beginLoad() =>
      const _PersonalizedPlaylistsOperation();
}

class _PersonalizedPlaylistsOperation
    implements PersonalizedPlaylistsLoadOperation {
  const _PersonalizedPlaylistsOperation();

  @override
  bool cancel() => true;

  @override
  Future<PersonalizedPlaylistsResult> run() async =>
      const PersonalizedPlaylistsResult();
}

class _PersonalizedTracksGateway implements PersonalizedTracksGateway {
  const _PersonalizedTracksGateway();

  @override
  PersonalizedTracksLoadOperation beginLoad() =>
      const _PersonalizedTracksOperation();
}

class _PersonalizedTracksOperation implements PersonalizedTracksLoadOperation {
  const _PersonalizedTracksOperation();

  @override
  bool cancel() => true;

  @override
  Future<PersonalizedTracksResult> run() async =>
      const PersonalizedTracksResult();
}

class _RelatedTracksGateway implements RelatedTracksGateway {
  const _RelatedTracksGateway();

  @override
  RelatedTracksLoadOperation beginLoad(PlaylistTrackSummary seed) =>
      const _RelatedTracksOperation();
}

class _RelatedTracksOperation implements RelatedTracksLoadOperation {
  const _RelatedTracksOperation();

  @override
  bool cancel() => true;

  @override
  Future<RelatedTracksResult> run() async => const RelatedTracksResult();
}

class _RecentListeningGateway implements RecentListeningGateway {
  const _RecentListeningGateway();

  @override
  void observe(PlaylistTrackSummary? track, int positionMs, bool playing) {}

  @override
  PlaylistTrackSummary? choose() => null;

  @override
  void dispose() {}
}

class _StubAudioEngine implements ForegroundAudioEngine {
  const _StubAudioEngine();

  @override
  Future<void> dispose() async {}

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) => throw StateError('unused');
}

class _StubMediaGateway implements MediaResolutionGateway {
  const _StubMediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => const _StubMediaOp();
}

class _StubMediaOp implements MediaResolutionOperation {
  const _StubMediaOp();

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async =>
      const MediaResolutionResult(failure: MediaResolutionFailure.unavailable);
}

class _StubQueueGateway implements PlaybackQueueGateway {
  final PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot.empty();

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult advance() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult clear() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult completeCurrent() =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult extendAndAdvanceFromTerminal(
    List<PlaylistTrackSummary> tracks,
  ) => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult remove(int index) =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult rewind() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult select(int index) =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) =>
      PlaybackQueueResult(snapshot: _snapshot);
}
