import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/music_track_tile.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

void main() {
  const track = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track:41001:0:fixtureMid:-',
    title: 'Fixture Track',
    subtitle: 'Live',
    artistNames: ['First Artist', 'Second Artist'],
    albumTitle: 'Fixture Album',
    durationSeconds: 185,
  );

  testWidgets('keeps compact Track metadata and actions reachable at 360 px', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var playCount = 0;
    var queueCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.light(),
        home: Scaffold(
          body: MusicTrackTile(
            itemKey: const ValueKey('compact-track'),
            queueKey: const ValueKey('compact-queue'),
            track: track,
            position: 12,
            desktop: false,
            onPlay: () => playCount++,
            onQueue: () => queueCount++,
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
    expect(tester.takeException(), isNull);
  });

  test('formats only positive known durations', () {
    expect(formatTrackDuration(1), '0:01');
    expect(formatTrackDuration(3599), '59:59');
    expect(formatTrackDuration(null), '—');
    expect(formatTrackDuration(0), '—');
  });
}
