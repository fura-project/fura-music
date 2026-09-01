import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/discover/new_song_controller.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/radar_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/home_controller.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

abstract final class _HomeGeometry {
  static const double compactBreakpoint = 600;
  static const double widePadding = 24;
  static const double compactPadding = 16;
  static const double sectionGap = 32;
  static const double itemGap = 16;
  static const double wideHeroHeight = 280;
  static const double compactHeroHeight = 256;
  static const double compactShelfWidth = 136;
  static const double wideShelfMinWidth = 136;
  static const double wideShelfMaxWidth = 164;
  static const double trackRowHeight = 60;
  static const double trackArtworkSize = 44;
  static const BorderRadius heroRadius = BorderRadius.all(Radius.circular(12));
  static const BorderRadius artworkRadius = BorderRadius.all(
    Radius.circular(8),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({
    required this.homeController,
    required this.recommendationController,
    required this.guestNewSongController,
    required this.radarController,
    required this.queuePlaybackController,
    required this.authenticated,
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onAccountAction,
    required this.onOpenRecommendation,
    this.lastOpenedRecommendation,
    this.recommendationReturnFocusNode,
    super.key,
  });

  final HomeController homeController;
  final RecommendedPlaylistController recommendationController;
  final NewSongController guestNewSongController;
  final RadarController radarController;
  final QueuePlaybackController queuePlaybackController;
  final bool authenticated;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final VoidCallback onAccountAction;
  final ValueChanged<RecommendedPlaylistSummary> onOpenRecommendation;
  final RecommendedPlaylistSummary? lastOpenedRecommendation;
  final FocusNode? recommendationReturnFocusNode;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      homeController,
      recommendationController,
      guestNewSongController,
      radarController,
      queuePlaybackController,
    ]),
    builder: (context, _) => SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _HomeGeometry.compactBreakpoint) {
            return _HomeCompactLayout(
              homeController: homeController,
              recommendationController: recommendationController,
              guestNewSongController: guestNewSongController,
              radarController: radarController,
              queuePlaybackController: queuePlaybackController,
              authenticated: authenticated,
              onOpenDiscover: onOpenDiscover,
              onOpenLibrary: onOpenLibrary,
              onAccountAction: onAccountAction,
              onOpenRecommendation: onOpenRecommendation,
              lastOpenedRecommendation: lastOpenedRecommendation,
              recommendationReturnFocusNode: recommendationReturnFocusNode,
            );
          }
          return _HomeWideLayout(
            homeController: homeController,
            recommendationController: recommendationController,
            guestNewSongController: guestNewSongController,
            radarController: radarController,
            queuePlaybackController: queuePlaybackController,
            authenticated: authenticated,
            onOpenDiscover: onOpenDiscover,
            onOpenLibrary: onOpenLibrary,
            onOpenRecommendation: onOpenRecommendation,
            lastOpenedRecommendation: lastOpenedRecommendation,
            recommendationReturnFocusNode: recommendationReturnFocusNode,
          );
        },
      ),
    ),
  );
}

class _HomeWideLayout extends StatelessWidget {
  const _HomeWideLayout({
    required this.homeController,
    required this.recommendationController,
    required this.guestNewSongController,
    required this.radarController,
    required this.queuePlaybackController,
    required this.authenticated,
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onOpenRecommendation,
    required this.lastOpenedRecommendation,
    required this.recommendationReturnFocusNode,
  });

  final HomeController homeController;
  final RecommendedPlaylistController recommendationController;
  final NewSongController guestNewSongController;
  final RadarController radarController;
  final QueuePlaybackController queuePlaybackController;
  final bool authenticated;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final ValueChanged<RecommendedPlaylistSummary> onOpenRecommendation;
  final RecommendedPlaylistSummary? lastOpenedRecommendation;
  final FocusNode? recommendationReturnFocusNode;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const PageStorageKey('home-scroll'),
    padding: const EdgeInsets.fromLTRB(
      _HomeGeometry.widePadding,
      _HomeGeometry.widePadding,
      _HomeGeometry.widePadding,
      128,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HomeSemanticHeading(),
        _DailyRecommendationSection(
          homeController: homeController,
          controller: recommendationController,
          guestNewSongController: guestNewSongController,
          radarController: radarController,
          queueController: queuePlaybackController,
          authenticated: authenticated,
          compact: false,
          onSelected: onOpenRecommendation,
          lastOpened: lastOpenedRecommendation,
          returnFocusNode: recommendationReturnFocusNode,
        ),
        const SizedBox(height: _HomeGeometry.sectionGap),
        _HomeSectionHeader(
          titleKey: const ValueKey('home-library-heading'),
          title: authenticated
              ? 'Your playlist treasures'
              : 'Popular playlists',
          actionKey: const ValueKey('home-open-library'),
          actionLabel: authenticated ? 'Open library' : 'Browse all',
          onAction: authenticated ? onOpenLibrary : onOpenDiscover,
        ),
        const SizedBox(height: _HomeGeometry.itemGap),
        if (authenticated)
          _PersonalizedPlaylistSection(
            controller: homeController,
            compact: false,
            onSelected: onOpenRecommendation,
            lastOpened: lastOpenedRecommendation,
            returnFocusNode: recommendationReturnFocusNode,
          )
        else
          _GuestPlaylistSection(
            controller: recommendationController,
            compact: false,
            onSelected: onOpenRecommendation,
            lastOpened: lastOpenedRecommendation,
            returnFocusNode: recommendationReturnFocusNode,
          ),
        const SizedBox(height: _HomeGeometry.sectionGap),
        _HomeSectionHeader(
          titleKey: const ValueKey('home-listening-one-heading'),
          title: authenticated ? 'Songs picked for you' : 'New songs',
        ),
        const SizedBox(height: _HomeGeometry.itemGap),
        if (authenticated)
          _PersonalizedTrackSection(
            controller: homeController,
            queueController: queuePlaybackController,
            compact: false,
          )
        else
          _GuestNewSongSection(
            controller: guestNewSongController,
            queueController: queuePlaybackController,
            compact: false,
          ),
        if (authenticated) ...[
          const SizedBox(height: _HomeGeometry.sectionGap),
          _HomeSectionHeader(
            titleKey: const ValueKey('home-recommended-playlists-heading'),
            title: 'Recommended playlists',
            actionKey: const ValueKey('home-open-more-recommendations'),
            actionLabel: 'See all',
            onAction: onOpenDiscover,
          ),
          const SizedBox(height: _HomeGeometry.itemGap),
          _MoreRecommendationsSection(
            controller: recommendationController,
            skippedItems: 1,
            compact: false,
            onSelected: onOpenRecommendation,
            lastOpened: lastOpenedRecommendation,
            returnFocusNode: recommendationReturnFocusNode,
          ),
        ],
        const SizedBox(height: _HomeGeometry.sectionGap),
        const _HomeSectionHeader(
          titleKey: ValueKey('home-listening-two-heading'),
          title: 'More from your listening',
        ),
        const SizedBox(height: _HomeGeometry.itemGap),
        _RelatedTrackSection(
          controller: homeController,
          queueController: queuePlaybackController,
          compact: false,
        ),
      ],
    ),
  );
}

