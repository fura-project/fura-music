import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_media_session/flutter_media_session.dart' as fms;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/flutter_media_session_system_edge.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_stack_experiment.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

void main() {
  test('keeps the Android media session resumable while paused', () {
    expect(projectAudioServiceConfig.androidStopForegroundOnPause, isFalse);
    expect(projectAudioServiceConfig.androidResumeOnClick, isTrue);
    expect(
      projectAudioServiceConfig.androidNotificationIcon,
      'drawable/ic_stat_fura_music',
    );
    expect(projectAudioServiceConfig.androidShowNotificationBadge, isFalse);
  });

  test(
    'publishes provider-neutral queue metadata and playback state',
    () async {
      final controller = _controller();
      final handler = ProjectSystemAudioHandler(controller);

      await controller.replaceAndPlay(const [first, second], 0);

      expect(handler.queue.value, hasLength(2));
      expect(handler.mediaItem.value?.title, 'First track');
      expect(handler.mediaItem.value?.artist, 'First artist');
      expect(handler.mediaItem.value?.album, 'First album');
      expect(
        handler.mediaItem.value?.artUri,
        Uri.parse('https://img.example.test/first.jpg'),
      );
      expect(handler.mediaItem.value?.duration, const Duration(minutes: 3));
      expect(handler.mediaItem.value?.id, isNot(contains('vkey')));
      expect(handler.playbackState.value.playing, isTrue);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(handler.playbackState.value.queueIndex, 0);
      expect(
        handler.playbackState.value.controls.map((control) => control.action),
        containsAll([MediaAction.pause, MediaAction.skipToNext]),
      );
      expect(
        handler.playbackState.value.systemActions,
        containsAll([
          MediaAction.seek,
          MediaAction.setRepeatMode,
          MediaAction.setShuffleMode,
        ]),
      );

      handler.close();
      expect(handler.queue.value, isEmpty);
      expect(handler.mediaItem.value, isNull);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(handler.playbackState.value.playing, isFalse);
      controller.dispose();
    },
  );

  test(
    'system commands delegate to the single queue and playback owner',
    () async {
      final audio = _FakeAudioEngine();
      final controller = _controller(audio: audio);
      final handler = ProjectSystemAudioHandler(controller);

      await controller.replaceAndPlay(const [first, second], 0);
      await handler.pause();
      expect(audio.sessions.first.pauseCalls, 1);
      expect(controller.playback.stage, TrackPlaybackStage.paused);

      await handler.play();
      expect(audio.sessions.first.playCalls, 2);
      expect(controller.playback.stage, TrackPlaybackStage.playing);

      await handler.seek(const Duration(seconds: 42));
      expect(audio.sessions.first.seekPositions, [42000]);

      await handler.skipToNext();
      expect(controller.current, same(second));
      expect(audio.sessions, hasLength(2));

      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      expect(controller.order, PlaybackOrder.shuffle);
      expect(controller.repeatMode, PlaybackRepeatMode.one);

      await handler.customAction('projectMprisVolume', {'value': 0.35});
      expect(audio.sessions.last.volumeValues.last, 0.35);

      await handler.skipToPrevious();
      expect(controller.current, same(first));

      await handler.stop();
      expect(controller.playback.stage, TrackPlaybackStage.stopped);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );

      handler.close();
      controller.dispose();
    },
  );

  test('page listeners can detach without disabling system commands', () async {
    final audio = _FakeAudioEngine();
    final controller = _controller(audio: audio);
    final handler = ProjectSystemAudioHandler(controller);
    void pageListener() {}

    controller.addListener(pageListener);
    await controller.replaceAndPlay(const [first, second], 0);
    controller.removeListener(pageListener);

    await handler.pause();
    await handler.play();
    await handler.skipToNext();

    expect(audio.sessions.first.pauseCalls, 1);
    expect(audio.sessions.first.playCalls, 2);
    expect(controller.current, same(second));
    expect(handler.mediaItem.value?.title, 'Second track');

    handler.close();
    controller.dispose();
  });

  test('AudioService success keeps the exact initialized controller', () async {
    ProjectSystemAudioHandler? initializedHandler;
    final audioSession = _FakeProjectAudioSession();
    final audioEngine = _FakeAudioEngine();
    final host = await initializeAppPlaybackHost(
      playbackQueueGateway: _MemoryQueueGateway(),
      mediaResolutionGateway: const _MediaGateway(),
      lyricGateway: const _NeverLyricGateway(),
      audioEngine: audioEngine,
      audioServiceInitializer: (handler, config) async {
        initializedHandler = handler;
        expect(config, same(projectAudioServiceConfig));
      },
      audioSessionFactory: () async => audioSession,
    );

    expect(host, isA<AudioServiceAppPlaybackHost>());
    expect(initializedHandler, isNotNull);
    expect(host.controller, same(initializedHandler!.controller));
    expect(audioSession.configureCalls, 1);

    await host.controller.replaceAndPlay(const [first], 0);
    audioSession.emitInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    await Future<void>.delayed(Duration.zero);
    expect(audioEngine.sessions.single.pauseCalls, 1);

    await host.controller.playback.resume();
    audioSession.emitBecomingNoisy();
    await Future<void>.delayed(Duration.zero);
    expect(audioEngine.sessions.single.pauseCalls, 2);

    await host.dispose();
    await audioSession.close();
  });

  test(
    'AudioService failure falls back without replacing the controller',
    () async {
      ProjectSystemAudioHandler? initializedHandler;
      var audioSessionRequested = false;
      final host = await initializeAppPlaybackHost(
        playbackQueueGateway: _MemoryQueueGateway(),
        mediaResolutionGateway: const _MediaGateway(),
        lyricGateway: const _NeverLyricGateway(),
        audioEngine: _FakeAudioEngine(),
        audioServiceInitializer: (handler, _) async {
          initializedHandler = handler;
          throw StateError('synthetic initialization failure');
        },
        audioSessionFactory: () async {
          audioSessionRequested = true;
          return _FakeProjectAudioSession();
        },
      );

      expect(host, isA<ForegroundAppPlaybackHost>());
      expect(initializedHandler, isNotNull);
      expect(host.controller, same(initializedHandler!.controller));
      expect(audioSessionRequested, isFalse);

      await host.dispose();
    },
  );

  test(
    'flutter_media_session projects metadata state and Queue-owned commands',
    () async {
      final audio = _FakeAudioEngine();
      final controller = _controller(audio: audio);
      final driver = _FakeFlutterMediaSessionDriver();
      final edge = FuraMediaSessionAdapter(
        controller: controller,
        driver: driver,
        platform: TargetPlatform.android,
      );

      await edge.activate();
      expect(driver.autoHandleInterruptions, [false]);
      expect(driver.activateCalls, 1);

      await controller.replaceAndPlay(const [first, second], 0);
      await _waitUntil(
        () => driver.metadata.lastOrNull?.title == 'First track',
      );
      expect(driver.metadata.last.artist, 'First artist');
      expect(driver.metadata.last.album, 'First album');
      expect(
        driver.metadata.last.artworkUri,
        'https://img.example.test/first.jpg',
      );
      expect(driver.metadata.last.duration, const Duration(minutes: 3));
      await _waitUntil(
        () => driver.states.lastOrNull?.status == fms.PlaybackStatus.playing,
      );
      expect(driver.states.last.status, fms.PlaybackStatus.playing);
      expect(
        driver.availableActions.last,
        containsAll([
          fms.MediaAction.pause,
          fms.MediaAction.stop,
          fms.MediaAction.skipToNext,
          fms.MediaAction.seekTo,
          fms.MediaAction.repeat,
          fms.MediaAction.shuffle,
        ]),
      );

      driver.emit(fms.MediaAction.pause);
      await _waitUntil(() => audio.sessions.first.pauseCalls == 1);
      expect(controller.playback.stage, TrackPlaybackStage.paused);

      driver.emit(fms.MediaAction.play);
      await _waitUntil(() => audio.sessions.first.playCalls == 2);
      expect(controller.playback.stage, TrackPlaybackStage.playing);

      driver.emit(
        const fms.MediaAction('seekTo', seekPosition: Duration(seconds: 42)),
      );
      await _waitUntil(() => audio.sessions.first.seekPositions.isNotEmpty);
      expect(audio.sessions.first.seekPositions, [42000]);

      driver.emit(fms.MediaAction.skipToNext);
      await _waitUntil(() => identical(controller.current, second));
      expect(audio.sessions, hasLength(2));
      await _waitUntil(
        () => driver.metadata.lastOrNull?.title == 'Second track',
      );
      expect(driver.metadata.last.artworkUri, isNull);

      driver.emit(fms.MediaAction.shuffle);
      await _waitUntil(() => controller.order == PlaybackOrder.shuffle);
      driver.emit(fms.MediaAction.repeat);
      await _waitUntil(() => controller.repeatMode == PlaybackRepeatMode.all);
      expect(driver.states.last.shuffleModeEnabled, isTrue);
      await _waitUntil(
        () => driver.states.last.repeatMode == fms.MediaRepeatMode.all,
      );

      driver.emit(fms.MediaAction.skipToPrevious);
      await _waitUntil(() => identical(controller.current, first));
      driver.emit(fms.MediaAction.stop);
      await _waitUntil(
        () => controller.playback.stage == TrackPlaybackStage.stopped,
      );

      await edge.deactivate();
      expect(driver.deactivateCalls, 1);
      controller.dispose();
      await driver.close();
    },
  );

  test('only the selected system-media edge is initialized', () async {
    var audioServiceCalls = 0;
    final candidateDriver = _FakeFlutterMediaSessionDriver();
    final candidateAudioSession = _FakeProjectAudioSession();
    final candidateHost = await initializeAppPlaybackHost(
      playbackQueueGateway: _MemoryQueueGateway(),
      mediaResolutionGateway: const _MediaGateway(),
      lyricGateway: const _NeverLyricGateway(),
      audioEngine: _FakeAudioEngine(),
      systemMediaEdge: SystemMediaEdgeKind.flutterMediaSession,
      platform: TargetPlatform.android,
      flutterMediaSessionDriver: candidateDriver,
      audioServiceInitializer: (_, _) async => audioServiceCalls += 1,
      audioSessionFactory: () async => candidateAudioSession,
    );

    expect(candidateHost, isA<FlutterMediaSessionAppPlaybackHost>());
    expect(candidateDriver.activateCalls, 1);
    expect(audioServiceCalls, 0);
    expect(candidateAudioSession.configureCalls, 1);
    await candidateHost.dispose();
    await candidateAudioSession.close();
    await candidateDriver.close();

    final unusedCandidateDriver = _FakeFlutterMediaSessionDriver();
    final baselineAudioSession = _FakeProjectAudioSession();
    final baselineHost = await initializeAppPlaybackHost(
      playbackQueueGateway: _MemoryQueueGateway(),
      mediaResolutionGateway: const _MediaGateway(),
      lyricGateway: const _NeverLyricGateway(),
      audioEngine: _FakeAudioEngine(),
      systemMediaEdge: SystemMediaEdgeKind.audioService,
      platform: TargetPlatform.android,
      flutterMediaSessionDriver: unusedCandidateDriver,
      audioServiceInitializer: (_, _) async => audioServiceCalls += 1,
      audioSessionFactory: () async => baselineAudioSession,
    );

    expect(baselineHost, isA<AudioServiceAppPlaybackHost>());
    expect(audioServiceCalls, 1);
    expect(unusedCandidateDriver.activateCalls, 0);
    expect(baselineAudioSession.configureCalls, 1);
    await baselineHost.dispose();
    await baselineAudioSession.close();
    await unusedCandidateDriver.close();
  });

  test(
    'iOS candidate is rejected before taking AVAudioSession ownership',
    () async {
      final driver = _FakeFlutterMediaSessionDriver();
      final controller = _controller();
      final edge = FuraMediaSessionAdapter(
        controller: controller,
        driver: driver,
        platform: TargetPlatform.iOS,
      );

      await expectLater(edge.activate(), throwsUnsupportedError);
      expect(driver.activateCalls, 0);
      expect(driver.autoHandleInterruptions, isEmpty);

      controller.dispose();
      await driver.close();
    },
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached before the bounded test deadline.');
}

