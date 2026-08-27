import 'package:flutter/material.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    required this.libraryController,
    required this.recommendationController,
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onOpenPlaylist,
    required this.onOpenRecommendation,
    this.lastOpenedPlaylist,
    this.playlistReturnFocusNode,
    this.lastOpenedRecommendation,
    this.recommendationReturnFocusNode,
    super.key,
  });

  final UserLibraryController libraryController;
  final RecommendedPlaylistController recommendationController;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final ValueChanged<UserPlaylistSummary> onOpenPlaylist;
  final ValueChanged<RecommendedPlaylistSummary> onOpenRecommendation;
  final UserPlaylistSummary? lastOpenedPlaylist;
  final FocusNode? playlistReturnFocusNode;
  final RecommendedPlaylistSummary? lastOpenedRecommendation;
  final FocusNode? recommendationReturnFocusNode;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([libraryController, recommendationController]),
    builder: (context, _) => SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final pagePadding = constraints.maxWidth >= 840
              ? MusicSpacing.panel
              : constraints.maxWidth < 520
              ? MusicSpacing.pageCompact
              : MusicSpacing.page;

          return SingleChildScrollView(
            key: const PageStorageKey('home-scroll'),
            padding: EdgeInsets.fromLTRB(
              pagePadding,
              compact ? MusicSpacing.pageCompact : MusicSpacing.page,
              pagePadding,
              MusicSpacing.pageWide,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Good to see you',
                        key: const ValueKey('home-heading'),
                        style:
                            (compact
                                    ? Theme.of(context).textTheme.headlineSmall
                                    : Theme.of(context)
                                          .textTheme
                                          .headlineMedium)
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your music and current QQ Music picks, ready when you are.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(
                      height: compact
                          ? MusicSpacing.section
                          : MusicSpacing.panel,
                    ),
                    _HomeSectionHeader(
                      title: 'Recommended playlists',
                      supportingText: 'Public playlist picks from QQ Music',
                      actionKey: const ValueKey('home-open-discover'),
                      actionLabel: 'See all',
                      onAction: onOpenDiscover,
                      compact: compact,
                    ),
                    const SizedBox(height: 12),
                    _RecommendationSection(
                      controller: recommendationController,
                      compact: compact,
                      onSelected: onOpenRecommendation,
                      lastOpened: lastOpenedRecommendation,
                      returnFocusNode: recommendationReturnFocusNode,
                    ),
                    SizedBox(
                      height: compact
                          ? MusicSpacing.section
                          : MusicSpacing.page,
                    ),
                    _HomeSectionHeader(
                      title: 'Your playlists',
                      supportingText: 'Saved in your QQ Music library',
                      actionKey: const ValueKey('home-open-library'),
                      actionLabel: 'Open library',
                      onAction: onOpenLibrary,
                      compact: compact,
                    ),
                    const SizedBox(height: 12),
                    _LibrarySection(
                      controller: libraryController,
                      compact: compact,
                      onSelected: onOpenPlaylist,
                      lastOpened: lastOpenedPlaylist,
                      returnFocusNode: playlistReturnFocusNode,
                      onOpenLibrary: onOpenLibrary,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    required this.title,
    required this.supportingText,
    required this.actionKey,
    required this.actionLabel,
    required this.onAction,
    required this.compact,
  });

  final String title;
  final String supportingText;
  final Key actionKey;
  final String actionLabel;
  final VoidCallback onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (compact
                            ? Theme.of(context).textTheme.titleLarge
                            : Theme.of(context).textTheme.headlineSmall)
                        ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: MusicSpacing.itemGap),
          TextButton(
            key: actionKey,
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
      Text(
        supportingText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

class _RecommendationSection extends StatelessWidget {
  const _RecommendationSection({
    required this.controller,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
  });

  final RecommendedPlaylistController controller;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;

  @override
  Widget build(BuildContext context) => switch (controller.stage) {
    RecommendedPlaylistStage.loading => _HomeLoadingStrip(
      key: const ValueKey('home-recommendations-loading'),
      compact: compact,
      semanticLabel: 'Loading Home recommendations',
    ),
    RecommendedPlaylistStage.empty => const _HomeInlineState(
      key: ValueKey('home-recommendations-empty'),
      icon: Icons.explore_off_outlined,
      title: 'No recommendations right now',
      detail: 'Discover still has rankings, Radar, and new releases.',
    ),
    RecommendedPlaylistStage.error => _HomeInlineState(
      key: const ValueKey('home-recommendations-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Recommendations are unavailable',
      detail: 'Your Library and Search are still available.',
      liveRegion: true,
      action: controller.canRetry
          ? FilledButton.tonal(
              onPressed: controller.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    RecommendedPlaylistStage.content =>
      _HomePlaylistStrip<RecommendedPlaylistSummary>(
        key: const ValueKey('home-recommendations-section'),
        items: controller.playlists.take(8).toList(growable: false),
        compact: compact,
        title: (playlist) => playlist.title,
        artworkUri: (playlist) => playlist.artworkUri,
        detail: (playlist) => playlist.trackCount == null
            ? 'QQ Music playlist'
            : '${playlist.trackCount} tracks',
        semanticLabel: (playlist) => playlist.trackCount == null
            ? '${playlist.title}, QQ Music playlist'
            : '${playlist.title}, ${playlist.trackCount} tracks',
        itemKey: (index) => ValueKey('home-recommendation-$index'),
        onSelected: onSelected,
        returnFocusNode: returnFocusNode,
        focusMatches: (playlist) =>
            lastOpened?.providerId == playlist.providerId &&
            lastOpened?.opaqueId == playlist.opaqueId,
        placeholderIcon: Icons.queue_music_rounded,
      ),
  };
}

class _LibrarySection extends StatelessWidget {
  const _LibrarySection({
    required this.controller,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
    required this.onOpenLibrary,
  });

  final UserLibraryController controller;
  final bool compact;
  final ValueChanged<UserPlaylistSummary> onSelected;
  final UserPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) => switch (controller.stage) {
    UserLibraryStage.loading => _HomeLoadingStrip(
      key: const ValueKey('home-library-loading'),
      compact: compact,
      semanticLabel: 'Loading your playlists',
      rows: true,
    ),
    UserLibraryStage.empty => _HomeInlineState(
      key: const ValueKey('home-library-empty'),
      icon: Icons.library_music_outlined,
      title: 'Your playlist library is empty',
      detail: 'Open Your music to browse favorite Albums and Artists.',
      action: FilledButton.tonal(
        onPressed: onOpenLibrary,
        child: const Text('Open your music'),
      ),
    ),
    UserLibraryStage.error => _HomeInlineState(
      key: const ValueKey('home-library-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load your playlists',
      detail: 'Your recommendations and Search are still available.',
      liveRegion: true,
      action: controller.canRetry
          ? FilledButton.tonal(
              onPressed: controller.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    UserLibraryStage.content => _HomeLibraryRows(
      key: const ValueKey('home-library-section'),
      items: controller.playlists.take(compact ? 4 : 6).toList(growable: false),
      compact: compact,
      onSelected: onSelected,
      lastOpened: lastOpened,
      returnFocusNode: returnFocusNode,
    ),
    UserLibraryStage.authenticationRequired ||
    UserLibraryStage.credentialRejected => const SizedBox.shrink(),
  };
}

class _HomePlaylistStrip<T> extends StatelessWidget {
  const _HomePlaylistStrip({
    required this.items,
    required this.compact,
    required this.title,
    required this.artworkUri,
    required this.detail,
    required this.semanticLabel,
    required this.itemKey,
    required this.onSelected,
    required this.returnFocusNode,
    required this.focusMatches,
    required this.placeholderIcon,
    super.key,
  });

  final List<T> items;
  final bool compact;
  final String Function(T item) title;
  final String? Function(T item) artworkUri;
  final String Function(T item) detail;
  final String Function(T item) semanticLabel;
  final Key Function(int index) itemKey;
  final ValueChanged<T> onSelected;
  final FocusNode? returnFocusNode;
  final bool Function(T item) focusMatches;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final cardWidth = compact ? 152.0 : 160.0;
    return SizedBox(
      height: cardWidth + 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: MusicSpacing.contentGap),
        itemBuilder: (context, index) {
          final item = items[index];
          return SizedBox(
            width: cardWidth,
            child: Focus(
              focusNode: focusMatches(item) ? returnFocusNode : null,
              child: Semantics(
                button: true,
                label: semanticLabel(item),
                excludeSemantics: true,
                onTap: () => onSelected(item),
                child: InkWell(
                  key: itemKey(index),
                  borderRadius: MusicRadii.content,
                  onTap: () => onSelected(item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        height: cardWidth,
                        child: _HomeArtwork(
                          uri: artworkUri(item),
                          placeholderIcon: placeholderIcon,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeLibraryRows extends StatelessWidget {
  const _HomeLibraryRows({
    required this.items,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
    super.key,
  });

  final List<UserPlaylistSummary> items;
  final bool compact;
  final ValueChanged<UserPlaylistSummary> onSelected;
  final UserPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;

  bool _focusMatches(UserPlaylistSummary playlist) =>
      lastOpened?.providerId == playlist.providerId &&
      lastOpened?.opaqueId == playlist.opaqueId;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = compact
          ? 1
          : constraints.maxWidth >= 1040
          ? 3
          : 2;
      const gap = 12.0;
      final itemWidth = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(
        key: ValueKey(compact ? 'home-library-list' : 'home-library-grid'),
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var index = 0; index < items.length; index++)
            SizedBox(
              width: itemWidth,
              child: _HomeLibraryRow(
                item: items[index],
                itemKey: ValueKey('home-library-playlist-$index'),
                onSelected: onSelected,
                focusNode: _focusMatches(items[index]) ? returnFocusNode : null,
              ),
            ),
        ],
      );
    },
  );
}

class _HomeLibraryRow extends StatelessWidget {
  const _HomeLibraryRow({
    required this.item,
    required this.itemKey,
    required this.onSelected,
    required this.focusNode,
  });

  final UserPlaylistSummary item;
  final Key itemKey;
  final ValueChanged<UserPlaylistSummary> onSelected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final detail = item.trackCount == null
        ? 'Saved playlist'
        : '${item.trackCount} tracks';
    final semanticLabel = item.trackCount == null
        ? '${item.title}, saved playlist'
        : '${item.title}, ${item.trackCount} tracks';
    return Focus(
      focusNode: focusNode,
      child: Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        onTap: () => onSelected(item),
        child: Material(
          color: colors.surfaceContainerLow,
          borderRadius: MusicRadii.control,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: itemKey,
            onTap: () => onSelected(item),
            child: Padding(
              padding: const EdgeInsets.all(MusicSpacing.itemGap),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 56,
                    child: _HomeArtwork(
                      uri: item.artworkUri,
                      placeholderIcon: Icons.library_music_rounded,
                      radius: MusicRadii.control,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: MusicSpacing.itemGap),
                  Icon(
                    Icons.chevron_right_rounded,
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

class _HomeArtwork extends StatelessWidget {
  const _HomeArtwork({
    required this.uri,
    required this.placeholderIcon,
    this.radius = MusicRadii.content,
  });

  final String? uri;
  final IconData placeholderIcon;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: radius,
      ),
      child: Icon(
        placeholderIcon,
        color: colors.onSecondaryContainer,
        size: 38,
      ),
    );
    return ClipRRect(
      borderRadius: radius,
      child: uri == null
          ? placeholder
          : Image.network(
              uri!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

class _HomeLoadingStrip extends StatelessWidget {
  const _HomeLoadingStrip({
    required this.compact,
    required this.semanticLabel,
    this.rows = false,
    super.key,
  });

  final bool compact;
  final String semanticLabel;
  final bool rows;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: rows
        ? _HomeLoadingRows(compact: compact)
        : SizedBox(
            height: compact ? 210 : 218,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: compact ? 3 : 7,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: MusicSpacing.contentGap),
              itemBuilder: (_, _) => Container(
                width: compact ? 152 : 160,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: MusicRadii.content,
                ),
              ),
            ),
          ),
  );
}

class _HomeLoadingRows extends StatelessWidget {
  const _HomeLoadingRows({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = compact
          ? 1
          : constraints.maxWidth >= 1040
          ? 3
          : 2;
      const gap = 12.0;
      final itemWidth = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var index = 0; index < (compact ? 4 : 6); index++)
            Container(
              width: itemWidth,
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: MusicRadii.control,
              ),
            ),
        ],
      );
    },
  );
}

class _HomeInlineState extends StatelessWidget {
  const _HomeInlineState({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
    this.liveRegion = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: liveRegion,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MusicSpacing.contentGap),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: MusicRadii.content,
      ),
      child: Wrap(
        spacing: MusicSpacing.contentGap,
        runSpacing: MusicSpacing.itemGap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    ),
  );
}
