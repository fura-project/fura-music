import 'package:flutter/material.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';

class MusicSectionDestination<T> {
  const MusicSectionDestination({
    required this.value,
    required this.icon,
    required this.label,
    required this.itemKey,
  });

  final T value;
  final IconData icon;
  final String label;
  final Key itemKey;
}

class MusicSectionSelector<T> extends StatelessWidget {
  const MusicSectionSelector({
    required this.controlKey,
    required this.label,
    required this.destinations,
    required this.selected,
    required this.compact,
    required this.onSelected,
    super.key,
  });

  final Key controlKey;
  final String label;
  final List<MusicSectionDestination<T>> destinations;
  final T selected;
  final bool compact;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final current = destinations.singleWhere(
      (destination) => destination.value == selected,
    );
    if (compact) {
      return Semantics(
        label: context.l10n.commonSelectedValue(label, current.label),
        child: DropdownMenu<T>(
          key: controlKey,
          width: 180,
          initialSelection: selected,
          selectOnly: true,
          requestFocusOnTap: true,
          enableSearch: false,
          leadingIcon: Icon(current.icon),
          dropdownMenuEntries: [
            for (final destination in destinations)
              DropdownMenuEntry<T>(
                value: destination.value,
                label: destination.label,
                labelWidget: Text(destination.label, key: destination.itemKey),
                leadingIcon: Icon(destination.icon),
              ),
          ],
          onSelected: (value) {
            if (value != null) onSelected(value);
          },
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<T>(
        key: controlKey,
        segments: [
          for (final destination in destinations)
            ButtonSegment<T>(
              value: destination.value,
              icon: Icon(destination.icon),
              label: Text(destination.label, key: destination.itemKey),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (selection) => onSelected(selection.single),
      ),
    );
  }
}
