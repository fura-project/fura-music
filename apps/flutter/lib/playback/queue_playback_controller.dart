import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/playback/collection_playback_source.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

enum RoamStage { idle, loading, continued, unsupported, empty, failed }

enum CollectionPlaybackStage { idle, ready, loading, failed, exhausted }

class QueuePlaybackController extends ChangeNotifier {
  QueuePlaybackController(
    this._gateway,
    this._playback, {
    this.lyrics,
    RelatedTracksGateway? relatedTracksGateway,
  }) : // The public named parameter cannot use a library-private name.
       // ignore: prefer_initializing_formals
       _relatedTracksGateway = relatedTracksGateway {
    _playback.addListener(_onPlaybackChanged);
    lyrics?.addListener(_onLyricsChanged);
    _accept(_gateway.snapshot());
    _syncLyricTrack();
  }

  final PlaybackQueueGateway _gateway;
  final TrackPlaybackController _playback;
  final LyricController? lyrics;
  final RelatedTracksGateway? _relatedTracksGateway;

  PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot.empty();
  final ValueNotifier<PlaylistTrackSummary?> _currentTrack = ValueNotifier(
    null,
  );
  PlaybackQueueFailure? _failure;
  bool _completionHandled = false;
  bool _disposed = false;
  String? _lyricTrackKey;
  bool _roamEnabled = false;
  RoamStage _roamStage = RoamStage.idle;
  RelatedTracksLoadOperation? _roamOperation;
  int _roamGeneration = 0;
  int _terminalIntentEpoch = 0;
  CollectionPlaybackSource? _collectionSource;
  CollectionPlaybackPageOperation? _collectionOperation;
  Future<void>? _collectionLoadFuture;
  CollectionPlaybackFailure? _collectionFailure;
  CollectionPlaybackStage _collectionStage = CollectionPlaybackStage.idle;
  int _collectionGeneration = 0;
  int _collectionNextCursor = 0;
  bool _collectionHasMore = false;
  int? _collectionLastDemandIndex;
  int _collectionInitialPagesLoaded = 0;
  int? _collectionTerminalToken;
  String? _collectionTerminalTrackKey;
  int? _collectionTerminalQueueLength;

  static const int _collectionLookaheadTracks = 3;
  static const int _collectionTerminalEmptyPageBudget = 3;

  PlaybackQueueSnapshot get snapshot => _snapshot;

  /// Notifies only when the provider-scoped current Track identity changes.
  /// Playback position, state, volume, and lyric updates stay on this
  /// controller's broader [Listenable].
  ValueListenable<PlaylistTrackSummary?> get currentTrackListenable =>
      _currentTrack;
  PlaybackQueueFailure? get failure => _failure;
  TrackPlaybackController get playback => _playback;
  List<PlaylistTrackSummary> get tracks => _snapshot.tracks;
  PlaylistTrackSummary? get current => _snapshot.current;
  int? get currentIndex => _snapshot.currentIndex;
  bool get hasPrevious => _snapshot.hasPrevious;
  bool get hasNext => _snapshot.hasNext;
  PlaybackOrder get order => _snapshot.order;
  PlaybackRepeatMode get repeatMode => _snapshot.repeatMode;
  bool get roamEnabled => _roamEnabled;
  bool get roamEffective =>
      _roamEnabled &&
      !collectionHasMore &&
      _relatedTracksGateway != null &&
      _snapshot.order == PlaybackOrder.sequential &&
      _snapshot.repeatMode == PlaybackRepeatMode.off &&
      switch (_snapshot.current) {
        final current? => supportsRelatedTracksProvider(current.providerId),
        null => false,
      };
  RoamStage get roamStage => _roamStage;
  CollectionPlaybackStage get collectionStage => _collectionStage;
  CollectionPlaybackFailure? get collectionFailure => _collectionFailure;
  String? get collectionSourceId => _collectionSource?.sourceId;
  bool get collectionHasMore => _collectionSource != null && _collectionHasMore;
  int get collectionDemandGeneration => _collectionGeneration;

