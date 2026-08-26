import 'package:flutter/material.dart';

typedef ConfirmationWrapper = Widget Function(Widget child);

Future<bool> showAdaptiveConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Key cancelKey,
  required Key confirmKey,
  required Key sheetKey,
  required Key dialogKey,
  ConfirmationWrapper? wrapper,
}) async {
  Widget wrap(Widget child) => wrapper?.call(child) ?? child;

  if (MediaQuery.sizeOf(context).width < 600) {
    return await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          builder: (routeContext) => wrap(
            SafeArea(
              key: sheetKey,
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(routeContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Text(message),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          key: cancelKey,
                          onPressed: () =>
                              Navigator.of(routeContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: confirmKey,
                          onPressed: () => Navigator.of(routeContext).pop(true),
                          child: Text(confirmLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  return await showDialog<bool>(
        context: context,
        builder: (routeContext) => wrap(
          AlertDialog(
            key: dialogKey,
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                key: cancelKey,
                onPressed: () => Navigator.of(routeContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: confirmKey,
                onPressed: () => Navigator.of(routeContext).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ),
      ) ??
      false;
}
