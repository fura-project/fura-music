import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/radar_controller.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_track_search_index.dart';
import 'package:flutterustmusic/library/track_like_presentation_controller.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

void main() {
  test(
    'P01 deterministic search index benchmark across 1k, 10k, 50k tracks',
    () {
      for (final size in const [1000, 10000, 50000]) {
        final targetIndex = size - 67;
        final tracks = List.generate(
          size,
          (index) => PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:$index',
            title: index == targetIndex
                ? 'Nevada'
                : 'Synthetic Horizon Song ${index % 997} Part $index',
            artistNames: [
              index == targetIndex ? 'Vicetone' : 'Artist ${index % 251}',
            ],
            albumTitle: 'Album Collection ${index % 509}',
          ),
          growable: false,
        );

        final rssBefore = ProcessInfo.currentRss;
        final buildWatch = Stopwatch()..start();
        final index = PlaylistTrackSearchIndex()
          ..update(tracks, collectionGeneration: 1);
        buildWatch.stop();

        final exactWatch = Stopwatch()..start();
        final exactResult = index.search('Nevada');
        exactWatch.stop();
        expect(exactResult.tracks.single.opaqueId, 'track:$targetIndex');

        final fuzzyWatch = Stopwatch()..start();
        final fuzzyResult = index.search('neveda');
        fuzzyWatch.stop();
        expect(fuzzyResult.tracks.single.opaqueId, 'track:$targetIndex');

        final replaceWatch = Stopwatch()..start();
        for (final query in const [
          'n',
          'ne',
          'nev',
          'neve',
          'neved',
          'neveda',
          'NEVEDA',
          'nevada',
        ]) {
          index.search(query);
        }
        replaceWatch.stop();

        final replacedTracks = List<PlaylistTrackSummary>.of(tracks);
        replacedTracks[0] = const PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:replaced-0',
          title: 'Replaced First',
          artistNames: ['Artist'],
        );
        final rebuildWatch = Stopwatch()..start();
        index.update(replacedTracks, collectionGeneration: 2);
        rebuildWatch.stop();

        final incrementalIndex = PlaylistTrackSearchIndex();
        final incrementalWatch = Stopwatch()..start();
        for (var end = 100; end <= size; end += 100) {
          incrementalIndex.update(
            tracks.sublist(0, end),
            collectionGeneration: 1,
          );
        }
        if (size % 100 != 0) {
          incrementalIndex.update(tracks, collectionGeneration: 1);
        }
        incrementalWatch.stop();
        final rssAfter = ProcessInfo.currentRss;

        // ignore: avoid_print
        print(
          'BENCH_AFTER size=$size '
          'build_ms=${buildWatch.elapsedMilliseconds} '
          'inc_append_ms=${incrementalWatch.elapsedMilliseconds} '
          'rebuild_ms=${rebuildWatch.elapsedMilliseconds} '
          'exact_us=${exactWatch.elapsedMicroseconds} '
          'fuzzy_us=${fuzzyWatch.elapsedMicroseconds} '
          'rapid_replace_us=${replaceWatch.elapsedMicroseconds} '
          'rss_delta_kb=${(rssAfter - rssBefore) ~/ 1024}',
        );
      }
    },
  );

  test('P02 & P03 & P06: warm 1117-track search (0 HTTP) vs cold 1117-track search (12 HTTP, concurrency=1)', () async {
    const total = 1117;
    const targetIndex = 1050;
    const likedPlaylist = UserPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'liked:1117',
      title: 'Liked Songs',
      trackCount: total,
      isLikedSongs: true,
      ownership: UserPlaylistOwnership.owned,
    );
    final pages = <int, PlaylistTrackPageResult>{};
    for (var offset = 0; offset < total; offset += 100) {
      final end = (offset + 100).clamp(0, total);
      pages[offset] = PlaylistTrackPageResult(
        offset: offset,
        nextOffset: end,
        total: total,
        hasMore: end < total,
        membershipTrackOpaqueIds: [
          for (var i = offset; i < end; i++) 'track:$i',
        ],
        tracks: [
          for (var i = offset; i < end; i++)
            PlaylistTrackSummary(
              providerId: 'qq-music',
              opaqueId: 'track:$i',
              title: i == targetIndex ? 'Nevada' : 'Song $i',
              artistNames: [i == targetIndex ? 'Vicetone' : 'Artist $i'],
            ),
        ],
      );
    }

    // P02: Warm cache search
    final warmGateway = _MeasuredDetailGateway(pages);
    final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
    addTearDown(mutations.dispose);
    final likes = TrackLikePresentationController(
      providerId: 'qq-music',
      enabled: true,
      playlistGateway: warmGateway,
      mutations: mutations,
    )..bindLikedPlaylist(likedPlaylist);
    addTearDown(likes.dispose);
    await likes.preload();
    expect(warmGateway.requests, 12);

    final warmDetail = PlaylistDetailController(
      likedPlaylist,
      likes.sessionGateway,
    );
    addTearDown(warmDetail.dispose);
    await warmDetail.load();
    final requestsBeforeWarmSearch = warmGateway.requests;
    final warmWatch = Stopwatch()..start();
    await warmDetail.requestSearchCoverage();
    final warmIndex = PlaylistTrackSearchIndex()
      ..update(
        warmDetail.tracks,
        collectionGeneration: warmDetail.snapshotGeneration,
      );
    final warmMatch = warmIndex.search('neveda');
    warmWatch.stop();

    expect(warmGateway.requests - requestsBeforeWarmSearch, 0);
    expect(warmMatch.tracks.single.opaqueId, 'track:$targetIndex');
    expect(warmDetail.processedCount, 1117);
    expect(warmDetail.searchScanStage, CollectionSearchScanStage.complete);

    // P03 & P06: Cold cache search (zero duplicates, peak concurrency 1)
    final coldGateway = _MeasuredDetailGateway(pages);
    final coldDetail = PlaylistDetailController(
      likedPlaylist,
      coldGateway,
      loadAllPageInterval: Duration.zero,
    );
    addTearDown(coldDetail.dispose);
    await coldDetail.load();
    final coldWatch = Stopwatch()..start();
    await coldDetail.requestSearchCoverage();
    final coldIndex = PlaylistTrackSearchIndex()
      ..update(
        coldDetail.tracks,
        collectionGeneration: coldDetail.snapshotGeneration,
      );
    final coldMatch = coldIndex.search('neveda');
    coldWatch.stop();

    expect(coldGateway.requests, 12);
    expect(coldGateway.duplicateOffsetRequests, 0);
    expect(coldGateway.peakConcurrency, 1);
    expect(coldMatch.tracks.single.opaqueId, 'track:$targetIndex');

    // ignore: avoid_print
    print(
      'BENCH_P02_P03 warm_us=${warmWatch.elapsedMicroseconds} '
      'warm_extra_http=${warmGateway.requests - requestsBeforeWarmSearch} '
      'cold_us=${coldWatch.elapsedMicroseconds} '
      'cold_http=${coldGateway.requests} '
      'cold_dup=${coldGateway.duplicateOffsetRequests} '
      'cold_peak_conc=${coldGateway.peakConcurrency}',
    );
  });

  test('P04 & P05 & P06: Radar click-to-first-track vs click-to-20/30/50 queue fill timeline', () async {
    final radarGateway = _TimedRadarGateway(
      pageLatency: const Duration(milliseconds: 10),
    );
    final radar = RadarController(radarGateway);
    addTearDown(radar.dispose);
    await radar.load();
    expect(radar.tracks, hasLength(1));

    final queue = QueuePlaybackController(
      _BenchQueueGateway(),
      TrackPlaybackController(
        const _DelayedMediaGateway(Duration(milliseconds: 120)),
        ForegroundPlaybackController(const _InstantAudioEngine()),
      ),
    );
    addTearDown(queue.dispose);

    final watch = Stopwatch()..start();
    int? firstPlayingMs;
    int? reached20Ms;
    int? reached30Ms;
    int? reached50Ms;
    final done50 = Completer<void>();

    void observe() {
      final elapsed = watch.elapsedMilliseconds;
      if (firstPlayingMs == null &&
          queue.playback.stage == TrackPlaybackStage.playing) {
        firstPlayingMs = elapsed;
      }
      if (reached20Ms == null && queue.tracks.length >= 20) {
        reached20Ms = elapsed;
      }
      if (reached30Ms == null && queue.tracks.length >= 30) {
        reached30Ms = elapsed;
      }
      if (reached50Ms == null && queue.tracks.length >= 50) {
        reached50Ms = elapsed;
        if (!done50.isCompleted) done50.complete();
      }
    }

    queue.addListener(observe);
    await queue.replaceAndPlayCollection(
      radar.collectionPlaybackSource(providerId: 'qq-music'),
      0,
    );
    await done50.future;
    queue.removeListener(observe);

    expect(queue.tracks, hasLength(51));
    expect(radarGateway.duplicatePageRequests, 0);
    expect(radarGateway.peakConcurrency, 1);
    // Queue reaches 20, 30, and 50 tracks BEFORE or independently of the 120ms media resolution!
    expect(reached50Ms!, lessThanOrEqualTo(firstPlayingMs! + 40));

    // ignore: avoid_print
    print(
      'BENCH_P04_P05 first_play_ms=$firstPlayingMs '
      'queue20_ms=$reached20Ms queue30_ms=$reached30Ms queue50_ms=$reached50Ms '
      'dup_pages=${radarGateway.duplicatePageRequests} '
      'peak_conc=${radarGateway.peakConcurrency}',
    );
  });
}

