import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/music_video/track_music_video_controller.dart';
import 'package:flutterustmusic/music_video/track_music_video_engine.dart';
import 'package:flutterustmusic/music_video/track_music_video_gateway.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/provider_presentation.dart';
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
                    context.l10n.musicVideoTitle,
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
              tooltip: context.l10n.musicVideoClose,
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
    TrackMusicVideoStage.loading => MusicLoadingPanel(
      key: const ValueKey('track-music-video-loading'),
      label: context.l10n.musicVideoLoading,
    ),
    TrackMusicVideoStage.unavailable => MusicContentStatePanel(
      key: const ValueKey('track-music-video-unavailable'),
      icon: Icons.music_video_outlined,
      title: context.l10n.musicVideoEmptyTitle,
      detail: context.l10n.musicVideoEmptyDetail(
        builtInProviderDisplayName(widget.track.providerId, context.l10n),
      ),
    ),
    TrackMusicVideoStage.error => MusicContentStatePanel(
      key: const ValueKey('track-music-video-error'),
      icon: Icons.video_file_outlined,
      title: _controller.failure == TrackMusicVideoFailure.sourceUnavailable
          ? context.l10n.musicVideoUnavailableTitle
          : context.l10n.musicVideoFailureTitle,
      detail: _failureCopy(
        context.l10n,
        _controller.failure,
        builtInProviderDisplayName(widget.track.providerId, context.l10n),
      ),
      action: _controller.canRetry
          ? FilledButton.tonal(
              key: const ValueKey('track-music-video-retry'),
              onPressed: _controller.retry,
              child: Text(context.l10n.commonRetry),
            )
          : null,
      liveRegion: true,
    ),
    TrackMusicVideoStage.interrupted => MusicContentStatePanel(
      key: const ValueKey('track-music-video-interrupted'),
      icon: Icons.stop_circle_outlined,
      title: context.l10n.musicVideoStoppedTitle,
      detail: context.l10n.musicVideoStoppedDetail,
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
      label: context.l10n.musicVideoControlsSemantics,
      child: Row(
        children: [
          IconButton.filled(
            key: const ValueKey('track-music-video-play-pause'),
            tooltip: playing
                ? context.l10n.musicVideoPause
                : context.l10n.musicVideoPlay,
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
                  context.l10n.playbackProgressSemantics(
                    _formatDuration(duration),
                    _formatDuration(Duration(milliseconds: value.round())),
                  ),
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

String _failureCopy(
  AppLocalizations l10n,
  TrackMusicVideoFailure? failure,
  String providerDisplayName,
) => switch (failure) {
  TrackMusicVideoFailure.sourceUnavailable => l10n.musicVideoFailureSource(
    providerDisplayName,
  ),
  TrackMusicVideoFailure.network => l10n.musicVideoFailureNetwork(
    providerDisplayName,
  ),
  TrackMusicVideoFailure.serviceUnavailable => l10n.musicVideoFailureService(
    providerDisplayName,
  ),
  TrackMusicVideoFailure.invalidResponse => l10n.musicVideoFailureInvalid(
    providerDisplayName,
  ),
  TrackMusicVideoFailure.cancelled => l10n.musicVideoFailureCancelled,
  TrackMusicVideoFailure.alreadyRunning => l10n.musicVideoFailureRunning,
  TrackMusicVideoFailure.coreUnavailable || null => l10n.musicVideoFailureCore,
};