  void setRoamEnabled(bool enabled) {
    if (_disposed || enabled == _roamEnabled) return;
    _roamEnabled = enabled;
    _invalidateRoam();
    if (!_disposed) notifyListeners();
  }

  Future<void> replaceAndPlay(
    List<PlaylistTrackSummary> tracks,
    int currentIndex,
  ) {
    _invalidateCollection();
    _invalidateRoam();
    return _apply(
      _gateway.replace(tracks: tracks, currentIndex: currentIndex),
      playChangedCurrent: true,
    );
  }

  /// Starts one logical Provider collection from its currently materialized
  /// prefix. The continuation is copied into this app-lifetime Queue owner, so
  /// disposing the presenting page cannot stop bounded playback paging.
  Future<void> replaceAndPlayCollection(
    CollectionPlaybackSource source,
    int currentIndex,
  ) async {
    if (_disposed) return;
    _invalidateCollection();
    _invalidateRoam();
    final validSource =
        source.sourceId.trim().isNotEmpty &&
        source.providerId.trim().isNotEmpty &&
        source.initialTracks.isNotEmpty &&
        currentIndex >= 0 &&
        currentIndex < source.initialTracks.length &&
        source.nextCursor >= 0 &&
        source.initialTracks.every(
          (track) => track.providerId == source.providerId,
        );
    if (!validSource ||
        (source.hasMore && _gateway is! PlaybackQueueBatchGateway)) {
      _collectionStage = CollectionPlaybackStage.failed;
      _collectionFailure = CollectionPlaybackFailure.invalidResponse;
      notifyListeners();
      return;
    }

    final result = _gateway.replace(
      tracks: source.initialTracks,
      currentIndex: currentIndex,
    );
    if (!_accept(result)) return;
    _collectionSource = source;
    _collectionNextCursor = source.nextCursor;
    _collectionHasMore = source.hasMore;
    _collectionStage = source.hasMore
        ? CollectionPlaybackStage.ready
        : CollectionPlaybackStage.exhausted;
    _collectionFailure = null;
    _completionHandled = false;
    notifyListeners();
    final current = _snapshot.current;
    if (current != null) await _playback.playTrack(current);
    _maybeDemandCollection();
  }

  Future<void> push(PlaylistTrackSummary track) {
    _invalidateCollection();
    _invalidateRoam();
    return _apply(_gateway.push(track), playChangedCurrent: true);
  }

  Future<void> select(int index) async {
    _invalidateRoam();
    await _apply(_gateway.select(index), playChangedCurrent: true);
    _maybeDemandCollection();
  }

  Future<void> advance() async {
    _invalidateRoam();
    await _apply(_gateway.advance(), playChangedCurrent: true);
    _maybeDemandCollection();
  }

  Future<void> rewind() async {
    _invalidateRoam();
    await _apply(_gateway.rewind(), playChangedCurrent: true);
    _maybeDemandCollection();
  }

  Future<void> setOrder(PlaybackOrder order) {
    if (order != _snapshot.order) _invalidateCollection();
    _invalidateRoam();
    return _apply(_gateway.setOrder(order), playChangedCurrent: false);
  }

  Future<void> toggleShuffle() => setOrder(
    order == PlaybackOrder.shuffle
        ? PlaybackOrder.sequential
        : PlaybackOrder.shuffle,
  );

  Future<void> setRepeatMode(PlaybackRepeatMode repeatMode) {
    if (repeatMode != _snapshot.repeatMode) _invalidateCollection();
    _invalidateRoam();
    return _apply(
      _gateway.setRepeatMode(repeatMode),
      playChangedCurrent: false,
    );
  }

  Future<void> cycleRepeatMode() => setRepeatMode(switch (repeatMode) {
    PlaybackRepeatMode.off => PlaybackRepeatMode.all,
    PlaybackRepeatMode.all => PlaybackRepeatMode.one,
    PlaybackRepeatMode.one => PlaybackRepeatMode.off,
  });

