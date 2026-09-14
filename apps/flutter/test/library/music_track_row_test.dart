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
}
