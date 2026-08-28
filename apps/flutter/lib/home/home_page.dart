import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/music_track_tile.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/home_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    required this.homeController,
    required this.recommendationController,
    required this.queuePlaybackController,
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onOpenRecommendation,
    this.lastOpenedRecommendation,
    this.recommendationReturnFocusNode,
    super.key,
  });

  final HomeController homeController;
  final RecommendedPlaylistController recommendationController;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final ValueChanged<RecommendedPlaylistSummary> onOpenRecommendation;
  final RecommendedPlaylistSummary? lastOpenedRecommendation;
  final FocusNode? recommendationReturnFocusNode;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      homeController,
      recommendationController,
      queuePlaybackController,
    ]),
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
                        homeController.account == null
                            ? 'For you today'
                            : 'For ${homeController.account!.displayName} today',
                        key: const ValueKey('home-heading'),
                        style:
                            (compact
                                    ? Theme.of(context).textTheme.headlineSmall
                                    : Theme.of(context)
                                          .textTheme
                                          .headlineMedium)
                                ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Personalized QQ Music picks, grounded in your account.',
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
                    const SizedBox(height: MusicSpacing.contentGap),
                    _DailyRecommendationSection(
                      homeController: homeController,
                      controller: recommendationController,
                      compact: compact,
                      onSelected: onOpenRecommendation,
                      lastOpened: lastOpenedRecommendation,
                      returnFocusNode: recommendationReturnFocusNode,
                    ),
                    if (compact) ...[
                      const SizedBox(height: MusicSpacing.contentGap),
                      _CompactHomeActions(
                        onOpenDiscover: onOpenDiscover,
                        onOpenLibrary: onOpenLibrary,
                      ),
                    ],
                    const SizedBox(height: MusicSpacing.pageWide),
                    _HomeSectionHeader(
                      titleKey: const ValueKey('home-library-heading'),
                      title: 'Your playlist treasures',
                      supportingText: 'Personalized playlists from QQ Music',
                      actionKey: const ValueKey('home-open-library'),
                      actionLabel: 'Open library',
                      onAction: onOpenLibrary,
                      compact: compact,
                    ),
                    const SizedBox(height: MusicSpacing.contentGap),
                    _PersonalizedPlaylistSection(
                      controller: homeController,
                      compact: compact,
                      onSelected: onOpenRecommendation,
                      lastOpened: lastOpenedRecommendation,
                      returnFocusNode: recommendationReturnFocusNode,
                      onOpenLibrary: onOpenLibrary,
                    ),
                    const SizedBox(height: MusicSpacing.pageWide),
                    _HomeSectionHeader(
                      titleKey: const ValueKey('home-programs-heading'),
                      title: 'Popular programs',
                      supportingText: 'Editorial and spoken-audio picks',
                      compact: compact,
                    ),
                    const SizedBox(height: MusicSpacing.contentGap),
                    const _UnavailableHomeSection(
                      key: ValueKey('home-hot-programs-unavailable'),
                      icon: Icons.podcasts_outlined,
                      message: 'Popular programs aren’t available through the verified client data yet.',
                    ),
                    const SizedBox(height: MusicSpacing.pageWide),
                    _HomeSectionHeader(
                      titleKey: const ValueKey('home-listening-one-heading'),
                      title: 'Songs picked for you',
                      supportingText:
                          'Song recommendations shaped by listening',
                      compact: compact,
                    ),
                    const SizedBox(height: MusicSpacing.contentGap),
                    _PersonalizedTrackSection(
                      controller: homeController,
                      queueController: queuePlaybackController,
                      compact: compact,
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
                    const SizedBox(height: MusicSpacing.contentGap),
                    _MoreRecommendationsSection(
                      controller: recommendationController,
                      skippedItems: homeController.dailyPlaylist == null
                          ? 4
                          : 3,
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
                    const SizedBox(height: MusicSpacing.contentGap),
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
                            ? Theme.of(context).textTheme.titleMedium
                            : Theme.of(context).textTheme.titleLarge)
                        ?.copyWith(fontWeight: FontWeight.w700),
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
    required this.homeController,
    required this.controller,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
  });

  final HomeController homeController;
  final RecommendedPlaylistController controller;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;

  @override
  Widget build(BuildContext context) {
    final daily = homeController.dailyPlaylist;
    final items = <RecommendedPlaylistSummary>[
      ?daily,
      ...controller.playlists.where((item) => !_samePlaylist(item, daily)),
    ].take(4).toList(growable: false);
    if (items.isNotEmpty) {
      return _DailyRecommendationContent(
        key: const ValueKey('home-recommendations-section'),
        items: items,
        dailyPlaylist: daily,
        compact: compact,
        onSelected: onSelected,
        lastOpened: lastOpened,
        returnFocusNode: returnFocusNode,
      );
    }
    if (homeController.dailyStage == HomeResourceStage.loading ||
        controller.stage == RecommendedPlaylistStage.loading) {
      return _DailyRecommendationLoading(compact: compact);
    }
    if (homeController.dailyStage == HomeResourceStage.empty &&
        controller.stage == RecommendedPlaylistStage.empty) {
      return const _HomeInlineState(
        key: ValueKey('home-recommendations-empty'),
        icon: Icons.explore_off_outlined,
        title: 'No recommendations right now',
        detail: 'Your Library and Search remain available.',
      );
    }
    return _HomeInlineState(
      key: const ValueKey('home-recommendations-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Recommendations are unavailable',
      detail: 'Your Library and Search are still available.',
      liveRegion: true,
      action: FilledButton.tonal(
        onPressed: () {
          homeController.retryDaily();
          controller.retry();
        },
        child: const Text('Try again'),
      ),
    );
  }
}

