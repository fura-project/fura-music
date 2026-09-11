import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

typedef MusicCollectionHeaderBuilder = Widget Function(
  BuildContext context,
  bool desktop,
  double collapseProgress,
);

typedef MusicCollectionBodyBuilder = Widget Function(
  BuildContext context,
  bool desktop,
);

/// Coordinates the scroll-driven header treatment shared by collection pages.
///
/// The Track viewport keeps ownership of its controller and paging behavior.
/// This widget only observes its notifications, converts the leading scroll
/// range into a continuous 0...1 header progress, and reports the discrete
/// Shell title hand-off once the compact header is established.
class MusicCollectionDetailLayout extends StatefulWidget {
  const MusicCollectionDetailLayout({
    required this.headerBuilder,
    required this.bodyBuilder,
    this.onHeaderCollapsedChanged,
    super.key,
  });

  final MusicCollectionHeaderBuilder headerBuilder;
  final MusicCollectionBodyBuilder bodyBuilder;
  final ValueChanged<bool>? onHeaderCollapsedChanged;

  @override
  State<MusicCollectionDetailLayout> createState() =>
      _MusicCollectionDetailLayoutState();
}

class _MusicCollectionDetailLayoutState
    extends State<MusicCollectionDetailLayout> {
  static const double _collapseExtent = 132;
  static const double _shellHandoffProgress = 0.55;

  double _progress = 0;
  bool _reportedCollapsed = false;

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final next = (notification.metrics.pixels / _collapseExtent).clamp(
      0.0,
      1.0,
    );
    final collapsed = next >= _shellHandoffProgress;
    if ((next - _progress).abs() >= 0.002 || collapsed != _reportedCollapsed) {
      setState(() {
        _progress = next;
        _reportedCollapsed = collapsed;
      });
      widget.onHeaderCollapsedChanged?.call(collapsed);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 820;
      return Column(
        children: [
          widget.headerBuilder(context, desktop, _progress),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScroll,
              child: widget.bodyBuilder(context, desktop),
            ),
          ),
        ],
      );
    },
  );
}

/// Shared, continuously compressing hero for Playlist, Album and Ranking.
///
/// The expanded form carries the local page toolbar and full metadata. As the
/// Track viewport scrolls, the toolbar hands its title to the application
/// Shell while artwork, copy spacing and metadata contract into a compact
/// collection identity row instead of disappearing in one frame.
class MusicCollectionDetailHeader extends StatelessWidget {
  const MusicCollectionDetailHeader({
    required this.collapseProgress,
    required this.desktop,
    required this.embedded,
    required this.artwork,
    required this.eyebrow,
    required this.title,
    required this.titleKey,
    required this.summary,
    required this.onBack,
    required this.backKey,
    required this.backTooltip,
    this.toolbarAction,
    this.expandedDetails = const [],
    this.expandedHeight,
    super.key,
  });

  final double collapseProgress;
  final bool desktop;
  final bool embedded;
  final Widget artwork;
  final String eyebrow;
  final String title;
  final Key titleKey;
  final String summary;
  final VoidCallback onBack;
  final Key backKey;
  final String backTooltip;
  final Widget? toolbarAction;
  final List<Widget> expandedDetails;
  final double? expandedHeight;

  @override
  Widget build(BuildContext context) {
    final progress = collapseProgress.clamp(0.0, 1.0);
    final expanded = 1 - progress;
    final horizontal = desktop
        ? MusicSpacing.pageWide
        : MusicSpacing.pageCompact;
    final artworkSize = lerpDouble(desktop ? 156 : 104, 64, progress)!;
    final openHeight = expandedHeight ?? (desktop ? 164 : 120);
    final titleStyle = TextStyle.lerp(
      desktop
          ? Theme.of(context).textTheme.headlineLarge
          : Theme.of(context).textTheme.headlineSmall,
      Theme.of(context).textTheme.titleLarge,
      progress,
    )?.copyWith(fontWeight: FontWeight.w700, height: 1.08);
    return Column(
      key: const ValueKey('collection-detail-adaptive-header'),
      children: [
        if (embedded)
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: expanded,
              child: Opacity(
                opacity: expanded,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontal - 8),
                    child: Row(
                      children: [
                        IconButton(
                          key: backKey,
                          tooltip: backTooltip,
                          onPressed: onBack,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 8),
                        const Spacer(),
                        ?toolbarAction,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            lerpDouble(desktop ? 20 : 12, 8, progress)!,
            horizontal,
            lerpDouble(desktop ? 24 : 18, 8, progress)!,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: MusicSizes.contentMaxWidth,
              ),
              child: SizedBox(
                height: lerpDouble(openHeight, 64, progress),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      key: const ValueKey('collection-detail-artwork'),
                      dimension: artworkSize,
                      child: artwork,
                    ),
                    SizedBox(
                      width: lerpDouble(desktop ? 28 : 18, 14, progress),
                    ),
                    Expanded(
                      child: ClipRect(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRect(
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  heightFactor: expanded,
                                  child: Opacity(
                                    opacity: expanded,
                                    child: Text(
                                      eyebrow,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.1,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: lerpDouble(8, 0, progress)),
                              Semantics(
                                header: true,
                                child: Text(
                                  title,
                                  key: titleKey,
                                  maxLines: progress > 0.55 ? 1 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                              ),
                              SizedBox(height: lerpDouble(9, 3, progress)),
                              Text(
                                summary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    (progress > 0.55
                                            ? Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                            : Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium)
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                              ),
                              if (expandedDetails.isNotEmpty)
                                ClipRect(
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    heightFactor: expanded,
                                    child: Opacity(
                                      opacity: expanded,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: expandedDetails,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
