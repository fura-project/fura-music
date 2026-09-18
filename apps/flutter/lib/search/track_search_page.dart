import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/catalog/artist_artwork.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/catalog/partial_results_notice.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/navigation/music_section_selector.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/pagination/bounded_viewport_page_demand.dart';
import 'package:flutterustmusic/search/album_search_controller.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_controller.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_controller.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_controller.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_suggestions.dart';

class TrackSearchPage extends StatefulWidget {
  const TrackSearchPage({
    required this.gateway,
    required this.queuePlaybackController,
    required this.onBack,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required this.onOpenPlaylist,
    required this.onSignInAgain,
    this.providerDisplayName,
    this.artistGateway,
    this.albumGateway,
    this.playlistGateway,
    this.suggestionGateway,
    this.embedded = false,
    super.key,
  });

  final TrackSearchGateway gateway;
  final QueuePlaybackController queuePlaybackController;
  final VoidCallback onBack;
  final ValueChanged<AlbumSummary> onOpenAlbum;
  final ValueChanged<ArtistSummary> onOpenArtist;
  final ValueChanged<UserPlaylistSummary> onOpenPlaylist;
  final VoidCallback onSignInAgain;
  final String? providerDisplayName;
  final ArtistSearchGateway? artistGateway;
  final AlbumSearchGateway? albumGateway;
  final PlaylistSearchGateway? playlistGateway;
  final TrackSearchGateway? suggestionGateway;
  final bool embedded;

  @override
  State<TrackSearchPage> createState() => TrackSearchPageState();
}

enum _SearchType { tracks, artists, albums, playlists }

class TrackSearchPageState extends State<TrackSearchPage> {
  late final TrackSearchController _controller;
  late final ArtistSearchController _artistController;
  late final AlbumSearchController _albumController;
  late final PlaylistSearchController _playlistController;
  late final TrackSearchSuggestionController _suggestionController;
  late final Listenable _controllers;
  final TextEditingController _queryController = TextEditingController();
  late final FocusNode _queryFocusNode;
  final MenuController _suggestionMenuController = MenuController();
  final Set<_SearchType> _visitedTypes = {_SearchType.tracks};
  _SearchType _searchType = _SearchType.tracks;
  int _searchTypeTransition = 0;

  void submitTrackQuery(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    _suggestionMenuController.close();
    _suggestionController.dismiss();
    if (_searchType != _SearchType.tracks) {
      setState(() {
        _searchType = _SearchType.tracks;
        _visitedTypes.add(_SearchType.tracks);
        _searchTypeTransition += 1;
      });
    }
    _replaceQueryText(normalized);
    unawaited(_controller.submit(normalized));
  }

  @override
  void initState() {
    super.initState();
    _queryFocusNode = FocusNode(
      debugLabel: 'track search',
      onKeyEvent: _handleSuggestionKeyEvent,
    );
    _controller = TrackSearchController(widget.gateway);
    _artistController = ArtistSearchController(
      widget.artistGateway ?? const RustArtistSearchGateway(),
    );
    _albumController = AlbumSearchController(
      widget.albumGateway ?? const RustAlbumSearchGateway(),
    );
    _playlistController = PlaylistSearchController(
      widget.playlistGateway ?? const RustPlaylistSearchGateway(),
    );
    _suggestionController = TrackSearchSuggestionController(
      widget.suggestionGateway,
    );
    _queryFocusNode.addListener(_handleQueryFocus);
    _suggestionController.addListener(_handleSuggestions);
    _controllers = Listenable.merge([
      _controller,
      _artistController,
      _albumController,
      _playlistController,
      _suggestionController,
      _queryFocusNode,
    ]);
  }