class _DailyRecommendationContent extends StatelessWidget {
  const _DailyRecommendationContent({
    required this.items,
    required this.dailyPlaylist,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
    super.key,
  });

  final List<RecommendedPlaylistSummary> items;
  final RecommendedPlaylistSummary? dailyPlaylist;
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
                    eyebrow: _samePlaylist(item, dailyPlaylist)
                        ? 'DAILY 30'
                        : 'PUBLIC PICK',
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
                eyebrow: _samePlaylist(items.first, dailyPlaylist)
                    ? 'DAILY 30'
                    : 'PUBLIC PICK',
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
    required this.eyebrow,
    required this.width,
    required this.itemKey,
    required this.onSelected,
    required this.focusNode,
  });

  final RecommendedPlaylistSummary playlist;
  final String eyebrow;
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
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
                              eyebrow,
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
                Positioned.fill(
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: itemKey,
                      onTap: () => onSelected(playlist),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonalizedPlaylistSection extends StatelessWidget {
  const _PersonalizedPlaylistSection({
    required this.controller,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
    required this.onOpenLibrary,
  });

  final HomeController controller;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) =>
      switch (controller.personalizedPlaylistsStage) {
        HomeResourceStage.loading => _HomeLoadingShelf(
          key: const ValueKey('home-library-loading'),
          compact: compact,
          semanticLabel: 'Loading your playlists',
        ),
        HomeResourceStage.empty => _HomeInlineState(
          key: const ValueKey('home-library-empty'),
          icon: Icons.library_music_outlined,
          title: 'No personalized playlists right now',
          detail: 'Open Library to browse the playlists you saved.',
          action: FilledButton.tonal(
            onPressed: onOpenLibrary,
            child: const Text('Open library'),
          ),
        ),
        HomeResourceStage.error => _HomeInlineState(
          key: const ValueKey('home-library-error'),
          icon: Icons.cloud_off_rounded,
          title: 'Couldn’t load personalized playlists',
          detail: 'Public recommendations and Search are still available.',
          liveRegion: true,
          action: FilledButton.tonal(
            onPressed: controller.retryPersonalizedPlaylists,
            child: const Text('Try again'),
          ),
        ),
        HomeResourceStage.content => _PlaylistShelf<RecommendedPlaylistSummary>(
          key: const ValueKey('home-library-section'),
          layoutKey: const ValueKey('home-library-shelf'),
          items: controller.personalizedPlaylists
              .take(compact ? 6 : 8)
              .toList(growable: false),
          compact: compact,
          title: (playlist) => playlist.title,
          artworkUri: (playlist) => playlist.artworkUri,
          detail: (playlist) => playlist.trackCount == null
              ? 'Personalized playlist'
              : '${playlist.trackCount} tracks',
          semanticLabel: (playlist) => playlist.trackCount == null
              ? '${playlist.title}, personalized playlist'
              : '${playlist.title}, ${playlist.trackCount} tracks',
          itemKey: (index) => ValueKey('home-library-playlist-$index'),
          onSelected: onSelected,
          focusNode: (playlist) =>
              lastOpened?.providerId == playlist.providerId &&
                  lastOpened?.opaqueId == playlist.opaqueId
              ? returnFocusNode
              : null,
          placeholderIcon: Icons.auto_awesome_rounded,
        ),
      };
}

class _CompactHomeActions extends StatelessWidget {
  const _CompactHomeActions({
    required this.onOpenDiscover,
    required this.onOpenLibrary,
  });

  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: FilledButton.tonalIcon(
          key: const ValueKey('home-compact-open-discover'),
          onPressed: onOpenDiscover,
          icon: const Icon(Icons.explore_outlined),
          label: const Text('Discover'),
        ),
      ),
      const SizedBox(width: MusicSpacing.itemGap),
      Expanded(
        child: FilledButton.tonalIcon(
          key: const ValueKey('home-compact-open-library'),
          onPressed: onOpenLibrary,
          icon: const Icon(Icons.library_music_outlined),
          label: const Text('Library'),
        ),
      ),
    ],
  );
}

