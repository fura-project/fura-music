import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/playback/linux_mpris_player.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/system_media_edge.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

/// Linux system edge directly projecting the one existing app-lifetime owner.
/// No AudioServicePlatform, AudioHandler, extra Flutter engine, source or Queue.
class FuraMprisSystemMediaEdge implements SystemMediaEdge {
  FuraMprisSystemMediaEdge({
    required this.controller,
    DBusClient Function()? clientFactory,
    this.serviceId = 'com.fura.flutterustmusic.playback',
    this.onRaise,
  }) : _clientFactory = clientFactory ?? DBusClient.session;

  final QueuePlaybackController controller;
  final DBusClient Function() _clientFactory;
  final String serviceId;
  final Future<void> Function()? onRaise;
  final _clock = Stopwatch()..start();
  DBusClient? _client;
  ProjectMprisPlayer? _player;
  StreamSubscription<ProjectMprisEvent>? _subscription;
  Future<void> _commandTail = Future.value();
  bool _active = false;
  bool _activating = false;
  Future<void>? _activation;
  Future<void>? _deactivation;
  bool _closed = false;
  int? _publishedSelection;
  ProjectMprisPlaybackState? _lastState;

  @override
  bool get isActive => _active;
  String get serviceName => projectMprisServiceName(serviceId);

  @override
  Future<void> activate() {
    if (_active || _activating || _closed) {
      throw StateError('MPRIS edge is not available for activation.');
    }
    _activating = true;
    return _activation = _activate().whenComplete(() {
      _activating = false;
      _activation = null;
    });
  }

  Future<void> _activate() async {
    final player = _player = ProjectMprisPlayer(
      identity: 'fura music',
      now: () => _clock.elapsed,
      sourceGeneration: () => controller.playback.sourceGeneration,
      onRaise: onRaise,
    );
    try {
      final client = _client = _clientFactory();
      await client.registerObject(player);
      final reply = await client.requestName(
        serviceName,
        flags: const {DBusRequestNameFlag.doNotQueue},
      );
      if (reply != DBusRequestNameReply.primaryOwner &&
          reply != DBusRequestNameReply.alreadyOwner) {
        throw StateError('MPRIS name is already owned.');
      }
      if (_closed) throw StateError('MPRIS activation was cancelled.');
      _active = true;
      _subscription = player.events.listen(_scheduleCommand);
      controller.addListener(_synchronize);
      controller.playback.positionDiscontinuity.addListener(
        _positionDiscontinuity,
      );
      _publish(force: true);
      _log('activate', 'success');
    } on Object {
      _active = false;
      controller.removeListener(_synchronize);
      controller.playback.positionDiscontinuity.removeListener(
        _positionDiscontinuity,
      );
      await _subscription?.cancel();
      try {
        await _client?.close();
      } finally {
        await player.close();
        _client = null;
        _player = null;
      }
      _log('activate', 'failed');
      rethrow;
    }
  }

  void _scheduleCommand(ProjectMprisEvent event) {
    if (!_active) return;
    _commandTail = _commandTail.then((_) async {
      if (!_active) return;
      try {
        await _dispatch(event);
        if (_active) _publish(force: true);
      } on Object {
        // Never print DBus/media causes; the owner keeps its typed failure.
        _log('command', 'failed');
        if (_active) _publish(force: true);
      }
    });
  }

  Future<void> _dispatch(ProjectMprisEvent event) async {
    final playback = controller.playback;
    switch (event.type) {
      case ProjectMprisEventType.play:
        if (_canPlayCurrent) await controller.playCurrent();
      case ProjectMprisEventType.playPause:
        if (playback.canPause) {
          await playback.pause();
        } else if (_canPlayCurrent) {
          await controller.playCurrent();
        }
      case ProjectMprisEventType.pause:
        if (playback.canPause) await playback.pause();
      case ProjectMprisEventType.stop:
        await controller.stop();
      case ProjectMprisEventType.next:
        if (!playback.requiresAuthentication && controller.hasNext) {
          await controller.advance(preserveInactiveState: true);
        }
      case ProjectMprisEventType.previous:
        if (!playback.requiresAuthentication && controller.hasPrevious) {
          await controller.rewind(preserveInactiveState: true);
        }
      case ProjectMprisEventType.seek:
      case ProjectMprisEventType.seekRelative:
        if (event.trackId != _player?.trackId ||
            event.sourceGeneration != playback.sourceGeneration) {
          _log('command_seek', 'stale_track');
          return;
        }
        if (!playback.canSeek) return;
        final requested = event.value! as Duration;
        if (event.type == ProjectMprisEventType.seekRelative) {
          final target = _player!.position + requested;
          if (target > Duration(milliseconds: playback.durationMs!)) {
            if (controller.hasNext) {
              await controller.advance(preserveInactiveState: true);
            }
            return;
          }
          await playback.seekToMs(target.inMilliseconds);
        } else {
          await playback.seekToMs(requested.inMilliseconds);
        }
      case ProjectMprisEventType.repeat:
        await controller.setRepeatMode(switch (event.value! as String) {
          'Track' => PlaybackRepeatMode.one,
          'Playlist' => PlaybackRepeatMode.all,
          _ => PlaybackRepeatMode.off,
        });
      case ProjectMprisEventType.shuffle:
        await controller.setOrder(
          event.value! as bool
              ? PlaybackOrder.shuffle
              : PlaybackOrder.sequential,
        );
      case ProjectMprisEventType.volume:
        await playback.setVolume((event.value! as double).clamp(0, 1));
    }
    _log('command_${event.type.name}', 'settled');
  }