  Future<void> remove(int index) {
    _invalidateCollection();
    _invalidateRoam();
    return _apply(_gateway.remove(index), playChangedCurrent: true);
  }

  Future<void> clear() {
    _invalidateCollection();
    _invalidateRoam();
    return _apply(_gateway.clear(), playChangedCurrent: true);
  }

  /// Applies the current Track's play/pause/retry action through the Queue
  /// owner so an explicit user or system Play intent wins over pending Roam.
  Future<void> activateCurrent() {
    if (_disposed) return Future.value();
    _invalidateRoam();
    return _playback.activate();
  }

  /// Applies an idempotent system Play intent through the Queue owner. Unlike
  /// [activateCurrent], an already playing Track is not toggled to pause.
  Future<void> playCurrent() {
    if (_disposed) return Future.value();
    _invalidateRoam();
    if (_playback.canResume) return _playback.resume();
    if (_playback.stage == TrackPlaybackStage.playing) return Future.value();
    return _playback.activate();
  }

  /// Stops foreground playback through the Queue owner. The Queue contents
  /// remain intact, but a pending terminal continuation is synchronously stale
  /// before the audio engine begins its asynchronous stop tail.
  Future<void> stop() {
    if (_disposed) return Future.value();
    _invalidateRoam();
    return _playback.stop();
  }

  /// Invalidates Provider-bound continuation without changing the Queue.
  /// Account/provider owners call this synchronously before switching identity
  /// or signing out.
  void invalidateCollectionSource() {
    if (_disposed) return;
    _invalidateCollection();
    notifyListeners();
  }

  /// Retries the current bounded page after a typed continuation failure.
  /// Existing Queue entries and the current Track remain untouched.
  void retryCollectionContinuation() {
    if (_disposed ||
        _collectionSource == null ||
        !_collectionHasMore ||
        _collectionOperation != null) {
      return;
    }
    _collectionLastDemandIndex = null;
    _collectionFailure = null;
    _collectionStage = CollectionPlaybackStage.ready;
    final terminalToken = _playback.stage == TrackPlaybackStage.completed
        ? _terminalIntentEpoch
        : null;
    _maybeDemandCollection(force: true, terminalToken: terminalToken);
  }

  /// Requests one bounded continuation page because the Queue viewport is
  /// approaching its materialized end. Playback position, startup fill and
  /// viewport demand all converge on the same single-flight page pump.
  void demandCollectionFromQueueViewport() {
    if (_disposed || _collectionStage == CollectionPlaybackStage.failed) {
      return;
    }
    _maybeDemandCollection(viewportDemand: true);
  }

  /// Re-resolves the current Track after an explicit playback-quality change.
  /// Active playback keeps its approximate position and paused/playing state;
  /// an idle, stopped, completed, or failed Track uses the new preference only
  /// on its next normal activation.
  Future<void> reloadCurrentSource() async {
    if (_disposed ||
        (_playback.stage != TrackPlaybackStage.playing &&
            _playback.stage != TrackPlaybackStage.paused)) {
      return;
    }
    final current = _snapshot.current;
    if (current == null) return;
    final providerId = current.providerId;
    final opaqueId = current.opaqueId;
    final positionMs = _playback.positionMs;
    final remainPaused = _playback.stage == TrackPlaybackStage.paused;

    _completionHandled = false;
    await _playback.playTrack(current);
    if (_disposed ||
        _snapshot.current?.providerId != providerId ||
        _snapshot.current?.opaqueId != opaqueId) {
      return;
    }
    if (_playback.canSeek && positionMs > 0) {
      await _playback.seekToMs(positionMs);
    }
    if (remainPaused && _playback.canPause) await _playback.pause();
  }

  Future<void> _completeCurrent(int terminalToken) async {
    final result = _gateway.completeCurrent();
    if (_disposed || !_accept(result)) return;
    if (result.playbackRequested) {
      _completionHandled = false;
      final current = _snapshot.current;
      if (current == null) {
        await _playback.stop();
      } else {
        await _playback.playTrack(current);
      }
      return;
    }
    final collectionClaimed = await _continueCollectionFromTerminal(
      terminalToken,
    );
    if (collectionClaimed) return;
    await _continueRoamFromTerminal(terminalToken);
  }