class _PersonalizedTrackSection extends StatelessWidget {
  const _PersonalizedTrackSection({
    required this.controller,
    required this.queueController,
    required this.compact,
  });

  final HomeController controller;
  final QueuePlaybackController queueController;
  final bool compact;

  @override
  Widget build(BuildContext context) =>
      switch (controller.personalizedTracksStage) {
        HomeResourceStage.loading => const _HomeTrackLoading(),
        HomeResourceStage.empty => const _HomeInlineState(
          key: ValueKey('home-personalized-tracks-empty'),
          icon: Icons.music_note_outlined,
          title: 'No personalized songs right now',
          detail: 'Public playlists and your Library remain available.',
        ),
        HomeResourceStage.error => _HomeInlineState(
          key: const ValueKey('home-personalized-tracks-error'),
          icon: Icons.cloud_off_rounded,
          title: 'Couldn’t load personalized songs',
          detail: 'Other Home sections are still available.',
          liveRegion: true,
          action: FilledButton.tonal(
            onPressed: controller.retryPersonalizedTracks,
            child: const Text('Try again'),
          ),
        ),
        HomeResourceStage.content => _PersonalizedTrackContent(
          tracks: controller.personalizedTracks.take(6).toList(growable: false),
          queueController: queueController,
          compact: compact,
        ),
      };
}

class _PersonalizedTrackContent extends StatelessWidget {
  const _PersonalizedTrackContent({
    required this.tracks,
    required this.queueController,
    required this.compact,
  });

  final List<PlaylistTrackSummary> tracks;
  final QueuePlaybackController queueController;
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = compact || constraints.maxWidth < 820 ? 1 : 2;
      final width = columns == 1
          ? constraints.maxWidth
          : (constraints.maxWidth - MusicSpacing.contentGap) / 2;
      return Wrap(
        key: const ValueKey('home-personalized-tracks'),
        spacing: MusicSpacing.contentGap,
        runSpacing: 2,
        children: [
          for (var index = 0; index < tracks.length; index++)
            SizedBox(
              width: width,
              child: _HomeTrackTile(
                track: tracks[index],
                position: index + 1,
                desktop: columns > 1,
                playing: _sameTrack(queueController.current, tracks[index]),
                onPlay: () => queueController.replaceAndPlay(tracks, index),
                onQueue: () => queueController.push(tracks[index]),
              ),
            ),
        ],
      );
    },
  );
}

class _HomeTrackTile extends StatelessWidget {
  const _HomeTrackTile({
    required this.track,
    required this.position,
    required this.desktop,
    required this.playing,
    required this.onPlay,
    required this.onQueue,
  });

  final PlaylistTrackSummary track;
  final int position;
  final bool desktop;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    decoration: BoxDecoration(
      color: playing
          ? Theme.of(context).colorScheme.secondaryContainer
          : Colors.transparent,
      borderRadius: MusicRadii.control,
    ),
    child: MusicTrackTile(
      track: track,
      position: position,
      desktop: desktop,
      onPlay: onPlay,
      onQueue: onQueue,
      itemKey: ValueKey('home-personalized-track-$position'),
      queueKey: ValueKey('home-personalized-track-queue-$position'),
    ),
  );
}

class _HomeTrackLoading extends StatelessWidget {
  const _HomeTrackLoading();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading personalized songs',
    child: Column(
      children: [
        for (var index = 0; index < 3; index++) ...[
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: MusicRadii.control,
            ),
          ),
          if (index < 2) const SizedBox(height: 2),
        ],
      ],
    ),
  );
}

class _MoreRecommendationsSection extends StatelessWidget {
  const _MoreRecommendationsSection({
    required this.controller,
    required this.skippedItems,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
  });

  final RecommendedPlaylistController controller;
  final int skippedItems;
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
    final items = controller.playlists
        .skip(skippedItems)
        .take(8)
        .toList(growable: false);
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
      itemKey: (index) =>
          ValueKey('home-recommendation-${index + skippedItems}'),
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
        child: Stack(
          children: [
            Column(
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
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: itemKey,
                  borderRadius: MusicRadii.content,
                  onTap: () => onSelected(item),
                ),
              ),
            ),
          ],
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

bool _samePlaylist(
  RecommendedPlaylistSummary playlist,
  RecommendedPlaylistSummary? other,
) =>
    other != null &&
    playlist.providerId == other.providerId &&
    playlist.opaqueId == other.opaqueId;

bool _sameTrack(PlaylistTrackSummary? track, PlaylistTrackSummary other) =>
    track != null &&
    track.providerId == other.providerId &&
    track.opaqueId == other.opaqueId;
