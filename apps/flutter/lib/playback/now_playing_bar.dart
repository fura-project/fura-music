import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_panel.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_panel.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({
    required this.controller,
    required this.onSignInAgain,
    super.key,
  });

  final QueuePlaybackController controller;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final track = controller.current;
        if (track == null) return const SizedBox.shrink();

        final playback = controller.playback;
        final authenticationFailure = _isAuthenticationFailure(
          playback.resolutionFailure,
        );
        final error =
            controller.failure != null ||
            playback.stage == TrackPlaybackStage.resolutionError ||
            playback.stage == TrackPlaybackStage.engineError;

        return SafeArea(
          top: false,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            elevation: 3,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 520;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    narrow ? 8 : 10,
                    12,
                    narrow ? 6 : 10,
                  ),
                  child: narrow
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                _StatusIcon(stage: playback.stage),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _TrackInfo(
                                    track: track,
                                    status: _statusCopy(controller),
                                    error: error,
                                  ),
                                ),
                                if (controller.lyrics != null)
                                  _LyricsButton(
                                    controller: controller,
                                    onSignInAgain: onSignInAgain,
                                  ),
                                _QueueButton(controller: controller),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: _transportControls(
                                controller,
                                track,
                                authenticationFailure,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            _StatusIcon(stage: playback.stage),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TrackInfo(
                                track: track,
                                status: _statusCopy(controller),
                                error: error,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ..._transportControls(
                              controller,
                              track,
                              authenticationFailure,
                            ),
                            if (controller.lyrics != null)
                              _LyricsButton(
                                controller: controller,
                                onSignInAgain: onSignInAgain,
                              ),
                            _QueueButton(controller: controller),
                          ],
                        ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<Widget> _transportControls(
    QueuePlaybackController controller,
    PlaylistTrackSummary track,
    bool authenticationFailure,
  ) {
    final playback = controller.playback;
    return [
      IconButton(
        key: const ValueKey('now-playing-previous'),
        tooltip: 'Previous',
        onPressed: !authenticationFailure && controller.hasPrevious
            ? () => unawaited(controller.rewind())
            : null,
        icon: const Icon(Icons.skip_previous_rounded),
      ),
      if (authenticationFailure)
        TextButton(
          key: const ValueKey('now-playing-sign-in-again'),
          onPressed: onSignInAgain,
          child: const Text('Sign in again'),
        )
      else
        IconButton(
          key: const ValueKey('now-playing-primary-action'),
          tooltip: _primaryTooltip(playback.stage),
          onPressed: _canActivate(playback.stage)
              ? () => _activate(playback, track)
              : null,
          icon: Icon(_primaryIcon(playback.stage)),
        ),
      IconButton(
        key: const ValueKey('now-playing-next'),
        tooltip: 'Next',
        onPressed: !authenticationFailure && controller.hasNext
            ? () => unawaited(controller.advance())
            : null,
        icon: const Icon(Icons.skip_next_rounded),
      ),
      if (_canStop(playback.stage))
        IconButton(
          key: const ValueKey('now-playing-stop'),
          tooltip: 'Stop',
          onPressed: () => unawaited(playback.stop()),
          icon: const Icon(Icons.stop_rounded),
        ),
    ];
  }
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({
    required this.track,
    required this.status,
    required this.error,
  });

  final PlaylistTrackSummary track;
  final String status;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artist = track.artistNames.isEmpty
        ? 'Unknown artist'
        : track.artistNames.join(' · ');
    return Column(
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
            color: error
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _QueueButton extends StatelessWidget {
  const _QueueButton({required this.controller});

  final QueuePlaybackController controller;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('now-playing-show-queue'),
    tooltip: 'Show queue',
    onPressed: () => unawaited(showPlaybackQueue(context, controller)),
    icon: const Icon(Icons.queue_music_rounded),
  );
}

class _LyricsButton extends StatelessWidget {
  const _LyricsButton({required this.controller, required this.onSignInAgain});

  final QueuePlaybackController controller;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('now-playing-show-lyrics'),
    tooltip: 'Show lyrics',
    onPressed: () => showLyrics(context, controller.lyrics!, onSignInAgain),
    icon: const Icon(Icons.lyrics_outlined),
  );
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

String _statusCopy(QueuePlaybackController controller) {
  final queueFailure = controller.failure;
  if (queueFailure != null) return _queueFailureCopy(queueFailure);
  final playback = controller.playback;
  return switch (playback.stage) {
    TrackPlaybackStage.idle => 'Ready to play',
    TrackPlaybackStage.resolving => 'Finding a playable source…',
    TrackPlaybackStage.loading => 'Loading audio…',
    TrackPlaybackStage.playing => 'Playing',
    TrackPlaybackStage.paused => 'Paused',
    TrackPlaybackStage.stopped => 'Stopped',
    TrackPlaybackStage.completed => 'Finished',
    TrackPlaybackStage.resolutionError => _resolutionFailureCopy(
      playback.resolutionFailure,
    ),
    TrackPlaybackStage.engineError => 'Playback failed. Try this track again.',
  };
}

String _queueFailureCopy(PlaybackQueueFailure failure) => switch (failure) {
  PlaybackQueueFailure.invalidTrack => 'A queue track was invalid.',
  PlaybackQueueFailure.invalidPosition =>
    'That queue position is no longer available.',
  PlaybackQueueFailure.coreUnavailable =>
    'The music core could not update the queue.',
  PlaybackQueueFailure.invalidResponse =>
    'The music core returned an invalid queue state.',
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
