import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

/// Binds the operating-system media session to the app's existing playback
/// owner. Implementations must never resolve media or maintain another queue.
abstract interface class SystemPlaybackBinding {
  void attach(QueuePlaybackController controller);

  void detach(QueuePlaybackController controller);
}

class NoopSystemPlaybackBinding implements SystemPlaybackBinding {
  const NoopSystemPlaybackBinding();

  @override
  void attach(QueuePlaybackController controller) {}

  @override
  void detach(QueuePlaybackController controller) {}
}

class AudioServiceSystemPlaybackBinding implements SystemPlaybackBinding {
  AudioServiceSystemPlaybackBinding._(
    this._handler,
    this._interruptionSubscription,
    this._becomingNoisySubscription,
  );

  final ProjectSystemAudioHandler _handler;
  final StreamSubscription<AudioInterruptionEvent> _interruptionSubscription;
  final StreamSubscription<void> _becomingNoisySubscription;

  @override
  void attach(QueuePlaybackController controller) =>
      _handler.attach(controller);

  @override
  void detach(QueuePlaybackController controller) =>
      _handler.detach(controller);

  Future<void> dispose() async {
    _handler.detachCurrent();
    await _interruptionSubscription.cancel();
    await _becomingNoisySubscription.cancel();
  }
}

/// Initializes the native media session used by Android, iOS, macOS, Linux
/// (MPRIS), and Windows (SMTC). Failure is deliberately non-fatal: foreground
/// playback remains usable if a desktop session bus or platform service is not
/// available.
Future<SystemPlaybackBinding> initializeSystemPlaybackBinding() async {
  final handler = ProjectSystemAudioHandler();
  try {
    await AudioService.init(
      builder: () => handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.axiaobo.flutterustmusic.playback',
        androidNotificationChannelName: 'Music playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );

    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.music());
    final interruptionSubscription = audioSession.interruptionEventStream
        .listen((event) {
          if (event.begin && event.type != AudioInterruptionType.duck) {
            unawaited(handler.pause());
          }
        });
    final becomingNoisySubscription = audioSession.becomingNoisyEventStream
        .listen((_) => unawaited(handler.pause()));
    return AudioServiceSystemPlaybackBinding._(
      handler,
      interruptionSubscription,
      becomingNoisySubscription,
    );
  } on Object {
    return const NoopSystemPlaybackBinding();
  }
}

/// Thin audio_service adapter. The project queue and playback controllers stay
/// authoritative; every system command delegates to them and every system
/// state update is derived from their provider-neutral snapshot.
class ProjectSystemAudioHandler extends BaseAudioHandler {
  QueuePlaybackController? _controller;
  String? _lastQueueSignature;
  String? _lastItemSignature;
  _PublishedPlayback? _lastPlayback;

  void attach(QueuePlaybackController controller) {
    if (identical(_controller, controller)) return;
    detachCurrent();
    _controller = controller;
    controller.addListener(_synchronize);
    _synchronize(force: true);
  }

  void detach(QueuePlaybackController controller) {
    if (identical(_controller, controller)) detachCurrent();
  }

  void detachCurrent() {
    final controller = _controller;
    if (controller != null) controller.removeListener(_synchronize);
    _controller = null;
    _lastQueueSignature = null;
    _lastItemSignature = null;
    _lastPlayback = null;
    queue.add(const []);
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle, playing: false),
    );
  }

  @override
  Future<void> play() async {
    final controller = _controller;
    if (controller == null) return;
    final playback = controller.playback;
    if (playback.canResume) {
      await playback.resume();
    } else if (playback.canActivate) {
      await playback.activate();
    }
  }

  @override
  Future<void> pause() async {
    final playback = _controller?.playback;
    if (playback?.canPause ?? false) await playback!.pause();
  }

  @override
  Future<void> stop() async {
    final playback = _controller?.playback;
    if (playback != null && _controller?.current != null) {
      await playback.stop();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final playback = _controller?.playback;
    if (playback?.canSeek ?? false) {
      await playback!.seekToMs(position.inMilliseconds);
      _synchronize(force: true);
    }
  }

  @override
  Future<void> skipToNext() async {
    final controller = _controller;
    if (controller != null &&
        !controller.playback.requiresAuthentication &&
        controller.hasNext) {
      await controller.advance();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final controller = _controller;
    if (controller != null &&
        !controller.playback.requiresAuthentication &&
        controller.hasPrevious) {
      await controller.rewind();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final controller = _controller;
    if (controller != null &&
        !controller.playback.requiresAuthentication &&
        index >= 0 &&
        index < controller.tracks.length) {
      await controller.select(index);
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.setRepeatMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => PlaybackRepeatMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => PlaybackRepeatMode.all,
      AudioServiceRepeatMode.none => PlaybackRepeatMode.off,
    });
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.setOrder(
      shuffleMode == AudioServiceShuffleMode.none
          ? PlaybackOrder.sequential
          : PlaybackOrder.shuffle,
    );
  }

  void _synchronize({bool force = false}) {
    final controller = _controller;
    if (controller == null) return;

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
        systemActions: controller.playback.canSeek
            ? const {MediaAction.seek}
            : const {},
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
