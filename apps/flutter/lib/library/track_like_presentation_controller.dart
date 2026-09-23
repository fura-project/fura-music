import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/library/library_mutation_feedback.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/track_like_gateway.dart';

enum AuthoritativeTrackLikeState {
  unavailable,
  unknown,
  loading,
  liked,
  notLiked,
}

/// Resolves Track like state from the Provider-owned Liked Songs collection.
///
/// A positive match is authoritative as soon as it is observed. A negative
/// result is exposed only after the collection ends with an exact total and no
/// omitted rows. Remote writes remain owned by [LibraryMutationCoordinator].
class TrackLikePresentationController extends ChangeNotifier {
  TrackLikePresentationController({
    required this.providerId,
    required this.enabled,
    required this.playlistGateway,
    required this.mutations,
  });

  final String providerId;
  final bool enabled;
  final PlaylistDetailGateway playlistGateway;
  final LibraryMutationCoordinator mutations;

  UserPlaylistSummary? _likedPlaylist;
  final Set<String> _likedTrackIds = <String>{};
  final Set<String> _requestedTrackIds = <String>{};
  Future<void>? _scan;
  PlaylistTrackPageLoadOperation? _operation;
  bool _complete = false;
  bool _loading = false;
  bool _scanReliable = true;
  int _generation = 0;
  bool _disposed = false;

  void bindLikedPlaylist(UserPlaylistSummary? playlist) {
    final valid =
        enabled &&
        playlist != null &&
        playlist.providerId == providerId &&
        playlist.isLikedSongs;
    final next = valid ? playlist : null;
    if (_samePlaylist(_likedPlaylist, next)) return;
    _invalidate(next);
  }

  AuthoritativeTrackLikeState stateFor(PlaylistTrackSummary track) {
    if (!enabled || track.providerId != providerId || _likedPlaylist == null) {
      return AuthoritativeTrackLikeState.unavailable;
    }
    if (_likedTrackIds.contains(track.opaqueId)) {
      return AuthoritativeTrackLikeState.liked;
    }
    if (_complete && _scanReliable) {
      return AuthoritativeTrackLikeState.notLiked;
    }
    if (_loading && _requestedTrackIds.contains(track.opaqueId)) {
      return AuthoritativeTrackLikeState.loading;
    }
    return AuthoritativeTrackLikeState.unknown;
  }

  Future<AuthoritativeTrackLikeState> resolve(
    PlaylistTrackSummary track,
  ) async {
    final initial = stateFor(track);
    if (initial == AuthoritativeTrackLikeState.unavailable ||
        initial == AuthoritativeTrackLikeState.liked ||
        initial == AuthoritativeTrackLikeState.notLiked) {
      return initial;
    }
    _requestedTrackIds.add(track.opaqueId);
    if (!_loading) {
      _loading = true;
      _notify();
    }
    final scan = _scan ??= _scanLikedSongs(_generation);
    await scan;
    if (identical(_scan, scan)) _scan = null;
    return stateFor(track);
  }

  Future<LibraryMutationOutcome<TrackLikeState>> setLiked({
    required PlaylistTrackSummary track,
    required bool liked,
    Future<void> Function()? refreshAdditionalState,
  }) => mutations.setTrackLiked(
    track: track,
    liked: liked,
    refreshAuthoritativeState: () async {
      _invalidate(_likedPlaylist);
      if (refreshAdditionalState != null) await refreshAdditionalState();
      await resolve(track);
    },
  );

  Future<void> _scanLikedSongs(int generation) async {
    final playlist = _likedPlaylist;
    if (playlist == null) {
      _finishScan(generation, reliable: false);
      return;
    }
    var offset = 0;
    var reliable = true;
    while (_isCurrent(generation)) {
      late final PlaylistTrackPageLoadOperation operation;
      try {
        operation = playlistGateway.beginLoad(
          playlist: playlist,
          offset: offset,
          size: PlaylistDetailController.pageSize,
        );
      } on Object {
        reliable = false;
        break;
      }
      _operation = operation;
      final result = await operation.run();
      if (identical(_operation, operation)) _operation = null;
      if (!_isCurrent(generation)) return;
      if (result.failure != null || result.offset != offset) {
        reliable = false;
        break;
      }
      reliable =
          reliable && result.totalIsExact && result.omittedTrackCount == 0;
      for (final track in result.tracks) {
        if (track.providerId == providerId) {
          _likedTrackIds.add(track.opaqueId);
        }
      }
      _notify();
      if (_requestedTrackIds.isNotEmpty &&
          _requestedTrackIds.every(_likedTrackIds.contains)) {
        break;
      }
      if (!result.hasMore) {
        _complete = true;
        break;
      }
      if (result.nextOffset <= offset) {
        reliable = false;
        break;
      }
      offset = result.nextOffset;
    }
    _finishScan(generation, reliable: reliable && _complete);
  }

  void _finishScan(int generation, {required bool reliable}) {
    if (!_isCurrent(generation)) return;
    _scanReliable = reliable;
    _loading = false;
    _notify();
  }

  void _invalidate(UserPlaylistSummary? playlist) {
    _generation += 1;
    _operation?.cancel();
    _operation = null;
    _scan = null;
    _likedPlaylist = playlist;
    _likedTrackIds.clear();
    _requestedTrackIds.clear();
    _complete = false;
    _loading = false;
    _scanReliable = true;
    _notify();
  }

  bool _samePlaylist(UserPlaylistSummary? left, UserPlaylistSummary? right) =>
      left?.providerId == right?.providerId &&
      left?.opaqueId == right?.opaqueId &&
      left?.isLikedSongs == right?.isLikedSongs;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _operation?.cancel();
    _operation = null;
    super.dispose();
  }
}

class TrackLikeActionScope
    extends InheritedNotifier<TrackLikePresentationController> {
  const TrackLikeActionScope({
    required TrackLikePresentationController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static TrackLikePresentationController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TrackLikeActionScope>()
          ?.notifier;
}

Future<void> performTrackLikeAction({
  required BuildContext context,
  required PlaylistTrackSummary track,
  required bool liked,
  Future<void> Function()? refreshAdditionalState,
}) async {
  final controller = TrackLikeActionScope.maybeOf(context);
  if (controller == null) return;
  final outcome = await controller.setLiked(
    track: track,
    liked: liked,
    refreshAdditionalState: refreshAdditionalState,
  );
  if (!context.mounted) return;
  showLibraryMutationFeedback(context, outcome.status);
}
