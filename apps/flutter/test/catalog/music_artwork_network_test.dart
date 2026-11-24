import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';

void main() {
  group('musicArtworkRequestHeaders', () {
    test('adds browser headers only for NetEase HTTPS artwork hosts', () {
      for (final uri in <String>[
        'https://music.126.net/image.jpg',
        'https://p1.music.126.net/image.jpg',
        'https://p2.music.126.net/image.jpg?param=320y320',
      ]) {
        expect(musicArtworkRequestHeaders(uri), <String, String>{
          'Referer': 'https://music.163.com/',
        }, reason: uri);
      }
    });

    test('does not alter other providers or untrusted URL variants', () {
      for (final uri in <String>[
        'https://y.gtimg.cn/music/photo_new/T002R300x300M000.jpg',
        'https://evil-music.126.net/image.jpg',
        'https://music.126.net.example.com/image.jpg',
        'http://p1.music.126.net/image.jpg',
        'https://user@p1.music.126.net/image.jpg',
        'not a url',
      ]) {
        expect(musicArtworkRequestHeaders(uri), isNull, reason: uri);
      }
    });

    test('network provider carries the same scoped headers', () {
      final netease = musicArtworkImageProvider(
        'https://p2.music.126.net/image.jpg',
      );
      final qq = musicArtworkImageProvider(
        'https://y.gtimg.cn/music/photo_new/image.jpg',
      );

      expect(netease, isA<NetworkImage>());
      expect(
        (netease as NetworkImage).headers,
        containsPair('Referer', 'https://music.163.com/'),
      );
      expect(netease.headers, isNot(contains('User-Agent')));
      expect(qq, isA<NetworkImage>());
      expect((qq as NetworkImage).headers, isNull);
    });

    test('installs one NetEase-compatible HttpClient user agent', () {
      final previous = HttpOverrides.current;
      addTearDown(() => HttpOverrides.global = previous);

      installMusicNetworkHttpPolicy();
      final overrides = HttpOverrides.current;
      expect(overrides, isNotNull);
      final client = overrides!.createHttpClient(null);
      addTearDown(client.close);

      expect(client.userAgent, 'Mozilla/5.0');
    });

    test('failure diagnostic exposes transport shape but not URL identity', () {
      const artwork =
          'https://p2.music.126.net/private-track-id.jpg?param=320y320';
      final diagnostic = musicArtworkFailureDiagnostic(
        artwork,
        NetworkImageLoadException(statusCode: 403, uri: Uri.parse(artwork)),
      );

      expect(diagnostic, contains('host=p2.music.126.net'));
      expect(diagnostic, contains('scheme=https'));
      expect(diagnostic, contains('status=403'));
      expect(diagnostic, contains('error=NetworkImageLoadException'));
      expect(diagnostic, isNot(contains('private-track-id')));
      expect(diagnostic, isNot(contains('320y320')));
    });

    testWidgets('error builder preserves the supplied artwork fallback', (
      tester,
    ) async {
      const fallback = SizedBox(key: ValueKey('fallback'));
      const host = Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(key: ValueKey('host')),
      );
      await tester.pumpWidget(host);
      final builder = musicArtworkErrorBuilder(
        'https://p2.music.126.net/art.jpg',
        fallback,
      );

      expect(
        builder(
          tester.element(find.byKey(const ValueKey('host'))),
          StateError('decode'),
          null,
        ),
        same(fallback),
      );
    });

    testWidgets(
      'frame builder expands ImageCache limits and skips fade when TickerMode resumes',
      (tester) async {
        const placeholder = SizedBox(key: ValueKey('placeholder'));
        const artwork = SizedBox(key: ValueKey('artwork'));
        final builder = musicArtworkFrameBuilder(placeholder);
        final cache = PaintingBinding.instance.imageCache;
        expect(cache.maximumSize, greaterThanOrEqualTo(2500));
        expect(cache.maximumSizeBytes, greaterThanOrEqualTo(256 << 20));

        var tickerEnabled = false;
        int? frame;
        late StateSetter update;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return TickerMode(
                  enabled: tickerEnabled,
                  child: Builder(
                    builder: (context) =>
                        builder(context, artwork, frame, false),
                  ),
                );
              },
            ),
          ),
        );
        expect(find.byKey(const ValueKey('placeholder')), findsOneWidget);

        update(() {
          tickerEnabled = true;
          frame = 0;
        });
        await tester.pump();
        expect(find.byKey(const ValueKey('artwork')), findsOneWidget);
        expect(find.byKey(const ValueKey('placeholder')), findsNothing);
      },
    );

    testWidgets(
      'preservePreviousFrame holds decoded frame A across pending uncached B -> decoded B without placeholder flash or fade replay',
      (tester) async {
        addTearDown(PaintingBinding.instance.imageCache.clear);
        addTearDown(PaintingBinding.instance.imageCache.clearLiveImages);

        final imageA = await tester.runAsync(
          () => _solidImage(const Color(0xFF225588)),
        );
        final imageB = await tester.runAsync(
          () => _solidImage(const Color(0xFFAA4422)),
        );
        expect(imageA, isNotNull);
        expect(imageB, isNotNull);

        for (final excludeFromSemantics in <bool>[true, false]) {
          for (final disableAnimations in <bool>[false, true]) {
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
            final completerA = Completer<ui.Image>();
            final completerB = Completer<ui.Image>();
            final completerC = Completer<ui.Image>();
            ImageProvider<Object> currentProvider = _ControlledImageProvider(
              'a-$excludeFromSemantics-$disableAnimations',
              completerA,
            );
            late StateSetter update;

            await tester.pumpWidget(
              MediaQuery(
                data: MediaQueryData(disableAnimations: disableAnimations),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return Image(
                        image: currentProvider,
                        excludeFromSemantics: excludeFromSemantics,
                        gaplessPlayback: true,
                        frameBuilder: musicArtworkFrameBuilder(
                          const SizedBox(key: ValueKey('artwork-placeholder')),
                          preservePreviousFrame: true,
                        ),
                        errorBuilder: (_, _, _) => const SizedBox(
                          key: ValueKey('artwork-error-fallback'),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );

            // Cold initial mount shows placeholder until A decodes.
            expect(
              find.byKey(const ValueKey('artwork-placeholder')),
              findsOneWidget,
            );
            expect(find.byType(RawImage), findsNothing);

            // Completing A reveals cleanly (with fade when animations enabled).
            completerA.complete(imageA!.clone());
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 40));
            if (!disableAnimations) {
              expect(find.byType(FadeTransition), findsOneWidget);
            } else {
              expect(find.byType(FadeTransition), findsNothing);
            }
            await tester.pumpAndSettle();

            expect(
              find.byKey(const ValueKey('artwork-placeholder')),
              findsNothing,
            );
            final decodedA = tester.widget<RawImage>(find.byType(RawImage));
            expect(decodedA.image, isNotNull);

            // Switching to pending uncached B keeps decoded A visible without
            // placeholder flash or fade replay.
            update(() {
              currentProvider = _ControlledImageProvider(
                'b-$excludeFromSemantics-$disableAnimations',
                completerB,
              );
            });
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 40));

            expect(
              find.byKey(const ValueKey('artwork-placeholder')),
              findsNothing,
            );
            expect(find.byType(FadeTransition), findsNothing);
            final heldA = tester.widget<RawImage>(find.byType(RawImage));
            expect(heldA.image, same(decodedA.image));

            // Completing B swaps directly to B without replaying the reveal fade.
            completerB.complete(imageB!.clone());
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 40));

            expect(
              find.byKey(const ValueKey('artwork-placeholder')),
              findsNothing,
            );
            expect(find.byType(FadeTransition), findsNothing);
            final decodedB = tester.widget<RawImage>(find.byType(RawImage));
            expect(decodedB.image, isNotNull);
            expect(decodedB.image, isNot(same(decodedA.image)));

            // If a subsequent image C fails, errorBuilder still takes over cleanly.
            update(() {
              currentProvider = _ControlledImageProvider(
                'c-$excludeFromSemantics-$disableAnimations',
                completerC,
              );
            });
            await tester.pump();
            expect(
              find.byKey(const ValueKey('artwork-error-fallback')),
              findsNothing,
            );
            completerC.completeError(StateError('decode failed'));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('artwork-error-fallback')),
              findsOneWidget,
            );
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }

        imageA!.dispose();
        imageB!.dispose();
      },
    );

    testWidgets(
      'default frameBuilder with gaplessPlayback: false drops previous frame on pending item switch',
      (tester) async {
        addTearDown(PaintingBinding.instance.imageCache.clear);
        addTearDown(PaintingBinding.instance.imageCache.clearLiveImages);

        final imageA = await tester.runAsync(
          () => _solidImage(const Color(0xFF225588)),
        );
        expect(imageA, isNotNull);

        final completerA = Completer<ui.Image>();
        final completerB = Completer<ui.Image>();
        ImageProvider<Object> currentProvider = _ControlledImageProvider(
          'list-a',
          completerA,
        );
        late StateSetter update;

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Image(
                  image: currentProvider,
                  gaplessPlayback: false,
                  frameBuilder: musicArtworkFrameBuilder(
                    const SizedBox(key: ValueKey('list-placeholder')),
                  ),
                );
              },
            ),
          ),
        );

        completerA.complete(imageA!.clone());
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('list-placeholder')), findsNothing);
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);

        update(() {
          currentProvider = _ControlledImageProvider('list-b', completerB);
        });
        await tester.pump();
        expect(find.byKey(const ValueKey('list-placeholder')), findsOneWidget);
        expect(find.byType(RawImage), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        imageA.dispose();
      },
    );

    testWidgets(
      'preservePreviousFrame finishes an in-progress reveal smoothly across mid-fade switches without restarting or flashing',
      (tester) async {
        addTearDown(PaintingBinding.instance.imageCache.clear);
        addTearDown(PaintingBinding.instance.imageCache.clearLiveImages);

        final imageA = await tester.runAsync(
          () => _solidImage(const Color(0xFF225588)),
        );
        final imageB = await tester.runAsync(
          () => _solidImage(const Color(0xFFAA4422)),
        );
        final imageC = await tester.runAsync(
          () => _solidImage(const Color(0xFF338844)),
        );
        expect(imageA, isNotNull);
        expect(imageB, isNotNull);
        expect(imageC, isNotNull);

        final completerA = Completer<ui.Image>();
        final completerB = Completer<ui.Image>();
        final providerA = _ControlledImageProvider('mid-a', completerA);
        final providerB = _ControlledImageProvider('mid-b', completerB);
        final providerC = _SynchronousImageProvider('mid-c', imageC!);
        ImageProvider<Object> currentProvider = providerA;
        late StateSetter update;

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Image(
                  image: currentProvider,
                  gaplessPlayback: true,
                  frameBuilder: musicArtworkFrameBuilder(
                    const SizedBox(key: ValueKey('mid-placeholder')),
                    preservePreviousFrame: true,
                  ),
                );
              },
            ),
          ),
        );

        // Cold mount -> A decodes -> fade starts -> advance into mid-fade.
        completerA.complete(imageA!.clone());
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final fadeAt50 = tester.widget<FadeTransition>(
          find.byType(FadeTransition),
        );
        final opacityBeforeSwitch = fadeAt50.opacity.value;
        expect(opacityBeforeSwitch, greaterThan(0.35));
        expect(opacityBeforeSwitch, lessThan(1.0));
        final rawA = tester.widget<RawImage>(find.byType(RawImage));

        // Switch mid-fade to pending uncached B: holds A and keeps advancing
        // the existing fade without restarting from 0.35.
        update(() => currentProvider = providerB);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final fadePendingB = tester.widget<FadeTransition>(
          find.byType(FadeTransition),
        );
        expect(fadePendingB.opacity.value, greaterThan(opacityBeforeSwitch));
        expect(
          tester.widget<RawImage>(find.byType(RawImage)).image,
          same(rawA.image),
        );

        // B decodes while still mid-fade: swaps to B without restarting fade.
        final opacityBeforeB = fadePendingB.opacity.value;
        completerB.complete(imageB!.clone());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final rawB = tester.widget<RawImage>(find.byType(RawImage));
        expect(rawB.image, isNot(same(rawA.image)));
        if (find.byType(FadeTransition).evaluate().isNotEmpty) {
          final fadeAfterB = tester.widget<FadeTransition>(
            find.byType(FadeTransition),
          );
          expect(
            fadeAfterB.opacity.value,
            greaterThanOrEqualTo(opacityBeforeB),
          );
        }

        // Remaining fade completes cleanly with no FadeTransition left.
        await tester.pumpAndSettle();
        expect(find.byType(FadeTransition), findsNothing);
        expect(find.byKey(const ValueKey('mid-placeholder')), findsNothing);

        // Switching to a synchronously cached image while mid-reveal stops the
        // reveal immediately.
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        final completerD = Completer<ui.Image>();
        await tester.pumpWidget(const SizedBox.shrink());
        currentProvider = _ControlledImageProvider('mid-d', completerD);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Image(
                  image: currentProvider,
                  gaplessPlayback: true,
                  frameBuilder: musicArtworkFrameBuilder(
                    const SizedBox(key: ValueKey('mid-placeholder')),
                    preservePreviousFrame: true,
                  ),
                );
              },
            ),
          ),
        );
        completerD.complete(imageA.clone());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(find.byType(FadeTransition), findsOneWidget);

        update(() => currentProvider = providerC);
        await tester.pump();
        expect(find.byType(FadeTransition), findsNothing);
        expect(find.byKey(const ValueKey('mid-placeholder')), findsNothing);
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);

        await tester.pumpWidget(const SizedBox.shrink());
        imageA.dispose();
        imageB.dispose();
        imageC.dispose();
      },
    );
  });
}

Future<ui.Image> _solidImage(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  picture.dispose();
  return image;
}

class _ControlledImageProvider extends ImageProvider<_ControlledImageProvider> {
  const _ControlledImageProvider(this.id, this.completer);

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

class _SynchronousImageProvider
    extends ImageProvider<_SynchronousImageProvider> {
  const _SynchronousImageProvider(this.id, this.image);

  final String id;
  final ui.Image image;

  @override
  Future<_SynchronousImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<_SynchronousImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _SynchronousImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
  );

  @override
  bool operator ==(Object other) =>
      other is _SynchronousImageProvider && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
