import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/queue.dart' as bridge_queue;

enum PlaybackQueueFailure {
  invalidTrack,
  invalidPosition,
  coreUnavailable,
  invalidResponse,
}

class PlaybackQueueSnapshot {
  PlaybackQueueSnapshot({
    required List<PlaylistTrackSummary> tracks,
    required this.currentIndex,
    required this.hasPrevious,
    required this.hasNext,
  }) : tracks = List.unmodifiable(tracks);

  factory PlaybackQueueSnapshot.empty() => PlaybackQueueSnapshot(
    tracks: const [],
    currentIndex: null,
    hasPrevious: false,
    hasNext: false,
  );

  final List<PlaylistTrackSummary> tracks;
  final int? currentIndex;
  final bool hasPrevious;
  final bool hasNext;

  PlaylistTrackSummary? get current => switch (currentIndex) {
    final index? => tracks[index],
    null => null,
  };

  @override
  String toString() =>
      'PlaybackQueueSnapshot(trackCount: ${tracks.length}, '
      'currentIndex: $currentIndex, hasPrevious: $hasPrevious, '
      'hasNext: $hasNext)';
}

class PlaybackQueueResult {
  const PlaybackQueueResult({
    this.snapshot,
    this.currentChanged = false,
    this.failure,
  });

  final PlaybackQueueSnapshot? snapshot;
  final bool currentChanged;
  final PlaybackQueueFailure? failure;

  @override
  String toString() =>
      'PlaybackQueueResult(hasSnapshot: ${snapshot != null}, '
      'currentChanged: $currentChanged, failure: $failure)';
}

abstract interface class PlaybackQueueGateway {
  PlaybackQueueResult snapshot();

  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  });

  PlaybackQueueResult push(PlaylistTrackSummary track);
  PlaybackQueueResult select(int index);
  PlaybackQueueResult advance();
  PlaybackQueueResult rewind();
  PlaybackQueueResult completeCurrent();
  PlaybackQueueResult remove(int index);
  PlaybackQueueResult clear();
}

abstract interface class PlaybackQueueBridge {
  bridge_queue.PlaybackQueueUpdate snapshot();

  bridge_queue.PlaybackQueueUpdate replace({
    required List<bridge_library.LibraryTrackSummary> tracks,
    required int? currentIndex,
  });

  bridge_queue.PlaybackQueueUpdate push(
    bridge_library.LibraryTrackSummary track,
  );
  bridge_queue.PlaybackQueueUpdate select(int index);
  bridge_queue.PlaybackQueueUpdate advance();
  bridge_queue.PlaybackQueueUpdate rewind();
  bridge_queue.PlaybackQueueUpdate completeCurrent();
  bridge_queue.PlaybackQueueUpdate remove(int index);
  bridge_queue.PlaybackQueueUpdate clear();
}

class RustPlaybackQueueGateway implements PlaybackQueueGateway {
  factory RustPlaybackQueueGateway({PlaybackQueueBridge? bridge}) =>
      RustPlaybackQueueGateway._(bridge);

  RustPlaybackQueueGateway._(this._bridge);

  PlaybackQueueBridge? _bridge;

  PlaybackQueueBridge get _resolvedBridge =>
      _bridge ??= _RustPlaybackQueueBridge();

  @override
  PlaybackQueueResult snapshot() => _invoke(() => _resolvedBridge.snapshot());

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) => _invoke(
    () => _resolvedBridge.replace(
      tracks: tracks.map(_bridgeTrack).toList(growable: false),
      currentIndex: currentIndex,
    ),
  );

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) =>
      _invoke(() => _resolvedBridge.push(_bridgeTrack(track)));

  @override
  PlaybackQueueResult select(int index) =>
      _invoke(() => _resolvedBridge.select(index));

  @override
  PlaybackQueueResult advance() => _invoke(() => _resolvedBridge.advance());

  @override
  PlaybackQueueResult rewind() => _invoke(() => _resolvedBridge.rewind());

  @override
  PlaybackQueueResult completeCurrent() =>
      _invoke(() => _resolvedBridge.completeCurrent());

  @override
  PlaybackQueueResult remove(int index) =>
      _invoke(() => _resolvedBridge.remove(index));

  @override
  PlaybackQueueResult clear() => _invoke(() => _resolvedBridge.clear());

  PlaybackQueueResult _invoke(
    bridge_queue.PlaybackQueueUpdate Function() operation,
  ) {
    try {
      return mapBridgePlaybackQueueUpdate(operation());
    } on Object {
      return const PlaybackQueueResult(
        failure: PlaybackQueueFailure.coreUnavailable,
      );
    }
  }
}

class _RustPlaybackQueueBridge implements PlaybackQueueBridge {
  _RustPlaybackQueueBridge() : _handle = bridge_queue.createPlaybackQueue();

  final bridge_queue.PlaybackQueueHandle _handle;

  @override
  bridge_queue.PlaybackQueueUpdate snapshot() => _handle.snapshot();

  @override
  bridge_queue.PlaybackQueueUpdate replace({
    required List<bridge_library.LibraryTrackSummary> tracks,
    required int? currentIndex,
  }) => _handle.replace(tracks: tracks, currentIndex: currentIndex);