  Future<bool> _continueCollectionFromTerminal(int terminalToken) async {
    final source = _collectionSource;
    if (source == null || !_collectionHasMore) return false;
    final current = _snapshot.current;
    if (current == null ||
        current.providerId != source.providerId ||
        _snapshot.order != PlaybackOrder.sequential ||
        _snapshot.repeatMode != PlaybackRepeatMode.off) {
      return true;
    }
    for (
      var attempt = 0;
      attempt < _collectionTerminalEmptyPageBudget;
      attempt++
    ) {
      final expectedLength = _snapshot.tracks.length;
      _collectionTerminalToken = terminalToken;
      _collectionTerminalTrackKey = _trackKey(current);
      _collectionTerminalQueueLength = expectedLength;
      _maybeDemandCollection(force: true, terminalToken: terminalToken);
      final pending = _collectionLoadFuture;
      if (pending != null) await pending;
      if (_disposed) return true;

      // A non-empty batch advanced playback. A failed page retains the
      // logical collection and waits for an explicit retry, so Roam must not
      // claim the same terminal completion.
      if (_playback.stage != TrackPlaybackStage.completed ||
          _snapshot.tracks.length != expectedLength ||
          _collectionStage == CollectionPlaybackStage.failed) {
        return true;
      }
      if (!_collectionHasMore) return false;

      // A valid all-omitted/empty page may advance the Provider cursor without
      // growing the Queue. Rearm only this terminal continuation and keep the
      // loop bounded so one completion can never drain an unbounded feed.
      _collectionLastDemandIndex = null;
    }
    return true;
  }

  bool get _collectionNeedsInitialFill {
    final source = _collectionSource;
    if (source == null || !source.policy.hasInitialFill) return false;
    return _snapshot.tracks.length < source.policy.initialQueueTarget &&
        _collectionInitialPagesLoaded < source.policy.maxInitialPages;
  }

  void _maybeDemandCollection({
    bool force = false,
    bool viewportDemand = false,
    int? terminalToken,
  }) {
    if (_disposed ||
        _collectionSource == null ||
        !_collectionHasMore ||
        _collectionOperation != null ||
        _collectionLoadFuture != null ||
        _snapshot.order != PlaybackOrder.sequential ||
        _snapshot.repeatMode != PlaybackRepeatMode.off) {
      return;
    }
    final currentIndex = _snapshot.currentIndex;
    if (currentIndex == null) return;
    final remaining = _snapshot.tracks.length - currentIndex - 1;
    final startupFill = _collectionNeedsInitialFill;
    if (!force && !viewportDemand && !startupFill) {
      if (remaining > _collectionLookaheadTracks) return;
      if (_collectionLastDemandIndex == currentIndex) return;
    }
    if (_collectionStage == CollectionPlaybackStage.failed && !force) return;

    _collectionLastDemandIndex = currentIndex;
    if (terminalToken != null) {
      _collectionTerminalToken = terminalToken;
      _collectionTerminalTrackKey = switch (_snapshot.current) {
        final current? => _trackKey(current),
        null => null,
      };
      _collectionTerminalQueueLength = _snapshot.tracks.length;
    }
    final future = Future<void>.microtask(_loadCollectionPage);
    _collectionLoadFuture = future;
    unawaited(future);
  }

