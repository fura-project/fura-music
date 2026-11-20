import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/catalog/music_artwork_placeholder.dart';
import 'package:flutterustmusic/fura_toast.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/library/library_mutation_feedback.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_track_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class PlaylistTrackPresentationController extends ChangeNotifier {
  PlaylistTrackPresentationController({
    required this.providerId,
    required this.enabled,
    required this.library,
    required this.gateway,
    required this.mutations,
  }) {
    library.addListener(_libraryChanged);
  }

  final String providerId;
  final bool enabled;
  final UserLibraryController library;
  final PlaylistDetailGateway gateway;
  final LibraryMutationCoordinator mutations;

  final Set<PlaylistTrackPageLoadOperation> _reads = {};
  final Map<_PlaylistPageKey, _SharedPlaylistPage> _sharedPages = {};
  int _generation = 0;
  bool _disposed = false;

  late final PlaylistDetailGateway sessionGateway = _PlaylistSessionGateway(
    this,
  );

  List<UserPlaylistSummary> get ownedPlaylists => enabled
      ? library.playlists
            .where(
              (playlist) =>
                  playlist.providerId == providerId &&
                  playlist.ownership == UserPlaylistOwnership.owned &&
                  !playlist.isLikedSongs,
            )
            .toList(growable: false)
      : const [];

  void invalidateSessionCache(UserPlaylistSummary playlist) {
    final keys = _sharedPages.keys
        .where(
          (key) =>
              key.providerId == playlist.providerId &&
              key.opaqueId == playlist.opaqueId,
        )
        .toList(growable: false);
    for (final key in keys) {
      _sharedPages.remove(key)?.source.cancel();
    }
  }

  Future<LibraryMutationOutcome<PlaylistTrackState>> addTrack({
    required UserPlaylistSummary playlist,
    required PlaylistTrackSummary track,
  }) => mutations.setPlaylistTrack(
    playlist: playlist,
    track: track,
    present: true,
    refreshAuthoritativeState: () {
      invalidateSessionCache(playlist);
      return _readMembership(playlist, track);
    },
  );

  Future<void> _readMembership(
    UserPlaylistSummary playlist,
    PlaylistTrackSummary target,
  ) async {
    var offset = 0;
    while (!_disposed) {
      final operation = sessionGateway.beginLoad(
        playlist: playlist,
        offset: offset,
        size: PlaylistDetailController.pageSize,
      );
      _reads.add(operation);
      final result = await operation.run();
      _reads.remove(operation);
      if (_disposed ||
          result.failure != null ||
          result.offset != offset ||
          result.tracks.any(
            (track) =>
                track.providerId == target.providerId &&
                track.opaqueId == target.opaqueId,
          ) ||
          !result.hasMore) {
        return;
      }
      if (result.nextOffset <= offset) return;
      offset = result.nextOffset;
    }
  }

  PlaylistTrackPageLoadOperation _beginSharedLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    final key = _PlaylistPageKey(
      playlist.providerId,
      playlist.opaqueId,
      offset,
      size,
    );
    var page = _sharedPages[key];
    if (page == null) {
      final source = gateway.beginLoad(
        playlist: playlist,
        offset: offset,
        size: size,
      );
      final generation = _generation;
      late final _SharedPlaylistPage created;
      final future = source.run().then((result) {
        if (!_disposed &&
            generation == _generation &&
            identical(_sharedPages[key], created)) {
          if (result.failure == null && result.offset == offset) {
            created.resolved = result;
          } else {
            _sharedPages.remove(key);
          }
        }
        return result;
      });
      created = _SharedPlaylistPage(source, future);
      page = created;
      _sharedPages[key] = page;
    }
    return _JoinedPlaylistPageLoadOperation(page);
  }

  void _libraryChanged() => notifyListeners();

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    library.removeListener(_libraryChanged);
    for (final read in _reads) {
      read.cancel();
    }
    _reads.clear();
    for (final page in _sharedPages.values) {
      page.source.cancel();
    }
    _sharedPages.clear();
    super.dispose();
  }
}

class _PlaylistSessionGateway implements PlaylistDetailGateway {
  const _PlaylistSessionGateway(this.owner);

  final PlaylistTrackPresentationController owner;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) => owner._beginSharedLoad(playlist: playlist, offset: offset, size: size);
}

@immutable
class _PlaylistPageKey {
  const _PlaylistPageKey(
    this.providerId,
    this.opaqueId,
    this.offset,
    this.size,
  );

  final String providerId;
  final String opaqueId;
  final int offset;
  final int size;

  @override
  bool operator ==(Object other) =>
      other is _PlaylistPageKey &&
      other.providerId == providerId &&
      other.opaqueId == opaqueId &&
      other.offset == offset &&
      other.size == size;

