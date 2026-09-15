import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutterustmusic/adaptive_side_sheet.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/partial_results_notice.dart';
import 'package:flutterustmusic/comments/track_comment_controller.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/provider_presentation.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

Future<void> showTrackCommentsSurface({
  required BuildContext context,
  required TrackCommentGateway gateway,
  required PlaylistTrackSummary track,
  required QueuePlaybackController playbackController,
}) async {
  final width = MediaQuery.sizeOf(context).width;
  final compact = width < 600;
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
  if (width >= 900) {
    await showAdaptiveSideSheet<void>(
      context: context,
      surfaceKey: const ValueKey('track-comments-wide-side-sheet'),
      width: 620,
      builder: (sheetContext) => PlaybackShortcuts(
        controller: playbackController,
        child: TrackCommentsPanel(
          gateway: gateway,
          track: track,
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
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
                    context.l10n.commentsTitle,
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
              tooltip: context.l10n.commentsClose,
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
    TrackCommentStage.loading => MusicLoadingPanel(
      key: const ValueKey('track-comments-loading'),
      label: context.l10n.commentsLoading,
    ),
    TrackCommentStage.empty => MusicContentStatePanel(
      key: const ValueKey('track-comments-empty'),
      icon: Icons.mode_comment_outlined,
      title: context.l10n.commentsEmptyTitle,
      detail: context.l10n.commentsEmptyDetail(
        builtInProviderDisplayName(widget.track.providerId, context.l10n),
      ),
    ),
    TrackCommentStage.error => MusicContentStatePanel(
      key: const ValueKey('track-comments-error'),
      icon: Icons.cloud_off_rounded,
      title: context.l10n.commentsFailureTitle,
      detail: _failureCopy(
        context.l10n,
        _controller.failure,
        builtInProviderDisplayName(widget.track.providerId, context.l10n),
      ),
      action: _controller.canRetry
          ? FilledButton.tonal(
              key: const ValueKey('track-comments-retry'),
              onPressed: _controller.retry,
              child: Text(context.l10n.commonRetry),
            )
          : null,
      liveRegion: true,
    ),
    TrackCommentStage.content => _CommentList(
      key: const ValueKey('track-comments-content'),
      hotComments: _controller.hotComments,
      latestComments: _controller.latestComments,
      omittedCommentCount: _controller.omittedCommentCount,
      partialResultRevision: _controller.partialResultRevision,
      isLoadingMore: _controller.isLoadingMore,
      appendFailure: _controller.appendFailure,
      canLoadMore: _controller.canLoadMore,
      canRetryMore: _controller.canRetryMore,
      onLoadMore: _controller.loadMore,
      onRetryMore: _controller.retryMore,
      providerDisplayName: builtInProviderDisplayName(
        widget.track.providerId,
        context.l10n,
      ),
    ),
  };
}

class _CommentList extends StatelessWidget {
  const _CommentList({
    required this.hotComments,
    required this.latestComments,
    required this.omittedCommentCount,
    required this.partialResultRevision,
    required this.isLoadingMore,
    required this.appendFailure,
    required this.canLoadMore,
    required this.canRetryMore,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.providerDisplayName,
    super.key,
  });

  final List<TrackCommentSummary> hotComments;
  final List<TrackCommentSummary> latestComments;
  final int omittedCommentCount;
  final int partialResultRevision;
  final bool isLoadingMore;
  final TrackCommentFailure? appendFailure;
  final bool canLoadMore;
  final bool canRetryMore;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryMore;
  final String providerDisplayName;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (omittedCommentCount > 0) {
      children.add(
        PartialResultsNotice(
          omittedCount: omittedCommentCount,
          resultRevision: partialResultRevision,
        ),
      );
    }
    if (hotComments.isNotEmpty) {
      children.add(_SectionHeading(title: context.l10n.commentsHot));
      children.addAll(
        hotComments.map(
          (comment) => _CommentItem(comment: comment, section: 'hot'),
        ),
      );
    }
    if (latestComments.isNotEmpty) {
      children.add(_SectionHeading(title: context.l10n.commentsNewest));
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
        providerDisplayName: providerDisplayName,
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
    final time = _commentTime(context, comment.publishedAtUnixSeconds);
    return Semantics(
      container: true,
      child: Padding(
        key: ValueKey('track-comment-$section-${comment.opaqueId}'),
        padding: const EdgeInsets.symmetric(vertical: MusicSpacing.itemGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CommentAvatar(
              authorInitial: authorInitial,
              artworkUri: comment.authorAvatarUri,
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

class _CommentAvatar extends StatelessWidget {
  const _CommentAvatar({required this.authorInitial, required this.artworkUri});

  final String authorInitial;
  final String? artworkUri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Center(
        child: Text(
          authorInitial.toUpperCase(),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: colors.onSecondaryContainer),
        ),
      ),
    );
    final uri = artworkUri;
    return SizedBox.square(
      key: const ValueKey('track-comment-avatar'),
      dimension: 40,
      child: ClipOval(
        child: uri == null
            ? fallback
            : Image.network(
                uri,
                headers: musicArtworkRequestHeaders(uri),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : fallback,
                errorBuilder: musicArtworkErrorBuilder(uri, fallback),
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
    required this.providerDisplayName,
  });

  final bool isLoading;
  final TrackCommentFailure? failure;
  final bool canLoadMore;
  final bool canRetry;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final String providerDisplayName;

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
                context.l10n.commentsLoadMoreFailure(
                  _failureCopy(context.l10n, failure, providerDisplayName),
                ),
                textAlign: TextAlign.center,
              ),
              if (canRetry) ...[
                const SizedBox(height: MusicSpacing.itemGap),
                TextButton(
                  key: const ValueKey('track-comments-retry-more'),
                  onPressed: onRetry,
                  child: Text(context.l10n.commonRetry),
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
          child: Text(context.l10n.commentsLoadMore),
        ),
      ),
    );
  }
}

String _commentTime(BuildContext context, int unixSeconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(
    unixSeconds * 1000,
    isUtc: true,
  ).toLocal();
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(value)} '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
}

String _failureCopy(
  AppLocalizations l10n,
  TrackCommentFailure? failure,
  String providerDisplayName,
) => switch (failure) {
  TrackCommentFailure.network => l10n.commentsFailureNetwork,
  TrackCommentFailure.serviceUnavailable => l10n.commentsFailureService(
    providerDisplayName,
  ),
  TrackCommentFailure.invalidResponse => l10n.commentsFailureInvalid(
    providerDisplayName,
  ),
  TrackCommentFailure.coreUnavailable => l10n.commentsFailureCore,
  TrackCommentFailure.alreadyRunning => l10n.commentsFailureRunning,
  TrackCommentFailure.cancelled => l10n.commentsFailureCancelled,
  null => l10n.commonRetry,
};