  Future<void> _loadCollectionPage() async {
    final source = _collectionSource;
    final batchGateway = _gateway is PlaybackQueueBatchGateway
        ? _gateway as PlaybackQueueBatchGateway
        : null;
    if (source == null || batchGateway == null || !_collectionHasMore) {
      _collectionLoadFuture = null;
      return;
    }
    final generation = _collectionGeneration;
    final requestCursor = _collectionNextCursor;
    final expectedLength = _snapshot.tracks.length;
    late final CollectionPlaybackPageOperation operation;
    try {
      operation = source.loader(requestCursor);
    } on Object {
      _failCollectionLoad(
        generation,
        CollectionPlaybackFailure.invalidResponse,
      );
      return;
    }
    _collectionOperation = operation;
    _collectionStage = CollectionPlaybackStage.loading;
    _collectionFailure = null;
    if (!_disposed) notifyListeners();

    late final CollectionPlaybackPage page;
    try {
      page = await operation.run();
    } on Object {
      if (identical(_collectionOperation, operation)) {
        _collectionOperation = null;
      }
      _failCollectionLoad(
        generation,
        CollectionPlaybackFailure.invalidResponse,
      );
      return;
    }
    if (identical(_collectionOperation, operation)) {
      _collectionOperation = null;
    }
    if (!_collectionIsCurrent(
      generation,
      source,
      requestCursor,
      expectedLength,
    )) {
      return;
    }
    final failure = page.failure;
    if (failure != null) {
      _failCollectionLoad(generation, failure);
      return;
    }
    final validCursor =
        page.requestCursor == requestCursor &&
        page.nextCursor >= requestCursor &&
        (!page.hasMore || page.nextCursor > requestCursor);
    final validTracks = page.tracks.every(
      (track) => track.providerId == source.providerId,
    );
    if (!validCursor || !validTracks) {
      _failCollectionLoad(
        generation,
        CollectionPlaybackFailure.invalidResponse,
      );
      return;
    }

    if (page.tracks.isNotEmpty) {
      final terminal = _collectionTerminalIsCurrent(generation, expectedLength);
      late final PlaybackQueueResult update;
      try {
        update = terminal
            ? _gateway.extendAndAdvanceFromTerminal(page.tracks)
            : batchGateway.extend(page.tracks);
      } on Object {
        _failCollectionLoad(
          generation,
          CollectionPlaybackFailure.invalidResponse,
        );
        return;
      }
      if (!_collectionIsGenerationCurrent(generation, source) ||
          !_accept(update)) {
        _failCollectionLoad(
          generation,
          CollectionPlaybackFailure.invalidResponse,
        );
        return;
      }
      if (terminal) {
        if (!update.playbackRequested) {
          _failCollectionLoad(
            generation,
            CollectionPlaybackFailure.invalidResponse,
          );
          return;
        }
        _completionHandled = false;
        final current = _snapshot.current;
        if (current != null) await _playback.playTrack(current);
      }
    }

    if (!_collectionIsGenerationCurrent(generation, source)) return;
    _collectionNextCursor = page.nextCursor;
    _collectionHasMore = page.hasMore;
    if (source.policy.hasInitialFill &&
        _collectionInitialPagesLoaded < source.policy.maxInitialPages) {
      _collectionInitialPagesLoaded += 1;
    }
    _collectionFailure = null;
    _collectionStage = page.hasMore
        ? CollectionPlaybackStage.ready
        : CollectionPlaybackStage.exhausted;
    _clearCollectionTerminalClaim();
    _collectionLoadFuture = null;
    if (!_disposed) notifyListeners();
    if (_collectionNeedsInitialFill) {
      _maybeDemandCollection();
    }
  }

  bool _collectionIsCurrent(
    int generation,
    CollectionPlaybackSource source,
    int requestCursor,
    int expectedLength,
  ) =>
      _collectionIsGenerationCurrent(generation, source) &&
      _collectionNextCursor == requestCursor &&
      _snapshot.tracks.length == expectedLength;

  bool _collectionIsGenerationCurrent(
    int generation,
    CollectionPlaybackSource source,
  ) =>
      !_disposed &&
      generation == _collectionGeneration &&
      identical(source, _collectionSource);

  bool _collectionTerminalIsCurrent(int generation, int expectedLength) =>
      !_disposed &&
      generation == _collectionGeneration &&
      _collectionTerminalToken == _terminalIntentEpoch &&
      _playback.stage == TrackPlaybackStage.completed &&
      _snapshot.order == PlaybackOrder.sequential &&
      _snapshot.repeatMode == PlaybackRepeatMode.off &&
      _snapshot.tracks.length == expectedLength &&
      _collectionTerminalQueueLength == expectedLength &&
      switch (_snapshot.current) {
        final current? => _trackKey(current) == _collectionTerminalTrackKey,
        null => false,
      };

