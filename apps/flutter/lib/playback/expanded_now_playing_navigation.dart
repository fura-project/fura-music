import 'package:flutter/widgets.dart';

/// Presentation-only entry point for the one retained expanded now-playing
/// surface owned by the authenticated application page.
class ExpandedNowPlayingNavigation extends InheritedWidget {
  const ExpandedNowPlayingNavigation({
    required this.onOpen,
    required super.child,
    super.key,
  });

  final VoidCallback onOpen;

  static ExpandedNowPlayingNavigation? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ExpandedNowPlayingNavigation>();

  @override
  bool updateShouldNotify(ExpandedNowPlayingNavigation oldWidget) =>
      onOpen != oldWidget.onOpen;
}
