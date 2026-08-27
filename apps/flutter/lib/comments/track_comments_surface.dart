import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/comments/track_comment_controller.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

Future<void> showTrackCommentsSurface({
  required BuildContext context,
  required TrackCommentGateway gateway,
  required PlaylistTrackSummary track,
  required QueuePlaybackController playbackController,
}) async {
  final compact = MediaQuery.sizeOf(context).width < 600;
  Widget content(BuildContext modalContext) => PlaybackShortcuts(
    controller: playbackController,
    child: TrackCommentsPanel(
      gateway: gateway,
      track: track,
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
        key: const ValueKey('track-comments-compact-surface'),
        height: MediaQuery.sizeOf(modalContext).height * 0.88,
        child: content(modalContext),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (modalContext) => Dialog(
      key: const ValueKey('track-comments-wide-surface'),
      child: SizedBox(
        width: 720,
        height: math.min(760, MediaQuery.sizeOf(modalContext).height - 64),
        child: content(modalContext),
      ),
    ),
  );
}

class TrackCommentsPanel extends StatefulWidget {
  const TrackCommentsPanel({
    required this.gateway,
    required this.track,
    required this.onClose,
    super.key,
  });

  final TrackCommentGateway gateway;
  final PlaylistTrackSummary track;
  final VoidCallback onClose;

  @override
  State<TrackCommentsPanel> createState() => _TrackCommentsPanelState();
}

class _TrackCommentsPanelState extends State<TrackCommentsPanel> {
  late final TrackCommentController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TrackCommentController(widget.gateway, widget.track);
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
                    'Comments',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    widget.track.title,
                    key: const ValueKey('track-comments-track-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) =>
                  _controller.stage == TrackCommentStage.content
                  ? Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: Text(
                        '${_controller.total}',
                        key: const ValueKey('track-comments-total'),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            IconButton(
              key: const ValueKey('track-comments-close'),
              tooltip: 'Close comments',
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
    TrackCommentStage.loading => const MusicLoadingPanel(
      key: ValueKey('track-comments-loading'),
      label: 'Loading comments',
    ),
    TrackCommentStage.empty => const MusicContentStatePanel(
      key: ValueKey('track-comments-empty'),
      icon: Icons.mode_comment_outlined,
      title: 'No comments yet',
      detail: 'QQ Music did not return comments for this Track.',
    ),
    TrackCommentStage.error => MusicContentStatePanel(
      key: const ValueKey('track-comments-error'),
      icon: Icons.cloud_off_rounded,
      title: 'Couldn’t load comments',
      detail: _failureCopy(_controller.failure),
      action: _controller.canRetry
          ? FilledButton.tonal(
              key: const ValueKey('track-comments-retry'),
              onPressed: _controller.retry,
              child: const Text('Try again'),
            )
          : null,
      liveRegion: true,
    ),
    TrackCommentStage.content => _CommentList(
      key: const ValueKey('track-comments-content'),
      hotComments: _controller.hotComments,
      latestComments: _controller.latestComments,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      canLoadMore: _controller.canLoadMore,
      canRetryMore: _controller.canRetryMore,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
    ),
  };
}

class _CommentList extends StatelessWidget {
  const _CommentList({
    required this.hotComments,
    required this.latestComments,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.canLoadMore,
    required this.canRetryMore,
    required this.onLoadMore,
    required this.onRetryMore,
    super.key,
  });

  final List<TrackCommentSummary> hotComments;
  final List<TrackCommentSummary> latestComments;
  final bool isLoadingMore;
  final TrackCommentFailure? appendFailure;
  final bool canLoadMore;
  final bool canRetryMore;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (hotComments.isNotEmpty) {
      children.add(const _SectionHeading(title: 'Hot comments'));
      children.addAll(
        hotComments.map(
          (comment) => _CommentItem(comment: comment, section: 'hot'),
        ),
      );
    }
    if (latestComments.isNotEmpty) {
      children.add(const _SectionHeading(title: 'Newest'));
      children.addAll(
        latestComments.map(
          (comment) => _CommentItem(comment: comment, section: 'latest'),
        ),
      );
    }
    children.add(
      _CommentFooter(
        isLoading: isLoadingMore,
        failure: appendFailure,
        canLoadMore: canLoadMore,
        canRetry: canRetryMore,
        onLoadMore: onLoadMore,
        onRetry: onRetryMore,
      ),
    );
    return ListView(
      key: const PageStorageKey<String>('track-comments-list'),
      padding: const EdgeInsetsDirectional.fromSTEB(
        MusicSpacing.pageCompact,
        MusicSpacing.contentGap,
        MusicSpacing.pageCompact,
        MusicSpacing.page,
      ),
      children: children,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(
      top: MusicSpacing.itemGap,
      bottom: MusicSpacing.itemGap,
    ),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _CommentItem extends StatelessWidget {
  const _CommentItem({required this.comment, required this.section});

  final TrackCommentSummary comment;
  final String section;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final authorInitial = comment.authorDisplayName.characters.first;
    final time = _commentTime(comment.publishedAtUnixSeconds);
    return Semantics(
      container: true,
      child: Padding(
        key: ValueKey('track-comment-$section-${comment.opaqueId}'),
        padding: const EdgeInsets.symmetric(vertical: MusicSpacing.itemGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: colors.secondaryContainer,
              foregroundColor: colors.onSecondaryContainer,
              child: Text(authorInitial.toUpperCase()),
            ),
            const SizedBox(width: MusicSpacing.contentGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          comment.authorDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: MusicSpacing.itemGap),
                      Text(
                        time,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(comment.content),
                  const SizedBox(height: MusicSpacing.itemGap),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.thumb_up_outlined,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${comment.praiseCount}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentFooter extends StatelessWidget {
  const _CommentFooter({
    required this.isLoading,
    required this.failure,
    required this.canLoadMore,
    required this.canRetry,
    required this.onLoadMore,
    required this.onRetry,
  });

  final bool isLoading;
  final TrackCommentFailure? failure;
  final bool canLoadMore;
  final bool canRetry;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(MusicSpacing.contentGap),
        child: Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }
    if (failure != null) {
      return Semantics(
        container: true,
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.all(MusicSpacing.contentGap),
          child: Column(
            children: [
              Text(
                'Couldn’t load more comments. ${_failureCopy(failure)}',
                textAlign: TextAlign.center,
              ),
              if (canRetry) ...[
                const SizedBox(height: MusicSpacing.itemGap),
                TextButton(
                  key: const ValueKey('track-comments-retry-more'),
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (!canLoadMore) return const SizedBox(height: MusicSpacing.itemGap);
    return Padding(
      padding: const EdgeInsets.all(MusicSpacing.contentGap),
      child: Center(
        child: OutlinedButton(
          key: const ValueKey('track-comments-load-more'),
          onPressed: onLoadMore,
          child: const Text('Load more'),
        ),
      ),
    );
  }
}

String _commentTime(int unixSeconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(
    unixSeconds * 1000,
    isUtc: true,
  ).toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _failureCopy(TrackCommentFailure? failure) => switch (failure) {
  TrackCommentFailure.network => 'Check your connection and try again.',
  TrackCommentFailure.serviceUnavailable =>
    'QQ Music comments are temporarily unavailable.',
  TrackCommentFailure.invalidResponse =>
    'QQ Music returned comment data this version cannot read.',
  TrackCommentFailure.coreUnavailable =>
    'The native comment service is unavailable in this build.',
  TrackCommentFailure.alreadyRunning =>
    'Another comment request is still finishing. Try again.',
  TrackCommentFailure.cancelled => 'The comment request was cancelled.',
  null => 'Try again.',
};