  @override
  void dispose() {
    _controller.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _playlistController.dispose();
    _suggestionController.removeListener(_handleSuggestions);
    _suggestionController.dispose();
    _queryController.dispose();
    _queryFocusNode
      ..removeListener(_handleQueryFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final body = SafeArea(
      child: AnimatedBuilder(
        animation: _controllers,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;
            return Column(
              children: [
                _SearchField(
                  controller: _queryController,
                  focusNode: _queryFocusNode,
                  desktop: desktop,
                  loading: _isLoading,
                  hintText: switch (_searchType) {
                    _SearchType.tracks => l10n.searchSongHint,
                    _SearchType.artists => l10n.searchArtistHint,
                    _SearchType.albums => l10n.searchAlbumHint,
                    _SearchType.playlists => l10n.searchPlaylistHint,
                  },
                  onSubmitted: _submit,
                  onChanged: _suggestionController.updateQuery,
                  suggestions: _suggestionController,
                  menuController: _suggestionMenuController,
                  onSuggestionSelected: _selectSuggestion,
                  onMenuClosed: _handleSuggestionMenuClosed,
                  onClear: _clear,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    desktop ? 48 : 20,
                    0,
                    desktop ? 48 : 20,
                    14,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: MusicSectionSelector<_SearchType>(
                      controlKey: const ValueKey('search-types'),
                      label: l10n.searchTypeLabel,
                      destinations: [
                        MusicSectionDestination(
                          value: _SearchType.tracks,
                          icon: Icons.music_note_rounded,
                          label: l10n.searchTracksType,
                          itemKey: const ValueKey('search-type-tracks'),
                        ),
                        MusicSectionDestination(
                          value: _SearchType.artists,
                          icon: Icons.person_rounded,
                          label: l10n.searchArtistsType,
                          itemKey: const ValueKey('search-type-artists'),
                        ),
                        MusicSectionDestination(
                          value: _SearchType.albums,
                          icon: Icons.album_rounded,
                          label: l10n.searchAlbumsType,
                          itemKey: const ValueKey('search-type-albums'),
                        ),
                        MusicSectionDestination(
                          value: _SearchType.playlists,
                          icon: Icons.queue_music_rounded,
                          label: l10n.searchPlaylistsType,
                          itemKey: const ValueKey('search-type-playlists'),
                        ),
                      ],
                      selected: _searchType,
                      compact: constraints.maxWidth < 680,
                      onSelected: (value) => _selectSearchType({value}),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey('search-type-body-$_searchTypeTransition'),
                      child: switch (_searchType) {
                        _SearchType.tracks => _trackBody(context, desktop),
                        _SearchType.artists => _artistBody(context, desktop),
                        _SearchType.albums => _albumBody(context, desktop),
                        _SearchType.playlists => _playlistBody(
                          context,
                          desktop,
                        ),
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('track-search-back'),
          tooltip: l10n.searchBackTooltip,
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(l10n.navSearch),
      ),
      body: body,
      bottomNavigationBar: NowPlayingBar(
        controller: widget.queuePlaybackController,
        onSignInAgain: widget.onSignInAgain,
      ),
    );
  }

  bool get _isLoading => switch (_searchType) {
    _SearchType.tracks => _controller.stage == TrackSearchStage.loading,
    _SearchType.artists => _artistController.stage == ArtistSearchStage.loading,
    _SearchType.albums => _albumController.stage == AlbumSearchStage.loading,
    _SearchType.playlists =>
      _playlistController.stage == PlaylistSearchStage.loading,
  };

  String _providerName(AppLocalizations l10n) =>
      widget.providerDisplayName ?? l10n.providerQqMusic;

  Widget _trackBody(
    BuildContext context,
    bool desktop,
  ) => switch (_controller.stage) {
    TrackSearchStage.idle => MusicContentStatePanel(
      key: ValueKey('track-search-idle'),
      icon: Icons.search_rounded,
      title: context.l10n.searchFindTracksTitle(_providerName(context.l10n)),
      detail: context.l10n.searchTrackPrompt,
    ),
    TrackSearchStage.loading => MusicLoadingPanel(
      key: ValueKey('track-search-loading'),
      label: context.l10n.searchLoadingTracks(_providerName(context.l10n)),
    ),
    TrackSearchStage.empty => MusicContentStatePanel(
      key: const ValueKey('track-search-empty'),
      icon: Icons.search_off_rounded,
      title: context.l10n.searchNoTracksTitle,
      detail: context.l10n.searchNoResultsDetail,
      action: TextButton(
        onPressed: _focusQuery,
        child: Text(context.l10n.searchEditAction),
      ),
    ),
    TrackSearchStage.error => _searchFailure(
      key: const ValueKey('track-search-error'),
      detail: _trackFailureCopy(_controller.failure, context.l10n),
      canRetry: _controller.canRetry,
      onRetry: _controller.retry,
      onEdit: _focusQuery,
    ),
    TrackSearchStage.content => ValueListenableBuilder(
      valueListenable: widget.queuePlaybackController.currentTrackListenable,
      builder: (context, current, _) => _SearchResults(
        key: const ValueKey('track-search-content'),
        query: _controller.query,
        items: _controller.items,
        total: _controller.total,
        omittedItemCount: _controller.omittedItemCount,
        partialResultRevision: _controller.partialResultRevision,
        hasMore: _controller.hasMore,
        isLoadingMore: _controller.isLoadingMore,
        appendFailure: _controller.appendFailure,
        onLoadMore: _controller.loadMore,
        onRetryMore: _controller.retryMore,
        onPlay: _play,
        onQueue: _queue,
        onOpenAlbum: widget.onOpenAlbum,
        onOpenArtist: widget.onOpenArtist,
        current: current,
        desktop: desktop,
      ),
    ),
  };

  Widget _artistBody(BuildContext context, bool desktop) =>
      switch (_artistController.stage) {
        ArtistSearchStage.idle => MusicContentStatePanel(
          key: ValueKey('artist-search-idle'),
          icon: Icons.person_search_rounded,
          title: context.l10n.searchFindArtistsTitle(
            _providerName(context.l10n),
          ),
          detail: context.l10n.searchArtistPrompt,
        ),
        ArtistSearchStage.loading => MusicLoadingPanel(
          key: ValueKey('artist-search-loading'),
          label: context.l10n.searchLoadingArtists(_providerName(context.l10n)),
        ),
        ArtistSearchStage.empty => MusicContentStatePanel(
          key: const ValueKey('artist-search-empty'),
          icon: Icons.person_off_outlined,
          title: context.l10n.searchNoArtistsTitle,
          detail: context.l10n.searchNoResultsDetail,
          action: TextButton(
            onPressed: _focusQuery,
            child: Text(context.l10n.searchEditAction),
          ),
        ),
        ArtistSearchStage.error => _searchFailure(
          key: const ValueKey('artist-search-error'),
          detail: _artistFailureCopy(_artistController.failure, context.l10n),
          canRetry: _artistController.canRetry,
          onRetry: _artistController.retry,
          onEdit: _focusQuery,
        ),
        ArtistSearchStage.content => _ArtistSearchResults(
          key: const ValueKey('artist-search-content'),
          query: _artistController.query,
          artists: _artistController.artists,
          total: _artistController.total,
          omittedCount: _artistController.omittedArtistCount,
          partialResultRevision: _artistController.partialResultRevision,
          hasMore: _artistController.hasMore,
          isLoadingMore: _artistController.isLoadingMore,
          appendFailure: _artistController.appendFailure != null,
          onLoadMore: _artistController.loadMore,
          onRetryMore: _artistController.retryMore,
          onOpenArtist: widget.onOpenArtist,
          desktop: desktop,
        ),
      };

  Widget _albumBody(BuildContext context, bool desktop) =>
      switch (_albumController.stage) {
        AlbumSearchStage.idle => MusicContentStatePanel(
          key: ValueKey('album-search-idle'),
          icon: Icons.album_rounded,
          title: context.l10n.searchFindAlbumsTitle(
            _providerName(context.l10n),
          ),
          detail: context.l10n.searchAlbumPrompt,
        ),
        AlbumSearchStage.loading => MusicLoadingPanel(
          key: ValueKey('album-search-loading'),
          label: context.l10n.searchLoadingAlbums(_providerName(context.l10n)),
        ),
        AlbumSearchStage.empty => MusicContentStatePanel(
          key: const ValueKey('album-search-empty'),
          icon: Icons.album_outlined,
          title: context.l10n.searchNoAlbumsTitle,
          detail: context.l10n.searchNoResultsDetail,
          action: TextButton(
            onPressed: _focusQuery,
            child: Text(context.l10n.searchEditAction),
          ),
        ),
        AlbumSearchStage.error => _searchFailure(
          key: const ValueKey('album-search-error'),
          detail: _albumFailureCopy(_albumController.failure, context.l10n),
          canRetry: _albumController.canRetry,
          onRetry: _albumController.retry,
          onEdit: _focusQuery,
        ),
        AlbumSearchStage.content => _AlbumSearchResults(
          key: const ValueKey('album-search-content'),
          query: _albumController.query,
          albums: _albumController.albums,
          total: _albumController.total,
          omittedCount: _albumController.omittedAlbumCount,
          partialResultRevision: _albumController.partialResultRevision,
          hasMore: _albumController.hasMore,
          isLoadingMore: _albumController.isLoadingMore,
          appendFailure: _albumController.appendFailure != null,
          onLoadMore: _albumController.loadMore,
          onRetryMore: _albumController.retryMore,
          onOpenAlbum: widget.onOpenAlbum,
          desktop: desktop,
        ),
      };

  Widget _playlistBody(
    BuildContext context,
    bool desktop,
  ) => switch (_playlistController.stage) {
    PlaylistSearchStage.idle => MusicContentStatePanel(
      key: ValueKey('playlist-search-idle'),
      icon: Icons.queue_music_rounded,
      title: context.l10n.searchFindPlaylistsTitle(_providerName(context.l10n)),
      detail: context.l10n.searchPlaylistPrompt,
    ),
    PlaylistSearchStage.loading => MusicLoadingPanel(
      key: ValueKey('playlist-search-loading'),
      label: context.l10n.searchLoadingPlaylists(_providerName(context.l10n)),
    ),
    PlaylistSearchStage.empty => MusicContentStatePanel(
      key: const ValueKey('playlist-search-empty'),
      icon: Icons.playlist_remove_rounded,
      title: context.l10n.searchNoPlaylistsTitle,
      detail: context.l10n.searchNoResultsDetail,
      action: TextButton(
        onPressed: _focusQuery,
        child: Text(context.l10n.searchEditAction),
      ),
    ),
    PlaylistSearchStage.error => _searchFailure(
      key: const ValueKey('playlist-search-error'),
      detail: _playlistFailureCopy(_playlistController.failure, context.l10n),
      canRetry: _playlistController.canRetry,
      onRetry: _playlistController.retry,
      onEdit: _focusQuery,
    ),
    PlaylistSearchStage.content => _PlaylistSearchResults(
      key: const ValueKey('playlist-search-content'),
      query: _playlistController.query,
      playlists: _playlistController.playlists,
      total: _playlistController.total,
      omittedCount: _playlistController.omittedPlaylistCount,
      partialResultRevision: _playlistController.partialResultRevision,
      hasMore: _playlistController.hasMore,
      isLoadingMore: _playlistController.isLoadingMore,
      appendFailure: _playlistController.appendFailure != null,
      onLoadMore: _playlistController.loadMore,
      onRetryMore: _playlistController.retryMore,
      onOpenPlaylist: widget.onOpenPlaylist,
      desktop: desktop,
    ),
  };

  Widget _searchFailure({
    required Key key,
    required String detail,
    required bool canRetry,
    required VoidCallback onRetry,
    required VoidCallback onEdit,
  }) => MusicContentStatePanel(
    key: key,
    icon: Icons.cloud_off_rounded,
    title: context.l10n.searchFailureTitle(_providerName(context.l10n)),
    detail: detail,
    liveRegion: true,
    action: Wrap(
      spacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (canRetry)
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text(context.l10n.commonRetry),
          ),
        TextButton(
          onPressed: onEdit,
          child: Text(context.l10n.searchEditAction),
        ),
      ],
    ),
  );

  void _submit(String query) {
    _suggestionMenuController.close();
    _suggestionController.dismiss();
    switch (_searchType) {
      case _SearchType.tracks:
        unawaited(_controller.submit(query));
        break;
      case _SearchType.artists:
        unawaited(_artistController.submit(query));
        break;
      case _SearchType.albums:
        unawaited(_albumController.submit(query));
        break;
      case _SearchType.playlists:
        unawaited(_playlistController.submit(query));
        break;
    }
  }

  void _selectSearchType(Set<_SearchType> selection) {
    final next = selection.single;
    if (_searchType == next) return;
    _suggestionMenuController.close();
    _suggestionController.dismiss();
    final firstVisit = !_visitedTypes.contains(next);
    final currentText = _queryController.text.trim();
    setState(() {
      _searchType = next;
      _visitedTypes.add(next);
      _searchTypeTransition += 1;
    });
    if (firstVisit) {
      _replaceQueryText(currentText);
      if (currentText.isNotEmpty) _submit(currentText);
      return;
    }
    _replaceQueryText(switch (next) {
      _SearchType.tracks => _controller.query,
      _SearchType.artists => _artistController.query,
      _SearchType.albums => _albumController.query,
      _SearchType.playlists => _playlistController.query,
    });
  }

  void _replaceQueryText(String value) {
    _queryController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _clear() {
    _queryController.clear();
    _suggestionMenuController.close();
    _suggestionController.dismiss();
    switch (_searchType) {
      case _SearchType.tracks:
        _controller.clear();
        break;
      case _SearchType.artists:
        _artistController.clear();
        break;
      case _SearchType.albums:
        _albumController.clear();
        break;
      case _SearchType.playlists:
        _playlistController.clear();
        break;
    }
    _focusQuery();
  }

  void _focusQuery() {
    _queryFocusNode.requestFocus();
    _queryController.selection = TextSelection.collapsed(
      offset: _queryController.text.length,
    );
  }

  void _handleQueryFocus() {
    if (_queryFocusNode.hasFocus) {
      _suggestionController.updateQuery(_queryController.text);
    } else if (!_suggestionMenuController.isOpen) {
      _suggestionController.dismiss();
    }
  }

  void _handleSuggestions() {
    if (!mounted) return;
    final shouldOpen =
        _queryFocusNode.hasFocus && _suggestionController.visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shouldOpen && !_suggestionMenuController.isOpen) {
        _suggestionMenuController.open();
      } else if (!shouldOpen && _suggestionMenuController.isOpen) {
        _suggestionMenuController.close();
      }
      setState(() {});
    });
  }

  void _handleSuggestionMenuClosed() {
    if (_suggestionController.visible) _suggestionController.dismiss();
  }

  KeyEventResult _handleSuggestionKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      return _suggestionController.moveHighlight(1)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return _suggestionController.moveHighlight(-1)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final query = _suggestionController.highlightedQuery;
      if (query == null) return KeyEventResult.ignored;
      _selectSuggestion(query);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _suggestionController.visible) {
      _suggestionMenuController.close();
      _suggestionController.dismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _selectSuggestion(String query) {
    _suggestionMenuController.close();
    _replaceQueryText(query);
    _submit(query);
  }

  void _play(int index) {
    unawaited(
      widget.queuePlaybackController.replaceAndPlay(_controller.tracks, index),
    );
  }

  void _queue(PlaylistTrackSummary track) {
    final playbackStart = widget.queuePlaybackController.push(track);
    if (!mounted) {
      unawaited(playbackStart);
      return;
    }
    final message = widget.queuePlaybackController.failure == null
        ? context.l10n.queueAddedMessage
        : context.l10n.queueUpdateFailureMessage;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    unawaited(playbackStart);
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.desktop,
    required this.loading,
    required this.hintText,
    required this.onSubmitted,
    required this.onChanged,
    required this.suggestions,
    required this.menuController,
    required this.onSuggestionSelected,
    required this.onMenuClosed,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool desktop;
  final bool loading;
  final String hintText;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final TrackSearchSuggestionController suggestions;
  final MenuController menuController;
  final ValueChanged<String> onSuggestionSelected;
  final VoidCallback onMenuClosed;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      desktop ? 48 : 20,
      desktop ? 20 : 12,
      desktop ? 48 : 20,
      16,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: LayoutBuilder(
          builder: (context, constraints) => MenuAnchor(
            key: const ValueKey('track-search-suggestions-anchor'),
            controller: menuController,
            childFocusNode: focusNode,
            style: MenuStyle(
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              shadowColor: const WidgetStatePropertyAll(Colors.transparent),
              elevation: const WidgetStatePropertyAll(0),
              fixedSize: WidgetStatePropertyAll(
                Size.fromWidth(constraints.maxWidth),
              ),
              shape: const WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
            ),
            alignmentOffset: const Offset(0, 8),
            crossAxisUnconstrained: false,
            consumeOutsideTap: false,
            onClose: onMenuClosed,
            menuChildren: [
              TrackSearchSuggestionsPanel(
                controller: suggestions,
                popup: true,
                keyPrefix: 'track',
                onSelected: onSuggestionSelected,
              ),
            ],
            builder: (context, _, _) =>
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => TextField(
                    key: const ValueKey('track-search-field'),
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: onChanged,
                    onSubmitted: loading ? null : onSubmitted,
                    decoration: InputDecoration(
                      hintText: hintText,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: value.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: context.l10n.commonClearSearch,
                              onPressed: onClear,
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ),
    ),
  );
}

class _SearchResults extends StatefulWidget {
  const _SearchResults({
    required this.query,
    required this.items,
    required this.total,
    required this.omittedItemCount,
    required this.partialResultRevision,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onPlay,
    required this.onQueue,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required this.current,
    required this.desktop,
    super.key,
  });

  final String query;
  final List<TrackSearchItem> items;
  final int total;
  final int omittedItemCount;
  final int partialResultRevision;
  final bool hasMore;
  final bool isLoadingMore;
  final SearchFailure? appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<int> onPlay;
  final ValueChanged<PlaylistTrackSummary> onQueue;
  final ValueChanged<AlbumSummary> onOpenAlbum;
  final ValueChanged<ArtistSummary> onOpenArtist;
  final PlaylistTrackSummary? current;
  final bool desktop;

  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  final ScrollController _scrollController = ScrollController();
  (String, String)? _hoveredTrack;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setHovered(PlaylistTrackSummary track, bool hovered) {
    final identity = (track.providerId, track.opaqueId);
    if (hovered && _hoveredTrack != identity) {
      setState(() => _hoveredTrack = identity);
    } else if (!hovered && _hoveredTrack == identity) {
      setState(() => _hoveredTrack = null);
    }
  }

  bool _clearHoverOnScroll(ScrollNotification notification) {
    if (_hoveredTrack != null && notification is ScrollUpdateNotification) {
      setState(() => _hoveredTrack = null);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.desktop ? 48 : 20,
              8,
              widget.desktop ? 48 : 20,
              widget.desktop ? 8 : 12,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                header: true,
                child: Text(
                  context.l10n.searchResultCount(widget.total, widget.query),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          if (widget.omittedItemCount > 0)
            Padding(
              padding: EdgeInsets.fromLTRB(
                widget.desktop ? 48 : 20,
                0,
                widget.desktop ? 48 : 20,
                12,
              ),
              child: PartialResultsNotice(
                omittedCount: widget.omittedItemCount,
                resultRevision: widget.partialResultRevision,
              ),
            ),
          if (widget.desktop)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: MusicTrackTableHeader(
                titleLabel: context.l10n.tableTitle,
                artistLabel: context.l10n.tableArtist,
                albumLabel: context.l10n.tableAlbum,
                durationLabel: context.l10n.tableDuration,
              ),
            ),
          Expanded(
            child: MusicTrackLocatorOverlay(
              controller: _scrollController,
              currentIndex: musicTrackIndexOf(
                widget.items.map((item) => item.track).toList(growable: false),
                widget.current,
              ),
              desktop: widget.desktop,
              itemExtent: musicTrackRowExtent(
                desktop: widget.desktop,
                includesSeparator: false,
              ),
              child: BoundedViewportPageDemand(
                enabled:
                    widget.hasMore &&
                    !widget.isLoadingMore &&
                    widget.appendFailure == null,
                generation: widget.query,
                onDemand: widget.onLoadMore,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _clearHoverOnScroll,
                  child: ListView.builder(
                    controller: _scrollController,
                    key: const PageStorageKey('track-search-results'),
                    padding: EdgeInsets.fromLTRB(
                      widget.desktop ? 40 : 12,
                      0,
                      widget.desktop ? 40 : 12,
                      24,
                    ),
                    itemCount: widget.items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == widget.items.length) {
                        return _SearchFooter(
                          hasMore: widget.hasMore,
                          isLoadingMore: widget.isLoadingMore,
                          appendFailure: widget.appendFailure != null,
                          onLoadMore: widget.onLoadMore,
                          onRetryMore: widget.onRetryMore,
                        );
                      }
                      final item = widget.items[index];
                      final identity = (
                        item.track.providerId,
                        item.track.opaqueId,
                      );
                      return _SearchTrackRow(
                        track: item.track,
                        album: item.album,
                        artists: item.artists,
                        index: index,
                        desktop: widget.desktop,
                        current:
                            item.track.providerId ==
                                widget.current?.providerId &&
                            item.track.opaqueId == widget.current?.opaqueId,
                        hovered: _hoveredTrack == identity,
                        onHoverChanged: (hovered) =>
                            _setHovered(item.track, hovered),
                        onPlay: () => widget.onPlay(index),
                        onQueue: () => widget.onQueue(item.track),
                        onOpenAlbum: item.album == null
                            ? null
                            : () => widget.onOpenAlbum(item.album!),
                        onOpenArtist: widget.onOpenArtist,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ArtistSearchResults extends StatelessWidget {
  const _ArtistSearchResults({
    required this.query,
    required this.artists,
    required this.total,
    required this.omittedCount,
    required this.partialResultRevision,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onOpenArtist,
    required this.desktop,
    super.key,
  });

  final String query;
  final List<ArtistSummary> artists;
  final int total;
  final int omittedCount;
  final int partialResultRevision;
  final bool hasMore;
  final bool isLoadingMore;
  final bool appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<ArtistSummary> onOpenArtist;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: BoundedViewportPageDemand(
        enabled: hasMore && !isLoadingMore && !appendFailure,
        generation: query,
        onDemand: onLoadMore,
        child: ListView.builder(
          key: const PageStorageKey('artist-search-results'),
          padding: EdgeInsets.fromLTRB(
            desktop ? 40 : 12,
            0,
            desktop ? 40 : 12,
            24,
          ),
          itemCount: artists.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
                    child: Semantics(
                      header: true,
                      child: Text(
                        context.l10n.searchArtistResultCount(total, query),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (omittedCount > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
                      child: PartialResultsNotice(
                        omittedCount: omittedCount,
                        resultRevision: partialResultRevision,
                      ),
                    ),
                ],
              );
            }
            if (index == artists.length + 1) {
              return _SearchFooter(
                hasMore: hasMore,
                isLoadingMore: isLoadingMore,
                appendFailure: appendFailure,
                onLoadMore: onLoadMore,
                onRetryMore: onRetryMore,
              );
            }
            final artistIndex = index - 1;
            final artist = artists[artistIndex];
            return ListTile(
              key: ValueKey('artist-search-result-$artistIndex'),
              minTileHeight: desktop ? 68 : 72,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: SizedBox.square(
                dimension: desktop ? 48 : 52,
                child: ArtistArtwork(uri: artist.artworkUri, iconSize: 24),
              ),
              title: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(context.l10n.searchArtistResultType),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onOpenArtist(artist),
            );
          },
        ),
      ),
    ),
  );
}

class _AlbumSearchResults extends StatelessWidget {
  const _AlbumSearchResults({
    required this.query,
    required this.albums,
    required this.total,
    required this.omittedCount,
    required this.partialResultRevision,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onOpenAlbum,
    required this.desktop,
    super.key,
  });

  final String query;
  final List<AlbumSummary> albums;
  final int total;
  final int omittedCount;
  final int partialResultRevision;
  final bool hasMore;
  final bool isLoadingMore;
  final bool appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<AlbumSummary> onOpenAlbum;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: BoundedViewportPageDemand(
        enabled: hasMore && !isLoadingMore && !appendFailure,
        generation: query,
        onDemand: onLoadMore,
        child: ListView.builder(
          key: const PageStorageKey('album-search-results'),
          padding: EdgeInsets.fromLTRB(
            desktop ? 40 : 12,
            0,
            desktop ? 40 : 12,
            24,
          ),
          itemCount: albums.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
                    child: Semantics(
                      header: true,
                      child: Text(
                        context.l10n.searchAlbumResultCount(total, query),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (omittedCount > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
                      child: PartialResultsNotice(
                        omittedCount: omittedCount,
                        resultRevision: partialResultRevision,
                      ),
                    ),
                ],
              );
            }
            if (index == albums.length + 1) {
              return _SearchFooter(
                hasMore: hasMore,
                isLoadingMore: isLoadingMore,
                appendFailure: appendFailure,
                onLoadMore: onLoadMore,
                onRetryMore: onRetryMore,
              );
            }
            final albumIndex = index - 1;
            final album = albums[albumIndex];
            return ListTile(
              key: ValueKey('album-search-result-$albumIndex'),
              minTileHeight: desktop ? 68 : 72,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: SizedBox.square(
                dimension: desktop ? 48 : 52,
                child: _TrackArtwork(uri: album.artworkUri),
              ),
              title: Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(context.l10n.searchAlbumResultType),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onOpenAlbum(album),
            );
          },
        ),
      ),
    ),
  );
}

class _PlaylistSearchResults extends StatelessWidget {
  const _PlaylistSearchResults({
    required this.query,
    required this.playlists,
    required this.total,
    required this.omittedCount,
    required this.partialResultRevision,
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onOpenPlaylist,
    required this.desktop,
    super.key,
  });

  final String query;
  final List<UserPlaylistSummary> playlists;
  final int total;
  final int omittedCount;
  final int partialResultRevision;
  final bool hasMore;
  final bool isLoadingMore;
  final bool appendFailure;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final ValueChanged<UserPlaylistSummary> onOpenPlaylist;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: BoundedViewportPageDemand(
        enabled: hasMore && !isLoadingMore && !appendFailure,
        generation: query,
        onDemand: onLoadMore,
        child: ListView.builder(
          key: const PageStorageKey('playlist-search-results'),
          padding: EdgeInsets.fromLTRB(
            desktop ? 40 : 12,
            0,
            desktop ? 40 : 12,
            24,
          ),
          itemCount: playlists.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
                    child: Semantics(
                      header: true,
                      child: Text(
                        context.l10n.searchPlaylistResultCount(total, query),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (omittedCount > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
                      child: PartialResultsNotice(
                        omittedCount: omittedCount,
                        resultRevision: partialResultRevision,
                      ),
                    ),
                ],
              );
            }
            if (index == playlists.length + 1) {
              return _SearchFooter(
                hasMore: hasMore,
                isLoadingMore: isLoadingMore,
                appendFailure: appendFailure,
                onLoadMore: onLoadMore,
                onRetryMore: onRetryMore,
              );
            }
            final playlistIndex = index - 1;
            final playlist = playlists[playlistIndex];
            return ListTile(
              key: ValueKey('playlist-search-result-$playlistIndex'),
              minTileHeight: desktop ? 68 : 72,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: SizedBox.square(
                dimension: desktop ? 48 : 52,
                child: _PlaylistArtwork(uri: playlist.artworkUri),
              ),
              title: Text(
                playlist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: playlist.trackCount == null
                  ? Text(context.l10n.searchPlaylistResultType)
                  : Text(context.l10n.trackCount(playlist.trackCount!)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onOpenPlaylist(playlist),
            );
          },
        ),
      ),
    ),
  );
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({this.uri});

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
      child: Icon(
        Icons.queue_music_rounded,
        color: colors.onSecondaryContainer,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: uri == null
          ? placeholder
          : Image.network(
              uri!,
              headers: musicArtworkRequestHeaders(uri!),
              fit: BoxFit.cover,
              errorBuilder: musicArtworkErrorBuilder(uri!, placeholder),
            ),
    );
  }
}

