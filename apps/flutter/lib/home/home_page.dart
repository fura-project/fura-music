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
          final pagePadding = constraints.maxWidth >= 1000
              ? 36.0
              : constraints.maxWidth < 520
              ? MusicSpacing.pageCompact
              : MusicSpacing.page;

          return SingleChildScrollView(
            key: const PageStorageKey('home-scroll'),
            padding: EdgeInsets.fromLTRB(
              pagePadding,
              compact ? MusicSpacing.contentGap : MusicSpacing.page,
              pagePadding,
              MusicSpacing.pageWide,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'For you today',
                        key: const ValueKey('home-heading'),
                        style:
                            (compact
                                    ? Theme.of(context).textTheme.titleMedium
                                    : Theme.of(context).textTheme.titleLarge)
                                ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Current QQ Music picks and the playlists you saved.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: MusicSpacing.section),
                    _HomeSectionHeader(
                      titleKey: const ValueKey('home-daily-heading'),
                      title: 'Daily recommendations',
                      supportingText:
                          'Current public playlist picks from QQ Music',
                      actionKey: const ValueKey('home-open-discover'),
                      actionLabel: 'Discover',
                      onAction: onOpenDiscover,
                      compact: compact,
                    ),
                    const SizedBox(height: 12),
                    _DailyRecommendationSection(
                      controller: recommendationController,
                      compact: compact,
                      onSelected: onOpenRecommendation,
                      lastOpened: lastOpenedRecommendation,
                      returnFocusNode: recommendationReturnFocusNode,
                    ),
                    const SizedBox(height: MusicSpacing.pageWide),
                    _HomeSectionHeader(
                      titleKey: const ValueKey('home-library-heading'),
                      title: 'Your playlist treasures',
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
                    const SizedBox(height: MusicSpacing.pageWide),
                    _HomeSectionHeader(
                      titleKey: const ValueKey('home-programs-heading'),
                      title: 'Popular programs',
                      supportingText: 'Editorial and spoken-audio picks',
                      compact: compact,
                    ),
                    const SizedBox(height: 12),
                    const _UnavailableHomeSection(
                      key: ValueKey('home-hot-programs-unavailable'),
                      icon: Icons.podcasts_outlined,
                      message: 'Popular programs aren’t available through the verified client data yet.',
                    ),
                    const SizedBox(height: MusicSpacing.pageWide),
                    _HomeSectionHeader(
                      titleKey: const ValueKey('home-listening-one-heading'),
                      title: 'Based on your listening',
                      supportingText:
                          'Song recommendations shaped by listening',
                      compact: compact,
                    ),
                    const SizedBox(height: 12),
                    const _UnavailableHomeSection(
                      key: ValueKey('home-listening-one-unavailable'),
                      icon: Icons.auto_awesome_outlined,
                      message: 'Listening-based song picks aren’t available through a verified capability yet.',
                    ),
                    const SizedBox(height: MusicSpacing.pageWide),
                    _HomeSectionHeader(
                      titleKey: const ValueKey(
                        'home-recommended-playlists-heading',
                      ),
                      title: 'Recommended playlists',
                      supportingText: 'More current public picks from QQ Music',
                      actionKey: const ValueKey(
                        'home-open-more-recommendations',
                      ),
                      actionLabel: 'See all',
                      onAction: onOpenDiscover,
                      compact: compact,
                    ),
                    const SizedBox(height: 12),
                    _MoreRecommendationsSection(
                      controller: recommendationController,
                      compact: compact,
                      onSelected: onOpenRecommendation,
                      lastOpened: lastOpenedRecommendation,
                      returnFocusNode: recommendationReturnFocusNode,
                    ),
                    const SizedBox(height: MusicSpacing.pageWide),
                    _HomeSectionHeader(
                      titleKey: const ValueKey('home-listening-two-heading'),
                      title: 'More from your listening',
                      supportingText:
                          'Another focused set of song recommendations',
                      compact: compact,
                    ),
                    const SizedBox(height: 12),
                    const _UnavailableHomeSection(
                      key: ValueKey('home-listening-two-unavailable'),
                      icon: Icons.music_note_outlined,
                      message: 'A second listening-based song set is not available without inventing personalization.',
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
    required this.titleKey,
    required this.title,
    required this.supportingText,
    required this.compact,
    this.actionKey,
    this.actionLabel,
    this.onAction,
  });

  final Key titleKey;
  final String title;
  final String supportingText;
  final bool compact;
  final Key? actionKey;
  final String? actionLabel;
  final VoidCallback? onAction;

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
                key: titleKey,
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
          if (onAction != null) ...[
            const SizedBox(width: MusicSpacing.itemGap),
            TextButton(
              key: actionKey,
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
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

class _DailyRecommendationSection extends StatelessWidget {
  const _DailyRecommendationSection({
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
    RecommendedPlaylistStage.loading => _DailyRecommendationLoading(
      compact: compact,
    ),
    RecommendedPlaylistStage.empty => const _HomeInlineState(
      key: ValueKey('home-recommendations-empty'),
      icon: Icons.explore_off_outlined,
      title: 'No public recommendations right now',
      detail: 'Your saved playlists remain available below.',
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
    RecommendedPlaylistStage.content => _DailyRecommendationContent(
      key: const ValueKey('home-recommendations-section'),
      items: controller.playlists.take(4).toList(growable: false),
      compact: compact,
      onSelected: onSelected,
      lastOpened: lastOpened,
      returnFocusNode: returnFocusNode,
    ),
  };
}

class _DailyRecommendationContent extends StatelessWidget {
  const _DailyRecommendationContent({
    required this.items,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
    super.key,
  });

  final List<RecommendedPlaylistSummary> items;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;

  bool _focusMatches(RecommendedPlaylistSummary playlist) =>
      lastOpened?.providerId == playlist.providerId &&
      lastOpened?.opaqueId == playlist.opaqueId;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return SizedBox(
        height: 230,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: MusicSpacing.contentGap),
          itemBuilder: (context, index) {
            final item = items[index];
            return index == 0
                ? _FeaturedRecommendationCard(
                    playlist: item,
                    width: 284,
                    itemKey: const ValueKey('home-recommendation-0'),
                    onSelected: onSelected,
                    focusNode: _focusMatches(item) ? returnFocusNode : null,
                  )
                : _PlaylistArtworkCard<RecommendedPlaylistSummary>(
                    width: 152,
                    item: item,
                    itemKey: ValueKey('home-recommendation-$index'),
                    title: (playlist) => playlist.title,
                    artworkUri: (playlist) => playlist.artworkUri,
                    detail: _recommendationDetail,
                    semanticLabel: _recommendationSemanticLabel,
                    placeholderIcon: Icons.queue_music_rounded,
                    onSelected: onSelected,
                    focusNode: _focusMatches(item) ? returnFocusNode : null,
                  );
          },
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final featuredWidth = (constraints.maxWidth * 0.37).clamp(380.0, 470.0);
        final secondaryItems = items.skip(1).toList(growable: false);
        return SizedBox(
          height: 230,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FeaturedRecommendationCard(
                playlist: items.first,
                width: featuredWidth,
                itemKey: const ValueKey('home-recommendation-0'),
                onSelected: onSelected,
                focusNode: _focusMatches(items.first) ? returnFocusNode : null,
              ),
              if (secondaryItems.isNotEmpty) ...[
                const SizedBox(width: MusicSpacing.contentGap),
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: secondaryItems.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: MusicSpacing.contentGap),
                    itemBuilder: (context, index) {
                      final item = secondaryItems[index];
                      return _PlaylistArtworkCard<RecommendedPlaylistSummary>(
                        width: 172,
                        item: item,
                        itemKey: ValueKey('home-recommendation-${index + 1}'),
                        title: (playlist) => playlist.title,
                        artworkUri: (playlist) => playlist.artworkUri,
                        detail: _recommendationDetail,
                        semanticLabel: _recommendationSemanticLabel,
                        placeholderIcon: Icons.queue_music_rounded,
                        onSelected: onSelected,
                        focusNode: _focusMatches(item) ? returnFocusNode : null,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _FeaturedRecommendationCard extends StatelessWidget {
  const _FeaturedRecommendationCard({
    required this.playlist,
    required this.width,
    required this.itemKey,
    required this.onSelected,
    required this.focusNode,
  });

  final RecommendedPlaylistSummary playlist;
  final double width;
  final Key itemKey;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final artworkWidth = width < 320 ? 136.0 : 190.0;
    return SizedBox(
      width: width,
      child: Focus(
        focusNode: focusNode,
        child: Semantics(
          button: true,
          label: _recommendationSemanticLabel(playlist),
          excludeSemantics: true,
          onTap: () => onSelected(playlist),
          child: Material(
            color: colors.surfaceContainerHigh,
            borderRadius: MusicRadii.content,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: itemKey,
              onTap: () => onSelected(playlist),
              child: Row(
                children: [
                  SizedBox(
                    width: artworkWidth,
                    height: double.infinity,
                    child: _HomeArtwork(
                      uri: playlist.artworkUri,
                      placeholderIcon: Icons.auto_awesome_rounded,
                      radius: BorderRadius.zero,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(MusicSpacing.contentGap),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'PUBLIC PICK',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            playlist.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _recommendationDetail(playlist),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 14),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: colors.primary,
                          ),
                        ],
                      ),
                    ),
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
    UserLibraryStage.loading => _HomeLoadingShelf(
      key: const ValueKey('home-library-loading'),
      compact: compact,
      semanticLabel: 'Loading your playlists',
    ),
    UserLibraryStage.empty => _HomeInlineState(
      key: const ValueKey('home-library-empty'),
      icon: Icons.library_music_outlined,
      title: 'Your playlist library is empty',
      detail: 'Open Library to browse favorite Albums and Artists.',
      action: FilledButton.tonal(
        onPressed: onOpenLibrary,
        child: const Text('Open library'),
      ),
    ),
    UserLibraryStage.error => _HomeInlineState(
      key: const ValueKey('home-library-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load your playlists',
      detail: 'Public recommendations and Search are still available.',
      liveRegion: true,
      action: controller.canRetry
          ? FilledButton.tonal(
              onPressed: controller.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    UserLibraryStage.content => _PlaylistShelf<UserPlaylistSummary>(
      key: const ValueKey('home-library-section'),
      layoutKey: const ValueKey('home-library-shelf'),
      items: controller.playlists.take(compact ? 6 : 8).toList(growable: false),
      compact: compact,
      title: (playlist) => playlist.title,
      artworkUri: (playlist) => playlist.artworkUri,
      detail: (playlist) => playlist.trackCount == null
          ? 'Saved playlist'
          : '${playlist.trackCount} tracks',
      semanticLabel: (playlist) => playlist.trackCount == null
          ? '${playlist.title}, saved playlist'
          : '${playlist.title}, ${playlist.trackCount} tracks',
      itemKey: (index) => ValueKey('home-library-playlist-$index'),
      onSelected: onSelected,
      focusNode: (playlist) =>
          lastOpened?.providerId == playlist.providerId &&
              lastOpened?.opaqueId == playlist.opaqueId
          ? returnFocusNode
          : null,
      placeholderIcon: Icons.library_music_rounded,
    ),
    UserLibraryStage.authenticationRequired ||
    UserLibraryStage.credentialRejected => const SizedBox.shrink(),
  };
}

class _MoreRecommendationsSection extends StatelessWidget {
  const _MoreRecommendationsSection({
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
  Widget build(BuildContext context) {
    if (controller.stage != RecommendedPlaylistStage.content) {
      return const _HomeInlineState(
        key: ValueKey('home-more-recommendations-unavailable'),
        icon: Icons.queue_music_outlined,
        title: 'More recommendations aren’t available',
        detail: 'The primary recommendation state is shown above.',
      );
    }
    final items = controller.playlists.skip(4).take(8).toList(growable: false);
    if (items.isEmpty) {
      return const _HomeInlineState(
        key: ValueKey('home-more-recommendations-empty'),
        icon: Icons.queue_music_outlined,
        title: 'No additional playlists right now',
        detail: 'The available public recommendations are shown above.',
      );
    }
    return _PlaylistShelf<RecommendedPlaylistSummary>(
      key: const ValueKey('home-public-playlists-section'),
      layoutKey: const ValueKey('home-public-playlists-shelf'),
      items: items,
      compact: compact,
      title: (playlist) => playlist.title,
      artworkUri: (playlist) => playlist.artworkUri,
      detail: _recommendationDetail,
      semanticLabel: _recommendationSemanticLabel,
      itemKey: (index) => ValueKey('home-recommendation-${index + 4}'),
      onSelected: onSelected,
      focusNode: (playlist) =>
          lastOpened?.providerId == playlist.providerId &&
              lastOpened?.opaqueId == playlist.opaqueId
          ? returnFocusNode
          : null,
      placeholderIcon: Icons.queue_music_rounded,
    );
  }
}

class _PlaylistShelf<T> extends StatelessWidget {
  const _PlaylistShelf({
    required this.layoutKey,
    required this.items,
    required this.compact,
    required this.title,
    required this.artworkUri,
    required this.detail,
    required this.semanticLabel,
    required this.itemKey,
    required this.onSelected,
    required this.focusNode,
    required this.placeholderIcon,
    super.key,
  });

  final Key layoutKey;
  final List<T> items;
  final bool compact;
  final String Function(T item) title;
  final String? Function(T item) artworkUri;
  final String Function(T item) detail;
  final String Function(T item) semanticLabel;
  final Key Function(int index) itemKey;
  final ValueChanged<T> onSelected;
  final FocusNode? Function(T item) focusNode;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 152.0 : 172.0;
    return SizedBox(
      key: layoutKey,
      height: width + 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: MusicSpacing.contentGap),
        itemBuilder: (context, index) => _PlaylistArtworkCard<T>(
          width: width,
          item: items[index],
          itemKey: itemKey(index),
          title: title,
          artworkUri: artworkUri,
          detail: detail,
          semanticLabel: semanticLabel,
          placeholderIcon: placeholderIcon,
          onSelected: onSelected,
          focusNode: focusNode(items[index]),
        ),
      ),
    );
  }
}

class _PlaylistArtworkCard<T> extends StatelessWidget {
  const _PlaylistArtworkCard({
    required this.width,
    required this.item,
    required this.itemKey,
    required this.title,
    required this.artworkUri,
    required this.detail,
    required this.semanticLabel,
    required this.placeholderIcon,
    required this.onSelected,
    required this.focusNode,
  });

  final double width;
  final T item;
  final Key itemKey;
  final String Function(T item) title;
  final String? Function(T item) artworkUri;
  final String Function(T item) detail;
  final String Function(T item) semanticLabel;
  final IconData placeholderIcon;
  final ValueChanged<T> onSelected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Focus(
      focusNode: focusNode,
      child: Semantics(
        button: true,
        label: semanticLabel(item),
        excludeSemantics: true,
        onTap: () => onSelected(item),
        child: InkWell(
          key: itemKey,
          borderRadius: MusicRadii.content,
          onTap: () => onSelected(item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: width,
                child: _HomeArtwork(
                  uri: artworkUri(item),
                  placeholderIcon: placeholderIcon,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                title(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
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
}

class _UnavailableHomeSection extends StatelessWidget {
  const _UnavailableHomeSection({
    required this.icon,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: '$message Unavailable.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(MusicSpacing.contentGap),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: MusicRadii.content,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: MusicRadii.control,
              ),
              child: Icon(icon, color: colors.onSurfaceVariant),
            ),
            const SizedBox(width: MusicSpacing.contentGap),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: MusicSpacing.itemGap),
            Text(
              'Unavailable',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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

class _DailyRecommendationLoading extends StatelessWidget {
  const _DailyRecommendationLoading({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading Home recommendations',
    child: SizedBox(
      height: 230,
      child: Row(
        children: [
          Container(
            width: compact ? 284 : 430,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: MusicRadii.content,
            ),
          ),
          const SizedBox(width: MusicSpacing.contentGap),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: MusicSpacing.contentGap),
              itemBuilder: (_, _) => Container(
                width: compact ? 152 : 172,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: MusicRadii.content,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HomeLoadingShelf extends StatelessWidget {
  const _HomeLoadingShelf({
    required this.compact,
    required this.semanticLabel,
    super.key,
  });

  final bool compact;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: SizedBox(
      height: compact ? 210 : 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: compact ? 3 : 7,
        separatorBuilder: (_, _) =>
            const SizedBox(width: MusicSpacing.contentGap),
        itemBuilder: (_, _) => Container(
          width: compact ? 152 : 172,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: MusicRadii.content,
          ),
        ),
      ),
    ),
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

String _recommendationDetail(RecommendedPlaylistSummary playlist) =>
    playlist.trackCount == null
    ? 'QQ Music playlist'
    : '${playlist.trackCount} tracks';

String _recommendationSemanticLabel(RecommendedPlaylistSummary playlist) =>
    playlist.trackCount == null
    ? '${playlist.title}, QQ Music playlist'
    : '${playlist.title}, ${playlist.trackCount} tracks';
