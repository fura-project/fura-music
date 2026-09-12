import 'dart:async';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/linux_mpris_audio_service.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

/// App-lifetime playback owner shared by Flutter UI and operating-system media
/// controls. A page may observe [controller], but must never dispose or replace
/// it. This keeps Android's AudioService lifecycle independent from navigation.
abstract interface class AppPlaybackHost {
  bool get systemControlsAvailable;

  QueuePlaybackController get controller;

  Future<void> dispose();
}

class ForegroundAppPlaybackHost implements AppPlaybackHost {
  ForegroundAppPlaybackHost(this.controller);

  @override
  final QueuePlaybackController controller;

  bool _disposed = false;

  @override
  bool get systemControlsAvailable => false;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
  }
}

class AudioServiceAppPlaybackHost implements AppPlaybackHost {
  AudioServiceAppPlaybackHost._(
    this._handler,
    this._interruptionSubscription,
    this._becomingNoisySubscription,
  );

  final ProjectSystemAudioHandler _handler;
  final StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  final StreamSubscription<void>? _becomingNoisySubscription;
  bool _disposed = false;

  @override
  QueuePlaybackController get controller => _handler.controller;

  @override
  bool get systemControlsAvailable => true;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _handler.close();
    await _interruptionSubscription?.cancel();
    await _becomingNoisySubscription?.cancel();
    controller.dispose();
  }
}

QueuePlaybackController createAppPlaybackController({
  required PlaybackQueueGateway playbackQueueGateway,
  required MediaResolutionGateway mediaResolutionGateway,
  required LyricGateway lyricGateway,
  required ForegroundAudioEngine audioEngine,
}) => QueuePlaybackController(
  playbackQueueGateway,
  TrackPlaybackController(
    mediaResolutionGateway,
    ForegroundPlaybackController(audioEngine),
  ),
  lyrics: LyricController(lyricGateway),
);

AppPlaybackHost createForegroundAppPlaybackHost({
  required PlaybackQueueGateway playbackQueueGateway,
  required MediaResolutionGateway mediaResolutionGateway,
  required LyricGateway lyricGateway,
  required ForegroundAudioEngine audioEngine,
}) => ForegroundAppPlaybackHost(
  createAppPlaybackController(
    playbackQueueGateway: playbackQueueGateway,
    mediaResolutionGateway: mediaResolutionGateway,
    lyricGateway: lyricGateway,
    audioEngine: audioEngine,
  ),
);

/// One cross-platform media-session configuration. Android keeps the playback
/// foreground service alive while paused so notification, lock-screen and
/// headset resume do not need to start a new foreground service from the
/// background on Android 12+.
@visibleForTesting
const projectAudioServiceConfig = AudioServiceConfig(
  androidNotificationChannelId: 'dev.axiaobo.flutterustmusic.playback',
  androidNotificationChannelName: 'fura music playback',
  androidNotificationChannelDescription: 'Playback controls for fura music',
  androidNotificationIcon: 'drawable/ic_stat_fura_music',
  androidNotificationOngoing: false,
  androidShowNotificationBadge: false,
  androidResumeOnClick: true,
  androidStopForegroundOnPause: false,
);

