import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/catalog/music_artwork_placeholder.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

Future<ui.Image> _createTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFF446688),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  picture.dispose();
  return image;
}

class _ControlledImageProvider extends ImageProvider<_ControlledImageProvider> {
  _ControlledImageProvider(this.id, this.completer);

  final String id;
  final Completer<ui.Image> completer;

  @override
  Future<_ControlledImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<_ControlledImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _ControlledImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    completer.future.then((image) => ImageInfo(image: image)),
  );

  @override
  bool operator ==(Object other) =>
      other is _ControlledImageProvider && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

void main() {
  group('MusicArtworkPlaceholder', () {
    testWidgets(
      'renders cohesive modern rounded icons for every artwork kind in Material 3 and Editorial themes',
      (tester) async {
        final themes = <ThemeData>[
          MusicMaterialTheme.light(),
          MusicMaterialTheme.dark(),
          MusicMaterialTheme.light(visualStyle: AppVisualStyle.editorial),
          MusicMaterialTheme.dark(visualStyle: AppVisualStyle.editorial),
        ];

        for (final theme in themes) {
          for (final kind in MusicArtworkKind.values) {
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: Center(
                    child: SizedBox.square(
                      dimension: 120,
                      child: MusicArtworkPlaceholder(kind: kind),
                    ),
                  ),
                ),
              ),
            );
            expect(
              find.byIcon(MusicArtworkPlaceholder.iconForKind(kind)),
              findsOneWidget,
              reason: 'Missing icon for $kind',
            );
            expect(tester.takeException(), isNull);
          }
        }
      },
    );

    testWidgets(
      'scales cleanly across compact thumbnails, medium shelf cards, and large Hero covers',
      (tester) async {
        // Compact 44px thumbnail: clean direct icon, no medallion ring.
        await tester.pumpWidget(
          MaterialApp(
            theme: MusicMaterialTheme.light(),
            home: const Scaffold(
              body: Center(
                child: SizedBox.square(
                  dimension: 44,
                  child: MusicArtworkPlaceholder(kind: MusicArtworkKind.track),
                ),
              ),
            ),
          ),
        );
        final compactIcon = tester.widget<Icon>(
          find.byIcon(Icons.music_note_rounded),
        );
        expect(compactIcon.size, lessThanOrEqualTo(22));
        expect(
          find.descendant(
            of: find.byType(MusicArtworkPlaceholder),
            matching: find.byType(Container),
          ),
          findsNothing,
        );

        // Medium 140px shelf card: single medallion framing.
        await tester.pumpWidget(
          MaterialApp(
            theme: MusicMaterialTheme.light(
              visualStyle: AppVisualStyle.editorial,
            ),
            home: const Scaffold(
              body: Center(
                child: SizedBox.square(
                  dimension: 140,
                  child: MusicArtworkPlaceholder(
                    kind: MusicArtworkKind.playlist,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          find.descendant(
            of: find.byType(MusicArtworkPlaceholder),
            matching: find.byType(Container),
          ),
          findsOneWidget,
        );

        // Large 260px Hero spotlight: concentric outer ring + medallion shifted
        // above bottom headline area.
        await tester.pumpWidget(
          MaterialApp(
            theme: MusicMaterialTheme.dark(
              visualStyle: AppVisualStyle.editorial,
            ),
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 520,
                  height: 260,
                  child: MusicArtworkPlaceholder(
                    kind: MusicArtworkKind.spotlight,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          find.descendant(
            of: find.byType(MusicArtworkPlaceholder),
            matching: find.byType(Container),
          ),
          findsNWidgets(2),
        );
        final align = tester.widget<Align>(
          find
              .descendant(
                of: find.byType(MusicArtworkPlaceholder),
                matching: find.byType(Align),
              )
              .first,
        );
        expect(align.alignment, const Alignment(0, -0.18));
      },
    );

    testWidgets(
      'avatar placeholder renders uppercased initial in both themes',
      (tester) async {
        for (final style in AppVisualStyle.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: MusicMaterialTheme.light(visualStyle: style),
              home: const Scaffold(
                body: Center(
                  child: SizedBox.square(
                    dimension: 40,
                    child: MusicArtworkPlaceholder.avatar(initial: 'f'),
                  ),
                ),
              ),
            ),
          );
          expect(find.text('F'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'handles extreme and tier-boundary dimensions without clamp errors or overflow',
      (tester) async {
        for (final size in <double>[0, 12, 24, 75, 76, 77, 179, 180, 360]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: MusicMaterialTheme.light(),
              home: Scaffold(
                body: Center(
                  child: SizedBox.square(
                    dimension: size,
                    child: const MusicArtworkPlaceholder(
                      kind: MusicArtworkKind.album,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'Failed at dimension $size',
          );
        }
      },
    );
    testWidgets(
      'clamps oversized explicit iconSize and falls back gracefully on blank avatar labels or large text scale',
      (tester) async {
        // Compact 64px box with legacy oversized iconSize: 68 must clamp safely.
        await tester.pumpWidget(
          MaterialApp(
            theme: MusicMaterialTheme.light(),
            home: const Scaffold(
              body: Center(
                child: SizedBox.square(
                  dimension: 64,
                  child: MusicArtworkPlaceholder(
                    kind: MusicArtworkKind.artist,
                    iconSize: 68,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        );
        final compactIcon = tester.widget<Icon>(
          find.byIcon(Icons.person_rounded),
        );
        expect(compactIcon.size, lessThanOrEqualTo(28));
        expect(tester.takeException(), isNull);

        // Medium 156px box with oversized iconSize: 68 must stay comfortably
        // inside its medallion.
        await tester.pumpWidget(
          MaterialApp(
            theme: MusicMaterialTheme.light(),
            home: const Scaffold(
              body: Center(
                child: SizedBox.square(
                  dimension: 156,
                  child: MusicArtworkPlaceholder(
                    kind: MusicArtworkKind.artist,
                    iconSize: 68,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        );
        final mediumIcon = tester.widget<Icon>(
          find.byIcon(Icons.person_rounded),
        );
        expect(mediumIcon.size, lessThan(60));
        expect(tester.takeException(), isNull);

        // Blank avatar label falls back to person icon instead of empty text.
        await tester.pumpWidget(
          MaterialApp(
            theme: MusicMaterialTheme.light(),
            home: const Scaffold(
              body: Center(
                child: SizedBox.square(
                  dimension: 40,
                  child: MusicArtworkPlaceholder.avatar(initial: '   '),
                ),
              ),
            ),
          ),
        );
        expect(find.byIcon(Icons.person_rounded), findsOneWidget);
        expect(find.byType(Text), findsNothing);
        expect(tester.takeException(), isNull);

        // Large accessibility text scaling scales down cleanly inside 40px.
        await tester.pumpWidget(
          MaterialApp(
            theme: MusicMaterialTheme.light(),
            home: const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2.5)),
              child: Scaffold(
                body: Center(
                  child: SizedBox.square(
                    dimension: 40,
                    child: MusicArtworkPlaceholder.avatar(initial: 'W'),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('W'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('startMusicArtworkPreload', () {
    tearDown(() {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });

    testWidgets(
      'warms ImageCache asynchronously and hits synchronously on subsequent checks',
      (tester) async {
        final imageCompleter = Completer<ui.Image>();
        final provider = _ControlledImageProvider(
          'preload-warm-test',
          imageCompleter,
        );
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        );
        final config = createLocalImageConfiguration(
          tester.element(find.byType(SizedBox)),
        );

        final first = startMusicArtworkPreload(provider, config);
        expect(first.readySynchronously, isFalse);

        final image = await tester.runAsync(_createTestImage);
        imageCompleter.complete(image!);
        expect(await first.future, MusicArtworkPreloadOutcome.loaded);
        await tester.pump();

        final second = startMusicArtworkPreload(provider, config);
        expect(second.readySynchronously, isTrue);
        expect(await second.future, MusicArtworkPreloadOutcome.loaded);
        await tester.pump();
      },
    );

    testWidgets(
      'distinguishes failed loads from explicit cancellation without throwing',
      (tester) async {
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        );
        final config = createLocalImageConfiguration(
          tester.element(find.byType(SizedBox)),
        );

        final failingCompleter = Completer<ui.Image>();
        final failingProvider = _ControlledImageProvider(
          'preload-fail-test',
          failingCompleter,
        );
        final failing = startMusicArtworkPreload(failingProvider, config);
        failingCompleter.completeError(StateError('network error'));
        expect(await failing.future, MusicArtworkPreloadOutcome.failed);
        expect(tester.takeException(), isNull);

        final pendingCompleter = Completer<ui.Image>();
        final pendingProvider = _ControlledImageProvider(
          'preload-cancel-test',
          pendingCompleter,
        );
        final cancelled = startMusicArtworkPreload(pendingProvider, config);
        cancelled.cancel();
        expect(await cancelled.future, MusicArtworkPreloadOutcome.cancelled);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