class _MeasuredDetailGateway implements PlaylistDetailGateway {
  _MeasuredDetailGateway(this.pages);

  final Map<int, PlaylistTrackPageResult> pages;
  final Set<int> _seenOffsets = {};
  int requests = 0;
  int duplicateOffsetRequests = 0;
  int _inFlight = 0;
  int peakConcurrency = 0;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    requests += 1;
    if (!_seenOffsets.add(offset)) duplicateOffsetRequests += 1;
    return _MeasuredDetailOp(
      pages[offset]!,
      onStart: () {
        _inFlight += 1;
        if (_inFlight > peakConcurrency) peakConcurrency = _inFlight;
      },
      onEnd: () => _inFlight -= 1,
    );
  }
}

class _MeasuredDetailOp implements PlaylistTrackPageLoadOperation {
  _MeasuredDetailOp(this.result, {required this.onStart, required this.onEnd});
  final PlaylistTrackPageResult result;
  final void Function() onStart;
  final void Function() onEnd;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async {
    onStart();
    try {
      await Future<void>.delayed(Duration.zero);
      return result;
    } finally {
      onEnd();
    }
  }
}

class _TimedRadarGateway implements RadarGateway {
  _TimedRadarGateway({required this.pageLatency});

  final Duration pageLatency;
  final Set<int> _seenPages = {};
  int duplicatePageRequests = 0;
  int _inFlight = 0;
  int peakConcurrency = 0;