const first = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'first',
  title: 'First track',
  artistNames: ['First artist'],
  albumTitle: 'First album',
  artworkUri: 'https://img.example.test/first.jpg',
  durationSeconds: 180,
);

const second = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'second',
  title: 'Second track',
  artistNames: ['Second artist'],
  artworkUri: 'not a URI',
  durationSeconds: 240,
);

QueuePlaybackController _controller({_FakeAudioEngine? audio}) =>
    QueuePlaybackController(
      _MemoryQueueGateway(),
      TrackPlaybackController(
        const _MediaGateway(),
        ForegroundPlaybackController(audio ?? _FakeAudioEngine()),
      ),
    );

class _MemoryQueueGateway implements PlaybackQueueGateway {
  PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot.empty();

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) => _update(tracks, currentIndex, playbackRequested: true);

  @override
  PlaybackQueueResult advance() {
    final current = _snapshot.currentIndex;
    if (current == null || _snapshot.tracks.isEmpty) return snapshot();
    final next = current + 1 < _snapshot.tracks.length ? current + 1 : 0;
    return _update(_snapshot.tracks, next, playbackRequested: next != current);
  }

  @override
  PlaybackQueueResult rewind() {
    final current = _snapshot.currentIndex;
    if (current == null || _snapshot.tracks.isEmpty) return snapshot();
    final previous = current > 0 ? current - 1 : _snapshot.tracks.length - 1;
    return _update(
      _snapshot.tracks,
      previous,
      playbackRequested: previous != current,
    );
  }

  @override
  PlaybackQueueResult select(int index) =>
      _update(_snapshot.tracks, index, playbackRequested: true);

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) {
    _snapshot = _copy(order: order);
    return snapshot();
  }

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) {
    _snapshot = _copy(repeatMode: repeatMode);
    return snapshot();
  }

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) => _update(
    [..._snapshot.tracks, track],
    _snapshot.currentIndex ?? 0,
    playbackRequested: _snapshot.currentIndex == null,
  );

  @override
  PlaybackQueueResult remove(int index) {
    final tracks = [..._snapshot.tracks]..removeAt(index);
    if (tracks.isEmpty) return _update(const [], null, playbackRequested: true);
    final current = _snapshot.currentIndex ?? 0;
    return _update(
      tracks,
      current > index ? current - 1 : current.clamp(0, tracks.length - 1),
      playbackRequested: current == index,
    );
  }

  @override
  PlaybackQueueResult clear() =>
      _update(const [], null, playbackRequested: true);

  @override
  PlaybackQueueResult completeCurrent() => advance();

  PlaybackQueueResult _update(
    List<PlaylistTrackSummary> tracks,
    int? currentIndex, {
    required bool playbackRequested,
  }) {
    _snapshot = PlaybackQueueSnapshot(
      tracks: List.unmodifiable(tracks),
      currentIndex: currentIndex,
      hasPrevious: currentIndex != null && tracks.length > 1,
      hasNext: currentIndex != null && tracks.length > 1,
      order: _snapshot.order,
      repeatMode: _snapshot.repeatMode,
    );
    return PlaybackQueueResult(
      snapshot: _snapshot,
      playbackRequested: playbackRequested,
    );
  }

  PlaybackQueueSnapshot _copy({
    PlaybackOrder? order,
    PlaybackRepeatMode? repeatMode,
  }) => PlaybackQueueSnapshot(
    tracks: _snapshot.tracks,
    currentIndex: _snapshot.currentIndex,
    hasPrevious: _snapshot.hasPrevious,
    hasNext: _snapshot.hasNext,
    order: order ?? _snapshot.order,
    repeatMode: repeatMode ?? _snapshot.repeatMode,
  );
}

