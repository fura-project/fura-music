import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/music_video/track_music_video_controller.dart';
import 'package:flutterustmusic/music_video/track_music_video_engine.dart';
import 'package:flutterustmusic/music_video/track_music_video_gateway.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

Future<void> showTrackMusicVideoSurface({
  required BuildContext context,
  required TrackMusicVideoGateway gateway,
  required TrackMusicVideoEngine engine,
  required PlaylistTrackSummary track,
  required QueuePlaybackController playbackController,
}) async {
  final compact = MediaQuery.sizeOf(context).width < 600;
  Widget content(BuildContext modalContext) => PlaybackShortcuts(
    controller: playbackController,
    child: TrackMusicVideoPanel(
      gateway: gateway,
      engine: engine,
      track: track,
      playbackController: playbackController,
      onClose: () => Navigator.of(modalContext).pop(),
    ),
  );

  if (compact) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (modalContext) => SizedBox(
        key: const ValueKey('track-music-video-compact-surface'),
        height: MediaQuery.sizeOf(modalContext).height * 0.9,
        child: content(modalContext),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (modalContext) => Dialog(
      key: const ValueKey('track-music-video-wide-surface'),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(960, MediaQuery.sizeOf(modalContext).width - 64),
        height: math.min(760, MediaQuery.sizeOf(modalContext).height - 64),
        child: content(modalContext),
      ),
    ),
  );
}

class TrackMusicVideoPanel extends StatefulWidget {
  const TrackMusicVideoPanel({
    required this.gateway,
    required this.engine,
    required this.track,
    required this.playbackController,
    required this.onClose,
    super.key,
  });

  final TrackMusicVideoGateway gateway;
  final TrackMusicVideoEngine engine;
  final PlaylistTrackSummary track;
  final QueuePlaybackController playbackController;
  final VoidCallback onClose;

  @override
  State<TrackMusicVideoPanel> createState() => _TrackMusicVideoPanelState();
}

class _TrackMusicVideoPanelState extends State<TrackMusicVideoPanel> {
  late final TrackMusicVideoController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TrackMusicVideoController(
      gateway: widget.gateway,
      engine: widget.engine,
      musicController: widget.playbackController,
      track: widget.track,
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          MusicSpacing.page,
          MusicSpacing.itemGap,
          MusicSpacing.itemGap,
          MusicSpacing.itemGap,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Music video',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    widget.track.title,
                    key: const ValueKey('track-music-video-track-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('track-music-video-close'),
              tooltip: 'Close music video',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
      const Divider(),
      Expanded(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => AnimatedSwitcher(
            duration: MusicMotion.stateChange,
            child: _body(context),
          ),
        ),
      ),
    ],
  );

  Widget _body(BuildContext context) => switch (_controller.stage) {
    TrackMusicVideoStage.loading => const MusicLoadingPanel(
      key: ValueKey('track-music-video-loading'),
      label: 'Loading music video',
    ),
    TrackMusicVideoStage.unavailable => const MusicContentStatePanel(
      key: ValueKey('track-music-video-unavailable'),
      icon: Icons.music_video_outlined,
      title: 'No music video for this Track',
      detail: 'QQ Music did not associate an MV with this Track.',
    ),
    TrackMusicVideoStage.error => MusicContentStatePanel(
      key: const ValueKey('track-music-video-error'),
      icon: Icons.video_file_outlined,
      title: _controller.failure == TrackMusicVideoFailure.sourceUnavailable
          ? 'Music video unavailable'
          : 'Couldn’t play music video',
      detail: _failureCopy(_controller.failure),
      action: _controller.canRetry
          ? FilledButton.tonal(
              key: const ValueKey('track-music-video-retry'),
              onPressed: _controller.retry,
              child: const Text('Try again'),
            )
          : null,
      liveRegion: true,
    ),
    TrackMusicVideoStage.interrupted => const MusicContentStatePanel(
      key: ValueKey('track-music-video-interrupted'),
      icon: Icons.stop_circle_outlined,
      title: 'Music video stopped',
      detail: 'Music playback or the current Queue Track changed.',
      liveRegion: true,
    ),
    TrackMusicVideoStage.playing ||
    TrackMusicVideoStage.paused ||
    TrackMusicVideoStage.completed => _TrackMusicVideoContent(
      controller: _controller,
    ),
  };
}

