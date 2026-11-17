import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  test('artwork palette cache reuses and bounds resolved schemes', () async {
    var loads = 0;
    final cache = ArtworkColorSchemeCache(
      maximumEntries: 1,
      artworkImageProviderBuilder: (_) => _artwork(),
      artworkColorSchemeLoader:
          ({required provider, required brightness}) async {
            loads += 1;
            return ColorScheme.fromSeed(
              seedColor: brightness == Brightness.light
                  ? const Color(0xff4f5f92)
                  : const Color(0xff84546d),
              brightness: brightness,
            );
          },
    );

    final light = await cache.resolve(
      artworkUri: 'artwork:one',
      brightness: Brightness.light,
    );
    final lightAgain = await cache.resolve(
      artworkUri: 'artwork:one',
      brightness: Brightness.light,
    );
    expect(lightAgain, same(light));
    expect(loads, 1);

    await cache.resolve(artworkUri: 'artwork:one', brightness: Brightness.dark);
    expect(loads, 2);
    expect(
      cache.lookup(artworkUri: 'artwork:one', brightness: Brightness.light),
      isNull,
    );
  });

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
      final topBar = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('expanded-now-playing-top-bar-backdrop')),
      );
      final topBarGradient = (topBar.decoration as BoxDecoration).gradient!;
      expect(topBarGradient.colors.toSet(), hasLength(greaterThan(1)));
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

      await tester.tap(find.byTooltip('Show queue'));
      await tester.pumpAndSettle();
      final queueSheet = find.byKey(
        const ValueKey('playback-queue-wide-side-sheet'),
      );
      expect(queueSheet, findsOneWidget);
      expect(tester.getRect(queueSheet).right, 1088);
      expect(
        Theme.of(tester.element(queueSheet)).colorScheme.primary,
        lightColors.primary,
      );
      expect(find.byType(Dialog), findsNothing);
      if (captureReviewImages) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            Uri.file('/tmp/flutterustmusic-now-playing-queue-sheet.png'),
          ),
        );
      }
      await tester.tap(find.byTooltip('Close queue'));
      await tester.pumpAndSettle();

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

  testWidgets('wide hero scales into a short window without nested scrolling', (
    tester,
  ) async {
    const captureReviewImages = bool.fromEnvironment(
      'NOW_PLAYING_VISUAL_REVIEW',
    );
    tester.view.physicalSize = const Size(1100, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: MusicMaterialTheme.light(),
        home: ExpandedNowPlayingPage(
          controller: controller,
          onBack: () {},
          onSignInAgain: () {},
          artworkImageProviderBuilder: (_) => _artwork(),
          artworkColorSchemeLoader:
              ({required provider, required brightness}) async =>
                  ColorScheme.fromSeed(
                    seedColor: const Color(0xff7b5b30),
                    brightness: brightness,
                  ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final hero = find.byKey(
      const ValueKey('expanded-now-playing-adaptive-hero'),
    );
    expect(hero, findsOneWidget);
    expect(
      find.descendant(of: hero, matching: find.byType(Scrollable)),
      findsNothing,
    );
    final wideLayoutRect = tester.getRect(
      find.byKey(const ValueKey('expanded-now-playing-wide-layout')),
    );
    final commentsRect = tester.getRect(
      find.byKey(const ValueKey('expanded-now-playing-comments')),
    );
    expect(wideLayoutRect.contains(commentsRect.bottomCenter), isTrue);
    expect(tester.takeException(), isNull);

    if (captureReviewImages) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-now-playing-desktop-short.png'),
        ),
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

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

  testWidgets('keeps content visible while artwork colors resolve', (
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
      find.byKey(const ValueKey('expanded-now-playing-wide-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('expanded-now-playing-palette-ready')),
      findsOneWidget,
    );
    expect(
      Theme.of(
        tester.element(
          find.byKey(const ValueKey('expanded-now-playing-artwork-backdrop')),
        ),
      ).colorScheme.primary,
      MusicMaterialTheme.light().colorScheme.primary,
    );

    final resolved = ColorScheme.fromSeed(
      seedColor: const Color(0xff4f5f92),
      brightness: Brightness.light,
    );
    palette.complete(resolved);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('expanded-now-playing-palette-ready')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('expanded-now-playing-wide-layout')),
      findsOneWidget,
    );
    expect(
      Theme.of(
        tester.element(
          find.byKey(const ValueKey('expanded-now-playing-artwork-backdrop')),
        ),
      ).colorScheme.primary,
      resolved.primary,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('reuses a resolved palette after the page is reopened', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loads = 0;
    final cache = ArtworkColorSchemeCache(
      artworkImageProviderBuilder: (_) => _artwork(),
      artworkColorSchemeLoader:
          ({required provider, required brightness}) async {
            loads += 1;
            return ColorScheme.fromSeed(
              seedColor: const Color(0xff4f5f92),
              brightness: brightness,
            );
          },
    );

    Future<QueuePlaybackController> pumpPage() async {
      final controller = _controller();
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicMaterialTheme.light(),
          home: ExpandedNowPlayingPage(
            controller: controller,
            onBack: () {},
            onSignInAgain: () {},
            artworkImageProviderBuilder: (_) => _artwork(),
            artworkColorSchemeCache: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    final firstController = await pumpPage();
    expect(loads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    firstController.dispose();

    final secondController = await pumpPage();
    expect(loads, 1);
    expect(
      find.byKey(const ValueKey('expanded-now-playing-wide-layout')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    secondController.dispose();
  });

  testWidgets(
    'normalizes extreme white and black artwork palettes while preserving multi-tone fidelity depth',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final extremeSeeds = <Color>[
        const Color(0xFF000000),
        const Color(0xFF050608),
        const Color(0xFFFFFFFF),
        const Color(0xFFFAFBFD),
      ];

      for (final brightness in Brightness.values) {
        final fallback = brightness == Brightness.light
            ? MusicMaterialTheme.light().colorScheme
            : MusicMaterialTheme.dark().colorScheme;
        for (final seed in <Color>[
          ...extremeSeeds,
          const Color(0xFF144256),
          const Color(0xFF282C32),
          const Color(0xFF5A5E66),
          const Color(0xFF2B6CB0),
          const Color(0xFFB83280),
          const Color(0xFFB8DCFF),
        ]) {
          final raw = ColorScheme.fromSeed(
            seedColor: seed,
            brightness: brightness,
            dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
          );
          final once = normalizeArtworkColorScheme(raw, fallback: fallback);
          final twice = normalizeArtworkColorScheme(once, fallback: fallback);
          expect(twice.primary, once.primary);
          expect(twice.primaryContainer, once.primaryContainer);
          expect(twice.secondaryContainer, once.secondaryContainer);
          expect(twice.tertiaryContainer, once.tertiaryContainer);
          expect(twice.surface, once.surface);
          expect(twice.surfaceContainerLowest, once.surfaceContainerLowest);
          expect(twice.surfaceContainerLow, once.surfaceContainerLow);
          expect(twice.surfaceContainer, once.surfaceContainer);
        }
        for (final seed in extremeSeeds) {
          final rawFidelity = ColorScheme.fromSeed(
            seedColor: seed,
            brightness: brightness,
            dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
          );
          final normalized = normalizeArtworkColorScheme(
            rawFidelity,
            fallback: fallback,
          );
          // Extreme achromatic covers must keep a subtle low-saturation smoky
          // palette rather than being dyed bright blue.
          expect(
            HSLColor.fromColor(normalized.primaryContainer).saturation,
            lessThan(0.24),
          );

          final controller = _controller();
          await tester.pumpWidget(
            MaterialApp(
              theme: brightness == Brightness.light
                  ? MusicMaterialTheme.light()
                  : MusicMaterialTheme.dark(),
              home: ExpandedNowPlayingPage(
                controller: controller,
                onBack: () {},
                onSignInAgain: () {},
                artworkImageProviderBuilder: (_) => _artwork(),
                artworkColorSchemeLoader: ({
                  required provider,
                  required brightness,
                }) async => rawFidelity,
              ),
            ),
          );
          await tester.pumpAndSettle();

          final backdrop = tester.widget<DecoratedBox>(
            find.byKey(const ValueKey('expanded-now-playing-artwork-backdrop')),
          );
          final gradient =
              (backdrop.decoration as BoxDecoration).gradient!
                  as LinearGradient;
          expect(gradient.colors, hasLength(3));
          expect(gradient.colors.toSet(), hasLength(3));

          final lyricsSurface = tester.widget<Material>(
            find.byKey(const ValueKey('expanded-now-playing-lyrics-surface')),
          );
          final surfaceColor = lyricsSurface.color!;
          if (brightness == Brightness.dark) {
            expect(gradient.colors.first.computeLuminance(), greaterThan(0.02));
            expect(
              gradient.colors.first.computeLuminance(),
              greaterThan(gradient.colors.last.computeLuminance()),
            );
            expect(surfaceColor.computeLuminance(), greaterThan(0.004));
          } else {
            expect(gradient.colors.first.computeLuminance(), greaterThan(0.55));
            expect(gradient.colors.last.computeLuminance(), greaterThan(0.85));
            expect(
              gradient.colors.last.computeLuminance(),
              greaterThan(gradient.colors.first.computeLuminance()),
            );
            expect(surfaceColor.computeLuminance(), greaterThan(0.65));
          }

          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      }

      // Dark chromatic covers (like Stray - Feint #051739) must preserve their
      // rich indigo saturation, avoid #000000 dead-black primary in light mode,
      // and avoid pitch-black primaryContainer in dark mode.
      final strayLight = normalizeArtworkColorScheme(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF051739),
          brightness: Brightness.light,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ),
      );
      expect(strayLight.primary, isNot(const Color(0xFF000000)));
      expect(
        HSLColor.fromColor(strayLight.primary).saturation,
        greaterThan(0.45),
      );
      expect(
        ArtworkAtmosphere.resolve(strayLight).primaryAmbient.computeLuminance(),
        greaterThan(0.40),
      );
      final strayDark = normalizeArtworkColorScheme(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF051739),
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ),
      );
      expect(
        HSLColor.fromColor(strayDark.primaryContainer).saturation,
        greaterThan(0.40),
      );
      expect(strayDark.primaryContainer.computeLuminance(), greaterThan(0.03));

      // Bright pastel chromatic covers (#B8DCFF) must keep their light fidelity
      // primaryContainer untouched in light mode.
      final rawPastelLight = ColorScheme.fromSeed(
        seedColor: const Color(0xFFB8DCFF),
        brightness: Brightness.light,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      );
      final pastelLight = normalizeArtworkColorScheme(rawPastelLight);
      expect(identical(pastelLight, rawPastelLight), isTrue);
    },
  );

  testWidgets(
    'dual-role perceptual extraction separates ambient canvas from focal accent across cover archetypes',
    (tester) async {
      // 1. 季候风 archetype: 95% B&W silver/charcoal film + 5% slate-blue ink.
      // Ambient canvas must stay low-saturation silver-grey while interactive
      // primary controls pick up the slate-blue calligraphy accent.
      final bwWithBlueInk = await tester.runAsync(
        () => _buildSyntheticCover(
          size: 40,
          pixelAt: (x, y) {
            if (x < 6 && y >= 4 && y < 34) {
              return const Color(0xFF3A7396); // ~5% slate-blue calligraphy
            }
            final v = 55 + ((x * 5 + y * 3) % 155);
            return Color.fromARGB(255, v, v, v);
          },
        ),
      );
      // 2. A Moment Apart archetype: 58% deep ocean blue + 34% dark umber +
      // 8% warm amber horizon. Both real colors must populate primaryAmbient
      // and secondaryAmbient.
      final oceanHorizon = await tester.runAsync(
        () => _buildSyntheticCover(
          size: 40,
          pixelAt: (x, y) {
            if (y < 22) return const Color(0xFF144860);
            if (y < 25) return const Color(0xFFD97D2B);
            return const Color(0xFF3B2A1E);
          },
        ),
      );
      // 3. Stray archetype: 68% abyssal black + 32% electric ice-blue smoke.
      final abyssalSmoke = await tester.runAsync(
        () => _buildSyntheticCover(
          size: 40,
          pixelAt: (x, y) => (x + y) % 3 == 0
              ? const Color(0xFF1E62CC)
              : const Color(0xFF04060A),
        ),
      );
      // 4. Extreme white cover + 8% dark text/ink (classic Score.score trap).
      final whiteWithBlackInk = await tester.runAsync(
        () => _buildSyntheticCover(
          size: 40,
          pixelAt: (x, y) => (y >= 18 && y <= 20)
              ? const Color(0xFF0D0F12)
              : const Color(0xFFFCFCFD),
        ),
      );
      // 5. Hong Kong archetype: 42% sunset yellow + 28% dark brown buildings +
      // 16% magenta-purple + 14% harbor teal. Must NOT mistake dark brown for a
      // 2nd color (repeating yellow/beige) and must NOT turn primary olive-brown.
      final sunsetHarbor = await tester.runAsync(
        () => _buildSyntheticCover(
          size: 40,
          pixelAt: (x, y) {
            if (y < 17) return const Color(0xFFE8CA5A);
            if (y < 28) {
              return x < 24 ? const Color(0xFF634118) : const Color(0xFF9E3B7C);
            }
            return const Color(0xFF1F7E7A);
          },
        ),
      );

      final covers = <String, MemoryImage>{
        'bw-ink': bwWithBlueInk!,
        'ocean-horizon': oceanHorizon!,
        'abyssal-smoke': abyssalSmoke!,
        'white-ink': whiteWithBlackInk!,
        'sunset-harbor': sunsetHarbor!,
      };
      final cache = ArtworkColorSchemeCache(
        artworkImageProviderBuilder: (uri) => covers[uri]!,
      );

      // Verify Archetype 1 (季候风): silver ambient + blue-accent controls
      final bwLight = await tester.runAsync(
        () => cache.resolve(artworkUri: 'bw-ink', brightness: Brightness.light),
      );
      expect(bwLight, isNotNull);
      final bwLightAtmos = ArtworkAtmosphere.resolve(bwLight!);
      expect(
        HSLColor.fromColor(bwLightAtmos.primaryAmbient).saturation,
        lessThan(0.18),
      );
      final bwPrimaryHsl = HSLColor.fromColor(bwLight.primary);
      expect(bwPrimaryHsl.saturation, greaterThan(0.28));
      expect(bwPrimaryHsl.hue, inInclusiveRange(175, 235));

      // Verify Archetype 2 (A Moment Apart): cool ocean primaryAmbient + warm
      // amber/earth secondaryAmbient
      final oceanDark = await tester.runAsync(
        () => cache.resolve(
          artworkUri: 'ocean-horizon',
          brightness: Brightness.dark,
        ),
      );
      expect(oceanDark, isNotNull);
      final oceanAtmos = ArtworkAtmosphere.resolve(oceanDark!);
      expect(
        HSLColor.fromColor(oceanAtmos.primaryAmbient).hue,
        inInclusiveRange(175, 235),
      );
      expect(
        HSLColor.fromColor(oceanAtmos.secondaryAmbient).hue,
        inInclusiveRange(12, 65),
      );

      // Verify Archetype 3 (Stray): luminous icy-blue mist in light mode (no
      // muddy black wash or #000000 play button) & lifted indigo in dark mode
      final smokeLight = await tester.runAsync(
        () => cache.resolve(
          artworkUri: 'abyssal-smoke',
          brightness: Brightness.light,
        ),
      );
      final smokeDark = await tester.runAsync(
        () => cache.resolve(
          artworkUri: 'abyssal-smoke',
          brightness: Brightness.dark,
        ),
      );
      expect(smokeLight!.primary, isNot(const Color(0xFF000000)));
      expect(
        ArtworkAtmosphere.resolve(smokeLight).primaryAmbient.computeLuminance(),
        greaterThan(0.40),
      );
      expect(
        ArtworkAtmosphere.resolve(smokeDark!).primaryAmbient.computeLuminance(),
        greaterThan(0.035),
      );

      // Verify Archetype 4 (Extreme white + black ink): never collapses into
      // pitch black ("一片黑") in dark mode or muddy grey in light mode
      final whiteDark = await tester.runAsync(
        () =>
            cache.resolve(artworkUri: 'white-ink', brightness: Brightness.dark),
      );
      final whiteLight = await tester.runAsync(
        () => cache.resolve(
          artworkUri: 'white-ink',
          brightness: Brightness.light,
        ),
      );
      expect(
        ArtworkAtmosphere.resolve(whiteDark!).primaryAmbient.computeLuminance(),
        greaterThan(0.035),
      );
      expect(
        ArtworkAtmosphere.resolve(whiteLight!).primaryAmbient
            .computeLuminance(),
        greaterThan(0.50),
      );

      // Verify Archetype 5 (Hong Kong): secondaryAmbient picks magenta or teal
      // (distinct hue from sunset yellow rather than dark brown), primary
      // avoids muddy olive-brown, and neutral surfaces stay clean.
      final hkLight = await tester.runAsync(
        () => cache.resolve(
          artworkUri: 'sunset-harbor',
          brightness: Brightness.light,
        ),
      );
      expect(hkLight, isNotNull);
      final hkAtmos = ArtworkAtmosphere.resolve(hkLight!);
      final hkPrimaryHue = HSLColor.fromColor(hkAtmos.primaryAmbient).hue;
      final hkSecondaryHue = HSLColor.fromColor(hkAtmos.secondaryAmbient).hue;
      final hueDelta = (hkPrimaryHue - hkSecondaryHue).abs();
      final wrappedHueDelta = hueDelta > 180 ? 360 - hueDelta : hueDelta;
      expect(wrappedHueDelta, greaterThan(40));
      expect(
        HSLColor.fromColor(hkLight.primary).hue,
        isNot(inInclusiveRange(38, 72)),
      );
      expect(
        HSLColor.fromColor(hkLight.surfaceContainerLowest).saturation,
        lessThan(0.15),
      );
    },
  );

  testWidgets(
    'sharing an active ImageProvider with default ArtworkColorSchemeCache keeps ImageCache intact',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(PaintingBinding.instance.imageCache.clear);
      addTearDown(PaintingBinding.instance.imageCache.clearLiveImages);

      final sharedArtwork = await tester.runAsync(
        () => _buildSyntheticCover(
          size: 96,
          pixelAt: (x, y) =>
              y < 56 ? const Color(0xFF1A5E8A) : const Color(0xFFD9822B),
        ),
      );
      expect(sharedArtwork, isNotNull);
      final cache = ArtworkColorSchemeCache(
        artworkImageProviderBuilder: (_) => sharedArtwork!,
      );
      final controller = _controller();
      final repaintKey = GlobalKey();

      // Simulate NowPlayingBar already rendering and caching the active track's
      // cover before ExpandedNowPlayingPage opens.
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicMaterialTheme.light(),
          home: Scaffold(
            body: Image(
              key: const ValueKey('outer-bar-shared-artwork'),
              image: sharedArtwork!,
              width: 56,
              height: 56,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          sharedArtwork,
          tester.element(
            find.byKey(const ValueKey('outer-bar-shared-artwork')),
          ),
        ),
      );
      await tester.pump();
      final outerRawBefore = tester.widget<RawImage>(
        find.descendant(
          of: find.byKey(const ValueKey('outer-bar-shared-artwork')),
          matching: find.byType(RawImage),
        ),
      );
      expect(outerRawBefore.image, isNotNull);
      expect(outerRawBefore.image!.debugDisposed, isFalse);

      // Open ExpandedNowPlayingPage sharing the exact same ImageProvider and
      // using the default dual-role color extraction loader.
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintKey,
          child: MaterialApp(
            theme: MusicMaterialTheme.light(),
            home: Stack(
              children: [
                Image(
                  key: const ValueKey('outer-bar-shared-artwork'),
                  image: sharedArtwork,
                  width: 56,
                  height: 56,
                ),
                ExpandedNowPlayingPage(
                  controller: controller,
                  onBack: () {},
                  onSignInAgain: () {},
                  artworkImageProviderBuilder: (_) => sharedArtwork,
                  artworkColorSchemeCache: cache,
                ),
              ],
            ),
          ),
        ),
      );
      final cachedScheme = await tester.runAsync(
        () => cache.resolve(
          artworkUri: _track.artworkUri!,
          brightness: Brightness.light,
        ),
      );
      expect(cachedScheme, isNotNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final rawImages = tester.widgetList<RawImage>(find.byType(RawImage));
      expect(rawImages.length, greaterThanOrEqualTo(2));
      for (final raw in rawImages) {
        expect(raw.image, isNotNull);
        expect(raw.image!.debugDisposed, isFalse);
      }

      // Force an actual engine raster pass over the shared ui.Image to prove
      // painting never hits a disposed cached image.
      await tester.runAsync(() async {
        final boundary =
            repaintKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final rendered = await boundary.toImage();
        rendered.dispose();
      });
      expect(tester.takeException(), isNull);

      final pageColors = Theme.of(
        tester.element(
          find.byKey(const ValueKey('expanded-now-playing-artwork-backdrop')),
        ),
      ).colorScheme;
      expect(
        pageColors.primary,
        isNot(MusicMaterialTheme.light().colorScheme.primary),
      );

      final handleProbe = rawImages.first.image!;
      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.pumpWidget(const SizedBox(width: 1));
      expect(handleProbe.debugGetOpenHandleStackTraces(), isEmpty);
      controller.dispose();
    },
  );

  testWidgets(
    'handles multi-frame animated artwork and rapid track switches without leaking or disposing shared frames',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(PaintingBinding.instance.imageCache.clear);
      addTearDown(PaintingBinding.instance.imageCache.clearLiveImages);

      final frames = await tester.runAsync(
        () => Future.wait([
          _buildRawImage(size: 32, color: const Color(0xFF1A5E8A)),
          _buildRawImage(size: 32, color: const Color(0xFFD9822B)),
        ]),
      );
      expect(frames, isNotNull);
      final frame1 = frames![0];
      final frame2 = frames[1];
      addTearDown(() {
        if (!frame1.debugDisposed) frame1.dispose();
        if (!frame2.debugDisposed) frame2.dispose();
      });
      final animatedCover = _TwoFrameAnimatedImageProvider(frame1, frame2);
      final secondCover = await tester.runAsync(
        () => _buildSyntheticCover(
          size: 48,
          pixelAt: (x, y) => const Color(0xFF9C27B0),
        ),
      );
      expect(secondCover, isNotNull);

      const firstTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:anim-1',
        title: 'Animated Cover Track',
        artistNames: ['Artist A'],
        artworkUri: 'https://example.invalid/anim-1.gif',
        durationSeconds: 180,
      );
      const secondTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:anim-2',
        title: 'Second Cover Track',
        artistNames: ['Artist B'],
        artworkUri: 'https://example.invalid/static-2.png',
        durationSeconds: 200,
      );

      final gateway = _MutableQueueGateway(const [firstTrack, secondTrack]);
      final controller = QueuePlaybackController(
        gateway,
        TrackPlaybackController(
          const _MediaGateway(),
          ForegroundPlaybackController(const _AudioEngine()),
        ),
        lyrics: LyricController(const _LyricGateway()),
      );
      addTearDown(controller.dispose);

      ImageProvider<Object> providerFor(String uri) =>
          uri.endsWith('.gif') ? animatedCover : secondCover!;
      final cache = ArtworkColorSchemeCache(
        artworkImageProviderBuilder: providerFor,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: MusicMaterialTheme.dark(),
          home: Stack(
            children: [
              Image(image: animatedCover, width: 48, height: 48),
              ExpandedNowPlayingPage(
                controller: controller,
                onBack: () {},
                onSignInAgain: () {},
                artworkImageProviderBuilder: providerFor,
                artworkColorSchemeCache: cache,
              ),
            ],
          ),
        ),
      );

      // Drive real engine toByteData() and FakeAsync frame/microtask pumping
      // across rapid track switches and animated frame transitions.
      await tester.pump(const Duration(milliseconds: 20));
      await controller.advance();
      await tester.pump(const Duration(milliseconds: 20));
      await controller.rewind();
      await tester.pump(const Duration(milliseconds: 20));
      await controller.advance();
      for (var step = 0; step < 6; step += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(
        cache.lookup(
          artworkUri: firstTrack.artworkUri!,
          brightness: Brightness.dark,
        ),
        isNotNull,
      );
      expect(
        cache.lookup(
          artworkUri: secondTrack.artworkUri!,
          brightness: Brightness.dark,
        ),
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      for (final raw in tester.widgetList<RawImage>(find.byType(RawImage))) {
        if (raw.image != null) {
          expect(raw.image!.debugDisposed, isFalse);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<MemoryImage> _buildSyntheticCover({
  required int size,
  required Color Function(int x, int y) pixelAt,
}) async {
  final rgba = Uint8List(size * size * 4);
  for (var y = 0; y < size; y += 1) {
    for (var x = 0; x < size; x += 1) {
      final c = pixelAt(x, y);
      final offset = (y * size + x) * 4;
      rgba[offset] = (c.r * 255.0).round().clamp(0, 255);
      rgba[offset + 1] = (c.g * 255.0).round().clamp(0, 255);
      rgba[offset + 2] = (c.b * 255.0).round().clamp(0, 255);
      rgba[offset + 3] = (c.a * 255.0).round().clamp(0, 255);
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    size,
    size,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  try {
    final pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return MemoryImage(pngBytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
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
  Future<void> dispose() async {}

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) => throw StateError('not used by this presentation test');
}

Future<ui.Image> _buildRawImage({
  required int size,
  required Color color,
}) async {
  final rgba = Uint8List(size * size * 4);
  final r = (color.r * 255.0).round().clamp(0, 255);
  final g = (color.g * 255.0).round().clamp(0, 255);
  final b = (color.b * 255.0).round().clamp(0, 255);
  final a = (color.a * 255.0).round().clamp(0, 255);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i] = r;
    rgba[i + 1] = g;
    rgba[i + 2] = b;
    rgba[i + 3] = a;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    size,
    size,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

class _TwoFrameAnimatedImageProvider
    extends ImageProvider<_TwoFrameAnimatedImageProvider> {
  const _TwoFrameAnimatedImageProvider(this.firstFrame, this.secondFrame);

  final ui.Image firstFrame;
  final ui.Image secondFrame;

  @override
  Future<_TwoFrameAnimatedImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<_TwoFrameAnimatedImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _TwoFrameAnimatedImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: SynchronousFuture<ui.Codec>(_TwoFrameCodec(firstFrame, secondFrame)),
    scale: 1,
  );
}

class _TwoFrameCodec implements ui.Codec {
  _TwoFrameCodec(this._first, this._second);

  final ui.Image _first;
  final ui.Image _second;
  int _cursor = 0;

  @override
  int get frameCount => 2;

  @override
  int get repetitionCount => -1;

  @override
  Future<ui.FrameInfo> getNextFrame() {
    final source = (_cursor++ % 2 == 0) ? _first : _second;
    return SynchronousFuture<ui.FrameInfo>(
      _SyntheticFrameInfo(
        image: source.clone(),
        duration: const Duration(milliseconds: 25),
      ),
    );
  }

  @override
  void dispose() {}
}

class _SyntheticFrameInfo implements ui.FrameInfo {
  const _SyntheticFrameInfo({required this.image, required this.duration});

  @override
  final ui.Image image;

  @override
  final Duration duration;
}

class _MutableQueueGateway extends _QueueGateway {
  _MutableQueueGateway(this._tracks);

  final List<PlaylistTrackSummary> _tracks;
  int _index = 0;

  PlaybackQueueSnapshot _current() => PlaybackQueueSnapshot(
    tracks: _tracks,
    currentIndex: _index,
    hasPrevious: _index > 0,
    hasNext: _index + 1 < _tracks.length,
  );

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _current());

  @override
  PlaybackQueueResult advance() {
    if (_index + 1 < _tracks.length) _index += 1;
    return PlaybackQueueResult(snapshot: _current());
  }

  @override
  PlaybackQueueResult rewind() {
    if (_index > 0) _index -= 1;
    return PlaybackQueueResult(snapshot: _current());
  }
}