  void _failCollectionLoad(int generation, CollectionPlaybackFailure failure) {
    if (_disposed || generation != _collectionGeneration) return;
    _collectionOperation = null;
    _collectionLoadFuture = null;
    _collectionFailure = failure;
    _collectionStage = CollectionPlaybackStage.failed;
    _clearCollectionTerminalClaim();
    notifyListeners();
  }

  void _clearCollectionTerminalClaim() {
    _collectionTerminalToken = null;
    _collectionTerminalTrackKey = null;
    _collectionTerminalQueueLength = null;
  }

  void _invalidateCollection() {
    ++_collectionGeneration;
    _collectionOperation?.cancel();
    _collectionOperation = null;
    _collectionLoadFuture = null;
    _collectionSource = null;
    _collectionFailure = null;
    _collectionStage = CollectionPlaybackStage.idle;
    _collectionNextCursor = 0;
    _collectionHasMore = false;
    _collectionLastDemandIndex = null;
    _collectionInitialPagesLoaded = 0;
    _clearCollectionTerminalClaim();
  }

  Future<void> _continueRoamFromTerminal(int terminalToken) async {
    final gateway = _relatedTracksGateway;
    final seed = _snapshot.current;
    if (!_roamEnabled ||
        gateway == null ||
        seed == null ||
        _snapshot.hasNext ||
        _snapshot.order != PlaybackOrder.sequential ||
        _snapshot.repeatMode != PlaybackRepeatMode.off) {
      return;
    }
    if (!supportsRelatedTracksProvider(seed.providerId)) {
      _roamStage = RoamStage.unsupported;
      notifyListeners();
      return;
    }

    final generation = ++_roamGeneration;
    final seedKey = _trackKey(seed);
    final expectedLength = _snapshot.tracks.length;
    late final RelatedTracksLoadOperation operation;
    try {
      operation = gateway.beginLoad(seed);
    } on Object {
      if (_roamIsCurrent(generation, terminalToken, seedKey, expectedLength)) {
        _roamStage = RoamStage.failed;
        notifyListeners();
      }
      return;
    }
    _roamOperation = operation;
    _roamStage = RoamStage.loading;
    notifyListeners();

    late final RelatedTracksResult result;
    try {
      result = await operation.run();
    } on Object {
      if (identical(_roamOperation, operation)) _roamOperation = null;
      if (_roamIsCurrent(generation, terminalToken, seedKey, expectedLength)) {
        _roamStage = RoamStage.failed;
        notifyListeners();
      }
      return;
    }
    if (identical(_roamOperation, operation)) _roamOperation = null;
    if (!_roamIsCurrent(generation, terminalToken, seedKey, expectedLength)) {
      return;
    }
    if (result.failure != null) {
      _roamStage = RoamStage.failed;
      notifyListeners();
      return;
    }
    if (result.tracks.any((track) => track.providerId != seed.providerId)) {
      _roamStage = RoamStage.failed;
      notifyListeners();
      return;
    }

    final identities = _snapshot.tracks.map(_trackKey).toSet();
    final additions = <PlaylistTrackSummary>[];
    for (final candidate in result.tracks) {
      if (identities.add(_trackKey(candidate))) additions.add(candidate);
    }
    if (additions.isEmpty) {
      _roamStage = RoamStage.empty;
      notifyListeners();
      return;
    }

    late final PlaybackQueueResult update;
    try {
      update = _gateway.extendAndAdvanceFromTerminal(additions);
    } on Object {
      if (_roamIsCurrent(generation, terminalToken, seedKey, expectedLength)) {
        _roamStage = RoamStage.failed;
        notifyListeners();
      }
      return;
    }
    if (!_roamIsCurrent(generation, terminalToken, seedKey, expectedLength) ||
        !_accept(update) ||
        !update.playbackRequested) {
      if (!_disposed && generation == _roamGeneration) {
        _roamStage = RoamStage.failed;
        notifyListeners();
      }
      return;
    }
    _roamStage = RoamStage.continued;
    _completionHandled = false;
    notifyListeners();
    final current = _snapshot.current;
    if (current != null) await _playback.playTrack(current);
  }

