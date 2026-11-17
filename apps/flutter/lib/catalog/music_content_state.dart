import 'package:flutter/material.dart';

class MusicLoadingPanel extends StatelessWidget {
  const MusicLoadingPanel({required this.label, this.detail, super.key});

  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasDetail = detail != null && detail!.isNotEmpty;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Semantics(
            container: true,
            label: hasDetail ? '$label, $detail' : label,
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(
                      dimension: 64,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: hasDetail
                        ? theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          )
                        : theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                  ),
                  if (hasDetail) ...[
                    const SizedBox(height: 8),
                    Text(
                      detail!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Smoothly reveals stage transitions (`loading` -> `content` / `empty` /
/// `error`) with a crisp fade and subtle vertical lift while keeping only the
/// active child in the widget tree and showing loading states immediately.
class MusicStageTransition extends StatefulWidget {
  const MusicStageTransition({
    required this.child,
    this.duration = const Duration(milliseconds: 140),
    this.slideOffset = 4,
    this.loading = false,
    super.key,
  });

  final Widget child;
  final Duration duration;
  final double slideOffset;
  final bool loading;

  @override
  State<MusicStageTransition> createState() => _MusicStageTransitionState();
}

class _MusicStageTransitionState extends State<MusicStageTransition>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _curved;

  static bool _isLoadingStage(Widget child) {
    if (child is MusicLoadingPanel) return true;
    if (child.key case ValueKey<String>(:final value)) {
      return value.endsWith('-loading');
    }
    return false;
  }

  void _ensureController() {
    if (_controller != null) {
      _controller!.duration = widget.duration;
      return;
    }
    final controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    );
    _controller = controller;
    _curved = CurvedAnimation(parent: controller, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _controller?.value = 1;
    }
  }

  @override
  void didUpdateWidget(MusicStageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller?.duration = widget.duration;
    final wasLoading = oldWidget.loading || _isLoadingStage(oldWidget.child);
    final isLoading = widget.loading || _isLoadingStage(widget.child);
    final stageChanged =
        !Widget.canUpdate(oldWidget.child, widget.child) ||
        oldWidget.loading != widget.loading;
    if (!stageChanged) {
      return;
    }
    final disableAnimations =
        !TickerMode.valuesOf(context).enabled ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        (MediaQuery.maybeAccessibleNavigationOf(context) ?? false);
    if (disableAnimations ||
        widget.duration <= Duration.zero ||
        isLoading ||
        !wasLoading) {
      _controller?.value = 1;
    } else {
      _ensureController();
      _controller!.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        (MediaQuery.maybeAccessibleNavigationOf(context) ?? false);
    if (disableAnimations) {
      return widget.child;
    }
    final animation = _curved ?? kAlwaysCompleteAnimation;
    return AnimatedBuilder(
      animation: animation,
      child: widget.child,
      builder: (context, child) {
        final progress = animation.value;
        final opacity = progress >= 1 ? 1.0 : 0.58 + (0.42 * progress);
        final dy = progress >= 1 ? 0.0 : (1 - progress) * widget.slideOffset;
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, dy),
            transformHitTests: false,
            child: child,
          ),
        );
      },
    );
  }
}

class MusicContentStatePanel extends StatelessWidget {
  const MusicContentStatePanel({
    required this.icon,
    required this.title,
    this.detail,
    this.action,
    this.liveRegion = false,
    this.announcementLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;
  final bool liveRegion;
  final String? announcementLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasDetail = detail != null && detail!.isNotEmpty;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 64,
            child: Icon(icon, size: 30, color: colors.onSecondaryContainer),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (hasDetail) ...[
          const SizedBox(height: 8),
          Text(
            detail!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                container: true,
                liveRegion: liveRegion,
                label: announcementLabel,
                excludeSemantics: announcementLabel != null,
                child: body,
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Retains visited tab children in the widget tree using [Offstage] while
/// animating switches between the outgoing and incoming tabs.
class MusicRetainedTabTransition extends StatefulWidget {
  const MusicRetainedTabTransition({
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 220),
    this.slideDistance = 12,
    super.key,
  });

  final int index;
  final List<Widget?> children;
  final Duration duration;
  final double slideDistance;

  @override
  State<MusicRetainedTabTransition> createState() =>
      _MusicRetainedTabTransitionState();
}

class _MusicRetainedTabTransitionState extends State<MusicRetainedTabTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _currentIndex;
  int? _previousIndex;
  double _direction = 1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      value: 1,
      duration: widget.duration,
    )..addStatusListener(_handleStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _controller.value = 1;
      _previousIndex = null;
    }
  }

  @override
  void didUpdateWidget(MusicRetainedTabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (_previousIndex != null && _previousIndex! >= widget.children.length) {
      _previousIndex = null;
    }
    if (widget.index == _currentIndex) return;
    _previousIndex = _currentIndex < widget.children.length
        ? _currentIndex
        : null;
    _direction = widget.index > _currentIndex ? 1 : -1;
    _currentIndex = widget.index;
    final disableAnimations =
        !TickerMode.valuesOf(context).enabled ||
        widget.duration <= Duration.zero ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        (MediaQuery.maybeAccessibleNavigationOf(context) ?? false);
    if (disableAnimations) {
      _controller.value = 1;
      _previousIndex = null;
    } else {
      _controller.forward(from: 0);
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _previousIndex != null &&
        mounted) {
      setState(() => _previousIndex = null);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final eased = Easing.emphasizedDecelerate.transform(_controller.value);
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          for (var index = 0; index < widget.children.length; index++)
            if (widget.children[index] != null)
              _buildChild(index, widget.children[index]!, eased),
        ],
      );
    },
  );

  Widget _buildChild(int index, Widget child, double animationValue) {
    final current = index == _currentIndex;
    final previous = index == _previousIndex;
    final active = current || previous;
    final offset = current
        ? Offset((1 - animationValue) * widget.slideDistance * _direction, 0)
        : Offset(
            -animationValue * (widget.slideDistance * 0.5) * _direction,
            0,
          );
    final opacity = current ? 0.72 + animationValue * 0.28 : 1 - animationValue;
    return Offstage(
      key: ValueKey<Object>(child.key ?? index),
      offstage: !active,
      child: TickerMode(
        enabled: current,
        child: ExcludeSemantics(
          excluding: !current,
          child: ExcludeFocus(
            excluding: !current,
            child: IgnorePointer(
              ignoring: !current,
              child: Transform.translate(
                offset: offset,
                transformHitTests: false,
                child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
