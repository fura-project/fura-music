import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/library/album_favorite_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_creation_gateway.dart';
import 'package:flutterustmusic/library/playlist_deletion_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_track_gateway.dart';
import 'package:flutterustmusic/library/track_like_gateway.dart';

enum LibraryMutationStatus {
  confirmed,
  definitiveFailure,
  outcomeUnknown,
  unavailable,
  alreadyRunning,
}

@immutable
class LibraryMutationOutcome<T> {
  const LibraryMutationOutcome({required this.status, this.value});

  final LibraryMutationStatus status;
  final T? value;

  bool get confirmed => status == LibraryMutationStatus.confirmed;
  bool get requiresAuthoritativeRefresh =>
      status == LibraryMutationStatus.outcomeUnknown;
}

/// Account-generation-scoped owner for remote personal-library writes.
///
/// It owns only request lifecycle and pending presentation. Provider protocol
/// remains in Rust, Queue state remains in QueuePlaybackController, and the
/// presentation membership owners decide how confirmed and indeterminate
/// writes are reconciled without discarding unrelated account state.
class LibraryMutationCoordinator extends ChangeNotifier {
  LibraryMutationCoordinator({
    required this.providerId,
    this.trackLikeGateway,
    this.albumFavoriteGateway,
    this.playlistTrackGateway,
    this.playlistCreationGateway,
    this.playlistDeletionGateway,
  });

  final String providerId;
  final TrackLikeGateway? trackLikeGateway;
  final AlbumFavoriteGateway? albumFavoriteGateway;
  final PlaylistTrackGateway? playlistTrackGateway;
  final PlaylistCreationGateway? playlistCreationGateway;
  final PlaylistDeletionGateway? playlistDeletionGateway;

  final Map<String, Object> _operations = <String, Object>{};
  int _generation = 0;
  bool _disposed = false;

  bool isTrackPending(PlaylistTrackSummary track) =>
      _operations.containsKey(_trackKey(track));

  bool isAlbumPending(AlbumSummary album) =>
      _operations.containsKey(_albumKey(album));

  bool isPlaylistPending(UserPlaylistSummary playlist) =>
      _operations.keys.any((key) => key.contains(_playlistIdentity(playlist)));

  bool get isCreatingPlaylist => _operations.containsKey('playlist:create');

