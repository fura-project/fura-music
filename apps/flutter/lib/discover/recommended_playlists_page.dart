import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/music_track_tile.dart';
import 'package:flutterustmusic/discover/new_album_controller.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';
import 'package:flutterustmusic/discover/new_song_controller.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/discover/radar_controller.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/discover/ranking_controller.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/discover/ranking_page.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/navigation/music_section_selector.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

class RecommendedPlaylistsPage extends StatefulWidget {
  const RecommendedPlaylistsPage({
    required this.gateway,
    required this.newAlbumGateway,
    required this.newSongGateway,
    required this.rankingGateway,
    required this.radarGateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onOpenPlaylist,
    required this.onOpenRanking,
    required this.onOpenAlbum,
    required this.onSignInAgain,
    this.embedded = false,
    super.key,
  });

  final RecommendedPlaylistGateway gateway;
  final NewAlbumGateway newAlbumGateway;
  final NewSongGateway newSongGateway;
  final RankingGateway rankingGateway;
  final RadarGateway radarGateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final ValueChanged<RecommendedPlaylistSummary> onOpenPlaylist;
  final ValueChanged<RankingSummary> onOpenRanking;
  final ValueChanged<AlbumSummary> onOpenAlbum;
  final VoidCallback onSignInAgain;
  final bool embedded;

  @override
  State<RecommendedPlaylistsPage> createState() =>
      _RecommendedPlaylistsPageState();
}

class _RecommendedPlaylistsPageState extends State<RecommendedPlaylistsPage> {
  late final RecommendedPlaylistController _controller;
  late final NewAlbumController _newAlbumController;
  late final NewSongController _newSongController;
  late final RankingGroupController _rankingController;
  late final RadarController _radarController;
  _DiscoverType _type = _DiscoverType.playlists;
  bool _rankingsVisited = false;
  bool _radarVisited = false;
  bool _newAlbumsVisited = false;
  bool _newSongsVisited = false;

  @override
  void initState() {
    super.initState();
    _controller = RecommendedPlaylistController(widget.gateway);
    _newAlbumController = NewAlbumController(widget.newAlbumGateway);
    _newSongController = NewSongController(widget.newSongGateway);
    _rankingController = RankingGroupController(widget.rankingGateway);
    _radarController = RadarController(widget.radarGateway);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _newAlbumController.dispose();
    _newSongController.dispose();
    _rankingController.dispose();
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _controller,
          _newAlbumController,
          _newSongController,
          _rankingController,
          _radarController,
        ]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MusicSectionSelector<_DiscoverType>(
                    controlKey: const ValueKey('discover-type-selector'),
                    label: 'Discover section',
                    destinations: const [
                      MusicSectionDestination(
                        value: _DiscoverType.playlists,
                        icon: Icons.queue_music_rounded,
                        label: 'Playlists',
                        itemKey: ValueKey('discover-type-playlists'),
                      ),
                      MusicSectionDestination(
                        value: _DiscoverType.rankings,
                        icon: Icons.leaderboard_rounded,
                        label: 'Rankings',
                        itemKey: ValueKey('discover-type-rankings'),
                      ),
                      MusicSectionDestination(
                        value: _DiscoverType.radar,
                        icon: Icons.radar_rounded,
                        label: 'Radar',
                        itemKey: ValueKey('discover-type-radar'),
                      ),
                      MusicSectionDestination(
                        value: _DiscoverType.newAlbums,
                        icon: Icons.album_rounded,
                        label: 'New albums',
                        itemKey: ValueKey('discover-type-new-albums'),
                      ),
                      MusicSectionDestination(
                        value: _DiscoverType.newSongs,
                        icon: Icons.new_releases_rounded,
                        label: 'New songs',
                        itemKey: ValueKey('discover-type-new-songs'),
                      ),
                    ],
                    selected: _type,
                    compact: constraints.maxWidth < 680,
                    onSelected: _selectType,
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: switch (_type) {
                    _DiscoverType.playlists => _playlistBody(),
                    _DiscoverType.rankings => _rankingBody(),
                    _DiscoverType.radar => _radarBody(),
                    _DiscoverType.newAlbums => _newAlbumBody(),
                    _DiscoverType.newSongs => _newSongBody(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('recommendations-back'),
          tooltip: 'Back to your music',
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Discover'),
      ),
      body: body,
      bottomNavigationBar: NowPlayingBar(
        controller: widget.queuePlaybackController,
        onSignInAgain: widget.onSignInAgain,
      ),
    );
  }