/// Creates the single app-lifetime playback owner and gives that same owner to
/// audio_service. Android's foreground service, MediaSession, notification and
/// remote callbacks are plugin-owned; the project handler only maps those
/// callbacks onto the Rust-backed queue and the selected audio engine.
///
/// A platform media-session failure is deliberately non-fatal: the returned
/// foreground host still owns the exact same controller, so in-app playback
/// remains available without creating a fallback player or queue.
Future<AppPlaybackHost> initializeAppPlaybackHost({
  required PlaybackQueueGateway playbackQueueGateway,
  required MediaResolutionGateway mediaResolutionGateway,
  required LyricGateway lyricGateway,
  required ForegroundAudioEngine audioEngine,
}) async {
  final controller = createAppPlaybackController(
    playbackQueueGateway: playbackQueueGateway,
    mediaResolutionGateway: mediaResolutionGateway,
    lyricGateway: lyricGateway,
    audioEngine: audioEngine,
  );
  final handler = ProjectSystemAudioHandler(controller);
  try {
    registerProjectLinuxMprisAudioService();
    await AudioService.init(
      builder: () => handler,
      config: projectAudioServiceConfig,
    );
  } on Object catch (error) {
    handler.close(clearPlatformState: false);
    developer.log(
      'System media-session initialization failed; '
      'phase=audio-service platform=${defaultTargetPlatform.name} '
      'errorType=${error.runtimeType}; foreground playback remains available.',
      name: 'fura_music.system_playback',
      level: 1000,
    );
    return ForegroundAppPlaybackHost(controller);
  }

  StreamSubscription<AudioInterruptionEvent>? interruptionSubscription;
  StreamSubscription<void>? becomingNoisySubscription;
  try {
    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.music());
    interruptionSubscription = audioSession.interruptionEventStream.listen((
      event,
    ) {
      if (event.begin && event.type != AudioInterruptionType.duck) {
        unawaited(handler.pause());
      }
    });
    becomingNoisySubscription = audioSession.becomingNoisyEventStream.listen(
      (_) => unawaited(handler.pause()),
    );
  } on Object catch (error) {
    developer.log(
      'Audio focus configuration failed; '
      'platform=${defaultTargetPlatform.name} errorType=${error.runtimeType}; '
      'the initialized system media session remains active.',
      name: 'fura_music.system_playback',
      level: 900,
    );
  }

  developer.log(
    'System media session ready; platform=${defaultTargetPlatform.name}.',
    name: 'fura_music.system_playback',
  );
  return AudioServiceAppPlaybackHost._(
    handler,
    interruptionSubscription,
    becomingNoisySubscription,
  );
}

/// The app-lifetime AudioHandler and playback owner. The Rust-backed queue stays
/// authoritative, but it is permanently owned by this service-facing handler
/// instead of being borrowed from a page's State object.
class ProjectSystemAudioHandler extends BaseAudioHandler {
  ProjectSystemAudioHandler(this.controller) {
    controller.addListener(_synchronize);
    _synchronize(force: true);
  }

  final QueuePlaybackController controller;
  String? _lastQueueSignature;
  String? _lastItemSignature;
  _PublishedPlayback? _lastPlayback;
  bool _closed = false;

  void close({bool clearPlatformState = true}) {
    if (_closed) return;
    _closed = true;
    controller.removeListener(_synchronize);
    _lastQueueSignature = null;
    _lastItemSignature = null;
    _lastPlayback = null;
    if (clearPlatformState) {
      queue.add(const []);
      mediaItem.add(null);
      playbackState.add(
        PlaybackState(
          processingState: AudioProcessingState.idle,
          playing: false,
        ),
      );
    }
  }

  @override
  Future<void> play() async {
    if (_closed) {
      _logCommand('play', accepted: false, reason: 'host-closed');
      return;
    }
    final playback = controller.playback;
    if (playback.canResume) {
      _logCommand('play', accepted: true, reason: 'resume');
      await playback.resume();
    } else if (playback.canActivate) {
      _logCommand('play', accepted: true, reason: 'activate-current');
      await playback.activate();
    } else {
      _logCommand('play', accepted: false, reason: 'no-playable-current');
    }
  }

  @override
  Future<void> pause() async {
    if (_closed) {
      _logCommand('pause', accepted: false, reason: 'host-closed');
      return;
    }
    final playback = controller.playback;
    _logCommand(
      'pause',
      accepted: playback.canPause,
      reason: playback.canPause ? 'playing' : 'not-playing',
    );
    if (playback.canPause) await playback.pause();
  }

  @override
  Future<void> stop() async {
    if (_closed) {
      _logCommand('stop', accepted: false, reason: 'host-closed');
      return;
    }
    final playback = controller.playback;
    _logCommand(
      'stop',
      accepted: controller.current != null,
      reason: controller.current == null ? 'empty-queue' : 'current-present',
    );
    if (controller.current != null) {
      await playback.stop();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_closed) {
      _logCommand('seek', accepted: false, reason: 'host-closed');
      return;
    }
    final playback = controller.playback;
    _logCommand(
      'seek',
      accepted: playback.canSeek,
      reason: playback.canSeek ? 'seekable' : 'not-seekable',
    );
    if (playback.canSeek) {
      await playback.seekToMs(position.inMilliseconds);
      _synchronize(force: true);
    }
  }