  @override
  bridge_queue.PlaybackQueueUpdate push(
    bridge_library.LibraryTrackSummary track,
  ) => _handle.push(track: track);

  @override
  bridge_queue.PlaybackQueueUpdate select(int index) =>
      _handle.select(index: index);

  @override
  bridge_queue.PlaybackQueueUpdate advance() => _handle.advance();

  @override
  bridge_queue.PlaybackQueueUpdate rewind() => _handle.rewind();

  @override
  bridge_queue.PlaybackQueueUpdate completeCurrent() =>
      _handle.completeCurrent();

  @override
  bridge_queue.PlaybackQueueUpdate remove(int index) =>
      _handle.remove(index: index);

  @override
  bridge_queue.PlaybackQueueUpdate clear() => _handle.clear();
}

bridge_library.LibraryTrackSummary _bridgeTrack(PlaylistTrackSummary track) =>
    bridge_library.LibraryTrackSummary(
      providerId: track.providerId,
      opaqueId: track.opaqueId,
      title: track.title,
      subtitle: track.subtitle,
      artistNames: track.artistNames,
      albumTitle: track.albumTitle,
      artworkUri: track.artworkUri,
      durationSeconds: track.durationSeconds,
    );

@visibleForTesting
PlaybackQueueResult mapBridgePlaybackQueueUpdate(
  bridge_queue.PlaybackQueueUpdate update,
) {
  final bridgeSnapshot = update.snapshot;
  final bridgeFailure = update.failure;
  if (bridgeFailure != null) {
    if (bridgeSnapshot != null || update.currentChanged) {
      return const PlaybackQueueResult(
        failure: PlaybackQueueFailure.invalidResponse,
      );
    }
    return PlaybackQueueResult(failure: _mapFailure(bridgeFailure));
  }
  if (bridgeSnapshot == null) {
    return const PlaybackQueueResult(
      failure: PlaybackQueueFailure.invalidResponse,
    );
  }

  final tracks = <PlaylistTrackSummary>[];
  for (final track in bridgeSnapshot.tracks) {
    final mapped = _mapTrack(track);
    if (mapped == null) {
      return const PlaybackQueueResult(
        failure: PlaybackQueueFailure.invalidResponse,
      );
    }
    tracks.add(mapped);
  }
  final currentIndex = bridgeSnapshot.currentIndex;
  final validEmpty =
      tracks.isEmpty &&
      currentIndex == null &&
      !bridgeSnapshot.hasPrevious &&
      !bridgeSnapshot.hasNext;
  final validContent =
      tracks.isNotEmpty &&
      currentIndex != null &&
      currentIndex >= 0 &&
      currentIndex < tracks.length &&
      bridgeSnapshot.hasPrevious == (currentIndex > 0) &&
      bridgeSnapshot.hasNext == (currentIndex + 1 < tracks.length);
  if (!validEmpty && !validContent) {
    return const PlaybackQueueResult(
      failure: PlaybackQueueFailure.invalidResponse,
    );
  }
  return PlaybackQueueResult(
    snapshot: PlaybackQueueSnapshot(
      tracks: tracks,
      currentIndex: currentIndex,
      hasPrevious: bridgeSnapshot.hasPrevious,
      hasNext: bridgeSnapshot.hasNext,
    ),
    currentChanged: update.currentChanged,
  );
}

PlaylistTrackSummary? _mapTrack(bridge_library.LibraryTrackSummary track) {
  final providerId = track.providerId;
  final validProvider =
      providerId.isNotEmpty &&
      providerId.codeUnits.every(
        (unit) =>
            unit >= 97 && unit <= 122 || unit >= 48 && unit <= 57 || unit == 45,
      );
  if (!validProvider ||
      track.opaqueId.trim().isEmpty ||
      track.title.trim().isEmpty ||
      track.artistNames.any((artist) => artist.trim().isEmpty) ||
      _blank(track.subtitle) ||
      _blank(track.albumTitle) ||
      _blank(track.artworkUri) ||
      (track.durationSeconds != null && track.durationSeconds! < 0)) {
    return null;
  }
  return PlaylistTrackSummary(
    providerId: providerId,
    opaqueId: track.opaqueId,
    title: track.title,
    artistNames: List.unmodifiable(track.artistNames),
    subtitle: track.subtitle,
    albumTitle: track.albumTitle,
    artworkUri: track.artworkUri,
    durationSeconds: track.durationSeconds,
  );
}

bool _blank(String? value) => value != null && value.trim().isEmpty;

PlaybackQueueFailure _mapFailure(bridge_queue.PlaybackQueueFailure failure) =>
    switch (failure) {
      bridge_queue.PlaybackQueueFailure.invalidTrack =>
        PlaybackQueueFailure.invalidTrack,
      bridge_queue.PlaybackQueueFailure.invalidPosition =>
        PlaybackQueueFailure.invalidPosition,
      bridge_queue.PlaybackQueueFailure.coreUnavailable =>
        PlaybackQueueFailure.coreUnavailable,
    };