  Widget _playlistBody() => switch (_controller.stage) {
    RecommendedPlaylistStage.loading => const MusicLoadingPanel(
      key: ValueKey('recommendations-loading'),
      label: 'Loading Recommended Playlists',
    ),
    RecommendedPlaylistStage.empty => const MusicContentStatePanel(
      key: ValueKey('recommendations-empty'),
      icon: Icons.explore_off_outlined,
      title: 'No recommendations right now',
      detail: 'QQ Music returned an empty recommended-playlist page.',
    ),
    RecommendedPlaylistStage.error => MusicContentStatePanel(
      key: const ValueKey('recommendations-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load recommendations',
      detail: _failureCopy(_controller.failure),
      liveRegion: true,
      action: _controller.canRetry
          ? FilledButton.tonal(
              onPressed: _controller.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    RecommendedPlaylistStage.content => _RecommendationCollection(
      key: const ValueKey('recommendations-content'),
      playlists: _controller.playlists,
      hasMore: _controller.hasMore,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
      onSelected: widget.onOpenPlaylist,
    ),
  };

  Widget _rankingBody() => switch (_rankingController.stage) {
    RankingGroupStage.loading => const MusicLoadingPanel(
      key: ValueKey('rankings-loading'),
      label: 'Loading QQ Music Rankings',
    ),
    RankingGroupStage.empty => const MusicContentStatePanel(
      key: ValueKey('rankings-empty'),
      icon: Icons.leaderboard_outlined,
      title: 'No rankings right now',
      detail: 'QQ Music returned no current ranking groups.',
    ),
    RankingGroupStage.error => MusicContentStatePanel(
      key: const ValueKey('rankings-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load rankings',
      detail: rankingFailureCopy(_rankingController.failure),
      liveRegion: true,
      action: _rankingController.canRetry
          ? FilledButton.tonal(
              onPressed: _rankingController.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    RankingGroupStage.content => _RankingCollection(
      key: const ValueKey('rankings-content'),
      groups: _rankingController.groups,
      onSelected: widget.onOpenRanking,
    ),
  };

  Widget _radarBody() => switch (_radarController.stage) {
    RadarStage.loading => const MusicLoadingPanel(
      key: ValueKey('radar-loading'),
      label: 'Loading QQ Music Radar',
    ),
    RadarStage.empty => const MusicContentStatePanel(
      key: ValueKey('radar-empty'),
      icon: Icons.radar_rounded,
      title: 'No Radar Tracks right now',
      detail: 'QQ Music returned an empty Radar Track page.',
    ),
    RadarStage.error => MusicContentStatePanel(
      key: const ValueKey('radar-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load Radar',
      detail: radarFailureCopy(_radarController.failure),
      liveRegion: true,
      action: _radarFailureAction(_radarController.failure),
    ),
    RadarStage.content => _RadarCollection(
      key: const ValueKey('radar-content'),
      tracks: _radarController.tracks,
      hasMore: _radarController.hasMore,
      isLoadingMore: _radarController.isLoadingMore,
      appendFailure: _radarController.appendFailure,
      canRetryMore: _radarController.canRetryMore,
      onLoadMore: _radarController.loadMore,
      onRetryMore: _radarController.retryMore,
      onReload: () => unawaited(_radarController.load()),
      onSignInAgain: widget.onSignInAgain,
      onPlay: _playRadar,
      onQueue: _queueRadar,
    ),
  };

  Widget _newAlbumBody() => switch (_newAlbumController.stage) {
    NewAlbumStage.loading => _NewAlbumShell(
      key: const ValueKey('new-albums-loading'),
      region: _newAlbumController.region,
      onRegionSelected: _newAlbumController.selectRegion,
      child: const MusicLoadingPanel(label: 'Loading New Albums'),
    ),
    NewAlbumStage.empty => _NewAlbumShell(
      key: const ValueKey('new-albums-empty'),
      region: _newAlbumController.region,
      onRegionSelected: _newAlbumController.selectRegion,
      child: const MusicContentStatePanel(
        icon: Icons.album_outlined,
        title: 'No new albums right now',
        detail: 'QQ Music returned an empty page for this region.',
      ),
    ),
    NewAlbumStage.error => _NewAlbumShell(
      key: const ValueKey('new-albums-error'),
      region: _newAlbumController.region,
      onRegionSelected: _newAlbumController.selectRegion,
      child: MusicContentStatePanel(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn’t load new albums',
        detail: newAlbumFailureCopy(_newAlbumController.failure),
        liveRegion: true,
        action: _newAlbumController.canRetry
            ? FilledButton.tonal(
                onPressed: _newAlbumController.retry,
                child: const Text('Try again'),
              )
            : null,
      ),
    ),
    NewAlbumStage.content => _NewAlbumCollection(
      key: const ValueKey('new-albums-content'),
      region: _newAlbumController.region,
      releases: _newAlbumController.releases,
      hasMore: _newAlbumController.hasMore,
      isLoadingMore: _newAlbumController.isLoadingMore,
      appendFailure: _newAlbumController.appendFailure,
      onRegionSelected: _newAlbumController.selectRegion,
      onLoadMore: _newAlbumController.loadMore,
      onRetryMore: _newAlbumController.retryMore,
      onSelected: (release) => widget.onOpenAlbum(release.album),
    ),
  };

  Widget _newSongBody() => switch (_newSongController.stage) {
    NewSongStage.loading => _NewSongShell(
      key: const ValueKey('new-songs-loading'),
      category: _newSongController.category,
      onCategorySelected: _newSongController.selectCategory,
      child: const MusicLoadingPanel(label: 'Loading New Songs'),
    ),
    NewSongStage.empty => _NewSongShell(
      key: const ValueKey('new-songs-empty'),
      category: _newSongController.category,
      onCategorySelected: _newSongController.selectCategory,
      child: const MusicContentStatePanel(
        icon: Icons.music_off_rounded,
        title: 'No new songs right now',
        detail: 'QQ Music returned no Tracks for this category.',
      ),
    ),
    NewSongStage.error => _NewSongShell(
      key: const ValueKey('new-songs-error'),
      category: _newSongController.category,
      onCategorySelected: _newSongController.selectCategory,
      child: MusicContentStatePanel(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn’t load new songs',
        detail: newSongFailureCopy(_newSongController.failure),
        liveRegion: true,
        action: _newSongController.canRetry
            ? FilledButton.tonal(
                onPressed: _newSongController.retry,
                child: const Text('Try again'),
              )
            : null,
      ),
    ),
    NewSongStage.content => _NewSongCollection(
      key: const ValueKey('new-songs-content'),
      category: _newSongController.category,
      tracks: _newSongController.tracks,
      onCategorySelected: _newSongController.selectCategory,
      onPlay: _playNewSong,
      onQueue: _queueNewSong,
    ),
  };

  Widget? _radarFailureAction(RadarFailure? failure) {
    if (_radarRequiresSignIn(failure)) {
      return FilledButton.tonal(
        onPressed: widget.onSignInAgain,
        child: const Text('Sign in again'),
      );
    }
    if (_radarController.canRetry) {
      return FilledButton.tonal(
        onPressed: _radarController.retry,
        child: const Text('Try again'),
      );
    }
    if (failure == RadarFailure.replaced) {
      return FilledButton.tonal(
        onPressed: () => unawaited(_radarController.load()),
        child: const Text('Reload Radar'),
      );
    }
    return null;
  }

  void _playRadar(int index) {
    unawaited(
      widget.queuePlaybackController.replaceAndPlay(
        _radarController.tracks,
        index,
      ),
    );
  }

  void _queueRadar(PlaylistTrackSummary track) {
    _queueTrack(track);
  }

  void _playNewSong(int index) {
    unawaited(
      widget.queuePlaybackController.replaceAndPlay(
        _newSongController.tracks,
        index,
      ),
    );
  }

  void _queueNewSong(PlaylistTrackSummary track) {
    _queueTrack(track);
  }

  void _queueTrack(PlaylistTrackSummary track) {
    final playbackStart = widget.queuePlaybackController.push(track);
    if (!mounted) {
      unawaited(playbackStart);
      return;
    }
    final message = widget.queuePlaybackController.failure == null
        ? 'Added to queue'
        : 'Couldn’t update the queue';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    unawaited(playbackStart);
  }

  void _selectType(_DiscoverType type) {
    if (_type == type) return;
    setState(() => _type = type);
    if (type == _DiscoverType.rankings && !_rankingsVisited) {
      _rankingsVisited = true;
      unawaited(_rankingController.load());
    }
    if (type == _DiscoverType.radar && !_radarVisited) {
      _radarVisited = true;
      unawaited(_radarController.load());
    }
    if (type == _DiscoverType.newAlbums && !_newAlbumsVisited) {
      _newAlbumsVisited = true;
      unawaited(_newAlbumController.load());
    }
    if (type == _DiscoverType.newSongs && !_newSongsVisited) {
      _newSongsVisited = true;
      unawaited(_newSongController.load());
    }
  }
}

enum _DiscoverType { playlists, rankings, radar, newAlbums, newSongs }

class _NewSongShell extends StatelessWidget {
  const _NewSongShell({
    required this.category,
    required this.onCategorySelected,
    required this.child,
    super.key,
  });

  final NewSongCategory category;
  final ValueChanged<NewSongCategory> onCategorySelected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _NewSongCategoryPicker(
        category: category,
        onSelected: onCategorySelected,
      ),
      Expanded(child: child),
    ],
  );
}

class _NewSongCollection extends StatelessWidget {
  const _NewSongCollection({
    required this.category,
    required this.tracks,
    required this.onCategorySelected,
    required this.onPlay,
    required this.onQueue,
    super.key,
  });

  final NewSongCategory category;
  final List<PlaylistTrackSummary> tracks;
  final ValueChanged<NewSongCategory> onCategorySelected;
  final ValueChanged<int> onPlay;
  final ValueChanged<PlaylistTrackSummary> onQueue;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              desktop ? 48 : 20,
              desktop ? 24 : 16,
              desktop ? 48 : 20,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New songs',
                  style:
                      (desktop
                              ? Theme.of(context).textTheme.headlineMedium
                              : Theme.of(context).textTheme.headlineSmall)
                          ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  '${newSongCategoryLabel(category)} releases from QQ Music',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _NewSongCategoryPicker(
            category: category,
            onSelected: onCategorySelected,
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: ListView.builder(
                  key: PageStorageKey<String>('new-song-list-${category.name}'),
                  padding: EdgeInsets.fromLTRB(
                    desktop ? 40 : 12,
                    8,
                    desktop ? 40 : 12,
                    28,
                  ),
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return MusicTrackTile(
                      itemKey: ValueKey('new-song-track-$index'),
                      queueKey: ValueKey('new-song-queue-$index'),
                      track: track,
                      position: index + 1,
                      desktop: desktop,
                      onPlay: () => onPlay(index),
                      onQueue: () => onQueue(track),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _NewSongCategoryPicker extends StatelessWidget {
  const _NewSongCategoryPicker({
    required this.category,
    required this.onSelected,
  });

  final NewSongCategory category;
  final ValueChanged<NewSongCategory> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('new-song-category-selector'),
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
    child: Row(
      children: [
        for (final value in NewSongCategory.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: ValueKey('new-song-category-${value.name}'),
              label: Text(newSongCategoryLabel(value)),
              selected: category == value,
              onSelected: (_) => onSelected(value),
            ),
          ),
      ],
    ),
  );
}

class _NewAlbumShell extends StatelessWidget {
  const _NewAlbumShell({
    required this.region,
    required this.onRegionSelected,
    required this.child,
    super.key,
  });

  final NewAlbumRegion region;
  final ValueChanged<NewAlbumRegion> onRegionSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _NewAlbumRegionPicker(region: region, onSelected: onRegionSelected),
      Expanded(child: child),
    ],
  );
}

class _NewAlbumCollection extends StatelessWidget {
  const _NewAlbumCollection({
    required this.region,
    required this.releases,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onRegionSelected,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onSelected,
    super.key,
  });

  final NewAlbumRegion region;
  final List<NewAlbumRelease> releases;
  final bool hasMore;
  final bool isLoadingMore;
  final NewAlbumFailure? appendFailure;
  final ValueChanged<NewAlbumRegion> onRegionSelected;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<NewAlbumRelease> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      final footer = _NewAlbumFooter(
        hasMore: hasMore,
        isLoadingMore: isLoadingMore,
        appendFailure: appendFailure,
        onLoadMore: onLoadMore,
        onRetryMore: onRetryMore,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              desktop ? 48 : 20,
              desktop ? 24 : 16,
              desktop ? 48 : 20,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New albums',
                  style:
                      (desktop
                              ? Theme.of(context).textTheme.headlineMedium
                              : Theme.of(context).textTheme.headlineSmall)
                          ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Fresh ${newAlbumRegionLabel(region)} releases from QQ Music',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _NewAlbumRegionPicker(region: region, onSelected: onRegionSelected),
          Expanded(
            child: desktop
                ? GridView.builder(
                    key: PageStorageKey<String>(
                      'new-album-grid-${region.name}',
                    ),
                    padding: const EdgeInsets.fromLTRB(48, 8, 48, 24),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisExtent: 282,
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                        ),
                    itemCount: releases.length + 1,
                    itemBuilder: (context, index) => index == releases.length
                        ? footer
                        : _NewAlbumCard(
                            key: ValueKey('new-album-$index'),
                            release: releases[index],
                            onTap: () => onSelected(releases[index]),
                          ),
                  )
                : ListView.separated(
                    key: PageStorageKey<String>(
                      'new-album-list-${region.name}',
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: releases.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => index == releases.length
                        ? footer
                        : _NewAlbumTile(
                            key: ValueKey('new-album-$index'),
                            release: releases[index],
                            onTap: () => onSelected(releases[index]),
                          ),
                  ),
          ),
        ],
      );
    },
  );
}

class _NewAlbumRegionPicker extends StatelessWidget {
  const _NewAlbumRegionPicker({required this.region, required this.onSelected});

  final NewAlbumRegion region;
  final ValueChanged<NewAlbumRegion> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('new-album-region-selector'),
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
    child: Row(
      children: [
        for (final value in NewAlbumRegion.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: ValueKey('new-album-region-${value.name}'),
              label: Text(newAlbumRegionLabel(value)),
              selected: region == value,
              onSelected: (_) => onSelected(value),
            ),
          ),
      ],
    ),
  );
}

