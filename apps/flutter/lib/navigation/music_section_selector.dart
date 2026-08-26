import 'package:flutter/material.dart';

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
      return MenuAnchor(
        menuChildren: [
          for (final destination in destinations)
            MenuItemButton(
              key: destination.itemKey,
              leadingIcon: Icon(destination.icon),
              trailingIcon: destination.value == selected
                  ? const Icon(Icons.check_rounded)
                  : null,
              onPressed: () => onSelected(destination.value),
              child: Text(destination.label),
            ),
        ],
        builder: (context, controller, _) => OutlinedButton.icon(
          key: controlKey,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: Icon(current.icon),
          label: Text('$label: ${current.label}'),
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
