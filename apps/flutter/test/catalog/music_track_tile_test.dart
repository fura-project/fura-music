import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/catalog/music_track_tile.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

void main() {
  const album = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'album:43001:fixtureAlbumMid',
    title: 'Fixture Album',
  );
  const firstArtist = ArtistSummary(
    providerId: 'qq-music',
    opaqueId: 'artist:42001:firstArtistMid',
    name: 'First Artist',
  );
  const secondArtist = ArtistSummary(
    providerId: 'qq-music',
    opaqueId: 'artist:42002:secondArtistMid',
    name: 'Second Artist',
  );
  const track = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:41001:0:fixtureMid:-',
    title: 'Fixture Track',
    subtitle: 'Live',
    artistNames: ['First Artist', 'Second Artist'],
    artists: [firstArtist, secondArtist],
    albumTitle: 'Fixture Album',
    album: album,
    durationSeconds: 185,
  );

  testWidgets('keeps compact Track metadata and actions reachable at 360 px', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var playCount = 0;
    var queueCount = 0;
    AlbumSummary? openedAlbum;
    ArtistSummary? openedArtist;

    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.light(),
        home: Scaffold(
          body: MusicTrackTile(
            itemKey: const ValueKey('compact-track'),
            queueKey: const ValueKey('compact-queue'),
            contextKey: const ValueKey('compact-context'),
            track: track,
            position: 12,
            desktop: false,
            onPlay: () => playCount++,
            onQueue: () => queueCount++,
            onOpenAlbum: (album) => openedAlbum = album,
            onOpenArtist: (artist) => openedArtist = artist,
          ),
        ),
      ),
    );

    expect(find.text('Fixture Track · Live'), findsOneWidget);
    expect(
      find.text('First Artist · Second Artist · Fixture Album · 3:05'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Artwork for Fixture Track')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final contextAction = find.byKey(const ValueKey('compact-context'));
    var contextFocused = false;
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      if (focusedContext != null &&
          find
              .ancestor(
                of: find.byElementPredicate(
                  (element) => identical(element, focusedContext),
                ),
                matching: contextAction,
              )
              .evaluate()
              .isNotEmpty) {
        contextFocused = true;
        break;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(contextFocused, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Open album'), findsOneWidget);
    expect(find.text('Open artist'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('track-context-album')));
    await tester.pumpAndSettle();
    expect(openedAlbum, same(album));

    await tester.tap(find.byKey(const ValueKey('compact-context')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-context-artist-1')));
    await tester.pumpAndSettle();
    expect(openedArtist, same(secondArtist));

    await tester.tap(find.byKey(const ValueKey('compact-track')));
    await tester.tap(find.byKey(const ValueKey('compact-queue')));
    expect(playCount, 1);
    expect(queueCount, 1);
    semantics.dispose();
  });

  testWidgets('uses dense desktop metadata and truthful unknown duration', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.dark(),
        home: Scaffold(
          body: Column(
            children: [
              MusicTrackTile(
                itemKey: const ValueKey('desktop-track'),
                queueKey: const ValueKey('desktop-queue'),
                track: track,
                position: 1,
                desktop: true,
                onPlay: () {},
                onQueue: () {},
              ),
              MusicTrackTile(
                itemKey: const ValueKey('unknown-duration-track'),
                queueKey: const ValueKey('unknown-duration-queue'),
                contextKey: const ValueKey('unknown-duration-context'),
                track: const PlaylistTrackSummary(
                  providerId: 'qq-music',
                  opaqueId: 'track:41002:0:fixtureMid2:-',
                  title: 'Unknown duration',
                  artistNames: [],
                ),
                position: 2,
                desktop: true,
                onPlay: () {},
                onQueue: () {},
                onOpenAlbum: (_) {},
                onOpenArtist: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.text('First Artist · Second Artist · Fixture Album'),
      findsOneWidget,
    );
    expect(find.text('3:05'), findsOneWidget);
    expect(find.text('Unknown artist'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('unknown-duration-context')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  test('formats only positive known durations', () {
    expect(formatTrackDuration(1), '0:01');
    expect(formatTrackDuration(3599), '59:59');
    expect(formatTrackDuration(null), '—');
    expect(formatTrackDuration(0), '—');
  });
}
