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

/// Simple choices use one Flutter M3 route on every platform. Detailed
/// settings are inline disclosures, not clients of this presentation edge.
SettingsChoicePresentation showSettingsSingleChoice({
  required BuildContext context,
  required String title,
  required List<SettingsChoiceOption> options,
  required int selectedIndex,
  String? footer,
  Key? footerKey,
}) {
  ModalRoute<int>? ownedRoute;
  var cancelled = false;
  final result = showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    requestFocus: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    constraints: const BoxConstraints(maxWidth: 520),
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
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