class _MediaGateway implements MediaResolutionGateway {
  const _MediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => _ResolutionOperation(opaqueTrackId);
}

class _ResolutionOperation implements MediaResolutionOperation {
  const _ResolutionOperation(this.id);

  final String id;

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async => MediaResolutionResult(
    source: ResolvedPlaybackSource(
      uri: Uri.parse('https://audio.example.test/$id.mp3'),
      format: PlaybackAudioFormat.mp3,
      quality: PlaybackAudioQuality.standard,
      validForSeconds: 3600,
    ),
  );
}

class _FakeAudioEngine implements ForegroundAudioEngine {
  final List<_FakeAudioSession> sessions = [];

  @override
  Future<void> dispose() async {}

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) async {
    final session = _FakeAudioSession();
    sessions.add(session);
    return session;
  }
}

class _FakeAudioSession implements ForegroundAudioSession {
  final _states = StreamController<ForegroundAudioState>.broadcast();
  final _failures = StreamController<ForegroundAudioFailure>.broadcast();
  final _positions = StreamController<int>.broadcast();
  int playCalls = 0;
  int pauseCalls = 0;
  final List<int> seekPositions = [];
  final List<double> volumeValues = [];

  @override
  Stream<ForegroundAudioState> get states => _states.stream;

  @override
  Stream<ForegroundAudioFailure> get failures => _failures.stream;