  @override
  RadarTrackPageLoadOperation beginLoad({required int page}) {
    if (!_seenPages.add(page)) duplicatePageRequests += 1;
    return _TimedRadarOp(
      page: page,
      delay: page == 1 ? Duration.zero : pageLatency,
      onStart: () {
        _inFlight += 1;
        if (_inFlight > peakConcurrency) peakConcurrency = _inFlight;
      },
      onEnd: () => _inFlight -= 1,
    );
  }
}

class _TimedRadarOp implements RadarTrackPageLoadOperation {
  _TimedRadarOp({
    required this.page,
    required this.delay,
    required this.onStart,
    required this.onEnd,
  });

  final int page;
  final Duration delay;
  final void Function() onStart;
  final void Function() onEnd;

  @override
  bool cancel() => true;

  @override
  Future<RadarTrackPageResult> run() async {
    onStart();
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final count = page == 1 ? 1 : 10;
      return RadarTrackPageResult(
        page: page,
        hasMore: true,
        tracks: List.generate(
          count,
          (i) => PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'radar:$page:$i',
            title: 'Radar $page-$i',
            artistNames: const ['Artist'],
          ),
        ),
      );
    } finally {
      onEnd();
    }
  }
}

class _DelayedMediaGateway implements MediaResolutionGateway {
  const _DelayedMediaGateway(this.delay);
  final Duration delay;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => _DelayedMediaOp(opaqueTrackId, delay);
}

