import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutterustmusic/library/paged_tracks_controller.dart';

/// Presentation-only lookahead. The transport page size and continuation cursor
/// remain owned by the existing gateway/controller; no QQ protocol lives here.
class PlaylistPrefetchPolicy {
  Duration? _lastSample;
  double _velocity = 0;

  void reset() {
    _lastSample = null;
    _velocity = 0;
  }

  int targetTrackCount({
    required int loadedCount,
    required double extentAfter,
    required double contentExtent,
    required double scrollDelta,
    required Duration sampleTime,
    required Duration pageLatency,
    int pageSize = PagedTracksController.pageSize,
  }) {
    if (scrollDelta <= 0 || loadedCount == 0 || contentExtent <= 0) {
      reset();
      return loadedCount;
    }
    final elapsed = _lastSample == null
        ? 1 / 60
        : (sampleTime - _lastSample!).inMicroseconds / 1000000;
    _lastSample = sampleTime;
    final speed = scrollDelta / elapsed.clamp(1 / 120, 0.25);
    // Respond immediately to acceleration; smooth deceleration. A new gesture
    // resets the sample, so time spent idle cannot bias its first prediction.
    _velocity = math.max(speed, _velocity * 0.65 + speed * 0.35);
    final rowExtent = contentExtent / loadedCount;
    final remainingRows = math.max(0, extentAfter) / rowExtent;
    final visibleEnd = (loadedCount - remainingRows).ceil().clamp(
      0,
      loadedCount,
    );
    final horizon = pageLatency.inMicroseconds / 1000000 + 0.5;
    final minimumLookahead = math.max(1, pageSize ~/ 2).toInt();
    final lookahead = (_velocity * horizon / rowExtent).ceil().clamp(
      minimumLookahead,
      pageSize * 2,
    );
    return visibleEnd + lookahead;
  }
}

/// Shared by Liked, ordinary playlists and recently played without changing layout,
/// PageStorage keys, lazy builders, or the parent's header-collapse listener.
class PlaylistScrollPrefetch extends StatefulWidget {
  const PlaylistScrollPrefetch({
    required this.controller,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final PagedTracksController controller;
  final Widget child;
  final bool enabled;

  @override
  State<PlaylistScrollPrefetch> createState() => _PlaylistScrollPrefetchState();
}

class _PlaylistScrollPrefetchState extends State<PlaylistScrollPrefetch> {
  final _policy = PlaylistPrefetchPolicy();
  int _dispatchEpoch = 0;
  int? _scheduledEpoch;
  int? _pendingTarget;

  void _invalidatePendingDispatch() {
    _dispatchEpoch += 1;
    _scheduledEpoch = null;
    _pendingTarget = null;
  }

  void _schedulePrefetch(int target) {
    _pendingTarget = math.max(_pendingTarget ?? 0, target);
    final epoch = _dispatchEpoch;
    if (_scheduledEpoch == epoch) return;
    _scheduledEpoch = epoch;
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          epoch != _dispatchEpoch ||
          !widget.enabled ||
          !identical(widget.controller, controller)) {
        return;
      }
      if (_scheduledEpoch == epoch) _scheduledEpoch = null;
      final target = _pendingTarget;
      _pendingTarget = null;
      if (target != null) controller.prefetchTo(target);
    });
  }

  @override
  void didUpdateWidget(PlaylistScrollPrefetch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _invalidatePendingDispatch();
      oldWidget.controller.cancelPrefetch();
      _policy.reset();
    } else if (oldWidget.enabled && !widget.enabled) {
      _invalidatePendingDispatch();
      widget.controller.cancelPrefetch();
      _policy.reset();
    } else if (!oldWidget.enabled && widget.enabled) {
      _policy.reset();
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (!widget.enabled ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _policy.reset();
    }
    final delta = switch (notification) {
      ScrollUpdateNotification() => notification.scrollDelta ?? 0,
      OverscrollNotification() => notification.overscroll,
      _ => 0.0,
    };
    if (delta < 0) {
      _invalidatePendingDispatch();
      widget.controller.cancelPrefetch();
      _policy.reset();
    } else if (delta > 0) {
      final metrics = notification.metrics;
      _schedulePrefetch(
        _policy.targetTrackCount(
          loadedCount: widget.controller.tracks.length,
          extentAfter: metrics.extentAfter,
          contentExtent:
              metrics.maxScrollExtent -
              metrics.minScrollExtent +
              metrics.viewportDimension,
          scrollDelta: delta,
          sampleTime: WidgetsBinding.instance.currentSystemFrameTimeStamp,
          pageLatency: widget.controller.estimatedPageLatency,
        ),
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      );

  @override
  void dispose() {
    _invalidatePendingDispatch();
    widget.controller.cancelPrefetch();
    super.dispose();
  }
}
