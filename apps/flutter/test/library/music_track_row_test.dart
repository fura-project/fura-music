import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

void main() {
  const track = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:row-interaction',
    title: 'Interactive Track',
    artistNames: ['First Artist'],
    artists: [
      ArtistSummary(
        providerId: 'qq-music',
        opaqueId: 'artist:first',
        name: 'First Artist',
      ),
    ],
    albumTitle: 'Interactive Album',
    album: AlbumSummary(
      providerId: 'qq-music',
      opaqueId: 'album:interactive',
      title: 'Interactive Album',
    ),
    durationSeconds: 201,
  );

  testWidgets('desktop row gives play, Artist and Album independent targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var rowPlays = 0;
    var playButtonCalls = 0;
    var artistCalls = 0;
    var albumCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 960,
              child: MusicTrackRowSurface(
                itemKey: const ValueKey('row'),
                desktop: true,
                current: false,
                semanticLabel: 'Interactive Track, First Artist',
                onTap: () => rowPlays++,
                contentBuilder: (context, active, hovered) =>
                    MusicTrackRowContent(
                      index: 1,
                      track: track,
                      desktop: true,
                      current: false,
                      active: active,
                      artistNames: 'First Artist',
                      onPlay: () => playButtonCalls++,
                      onAddToQueue: () {},
                      onMore: () {},
                      onOpenArtist: () => artistCalls++,
                      onOpenAlbum: () => albumCalls++,
                      showInlineQueueAction: hovered,
                    ),
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('row'))));
    await tester.pump();
    expect(find.byTooltip('Play from here'), findsOneWidget);

    await tester.tap(find.byTooltip('Play from here'));
    await tester.tap(find.byTooltip('Open artist'));
    await tester.tap(find.byTooltip('Open album'));

    expect(playButtonCalls, 1);
    expect(artistCalls, 1);
    expect(albumCalls, 1);
    expect(rowPlays, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact row leaves Artist and Album navigation to More', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var rowPlays = 0;
    var artistCalls = 0;
    var albumCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicTrackRowSurface(
            itemKey: const ValueKey('compact-row'),
            desktop: false,
            current: false,
            semanticLabel: 'Interactive Track, First Artist',
            onTap: () => rowPlays++,
            contentBuilder: (context, active, hovered) => MusicTrackRowContent(
              index: 1,
              track: track,
              desktop: false,
              current: false,
              active: active,
              artistNames: 'First Artist',
              onPlay: () {},
              onAddToQueue: () {},
              onMore: () {},
              onOpenArtist: () => artistCalls++,
              onOpenAlbum: () => albumCalls++,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MusicTrackMetadataAction), findsNothing);
    await tester.tap(find.text('First Artist'));
    await tester.tap(find.text('Interactive Album'));

    expect(artistCalls, 0);
    expect(albumCalls, 0);
    expect(rowPlays, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple Artists use the shared detail chooser', (tester) async {
    ArtistSummary? selected;
    const artists = [
      ArtistSummary(
        providerId: 'qq-music',
        opaqueId: 'artist:first',
        name: 'First Artist',
      ),
      ArtistSummary(
        providerId: 'qq-music',
        opaqueId: 'artist:second',
        name: 'Second Artist',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => openMusicTrackArtists(
              context: context,
              artists: artists,
              onSelected: (artist) => selected = artist,
              itemKeyPrefix: 'test-artist',
            ),
            child: const Text('Choose'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('test-artist-1')));
    await tester.pumpAndSettle();

    expect(selected, artists[1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current compact row uses the shared selected surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Material(
            child: MusicTrackRowSurface(
              itemKey: const ValueKey('current-row'),
              desktop: false,
              current: true,
              semanticLabel: 'Current Interactive Track',
              onTap: () {},
              contentBuilder: (context, active, hovered) =>
                  MusicTrackRowContent(
                    index: 1,
                    track: track,
                    desktop: false,
                    current: true,
                    active: active,
                    artistNames: 'First Artist',
                    onPlay: () {},
                    onAddToQueue: () {},
                    onMore: () {},
                  ),
            ),
          ),
        ),
      ),
    );

    final row = find.byKey(const ValueKey('current-row'));
    final ink = tester.widget<Ink>(
      find.descendant(of: row, matching: find.byType(Ink)),
    );
    expect(
      (ink.decoration as BoxDecoration).color,
      Theme.of(tester.element(row)).colorScheme.surfaceContainerHigh,
    );
    expect(
      tester.getSemantics(row).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('locator appears offscreen and returns to the current row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicTrackLocatorOverlay(
            controller: controller,
            currentIndex: 20,
            desktop: false,
            child: ListView.builder(
              controller: controller,
              itemExtent: 65,
              itemCount: 30,
              itemBuilder: (context, index) => SizedBox(
                key: ValueKey('locator-row-$index'),
                child: Text('Track ${index + 1}'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final locator = find.byKey(const ValueKey('locate-current-track'));
    expect(locator, findsOneWidget);
    await tester.tap(locator);
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(1000));
    expect(find.byKey(const ValueKey('locator-row-20')), findsOneWidget);
    expect(locator, findsOneWidget);
    expect(locator.hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'locator stays semantics-safe through metrics and owner changes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _locatorHarness(
          controller: controller,
          currentIndex: 20,
          desktop: false,
        ),
      );
      await tester.pumpAndSettle();
      final locator = find.byKey(const ValueKey('locate-current-track'));
      final locatorSemantics = find.semantics.byPredicate(
        (node) => node.tooltip == 'Locate current track',
      );
      expect(locator, findsOneWidget);
      expect(locatorSemantics, findsOne);
      final stableLocatorElement = tester.element(locator);
      if (const bool.fromEnvironment('LOCATOR_VISUAL_REVIEW')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-locator-compact-offscreen.png'),
          ),
        );
      }

      await tester.tap(locator);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('LOCATOR_VISUAL_REVIEW')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(Uri.file('/tmp/fura-locator-compact-located.png')),
        );
      }

      tester.view.physicalSize = const Size(520, 300);
      await tester.pumpWidget(
        _locatorHarness(
          controller: controller,
          currentIndex: 5,
          desktop: true,
          leadingExtent: 34,
        ),
      );
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('LOCATOR_VISUAL_REVIEW')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-locator-desktop-offscreen.png'),
          ),
        );
      }

      controller.jumpTo(controller.position.minScrollExtent);
      tester.view.physicalSize = const Size(320, 500);
      await tester.pumpWidget(
        _locatorHarness(
          controller: controller,
          currentIndex: 0,
          desktop: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 8));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(locator, findsOneWidget);
      expect(tester.element(locator), same(stableLocatorElement));
      expect(locator.hitTestable(), findsNothing);
      expect(locatorSemantics, findsNothing);
      if (const bool.fromEnvironment('LOCATOR_VISUAL_REVIEW')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(Uri.file('/tmp/fura-locator-visible-row.png')),
        );
      }

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('locator remains hidden while any part of its row is visible', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _locatorHarness(controller: controller, currentIndex: 5, desktop: false),
    );
    await tester.pumpAndSettle();
    final locator = find.byKey(const ValueKey('locate-current-track'));
    final locatorSemantics = find.semantics.byPredicate(
      (node) => node.tooltip == 'Locate current track',
    );

    controller.jumpTo(26);
    await tester.pumpAndSettle();
    expect(locator, findsOneWidget);
    expect(locator.hitTestable(), findsNothing);
    expect(locatorSemantics, findsNothing);

    controller.jumpTo(25);
    await tester.pumpAndSettle();
    expect(locator, findsOneWidget);
    expect(locatorSemantics, findsOne);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

Widget _locatorHarness({
  required ScrollController controller,
  required int? currentIndex,
  required bool desktop,
  double leadingExtent = 0,
}) => MaterialApp(
  home: Scaffold(
    body: MusicTrackLocatorOverlay(
      controller: controller,
      currentIndex: currentIndex,
      desktop: desktop,
      leadingExtent: leadingExtent,
      itemExtent: musicTrackRowExtent(desktop: desktop),
      child: ListView.builder(
        controller: controller,
        itemExtent: musicTrackRowExtent(desktop: desktop),
        itemCount: 40,
        itemBuilder: (context, index) => SizedBox(
          key: ValueKey('locator-row-$index'),
          child: Text('Track ${index + 1}'),
        ),
      ),
    ),
  ),
);
