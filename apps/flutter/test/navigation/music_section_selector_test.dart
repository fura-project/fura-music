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

const _chineseDestinations = [
  MusicSectionDestination(
    value: _Section.tracks,
    icon: Icons.music_note_rounded,
    label: '歌曲',
    itemKey: ValueKey('section-tracks'),
  ),
  MusicSectionDestination(
    value: _Section.artists,
    icon: Icons.person_rounded,
    label: '歌手',
    itemKey: ValueKey('section-artists'),
  ),
  MusicSectionDestination(
    value: _Section.albums,
    icon: Icons.album_rounded,
    label: '专辑和单曲',
    itemKey: ValueKey('section-albums'),
  ),
];

void main() {
  const captureMaterialReview = bool.fromEnvironment(
    'MATERIAL_FIRST_VISUAL_REVIEW',
  );
  for (final (language, label, destinations) in [
    ('English', 'Search type', _destinations),
    ('Chinese', '搜索类型', _chineseDestinations),
  ]) {
    for (final width in [320.0, 360.0, 390.0]) {
      testWidgets('$language compact selector is stable at $width px', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 240);
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
                  label: label,
                  destinations: destinations,
                  selected: _Section.tracks,
                  compact: true,
                  onSelected: (value) => selected = value,
                ),
              ),
            ),
          ),
        );

        final control = find.byKey(const ValueKey('section-selector'));
        final currentLabel = destinations.first.label;
        expect(find.text(currentLabel), findsWidgets);
        expect(find.text('$label: $currentLabel'), findsNothing);
        expect(find.byType(DropdownMenu<_Section>), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
        final size = tester.getSize(control);
        expect(size.width, 180);
        expect(size.height, 56);
        final semantics = tester.getSemantics(control);
        expect(semantics.label, contains(label));
        expect(semantics.label, contains(currentLabel));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('section-tracks')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('section-artists')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('section-albums')).hitTestable(),
          findsOneWidget,
        );
        if (captureMaterialReview && language == 'English' && width == 360) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              Uri.file('/tmp/fura-search-material-dropdown-360.png'),
            ),
          );
        }
        await tester.tap(
          find
              .ancestor(
                of: find.byKey(const ValueKey('section-artists')).hitTestable(),
                matching: find.byType(MenuItemButton),
              )
              .hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(selected, _Section.artists);
        expect(tester.takeException(), isNull);
      });
    }
  }

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