class _HomeCompactLayout extends StatelessWidget {
  const _HomeCompactLayout({
    required this.homeController,
    required this.recommendationController,
    required this.guestNewSongController,
    required this.radarController,
    required this.queuePlaybackController,
    required this.authenticated,
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onAccountAction,
    required this.onOpenRecommendation,
    required this.lastOpenedRecommendation,
    required this.recommendationReturnFocusNode,
  });

  final HomeController homeController;
  final RecommendedPlaylistController recommendationController;
  final NewSongController guestNewSongController;
  final RadarController radarController;
  final QueuePlaybackController queuePlaybackController;
  final bool authenticated;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final VoidCallback onAccountAction;
  final ValueChanged<RecommendedPlaylistSummary> onOpenRecommendation;
  final RecommendedPlaylistSummary? lastOpenedRecommendation;
  final FocusNode? recommendationReturnFocusNode;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const PageStorageKey('home-scroll'),
    padding: const EdgeInsets.only(bottom: 140),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CompactCategoryBar(
          onOpenDiscover: onOpenDiscover,
          authenticated: authenticated,
          onAccountAction: onAccountAction,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            _HomeGeometry.compactPadding,
            _HomeGeometry.itemGap,
            _HomeGeometry.compactPadding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DailyRecommendationSection(
                homeController: homeController,
                controller: recommendationController,
                guestNewSongController: guestNewSongController,
                radarController: radarController,
                queueController: queuePlaybackController,
                authenticated: authenticated,
                compact: true,
                onSelected: onOpenRecommendation,
                lastOpened: lastOpenedRecommendation,
                returnFocusNode: recommendationReturnFocusNode,
              ),
              const SizedBox(height: 24),
              _CompactHomeActions(
                onOpenDiscover: onOpenDiscover,
                onOpenLibrary: onOpenLibrary,
              ),
              const SizedBox(height: _HomeGeometry.sectionGap),
              _HomeSectionHeader(
                titleKey: const ValueKey('home-library-heading'),
                title: authenticated
                    ? 'Your playlist treasures'
                    : 'Popular playlists',
                actionKey: const ValueKey('home-open-library'),
                actionLabel: authenticated ? 'Library' : 'Browse all',
                onAction: authenticated ? onOpenLibrary : onOpenDiscover,
                compact: true,
              ),
              const SizedBox(height: _HomeGeometry.itemGap),
              if (authenticated)
                _PersonalizedPlaylistSection(
                  controller: homeController,
                  compact: true,
                  onSelected: onOpenRecommendation,
                  lastOpened: lastOpenedRecommendation,
                  returnFocusNode: recommendationReturnFocusNode,
                )
              else
                _GuestPlaylistSection(
                  controller: recommendationController,
                  compact: true,
                  onSelected: onOpenRecommendation,
                  lastOpened: lastOpenedRecommendation,
                  returnFocusNode: recommendationReturnFocusNode,
                ),
              const SizedBox(height: _HomeGeometry.sectionGap),
              _HomeSectionHeader(
                titleKey: const ValueKey('home-listening-one-heading'),
                title: authenticated ? 'Songs picked for you' : 'New songs',
                compact: true,
              ),
              const SizedBox(height: _HomeGeometry.itemGap),
              if (authenticated)
                _PersonalizedTrackSection(
                  controller: homeController,
                  queueController: queuePlaybackController,
                  compact: true,
                )
              else
                _GuestNewSongSection(
                  controller: guestNewSongController,
                  queueController: queuePlaybackController,
                  compact: true,
                ),
              if (authenticated) ...[
                const SizedBox(height: _HomeGeometry.sectionGap),
                _HomeSectionHeader(
                  titleKey: const ValueKey(
                    'home-recommended-playlists-heading',
                  ),
                  title: 'Recommended playlists',
                  actionKey: const ValueKey('home-open-more-recommendations'),
                  actionLabel: 'See all',
                  onAction: onOpenDiscover,
                  compact: true,
                ),
                const SizedBox(height: _HomeGeometry.itemGap),
                _MoreRecommendationsSection(
                  controller: recommendationController,
                  skippedItems: 1,
                  compact: true,
                  onSelected: onOpenRecommendation,
                  lastOpened: lastOpenedRecommendation,
                  returnFocusNode: recommendationReturnFocusNode,
                ),
              ],
              const SizedBox(height: _HomeGeometry.sectionGap),
              const _HomeSectionHeader(
                titleKey: ValueKey('home-listening-two-heading'),
                title: 'More from your listening',
                compact: true,
              ),
              const SizedBox(height: _HomeGeometry.itemGap),
              _RelatedTrackSection(
                controller: homeController,
                queueController: queuePlaybackController,
                compact: true,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HomeSemanticHeading extends StatelessWidget {
  const _HomeSemanticHeading();

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('home-heading'),
    header: true,
    label: 'Home recommendations',
    child: const SizedBox.shrink(),
  );
}

class _CompactCategoryBar extends StatelessWidget {
  const _CompactCategoryBar({
    required this.onOpenDiscover,
    required this.authenticated,
    required this.onAccountAction,
  });

  final VoidCallback onOpenDiscover;
  final bool authenticated;
  final VoidCallback onAccountAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _CompactCategoryItem(
              key: const ValueKey('home-heading'),
              selected: true,
              label: 'Recommend',
              colors: colors,
            ),
            _CompactCategoryItem(
              label: 'Music',
              colors: colors,
              onPressed: onOpenDiscover,
            ),
            _CompactCategoryItem(
              label: 'Audiobooks',
              colors: colors,
              unavailableReason: 'Audiobooks are not available',
            ),
            _CompactCategoryItem(
              label: 'Podcasts',
              colors: colors,
              unavailableReason:
                  'Podcasts are outside the current product scope',
            ),
            IconButton(
              key: ValueKey(authenticated ? 'sign-out' : 'sign-in'),
              onPressed: onAccountAction,
              tooltip: authenticated ? 'Sign out' : 'Sign in to QQ Music',
              icon: Icon(
                authenticated ? Icons.more_vert_rounded : Icons.login_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactCategoryItem extends StatelessWidget {
  const _CompactCategoryItem({
    required this.label,
    required this.colors,
    this.selected = false,
    this.onPressed,
    this.unavailableReason,
    super.key,
  });

  final String label;
  final ColorScheme colors;
  final bool selected;
  final VoidCallback? onPressed;
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      header: selected,
      selected: selected,
      enabled: selected || onPressed != null,
      label: unavailableReason == null ? label : '$label, unavailable',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected || onPressed != null
                      ? colors.onSurface
                      : colors.onSurfaceVariant.withValues(alpha: 0.55),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 28,
                height: 3,
                child: selected
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
    return Expanded(
      child: unavailableReason == null
          ? content
          : Tooltip(message: unavailableReason!, child: content),
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    required this.titleKey,
    required this.title,
    this.compact = false,
    this.actionKey,
    this.actionLabel,
    this.onAction,
  });

  final Key titleKey;
  final String title;
  final bool compact;
  final Key? actionKey;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
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
            style: compact
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.titleLarge,
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
  );
}

class _DailyRecommendationSection extends StatelessWidget {
  const _DailyRecommendationSection({
    required this.homeController,
    required this.controller,
    required this.guestNewSongController,
    required this.radarController,
    required this.queueController,
    required this.authenticated,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
  });

  final HomeController homeController;
  final RecommendedPlaylistController controller;
  final NewSongController guestNewSongController;
  final RadarController radarController;
  final QueuePlaybackController queueController;
  final bool authenticated;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;

  @override
  Widget build(BuildContext context) {
    final daily = homeController.dailyPlaylist;
    final featured =
        controller.stage == RecommendedPlaylistStage.content &&
            controller.playlists.isNotEmpty
        ? controller.playlists.first
        : null;
    return _DailyRecommendationContent(
      key: const ValueKey('home-recommendations-section'),
      featuredPlaylist: featured,
      guestPopularPlaylist:
          controller.stage == RecommendedPlaylistStage.content &&
              controller.playlists.length > 1
          ? controller.playlists[1]
          : null,
      publicStage: controller.stage,
      guestNewSongController: guestNewSongController,
      dailyPlaylist: daily,
      dailyStage: homeController.dailyStage,
      radarController: radarController,
      queueController: queueController,
      authenticated: authenticated,
      compact: compact,
      onSelected: onSelected,
      onRetryPublic: controller.retry,
      onRetryDaily: homeController.retryDaily,
      lastOpened: lastOpened,
      returnFocusNode: returnFocusNode,
    );
  }
}

class _DailyRecommendationContent extends StatelessWidget {
  const _DailyRecommendationContent({
    required this.featuredPlaylist,
    required this.guestPopularPlaylist,
    required this.publicStage,
    required this.guestNewSongController,
    required this.dailyPlaylist,
    required this.dailyStage,
    required this.radarController,
    required this.queueController,
    required this.authenticated,
    required this.compact,
    required this.onSelected,
    required this.onRetryPublic,
    required this.onRetryDaily,
    required this.lastOpened,
    required this.returnFocusNode,
    super.key,
  });

  final RecommendedPlaylistSummary? featuredPlaylist;
  final RecommendedPlaylistSummary? guestPopularPlaylist;
  final RecommendedPlaylistStage publicStage;
  final NewSongController guestNewSongController;
  final RecommendedPlaylistSummary? dailyPlaylist;
  final HomeResourceStage dailyStage;
  final RadarController radarController;
  final QueuePlaybackController queueController;
  final bool authenticated;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final VoidCallback onRetryPublic;
  final VoidCallback onRetryDaily;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;

  bool _focusMatches(RecommendedPlaylistSummary playlist) =>
      lastOpened?.providerId == playlist.providerId &&
      lastOpened?.opaqueId == playlist.opaqueId;

  Widget _featuredSlot() {
    final playlist = featuredPlaylist;
    if (playlist != null) {
      return _FeaturedRecommendationCard(
        playlist: playlist,
        eyebrow: "TODAY'S PICK",
        height: compact ? _HomeGeometry.compactHeroHeight : null,
        itemKey: const ValueKey('home-recommendation-0'),
        onSelected: onSelected,
        focusNode: _focusMatches(playlist) ? returnFocusNode : null,
      );
    }
    return _RecommendationSlotState(
      key: const ValueKey('home-recommendation-hero-state'),
      title: "Today's pick",
      detail: _publicStateDetail(publicStage),
      loading: publicStage == RecommendedPlaylistStage.loading,
      onRetry: publicStage == RecommendedPlaylistStage.error
          ? onRetryPublic
          : null,
      compact: compact,
      featured: true,
    );
  }

  Widget _dailySlot() {
    if (!authenticated) {
      final playlist = guestPopularPlaylist;
      if (playlist != null) {
        return compact
            ? _CompactRecommendationCard(
                playlist: playlist,
                eyebrow: 'Popular playlist',
                eyebrowKey: const ValueKey('home-guest-popular-heading'),
                itemKey: const ValueKey('home-guest-popular-playlist'),
                onSelected: onSelected,
                focusNode: _focusMatches(playlist) ? returnFocusNode : null,
              )
            : _WideRecommendationCard(
                playlist: playlist,
                eyebrow: 'Popular playlist',
                eyebrowKey: const ValueKey('home-guest-popular-heading'),
                itemKey: const ValueKey('home-guest-popular-playlist'),
                onSelected: onSelected,
                focusNode: _focusMatches(playlist) ? returnFocusNode : null,
              );
      }
      return _RecommendationSlotState(
        key: const ValueKey('home-guest-popular-state'),
        headingKey: const ValueKey('home-guest-popular-heading'),
        title: 'Popular playlist',
        detail: _publicStateDetail(publicStage),
        loading: publicStage == RecommendedPlaylistStage.loading,
        onRetry: publicStage == RecommendedPlaylistStage.error
            ? onRetryPublic
            : null,
        compact: compact,
      );
    }
    final playlist = dailyPlaylist;
    if (playlist != null) {
      return compact
          ? _CompactRecommendationCard(
              playlist: playlist,
              eyebrow: 'Daily recommendation',
              eyebrowKey: const ValueKey('home-daily-heading'),
              itemKey: const ValueKey('home-daily-recommendation'),
              onSelected: onSelected,
              focusNode: _focusMatches(playlist) ? returnFocusNode : null,
            )
          : _WideRecommendationCard(
              playlist: playlist,
              eyebrow: 'Daily recommendation',
              eyebrowKey: const ValueKey('home-daily-heading'),
              itemKey: const ValueKey('home-daily-recommendation'),
              onSelected: onSelected,
              focusNode: _focusMatches(playlist) ? returnFocusNode : null,
            );
    }
    return _RecommendationSlotState(
      key: const ValueKey('home-daily-recommendation-state'),
      headingKey: const ValueKey('home-daily-heading'),
      title: 'Daily recommendation',
      detail: _dailyStateDetail(dailyStage),
      loading: dailyStage == HomeResourceStage.loading,
      onRetry: dailyStage == HomeResourceStage.error ? onRetryDaily : null,
      compact: compact,
    );
  }

  Widget _radarSlot() {
    if (!authenticated) {
      if (guestNewSongController.stage == NewSongStage.content &&
          guestNewSongController.tracks.isNotEmpty) {
        final tracks = guestNewSongController.tracks;
        return _TrackRecommendationCard(
          track: tracks.first,
          label: 'New songs',
          itemKey: const ValueKey('home-guest-new-song-recommendation'),
          placeholderIcon: Icons.new_releases_outlined,
          compact: compact,
          onPlay: () => unawaited(queueController.replaceAndPlay(tracks, 0)),
        );
      }
      return _RecommendationSlotState(
        key: const ValueKey('home-guest-new-song-state'),
        title: 'New songs',
        detail: _newSongStateDetail(guestNewSongController.stage),
        loading: guestNewSongController.stage == NewSongStage.loading,
        onRetry: guestNewSongController.canRetry
            ? guestNewSongController.retry
            : null,
        compact: compact,
      );
    }
    if (radarController.stage == RadarStage.content &&
        radarController.tracks.isNotEmpty) {
      final tracks = radarController.tracks;
      return _TrackRecommendationCard(
        track: tracks.first,
        label: 'Radar',
        itemKey: const ValueKey('home-radar-recommendation'),
        placeholderIcon: Icons.radar_rounded,
        compact: compact,
        onPlay: () => unawaited(queueController.replaceAndPlay(tracks, 0)),
      );
    }
    return _RecommendationSlotState(
      key: const ValueKey('home-radar-state'),
      title: 'Radar',
      detail: _radarStateDetail(radarController.stage),
      loading: radarController.stage == RadarStage.loading,
      onRetry: radarController.canRetry ? radarController.retry : null,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _featuredSlot(),
          const SizedBox(height: _HomeGeometry.itemGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _dailySlot()),
              const SizedBox(width: _HomeGeometry.itemGap),
              Expanded(child: _radarSlot()),
            ],
          ),
        ],
      );
    }

