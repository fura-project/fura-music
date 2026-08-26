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
        final authenticationFailure = playback.requiresAuthentication;
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
                  padding: EdgeInsets.fromLTRB(16, narrow ? 8 : 10, 12, 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (narrow)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                _NowPlayingArtwork(
                                  track: track,
                                  stage: playback.stage,
                                  dimension: 44,
                                ),
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
                                _VolumeButton(controller: playback),
                                _QueueButton(controller: controller),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: _transportControls(
                                controller,
                                authenticationFailure,
                              ),
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            _NowPlayingArtwork(
                              track: track,
                              stage: playback.stage,
                              dimension: 52,
                            ),
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
                              authenticationFailure,
                            ),
                            if (controller.lyrics != null)
                              _LyricsButton(
                                controller: controller,
                                onSignInAgain: onSignInAgain,
                              ),
                            _VolumeButton(controller: playback),
                            _QueueButton(controller: controller),
                          ],
                        ),
                      _PlaybackProgress(controller: playback, track: track),
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
          onPressed: playback.canActivate
              ? () => unawaited(playback.activate())
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

class _PlaybackProgress extends StatefulWidget {
  const _PlaybackProgress({required this.controller, required this.track});

  final TrackPlaybackController controller;
  final PlaylistTrackSummary track;

  @override
  State<_PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<_PlaybackProgress> {
  double? _previewMs;
  int _seekAttempt = 0;

  @override
  void didUpdateWidget(covariant _PlaybackProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.providerId != widget.track.providerId ||
        oldWidget.track.opaqueId != widget.track.opaqueId) {
      _seekAttempt += 1;
      _previewMs = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = widget.controller.durationMs;
    if (durationMs == null) return const SizedBox.shrink();
    final rawPosition = _previewMs ?? widget.controller.positionMs.toDouble();
    final position = rawPosition.clamp(0, durationMs.toDouble()).toDouble();
    final colors = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            _playbackTime(position.round()),
            key: const ValueKey('now-playing-position'),
            style: textStyle,
            textAlign: TextAlign.end,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              key: const ValueKey('now-playing-progress'),
              value: position,
              max: durationMs.toDouble(),
              semanticFormatterCallback: (value) =>
                  '${_playbackTime(value.round())} of '
                  '${_playbackTime(durationMs)}',
              onChangeStart: widget.controller.canSeek
                  ? (value) => setState(() => _previewMs = value)
                  : null,
              onChanged: widget.controller.canSeek
                  ? (value) => setState(() => _previewMs = value)
                  : null,
              onChangeEnd: widget.controller.canSeek ? _commitSeek : null,
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            _playbackTime(durationMs),
            key: const ValueKey('now-playing-duration'),
            style: textStyle,
          ),
        ),
      ],
    );
  }

  void _commitSeek(double value) {
    final attempt = ++_seekAttempt;
    setState(() => _previewMs = value);
    unawaited(() async {
      await widget.controller.seekToMs(value.round());
      if (!mounted || attempt != _seekAttempt) return;
      setState(() => _previewMs = null);
    }());
  }
}

String _playbackTime(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
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

class _VolumeButton extends StatelessWidget {
  const _VolumeButton({required this.controller});

  final TrackPlaybackController controller;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('now-playing-volume'),
    tooltip: 'Volume',
    onPressed: () => unawaited(_showVolumeControl(context, controller)),
    icon: Icon(
      controller.volume == 0
          ? Icons.volume_off_rounded
          : controller.volume < 0.5
          ? Icons.volume_down_rounded
          : Icons.volume_up_rounded,
    ),
  );
}

Future<void> _showVolumeControl(
  BuildContext context,
  TrackPlaybackController controller,
) async {
  if (MediaQuery.sizeOf(context).width < 600) {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: _VolumePanel(controller: controller),
        ),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Volume'),
      content: SizedBox(
        width: 320,
        child: _VolumePanel(controller: controller),
      ),
    ),
  );
}

class _VolumePanel extends StatefulWidget {
  const _VolumePanel({required this.controller});

  final TrackPlaybackController controller;

  @override
  State<_VolumePanel> createState() => _VolumePanelState();
}

class _VolumePanelState extends State<_VolumePanel> {
  double? _preview;
  int _attempt = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final value = (_preview ?? widget.controller.volume)
          .clamp(0, 1)
          .toDouble();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                value == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_down_rounded,
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('volume-slider'),
                  value: value,
                  semanticFormatterCallback: (value) =>
                      '${(value * 100).round()} percent',
                  onChangeStart: (value) => setState(() => _preview = value),
                  onChanged: (value) => setState(() => _preview = value),
                  onChangeEnd: _commit,
                ),
              ),
              Icon(
                value < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
              ),
            ],
          ),
          Text(
            '${(value * 100).round()}%',
            key: const ValueKey('volume-percent'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      );
    },
  );

  void _commit(double value) {
    final attempt = ++_attempt;
    setState(() => _preview = value);
    unawaited(() async {
      await widget.controller.setVolume(value);
      if (!mounted || attempt != _attempt) return;
      setState(() => _preview = null);
    }());
  }
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

class _NowPlayingArtwork extends StatelessWidget {
  const _NowPlayingArtwork({
    required this.track,
    required this.stage,
    required this.dimension,
  });

  final PlaylistTrackSummary track;
  final TrackPlaybackStage stage;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final artworkUri = track.artworkUri;
    final busy =
        stage == TrackPlaybackStage.resolving ||
        stage == TrackPlaybackStage.loading;
    final error =
        stage == TrackPlaybackStage.resolutionError ||
        stage == TrackPlaybackStage.engineError;
    return Semantics(
      container: true,
      image: true,
      label: 'Artwork for ${track.title}',
      child: SizedBox.square(
        key: const ValueKey('now-playing-artwork'),
        dimension: dimension,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              artworkUri == null
                  ? const _NowPlayingArtworkPlaceholder()
                  : Image.network(
                      artworkUri,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      gaplessPlayback: true,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : const _NowPlayingArtworkPlaceholder(),
                      errorBuilder: (context, error, stackTrace) =>
                          const _NowPlayingArtworkPlaceholder(),
                    ),
              if (busy || error)
                ColoredBox(
                  key: const ValueKey('now-playing-artwork-state'),
                  color: Colors.black.withValues(alpha: 0.44),
                  child: Center(
                    child: busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            Icons.error_outline_rounded,
                            color: Theme.of(context).colorScheme.errorContainer,
                            size: 24,
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlayingArtworkPlaceholder extends StatelessWidget {
  const _NowPlayingArtworkPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('now-playing-artwork-placeholder'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      child: Icon(
        Icons.album_rounded,
        color: colors.onPrimaryContainer,
        size: 28,
      ),
    );
  }
}

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