class _SearchTrackRow extends StatefulWidget {
  const _SearchTrackRow({
    required this.track,
    required this.album,
    required this.artists,
    required this.index,
    required this.desktop,
    required this.current,
    required this.hovered,
    required this.onHoverChanged,
    required this.onPlay,
    required this.onQueue,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

  final PlaylistTrackSummary track;
  final AlbumSummary? album;
  final List<ArtistSummary> artists;
  final int index;
  final bool desktop;
  final bool current;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onPlay;
  final VoidCallback onQueue;
  final VoidCallback? onOpenAlbum;
  final ValueChanged<ArtistSummary> onOpenArtist;

  @override
  State<_SearchTrackRow> createState() => _SearchTrackRowState();
}

class _SearchTrackRowState extends State<_SearchTrackRow> {
  @override
  Widget build(BuildContext context) {
    final artistCopy = widget.track.artistNames.isEmpty
        ? context.l10n.trackUnknownArtist
        : widget.track.artistNames.join(' · ');
    final title = widget.track.subtitle == null
        ? widget.track.title
        : '${widget.track.title} · ${widget.track.subtitle}';
    return MusicTrackRowSurface(
      itemKey: ValueKey('track-search-result-${widget.index}'),
      desktop: widget.desktop,
      current: widget.current,
      hovered: widget.hovered,
      onHoverChanged: widget.onHoverChanged,
      semanticLabel: context.l10n.commonTrackSemantics(artistCopy, title),
      onTap: widget.onPlay,
      onContextMenuRequested: (position) => unawaited(
        position == null
            ? _showCompactActions()
            : _showDesktopActions(position),
      ),
      contentBuilder: (context, active, hovered) => MusicTrackRowContent(
        index: widget.index + 1,
        track: widget.track,
        title: title,
        desktop: widget.desktop,
        current: widget.current,
        active: active,
        artistNames: artistCopy,
        onPlay: widget.onPlay,
        onAddToQueue: widget.onQueue,
        onOpenAlbum: widget.onOpenAlbum,
        onOpenArtist: widget.artists.isEmpty ? null : _openArtist,
        onMore: () => unawaited(_showCompactActions()),
        showInlineQueueAction: hovered,
        queueKey: ValueKey('track-search-queue-${widget.index}'),
        moreKey: ValueKey('track-search-more-${widget.index}'),
        artistTooltip: widget.artists.length > 1
            ? context.l10n.commonChooseArtist
            : context.l10n.commonOpenArtist,
      ),
    );
  }

  Future<void> _showDesktopActions(Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final action = await showMenu<MusicTrackAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: _menuItems(),
    );
    _runAction(action);
  }

  Future<void> _showCompactActions() async {
    final action = await showModalBottomSheet<MusicTrackAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: ValueKey('track-search-play-${widget.index}'),
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text(context.l10n.commonPlayFromHere),
              onTap: () => Navigator.pop(context, MusicTrackAction.play),
            ),
            ListTile(
              key: ValueKey('track-search-add-to-queue-${widget.index}'),
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(context.l10n.commonAddToQueue),
              onTap: () => Navigator.pop(context, MusicTrackAction.addToQueue),
            ),
            if (widget.album != null)
              ListTile(
                key: ValueKey('track-search-album-${widget.index}'),
                leading: const Icon(Icons.album_rounded),
                title: Text(context.l10n.commonOpenAlbum),
                onTap: () => Navigator.pop(context, MusicTrackAction.openAlbum),
              ),
            if (widget.artists.isNotEmpty)
              ListTile(
                key: ValueKey('track-search-artist-${widget.index}'),
                leading: const Icon(Icons.person_rounded),
                title: Text(context.l10n.commonOpenArtist),
                onTap: () =>
                    Navigator.pop(context, MusicTrackAction.openArtist),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    _runAction(action);
  }

  List<PopupMenuEntry<MusicTrackAction>> _menuItems() => [
    PopupMenuItem(
      value: MusicTrackAction.play,
      child: ListTile(
        leading: const Icon(Icons.play_arrow_rounded),
        title: Text(context.l10n.commonPlayFromHere),
      ),
    ),
    PopupMenuItem(
      value: MusicTrackAction.addToQueue,
      child: ListTile(
        leading: const Icon(Icons.playlist_add_rounded),
        title: Text(context.l10n.commonAddToQueue),
      ),
    ),
    if (widget.album != null)
      PopupMenuItem(
        value: MusicTrackAction.openAlbum,
        child: ListTile(
          leading: const Icon(Icons.album_rounded),
          title: Text(context.l10n.commonOpenAlbum),
        ),
      ),
    if (widget.artists.isNotEmpty)
      PopupMenuItem(
        value: MusicTrackAction.openArtist,
        child: ListTile(
          leading: const Icon(Icons.person_rounded),
          title: Text(context.l10n.commonOpenArtist),
        ),
      ),
  ];

  void _runAction(MusicTrackAction? action) {
    switch (action) {
      case MusicTrackAction.play:
        widget.onPlay();
      case MusicTrackAction.addToQueue:
        widget.onQueue();
      case MusicTrackAction.openAlbum:
        widget.onOpenAlbum?.call();
      case MusicTrackAction.openArtist:
        unawaited(_openArtist());
      case null:
        return;
    }
  }

  Future<void> _openArtist() => openMusicTrackArtists(
    context: context,
    artists: widget.artists,
    onSelected: widget.onOpenArtist,
    title: context.l10n.trackChooseArtistTitle,
    detail: context.l10n.searchBrowseCreditedArtists,
    itemKeyPrefix: 'track-search-artist-${widget.index}',
  );
}

class _TrackArtwork extends StatelessWidget {
  const _TrackArtwork({this.uri});

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
      child: Icon(Icons.music_note_rounded, color: colors.onPrimaryContainer),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: uri == null
          ? placeholder
          : Image.network(
              uri!,
              headers: musicArtworkRequestHeaders(uri!),
              fit: BoxFit.cover,
              errorBuilder: musicArtworkErrorBuilder(uri!, placeholder),
            ),
    );
  }
}

