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
  }) : _clientFactory = clientFactory ?? DBusClient.session;

  final QueuePlaybackController controller;
  final DBusClient Function() _clientFactory;
  final String serviceId;
  DBusClient? _client;
  ProjectMprisPlayer? _player;
  StreamSubscription<ProjectMprisEvent>? _subscription;
  Future<void> _commandTail = Future.value();
  bool _active = false;
  bool _activating = false;
  Future<void>? _activation;
  Future<void>? _deactivation;
  bool _closed = false;
  String? _itemSignature;
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
      identity: 'fura music playback',
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
      _publish(force: true);
      _log('activate', 'success');
    } on Object {
      _active = false;
      controller.removeListener(_synchronize);
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
        if (playback.canResume || playback.canActivate) {
          await controller.playCurrent();
        }
      case ProjectMprisEventType.pause:
        if (playback.canPause) await playback.pause();
      case ProjectMprisEventType.stop:
        await controller.stop();
      case ProjectMprisEventType.next:
        if (!playback.requiresAuthentication && controller.hasNext) {
          await controller.advance();
        }
      case ProjectMprisEventType.previous:
        if (!playback.requiresAuthentication && controller.hasPrevious) {
          await controller.rewind();
        }
      case ProjectMprisEventType.seek:
        if (event.trackId != _player?.trackId) {
          _log('command_seek', 'stale_track');
          return;
        }
        if (playback.canSeek) {
          await playback.seekToMs((event.value! as Duration).inMilliseconds);
          if (_active && playback.canSeek) {
            await _player!.emitSeeked(
              Duration(milliseconds: playback.positionMs),
            );
          }
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

  void _synchronize() => _publish();

  void _publish({bool force = false}) {
    final player = _player;
    if (!_active || player == null) return;
    final current = controller.current;
    // Private in-memory equality only: metadata is never diagnostic output.
    final signature = current == null
        ? null
        : '${current.providerId}\u0000${current.opaqueId}\u0000${controller.currentIndex}\u0000${current.title}\u0000${current.artistNames.join('\u0001')}\u0000${current.albumTitle}\u0000${current.durationSeconds}\u0000${current.artworkUri}';
    if (force || signature != _itemSignature) {
      _itemSignature = signature;
      if (current == null) {
        player.clearMediaItem();
      } else {
        player.updateMediaItem(current, index: controller.currentIndex!);
      }
    }
    final playback = controller.playback;
    final state = ProjectMprisPlaybackState(
      updatePosition: Duration(
        milliseconds: playback.positionMs.clamp(0, 1 << 62),
      ),
      updateTime: DateTime.now(),
      stage: playback.stage,
      repeatMode: controller.repeatMode,
      order: controller.order,
      volume: playback.volume,
      canGoNext: !playback.requiresAuthentication && controller.hasNext,
      canGoPrevious: !playback.requiresAuthentication && controller.hasPrevious,
      canPlay: current != null && (playback.canResume || playback.canActivate),
      canPause: playback.canPause,
      canSeek: playback.canSeek,
    );
    final previous = _lastState;
    if (!force &&
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
              ? state.updateTime.difference(previous.updateTime)
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