class _NewAlbumTile extends StatelessWidget {
  const _NewAlbumTile({required this.release, required this.onTap, super.key});

  final NewAlbumRelease release;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = _newAlbumDetails(release);
    return Semantics(
      button: true,
      label: _newAlbumSemanticLabel(release),
      excludeSemantics: true,
      onTap: onTap,
      child: ListTile(
        minTileHeight: 82,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: SizedBox.square(
          dimension: 60,
          child: _NewAlbumArtwork(uri: release.album.artworkUri),
        ),
        title: Text(
          release.album.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _NewAlbumCard extends StatelessWidget {
  const _NewAlbumCard({required this.release, required this.onTap, super.key});

  final NewAlbumRelease release;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _newAlbumSemanticLabel(release),
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _NewAlbumArtwork(uri: release.album.artworkUri)),
            const SizedBox(height: 10),
            Text(
              release.album.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              _newAlbumDetails(release),
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
  );
}

class _NewAlbumArtwork extends StatelessWidget {
  const _NewAlbumArtwork({this.uri});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.secondaryContainer, colors.primaryContainer],
        ),
      ),
      child: Icon(Icons.album_rounded, color: colors.onSecondaryContainer),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
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

class _NewAlbumFooter extends StatelessWidget {
  const _NewAlbumFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final NewAlbumFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: isLoadingMore
          ? const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : appendFailure != null
          ? FilledButton.tonal(
              onPressed: onRetryMore,
              child: const Text('Try loading more again'),
            )
          : hasMore
          ? FilledButton.tonal(
              key: const ValueKey('new-albums-load-more'),
              onPressed: onLoadMore,
              child: const Text('Load more'),
            )
          : Text(
              'End of new albums',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

String _newAlbumDetails(NewAlbumRelease release) {
  final details = <String>[
    if (release.artists.isNotEmpty)
      release.artists.map((artist) => artist.name).join(' · '),
    ?release.releaseDate,
  ];
  return details.isEmpty ? 'Album' : details.join(' · ');
}

String _newAlbumSemanticLabel(NewAlbumRelease release) =>
    '${release.album.title}, ${_newAlbumDetails(release)}';

class _RankingCollection extends StatelessWidget {
  const _RankingCollection({
    required this.groups,
    required this.onSelected,
    super.key,
  });

  final List<RankingGroup> groups;
  final ValueChanged<RankingSummary> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      return ListView(
        key: const PageStorageKey<String>('ranking-groups'),
        padding: EdgeInsets.fromLTRB(
          desktop ? 48 : 16,
          desktop ? 24 : 16,
          desktop ? 48 : 16,
          28,
        ),
        children: [
          Text(
            'QQ Music rankings',
            style:
                (desktop
                        ? Theme.of(context).textTheme.headlineMedium
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Current charts from QQ Music',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: desktop ? 28 : 20),
          for (final group in groups) ...[
            Semantics(
              header: true,
              child: Text(
                group.title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            if (desktop)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final ranking in group.rankings)
                    SizedBox(
                      width: 280,
                      child: _RankingTile(
                        ranking: ranking,
                        onTap: () => onSelected(ranking),
                      ),
                    ),
                ],
              )
            else
              for (final ranking in group.rankings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RankingTile(
                    ranking: ranking,
                    onTap: () => onSelected(ranking),
                  ),
                ),
            const SizedBox(height: 24),
          ],
        ],
      );
    },
  );
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({required this.ranking, required this.onTap});

  final RankingSummary ranking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = <String>[];
    if (ranking.period case final period?) details.add(period);
    if (ranking.trackCount case final count?) details.add('$count Tracks');
    final semantic = details.isEmpty
        ? ranking.title
        : '${ranking.title}, ${details.join(', ')}';
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: ListTile(
        key: ValueKey('ranking-${ranking.opaqueId}'),
        minTileHeight: 80,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: SizedBox.square(
          dimension: 60,
          child: RankingArtwork(uri: ranking.artworkUri),
        ),
        title: Text(
          ranking.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: details.isEmpty
            ? const Text('Current ranking')
            : Text(details.join(' · ')),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _RadarCollection extends StatelessWidget {
  const _RadarCollection({
    required this.tracks,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.canRetryMore,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onReload,
    required this.onSignInAgain,
    required this.onPlay,
    required this.onQueue,
    super.key,
  });

  final List<PlaylistTrackSummary> tracks;
  final bool hasMore;
  final bool isLoadingMore;
  final RadarFailure? appendFailure;
  final bool canRetryMore;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final VoidCallback onReload;
  final VoidCallback onSignInAgain;
  final ValueChanged<int> onPlay;
  final ValueChanged<PlaylistTrackSummary> onQueue;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: ListView.builder(
            key: const PageStorageKey<String>('radar-tracks'),
            padding: EdgeInsets.fromLTRB(
              desktop ? 40 : 12,
              desktop ? 24 : 16,
              desktop ? 40 : 12,
              24,
            ),
            itemCount: tracks.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QQ Music Radar',
                        style:
                            (desktop
                                    ? Theme.of(context).textTheme.headlineMedium
                                    : Theme.of(context).textTheme.headlineSmall)
                                ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Track recommendations for your signed-in session',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (index == tracks.length + 1) {
                return _RadarFooter(
                  hasMore: hasMore,
                  isLoadingMore: isLoadingMore,
                  appendFailure: appendFailure,
                  canRetryMore: canRetryMore,
                  onLoadMore: onLoadMore,
                  onRetryMore: onRetryMore,
                  onReload: onReload,
                  onSignInAgain: onSignInAgain,
                );
              }
              final trackIndex = index - 1;
              final track = tracks[trackIndex];
              return MusicTrackTile(
                itemKey: ValueKey('radar-track-$trackIndex'),
                queueKey: ValueKey('radar-queue-$trackIndex'),
                track: track,
                position: trackIndex + 1,
                desktop: desktop,
                onPlay: () => onPlay(trackIndex),
                onQueue: () => onQueue(track),
              );
            },
          ),
        ),
      );
    },
  );
}