  @override
  Future<void> skipToNext() async {
    final accepted =
        !_closed &&
        !controller.playback.requiresAuthentication &&
        controller.hasNext;
    _logCommand(
      'next',
      accepted: accepted,
      reason: _queueCommandReason(hasTarget: controller.hasNext),
    );
    if (accepted) {
      await controller.advance();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final accepted =
        !_closed &&
        !controller.playback.requiresAuthentication &&
        controller.hasPrevious;
    _logCommand(
      'previous',
      accepted: accepted,
      reason: _queueCommandReason(hasTarget: controller.hasPrevious),
    );
    if (accepted) {
      await controller.rewind();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final accepted =
        !_closed &&
        !controller.playback.requiresAuthentication &&
        index >= 0 &&
        index < controller.tracks.length;
    _logCommand(
      'queue-item',
      accepted: accepted,
      reason: _queueCommandReason(
        hasTarget: index >= 0 && index < controller.tracks.length,
      ),
    );
    if (accepted) {
      await controller.select(index);
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _logCommand(
      'repeat',
      accepted: !_closed,
      reason: _closed ? 'host-closed' : 'active-host',
    );
    if (_closed) return;
    await controller.setRepeatMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => PlaybackRepeatMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => PlaybackRepeatMode.all,
      AudioServiceRepeatMode.none => PlaybackRepeatMode.off,
    });
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _logCommand(
      'shuffle',
      accepted: !_closed,
      reason: _closed ? 'host-closed' : 'active-host',
    );
    if (_closed) return;
    await controller.setOrder(
      shuffleMode == AudioServiceShuffleMode.none
          ? PlaybackOrder.sequential
          : PlaybackOrder.shuffle,
    );
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name != projectMprisVolumeAction) {
      return super.customAction(name, extras);
    }
    final rawValue = extras?['value'];
    if (_closed || rawValue is! num || !rawValue.isFinite) return null;
    await controller.playback.setVolume(rawValue.toDouble().clamp(0, 1));
    _synchronize(force: true);
    return null;
  }

  @override
  Future<void> onTaskRemoved() async {
    developer.log(
      'Android task removed; playbackStage=${controller.playback.stage.name}.',
      name: 'fura_music.system_playback',
    );
  }

  @override
  Future<void> onNotificationDeleted() async {
    _logCommand(
      'notification-deleted',
      accepted: !_closed,
      reason: _closed ? 'host-closed' : 'stop-playback',
    );
    await stop();
  }

  String _queueCommandReason({required bool hasTarget}) {
    if (_closed) return 'host-closed';
    if (controller.playback.requiresAuthentication) {
      return 'authentication-required';
    }
    return hasTarget ? 'target-present' : 'target-unavailable';
  }

  void _logCommand(
    String action, {
    required bool accepted,
    required String reason,
  }) {
    developer.log(
      'System media command; action=$action accepted=$accepted reason=$reason.',
      name: 'fura_music.system_playback',
    );
  }

  void _synchronize({bool force = false}) {
    if (_closed) return;

    final queueItems = <MediaItem>[
      for (var index = 0; index < controller.tracks.length; index += 1)
        _mediaItem(controller.tracks[index], index),
    ];
    final queueSignature = queueItems
        .map(
          (item) => '${item.id}\u0000${item.title}\u0000${item.artUri ?? ''}',
        )
        .join('\u0001');
    if (force || queueSignature != _lastQueueSignature) {
      _lastQueueSignature = queueSignature;
      queue.add(List.unmodifiable(queueItems));
    }

    final currentIndex = controller.currentIndex;
    final currentItem =
        currentIndex == null || currentIndex >= queueItems.length
        ? null
        : queueItems[currentIndex];
    final itemSignature = currentItem == null
        ? null
        : '${currentItem.id}\u0000${currentItem.title}\u0000'
              '${currentItem.artist ?? ''}\u0000${currentItem.album ?? ''}\u0000'
              '${currentItem.duration?.inMilliseconds ?? -1}\u0000'
              '${currentItem.artUri ?? ''}';
    if (force || itemSignature != _lastItemSignature) {
      _lastItemSignature = itemSignature;
      mediaItem.add(currentItem);
    }

    final stage = controller.playback.stage;
    final position = Duration(
      milliseconds: controller.playback.positionMs.clamp(0, 1 << 62),
    );
    final now = DateTime.now();
    final nextPlayback = _PublishedPlayback(
      stage: stage,
      position: position,
      publishedAt: now,
      currentIndex: currentIndex,
      hasPrevious: controller.hasPrevious,
      hasNext: controller.hasNext,
      order: controller.order,
      repeatMode: controller.repeatMode,
    );
    if (!force && !_shouldPublishPlayback(nextPlayback)) return;
    _lastPlayback = nextPlayback;

    playbackState.add(
      PlaybackState(
        controls: _controls(controller),
        systemActions: {
          if (controller.playback.canSeek) MediaAction.seek,
          if (currentItem != null) ...{
            MediaAction.setRepeatMode,
            MediaAction.setShuffleMode,
          },
        },
        androidCompactActionIndices: _compactActionIndices(controller),
        processingState: _processingState(stage),
        playing: stage == TrackPlaybackStage.playing,
        updatePosition: position,
        speed: 1,
        queueIndex: currentIndex,
        repeatMode: switch (controller.repeatMode) {
          PlaybackRepeatMode.off => AudioServiceRepeatMode.none,
          PlaybackRepeatMode.all => AudioServiceRepeatMode.all,
          PlaybackRepeatMode.one => AudioServiceRepeatMode.one,
        },
        shuffleMode: controller.order == PlaybackOrder.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        errorCode:
            stage == TrackPlaybackStage.resolutionError ||
                stage == TrackPlaybackStage.engineError
            ? 1
            : null,
        errorMessage:
            stage == TrackPlaybackStage.resolutionError ||
                stage == TrackPlaybackStage.engineError
            ? 'Playback unavailable'
            : null,
      ),
    );
  }

