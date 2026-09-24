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

/// Account-session owner for Track membership in the Provider's Liked Songs.
///
/// Presentation pages and Heart controls share the same bounded page futures.
/// Provider-owned opaque identities are retained independently from rows that
/// can be rendered as a complete [PlaylistTrackSummary].
class TrackLikePresentationController extends ChangeNotifier {
  TrackLikePresentationController({
    required this.providerId,
    required this.enabled,
    required PlaylistDetailGateway playlistGateway,
    required this.mutations,
  }) : _sourceGateway = playlistGateway {
    sessionGateway = _TrackMembershipGateway(this);
  }

  final String providerId;
  final bool enabled;
  final PlaylistDetailGateway _sourceGateway;
  final LibraryMutationCoordinator mutations;
  late final PlaylistDetailGateway sessionGateway;

  UserPlaylistSummary? _likedPlaylist;
  final Set<String> _likedTrackIds = <String>{};
  final Map<String, bool> _confirmedOverrides = <String, bool>{};
  final Set<String> _requestedTrackIds = <String>{};
  final Set<String> _needsReconciliation = <String>{};
  final Map<_TrackPageKey, _SharedTrackPage> _sharedPages = {};
  Future<void>? _scan;
  Future<void>? _refresh;
  PlaylistTrackPageLoadOperation? _operation;
  int _nextOffset = 0;
  bool _complete = false;
  bool _loading = false;
  bool _scanReliable = true;
  bool _refreshing = false;
  Set<String>? _refreshIds;
  int _refreshNextOffset = 0;
  bool _refreshReliable = true;
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
    if (next != null) unawaited(preload());
  }

  AuthoritativeTrackLikeState stateFor(PlaylistTrackSummary track) {
    if (!enabled || track.providerId != providerId || _likedPlaylist == null) {
      return AuthoritativeTrackLikeState.unavailable;
    }
    final membershipIdentity = track.membershipIdentity;
    if (_needsReconciliation.contains(membershipIdentity)) {
      return AuthoritativeTrackLikeState.unknown;
    }
    final override = _confirmedOverrides[membershipIdentity];
    if (override != null) {
      return override
          ? AuthoritativeTrackLikeState.liked
          : AuthoritativeTrackLikeState.notLiked;
    }
    if (_likedTrackIds.contains(membershipIdentity)) {
      return AuthoritativeTrackLikeState.liked;
    }
    if (_complete && _scanReliable) {
      return AuthoritativeTrackLikeState.notLiked;
    }
    if (_loading && _requestedTrackIds.contains(membershipIdentity)) {
      return AuthoritativeTrackLikeState.loading;
    }
    return AuthoritativeTrackLikeState.unknown;
  }

  /// Starts one bounded-page-at-a-time background scan for this account.
  /// Repeated calls share the same future and continue from [_nextOffset].
  Future<void> preload() {
    if (!enabled || _likedPlaylist == null || _complete || _disposed) {
      return Future.value();
    }
    final running = _scan;
    if (running != null) return running;
    final generation = _generation;
    _diagnostic('preload_started');
    late final Future<void> scan;
    scan = _scanContinuation(generation).whenComplete(() {
      if (identical(_scan, scan)) _scan = null;
    });
    _scan = scan;
    return scan;
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
    _requestedTrackIds.add(track.membershipIdentity);
    if (!_loading && !_complete) {
      _loading = true;
      _notify();
    }
    await preload();
    return stateFor(track);
  }

  Future<LibraryMutationOutcome<TrackLikeState>> setLiked({
    required PlaylistTrackSummary track,
    required bool liked,
    Future<void> Function()? refreshAdditionalState,
  }) async {
    _diagnostic(
      'action_requested',
      detail: 'knownState=${stateFor(track).name}',
    );
    final outcome = await mutations.setTrackLiked(track: track, liked: liked);
    switch (outcome.status) {
      case LibraryMutationStatus.confirmed:
        _confirmedOverrides[track.membershipIdentity] =
            outcome.value == TrackLikeState.liked;
        _needsReconciliation.remove(track.membershipIdentity);
        _diagnostic('write_confirmed');
        _notify();
        _startBackgroundReconciliation(refreshAdditionalState);
      case LibraryMutationStatus.outcomeUnknown:
        _confirmedOverrides.remove(track.membershipIdentity);
        _needsReconciliation.add(track.membershipIdentity);
        _diagnostic('write_outcome_unknown');
        _notify();
        _startBackgroundReconciliation(refreshAdditionalState);
      case LibraryMutationStatus.definitiveFailure:
        _diagnostic('write_definitive_failure');
      case LibraryMutationStatus.unavailable:
        _diagnostic('write_unavailable');
      case LibraryMutationStatus.alreadyRunning:
        _diagnostic('write_already_running');
    }
    return outcome;
  }

  /// Revalidates the collection without clearing the visible account snapshot.
  /// A complete exact replacement is committed atomically.
  Future<void> refreshSnapshot() {
    final running = _refresh;
    if (running != null) return running;
    if (!enabled || _likedPlaylist == null || _disposed) return Future.value();
    _operation?.cancel();
    _operation = null;
    _scan = null;
    _cancelSharedPages();
    _refreshing = true;
    _refreshIds = <String>{};
    _refreshNextOffset = 0;
    _refreshReliable = true;
    final generation = _generation;
    _diagnostic('reconcile_started');
    late final Future<void> refresh;
    refresh = _scanRefresh(generation).whenComplete(() {
      if (identical(_refresh, refresh)) _refresh = null;
    });
    _refresh = refresh;
    return refresh;
  }

  void _startBackgroundReconciliation(
    Future<void> Function()? refreshAdditionalState,
  ) {
    final membership = refreshSnapshot();
    if (refreshAdditionalState != null) {
      unawaited(Future.wait<void>([membership, refreshAdditionalState()]));
    } else {
      unawaited(membership);
    }
  }

  Future<void> _scanContinuation(int generation) async {
    _loading = _requestedTrackIds.isNotEmpty;
    _notify();
    while (_isCurrent(generation) && !_complete && !_refreshing) {
      final playlist = _likedPlaylist;
      if (playlist == null) break;
      final expectedOffset = _nextOffset;
      late final PlaylistTrackPageLoadOperation operation;
      try {
        operation = sessionGateway.beginLoad(
          playlist: playlist,
          offset: expectedOffset,
          size: PlaylistDetailController.pageSize,
        );
      } on Object {
        break;
      }
      _operation = operation;
      final result = await operation.run();
      if (identical(_operation, operation)) _operation = null;
      if (!_isCurrent(generation) || _refreshing) return;
      if (_isSessionFailure(result.failure)) {
        _invalidate(null);
        return;
      }
      if (!_validPage(result, expectedOffset)) break;
      _acceptCurrentPage(result);
    }
    if (!_isCurrent(generation)) return;
    _loading = false;
    _diagnostic(
      _complete && _scanReliable ? 'preload_complete' : 'preload_paused',
    );
    _notify();
  }

  Future<void> _scanRefresh(int generation) async {
    while (_isCurrent(generation) && _refreshing) {
      final playlist = _likedPlaylist;
      if (playlist == null) break;
      final expectedOffset = _refreshNextOffset;
      late final PlaylistTrackPageLoadOperation operation;
      try {
        operation = sessionGateway.beginLoad(
          playlist: playlist,
          offset: expectedOffset,
          size: PlaylistDetailController.pageSize,
        );
      } on Object {
        break;
      }
      _operation = operation;
      final result = await operation.run();
      if (identical(_operation, operation)) _operation = null;
      if (!_isCurrent(generation) || !_refreshing) return;
      if (_isSessionFailure(result.failure)) {
        _invalidate(null);
        return;
      }
      if (!_validPage(result, expectedOffset)) break;
      _acceptRefreshPage(result);
      if (!result.hasMore) {
        if (_refreshReliable) _commitRefresh();
        break;
      }
    }
    if (!_isCurrent(generation)) return;
    _refreshing = false;
    _refreshIds = null;
    _diagnostic('reconcile_finished');
    _notify();
  }

  PlaylistTrackPageLoadOperation _beginSharedLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    if (!_samePlaylist(_likedPlaylist, playlist)) {
      return _sourceGateway.beginLoad(
        playlist: playlist,
        offset: offset,
        size: size,
      );
    }
    final key = _TrackPageKey(playlist.opaqueId, offset, size);
    var page = _sharedPages[key];
    if (page == null) {
      final source = _sourceGateway.beginLoad(
        playlist: playlist,
        offset: offset,
        size: size,
      );
      final generation = _generation;
      late final Future<PlaylistTrackPageResult> future;
      future = source.run().then((result) {
        if (_isCurrent(generation)) {
          if (_isSessionFailure(result.failure)) {
            _invalidate(null);
          } else if (result.failure == null) {
            if (_refreshing) {
              _acceptRefreshPage(result);
            } else {
              _acceptCurrentPage(result);
            }
          } else if (identical(_sharedPages[key]?.future, future)) {
            _sharedPages.remove(key);
          }
        }
        return result;
      });
      page = _SharedTrackPage(source, future);
      _sharedPages[key] = page;
    }
    return _JoinedTrackPageLoadOperation(page.future);
  }

  void _acceptCurrentPage(PlaylistTrackPageResult result) {
    if (result.failure != null || result.offset != _nextOffset) return;
    _likedTrackIds.addAll(result.membershipTrackOpaqueIds);
    for (final track in result.tracks) {
      if (track.providerId == providerId) {
        _likedTrackIds.add(track.membershipIdentity);
      }
    }
    _scanReliable = _scanReliable && result.membershipIsExact;
    if (result.nextOffset > _nextOffset) _nextOffset = result.nextOffset;
    if (!result.hasMore) _complete = true;
    _notify();
  }

  void _acceptRefreshPage(PlaylistTrackPageResult result) {
    final ids = _refreshIds;
    if (!_refreshing ||
        ids == null ||
        result.failure != null ||
        result.offset != _refreshNextOffset) {
      return;
    }
    ids.addAll(result.membershipTrackOpaqueIds);
    for (final track in result.tracks) {
      if (track.providerId == providerId) ids.add(track.membershipIdentity);
    }
    _needsReconciliation.removeAll(ids);
    _refreshReliable = _refreshReliable && result.membershipIsExact;
    if (result.nextOffset > _refreshNextOffset) {
      _refreshNextOffset = result.nextOffset;
    }
    _notify();
  }

  void _commitRefresh() {
    final ids = _refreshIds;
    if (ids == null) return;
    _likedTrackIds
      ..clear()
      ..addAll(ids);
    _nextOffset = _refreshNextOffset;
    _complete = true;
    _scanReliable = true;
    _confirmedOverrides.clear();
    _needsReconciliation.clear();
  }

  bool _validPage(PlaylistTrackPageResult result, int expectedOffset) =>
      result.failure == null &&
      result.offset == expectedOffset &&
      result.nextOffset >= expectedOffset &&
      (!result.hasMore || result.nextOffset > expectedOffset);

  bool _isSessionFailure(UserLibraryFailure? failure) =>
      failure == UserLibraryFailure.authenticationRequired ||
      failure == UserLibraryFailure.credentialRejected ||
      failure == UserLibraryFailure.credentialRejectedStorageCleanupFailed ||
      failure == UserLibraryFailure.replaced;

  void _invalidate(UserPlaylistSummary? playlist) {
    _generation += 1;
    _operation?.cancel();
    _operation = null;
    _scan = null;
    _refresh = null;
    _cancelSharedPages();
    _likedPlaylist = playlist;
    _likedTrackIds.clear();
    _confirmedOverrides.clear();
    _requestedTrackIds.clear();
    _needsReconciliation.clear();
    _nextOffset = 0;
    _complete = false;
    _loading = false;
    _scanReliable = true;
    _refreshing = false;
    _refreshIds = null;
    _notify();
  }

  void _cancelSharedPages() {
    for (final page in _sharedPages.values) {
      page.source.cancel();
    }
    _sharedPages.clear();
  }

  bool _samePlaylist(UserPlaylistSummary? left, UserPlaylistSummary? right) =>
      left?.providerId == right?.providerId &&
      left?.opaqueId == right?.opaqueId &&
      left?.isLikedSongs == right?.isLikedSongs;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _diagnostic(String phase, {String? detail}) {
    debugPrint(
      'FURA_DIAGNOSTIC library_mutation provider=$providerId '
      'kind=track_like phase=$phase${detail == null ? '' : ' $detail'}',
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _operation?.cancel();
    _operation = null;
    _cancelSharedPages();
    super.dispose();
  }
}