class _TrackMusicVideoContent extends StatelessWidget {
  const _TrackMusicVideoContent({required this.controller});

  final TrackMusicVideoController controller;

  @override
  Widget build(BuildContext context) {
    final video = controller.musicVideo!;
    final session = controller.session!;
    final artists = video.artistNames.join(' · ');
    return ListView(
      key: const ValueKey('track-music-video-content'),
      padding: const EdgeInsetsDirectional.fromSTEB(
        MusicSpacing.pageCompact,
        MusicSpacing.contentGap,
        MusicSpacing.pageCompact,
        MusicSpacing.page,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ClipRRect(
              borderRadius: MusicRadii.content,
              child: ColoredBox(
                color: Colors.black,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: session.buildVideo(
                    key: const ValueKey('track-music-video-player'),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: MusicSpacing.contentGap),
        Text(
          video.title,
          key: const ValueKey('track-music-video-title'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          artists,
          key: const ValueKey('track-music-video-artists'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: MusicSpacing.itemGap),
        _TrackMusicVideoControls(controller: controller),
      ],
    );
  }
}

class _TrackMusicVideoControls extends StatelessWidget {
  const _TrackMusicVideoControls({required this.controller});

  final TrackMusicVideoController controller;

  @override
  Widget build(BuildContext context) {
    final duration = controller.duration;
    final maximum = math.max(1, duration.inMilliseconds).toDouble();
    final position = controller.position.inMilliseconds.clamp(0, maximum);
    final playing = controller.stage == TrackMusicVideoStage.playing;
    return Semantics(
      container: true,
      label: 'Music video playback controls',
      child: Row(
        children: [
          IconButton.filled(
            key: const ValueKey('track-music-video-play-pause'),
            tooltip: playing ? 'Pause music video' : 'Play music video',
            onPressed: controller.canTogglePlayback
                ? () => unawaited(controller.togglePlayback())
                : null,
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
          const SizedBox(width: MusicSpacing.itemGap),
          Text(
            _formatDuration(controller.position),
            key: const ValueKey('track-music-video-position'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Expanded(
            child: Slider(
              key: const ValueKey('track-music-video-progress'),
              min: 0,
              max: maximum,
              value: position.toDouble(),
              onChanged: controller.canSeek
                  ? (value) => unawaited(
                      controller.seek(Duration(milliseconds: value.round())),
                    )
                  : null,
              semanticFormatterCallback: (value) =>
                  '${_formatDuration(Duration(milliseconds: value.round()))} '
                  'of ${_formatDuration(duration)}',
            ),
          ),
          Text(
            _formatDuration(duration),
            key: const ValueKey('track-music-video-duration'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final totalSeconds = math.max(0, value.inSeconds);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _failureCopy(TrackMusicVideoFailure? failure) => switch (failure) {
  TrackMusicVideoFailure.sourceUnavailable =>
    'QQ Music did not provide a supported playable MV source.',
  TrackMusicVideoFailure.network =>
    'The MV request could not reach QQ Music. Check your connection.',
  TrackMusicVideoFailure.serviceUnavailable =>
    'QQ Music could not serve this MV right now.',
  TrackMusicVideoFailure.invalidResponse =>
    'QQ Music returned MV data the app could not safely use.',
  TrackMusicVideoFailure.cancelled => 'The MV request was cancelled.',
  TrackMusicVideoFailure.alreadyRunning =>
    'Another MV request is already running. Try again shortly.',
  TrackMusicVideoFailure.coreUnavailable ||
  null => 'The MV player could not start this video.',
};