    return SizedBox(
      height: _HomeGeometry.wideHeroHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: _featuredSlot()),
          const SizedBox(width: _HomeGeometry.itemGap),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _dailySlot()),
                const SizedBox(height: _HomeGeometry.itemGap),
                Expanded(child: _radarSlot()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackRecommendationCard extends StatelessWidget {
  const _TrackRecommendationCard({
    required this.track,
    required this.label,
    required this.itemKey,
    required this.placeholderIcon,
    required this.compact,
    required this.onPlay,
  });

  final PlaylistTrackSummary track;
  final String label;
  final Key itemKey;
  final IconData placeholderIcon;
  final bool compact;
  final VoidCallback onPlay;

  String get _artists =>
      track.artistNames.isEmpty ? 'QQ Music' : track.artistNames.join(' · ');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semanticsLabel = '$label, ${track.title}, $_artists. Play';
    if (compact) {
      return Semantics(
        button: true,
        label: semanticsLabel,
        onTap: onPlay,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _HomeArtwork(
                    uri: track.artworkUri,
                    placeholderIcon: placeholderIcon,
                    radius: _HomeGeometry.heroRadius,
                  ),
                  Positioned.fill(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: itemKey,
                        borderRadius: _HomeGeometry.heroRadius,
                        onTap: onPlay,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onPlay,
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: _HomeGeometry.heroRadius,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: _HomeArtwork(
                      uri: track.artworkUri,
                      placeholderIcon: placeholderIcon,
                      radius: _HomeGeometry.artworkRadius,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _artists,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.play_arrow_rounded, color: colors.primary),
                ],
              ),
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(key: itemKey, onTap: onPlay),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedRecommendationCard extends StatelessWidget {
  const _FeaturedRecommendationCard({
    required this.playlist,
    required this.eyebrow,
    required this.itemKey,
    required this.onSelected,
    required this.focusNode,
    this.height,
  });

  final RecommendedPlaylistSummary playlist;
  final String eyebrow;
  final Key itemKey;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final FocusNode? focusNode;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: Semantics(
        button: true,
        label: _recommendationSemanticLabel(playlist),
        onTap: () => onSelected(playlist),
        child: Material(
          color: colors.surfaceContainerHigh,
          borderRadius: _HomeGeometry.heroRadius,
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _HomeArtwork(
                uri: playlist.artworkUri,
                placeholderIcon: Icons.auto_awesome_rounded,
                radius: BorderRadius.zero,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.scrim.withValues(alpha: 0.04),
                      colors.scrim.withValues(alpha: 0.78),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 24,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            eyebrow,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: colors.inversePrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            playlist.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _recommendationDetail(playlist),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: colors.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: itemKey,
                    focusNode: focusNode,
                    onTap: () => onSelected(playlist),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideRecommendationCard extends StatelessWidget {
  const _WideRecommendationCard({
    required this.playlist,
    required this.itemKey,
    required this.onSelected,
    required this.focusNode,
    this.eyebrow,
    this.eyebrowKey,
  });

  final RecommendedPlaylistSummary playlist;
  final Key itemKey;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final FocusNode? focusNode;
  final String? eyebrow;
  final Key? eyebrowKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: _recommendationSemanticLabel(playlist),
      onTap: () => onSelected(playlist),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: _HomeGeometry.heroRadius,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: _HomeArtwork(
                      uri: playlist.artworkUri,
                      placeholderIcon: Icons.queue_music_rounded,
                      radius: _HomeGeometry.artworkRadius,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null) ...[
                          Text(
                            eyebrow!,
                            key: eyebrowKey,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          playlist.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _recommendationDetail(playlist),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: itemKey,
                  focusNode: focusNode,
                  onTap: () => onSelected(playlist),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactRecommendationCard extends StatelessWidget {
  const _CompactRecommendationCard({
    required this.playlist,
    required this.itemKey,
    required this.onSelected,
    required this.focusNode,
    this.eyebrow,
    this.eyebrowKey,
  });

  final RecommendedPlaylistSummary playlist;
  final Key itemKey;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final FocusNode? focusNode;
  final String? eyebrow;
  final Key? eyebrowKey;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _recommendationSemanticLabel(playlist),
    onTap: () => onSelected(playlist),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _HomeArtwork(
                uri: playlist.artworkUri,
                placeholderIcon: Icons.queue_music_rounded,
                radius: _HomeGeometry.heroRadius,
              ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: itemKey,
                    focusNode: focusNode,
                    borderRadius: _HomeGeometry.heroRadius,
                    onTap: () => onSelected(playlist),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            key: eyebrowKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
        ],
        Text(
          playlist.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    ),
  );
}

class _RecommendationSlotState extends StatelessWidget {
  const _RecommendationSlotState({
    required this.title,
    required this.detail,
    required this.loading,
    required this.onRetry,
    required this.compact,
    this.featured = false,
    this.headingKey,
    super.key,
  });

  final String title;
  final String detail;
  final bool loading;
  final VoidCallback? onRetry;
  final bool compact;
  final bool featured;
  final Key? headingKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = Icon(
      loading
          ? Icons.hourglass_top_rounded
          : onRetry == null
          ? Icons.music_off_outlined
          : Icons.cloud_off_rounded,
      color: colors.onSurfaceVariant,
    );
    final action = onRetry == null
        ? null
        : IconButton(
            tooltip: 'Retry $title',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          );

    if (compact && !featured) {
      return Semantics(
        label: '$title. $detail',
        liveRegion: onRetry != null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Material(
                color: colors.surfaceContainerLow,
                borderRadius: _HomeGeometry.heroRadius,
                child: Center(child: action ?? icon),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              key: headingKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final content = Material(
      color: featured
          ? colors.surfaceContainerHigh
          : colors.surfaceContainerLow,
      borderRadius: _HomeGeometry.heroRadius,
      child: Padding(
        padding: const EdgeInsets.all(_HomeGeometry.itemGap),
        child: Row(
          children: [
            SizedBox.square(
              dimension: featured ? 48 : 44,
              child: Center(child: icon),
            ),
            const SizedBox(width: _HomeGeometry.itemGap),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    key: headingKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: featured
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
    return Semantics(
      label: '$title. $detail',
      liveRegion: onRetry != null,
      child: compact && featured
          ? SizedBox(height: _HomeGeometry.compactHeroHeight, child: content)
          : content,
    );
  }
}

class _GuestPlaylistSection extends StatelessWidget {
  const _GuestPlaylistSection({
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
    return switch (controller.stage) {
      RecommendedPlaylistStage.loading => _HomeLoadingShelf(
        key: const ValueKey('home-guest-playlists-loading'),
        compact: compact,
        semanticLabel: 'Loading public playlists',
      ),
      RecommendedPlaylistStage.empty => const _HomeInlineState(
        key: ValueKey('home-guest-playlists-empty'),
        icon: Icons.queue_music_outlined,
        title: 'No public playlists right now',
        detail: 'QQ Music did not return any public playlist recommendations.',
      ),
      RecommendedPlaylistStage.error => _HomeInlineState(
        key: const ValueKey('home-guest-playlists-error'),
        icon: Icons.cloud_off_outlined,
        title: 'Couldn’t load public playlists',
        detail: _publicStateDetail(controller.stage),
        liveRegion: true,
        action: controller.canRetry
            ? FilledButton.tonal(
                onPressed: controller.retry,
                child: const Text('Try again'),
              )
            : null,
      ),
      RecommendedPlaylistStage.content => _guestPlaylistContent(),
    };
  }

  Widget _guestPlaylistContent() {
    final items = controller.playlists.skip(2).take(6).toList(growable: false);
    if (items.isEmpty) {
      return const _HomeInlineState(
        key: ValueKey('home-guest-playlists-empty'),
        icon: Icons.queue_music_outlined,
        title: 'No additional public playlists right now',
        detail: 'The available public recommendations are shown above.',
      );
    }
    return _PlaylistShelf<RecommendedPlaylistSummary>(
      key: const ValueKey('home-guest-playlists-section'),
      layoutKey: const ValueKey('home-guest-playlists-shelf'),
      items: items,
      compact: compact,
      title: (playlist) => playlist.title,
      artworkUri: (playlist) => playlist.artworkUri,
      semanticLabel: _recommendationSemanticLabel,
      itemKey: (index) => ValueKey('home-guest-playlist-${index + 1}'),
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

class _GuestNewSongSection extends StatelessWidget {
  const _GuestNewSongSection({
    required this.controller,
    required this.queueController,
    required this.compact,
  });

  final NewSongController controller;
  final QueuePlaybackController queueController;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return switch (controller.stage) {
      NewSongStage.loading => _HomeTrackLoading(
        compact: compact,
        semanticLabel: 'Loading public new songs',
      ),
      NewSongStage.empty => const _HomeInlineState(
        key: ValueKey('home-guest-new-songs-empty'),
        icon: Icons.new_releases_outlined,
        title: 'No new songs right now',
        detail: 'QQ Music did not return a public new-song collection.',
      ),
      NewSongStage.error => _HomeInlineState(
        key: const ValueKey('home-guest-new-songs-error'),
        icon: Icons.cloud_off_outlined,
        title: 'Couldn’t load new songs',
        detail: _newSongFailureDetail(controller.failure),
        liveRegion: true,
        action: controller.canRetry
            ? FilledButton.tonal(
                onPressed: controller.retry,
                child: const Text('Try again'),
              )
            : null,
      ),
      NewSongStage.content => _HomeTrackContent(
        tracks: controller.tracks.take(6).toList(growable: false),
        queueController: queueController,
        compact: compact,
        sectionKey: const ValueKey('home-guest-new-songs'),
        itemKeyPrefix: 'home-guest-new-song',
      ),
    };
  }
}

class _PersonalizedPlaylistSection extends StatelessWidget {
  const _PersonalizedPlaylistSection({
    required this.controller,
    required this.compact,
    required this.onSelected,
    required this.lastOpened,
    required this.returnFocusNode,
  });

  final HomeController controller;
  final bool compact;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;
  final RecommendedPlaylistSummary? lastOpened;
  final FocusNode? returnFocusNode;

  @override
  Widget build(BuildContext context) {
    return switch (controller.personalizedPlaylistsStage) {
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
        compactFootprint: true,
      ),
      HomeResourceStage.error => _HomeInlineState(
        key: const ValueKey('home-library-error'),
        icon: Icons.cloud_off_rounded,
        title: _personalizedPlaylistFailureTitle(
          controller.personalizedPlaylistsFailure,
        ),
        detail: _personalizedPlaylistFailureDetail(
          controller.personalizedPlaylistsFailure,
        ),
        liveRegion: true,
        compactFootprint: true,
        action: FilledButton.tonal(
          onPressed: controller.retryPersonalizedPlaylists,
          child: const Text('Try again'),
        ),
      ),
      HomeResourceStage.content => _PlaylistShelf<RecommendedPlaylistSummary>(
        key: const ValueKey('home-library-section'),
        layoutKey: const ValueKey('home-library-shelf'),
        items: controller.personalizedPlaylists.take(6).toList(growable: false),
        compact: compact,
        title: (playlist) => playlist.title,
        artworkUri: (playlist) => playlist.artworkUri,
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
    key: const ValueKey('home-compact-actions'),
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _CompactHomeAction(
        key: const ValueKey('home-compact-open-discover'),
        icon: Icons.explore_outlined,
        label: 'Discover',
        onPressed: onOpenDiscover,
      ),
      _CompactHomeAction(
        icon: Icons.today_outlined,
        label: 'Daily',
        onPressed: onOpenDiscover,
      ),
      _CompactHomeAction(
        icon: Icons.leaderboard_outlined,
        label: 'Rankings',
        onPressed: onOpenDiscover,
      ),
      _CompactHomeAction(
        key: const ValueKey('home-compact-open-library'),
        icon: Icons.library_music_outlined,
        label: 'Library',
        onPressed: onOpenLibrary,
      ),
    ],
  );
}

class _CompactHomeAction extends StatelessWidget {
  const _CompactHomeAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 72,
    child: Column(
      children: [
        IconButton.filledTonal(
          onPressed: onPressed,
          tooltip: label,
          icon: Icon(icon),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    ),
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
  Widget build(BuildContext context) {
    return switch (controller.personalizedTracksStage) {
      HomeResourceStage.loading => _HomeTrackLoading(
        compact: compact,
        semanticLabel: 'Loading personalized songs',
      ),
      HomeResourceStage.empty => const _HomeInlineState(
        key: ValueKey('home-personalized-tracks-empty'),
        icon: Icons.music_note_outlined,
        title: 'No personalized songs right now',
        detail: 'Public playlists and your Library remain available.',
        compactFootprint: true,
      ),
      HomeResourceStage.error => _HomeInlineState(
        key: const ValueKey('home-personalized-tracks-error'),
        icon: Icons.cloud_off_rounded,
        title: 'Couldn’t load personalized songs',
        detail: 'Other Home sections are still available.',
        liveRegion: true,
        compactFootprint: true,
        action: FilledButton.tonal(
          onPressed: controller.retryPersonalizedTracks,
          child: const Text('Try again'),
        ),
      ),
      HomeResourceStage.content => _HomeTrackContent(
        tracks: controller.personalizedTracks.take(6).toList(growable: false),
        queueController: queueController,
        compact: compact,
        sectionKey: const ValueKey('home-personalized-tracks'),
        itemKeyPrefix: 'home-personalized-track',
      ),
    };
  }
}

class _RelatedTrackSection extends StatelessWidget {
  const _RelatedTrackSection({
    required this.controller,
    required this.queueController,
    required this.compact,
  });

  final HomeController controller;
  final QueuePlaybackController queueController;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final seed = controller.relatedSeed;
    return switch (controller.relatedTracksStage) {
      HomeResourceStage.loading => _HomeTrackLoading(
        compact: compact,
        semanticLabel:
            'Loading songs related to ${seed?.title ?? 'the current song'}',
      ),
      HomeResourceStage.empty when seed == null => const _HomeInlineState(
        key: ValueKey('home-related-tracks-no-seed'),
        icon: Icons.music_note_outlined,
        title: 'No recommendation seed yet',
        detail:
            'Personalized songs or your current queue song will appear here.',
        compactFootprint: true,
      ),
      HomeResourceStage.empty => _HomeInlineState(
        key: const ValueKey('home-related-tracks-empty'),
        icon: Icons.music_note_outlined,
        title: 'No related songs right now',
        detail: 'QQ Music returned no related songs for “${seed!.title}”.',
        compactFootprint: true,
      ),
      HomeResourceStage.error => _HomeInlineState(
        key: const ValueKey('home-related-tracks-error'),
        icon: Icons.cloud_off_rounded,
        title: _relatedTracksFailureTitle(controller.relatedTracksFailure),
        detail: _relatedTracksFailureDetail(
          controller.relatedTracksFailure,
          seed,
        ),
        liveRegion: true,
        compactFootprint: true,
        action: seed == null
            ? null
            : FilledButton.tonal(
                onPressed: controller.retryRelatedTracks,
                child: const Text('Try again'),
              ),
      ),
      HomeResourceStage.content => Column(
        key: const ValueKey('home-related-tracks-section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inspired by “${seed?.title ?? 'your current song'}”',
            key: const ValueKey('home-related-tracks-seed'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _HomeTrackContent(
            tracks: controller.relatedTracks.take(6).toList(growable: false),
            queueController: queueController,
            compact: compact,
            sectionKey: const ValueKey('home-related-tracks'),
            itemKeyPrefix: 'home-related-track',
          ),
        ],
      ),
    };
  }
}

class _HomeTrackContent extends StatelessWidget {
  const _HomeTrackContent({
    required this.tracks,
    required this.queueController,
    required this.compact,
    required this.sectionKey,
    required this.itemKeyPrefix,
  });

  final List<PlaylistTrackSummary> tracks;
  final QueuePlaybackController queueController;
  final bool compact;
  final Key sectionKey;
  final String itemKeyPrefix;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = compact ? 1 : 2;
      final width = columns == 1
          ? constraints.maxWidth
          : (constraints.maxWidth - _HomeGeometry.itemGap) / 2;
      return Wrap(
        key: sectionKey,
        spacing: _HomeGeometry.itemGap,
        runSpacing: 0,
        children: [
          for (var index = 0; index < tracks.length; index++)
            SizedBox(
              width: width,
              child: _HomeTrackTile(
                itemKey: ValueKey('$itemKeyPrefix-${index + 1}'),
                queueKey: ValueKey('$itemKeyPrefix-queue-${index + 1}'),
                track: tracks[index],
                position: index + 1,
                compact: compact,
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
    required this.itemKey,
    required this.queueKey,
    required this.track,
    required this.position,
    required this.compact,
    required this.playing,
    required this.onPlay,
    required this.onQueue,
  });

  final Key itemKey;
  final Key queueKey;
  final PlaylistTrackSummary track;
  final int position;
  final bool compact;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final artists = track.artistNames.isEmpty
        ? 'Unknown artist'
        : track.artistNames.join(' · ');
    return SizedBox(
      height: _HomeGeometry.trackRowHeight,
      child: Semantics(
        button: true,
        label: '${track.title}, $artists',
        onTap: onPlay,
        child: Material(
          color: playing ? colors.secondaryContainer : Colors.transparent,
          borderRadius: _HomeGeometry.artworkRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: itemKey,
            onTap: onPlay,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: _HomeGeometry.trackArtworkSize,
                    child: _HomeArtwork(
                      uri: track.artworkUri,
                      placeholderIcon: playing
                          ? Icons.graphic_eq_rounded
                          : Icons.music_note_rounded,
                      radius: const BorderRadius.all(Radius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: playing
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: playing
                                    ? colors.onSecondaryContainer
                                    : null,
                              ),
                        ),
                        Text(
                          artists,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: playing
                                    ? colors.onSecondaryContainer.withValues(
                                        alpha: 0.78,
                                      )
                                    : colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (!compact && track.durationSeconds != null) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        _durationLabel(track.durationSeconds!),
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                  IconButton(
                    key: queueKey,
                    onPressed: onQueue,
                    tooltip: 'Add ${track.title} to queue',
                    icon: const Icon(Icons.playlist_add_rounded),
                    iconSize: 20,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
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

class _HomeTrackLoading extends StatelessWidget {
  const _HomeTrackLoading({required this.compact, required this.semanticLabel});

  final bool compact;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - _HomeGeometry.itemGap) / 2;
        return Wrap(
          spacing: _HomeGeometry.itemGap,
          children: [
            for (var index = 0; index < 6; index++)
              Container(
                width: width,
                height: _HomeGeometry.trackRowHeight,
                margin: const EdgeInsets.only(bottom: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: _HomeGeometry.artworkRadius,
                ),
              ),
          ],
        );
      },
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
        .take(6)
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
      semanticLabel: _recommendationSemanticLabel,
      itemKey: (index) =>
          ValueKey('home-recommendation-${index + skippedItems + 1}'),
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
  final String Function(T item) semanticLabel;
  final Key Function(int index) itemKey;
  final ValueChanged<T> onSelected;
  final FocusNode? Function(T item) focusNode;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return SizedBox(
        key: layoutKey,
        height: _HomeGeometry.compactShelfWidth + 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: _HomeGeometry.itemGap),
          itemBuilder: (context, index) => _PlaylistArtworkCard<T>(
            width: _HomeGeometry.compactShelfWidth,
            item: items[index],
            itemKey: itemKey(index),
            title: title,
            artworkUri: artworkUri,
            semanticLabel: semanticLabel,
            placeholderIcon: placeholderIcon,
            onSelected: onSelected,
            focusNode: focusNode(items[index]),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableColumns =
            ((constraints.maxWidth + _HomeGeometry.itemGap) /
                    (_HomeGeometry.wideShelfMinWidth + _HomeGeometry.itemGap))
                .floor()
                .clamp(1, 6);
        final fittedWidth =
            (constraints.maxWidth -
                _HomeGeometry.itemGap * (availableColumns - 1)) /
            availableColumns;
        final cardWidth = fittedWidth > _HomeGeometry.wideShelfMaxWidth
            ? _HomeGeometry.wideShelfMaxWidth
            : fittedWidth;
        return Wrap(
          key: layoutKey,
          spacing: _HomeGeometry.itemGap,
          runSpacing: _HomeGeometry.itemGap,
          children: [
            for (var index = 0; index < items.length; index++)
              _PlaylistArtworkCard<T>(
                width: cardWidth,
                item: items[index],
                itemKey: itemKey(index),
                title: title,
                artworkUri: artworkUri,
                semanticLabel: semanticLabel,
                placeholderIcon: placeholderIcon,
                onSelected: onSelected,
                focusNode: focusNode(items[index]),
              ),
          ],
        );
      },
    );
  }
}

class _PlaylistArtworkCard<T> extends StatelessWidget {
  const _PlaylistArtworkCard({
    required this.item,
    required this.itemKey,
    required this.title,
    required this.artworkUri,
    required this.semanticLabel,
    required this.placeholderIcon,
    required this.onSelected,
    required this.focusNode,
    this.width,
  });

  final double? width;
  final T item;
  final Key itemKey;
  final String Function(T item) title;
  final String? Function(T item) artworkUri;
  final String Function(T item) semanticLabel;
  final IconData placeholderIcon;
  final ValueChanged<T> onSelected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Semantics(
      button: true,
      label: semanticLabel(item),
      onTap: () => onSelected(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _HomeArtwork(
                  uri: artworkUri(item),
                  placeholderIcon: placeholderIcon,
                  radius: _HomeGeometry.artworkRadius,
                ),
                Positioned.fill(
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: itemKey,
                      focusNode: focusNode,
                      borderRadius: _HomeGeometry.artworkRadius,
                      onTap: () => onSelected(item),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title(item),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
          ),
        ],
      ),
    ),
  );
}

class _HomeArtwork extends StatelessWidget {
  const _HomeArtwork({
    required this.uri,
    required this.placeholderIcon,
    this.radius = _HomeGeometry.artworkRadius,
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
    child: compact
        ? SizedBox(
            height: _HomeGeometry.compactShelfWidth + 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: _HomeGeometry.itemGap),
              itemBuilder: (_, _) => Container(
                width: _HomeGeometry.compactShelfWidth,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: _HomeGeometry.artworkRadius,
                ),
              ),
            ),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  (constraints.maxWidth - _HomeGeometry.itemGap * 5) / 6;
              return SizedBox(
                height: width + 44,
                child: Row(
                  children: [
                    for (var index = 0; index < 6; index++) ...[
                      if (index > 0)
                        const SizedBox(width: _HomeGeometry.itemGap),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            borderRadius: _HomeGeometry.artworkRadius,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
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
    this.compactFootprint = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  final bool liveRegion;
  final bool compactFootprint;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: liveRegion,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: compactFootprint ? null : double.infinity,
        constraints: compactFootprint
            ? const BoxConstraints(maxWidth: 680)
            : null,
        padding: const EdgeInsets.all(_HomeGeometry.itemGap),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: _HomeGeometry.heroRadius,
        ),
        child: Wrap(
          spacing: _HomeGeometry.itemGap,
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
    ),
  );
}

String _personalizedPlaylistFailureTitle(
  PersonalizedPlaylistsFailure? failure,
) => switch (failure) {
  PersonalizedPlaylistsFailure.invalidResponse =>
    'Personalized playlist response not recognized',
  PersonalizedPlaylistsFailure.network => 'Personalized playlists are offline',
  PersonalizedPlaylistsFailure.serviceUnavailable =>
    'Personalized playlists are temporarily unavailable',
  PersonalizedPlaylistsFailure.replaced =>
    'Personalized playlist request was replaced',
  PersonalizedPlaylistsFailure.cancelled =>
    'Personalized playlist request was cancelled',
  PersonalizedPlaylistsFailure.alreadyRunning =>
    'Personalized playlists are already loading',
  _ => 'Couldn’t load personalized playlists',
};

String _personalizedPlaylistFailureDetail(
  PersonalizedPlaylistsFailure? failure,
) => switch (failure) {
  PersonalizedPlaylistsFailure.invalidResponse => 'QQ Music returned a personalized-playlist structure this client does not recognize. No account content was recorded.',
  PersonalizedPlaylistsFailure.network =>
    'Check the network connection, then try again.',
  PersonalizedPlaylistsFailure.serviceUnavailable =>
    'QQ Music rejected or could not serve this request. Try again later.',
  PersonalizedPlaylistsFailure.replaced =>
    'A newer authenticated recommendation request replaced this one.',
  PersonalizedPlaylistsFailure.cancelled =>
    'The request ended before personalized playlists were returned.',
  PersonalizedPlaylistsFailure.alreadyRunning =>
    'Wait for the active personalized-playlist request to finish.',
  _ => 'Public recommendations and Search are still available.',
};

String _relatedTracksFailureTitle(
  RelatedTracksFailure? failure,
) => switch (failure) {
  RelatedTracksFailure.invalidTrack => 'This song can’t seed recommendations',
  RelatedTracksFailure.network => 'Related songs are offline',
  RelatedTracksFailure.serviceUnavailable =>
    'Related songs are temporarily unavailable',
  RelatedTracksFailure.invalidResponse =>
    'Related-song response not recognized',
  RelatedTracksFailure.cancelled => 'Related-song request was cancelled',
  RelatedTracksFailure.alreadyRunning => 'Related songs are already loading',
  _ => 'Couldn’t load related songs',
};

String _relatedTracksFailureDetail(
  RelatedTracksFailure? failure,
  PlaylistTrackSummary? seed,
) => switch (failure) {
  RelatedTracksFailure.invalidTrack =>
    '“${seed?.title ?? 'This song'}” has no usable QQ Music identity.',
  RelatedTracksFailure.network =>
    'Check the network connection, then try again.',
  RelatedTracksFailure.serviceUnavailable =>
    'QQ Music could not serve related songs for this seed right now.',
  RelatedTracksFailure.invalidResponse => 'QQ Music returned a related-song structure this client does not recognize.',
  RelatedTracksFailure.cancelled =>
    'The seed changed before related songs were returned.',
  RelatedTracksFailure.alreadyRunning =>
    'Wait for the active related-song request to finish.',
  _ => 'The related-song Core capability could not be reached.',
};

String _publicStateDetail(RecommendedPlaylistStage stage) => switch (stage) {
  RecommendedPlaylistStage.loading => 'Loading public recommendations…',
  RecommendedPlaylistStage.content =>
    'No additional public recommendation is available right now.',
  RecommendedPlaylistStage.empty =>
    'QQ Music has no public recommendation available right now.',
  RecommendedPlaylistStage.error =>
    'Public recommendations could not be loaded.',
};

String _dailyStateDetail(HomeResourceStage stage) => switch (stage) {
  HomeResourceStage.loading => 'Loading your Daily 30…',
  HomeResourceStage.content => 'Daily 30 is unavailable right now.',
  HomeResourceStage.empty => 'Daily 30 is unavailable right now.',
  HomeResourceStage.error => 'Daily 30 could not be loaded.',
};

String _radarStateDetail(RadarStage stage) => switch (stage) {
  RadarStage.loading => 'Loading your Radar recommendations…',
  RadarStage.content => 'Radar is unavailable right now.',
  RadarStage.empty => 'QQ Music has no Radar recommendation right now.',
  RadarStage.error => 'Radar recommendations could not be loaded.',
};

String _newSongStateDetail(NewSongStage stage) => switch (stage) {
  NewSongStage.loading => 'Loading public new songs…',
  NewSongStage.content => 'No public new song is available right now.',
  NewSongStage.empty => 'QQ Music has no public new songs right now.',
  NewSongStage.error => 'Public new songs could not be loaded.',
};

String _newSongFailureDetail(NewSongFailure? failure) => switch (failure) {
  NewSongFailure.network => 'Check your connection, then try again.',
  NewSongFailure.serviceUnavailable =>
    'QQ Music new songs are temporarily unavailable.',
  NewSongFailure.cancelled => 'The new-song request was cancelled.',
  NewSongFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  NewSongFailure.invalidResponse =>
    'QQ Music returned a new-song response this client does not recognize.',
  NewSongFailure.alreadyRunning =>
    'Wait for the active new-song request to finish.',
  null => 'Public new songs could not be loaded.',
};

String _recommendationDetail(RecommendedPlaylistSummary playlist) =>
    playlist.trackCount == null
    ? 'QQ Music playlist'
    : '${playlist.trackCount} tracks';

String _recommendationSemanticLabel(RecommendedPlaylistSummary playlist) =>
    playlist.trackCount == null
    ? '${playlist.title}, QQ Music playlist'
    : '${playlist.title}, ${playlist.trackCount} tracks';

String _durationLabel(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

bool _sameTrack(PlaylistTrackSummary? track, PlaylistTrackSummary other) =>
    track != null &&
    track.providerId == other.providerId &&
    track.opaqueId == other.opaqueId;
