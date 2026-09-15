import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

/// Presents a full-height, edge-aligned Material 3 modal on wide layouts.
///
/// The caller's Theme is captured deliberately so artwork-derived now-playing
/// colors survive the root Navigator boundary instead of falling back to the
/// app-level brand or system palette.
Future<T?> showAdaptiveSideSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required Key surfaceKey,
  double width = 560,
}) {
  final capturedTheme = Theme.of(context);
  final mediaQuery = MediaQuery.of(context);
  final direction = Directionality.of(context);
  final colors = capturedTheme.colorScheme;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: colors.scrim.withValues(alpha: 0.42),
    transitionDuration: mediaQuery.disableAnimations
        ? Duration.zero
        : MusicMotion.stateChange,
    pageBuilder: (routeContext, _, _) {
      final availableWidth = MediaQuery.sizeOf(routeContext).width - 24;
      return Theme(
        data: capturedTheme,
        child: SafeArea(
          minimum: const EdgeInsets.all(12),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SizedBox(
              width: math.min(width, availableWidth),
              height: double.infinity,
              child: Material(
                key: surfaceKey,
                color: colors.surfaceContainerLow,
                surfaceTintColor: colors.surfaceTint,
                elevation: 3,
                shadowColor: colors.shadow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                child: Builder(builder: builder),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Easing.emphasizedDecelerate,
        reverseCurve: Easing.emphasizedAccelerate,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(direction == TextDirection.ltr ? 0.12 : -0.12, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
