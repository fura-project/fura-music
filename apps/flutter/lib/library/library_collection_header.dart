import 'package:flutter/material.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class LibraryCollectionHeader extends StatelessWidget {
  const LibraryCollectionHeader({
    required this.title,
    required this.subtitle,
    this.refreshKey,
    this.refreshTooltip,
    this.onRefresh,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String subtitle;
  final Key? refreshKey;
  final String? refreshTooltip;
  final VoidCallback? onRefresh;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      final theme = Theme.of(context);
      final editorial = context.editorialTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              desktop ? MusicSpacing.pageWide : MusicSpacing.pageCompact,
              MusicSpacing.contentGap,
              desktop ? MusicSpacing.pageWide : MusicSpacing.pageCompact,
              MusicSpacing.contentGap,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (editorial.isEditorial) ...[
                        Text(
                          '01',
                          style: editorial.eyebrow(theme.textTheme.labelSmall),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        title,
                        style: editorial.isEditorial
                            ? editorial.serif(
                                desktop
                                    ? theme.textTheme.headlineLarge
                                    : theme.textTheme.headlineSmall,
                                fontWeight: FontWeight.w500,
                                color: editorial.inkPrimary,
                              )
                            : (desktop
                                      ? theme.textTheme.headlineMedium
                                      : theme.textTheme.headlineSmall)
                                  ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: MusicSpacing.itemGap),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (refreshTooltip case final tooltip?) ...[
                  const SizedBox(width: MusicSpacing.contentGap),
                  editorial.isEditorial
                      ? IconButton.outlined(
                          key: refreshKey,
                          tooltip: tooltip,
                          onPressed: onRefresh,
                          style: IconButton.styleFrom(
                            side: BorderSide(color: editorial.ruleStrong),
                            shape: RoundedRectangleBorder(
                              borderRadius: editorial.controlRadius,
                            ),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                        )
                      : IconButton.filledTonal(
                          key: refreshKey,
                          tooltip: tooltip,
                          onPressed: onRefresh,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                ],
                ...actions,
              ],
            ),
          ),
          if (editorial.isEditorial)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: desktop
                    ? MusicSpacing.pageWide
                    : MusicSpacing.pageCompact,
              ),
              child: Divider(height: 1, color: editorial.hairline),
            ),
        ],
      );
    },
  );
}