  @override
  Stream<int> get positionMs => _positions.stream;

  @override
  Future<void> play() async {
    playCalls += 1;
    _states.add(ForegroundAudioState.playing);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    _states.add(ForegroundAudioState.paused);
  }

  @override
  Future<void> seekToMs(int positionMs) async {
    seekPositions.add(positionMs);
    _positions.add(positionMs);
  }

  @override
  Future<void> setVolume(double volume) async => volumeValues.add(volume);

  @override
  Future<void> stop() async => _states.add(ForegroundAudioState.stopped);

  @override
  Future<void> dispose() async {
    await _states.close();
    await _failures.close();
    await _positions.close();
  }
}

class _NeverLyricGateway implements LyricGateway {
  const _NeverLyricGateway();

  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) => const _UnavailableLyricOperation();
}

class _UnavailableLyricOperation implements LyricLoadOperation {
  const _UnavailableLyricOperation();

  @override
  bool cancel() => true;

  @override
  Future<LyricLoadResult> run() async =>
      const LyricLoadResult(failure: LyricFailure.unavailable);
}

class _FakeProjectAudioSession implements ProjectAudioSession {
  final _interruptions = StreamController<AudioInterruptionEvent>.broadcast();
  final _becomingNoisy = StreamController<void>.broadcast();
  int configureCalls = 0;

