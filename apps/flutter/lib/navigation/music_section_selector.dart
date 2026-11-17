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

class MusicSectionSelector<T> extends StatefulWidget {
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
  State<MusicSectionSelector<T>> createState() =>
      _MusicSectionSelectorState<T>();
}

class _MusicSectionSelectorState<T> extends State<MusicSectionSelector<T>>
    with TickerProviderStateMixin {
  late TabController _tabController;

  int get _selectedIndex {
    final index = widget.destinations.indexWhere(
      (destination) => destination.value == widget.selected,
    );
    return index >= 0 ? index : 0;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.destinations.length,
      initialIndex: _selectedIndex,
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(MusicSectionSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedIndex = _selectedIndex;
    if (widget.destinations.length != _tabController.length) {
      _tabController.dispose();
      _tabController = TabController(
        length: widget.destinations.length,
        initialIndex: selectedIndex,
        vsync: this,
      );
      return;
    }
    if (_tabController.index != selectedIndex) {
      _tabController.animateTo(selectedIndex);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.destinations.isEmpty) return const SizedBox.shrink();
    final selectedIndex = _selectedIndex;
    final current = widget.destinations[selectedIndex];
    if (widget.compact) {
      final theme = Theme.of(context);
      final labelStyle = theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      );
      return Semantics(
        container: true,
        label: context.l10n.commonSelectedValue(widget.label, current.label),
        child: TabBar.secondary(
          key: widget.controlKey,
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: theme.colorScheme.outlineVariant.withValues(
            alpha: 0.45,
          ),
          labelStyle: labelStyle,
          unselectedLabelStyle: labelStyle,
          labelPadding: const EdgeInsets.symmetric(horizontal: 14),
          onTap: (index) {
            final target = widget.destinations[index].value;
            final currentSelectedIndex = _selectedIndex;
            if (_tabController.index != currentSelectedIndex) {
              _tabController.index = currentSelectedIndex;
            }
            widget.onSelected(target);
          },
          tabs: [
            for (final destination in widget.destinations)
              Tab(key: destination.itemKey, text: destination.label),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<T>(
        key: widget.controlKey,
        segments: [
          for (final destination in widget.destinations)
            ButtonSegment<T>(
              value: destination.value,
              icon: Icon(destination.icon),
              label: Text(destination.label, key: destination.itemKey),
            ),
        ],
        selected: {widget.selected},
        onSelectionChanged: (selection) => widget.onSelected(selection.single),
      ),
    );
  }
}
