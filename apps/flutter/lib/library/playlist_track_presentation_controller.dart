import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/library/library_mutation_feedback.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_track_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';

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
  bool _disposed = false;

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

  Future<LibraryMutationOutcome<PlaylistTrackState>> addTrack({
    required UserPlaylistSummary playlist,
    required PlaylistTrackSummary track,
  }) => mutations.setPlaylistTrack(
    playlist: playlist,
    track: track,
    present: true,
    refreshAuthoritativeState: () => _readMembership(playlist, track),
  );

  Future<void> _readMembership(
    UserPlaylistSummary playlist,
    PlaylistTrackSummary target,
  ) async {
    var offset = 0;
    while (!_disposed) {
      final operation = gateway.beginLoad(
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

  void _libraryChanged() => notifyListeners();

  @override
  void dispose() {
    _disposed = true;
    library.removeListener(_libraryChanged);
    for (final read in _reads) {
      read.cancel();
    }
    _reads.clear();
    super.dispose();
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
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(title: Text(context.l10n.libraryChoosePlaylist)),
                for (final playlist in playlists)
                  ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: Text(playlist.title),
                    onTap: () => Navigator.pop(context, playlist),
                  ),
              ],
            ),
          ),
        )
      : await showDialog<UserPlaylistSummary>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.libraryChoosePlaylist),
            content: SizedBox(
              width: 400,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final playlist in playlists)
                    ListTile(
                      leading: const Icon(Icons.queue_music_rounded),
                      title: Text(playlist.title),
                      onTap: () => Navigator.pop(context, playlist),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.commonCancel),
              ),
            ],
          ),
        );
  if (selected == null || !context.mounted) return;
  final outcome = await controller.addTrack(playlist: selected, track: track);
  if (!context.mounted) return;
  showLibraryMutationFeedback(context, outcome.status);
}
