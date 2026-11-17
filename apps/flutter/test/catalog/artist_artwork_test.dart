import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/artist_artwork.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';

void main() {
  testWidgets('binds an available Artist artwork URI to a network image', (
    tester,
  ) async {
    const uri = 'https://example.invalid/artist.jpg';
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 100,
            child: ArtistArtwork(uri: uri),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, uri);
    expect(image.fit, BoxFit.cover);
  });

  testWidgets('keeps a Material fallback when Artist artwork is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 100,
            child: ArtistArtwork(uri: null),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'musicArtworkFrameBuilder shows placeholder until frame arrives and reveals without placeholder opacity layer',
    (tester) async {
      final builder = musicArtworkFrameBuilder(
        const SizedBox(key: ValueKey('artwork-placeholder')),
      );

      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            key: const ValueKey('test-frame-host'),
            builder: (context) {
              capturedContext = context;
              return builder(
                context,
                const SizedBox(key: ValueKey('artwork-decoded')),
                null,
                false,
              );
            },
          ),
        ),
      );

      expect(find.byKey(const ValueKey('artwork-placeholder')), findsOneWidget);
      expect(find.byKey(const ValueKey('artwork-decoded')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('test-frame-host')),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            key: const ValueKey('test-frame-host'),
            builder: (context) => builder(
              capturedContext,
              const SizedBox(key: ValueKey('artwork-decoded')),
              0,
              false,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.byKey(const ValueKey('artwork-decoded')), findsOneWidget);
      expect(find.byKey(const ValueKey('artwork-placeholder')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('test-frame-host')),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('artwork-placeholder')), findsNothing);
      expect(find.byKey(const ValueKey('artwork-decoded')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('test-frame-host')),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'musicArtworkFrameBuilder skips animation when first mounted with an already-decoded frame and recycles cleanly mid-flight',
    (tester) async {
      final builder = musicArtworkFrameBuilder(
        const SizedBox(key: ValueKey('artwork-placeholder')),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            key: const ValueKey('test-frame-host'),
            builder: (context) => builder(
              context,
              const SizedBox(key: ValueKey('artwork-decoded')),
              0,
              false,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('artwork-decoded')), findsOneWidget);
      expect(find.byKey(const ValueKey('artwork-placeholder')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('test-frame-host')),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );

      // Recycle to pending frame, then to async frame, then to warm-cache sync hit mid-flight.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            key: const ValueKey('test-frame-host'),
            builder: (context) => builder(
              context,
              const SizedBox(key: ValueKey('artwork-decoded')),
              null,
              false,
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('artwork-placeholder')), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            key: const ValueKey('test-frame-host'),
            builder: (context) => builder(
              context,
              const SizedBox(key: ValueKey('artwork-decoded')),
              0,
              false,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.byKey(const ValueKey('artwork-placeholder')), findsOneWidget);

      // Warm-cache hit while previous reveal is mid-flight snaps immediately.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            key: const ValueKey('test-frame-host'),
            builder: (context) => builder(
              context,
              const SizedBox(key: ValueKey('artwork-decoded-sync')),
              0,
              true,
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('artwork-placeholder')), findsNothing);
      expect(
        find.byKey(const ValueKey('artwork-decoded-sync')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('test-frame-host')),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'MusicStageTransition animates loading-to-content reveal and snaps immediately for loading or non-loading swaps',
    (tester) async {
      Widget buildStage(Widget child) {
        return MaterialApp(
          home: Scaffold(body: MusicStageTransition(child: child)),
        );
      }

      await tester.pumpWidget(
        buildStage(const SizedBox(key: ValueKey('stage-loading'))),
      );
      expect(find.byKey(const ValueKey('stage-loading')), findsOneWidget);

      await tester.pumpWidget(
        buildStage(const SizedBox(key: ValueKey('stage-content'))),
      );
      await tester.pump(const Duration(milliseconds: 40));

      // Outgoing child is unmounted immediately so rapid cycling never collides keys.
      expect(find.byKey(const ValueKey('stage-loading')), findsNothing);
      expect(find.byKey(const ValueKey('stage-content')), findsOneWidget);

      final opacityFinder = find.descendant(
        of: find.byType(MusicStageTransition),
        matching: find.byType(Opacity),
      );
      final midOpacity = tester.widget<Opacity>(opacityFinder);
      expect(midOpacity.opacity, greaterThan(0.58));
      expect(midOpacity.opacity, lessThan(1.0));

      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(opacityFinder).opacity, 1.0);
      expect(find.byKey(const ValueKey('stage-content')), findsOneWidget);

      // Switching between two non-loading stages (e.g., local filter or clear to idle) snaps on frame 1.
      await tester.pumpWidget(
        buildStage(const SizedBox(key: ValueKey('stage-idle'))),
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.widget<Opacity>(opacityFinder).opacity, 1.0);

      // Re-entering loading stage snaps to full opacity on the very first frame.
      await tester.pumpWidget(
        buildStage(const SizedBox(key: ValueKey('stage-loading'))),
      );
      await tester.pump();
      expect(tester.widget<Opacity>(opacityFinder).opacity, 1.0);
    },
  );
}
