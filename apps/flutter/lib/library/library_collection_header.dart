import 'package:flutter/material.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class LibraryCollectionHeader extends StatelessWidget {
  const LibraryCollectionHeader({
    required this.title,
    required this.subtitle,
    this.refreshKey,
    this.refreshTooltip,
    this.onRefresh,
    super.key,
  });

  final String title;
  final String subtitle;
  final Key? refreshKey;
  final String? refreshTooltip;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 760;
      final theme = Theme.of(context);
      return Padding(
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
                  Text(
                    title,
                    style:
                        (desktop
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
              IconButton.filledTonal(
                key: refreshKey,
                tooltip: tooltip,
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ],
        ),
      );
    },
  );
}
