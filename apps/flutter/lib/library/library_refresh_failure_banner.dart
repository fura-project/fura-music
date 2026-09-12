import 'package:flutter/material.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';

class LibraryRefreshFailureBanner extends StatelessWidget {
  const LibraryRefreshFailureBanner({
    required this.message,
    required this.canRetry,
    required this.onRetry,
    required this.onDismiss,
    super.key,
  });

  final String message;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: MaterialBanner(
      content: Text(message),
      leading: const Icon(Icons.sync_problem_rounded),
      actions: [
        if (canRetry)
          TextButton(
            key: const ValueKey('library-refresh-retry'),
            onPressed: onRetry,
            child: Text(context.l10n.commonRetry),
          ),
        IconButton(
          key: const ValueKey('library-refresh-dismiss'),
          tooltip: context.l10n.libraryRefreshDismissTooltip,
          onPressed: onDismiss,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}
