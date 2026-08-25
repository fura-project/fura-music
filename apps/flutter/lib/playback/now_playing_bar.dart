import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({
    required this.controller,
    required this.onSignInAgain,
    super.key,
  });

  final TrackPlaybackController controller;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final track = controller.track;
        if (track == null) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final artist = track.artistNames.isEmpty
            ? 'Unknown artist'
            : track.artistNames.join(' · ');
        final status = _statusCopy(controller);
        final authenticationFailure = _isAuthenticationFailure(
          controller.resolutionFailure,
        );

        return SafeArea(
          top: false,
          child: Material(
            color: colors.surfaceContainer,
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  _StatusIcon(stage: controller.stage),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          key: const ValueKey('now-playing-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$artist · $status',
                          key: const ValueKey('now-playing-status'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                controller.stage ==
                                        TrackPlaybackStage.resolutionError ||
                                    controller.stage ==
                                        TrackPlaybackStage.engineError
                                ? colors.error
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (authenticationFailure)
                    TextButton(
                      key: const ValueKey('now-playing-sign-in-again'),
                      onPressed: onSignInAgain,
                      child: const Text('Sign in again'),
                    )
                  else
                    IconButton(
                      key: const ValueKey('now-playing-primary-action'),
                      tooltip: _primaryTooltip(controller.stage),
                      onPressed: _canActivate(controller.stage)
                          ? () => _activate(controller, track)
                          : null,
                      icon: Icon(_primaryIcon(controller.stage)),
                    ),
                  if (_canStop(controller.stage))
                    IconButton(
                      key: const ValueKey('now-playing-stop'),
                      tooltip: 'Stop',
                      onPressed: () => unawaited(controller.stop()),
                      icon: const Icon(Icons.stop_rounded),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.stage});

  final TrackPlaybackStage stage;

  @override
  Widget build(BuildContext context) {
    if (stage == TrackPlaybackStage.resolving ||
        stage == TrackPlaybackStage.loading) {
      return const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    return Icon(
      stage == TrackPlaybackStage.resolutionError ||
              stage == TrackPlaybackStage.engineError
          ? Icons.error_outline_rounded
          : Icons.graphic_eq_rounded,
      color:
          stage == TrackPlaybackStage.resolutionError ||
              stage == TrackPlaybackStage.engineError
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.primary,
    );
  }
}

void _activate(TrackPlaybackController controller, PlaylistTrackSummary track) {
  switch (controller.stage) {
    case TrackPlaybackStage.playing:
      unawaited(controller.pause());
      return;
    case TrackPlaybackStage.paused:
      unawaited(controller.resume());
      return;
    case TrackPlaybackStage.resolutionError:
      controller.retry();
      return;
    case TrackPlaybackStage.stopped:
    case TrackPlaybackStage.completed:
    case TrackPlaybackStage.engineError:
    case TrackPlaybackStage.idle:
      unawaited(controller.playTrack(track));
      return;
    case TrackPlaybackStage.resolving:
    case TrackPlaybackStage.loading:
      return;
  }
}

bool _canActivate(TrackPlaybackStage stage) =>
    stage != TrackPlaybackStage.resolving &&
    stage != TrackPlaybackStage.loading;

bool _canStop(TrackPlaybackStage stage) => switch (stage) {
  TrackPlaybackStage.resolving ||
  TrackPlaybackStage.loading ||
  TrackPlaybackStage.playing ||
  TrackPlaybackStage.paused => true,
  _ => false,
};

String _primaryTooltip(TrackPlaybackStage stage) => switch (stage) {
  TrackPlaybackStage.playing => 'Pause',
  TrackPlaybackStage.paused => 'Resume',
  TrackPlaybackStage.resolutionError ||
  TrackPlaybackStage.engineError => 'Try again',
  _ => 'Play',
};

IconData _primaryIcon(TrackPlaybackStage stage) => switch (stage) {
  TrackPlaybackStage.playing => Icons.pause_rounded,
  TrackPlaybackStage.resolutionError ||
  TrackPlaybackStage.engineError => Icons.refresh_rounded,
  _ => Icons.play_arrow_rounded,
};

String _statusCopy(TrackPlaybackController controller) =>
    switch (controller.stage) {
      TrackPlaybackStage.idle => 'Ready to play',
      TrackPlaybackStage.resolving => 'Finding a playable source…',
      TrackPlaybackStage.loading => 'Loading audio…',
      TrackPlaybackStage.playing => 'Playing',
      TrackPlaybackStage.paused => 'Paused',
      TrackPlaybackStage.stopped => 'Stopped',
      TrackPlaybackStage.completed => 'Finished',
      TrackPlaybackStage.resolutionError => _resolutionFailureCopy(
        controller.resolutionFailure,
      ),
      TrackPlaybackStage.engineError =>
        'Playback failed. Try this track again.',
    };

String _resolutionFailureCopy(MediaResolutionFailure? failure) =>
    switch (failure) {
      MediaResolutionFailure.authenticationRequired ||
      MediaResolutionFailure.replaced ||
      MediaResolutionFailure.cancelled => 'Sign in to play this track.',
      MediaResolutionFailure.credentialRejected =>
        'Your QQ Music session was rejected and removed.',
      MediaResolutionFailure.credentialRejectedStorageCleanupFailed =>
        'Your session was rejected, but secure storage could not remove it.',
      MediaResolutionFailure.unavailable =>
        'QQ Music did not provide a playable source.',
      MediaResolutionFailure.network => 'Couldn’t reach QQ Music. Try again.',
      MediaResolutionFailure.serviceUnavailable =>
        'QQ Music playback is unavailable right now.',
      MediaResolutionFailure.invalidResponse =>
        'QQ Music returned a source this build could not safely play.',
      MediaResolutionFailure.coreUnavailable =>
        'The music core could not resolve this track.',
      MediaResolutionFailure.alreadyRunning =>
        'Another media request is still running.',
      null => 'This track could not be resolved.',
    };

bool _isAuthenticationFailure(MediaResolutionFailure? failure) =>
    switch (failure) {
      MediaResolutionFailure.authenticationRequired ||
      MediaResolutionFailure.credentialRejected ||
      MediaResolutionFailure.credentialRejectedStorageCleanupFailed ||
      MediaResolutionFailure.replaced ||
      MediaResolutionFailure.cancelled => true,
      _ => false,
    };
