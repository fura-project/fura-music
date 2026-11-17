import 'package:flutter/material.dart';
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
        expect(find.text(currentLabel), findsOneWidget);
        expect(find.text('$label: $currentLabel'), findsNothing);
        expect(find.byType(TabBar), findsOneWidget);
        expect(find.byType(DropdownMenu<_Section>), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        final size = tester.getSize(control);
        expect(size.width, lessThanOrEqualTo(width));
        expect(size.height, 48);
        final semantics = tester.getSemantics(control);
        expect(semantics.label, contains(label));
        expect(semantics.label, contains(currentLabel));
        expect(
          find.byKey(const ValueKey('section-tracks')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('section-artists')).hitTestable(),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('section-albums')),
        );
        await tester.pumpAndSettle();
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
        final artistsTab = find.byKey(const ValueKey('section-artists'));
        await tester.ensureVisible(artistsTab);
        await tester.pumpAndSettle();
        await tester.tap(artistsTab);
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

  testWidgets(
    'compact secondary TabBar stays strictly controlled by selected and scales cleanly at 2.0x',
    (tester) async {
      tester.view.physicalSize = const Size(320, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const fourChineseTabs = [
        ..._chineseDestinations,
        MusicSectionDestination(
          value: _Section.tracks,
          icon: Icons.queue_music_rounded,
          label: '推荐歌单精选',
          itemKey: ValueKey('section-playlists'),
        ),
      ];

      var selected = _Section.tracks;
      var allowSelectionChange = false;
      _Section? tapped;
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          theme: MusicMaterialTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: MusicSectionSelector<_Section>(
                    controlKey: const ValueKey('section-selector'),
                    label: '搜索类型',
                    destinations: fourChineseTabs,
                    selected: selected,
                    compact: true,
                    onSelected: (value) {
                      tapped = value;
                      if (allowSelectionChange) {
                        setState(() => selected = value);
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.indicatorSize, isNot(TabBarIndicatorSize.label));
      expect(tabBar.controller!.index, 0);

      final artistsTab = find.byKey(const ValueKey('section-artists'));
      await tester.ensureVisible(artistsTab);
      await tester.pumpAndSettle();
      await tester.tap(artistsTab);
      await tester.pumpAndSettle();

      // Guarded parent kept selected == _Section.tracks, so TabController must not desync.
      expect(tapped, _Section.artists);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);

      allowSelectionChange = true;
      await tester.tap(artistsTab);
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);

      final playlistsTab = find.byKey(const ValueKey('section-playlists'));
      await tester.ensureVisible(playlistsTab);
      await tester.pumpAndSettle();
      expect(playlistsTab.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      rebuild(() {});
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicMaterialTheme.light(),
          home: Scaffold(
            body: MusicSectionSelector<_Section>(
              controlKey: const ValueKey('empty-selector'),
              label: 'Empty',
              destinations: const [],
              selected: _Section.albums,
              compact: true,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
