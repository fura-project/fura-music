import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollDirection;
import 'package:flutterustmusic/fura_toast.dart';
import 'package:flutterustmusic/adaptive_side_sheet.dart';
import 'package:flutterustmusic/adaptive_confirmation.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/catalog/music_track_tile.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/pagination/bounded_viewport_page_demand.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

Future<void> showPlaybackQueue(
  BuildContext context,
  QueuePlaybackController controller,
) async {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 600) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.72,
        child: PlaybackShortcuts(
          controller: controller,
          child: PlaybackQueuePanel(
            controller: controller,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
    return;
  }
  if (width >= 900) {
    await showAdaptiveSideSheet<void>(
      context: context,
      surfaceKey: const ValueKey('playback-queue-wide-side-sheet'),
      builder: (sheetContext) => PlaybackShortcuts(
        controller: controller,
        child: PlaybackQueuePanel(
          controller: controller,
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    animationStyle: furaDialogAnimationStyle(context),
    builder: (context) => FuraDialogTransition(
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: PlaybackShortcuts(
            controller: controller,
            child: PlaybackQueuePanel(
              controller: controller,
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    ),
  );
}

class PlaybackQueuePanel extends StatefulWidget {
  const PlaybackQueuePanel({
    required this.controller,
    required this.onClose,
    super.key,
  });

  final QueuePlaybackController controller;
  final VoidCallback onClose;

  @override
  State<PlaybackQueuePanel> createState() => _PlaybackQueuePanelState();
}

class _PlaybackQueuePanelState extends State<PlaybackQueuePanel> {
  static const double _listVerticalPadding = 8.0;
  static const double _viewportAnchorFraction = 0.28;

  final GlobalKey _activeTileKey = GlobalKey(debugLabel: 'queue-active-tile');
  final Map<int, BuildContext> _mountedTileContexts = <int, BuildContext>{};
  final List<ScrollController> _retiredControllers = <ScrollController>[];
  ScrollController? _scrollController;
  bool _didInitialScroll = false;
  bool _suppressScrollNotifications = false;
  bool _disposeRetiredScheduled = false;
  int _initialPositionRevision = 0;

  @override
  void didUpdateWidget(PlaybackQueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _resetInitialScroll(disposeImmediately: true);
    }
  }

  @override
  void dispose() {
    _initialPositionRevision += 1;
    _scrollController?.dispose();
    for (final retired in _retiredControllers) {
      retired.dispose();
    }
    _retiredControllers.clear();
    super.dispose();
  }

  void _resetInitialScroll({required bool disposeImmediately}) {
    _initialPositionRevision += 1;
    _didInitialScroll = false;
    _mountedTileContexts.clear();
    final existing = _scrollController;
    _scrollController = null;
    if (existing != null) {
      if (disposeImmediately) {
        existing.dispose();
      } else {
        _retireController(existing);
      }
    }
  }

  void _retireController(ScrollController controller) {
    _retiredControllers.add(controller);
    if (_disposeRetiredScheduled) return;
    _disposeRetiredScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _disposeRetiredScheduled = false;
      for (final retired in _retiredControllers) {
        retired.dispose();
      }
      _retiredControllers.clear();
    });
  }

  static double _estimatedTileHeight({
    required bool desktop,
    required TextScaler textScaler,
  }) {
    final minTileHeight = desktop ? 64.0 : 72.0;
    return math.max(minTileHeight, 16.0 + textScaler.scale(36.0));
  }

  static double _targetScrollOffset({
    required int? currentIndex,
    required int trackCount,
    required double tileHeight,
    required double viewportHeight,
    double? maxScrollExtent,
  }) {
    if (currentIndex == null ||
        currentIndex <= 0 ||
        currentIndex >= trackCount ||
        viewportHeight <= 0) {
      return 0;
    }
    final anchorInset = math.max(
      _listVerticalPadding,
      viewportHeight * _viewportAnchorFraction,
    );
    final rawOffset =
        _listVerticalPadding + (currentIndex * tileHeight) - anchorInset;
    final upperBound =
        maxScrollExtent ??
        math.max(
          0.0,
          (2 * _listVerticalPadding) +
              (trackCount * tileHeight) -
              viewportHeight,
        );
    return rawOffset.clamp(0.0, math.max(0.0, upperBound)).toDouble();
  }

  ScrollController _ensureScrollController({
    required int trackCount,
    required int? currentIndex,
    required double viewportHeight,
    required bool desktop,
    required TextScaler textScaler,
  }) {
    if (_didInitialScroll && _scrollController != null) {
      return _scrollController!;
    }
    if (viewportHeight <= 0) {
      return _scrollController ??= ScrollController(keepScrollOffset: false);
    }
    final estimatedTileHeight = _estimatedTileHeight(
      desktop: desktop,
      textScaler: textScaler,
    );
    final initialOffset = _targetScrollOffset(
      currentIndex: currentIndex,
      trackCount: trackCount,
      tileHeight: estimatedTileHeight,
      viewportHeight: viewportHeight,
    );
    _didInitialScroll = true;
    final existing = _scrollController;
    final ScrollController scrollController;
    if (existing == null) {
      scrollController = ScrollController(
        initialScrollOffset: initialOffset,
        keepScrollOffset: false,
      );
      _scrollController = scrollController;
    } else if (!existing.hasClients) {
      _retireController(existing);
      scrollController = ScrollController(
        initialScrollOffset: initialOffset,
        keepScrollOffset: false,
      );
      _scrollController = scrollController;
    } else {
      scrollController = existing;
    }
    final targetIndex = currentIndex ?? 0;
    if (targetIndex >= 0 && targetIndex < trackCount) {
      final revision = ++_initialPositionRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refineInitialPosition(
          revision: revision,
          targetIndex: targetIndex,
          trackCount: trackCount,
          fallbackTileHeight: estimatedTileHeight,
          attempt: 0,
        );
      });
    }
    return scrollController;
  }

  void _jumpSilently(ScrollController scrollController, double offset) {
    _suppressScrollNotifications = true;
    try {
      scrollController.jumpTo(offset);
    } finally {
      _suppressScrollNotifications = false;
    }
  }

  void _refineInitialPosition({
    required int revision,
    required int targetIndex,
    required int trackCount,
    required double fallbackTileHeight,
    required int attempt,
  }) {
    if (!mounted || revision != _initialPositionRevision) return;
    final scrollController = _scrollController;
    if (scrollController == null || scrollController.positions.length != 1) {
      return;
    }
    final position = scrollController.position;
    if (!position.hasContentDimensions) return;

    if (targetIndex <= 0 || targetIndex >= trackCount) {
      if ((position.pixels - position.minScrollExtent).abs() >= 0.5) {
        _jumpSilently(scrollController, position.minScrollExtent);
      }
      return;
    }

    final activeContext = _activeTileKey.currentContext;
    if (activeContext != null && activeContext.mounted) {
      final activeObject = activeContext.findRenderObject();
      if (activeObject is RenderBox && activeObject.hasSize) {
        final viewport = RenderAbstractViewport.maybeOf(activeObject);
        if (viewport != null) {
          final alignment =
              activeObject.size.height >= position.viewportDimension
              ? 0.0
              : _viewportAnchorFraction;
          final desired = viewport
              .getOffsetToReveal(activeObject, alignment)
              .offset
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
          if ((desired - position.pixels).abs() >= 0.5) {
            _jumpSilently(scrollController, desired);
            if (attempt < 4) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _refineInitialPosition(
                  revision: revision,
                  targetIndex: targetIndex,
                  trackCount: trackCount,
                  fallbackTileHeight: activeObject.size.height,
                  attempt: attempt + 1,
                );
              });
            }
          }
          return;
        }
      }
    }

    int? minMounted;
    int? maxMounted;
    RenderBox? minBox;
    RenderBox? maxBox;
    var heightSum = 0.0;
    var heightCount = 0;
    final staleIndices = <int>[];
    for (final entry in _mountedTileContexts.entries) {
      final ctx = entry.value;
      if (!ctx.mounted) {
        staleIndices.add(entry.key);
        continue;
      }
      final renderObject = ctx.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.hasSize ||
          renderObject.size.height <= 0) {
        continue;
      }
      final idx = entry.key;
      heightSum += renderObject.size.height;
      heightCount += 1;
      if (minMounted == null || idx < minMounted) {
        minMounted = idx;
        minBox = renderObject;
      }
      if (maxMounted == null || idx > maxMounted) {
        maxMounted = idx;
        maxBox = renderObject;
      }
    }
    for (final idx in staleIndices) {
      _mountedTileContexts.remove(idx);
    }

    final tileHeight = heightCount > 0
        ? (heightSum / heightCount)
        : fallbackTileHeight;
    final anchorInset = math.max(
      _listVerticalPadding,
      position.viewportDimension * _viewportAnchorFraction,
    );
    double desiredOffset;
    if (maxMounted != null && maxBox != null && targetIndex > maxMounted) {
      final maxTop =
          RenderAbstractViewport.maybeOf(maxBox)
              ?.getOffsetToReveal(maxBox, 0.0)
              .offset ??
          position.pixels;
      final raw =
          maxTop +
          maxBox.size.height +
          ((targetIndex - maxMounted - 1) * tileHeight) -
          anchorInset;
      desiredOffset = raw
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
    } else if (minMounted != null &&
        minBox != null &&
        targetIndex < minMounted) {
      final minTop =
          RenderAbstractViewport.maybeOf(minBox)
              ?.getOffsetToReveal(minBox, 0.0)
              .offset ??
          position.pixels;
      final raw =
          minTop - ((minMounted - targetIndex) * tileHeight) - anchorInset;
      desiredOffset = raw
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
    } else {
      desiredOffset = _targetScrollOffset(
        currentIndex: targetIndex,
        trackCount: trackCount,
        tileHeight: tileHeight,
        viewportHeight: position.viewportDimension,
        maxScrollExtent: position.maxScrollExtent,
      );
    }

    if ((desiredOffset - position.pixels).abs() < 0.5) return;
    _jumpSilently(scrollController, desiredOffset);
    if (attempt < 5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refineInitialPosition(
          revision: revision,
          targetIndex: targetIndex,
          trackCount: trackCount,
          fallbackTileHeight: tileHeight,
          attempt: attempt + 1,
        );
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_suppressScrollNotifications) return true;
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _initialPositionRevision += 1;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tracks = controller.tracks;
        if (tracks.isEmpty && _didInitialScroll) {
          _resetInitialScroll(disposeImmediately: false);
        }
        final continuationFooter =
            controller.collectionSourceId != null &&
            (controller.collectionStage == CollectionPlaybackStage.loading ||
                controller.collectionStage == CollectionPlaybackStage.failed ||
                controller.collectionStage ==
                    CollectionPlaybackStage.exhausted);
        final theme = Theme.of(context);
        final desktop = MediaQuery.sizeOf(context).width >= 600;
        return SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.queueTitle,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            context.l10n.queueTrackCount(tracks.length),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (tracks.isNotEmpty)
                      TextButton(
                        key: const ValueKey('queue-clear'),
                        onPressed: () => unawaited(
                          _confirmAndClearQueue(
                            context,
                            controller,
                            tracks.length,
                          ),
                        ),
                        child: Text(context.l10n.queueClear),
                      ),
                    IconButton(
                      tooltip: context.l10n.queueClose,
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (controller.failure case final failure?)
                Semantics(
                  container: true,
                  liveRegion: true,
                  label: _failureCopy(context.l10n, failure),
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _failureCopy(context.l10n, failure),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: tracks.isEmpty
                    ? MusicContentStatePanel(
                        key: const ValueKey('playback-queue-empty'),
                        icon: Icons.queue_music_rounded,
                        title: context.l10n.queueEmpty,
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final scrollController = _ensureScrollController(
                            trackCount: tracks.length,
                            currentIndex: controller.currentIndex,
                            viewportHeight: constraints.maxHeight,
                            desktop: desktop,
                            textScaler: MediaQuery.textScalerOf(context),
                          );
                          return BoundedViewportPageDemand(
                            key: const ValueKey('queue-continuation-demand'),
                            enabled:
                                controller.collectionHasMore &&
                                controller.collectionStage ==
                                    CollectionPlaybackStage.ready,
                            generation: controller.collectionDemandGeneration,
                            onDemand:
                                controller.demandCollectionFromQueueViewport,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: _handleScrollNotification,
                              child: ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: _listVerticalPadding,
                                ),
                                itemCount:
                                    tracks.length +
                                    (continuationFooter ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == tracks.length) {
                                    return _QueueContinuationFooter(
                                      stage: controller.collectionStage,
                                      onRetry: controller
                                          .retryCollectionContinuation,
                                    );
                                  }
                                  final track = tracks[index];
                                  final current =
                                      index == controller.currentIndex;
                                  return KeyedSubtree(
                                    key: current ? _activeTileKey : null,
                                    child: Builder(
                                      builder: (tileContext) {
                                        _mountedTileContexts[index] =
                                            tileContext;
                                        return _QueueTrackTile(
                                          track: track,
                                          index: index,
                                          current: current,
                                          desktop: desktop,
                                          onSelect: current
                                              ? null
                                              : () => unawaited(
                                                  controller.select(index),
                                                ),
                                          onRemove: () => unawaited(
                                            controller.remove(index),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QueueContinuationFooter extends StatelessWidget {
  const _QueueContinuationFooter({required this.stage, required this.onRetry});

  final CollectionPlaybackStage stage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: colors.onSurfaceVariant);
    return Semantics(
      container: true,
      liveRegion:
          stage == CollectionPlaybackStage.loading ||
          stage == CollectionPlaybackStage.failed,
      child: Padding(
        key: const ValueKey('queue-continuation-footer'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: switch (stage) {
          CollectionPlaybackStage.loading => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  context.l10n.queueContinuationLoading,
                  style: textStyle,
                ),
              ),
            ],
          ),
          CollectionPlaybackStage.failed => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.queueContinuationFailure,
                textAlign: TextAlign.center,
                style: textStyle?.copyWith(color: colors.error),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const ValueKey('queue-continuation-retry'),
                onPressed: onRetry,
                child: Text(context.l10n.queueContinuationRetry),
              ),
            ],
          ),
          CollectionPlaybackStage.exhausted => Text(
            context.l10n.queueContinuationEnd,
            textAlign: TextAlign.center,
            style: textStyle,
          ),
          CollectionPlaybackStage.idle ||
          CollectionPlaybackStage.ready => const SizedBox.shrink(),
        },
      ),
    );
  }
}