  bool get _canPlayCurrent {
    final current = controller.current;
    if (current == null) return false;
    final playback = controller.playback;
    final source = playback.track;
    return !playback.requiresAuthentication ||
        source?.providerId != current.providerId ||
        source?.opaqueId != current.opaqueId;
  }

  void _synchronize() => _publish();

  void _positionDiscontinuity() {
    final player = _player;
    if (!_active || player == null || controller.current == null) return;
    _publish(force: true);
    unawaited(
      player
          .emitSeeked(Duration(milliseconds: controller.playback.positionMs))
          .catchError((Object _) => _log('seeked', 'failed')),
    );
  }

  void _publish({bool force = false}) {
    final player = _player;
    if (!_active || player == null) return;
    final current = controller.current;
    final selection = controller.currentSelectionRevision;
    final selectionChanged = _publishedSelection != selection;
    if (selectionChanged) {
      _publishedSelection = selection;
      if (current == null) {
        player.clearMediaItem();
      } else {
        player.updateMediaItem(current, selection: selection);
      }
    }
    final playback = controller.playback;
    final playable = _canPlayCurrent;
    final state = ProjectMprisPlaybackState(
      updatePosition: Duration(
        milliseconds: playback.positionMs.clamp(0, 1 << 62),
      ),
      updateTime: _clock.elapsed,
      stage: playback.stage,
      repeatMode: controller.repeatMode,
      order: controller.order,
      volume: playback.volume,
      canGoNext: !playback.requiresAuthentication && controller.hasNext,
      canGoPrevious: !playback.requiresAuthentication && controller.hasPrevious,
      canPlay: playable,
      canPause: playable && (playback.canPause || playback.canResume),
      canSeek: playback.canSeek,
    );
    final previous = _lastState;
    if (!force &&
        !selectionChanged &&
        previous != null &&
        previous.stage == state.stage &&
        previous.repeatMode == state.repeatMode &&
        previous.order == state.order &&
        previous.volume == state.volume &&
        previous.canGoNext == state.canGoNext &&
        previous.canGoPrevious == state.canGoPrevious &&
        previous.canPlay == state.canPlay &&
        previous.canPause == state.canPause &&
        previous.canSeek == state.canSeek) {
      final projected =
          previous.updatePosition +
          (previous.stage == TrackPlaybackStage.playing
              ? state.updateTime - previous.updateTime
              : Duration.zero);
      if ((state.updatePosition - projected).abs() <
          const Duration(seconds: 2)) {
        return;
      }
    }
    _lastState = state;
    player.updatePlaybackState(state);
  }

  @override
  Future<void> deactivate() => _deactivation ??= _deactivate();

  Future<void> _deactivate() async {
    _closed = true;
    _active = false;
    await _activation?.then<void>((_) {}, onError: (Object _) {});
    controller.removeListener(_synchronize);
    controller.playback.positionDiscontinuity.removeListener(
      _positionDiscontinuity,
    );
    await _subscription?.cancel();
    // Revoke queued commands. An already delegated operation belongs to the
    // controller, not this projection; waiting for (e.g.) a media resolution
    // here would make host disposal depend on network settlement. Its late
    // continuation is observed but cannot publish into a closed DBus edge.
    final client = _client;
    final player = _player;
    try {
      if (client != null) {
        try {
          if (player != null) await client.unregisterObject(player);
        } finally {
          await client.close(); // Also releases the well-known name.
        }
      }
    } finally {
      if (player != null) await player.close();
      _client = null;
      _player = null;
    }
    _log('deactivate', 'success');
  }
}

void _log(String phase, String outcome) =>
    debugPrint('FURA_DIAGNOSTIC fura_mpris phase=$phase outcome=$outcome');
