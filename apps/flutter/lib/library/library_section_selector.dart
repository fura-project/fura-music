import 'package:flutter/material.dart';
import 'package:flutterustmusic/navigation/music_section_selector.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

enum LibrarySection { playlists, albums, artists }

const _destinations = [
  MusicSectionDestination(
    value: LibrarySection.playlists,
    icon: Icons.queue_music_rounded,
    label: 'Playlists',
    itemKey: ValueKey('library-section-playlists'),
  ),
  MusicSectionDestination(
    value: LibrarySection.albums,
    icon: Icons.album_rounded,
    label: 'Albums',
    itemKey: ValueKey('library-section-albums'),
  ),
  MusicSectionDestination(
    value: LibrarySection.artists,
    icon: Icons.person_rounded,
    label: 'Artists',
    itemKey: ValueKey('library-section-artists'),
  ),
];

class LibrarySectionSelector extends StatelessWidget {
  const LibrarySectionSelector({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final LibrarySection selected;
  final ValueChanged<LibrarySection> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 680;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? MusicSpacing.pageCompact : MusicSpacing.pageWide,
          MusicSpacing.contentGap,
          compact ? MusicSpacing.pageCompact : MusicSpacing.pageWide,
          0,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: MusicSectionSelector<LibrarySection>(
            controlKey: const ValueKey('library-section-selector'),
            label: 'Library',
            destinations: _destinations,
            selected: selected,
            compact: compact,
            onSelected: onSelected,
          ),
        ),
      );
    },
  );
}
