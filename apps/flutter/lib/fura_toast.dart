import 'package:flutter/material.dart';

typedef FuraToastMarginResolver = EdgeInsets Function(BuildContext context);

/// Provides shell-aware [SnackBar] margins so transient capsule toasts never
/// collide with the persistent player bar or compact navigation bar.
class FuraToastScope extends InheritedWidget {
  const FuraToastScope({
    required this.resolveMargin,
    required super.child,
    super.key,
  });

  final FuraToastMarginResolver resolveMargin;

  static FuraToastMarginResolver? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FuraToastScope>()
      ?.resolveMargin;

  @override
  bool updateShouldNotify(FuraToastScope oldWidget) =>
      resolveMargin != oldWidget.resolveMargin;
}

EdgeInsets furaPlaybackSnackBarMargin({
  required double viewportWidth,
  required double bottomSafeArea,
  required bool playerPresent,
  required bool settingsOpen,
  required bool expandedNowPlayingOpen,
}) {
  const gap = 12.0;
  var bottom = bottomSafeArea + gap;
  if (expandedNowPlayingOpen) {
    final expandedControls = viewportWidth < 600 ? 132.0 : 124.0;
    bottom += expandedControls;
  } else if (playerPresent) {
    final player = viewportWidth < 640 ? 68.0 : 88.0;
    final navigation = viewportWidth < 840 && !settingsOpen ? 72.0 : 0.0;
    bottom += player + navigation;
  }
  final horizontal = viewportWidth > 392
      ? ((viewportWidth - 360) / 2).clamp(16.0, double.infinity).toDouble()
      : 16.0;
  return EdgeInsets.fromLTRB(horizontal, 0, horizontal, bottom);
}

EdgeInsets resolveFuraToastMargin(BuildContext context) {
  final resolver = FuraToastScope.maybeOf(context);
  if (resolver != null) {
    return resolver(context);
  }
  return furaPlaybackSnackBarMargin(
    viewportWidth: MediaQuery.sizeOf(context).width,
    bottomSafeArea: MediaQuery.paddingOf(context).bottom,
    playerPresent: false,
    settingsOpen: false,
    expandedNowPlayingOpen: false,
  );
}

AnimationStyle? furaToastAnimationStyle(BuildContext context) {
  if (MediaQuery.accessibleNavigationOf(context) ||
      MediaQuery.disableAnimationsOf(context)) {
    return AnimationStyle.noAnimation;
  }
  return const AnimationStyle(
    duration: Duration(milliseconds: 350),
    reverseDuration: Duration(milliseconds: 220),
  );
}

SnackBar buildFuraToastSnackBar(
  BuildContext context, {
  required String message,
  Key? snackBarKey,
  Key? surfaceKey,
  Key? semanticsKey,
  EdgeInsets? margin,
  Duration duration = const Duration(milliseconds: 1800),
  VoidCallback? onVisible,
}) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return SnackBar(
    key: snackBarKey,
    behavior: SnackBarBehavior.floating,
    clipBehavior: Clip.none,
    duration: duration,
    margin: margin ?? resolveFuraToastMargin(context),
    padding: EdgeInsets.zero,
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const StadiumBorder(),
    onVisible: onVisible,
    content: Center(
      heightFactor: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: FuraToastTransition(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Material(
              key: surfaceKey,
              color: colors.surfaceContainerHighest,
              surfaceTintColor: Colors.transparent,
              elevation: 3,
              shadowColor: colors.shadow.withValues(alpha: 0.20),
              shape: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Semantics(
                  key: semanticsKey,
                  liveRegion: true,
                  label: message,
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showFuraToast(
  BuildContext context,
  String message, {
  Key? snackBarKey,
  Key? surfaceKey,
  Key? semanticsKey,
  EdgeInsets? margin,
  Duration duration = const Duration(milliseconds: 1800),
  VoidCallback? onVisible,
  bool hideCurrent = true,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return null;
  if (hideCurrent) {
    messenger.hideCurrentSnackBar();
  }
  return messenger.showSnackBar(
    buildFuraToastSnackBar(
      context,
      message: message,
      snackBarKey: snackBarKey,
      surfaceKey: surfaceKey,
      semanticsKey: semanticsKey,
      margin: margin,
      duration: duration,
      onVisible: onVisible,
    ),
  );
}

/// Animates the floating capsule toast inside the visible `[0.38, 1.0]` M3
/// [SnackBar] fade window so entrance scale and vertical lift are not lost
/// while Flutter's outer `_fadeInM3Animation` holds opacity at `0.0` during
/// `[0.0, 0.40]`.
class FuraToastTransition extends StatelessWidget {
  const FuraToastTransition({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = context
        .findAncestorWidgetOfExactType<SnackBar>()
        ?.animation;
    if (animation == null ||
        MediaQuery.accessibleNavigationOf(context) ||
        MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final raw = animation.value.clamp(0.0, 1.0);
        final isReversing =
            animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;
        if (isReversing) {
          final progress = ((raw - 0.40) / 0.60).clamp(0.0, 1.0);
          final curved = Curves.easeInCubic.transform(progress);
          return Opacity(
            opacity: curved.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1.0 - curved) * 14.0),
              child: Transform.scale(
                scale: 0.86 + (0.14 * curved),
                child: child,
              ),
            ),
          );
        }
        final progress = ((raw - 0.38) / 0.62).clamp(0.0, 1.0);
        final easeOut = Curves.easeOutCubic.transform(progress);
        final scaleProgress = Curves.easeOutBack.transform(progress);
        return Opacity(
          opacity: easeOut.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - easeOut) * 22.0),
            child: Transform.scale(
              scale: 0.80 + (0.20 * scaleProgress),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

AnimationStyle? furaDialogAnimationStyle(BuildContext context) {
  if (MediaQuery.accessibleNavigationOf(context) ||
      MediaQuery.disableAnimationsOf(context)) {
    return AnimationStyle.noAnimation;
  }
  return const AnimationStyle(
    duration: Duration(milliseconds: 220),
    reverseDuration: Duration(milliseconds: 160),
  );
}

/// Adds Material 3 scale and vertical lift entrance/exit motion to modal
/// [Dialog] and [AlertDialog] routes (which by default only fade in Flutter).
class FuraDialogTransition extends StatelessWidget {
  const FuraDialogTransition({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null ||
        MediaQuery.accessibleNavigationOf(context) ||
        MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final raw = animation.value.clamp(0.0, 1.0);
        final isReversing =
            animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;
        if (isReversing) {
          final curved = Curves.easeInCubic.transform(raw);
          return Transform.translate(
            offset: Offset(0, (1.0 - curved) * 12.0),
            child: Transform.scale(scale: 0.92 + (0.08 * curved), child: child),
          );
        }
        final slideProgress = Curves.easeOutCubic.transform(raw);
        final scaleProgress = Curves.easeOutBack.transform(raw);
        return Transform.translate(
          offset: Offset(0, (1.0 - slideProgress) * 18.0),
          child: Transform.scale(
            scale: 0.88 + (0.12 * scaleProgress),
            child: child,
          ),
        );
      },
    );
  }
}
