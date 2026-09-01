import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_page.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

void main() {
  testWidgets(
    'uses artwork-derived Material colors in light and dark layouts',
    (tester) async {
      const captureReviewImages = bool.fromEnvironment(
        'NOW_PLAYING_VISUAL_REVIEW',
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final artwork = _artwork();
      final extractedLight = await tester.runAsync(
        () => ColorScheme.fromImageProvider(
          provider: artwork,
          brightness: Brightness.light,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ),
      );
      final extractedDark = await tester.runAsync(
        () => ColorScheme.fromImageProvider(
          provider: artwork,
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ),
      );
      expect(extractedLight, isNotNull);
      expect(extractedDark, isNotNull);
      final controller = _controller();

      Future<void> pumpPage({
        required Size size,
        required Brightness brightness,
      }) async {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: brightness == Brightness.light
                ? MusicMaterialTheme.light()
                : MusicMaterialTheme.dark(),
            home: ExpandedNowPlayingPage(
              controller: controller,
              onBack: () {},
              onSignInAgain: () {},
              artworkImageProviderBuilder: (_) => artwork,
              artworkColorSchemeLoader:
                  ({required provider, required brightness}) async =>
                      brightness == Brightness.light
                      ? extractedLight!
                      : extractedDark!,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpPage(size: const Size(1100, 800), brightness: Brightness.light);
      final lightColors = Theme.of(
        tester.element(
          find.byKey(const ValueKey('expanded-now-playing-artwork-backdrop')),
        ),
      ).colorScheme;
      expect(lightColors.brightness, Brightness.light);
      expect(
        lightColors.primary,
        isNot(MusicMaterialTheme.light().colorScheme.primary),
      );
      expect(
        find.byKey(const ValueKey('expanded-now-playing-wide-layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expanded-now-playing-lyrics-surface')),
        findsOneWidget,
      );
      expect(find.text('Take me hand'), findsWidgets);
      expect(find.text('I feel love is born again'), findsOneWidget);
      expect(find.text('爱再次诞生'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (captureReviewImages) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-now-playing-desktop-light.png'),
          ),
        );
      }

      await pumpPage(size: const Size(390, 844), brightness: Brightness.dark);
      final darkColors = Theme.of(
        tester.element(
          find.byKey(const ValueKey('expanded-now-playing-artwork-backdrop')),
        ),
      ).colorScheme;
      expect(darkColors.brightness, Brightness.dark);
      expect(
        darkColors.primary,
        isNot(MusicMaterialTheme.dark().colorScheme.primary),
      );
      expect(
        find.byKey(const ValueKey('expanded-now-playing-compact-layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('lyrics-translation-0')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      if (captureReviewImages) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-now-playing-mobile-dark.png'),
          ),
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('falls back to the app scheme when artwork colors fail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller();
    final baseTheme = MusicMaterialTheme.light();

    await tester.pumpWidget(
      MaterialApp(
        theme: baseTheme,
        home: ExpandedNowPlayingPage(
          controller: controller,
          onBack: () {},
          onSignInAgain: () {},
          artworkImageProviderBuilder: (_) => _artwork(),
          artworkColorSchemeLoader: ({
            required provider,
            required brightness,
          }) => Future.error(StateError('synthetic color extraction failure')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final colors = Theme.of(
      tester.element(
        find.byKey(const ValueKey('expanded-now-playing-artwork-backdrop')),
      ),
    ).colorScheme;
    expect(colors.primary, baseTheme.colorScheme.primary);
    expect(
      find.byKey(const ValueKey('expanded-now-playing-wide-layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('does not paint track content with a stale palette', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller();
    final palette = Completer<ColorScheme>();

    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.light(),
        home: ExpandedNowPlayingPage(
          controller: controller,
          onBack: () {},
          onSignInAgain: () {},
          artworkImageProviderBuilder: (_) => _artwork(),
          artworkColorSchemeLoader: ({
            required provider,
            required brightness,
          }) => palette.future,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('expanded-now-playing-palette-loading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('expanded-now-playing-wide-layout')),
      findsNothing,
    );

    palette.complete(
      ColorScheme.fromSeed(
        seedColor: const Color(0xff4f5f92),
        brightness: Brightness.light,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('expanded-now-playing-palette-loading')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('expanded-now-playing-palette-ready')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('expanded-now-playing-wide-layout')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

MemoryImage _artwork() => MemoryImage(base64Decode(_artworkPng));

const _artworkPng =
    'iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAMAAADXqc3KAAAALVBMVEX//v9/'
    'iaQ0Qm7W1egMGlWoo9I3NItbVaYaJGYnLXZGPZ5VRq+KdNlrUcx9YtstDn9v'
    'AAAAj0lEQVQoz4WR2w4DIQgF16JUUfr/n7u4FkVD0/PIZAiX6/qb8AK3DjHG'
    '5AEUEN9OoyxxJCilDHJIVCbJdoaAiJPEsBohoUVz8EpkSJ5Sq3VH4vR6qk82'
    'qfcCZv4SRWObxkpUymMX+DAvqRPUaZslgtZZEhuEwWwOS6LjWGmS8106g/Os'
    'R2rud0X68ffm17fc17gJI1iPuHoAAAAASUVORK5CYII=';

QueuePlaybackController _controller() {
  final lyrics = LyricController(const _LyricGateway());
  return QueuePlaybackController(
    _QueueGateway(),
    TrackPlaybackController(
      const _MediaGateway(),
      ForegroundPlaybackController(const _AudioEngine()),
    ),
    lyrics: lyrics,
  );
}

const _track = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:visual-review',
  title: 'Take me hand',
  artistNames: ['Cecile Corbel'],
  albumTitle: 'Take me hand',
  artworkUri: 'https://example.invalid/artwork.png',
  durationSeconds: 235,
);

class _QueueGateway implements PlaybackQueueGateway {
  final PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot(
    tracks: const [_track],
    currentIndex: 0,
    hasPrevious: false,
    hasNext: false,
  );

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult advance() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult clear() =>
      PlaybackQueueResult(snapshot: PlaybackQueueSnapshot.empty());

  @override
  PlaybackQueueResult completeCurrent() =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) =>
      PlaybackQueueResult(snapshot: _snapshot);

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

class _LyricGateway implements LyricGateway {
  const _LyricGateway();

  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) => const _LyricOperation();
}

class _LyricOperation implements LyricLoadOperation {
  const _LyricOperation();

  @override
  bool cancel() => true;

  @override
  Future<LyricLoadResult> run() async => LyricLoadResult(
    lyrics: SynchronizedLyrics([
      for (var index = 0; index < 8; index += 1)
        SynchronizedLyricLine(
          text: const [
            'I feel love is born again',
            'Fireflies',
            'In the moonlight',
            'Rising stars',
            'Remember',
            'In my dreams',
            'I feel your light',
            'Take me hand',
          ][index],
          startMs: index * 4000,
          durationMs: 4000,
          translation: index == 0 ? '爱再次诞生' : '完整翻译第 ${index + 1} 行',
          segments: const [],
        ),
    ]),
  );
}

class _MediaGateway implements MediaResolutionGateway {
  const _MediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => const _MediaOperation();
}

class _MediaOperation implements MediaResolutionOperation {
  const _MediaOperation();

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async =>
      const MediaResolutionResult(failure: MediaResolutionFailure.unavailable);
}

class _AudioEngine implements ForegroundAudioEngine {
  const _AudioEngine();

  @override
  Future<ForegroundAudioSession> loadRemote(Uri source) =>
      throw StateError('not used by this presentation test');
}