  @override
  Stream<AudioInterruptionEvent> get interruptionEvents =>
      _interruptions.stream;

  @override
  Stream<void> get becomingNoisyEvents => _becomingNoisy.stream;

  @override
  Future<void> configureMusic() async => configureCalls += 1;

  void emitInterruption(AudioInterruptionEvent event) =>
      _interruptions.add(event);

  void emitBecomingNoisy() => _becomingNoisy.add(null);

  Future<void> close() async {
    await _interruptions.close();
    await _becomingNoisy.close();
  }
}

class _FakeFlutterMediaSessionDriver implements FlutterMediaSessionDriver {
  final _actions = StreamController<fms.MediaAction>.broadcast();
  final List<bool> autoHandleInterruptions = [];
  final List<fms.MediaMetadata> metadata = [];
  final List<fms.PlaybackState> states = [];
  final List<Set<fms.MediaAction>> availableActions = [];
  int activateCalls = 0;
  int deactivateCalls = 0;

  @override
  Stream<fms.MediaAction> get actions => _actions.stream;

  @override
  Future<void> setAutoHandleInterruptions(bool enabled) async =>
      autoHandleInterruptions.add(enabled);

  @override
  Future<void> activate() async => activateCalls += 1;

  @override
  Future<void> deactivate() async => deactivateCalls += 1;

  @override
  Future<void> updateMetadata(fms.MediaMetadata value) async =>
      metadata.add(value);

  @override
  Future<void> updatePlaybackState(fms.PlaybackState value) async =>
      states.add(value);

  @override
  Future<void> updateAvailableActions(Set<fms.MediaAction> value) async =>
      availableActions.add(Set.unmodifiable(value));

  void emit(fms.MediaAction action) => _actions.add(action);

  Future<void> close() => _actions.close();
}