class _DelayedMediaOp implements MediaResolutionOperation {
  _DelayedMediaOp(this.opaqueTrackId, this.delay);
  final String opaqueTrackId;
  final Duration delay;

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async {
    await Future<void>.delayed(delay);
    return MediaResolutionResult(
      source: ResolvedPlaybackSource(
        uri: Uri.parse('https://example.invalid/$opaqueTrackId.mp3'),
        format: PlaybackAudioFormat.mp3,
        quality: PlaybackAudioQuality.standard,
        validForSeconds: 300,
      ),
    );
  }
}

class _InstantAudioEngine implements ForegroundAudioEngine {
  const _InstantAudioEngine();

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) async => _InstantAudioSession();

  @override
  Future<void> dispose() async {}
}

class _InstantAudioSession implements ForegroundAudioSession {
  final _states = StreamController<ForegroundAudioState>.broadcast();
  final _failures = StreamController<ForegroundAudioFailure>.broadcast();
  final _positions = StreamController<int>.broadcast();

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> play() async => _states.add(ForegroundAudioState.playing);

  @override
  Future<void> pause() async => _states.add(ForegroundAudioState.paused);

  @override
  Future<void> seekToMs(int positionMs) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async => _states.add(ForegroundAudioState.stopped);

  @override
  Future<void> dispose() async {
    await _states.close();
    await _failures.close();
    await _positions.close();
  }
}

class _BenchQueueGateway
    implements PlaybackQueueGateway, PlaybackQueueBatchGateway {
  List<PlaylistTrackSummary> _tracks = const [];
  int? _current;

  PlaybackQueueResult _ok({bool changed = false}) => PlaybackQueueResult(
    snapshot: PlaybackQueueSnapshot(
      tracks: List.unmodifiable(_tracks),
      currentIndex: _current,
      hasPrevious: _current != null && _current! > 0,
      hasNext: _current != null && _current! + 1 < _tracks.length,
    ),
    playbackRequested: changed,
  );

  @override
  PlaybackQueueResult snapshot() => _ok();

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    int? currentIndex,
  }) {
    _tracks = List.of(tracks);
    _current = currentIndex;
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult extend(List<PlaylistTrackSummary> tracks) {
    _tracks = [..._tracks, ...tracks];
    return _ok();
  }

  @override
  PlaybackQueueResult extendAndAdvanceFromTerminal(
    List<PlaylistTrackSummary> tracks,
  ) {
    _current = _tracks.length;
    _tracks = [..._tracks, ...tracks];
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) {
    _tracks = [..._tracks, track];
    _current ??= 0;
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult select(int index) {
    _current = index;
    return _ok(changed: true);
  }

  @override
  PlaybackQueueResult advance() => _ok();

  @override
  PlaybackQueueResult rewind() => _ok();

  @override
  PlaybackQueueResult completeCurrent() => _ok();

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) => _ok();

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) => _ok();

  @override
  PlaybackQueueResult remove(int index) => _ok();

  @override
  PlaybackQueueResult clear() => _ok();
}
