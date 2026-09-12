import 'package:flutter/material.dart';
import 'package:flutterustmusic/navigation/music_section_selector.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

enum LibrarySection { playlists, albums, artists, likedSongs }

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
      final l10n = context.l10n;
      final destinations = [
        MusicSectionDestination(
          value: LibrarySection.likedSongs,
          icon: Icons.favorite_rounded,
          label: l10n.libraryLikedSongs,
          itemKey: const ValueKey('library-section-liked-songs'),
        ),
        MusicSectionDestination(
          value: LibrarySection.playlists,
          icon: Icons.queue_music_rounded,
          label: l10n.libraryPlaylists,
          itemKey: const ValueKey('library-section-playlists'),
        ),
        MusicSectionDestination(
          value: LibrarySection.albums,
          icon: Icons.album_rounded,
          label: l10n.libraryAlbums,
          itemKey: const ValueKey('library-section-albums'),
        ),
        MusicSectionDestination(
          value: LibrarySection.artists,
          icon: Icons.person_rounded,
          label: l10n.libraryArtists,
          itemKey: const ValueKey('library-section-artists'),
        ),
      ];
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
            label: l10n.librarySectionLabel,
            destinations: destinations,
            selected: selected,
            compact: compact,
            onSelected: onSelected,
          ),
        ),
      );
    },
  );
}