  Future<LibraryMutationOutcome<TrackLikeState>> setTrackLiked({
    required PlaylistTrackSummary track,
    required bool liked,
  }) async {
    final gateway = trackLikeGateway;
    if (gateway == null || track.providerId != providerId) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.unavailable,
      );
    }
    final key = _trackKey(track);
    if (_operations.containsKey(key)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.alreadyRunning,
      );
    }
    final operation = gateway.beginMutation(
      providerId: providerId,
      opaqueTrackId: track.opaqueId,
      desiredState: liked ? TrackLikeState.liked : TrackLikeState.notLiked,
    );
    final generation = _generation;
    if (!_start(key, operation)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.alreadyRunning,
      );
    }
    _diagnostic(kind: 'track_like', phase: 'bridge_started');
    final result = await operation.run();
    if (!_finishIfCurrent(key, operation, generation)) {
      _diagnostic(
        kind: 'track_like',
        phase: 'bridge_finished',
        outcome: LibraryMutationStatus.outcomeUnknown,
        failure: 'stale_generation',
      );
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.outcomeUnknown,
      );
    }
    final status = _trackLikeStatus(result);
    _diagnostic(
      kind: 'track_like',
      phase: 'bridge_finished',
      outcome: status,
      failure: result.failure?.name,
    );
    return LibraryMutationOutcome<TrackLikeState>(
      status: status,
      value: result.confirmedState,
    );
  }

  Future<LibraryMutationOutcome<AlbumFavoriteState>> setAlbumFavorite({
    required AlbumSummary album,
    required bool favorite,
  }) async {
    final gateway = albumFavoriteGateway;
    if (gateway == null || album.providerId != providerId) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.unavailable,
      );
    }
    final key = _albumKey(album);
    if (_operations.containsKey(key)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.alreadyRunning,
      );
    }
    final operation = gateway.beginMutation(
      providerId: providerId,
      opaqueAlbumId: album.opaqueId,
      desiredState: favorite
          ? AlbumFavoriteState.favorite
          : AlbumFavoriteState.notFavorite,
    );
    final generation = _generation;
    if (!_start(key, operation)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.alreadyRunning,
      );
    }
    _diagnostic(kind: 'album_favorite', phase: 'bridge_started');
    final result = await operation.run();
    if (!_finishIfCurrent(key, operation, generation)) {
      _diagnostic(
        kind: 'album_favorite',
        phase: 'bridge_finished',
        outcome: LibraryMutationStatus.outcomeUnknown,
        failure: 'stale_generation',
      );
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.outcomeUnknown,
      );
    }
    final status = _albumFavoriteStatus(result);
    _diagnostic(
      kind: 'album_favorite',
      phase: 'bridge_finished',
      outcome: status,
      failure: result.failure?.name,
    );
    return LibraryMutationOutcome<AlbumFavoriteState>(
      status: status,
      value: result.confirmedState,
    );
  }

  Future<LibraryMutationOutcome<PlaylistTrackState>> setPlaylistTrack({
    required UserPlaylistSummary playlist,
    required PlaylistTrackSummary track,
    required bool present,
    required Future<void> Function() refreshAuthoritativeState,
  }) async {
    final gateway = playlistTrackGateway;
    if (gateway == null ||
        playlist.providerId != providerId ||
        track.providerId != providerId ||
        playlist.ownership != UserPlaylistOwnership.owned ||
        playlist.isLikedSongs) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.unavailable,
      );
    }
    final key =
        'playlist-track:${_playlistIdentity(playlist)}:${track.opaqueId}';
    if (_operations.containsKey(key)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.alreadyRunning,
      );
    }
    final operation = gateway.beginMutation(
      providerId: providerId,
      opaquePlaylistId: playlist.opaqueId,
      opaqueTrackId: track.opaqueId,
      desiredState: present
          ? PlaylistTrackState.present
          : PlaylistTrackState.absent,
    );
    final generation = _generation;
    if (!_start(key, operation)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.alreadyRunning,
      );
    }
    final result = await operation.run();
    if (!_finishIfCurrent(key, operation, generation)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.outcomeUnknown,
      );
    }
    final outcome = LibraryMutationOutcome<PlaylistTrackState>(
      status: _playlistTrackStatus(result),
      value: result.confirmedState,
    );
    if (outcome.confirmed || outcome.requiresAuthoritativeRefresh) {
      await _refreshIfCurrent(generation, refreshAuthoritativeState);
    }
    return outcome;
  }

  Future<LibraryMutationOutcome<UserPlaylistSummary>> createPlaylist({
    required String name,
    required Future<void> Function() refreshAuthoritativeState,
  }) async {
    final gateway = playlistCreationGateway;
    final normalized = name.trim();
    if (gateway == null || normalized.isEmpty || normalized.length > 256) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.unavailable,
      );
    }
    const key = 'playlist:create';
    if (_operations.containsKey(key)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.alreadyRunning,
      );
    }
    final operation = gateway.beginCreation(name: normalized);
    final generation = _generation;
    if (!_start(key, operation)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.alreadyRunning,
      );
    }
    final result = await operation.run();
    if (!_finishIfCurrent(key, operation, generation)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.outcomeUnknown,
      );
    }
    final outcome = LibraryMutationOutcome<UserPlaylistSummary>(
      status: _creationStatus(result),
      value: result.createdPlaylist,
    );
    if (outcome.confirmed || outcome.requiresAuthoritativeRefresh) {
      await _refreshIfCurrent(generation, refreshAuthoritativeState);
    }
    return outcome;
  }

  Future<LibraryMutationOutcome<bool>> deletePlaylist({
    required UserPlaylistSummary playlist,
    required Future<void> Function() refreshAuthoritativeState,
  }) async {
    final gateway = playlistDeletionGateway;
    if (gateway == null ||
        playlist.providerId != providerId ||
        playlist.ownership != UserPlaylistOwnership.owned ||
        playlist.isLikedSongs) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.unavailable,
      );
    }
    final key = 'playlist:delete:${_playlistIdentity(playlist)}';
    if (_operations.containsKey(key)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.alreadyRunning,
      );
    }
    final operation = gateway.beginDeletion(
      providerId: providerId,
      opaquePlaylistId: playlist.opaqueId,
    );
    final generation = _generation;
    if (!_start(key, operation)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.alreadyRunning,
      );
    }
    final result = await operation.run();
    if (!_finishIfCurrent(key, operation, generation)) {
      return const LibraryMutationOutcome(
        status: LibraryMutationStatus.outcomeUnknown,
      );
    }
    final outcome = LibraryMutationOutcome<bool>(
      status: _deletionStatus(result),
      value: result.deleted,
    );
    if (outcome.confirmed || outcome.requiresAuthoritativeRefresh) {
      await _refreshIfCurrent(generation, refreshAuthoritativeState);
    }
    return outcome;
  }

  bool _start(String key, Object operation) {
    if (_disposed || _operations.containsKey(key)) return false;
    _operations[key] = operation;
    notifyListeners();
    return true;
  }

  bool _finishIfCurrent(String key, Object operation, int generation) {
    final current = !_disposed && generation == _generation;
    if (identical(_operations[key], operation)) _operations.remove(key);
    if (!_disposed) notifyListeners();
    return current;
  }

  Future<void> _refreshIfCurrent(
    int generation,
    Future<void> Function() refresh,
  ) async {
    if (_disposed || generation != _generation) return;
    await refresh();
  }

  void _diagnostic({
    required String kind,
    required String phase,
    LibraryMutationStatus? outcome,
    String? failure,
  }) {
    debugPrint(
      'FURA_DIAGNOSTIC library_mutation provider=$providerId kind=$kind '
      'phase=$phase${outcome == null ? '' : ' outcome=${outcome.name}'}'
      '${failure == null ? '' : ' failure=$failure'}',
    );
  }

  static LibraryMutationStatus _trackLikeStatus(
    TrackLikeMutationResult result,
  ) => switch (result.failure) {
    null => LibraryMutationStatus.confirmed,
    TrackLikeMutationFailure.networkOutcomeUnknown ||
    TrackLikeMutationFailure.invalidResponseOutcomeUnknown ||
    TrackLikeMutationFailure.replacedOutcomeUnknown ||
    TrackLikeMutationFailure.cancelledOutcomeUnknown =>
      LibraryMutationStatus.outcomeUnknown,
    TrackLikeMutationFailure.alreadyRunning =>
      LibraryMutationStatus.alreadyRunning,
    _ => LibraryMutationStatus.definitiveFailure,
  };

  static LibraryMutationStatus _albumFavoriteStatus(
    AlbumFavoriteMutationResult result,
  ) => switch (result.failure) {
    null => LibraryMutationStatus.confirmed,
    AlbumFavoriteMutationFailure.networkOutcomeUnknown ||
    AlbumFavoriteMutationFailure.invalidResponseOutcomeUnknown ||
    AlbumFavoriteMutationFailure.replacedOutcomeUnknown ||
    AlbumFavoriteMutationFailure.cancelledOutcomeUnknown =>
      LibraryMutationStatus.outcomeUnknown,
    AlbumFavoriteMutationFailure.alreadyRunning =>
      LibraryMutationStatus.alreadyRunning,
    _ => LibraryMutationStatus.definitiveFailure,
  };

  static LibraryMutationStatus _playlistTrackStatus(
    PlaylistTrackMutationResult result,
  ) => switch (result.failure) {
    null => LibraryMutationStatus.confirmed,
    PlaylistTrackMutationFailure.networkOutcomeUnknown ||
    PlaylistTrackMutationFailure.invalidResponseOutcomeUnknown ||
    PlaylistTrackMutationFailure.replacedOutcomeUnknown ||
    PlaylistTrackMutationFailure.cancelledOutcomeUnknown =>
      LibraryMutationStatus.outcomeUnknown,
    PlaylistTrackMutationFailure.alreadyRunning =>
      LibraryMutationStatus.alreadyRunning,
    _ => LibraryMutationStatus.definitiveFailure,
  };

  static LibraryMutationStatus _creationStatus(PlaylistCreationResult result) =>
      switch (result.failure) {
        null => LibraryMutationStatus.confirmed,
        PlaylistCreationFailure.networkOutcomeUnknown ||
        PlaylistCreationFailure.invalidResponseOutcomeUnknown ||
        PlaylistCreationFailure.replacedOutcomeUnknown ||
        PlaylistCreationFailure.cancelledOutcomeUnknown =>
          LibraryMutationStatus.outcomeUnknown,
        PlaylistCreationFailure.alreadyRunning =>
          LibraryMutationStatus.alreadyRunning,
        _ => LibraryMutationStatus.definitiveFailure,
      };

  static LibraryMutationStatus _deletionStatus(PlaylistDeletionResult result) =>
      switch (result.failure) {
        null => LibraryMutationStatus.confirmed,
        PlaylistDeletionFailure.networkOutcomeUnknown ||
        PlaylistDeletionFailure.invalidResponseOutcomeUnknown ||
        PlaylistDeletionFailure.replacedOutcomeUnknown ||
        PlaylistDeletionFailure.cancelledOutcomeUnknown =>
          LibraryMutationStatus.outcomeUnknown,
        PlaylistDeletionFailure.alreadyRunning =>
          LibraryMutationStatus.alreadyRunning,
        _ => LibraryMutationStatus.definitiveFailure,
      };

  String _trackKey(PlaylistTrackSummary track) =>
      'track-like:${track.providerId}:${track.opaqueId}';

  String _albumKey(AlbumSummary album) =>
      'album-favorite:${album.providerId}:${album.opaqueId}';

  String _playlistIdentity(UserPlaylistSummary playlist) =>
      '${playlist.providerId}:${playlist.opaqueId}';

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    for (final operation in _operations.values) {
      switch (operation) {
        case TrackLikeMutationOperation operation:
          operation.cancel();
        case AlbumFavoriteMutationOperation operation:
          operation.cancel();
        case PlaylistTrackMutationOperation operation:
          operation.cancel();
        case PlaylistCreationOperation operation:
          operation.cancel();
        case PlaylistDeletionOperation operation:
          operation.cancel();
      }
    }
    _operations.clear();
    super.dispose();
  }
}