class _TrackMembershipGateway implements PlaylistDetailGateway {
  const _TrackMembershipGateway(this.owner);

  final TrackLikePresentationController owner;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) => owner._beginSharedLoad(playlist: playlist, offset: offset, size: size);
}

@immutable
class _TrackPageKey {
  const _TrackPageKey(this.playlistId, this.offset, this.size);

  final String playlistId;
  final int offset;
  final int size;

  @override
  bool operator ==(Object other) =>
      other is _TrackPageKey &&
      other.playlistId == playlistId &&
      other.offset == offset &&
      other.size == size;

  @override
  int get hashCode => Object.hash(playlistId, offset, size);
}

class _SharedTrackPage {
  const _SharedTrackPage(this.source, this.future);

  final PlaylistTrackPageLoadOperation source;
  final Future<PlaylistTrackPageResult> future;
}

class _JoinedTrackPageLoadOperation implements PlaylistTrackPageLoadOperation {
  _JoinedTrackPageLoadOperation(this._future);

  final Future<PlaylistTrackPageResult> _future;
  bool _active = true;

  @override
  bool cancel() {
    final wasActive = _active;
    _active = false;
    return wasActive;
  }

  @override
  Future<PlaylistTrackPageResult> run() async {
    if (!_active) {
      return const PlaylistTrackPageResult(
        failure: UserLibraryFailure.cancelled,
      );
    }
    final result = await _future;
    return _active
        ? result
        : const PlaylistTrackPageResult(failure: UserLibraryFailure.cancelled);
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
