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

  @override
  void didUpdateWidget(BoundedViewportPageDemand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled ||
        oldWidget.generation != widget.generation) {
      _armed = true;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (!widget.enabled ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final delta = switch (notification) {
      ScrollUpdateNotification() => notification.scrollDelta ?? 0,
      OverscrollNotification() => notification.overscroll,
      _ => 0.0,
    };
    if (delta < 0) {
      _armed = true;
      widget.onRetreat?.call();
      return false;
    }
    if (delta <= 0) return false;

    final threshold =
        notification.metrics.viewportDimension * widget.thresholdViewports;
    if (notification.metrics.extentAfter > threshold * 1.5) {
      _armed = true;
    } else if (_armed && notification.metrics.extentAfter <= threshold) {
      _armed = false;
      unawaited(Future<void>.sync(widget.onDemand));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      );
}