  bool _roamIsCurrent(
    int generation,
    int terminalToken,
    String seedKey,
    int expectedLength,
  ) =>
      !_disposed &&
      generation == _roamGeneration &&
      terminalToken == _terminalIntentEpoch &&
      _roamEnabled &&
      _playback.stage == TrackPlaybackStage.completed &&
      _snapshot.order == PlaybackOrder.sequential &&
      _snapshot.repeatMode == PlaybackRepeatMode.off &&
      !_snapshot.hasNext &&
      _snapshot.tracks.length == expectedLength &&
      switch (_snapshot.current) {
        final current? => _trackKey(current) == seedKey,
        null => false,
      };

  void _invalidateRoam() {
    ++_roamGeneration;
    ++_terminalIntentEpoch;
    _roamOperation?.cancel();
    _roamOperation = null;
    _roamStage = RoamStage.idle;
  }

  Future<void> _apply(
    PlaybackQueueResult result, {
    required bool playChangedCurrent,
  }) async {
    if (_disposed || !_accept(result)) return;
    if (!playChangedCurrent || !result.playbackRequested) return;

    _completionHandled = false;
    final current = _snapshot.current;
    if (current == null) {
      await _playback.stop();
    } else {
      await _playback.playTrack(current);
    }
  }

  bool _accept(PlaybackQueueResult result) {
    final failure = result.failure;
    final snapshot = result.snapshot;
    if (failure != null || snapshot == null) {
      _failure = failure ?? PlaybackQueueFailure.invalidResponse;
      if (!_disposed) notifyListeners();
      return false;
    }
    _failure = null;
    final previousCurrent = _snapshot.current;
    _snapshot = snapshot;
    if (!_sameTrack(previousCurrent, _snapshot.current)) {
      _currentTrack.value = _snapshot.current;
    }
    _syncLyricTrack();
    if (!_disposed) notifyListeners();
    return true;
  }

  void _onPlaybackChanged() {
    if (_disposed) return;
    if (_playback.stage != TrackPlaybackStage.completed &&
        _roamOperation != null) {
      _invalidateRoam();
    }
    lyrics?.updatePositionMs(_playback.positionMs);
    notifyListeners();
    if (_playback.stage == TrackPlaybackStage.completed) {
      if (!_completionHandled) {
        _completionHandled = true;
        final terminalToken = ++_terminalIntentEpoch;
        unawaited(_completeCurrent(terminalToken));
      }
    } else {
      _completionHandled = false;
      _maybeDemandCollection();
    }
  }

  void _onLyricsChanged() {
    if (!_disposed) notifyListeners();
  }

  void _syncLyricTrack() {
    final lyricController = lyrics;
    if (lyricController == null || _disposed) return;
    final current = _snapshot.current;
    final key = current == null
        ? null
        : '${current.providerId}\u0000${current.opaqueId}';
    if (key == _lyricTrackKey) return;
    _lyricTrackKey = key;
    if (current == null) {
      lyricController.clear();
    } else {
      unawaited(lyricController.load(current));
    }
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      _invalidateCollection();
      _invalidateRoam();
      _playback.removeListener(_onPlaybackChanged);
      lyrics?.removeListener(_onLyricsChanged);
      lyrics?.dispose();
      _playback.dispose();
      _currentTrack.dispose();
    }
    super.dispose();
  }
}

bool _sameTrack(PlaylistTrackSummary? first, PlaylistTrackSummary? second) =>
    first?.providerId == second?.providerId &&
    first?.opaqueId == second?.opaqueId;

String _trackKey(PlaylistTrackSummary track) =>
    '${track.providerId}\u0000${track.opaqueId}';