  @override
  int get hashCode => Object.hash(providerId, opaqueId, offset, size);
}

class _SharedPlaylistPage {
  _SharedPlaylistPage(this.source, this.future);

  final PlaylistTrackPageLoadOperation source;
  final Future<PlaylistTrackPageResult> future;
  PlaylistTrackPageResult? resolved;
}

class _JoinedPlaylistPageLoadOperation
    implements PlaylistTrackPageLoadOperation {
  _JoinedPlaylistPageLoadOperation(this._page);

  final _SharedPlaylistPage _page;
  bool _active = true;

  @override
  bool cancel() {
    final wasActive = _active;
    _active = false;
    return wasActive;
  }

  @override
  Future<PlaylistTrackPageResult> run() {
    if (!_active) {
      return SynchronousFuture(
        const PlaylistTrackPageResult(failure: UserLibraryFailure.cancelled),
      );
    }
    final resolved = _page.resolved;
    if (resolved != null) {
      return SynchronousFuture(resolved);
    }
    return _page.future.then(
      (result) => _active
          ? result
          : const PlaylistTrackPageResult(
              failure: UserLibraryFailure.cancelled,
            ),
    );
  }
}

class PlaylistTrackActionScope
    extends InheritedNotifier<PlaylistTrackPresentationController> {
  const PlaylistTrackActionScope({
    required PlaylistTrackPresentationController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static PlaylistTrackPresentationController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PlaylistTrackActionScope>()
          ?.notifier;

  static PlaylistTrackPresentationController? readOf(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<PlaylistTrackActionScope>()
          ?.notifier;
}

Future<void> showAddTrackToPlaylist({
  required BuildContext context,
  required PlaylistTrackSummary track,
}) async {
  final controller = PlaylistTrackActionScope.maybeOf(context);
  final playlists = controller?.ownedPlaylists ?? const [];
  if (controller == null || playlists.isEmpty) return;
  final compact = MediaQuery.sizeOf(context).width < 600;
  final selected = compact
      ? await showModalBottomSheet<UserPlaylistSummary>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  ListTile(
                    title: Text(
                      context.l10n.libraryChoosePlaylist,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  for (final playlist in playlists)
                    _PlaylistPickerTile(
                      playlist: playlist,
                      onTap: () => Navigator.pop(context, playlist),
                    ),
                ],
              ),
            ),
          ),
        )
      : await showDialog<UserPlaylistSummary>(
          context: context,
          animationStyle: furaDialogAnimationStyle(context),
          builder: (context) => FuraDialogTransition(
            child: AlertDialog(
              title: Text(context.l10n.libraryChoosePlaylist),
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 420,
                  maxHeight: 480,
                ),
                child: SizedBox(
                  width: 400,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return _PlaylistPickerTile(
                        playlist: playlist,
                        onTap: () => Navigator.pop(context, playlist),
                      );
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.commonCancel),
                ),
              ],
            ),
          ),
        );
  if (selected == null || !context.mounted) return;
  final outcome = await controller.addTrack(playlist: selected, track: track);
  if (!context.mounted) return;
  showLibraryMutationFeedback(context, outcome.status);
}

class _PlaylistPickerTile extends StatelessWidget {
  const _PlaylistPickerTile({required this.playlist, required this.onTap});

  final UserPlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final trackCount = playlist.trackCount;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: _PlaylistPickerArtwork(uri: playlist.artworkUri),
      title: Text(playlist.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: trackCount != null
          ? Text(context.l10n.likedTrackCount(trackCount))
          : null,
      onTap: onTap,
    );
  }
}

class _PlaylistPickerArtwork extends StatelessWidget {
  const _PlaylistPickerArtwork({required this.uri});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    final editorial = context.editorialTheme;
    final radius = editorial.isEditorial
        ? editorial.artworkRadius
        : BorderRadius.circular(10);
    const fallback = MusicArtworkPlaceholder(kind: MusicArtworkKind.playlist);
    final resolvedUri = uri;
    final clipped = ClipRRect(
      borderRadius: radius,
      child: resolvedUri == null
          ? fallback
          : Image.network(
              resolvedUri,
              headers: musicArtworkRequestHeaders(resolvedUri),
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              gaplessPlayback: true,
              frameBuilder: musicArtworkFrameBuilder(fallback),
              errorBuilder: musicArtworkErrorBuilder(resolvedUri, fallback),
            ),
    );
    return SizedBox.square(
      dimension: 44,
      child: editorial.isEditorial
          ? DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: editorial.hairline),
              ),
              child: clipped,
            )
          : clipped,
    );
  }
}
