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

/// One cross-platform route owner; all visual composition belongs to Fura.
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
    showDragHandle: false,
    useSafeArea: true,
    isScrollControlled: true,
    requestFocus: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    constraints: const BoxConstraints(maxWidth: 480),
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
          child: FuraChoiceSheet(
            title: title,
            options: options,
            selectedIndex: selectedIndex,
            onSelected: (index) => Navigator.of(sheetContext).pop(index),
          ),
        ),
      );
    },
  );
  // Navigator's result completes at pop start, while the outgoing modal still
  // owns a focus scope. Return only after its real Overlay removal; otherwise
  // late modal teardown can overwrite the triggering row's restored focus.
  final settledResult = result.then((value) async {
    await ownedRoute?.completed;
    return value;
  });
  return SettingsChoicePresentation._(settledResult, () {
    cancelled = true;
    final route = ownedRoute;
    // Cancel only our route, not a newer/unrelated one.
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  });
}

/// Content-driven M3 bottom dialog, independent of ListTile/BottomSheet theme.
class FuraChoiceSheet extends StatelessWidget {
  const FuraChoiceSheet({
    required this.title,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });
  final String title;
  final List<SettingsChoiceOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('settings-choice-sheet'),
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  height: 24,
                  child: Center(
                    child: Container(
                      key: const ValueKey('settings-choice-handle'),
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleLarge),
                ),
              ),
              RadioGroup<int>(
                groupValue: selectedIndex,
                onChanged: (index) => onSelected(index ?? selectedIndex),
                child: Column(
                  children: [
                    for (var index = 0; index < options.length; index++)
                      FuraChoiceRow<int>(
                        key: options[index].key,
                        value: index,
                        label: options[index].label,
                        supportingText: options[index].supportingText,
                        enabled: options[index].enabled,
                        autofocus: index == selectedIndex,
                        onSelected: () => onSelected(index),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Explicit choice grammar. Selection is the Radio, never a filled row.
/// RadioGroup retains standard keyboard traversal and checked semantics.
class FuraChoiceRow<T> extends StatelessWidget {
  const FuraChoiceRow({
    required this.value,
    required this.label,
    required this.onSelected,
    this.supportingText,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    super.key,
  });
  final T value;
  final String label;
  final String? supportingText;
  final VoidCallback onSelected;
  final bool enabled, autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? onSelected : null,
        canRequestFocus: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 24, 4),
            child: Row(
              children: [
                Radio<T>(
                  value: value,
                  enabled: enabled,
                  toggleable: true,
                  autofocus: autofocus,
                  focusNode: focusNode,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: enabled
                              ? theme.colorScheme.onSurface
                              : theme.disabledColor,
                        ),
                      ),
                      if (supportingText != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          supportingText!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
