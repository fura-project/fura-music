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
        final wide = constraints.maxWidth >= 760;
        final columns = constraints.maxWidth >= 720 ? 2 : 1;
        final availableWidth = (constraints.maxWidth - pagePadding * 2).clamp(
          0.0,
          MusicSizes.contentMaxWidth,
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
              constraints: const BoxConstraints(
                maxWidth: MusicSizes.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HomeHero(wide: wide, onOpenLibrary: onOpenLibrary),
                  const SizedBox(height: MusicSpacing.pageWide),
                  if (wide)
                    const Row(
                      children: [
                        Expanded(child: _HomeSectionHeading()),
                        _HomeSectionSupportingText(),
                      ],
                    )
                  else
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HomeSectionHeading(),
                        SizedBox(height: MusicSpacing.itemGap),
                        _HomeSectionSupportingText(),
                      ],
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
                        eyebrow: 'DISCOVER',
                        title: 'Find something new',
                        description: 'Recommendations, rankings, Radar, and new releases',
                        onTap: onOpenDiscover,
                      ),
                      _HomeDestination(
                        key: const ValueKey('home-open-search'),
                        width: tileWidth,
                        icon: Icons.search_rounded,
                        eyebrow: 'SEARCH',
                        title: 'Search the catalog',
                        description: 'Tracks, Artists, Albums, and Playlists from QQ Music',
                        onTap: onOpenSearch,
                      ),
                    ],
                  ),
                  const SizedBox(height: MusicSpacing.pageWide),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: MusicRadii.content,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(MusicSpacing.contentGap),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: MusicSpacing.contentGap),
                          Expanded(
                            child: Text(
                              'Your saved session stays on this device; catalog requests go directly to QQ Music.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _HomeSectionHeading extends StatelessWidget {
  const _HomeSectionHeading();

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      'Explore QQ Music',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
  );
}

class _HomeSectionSupportingText extends StatelessWidget {
  const _HomeSectionSupportingText();

  @override
  Widget build(BuildContext context) => Text(
    'Your existing catalog, one tap away',
    style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.wide, required this.onOpenLibrary});

  final bool wide;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Music starts here',
            key: const ValueKey('home-heading'),
            style: theme.textTheme.displaySmall?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
        ),
        const SizedBox(height: MusicSpacing.itemGap),
        Text(
          'Open your playlists and favorites, or explore the QQ Music catalog.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onPrimaryContainer.withValues(alpha: 0.78),
          ),
        ),
        const SizedBox(height: MusicSpacing.contentGap),
        FilledButton.icon(
          key: const ValueKey('home-open-library'),
          onPressed: onOpenLibrary,
          icon: const Icon(Icons.library_music_rounded),
          label: const Text('Open your music'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
          ),
        ),
      ],
    );

    return Container(
      key: const ValueKey('home-hero'),
      width: double.infinity,
      constraints: BoxConstraints(minHeight: wide ? 288 : 260),
      decoration: BoxDecoration(
        borderRadius: MusicRadii.hero,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer,
            Color.alphaBlend(
              colors.primary.withValues(alpha: 0.16),
              colors.tertiaryContainer,
            ),
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(
          wide ? MusicSpacing.pageWide : MusicSpacing.page,
        ),
        child: wide
            ? Row(
                children: [
                  Expanded(flex: 3, child: copy),
                  const SizedBox(width: MusicSpacing.pageWide),
                  const Expanded(flex: 2, child: _MusicArtworkMotif()),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  copy,
                  const SizedBox(height: MusicSpacing.page),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 128,
                      height: 72,
                      child: _MusicArtworkMotif(compact: true),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MusicArtworkMotif extends StatelessWidget {
  const _MusicArtworkMotif({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -0.13,
            child: _MotifTile(
              color: colors.tertiary,
              icon: Icons.album_rounded,
              size: compact ? 62 : 150,
            ),
          ),
          Transform.translate(
            offset: Offset(compact ? 40 : 78, compact ? 8 : 24),
            child: Transform.rotate(
              angle: 0.12,
              child: _MotifTile(
                color: colors.primary,
                icon: Icons.graphic_eq_rounded,
                size: compact ? 54 : 124,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MotifTile extends StatelessWidget {
  const _MotifTile({
    required this.color,
    required this.icon,
    required this.size,
  });

  final Color color;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      borderRadius: MusicRadii.artwork,
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.16),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Icon(icon, color: Colors.white, size: size * 0.42),
  );
}

class _HomeDestination extends StatelessWidget {
  const _HomeDestination({
    required this.width,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.onTap,
    super.key,
  });

  final double width;
  final IconData icon;
  final String eyebrow;
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
            constraints: const BoxConstraints(minHeight: 152),
            child: Padding(
              padding: const EdgeInsets.all(MusicSpacing.contentGap),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: MusicRadii.content,
                    ),
                    child: Icon(
                      icon,
                      color: colors.onSecondaryContainer,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: MusicSpacing.contentGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          eyebrow,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: MusicSpacing.itemGap),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: MusicSpacing.itemGap),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: colors.onSurfaceVariant,
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