class _RadarFooter extends StatelessWidget {
  const _RadarFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.canRetryMore,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onReload,
    required this.onSignInAgain,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final RadarFailure? appendFailure;
  final bool canRetryMore;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final VoidCallback onReload;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final failure = appendFailure;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: isLoadingMore
            ? const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : _radarRequiresSignIn(failure)
            ? FilledButton.tonal(
                onPressed: onSignInAgain,
                child: const Text('Sign in again'),
              )
            : canRetryMore
            ? FilledButton.tonal(
                onPressed: onRetryMore,
                child: const Text('Try loading more again'),
              )
            : failure == RadarFailure.replaced
            ? FilledButton.tonal(
                onPressed: onReload,
                child: const Text('Reload Radar'),
              )
            : failure != null
            ? Text(
                radarFailureCopy(failure),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              )
            : hasMore
            ? FilledButton.tonal(
                key: const ValueKey('radar-load-more'),
                onPressed: onLoadMore,
                child: const Text('Load more'),
              )
            : Text(
                'End of Radar recommendations',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

class _RecommendationCollection extends StatelessWidget {
  const _RecommendationCollection({
    required this.playlists,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onSelected,
    super.key,
  });

  final List<RecommendedPlaylistSummary> playlists;
  final bool hasMore;
  final bool isLoadingMore;
  final RecommendedPlaylistFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<RecommendedPlaylistSummary> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      final header = Padding(
        padding: EdgeInsets.fromLTRB(
          desktop ? 48 : 20,
          desktop ? 24 : 16,
          desktop ? 48 : 20,
          desktop ? 24 : 16,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recommended playlists',
                style:
                    (desktop
                            ? Theme.of(context).textTheme.headlineMedium
                            : Theme.of(context).textTheme.headlineSmall)
                        ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Public picks from QQ Music',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
      final footer = _RecommendationFooter(
        hasMore: hasMore,
        isLoadingMore: isLoadingMore,
        appendFailure: appendFailure,
        onLoadMore: onLoadMore,
        onRetryMore: onRetryMore,
      );
      return Column(
        children: [
          header,
          Expanded(
            child: desktop
                ? GridView.builder(
                    key: const PageStorageKey<String>(
                      'recommended-playlist-grid',
                    ),
                    padding: const EdgeInsets.fromLTRB(48, 0, 48, 24),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisExtent: 270,
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 28,
                        ),
                    itemCount: playlists.length + 1,
                    itemBuilder: (context, index) => index == playlists.length
                        ? footer
                        : _RecommendationGridItem(
                            key: ValueKey('recommendations-item-$index'),
                            playlist: playlists[index],
                            onTap: () => onSelected(playlists[index]),
                          ),
                  )
                : ListView.separated(
                    key: const PageStorageKey<String>(
                      'recommended-playlist-list',
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: playlists.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => index == playlists.length
                        ? footer
                        : _RecommendationListItem(
                            key: ValueKey('recommendations-item-$index'),
                            playlist: playlists[index],
                            onTap: () => onSelected(playlists[index]),
                          ),
                  ),
          ),
        ],
      );
    },
  );
}

class _RecommendationGridItem extends StatelessWidget {
  const _RecommendationGridItem({
    required this.playlist,
    required this.onTap,
    super.key,
  });

  final RecommendedPlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _semanticLabel(playlist),
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _RecommendationArtwork(uri: playlist.artworkUri)),
          const SizedBox(height: 12),
          Text(
            playlist.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
          ),
          if (playlist.trackCount case final count?) ...[
            const SizedBox(height: 4),
            Text(
              '$count tracks',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _RecommendationListItem extends StatelessWidget {
  const _RecommendationListItem({
    required this.playlist,
    required this.onTap,
    super.key,
  });

  final RecommendedPlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _semanticLabel(playlist),
    excludeSemantics: true,
    onTap: onTap,
    child: ListTile(
      minTileHeight: 80,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: SizedBox.square(
        dimension: 60,
        child: _RecommendationArtwork(uri: playlist.artworkUri),
      ),
      title: Text(playlist.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: playlist.trackCount != null
          ? Text('${playlist.trackCount} tracks')
          : const Text('QQ Music playlist'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _RecommendationArtwork extends StatelessWidget {
  const _RecommendationArtwork({this.uri});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      child: Icon(Icons.queue_music_rounded, color: colors.onPrimaryContainer),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
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

class _RecommendationFooter extends StatelessWidget {
  const _RecommendationFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final RecommendedPlaylistFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: isLoadingMore
          ? const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : appendFailure != null
          ? FilledButton.tonal(
              onPressed: onRetryMore,
              child: const Text('Try loading more again'),
            )
          : hasMore
          ? FilledButton.tonal(
              key: const ValueKey('recommendations-load-more'),
              onPressed: onLoadMore,
              child: const Text('Load more'),
            )
          : Text(
              'End of recommendations',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

String _semanticLabel(RecommendedPlaylistSummary playlist) {
  final count = playlist.trackCount;
  return count == null ? playlist.title : '${playlist.title}, $count tracks';
}

String _failureCopy(RecommendedPlaylistFailure? failure) => switch (failure) {
  RecommendedPlaylistFailure.network => 'Check your connection and try again.',
  RecommendedPlaylistFailure.serviceUnavailable =>
    'QQ Music recommendations are temporarily unavailable.',
  RecommendedPlaylistFailure.cancelled =>
    'The recommendation request was cancelled.',
  RecommendedPlaylistFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  RecommendedPlaylistFailure.invalidResponse ||
  RecommendedPlaylistFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected recommendation response.',
};

bool _radarRequiresSignIn(RadarFailure? failure) =>
    failure == RadarFailure.authenticationRequired ||
    failure == RadarFailure.credentialRejected ||
    failure == RadarFailure.credentialRejectedStorageCleanupFailed;

String radarFailureCopy(RadarFailure? failure) => switch (failure) {
  RadarFailure.authenticationRequired =>
    'Sign in to load QQ Music Radar Tracks.',
  RadarFailure.credentialRejected =>
    'Your QQ Music session expired. Sign in again to continue.',
  RadarFailure.credentialRejectedStorageCleanupFailed =>
    'Your QQ Music session expired, but its saved copy could not be removed. '
        'Sign in again after checking secure storage.',
  RadarFailure.network => 'Check your connection and try again.',
  RadarFailure.serviceUnavailable =>
    'QQ Music Radar is temporarily unavailable.',
  RadarFailure.replaced =>
    'The signed-in account changed while Radar was loading.',
  RadarFailure.cancelled => 'The Radar request was cancelled.',
  RadarFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  RadarFailure.invalidResponse ||
  RadarFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected Radar response.',
};

String newAlbumRegionLabel(NewAlbumRegion region) => switch (region) {
  NewAlbumRegion.mainlandChina => 'Mainland China',
  NewAlbumRegion.hongKongTaiwan => 'Hong Kong / Taiwan',
  NewAlbumRegion.western => 'Western',
  NewAlbumRegion.korea => 'Korea',
  NewAlbumRegion.japan => 'Japan',
  NewAlbumRegion.other => 'Other',
};

String newAlbumFailureCopy(NewAlbumFailure? failure) => switch (failure) {
  NewAlbumFailure.network => 'Check your connection and try again.',
  NewAlbumFailure.serviceUnavailable =>
    'QQ Music new albums are temporarily unavailable.',
  NewAlbumFailure.cancelled => 'The new-album request was cancelled.',
  NewAlbumFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  NewAlbumFailure.invalidResponse ||
  NewAlbumFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected new-album response.',
};

String newSongCategoryLabel(NewSongCategory category) => switch (category) {
  NewSongCategory.latest => 'Latest',
  NewSongCategory.mainlandChina => 'Mainland China',
  NewSongCategory.hongKongTaiwan => 'Hong Kong / Taiwan',
  NewSongCategory.western => 'Western',
  NewSongCategory.korea => 'Korea',
  NewSongCategory.japan => 'Japan',
};

String newSongFailureCopy(NewSongFailure? failure) => switch (failure) {
  NewSongFailure.network => 'Check your connection and try again.',
  NewSongFailure.serviceUnavailable =>
    'QQ Music new songs are temporarily unavailable.',
  NewSongFailure.cancelled => 'The new-song request was cancelled.',
  NewSongFailure.coreUnavailable =>
    'The local music core is unavailable. Restart the app and try again.',
  NewSongFailure.invalidResponse ||
  NewSongFailure.alreadyRunning ||
  null => 'QQ Music returned an unexpected new-song response.',
};
