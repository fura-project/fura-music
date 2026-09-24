import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_media_session/flutter_media_session.dart' as fms;
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/system_media_edge.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

abstract interface class FlutterMediaSessionDriver {
  Stream<fms.MediaAction> get actions;

  Future<void> setAutoHandleInterruptions(bool enabled);
  Future<void> setBackgroundKeepAlive(bool enabled);
  Future<void> activate();
  Future<void> deactivate();
  Future<void> updateMetadata(fms.MediaMetadata metadata);
  Future<void> updatePlaybackState(fms.PlaybackState state);
  Future<void> updateAvailableActions(Set<fms.MediaAction> actions);
}

class PlatformFlutterMediaSessionDriver implements FlutterMediaSessionDriver {
  PlatformFlutterMediaSessionDriver()
    : _session = fms.FlutterMediaSession(),
      _platform = fms.FlutterMediaSessionPlatform.instance;

  final fms.FlutterMediaSession _session;
  final fms.FlutterMediaSessionPlatform _platform;

  @override
  Stream<fms.MediaAction> get actions => _platform.onMediaAction;

  @override
  Future<void> setAutoHandleInterruptions(bool enabled) =>
      _session.setAutoHandleInterruptions(enabled);

  @override
  Future<void> setBackgroundKeepAlive(bool enabled) =>
      _session.setBackgroundKeepAlive(enabled);

  @override
  Future<void> activate() => _session.activate();

  @override
  Future<void> deactivate() => _session.deactivate();

  @override
  Future<void> updateMetadata(fms.MediaMetadata metadata) =>
      _platform.updateMetadata(metadata);

  @override
  Future<void> updatePlaybackState(fms.PlaybackState state) =>
      _platform.updatePlaybackState(state);

  @override
  Future<void> updateAvailableActions(Set<fms.MediaAction> actions) =>
      _platform.updateAvailableActions(actions);
}

/// Fura-owned flutter_media_session adapter.
///
/// Unlike the package's sample player adapters, this adapter never calls a
/// native player's next/previous methods. It publishes the app-lifetime Queue
/// owner and delegates every system command back to that same owner.
class FuraMediaSessionAdapter implements SystemMediaEdge {
  FuraMediaSessionAdapter({
    required QueuePlaybackController controller,
    FlutterMediaSessionDriver? driver,
    TargetPlatform? platform,
  }) : // Keep the public label `controller` while storing it privately.
       // ignore: prefer_initializing_formals
       _controller = controller,
       _driver = driver ?? PlatformFlutterMediaSessionDriver(),
       _platform = platform ?? defaultTargetPlatform;

  final QueuePlaybackController _controller;
  final FlutterMediaSessionDriver _driver;
  final TargetPlatform _platform;
  StreamSubscription<fms.MediaAction>? _actionSubscription;
  Future<void> _commandTail = Future<void>.value();
  Future<void> _synchronizationTail = Future<void>.value();
  String? _metadataSignature;
  String? _actionsSignature;
  _PublishedFlutterMediaState? _lastPlayback;
  bool _active = false;

  QueuePlaybackController get controller => _controller;

  @override
  bool get isActive => _active;

