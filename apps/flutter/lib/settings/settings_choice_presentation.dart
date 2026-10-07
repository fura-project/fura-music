import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Presentation only. Enum mapping and persistence stay with the Settings row.
class SettingsChoiceOption {
  const SettingsChoiceOption({
    required this.label,
    this.supportingText,
    this.enabled = true,
    this.key,
  });
  final String label;
  final String? supportingText;
  final bool enabled;
  final Key? key;
}

class SettingsChoicePresentation {
  SettingsChoicePresentation._(this.result, this._cancel);
  final Future<int?> result;
  final VoidCallback _cancel;
  void cancel() => _cancel();
}

const _channel = MethodChannel('com.fura/settings_choice');
int _nextRequestId = 0;

SettingsChoicePresentation showSettingsSingleChoice({
  required BuildContext context,
  required String title,
  required List<SettingsChoiceOption> options,
  required int selectedIndex,
  String? footer,
  Key? footerKey,
}) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final id = ++_nextRequestId;
    final theme = Theme.of(context);
    final result = _channel
        .invokeMethod<int>('show', {
          'requestId': id,
          'title': title,
          'options': [
            for (final option in options)
              {
                'label': option.label,
                'supportingText': option.supportingText,
                'enabled': option.enabled,
              },
          ],
          'selectedIndex': selectedIndex,
          'brightness': theme.brightness.name,
          'primary': theme.colorScheme.primary.toARGB32(),
          'footer': footer,
        })
        .then(
          (index) =>
              index != null &&
                  index >= 0 &&
                  index < options.length &&
                  options[index].enabled
              ? index
              : null,
        );
    return SettingsChoicePresentation._(result, () {
      // Disposal is not a new interaction. A missing/detached host cannot
      // dismiss anything, and must never open a Flutter replacement dialog.
      unawaited(
        _channel
            .invokeMethod<void>('dismiss', {'requestId': id})
            .catchError((Object _) {}),
      );
    });
  }

  ModalRoute<int>? ownedRoute;
  var cancelled = false;
  final result = showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    requestFocus: true,
    constraints: BoxConstraints(
      maxWidth: 640,
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (sheetContext) {
      ownedRoute = ModalRoute.of<int>(sheetContext);
      if (cancelled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final route = ownedRoute;
          if (route != null && route.isActive) {
            route.navigator?.removeRoute(route);
          }
        });
      }
      return Theme(
        data: Theme.of(sheetContext)
            .copyWith(listTileTheme: const ListTileThemeData()),
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  Navigator.of(sheetContext).pop();
                  return null;
                },
              ),
            },
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                key: const ValueKey('settings-choice-sheet'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    RadioGroup<int>(
                      groupValue: selectedIndex,
                      onChanged: (index) =>
                          Navigator.of(sheetContext)
                              .pop(index ?? selectedIndex),
                      child: Column(
                        children: [
                          for (var index = 0; index < options.length; index++)
                            RadioListTile<int>(
                              key: options[index].key,
                              value: index,
                              enabled: options[index].enabled,
                              toggleable: true,
                              autofocus: index == selectedIndex,
                              title: Text(options[index].label),
                              subtitle: options[index].supportingText == null
                                  ? null
                                  : Text(options[index].supportingText!),
                            ),
                        ],
                      ),
                    ),
                    if (footer != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                        child: Text(
                          footer,
                          key: footerKey,
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  return SettingsChoicePresentation._(result, () {
    cancelled = true;
    final route = ownedRoute;
    // Never pop a newer/unrelated route. Removal completes this caller only.
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  });
}
