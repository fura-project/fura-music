import 'dart:async';

import 'package:flutter/widgets.dart';

/// Converts one downward approach to the end of a vertical viewport into one
/// bounded page-demand signal. It never loops and it does not cancel transport
/// already in flight; owners keep single-flight, retry and continuation state.
class BoundedViewportPageDemand extends StatefulWidget {
  const BoundedViewportPageDemand({
    required this.child,
    required this.onDemand,
    this.onRetreat,
    this.enabled = true,
    this.thresholdViewports = 1.25,
    this.generation,
    super.key,
  });

  final Widget child;
  final FutureOr<void> Function() onDemand;
  final VoidCallback? onRetreat;
  final bool enabled;
  final double thresholdViewports;

  /// A query/filter identity. Changing it rearms a new bounded demand window.
  final Object? generation;

  @override
  State<BoundedViewportPageDemand> createState() =>
      _BoundedViewportPageDemandState();
}

class _BoundedViewportPageDemandState extends State<BoundedViewportPageDemand> {
  bool _armed = true;
  int _dispatchEpoch = 0;
  int? _scheduledEpoch;
  bool _pendingDemand = false;
  bool _pendingRetreat = false;

  @override
  void didUpdateWidget(BoundedViewportPageDemand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation) {
      _invalidatePendingDispatch();
      _armed = true;
    } else if (oldWidget.enabled && !widget.enabled) {
      // Loading and other temporary disable states invalidate work recorded in
      // the previous frame, but do not grant another approach when re-enabled.
      _invalidatePendingDispatch();
    }
  }

  void _invalidatePendingDispatch() {
    _dispatchEpoch += 1;
    _scheduledEpoch = null;
    _pendingDemand = false;
    _pendingRetreat = false;
  }

  void _scheduleDispatch({bool demand = false, bool retreat = false}) {
    _pendingDemand = _pendingDemand || demand;
    _pendingRetreat = _pendingRetreat || retreat;
    final epoch = _dispatchEpoch;
    if (_scheduledEpoch == epoch) return;
    _scheduledEpoch = epoch;
    final generation = widget.generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          epoch != _dispatchEpoch ||
          generation != widget.generation) {
        return;
      }
      if (_scheduledEpoch == epoch) _scheduledEpoch = null;
      final dispatchRetreat = _pendingRetreat;
      final dispatchDemand = _pendingDemand;
      _pendingRetreat = false;
      _pendingDemand = false;

      if (!widget.enabled) return;
      if (dispatchRetreat) widget.onRetreat?.call();
      if (dispatchDemand && mounted) {
        unawaited(Future<void>.sync(widget.onDemand));
      }
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final delta = switch (notification) {
      ScrollUpdateNotification() => notification.scrollDelta ?? 0,
      OverscrollNotification() => notification.overscroll,
      _ => 0.0,
    };
    if (delta < 0) {
      _armed = true;
      _pendingDemand = false;
      if (widget.enabled) _scheduleDispatch(retreat: true);
      return false;
    }
    if (delta <= 0) return false;

    final threshold =
        notification.metrics.viewportDimension * widget.thresholdViewports;
    if (notification.metrics.extentAfter > threshold * 1.5) {
      _pendingDemand = false;
      _armed = true;
    } else if (widget.enabled &&
        _armed &&
        notification.metrics.extentAfter <= threshold) {
      _armed = false;
      _scheduleDispatch(demand: true);
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
    super.dispose();
  }
}