  static bool supportsPlatform(TargetPlatform platform) => switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.windows ||
    TargetPlatform.macOS => true,
    // 3.0.5 unconditionally owns AVAudioSession on iOS and exposes no switch
    // to disable it; Linux has no plugin implementation.
    TargetPlatform.iOS ||
    TargetPlatform.linux ||
    TargetPlatform.fuchsia => false,
  };

  @override
  Future<void> activate() async {
    if (_active) throw StateError('System media edge is already active.');
    if (!supportsPlatform(_platform)) {
      throw UnsupportedError(
        'flutter_media_session is not an admissible Fura system edge on '
        '${_platform.name}.',
      );
    }

    _active = true;
    _controller.addListener(_scheduleSynchronization);
    _actionSubscription = _driver.actions.listen(
      _onAction,
      onError: (Object _) {
        // A platform command-stream failure must not affect Queue or playback.
      },
    );
    var androidForegroundStartupPrimed = false;
    try {
      // Android is the only supported Fura candidate target where 3.0.5 has
      // an optional focus owner. Disable it before creating the Media3 service.
      if (_platform == TargetPlatform.android) {
        await _driver.setAutoHandleInterruptions(false);
        // flutter_media_session 3.0.5 starts its MediaSessionService with
        // startForegroundService(), even while the initial Queue state is
        // idle. Prime its public keep-alive switch before activation so
        // Media3 posts the required foreground notification inside Android's
        // deadline, then immediately return to the Queue-owned playback state.
        // Without this handshake Android reports a foreground-service ANR.
        await _driver.setBackgroundKeepAlive(true);
        androidForegroundStartupPrimed = true;
      }
      await _driver.activate();
      if (androidForegroundStartupPrimed) {
        await _driver.setBackgroundKeepAlive(false);
        androidForegroundStartupPrimed = false;
      }
      await _enqueueSynchronization(force: true, exposeFailure: true);
    } on Object {
      if (androidForegroundStartupPrimed) {
        try {
          await _driver.setBackgroundKeepAlive(false);
        } on Object {
          // The original activation failure remains the useful diagnostic.
        }
      }
      await _detach(deactivatePlatform: true);
      rethrow;
    }
  }

  @override
  Future<void> deactivate() => _detach(deactivatePlatform: true);

  Future<void> _detach({required bool deactivatePlatform}) async {
    if (!_active && _actionSubscription == null) return;
    _active = false;
    _controller.removeListener(_scheduleSynchronization);
    await _synchronizationTail;
    await _actionSubscription?.cancel();
    _actionSubscription = null;
    _metadataSignature = null;
    _actionsSignature = null;
    _lastPlayback = null;
    if (deactivatePlatform) {
      try {
        await _driver.deactivate();
      } on Object {
        // Deactivation is terminal and must not replace the Queue owner.
      }
    }
  }

  void _onAction(fms.MediaAction action) {
    if (!_active) return;
    _enqueue(() async {
      if (!_active) return;
      switch (action.name) {
        case 'play':
          final playback = _controller.playback;
          if (playback.canResume) {
            await _controller.playCurrent();
          } else if (playback.canActivate) {
            await _controller.playCurrent();
          }
        case 'pause':
          if (_controller.playback.canPause) {
            await _controller.playback.pause();
          }
        case 'stop':
          if (_controller.current != null) {
            await _controller.stop();
          }
        case 'skipToNext':
          if (!_controller.playback.requiresAuthentication &&
              _controller.hasNext) {
            await _controller.advance();
          }
        case 'skipToPrevious':
          if (!_controller.playback.requiresAuthentication &&
              _controller.hasPrevious) {
            await _controller.rewind();
          }
        case 'seekTo':
          final position = action.seekPosition;
          if (position != null && _controller.playback.canSeek) {
            await _controller.playback.seekToMs(position.inMilliseconds);
          }
        case 'shuffle':
          await _controller.setOrder(
            _controller.order == PlaybackOrder.shuffle
                ? PlaybackOrder.sequential
                : PlaybackOrder.shuffle,
          );
        case 'repeat':
          await _controller.setRepeatMode(switch (_controller.repeatMode) {
            PlaybackRepeatMode.off => PlaybackRepeatMode.all,
            PlaybackRepeatMode.all => PlaybackRepeatMode.one,
            PlaybackRepeatMode.one => PlaybackRepeatMode.off,
          });
        default:
          // Rewind/fast-forward and package-specific custom actions are not
          // advertised by Fura and therefore remain ignored.
          break;
      }
    });
  }

  void _enqueue(Future<void> Function() command) {
    _commandTail = _commandTail
        .then((_) => command())
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }

  void _scheduleSynchronization() {
    unawaited(_enqueueSynchronization());
  }

  Future<void> _enqueueSynchronization({
    bool force = false,
    bool exposeFailure = false,
  }) {
    final result = _synchronizationTail.then((_) async {
      if (_active) await _synchronize(force: force);
    });
    _synchronizationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return exposeFailure ? result : _synchronizationTail;
  }

  Future<void> _synchronize({bool force = false}) async {
    if (!_active) return;
    final current = _controller.current;
    final metadataSignature = current == null
        ? 'none'
        : '${current.providerId}\u0000${current.opaqueId}\u0000'
              '${current.title}\u0000${current.artistNames.join('\u0001')}\u0000'
              '${current.albumTitle ?? ''}\u0000${current.durationSeconds ?? -1}\u0000'
              '${current.artworkUri ?? ''}';
    if (force || metadataSignature != _metadataSignature) {
      _metadataSignature = metadataSignature;
      await _driver.updateMetadata(_metadata(current));
    }

    final actions = _availableActions();
    final actionsSignature = actions.map((action) => action.name).toList()
      ..sort();
    final joinedActions = actionsSignature.join(',');
    if (force || joinedActions != _actionsSignature) {
      _actionsSignature = joinedActions;
      await _driver.updateAvailableActions(actions);
    }

    final next = _playbackState();
    if (force || _shouldPublish(next)) {
      _lastPlayback = next;
      await _driver.updatePlaybackState(next.state);
    }
  }

  fms.MediaMetadata _metadata(PlaylistTrackSummary? track) => fms.MediaMetadata(
    title: track?.title,
    artist: track == null || track.artistNames.isEmpty
        ? null
        : track.artistNames.join(', '),
    album: track?.albumTitle,
    artworkUri: _safeArtworkUri(track?.artworkUri),
    duration: track?.durationSeconds == null || track!.durationSeconds! <= 0
        ? null
        : Duration(seconds: track.durationSeconds!),
  );

  Set<fms.MediaAction> _availableActions() => {
    if (_controller.playback.canResume || _controller.playback.canActivate)
      fms.MediaAction.play,
    if (_controller.playback.canPause) fms.MediaAction.pause,
    if (_controller.current != null) fms.MediaAction.stop,
    if (_controller.hasPrevious) fms.MediaAction.skipToPrevious,
    if (_controller.hasNext) fms.MediaAction.skipToNext,
    if (_controller.playback.canSeek) fms.MediaAction.seekTo,
    if (_controller.current != null) ...{
      fms.MediaAction.repeat,
      fms.MediaAction.shuffle,
    },
  };

  _PublishedFlutterMediaState _playbackState() {
    final stage = _controller.playback.stage;
    final state = fms.PlaybackState(
      status: switch (stage) {
        TrackPlaybackStage.resolving ||
        TrackPlaybackStage.loading => fms.PlaybackStatus.buffering,
        TrackPlaybackStage.playing => fms.PlaybackStatus.playing,
        TrackPlaybackStage.paused => fms.PlaybackStatus.paused,
        TrackPlaybackStage.completed => fms.PlaybackStatus.ended,
        TrackPlaybackStage.resolutionError ||
        TrackPlaybackStage.engineError => fms.PlaybackStatus.error,
        TrackPlaybackStage.idle ||
        TrackPlaybackStage.stopped => fms.PlaybackStatus.idle,
      },
      position: Duration(
        milliseconds: _controller.playback.positionMs.clamp(0, 1 << 62),
      ),
      repeatMode: switch (_controller.repeatMode) {
        PlaybackRepeatMode.off => fms.MediaRepeatMode.none,
        PlaybackRepeatMode.all => fms.MediaRepeatMode.all,
        PlaybackRepeatMode.one => fms.MediaRepeatMode.one,
      },
      shuffleModeEnabled: _controller.order == PlaybackOrder.shuffle,
    );
    return _PublishedFlutterMediaState(
      state: state,
      currentIndex: _controller.currentIndex,
      hasPrevious: _controller.hasPrevious,
      hasNext: _controller.hasNext,
      publishedAt: DateTime.now(),
    );
  }

  bool _shouldPublish(_PublishedFlutterMediaState next) {
    final previous = _lastPlayback;
    if (previous == null || !previous.sameSemantics(next)) return true;
    final elapsed = previous.state.status == fms.PlaybackStatus.playing
        ? next.publishedAt.difference(previous.publishedAt)
        : Duration.zero;
    final projected = previous.state.position + elapsed;
    return (next.state.position - projected).abs() >=
        const Duration(seconds: 2);
  }
}

String? _safeArtworkUri(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  return uri.toString();
}

class _PublishedFlutterMediaState {
  const _PublishedFlutterMediaState({
    required this.state,
    required this.currentIndex,
    required this.hasPrevious,
    required this.hasNext,
    required this.publishedAt,
  });

  final fms.PlaybackState state;
  final int? currentIndex;
  final bool hasPrevious;
  final bool hasNext;
  final DateTime publishedAt;

  bool sameSemantics(_PublishedFlutterMediaState other) =>
      state.status == other.state.status &&
      state.repeatMode == other.state.repeatMode &&
      state.shuffleModeEnabled == other.state.shuffleModeEnabled &&
      currentIndex == other.currentIndex &&
      hasPrevious == other.hasPrevious &&
      hasNext == other.hasNext;
}