class _QueueTrackTile extends StatelessWidget {
  const _QueueTrackTile({
    required this.track,
    required this.index,
    required this.current,
    required this.desktop,
    required this.onSelect,
    required this.onRemove,
  });

  final PlaylistTrackSummary track;
  final int index;
  final bool current;
  final bool desktop;
  final VoidCallback? onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final secondaryForeground = current
        ? colors.onSecondaryContainer.withValues(alpha: 0.82)
        : colors.onSurfaceVariant;
    final duration = formatTrackDuration(track.durationSeconds);
    final album = track.albumTitle?.trim();
    final metadata = [
      track.artistNames.isEmpty
          ? context.l10n.trackUnknownArtist
          : track.artistNames.join(' · '),
      if (album != null && album.isNotEmpty) album,
      if (!desktop) duration,
    ].join(' · ');

    return Semantics(
      selected: current,
      button: !current,
      child: ListTile(
        key: ValueKey('queue-entry-$index'),
        minTileHeight: desktop ? 64 : 72,
        shape: const RoundedRectangleBorder(borderRadius: MusicRadii.control),
        contentPadding: EdgeInsets.symmetric(horizontal: desktop ? 12 : 8),
        selected: current,
        selectedColor: colors.onSecondaryContainer,
        selectedTileColor: colors.secondaryContainer,
        leading: SizedBox(
          width: 76,
          child: Row(
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  width: 28,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${index + 1}',
                      key: ValueKey('queue-position-$index'),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: secondaryForeground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _QueueArtwork(track: track, current: current, index: index),
            ],
          ),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: current ? FontWeight.w700 : FontWeight.w600,
            color: current ? colors.onSecondaryContainer : null,
          ),
        ),
        subtitle: Text(
          metadata,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondaryForeground,
          ),
        ),
        onTap: onSelect,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (desktop) ...[
              ExcludeSemantics(
                child: SizedBox(
                  width: 48,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      duration,
                      key: ValueKey('queue-duration-$index'),
                      maxLines: 1,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryForeground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              key: ValueKey('queue-remove-$index'),
              tooltip: context.l10n.queueRemove,
              onPressed: onRemove,
              color: current ? colors.onSecondaryContainer : null,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmAndClearQueue(
  BuildContext context,
  QueuePlaybackController controller,
  int trackCount,
) async {
  final description = trackCount == 1
      ? context.l10n.queueClearOneDetail
      : context.l10n.queueClearManyDetail(trackCount);
  final confirmed = await showAdaptiveConfirmation(
    context,
    title: context.l10n.queueClearTitle,
    message: description,
    confirmLabel: context.l10n.queueClear,
    cancelKey: const ValueKey('queue-clear-cancel'),
    confirmKey: const ValueKey('queue-clear-confirm'),
    sheetKey: const ValueKey('queue-clear-confirmation-sheet'),
    dialogKey: const ValueKey('queue-clear-confirmation-dialog'),
    wrapper: (child) => PlaybackShortcuts(controller: controller, child: child),
  );
  if (confirmed) await controller.clear();
}

class _QueueArtwork extends StatelessWidget {
  const _QueueArtwork({
    required this.track,
    required this.current,
    required this.index,
  });

  final PlaylistTrackSummary track;
  final bool current;
  final int index;

  @override
  Widget build(BuildContext context) {
    final artworkUri = track.artworkUri;
    return SizedBox.square(
      key: ValueKey('queue-artwork-$index'),
      dimension: 40,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (artworkUri == null)
              const _QueueArtworkPlaceholder()
            else
              Image.network(
                artworkUri,
                headers: musicArtworkRequestHeaders(artworkUri),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                gaplessPlayback: true,
                frameBuilder: musicArtworkFrameBuilder(
                  const _QueueArtworkPlaceholder(),
                ),
                errorBuilder: musicArtworkErrorBuilder(
                  artworkUri,
                  const _QueueArtworkPlaceholder(),
                ),
              ),
            if (current)
              ColoredBox(
                key: ValueKey('queue-current-indicator-$index'),
                color: Colors.black.withValues(alpha: 0.42),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QueueArtworkPlaceholder extends StatelessWidget {
  const _QueueArtworkPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('queue-artwork-placeholder'),
      color: colors.surfaceContainerHighest,
      child: Icon(
        Icons.album_outlined,
        color: colors.onSurfaceVariant,
        size: 22,
      ),
    );
  }
}

String _failureCopy(AppLocalizations l10n, PlaybackQueueFailure failure) =>
    switch (failure) {
      PlaybackQueueFailure.invalidTrack => l10n.queueFailureInvalidTrack,
      PlaybackQueueFailure.invalidPosition => l10n.queueFailureInvalidPosition,
      PlaybackQueueFailure.coreUnavailable => l10n.queueFailureCore,
      PlaybackQueueFailure.invalidResponse => l10n.queueFailureInvalidResponse,
    };
