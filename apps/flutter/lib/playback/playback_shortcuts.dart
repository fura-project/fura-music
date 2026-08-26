import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

class PlaybackShortcuts extends StatelessWidget {
  const PlaybackShortcuts({
    required this.controller,
    required this.child,
    super.key,
  });

  final QueuePlaybackController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
          _activatePlayback,
      const SingleActivator(LogicalKeyboardKey.space, control: true):
          _activatePlayback,
      const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
          _rewindPlayback,
      const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
          _rewindPlayback,
      const SingleActivator(LogicalKeyboardKey.mediaTrackNext):
          _advancePlayback,
      const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
          _advancePlayback,
      const SingleActivator(LogicalKeyboardKey.mediaStop): _stopPlayback,
    },
    child: Focus(autofocus: true, child: child),
  );

  void _activatePlayback() {
    final playback = controller.playback;
    if (playback.canActivate) unawaited(playback.activate());
  }

  void _rewindPlayback() {
    final playback = controller.playback;
    if (!playback.requiresAuthentication && controller.hasPrevious) {
      unawaited(controller.rewind());
    }
  }

  void _advancePlayback() {
    final playback = controller.playback;
    if (!playback.requiresAuthentication && controller.hasNext) {
      unawaited(controller.advance());
    }
  }

  void _stopPlayback() {
    if (controller.current != null) unawaited(controller.playback.stop());
  }
}
