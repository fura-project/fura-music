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

/// One SDK Material 3 modal route on every platform; the Settings row owns
/// enum mapping, persistence and focus restoration after route removal.
SettingsChoicePresentation showSettingsSingleChoice({
  required BuildContext context,
  required String title,
  required List<SettingsChoiceOption> options,
  required int selectedIndex,
}) {
  ModalRoute<int>? ownedRoute;
  var cancelled = false;
  final result = showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    requestFocus: true,
    // Override Material 3's desktop 640 dp fallback. The SDK route supplies the
    // current window's finite width, including when the window is resized.
    constraints: const BoxConstraints(maxWidth: double.infinity),
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
      return Shortcuts(
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
            child: SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                key: const ValueKey('settings-choice-sheet'),
                primary: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
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
                              autofocus: index == selectedIndex,
                              toggleable: true,
                              title: Text(options[index].label),
                              subtitle: options[index].supportingText == null
                                  ? null
                                  : Text(options[index].supportingText!),
                            ),
                        ],
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
  // The outgoing modal still owns a focus scope when its result completes.
  // Wait for real Overlay removal, not a guessed animation delay.
  final settledResult = result.then((value) async {
    await ownedRoute?.completed;
    return value;
  });
  return SettingsChoicePresentation._(settledResult, () {
    cancelled = true;
    final route = ownedRoute;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  });
}
