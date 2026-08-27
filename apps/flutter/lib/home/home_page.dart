import 'package:flutter/material.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    required this.onOpenDiscover,
    required this.onOpenSearch,
    required this.onOpenLibrary,
    super.key,
  });

  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final pagePadding = constraints.maxWidth >= 840
            ? MusicSpacing.pageWide
            : constraints.maxWidth < 520
            ? MusicSpacing.pageCompact
            : MusicSpacing.page;
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        final availableWidth = (constraints.maxWidth - pagePadding * 2).clamp(
          0.0,
          960.0,
        );
        final tileWidth =
            (availableWidth - MusicSpacing.contentGap * (columns - 1)) /
            columns;

        return SingleChildScrollView(
          key: const PageStorageKey('home-scroll'),
          padding: EdgeInsets.fromLTRB(
            pagePadding,
            MusicSpacing.page,
            pagePadding,
            MusicSpacing.pageWide,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Start listening',
                      key: const ValueKey('home-heading'),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                  const SizedBox(height: MusicSpacing.itemGap),
                  Text(
                    'Explore QQ Music or return to the collection you know.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: MusicSpacing.section),
                  Semantics(
                    header: true,
                    child: Text(
                      'Choose where to begin',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: MusicSpacing.contentGap),
                  Wrap(
                    spacing: MusicSpacing.contentGap,
                    runSpacing: MusicSpacing.contentGap,
                    children: [
                      _HomeDestination(
                        key: const ValueKey('home-open-discover'),
                        width: tileWidth,
                        icon: Icons.explore_rounded,
                        title: 'Discover',
                        description: 'Recommendations, rankings, Radar, and new releases',
                        onTap: onOpenDiscover,
                      ),
                      _HomeDestination(
                        key: const ValueKey('home-open-search'),
                        width: tileWidth,
                        icon: Icons.search_rounded,
                        title: 'Search the catalog',
                        description:
                            'Find Tracks, Artists, Albums, and Playlists',
                        onTap: onOpenSearch,
                      ),
                      _HomeDestination(
                        key: const ValueKey('home-open-library'),
                        width: tileWidth,
                        icon: Icons.library_music_rounded,
                        title: 'Your music',
                        description:
                            'Playlists, favorite Albums, and favorite Artists',
                        onTap: onOpenLibrary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _HomeDestination extends StatelessWidget {
  const _HomeDestination({
    required this.width,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    super.key,
  });

  final double width;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: MusicRadii.content,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 144),
            child: Padding(
              padding: const EdgeInsets.all(MusicSpacing.contentGap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: colors.primary, size: 28),
                  const SizedBox(height: MusicSpacing.contentGap),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: MusicSpacing.itemGap),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
