import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/navigation/music_section_selector.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

enum _Section { tracks, artists, albums }

const _destinations = [
  MusicSectionDestination(
    value: _Section.tracks,
    icon: Icons.music_note_rounded,
    label: 'Tracks',
    itemKey: ValueKey('section-tracks'),
  ),
  MusicSectionDestination(
    value: _Section.artists,
    icon: Icons.person_rounded,
    label: 'Artists',
    itemKey: ValueKey('section-artists'),
  ),
  MusicSectionDestination(
    value: _Section.albums,
    icon: Icons.album_rounded,
    label: 'Albums',
    itemKey: ValueKey('section-albums'),
  ),
];

void main() {
  testWidgets('exposes every compact destination from one labeled menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _Section? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MusicSectionSelector<_Section>(
              controlKey: const ValueKey('section-selector'),
              label: 'Search type',
              destinations: _destinations,
              selected: _Section.tracks,
              compact: true,
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Search type: Tracks'), findsOneWidget);
    expect(find.byKey(const ValueKey('section-artists')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('section-tracks')), findsOneWidget);
    expect(find.byKey(const ValueKey('section-artists')), findsOneWidget);
    expect(find.byKey(const ValueKey('section-albums')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('section-artists')));
    await tester.pumpAndSettle();
    expect(selected, _Section.artists);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps medium and desktop destinations visible and selectable', (
    tester,
  ) async {
    _Section? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.dark(),
        home: Scaffold(
          body: MusicSectionSelector<_Section>(
            controlKey: const ValueKey('section-selector'),
            label: 'Discover section',
            destinations: _destinations,
            selected: _Section.tracks,
            compact: false,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.byType(SegmentedButton<_Section>), findsOneWidget);
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('section-albums')));
    await tester.pumpAndSettle();
    expect(selected, _Section.albums);
    expect(tester.takeException(), isNull);
  });
}