class _SearchFooter extends StatelessWidget {
  const _SearchFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final bool appendFailure;
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
          : appendFailure
          ? FilledButton.tonal(
              onPressed: onRetryMore,
              child: Text(context.l10n.commonTryLoadingMoreAgain),
            )
          : hasMore
          ? FilledButton.tonal(
              key: const ValueKey('track-search-load-more'),
              onPressed: onLoadMore,
              child: Text(context.l10n.commonLoadMore),
            )
          : Text(
              context.l10n.searchEndOfResults,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    ),
  );
}

String _trackFailureCopy(SearchFailure? failure, AppLocalizations l10n) =>
    switch (failure) {
      SearchFailure.network => l10n.searchNetworkFailure,
      SearchFailure.serviceUnavailable => l10n.searchServiceUnavailable,
      SearchFailure.cancelled => l10n.searchCancelled,
      SearchFailure.coreUnavailable => l10n.searchCoreUnavailable,
      SearchFailure.invalidResponse ||
      SearchFailure.alreadyRunning ||
      null => l10n.searchUnexpectedResponse,
    };

String _artistFailureCopy(SearchFailure? failure, AppLocalizations l10n) =>
    switch (failure) {
      SearchFailure.network => l10n.searchNetworkFailure,
      SearchFailure.serviceUnavailable => l10n.searchArtistServiceUnavailable,
      SearchFailure.cancelled => l10n.searchArtistCancelled,
      SearchFailure.coreUnavailable => l10n.searchCoreUnavailable,
      SearchFailure.invalidResponse ||
      SearchFailure.alreadyRunning ||
      null => l10n.searchArtistUnexpectedResponse,
    };

String _albumFailureCopy(SearchFailure? failure, AppLocalizations l10n) =>
    switch (failure) {
      SearchFailure.network => l10n.searchNetworkFailure,
      SearchFailure.serviceUnavailable => l10n.searchAlbumServiceUnavailable,
      SearchFailure.cancelled => l10n.searchAlbumCancelled,
      SearchFailure.coreUnavailable => l10n.searchCoreUnavailable,
      SearchFailure.invalidResponse ||
      SearchFailure.alreadyRunning ||
      null => l10n.searchAlbumUnexpectedResponse,
    };

String _playlistFailureCopy(SearchFailure? failure, AppLocalizations l10n) =>
    switch (failure) {
      SearchFailure.network => l10n.searchNetworkFailure,
      SearchFailure.serviceUnavailable => l10n.searchPlaylistServiceUnavailable,
      SearchFailure.cancelled => l10n.searchPlaylistCancelled,
      SearchFailure.coreUnavailable => l10n.searchCoreUnavailable,
      SearchFailure.invalidResponse ||
      SearchFailure.alreadyRunning ||
      null => l10n.searchPlaylistUnexpectedResponse,
    };