  bool _shouldPublishPlayback(_PublishedPlayback next) {
    final previous = _lastPlayback;
    if (previous == null || !previous.sameSemantics(next)) return true;
    final elapsed = previous.stage == TrackPlaybackStage.playing
        ? next.publishedAt.difference(previous.publishedAt)
        : Duration.zero;
    final projected = previous.position + elapsed;
    return (next.position - projected).abs() >= const Duration(seconds: 2);
  }
}

List<MediaControl> _controls(QueuePlaybackController controller) => [
  if (controller.hasPrevious) MediaControl.skipToPrevious,
  if (controller.playback.canPause) MediaControl.pause else MediaControl.play,
  MediaControl.stop,
  if (controller.hasNext) MediaControl.skipToNext,
];

List<int> _compactActionIndices(QueuePlaybackController controller) {
  final controls = _controls(controller);
  final indices = <int>[];
  for (
    var index = 0;
    index < controls.length && indices.length < 3;
    index += 1
  ) {
    final action = controls[index].action;
    if (action == MediaAction.skipToPrevious ||
        action == MediaAction.play ||
        action == MediaAction.pause ||
        action == MediaAction.skipToNext) {
      indices.add(index);
    }
  }
  return indices;
}

AudioProcessingState _processingState(TrackPlaybackStage stage) =>
    switch (stage) {
      TrackPlaybackStage.resolving ||
      TrackPlaybackStage.loading => AudioProcessingState.loading,
      TrackPlaybackStage.playing ||
      TrackPlaybackStage.paused => AudioProcessingState.ready,
      TrackPlaybackStage.completed => AudioProcessingState.completed,
      TrackPlaybackStage.resolutionError ||
      TrackPlaybackStage.engineError => AudioProcessingState.error,
      TrackPlaybackStage.idle ||
      TrackPlaybackStage.stopped => AudioProcessingState.idle,
    };

MediaItem _mediaItem(PlaylistTrackSummary track, int index) => MediaItem(
  id: '${track.providerId}:${track.opaqueId}:$index',
  title: track.title,
  artist: track.artistNames.isEmpty ? null : track.artistNames.join(', '),
  album: track.albumTitle,
  duration: track.durationSeconds == null || track.durationSeconds! <= 0
      ? null
      : Duration(seconds: track.durationSeconds!),
  artUri: _safeArtworkUri(track.artworkUri),
);

Uri? _safeArtworkUri(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  return uri;
}

class _PublishedPlayback {
  const _PublishedPlayback({
    required this.stage,
    required this.position,
    required this.publishedAt,
    required this.currentIndex,
    required this.hasPrevious,
    required this.hasNext,
    required this.order,
    required this.repeatMode,
  });

  final TrackPlaybackStage stage;
  final Duration position;
  final DateTime publishedAt;
  final int? currentIndex;
  final bool hasPrevious;
  final bool hasNext;
  final PlaybackOrder order;
  final PlaybackRepeatMode repeatMode;

  bool sameSemantics(_PublishedPlayback other) =>
      stage == other.stage &&
      currentIndex == other.currentIndex &&
      hasPrevious == other.hasPrevious &&
      hasNext == other.hasNext &&
      order == other.order &&
      repeatMode == other.repeatMode;
}
