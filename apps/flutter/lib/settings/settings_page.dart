import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

enum SettingsSection { appearance, playback }

extension SettingsSectionPresentation on SettingsSection {
  String get label => switch (this) {
    SettingsSection.appearance => 'Appearance',
    SettingsSection.playback => 'Playback',
  };

  IconData get icon => switch (this) {
    SettingsSection.appearance => Icons.palette_outlined,
    SettingsSection.playback => Icons.headphones_outlined,
  };

  String get description => switch (this) {
    SettingsSection.appearance => 'Theme mode and system appearance',
    SettingsSection.playback => 'Streaming quality for QQ Music',
  };

  String summary(AppSettings settings) => switch (this) {
    SettingsSection.appearance => switch (settings.theme) {
      AppThemePreference.system => 'Following the system theme',
      AppThemePreference.light => 'Light theme',
      AppThemePreference.dark => 'Dark theme',
    },
    SettingsSection.playback => switch (settings.playbackQuality) {
      AppPlaybackQualityPreference.standard => 'Standard quality',
      AppPlaybackQualityPreference.high => 'High quality',
    },
  };

  bool matches(String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    final terms = switch (this) {
      SettingsSection.appearance => const [
        'appearance',
        'theme',
        'system',
        'light',
        'dark',
        'color',
      ],
      SettingsSection.playback => const [
        'playback',
        'quality',
        'audio',
        'standard',
        'high',
        'music source',
      ],
    };
    return terms.any((term) => term.contains(normalizedQuery));
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settings,
    required this.onSettingsChanged,
    required this.onBack,
    required this.onCompactSectionSelected,
    this.selectedSection = SettingsSection.appearance,
    this.compactSectionOpen = false,
    this.compactHierarchy = false,
    this.searchQuery = '',
    this.embedded = false,
    this.showToolbar = true,
    super.key,
  });

  final AppSettings settings;
  final Future<AppSettingsWriteResult> Function(AppSettings settings)
  onSettingsChanged;
  final VoidCallback onBack;
  final ValueChanged<SettingsSection> onCompactSectionSelected;
  final SettingsSection selectedSection;
  final bool compactSectionOpen;
  final bool compactHierarchy;
  final String searchQuery;
  final bool embedded;
  final bool showToolbar;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _saving = false;

  Future<void> _save(AppSettings settings) async {
    if (_saving || settings == widget.settings) return;
    setState(() => _saving = true);
    final result = await widget.onSettingsChanged(settings);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result == AppSettingsWriteResult.storageUnavailable) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Couldn’t save settings on this device.'),
          ),
        );
    }
  }

  Future<void> _showCompactSearch() async {
    final section = await showSearch<SettingsSection?>(
      context: context,
      delegate: _SettingsSearchDelegate(widget.settings),
    );
    if (!mounted || section == null) return;
    widget.onCompactSectionSelected(section);
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = widget.searchQuery.trim().toLowerCase();
    final sections = normalizedQuery.isEmpty
        ? [widget.selectedSection]
        : SettingsSection.values
              .where((section) => section.matches(normalizedQuery))
              .toList(growable: false);
    final compactDetail = widget.compactHierarchy && widget.compactSectionOpen;
    final toolbar = AppBar(
      key: const ValueKey('settings-toolbar'),
      centerTitle: widget.compactHierarchy,
      leading: IconButton(
        key: const ValueKey('settings-back'),
        tooltip: 'Back',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : MusicMotion.stateChange,
        child: Text(
          compactDetail ? widget.selectedSection.label : 'Settings',
          key: ValueKey(
            compactDetail
                ? 'settings-compact-title-${widget.selectedSection.name}'
                : 'settings-compact-title-menu',
          ),
        ),
      ),
      actions: [
        if (widget.compactHierarchy && !compactDetail)
          IconButton(
            key: const ValueKey('settings-compact-search'),
            tooltip: 'Search settings',
            onPressed: () => unawaited(_showCompactSearch()),
            icon: const Icon(Icons.search_rounded),
          ),
      ],
    );
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final contentKey = normalizedQuery.isEmpty
        ? 'section-${widget.selectedSection.name}'
        : 'search-${sections.map((section) => section.name).join('-')}';
    final settingsContent = AnimatedSwitcher(
      key: const ValueKey('settings-content-transition'),
      duration: disableAnimations ? Duration.zero : MusicMotion.stateChange,
      switchInCurve: Easing.emphasizedDecelerate,
      switchOutCurve: Easing.emphasizedAccelerate,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.025, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: SafeArea(
        key: ValueKey(contentKey),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              key: const ValueKey('settings-content'),
              padding: const EdgeInsets.fromLTRB(
                MusicSpacing.page,
                MusicSpacing.contentGap,
                MusicSpacing.page,
                MusicSpacing.page,
              ),
              children: [
                if (normalizedQuery.isNotEmpty) ...[
                  Text(
                    'Search results',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: MusicSpacing.itemGap),
                  Text(
                    sections.isEmpty
                        ? 'No settings match “${widget.searchQuery.trim()}”.'
                        : '${sections.length} ${sections.length == 1 ? 'section' : 'sections'} match “${widget.searchQuery.trim()}”.',
                    key: ValueKey(
                      sections.isEmpty
                          ? 'settings-search-empty'
                          : 'settings-search-summary',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: MusicSpacing.section),
                ],
                for (var index = 0; index < sections.length; index++) ...[
                  if (index > 0) const SizedBox(height: MusicSpacing.section),
                  ..._section(
                    context,
                    sections[index],
                    compact: widget.compactHierarchy,
                  ),
                ],
                if (_saving) ...[
                  const SizedBox(height: MusicSpacing.contentGap),
                  const LinearProgressIndicator(
                    key: ValueKey('settings-save-progress'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final body = widget.compactHierarchy
        ? AnimatedSwitcher(
            key: const ValueKey('settings-compact-level-transition'),
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 300),
            switchInCurve: Easing.emphasizedDecelerate,
            switchOutCurve: Easing.emphasizedAccelerate,
            transitionBuilder: (child, animation) {
              final detail =
                  child.key == const ValueKey('settings-compact-detail');
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: detail
                        ? const Offset(0.12, 0)
                        : const Offset(-0.06, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: compactDetail
                ? KeyedSubtree(
                    key: const ValueKey('settings-compact-detail'),
                    child: settingsContent,
                  )
                : _CompactSettingsMenu(
                    key: const ValueKey('settings-compact-menu'),
                    settings: widget.settings,
                    onSelected: widget.onCompactSectionSelected,
                  ),
          )
        : settingsContent;
    if (widget.embedded) {
      return Column(
        key: const ValueKey('embedded-settings-page'),
        children: [
          if (widget.showToolbar)
            SizedBox(height: kToolbarHeight, child: toolbar),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(appBar: toolbar, body: body);
  }

  List<Widget> _section(
    BuildContext context,
    SettingsSection section, {
    required bool compact,
  }) {
    final content = switch (section) {
      SettingsSection.appearance => _appearanceSection(context, compact),
      SettingsSection.playback => _playbackSection(context, compact),
    };
    if (!compact) return content;
    return [
      Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: MusicRadii.content,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(MusicSpacing.contentGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: content,
          ),
        ),
      ),
    ];
  }

  List<Widget> _appearanceSection(BuildContext context, bool compact) => [
    Text(
      compact ? 'Theme mode' : 'Appearance',
      key: const ValueKey('settings-appearance-section'),
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: MusicSpacing.itemGap),
    Text(
      'Choose how fura music follows your system appearance.',
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
    const SizedBox(height: MusicSpacing.contentGap),
    SegmentedButton<AppThemePreference>(
      key: const ValueKey('settings-theme-selector'),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: AppThemePreference.system,
          icon: Icon(Icons.brightness_auto_rounded),
          label: Text('System'),
        ),
        ButtonSegment(
          value: AppThemePreference.light,
          icon: Icon(Icons.light_mode_outlined),
          label: Text('Light'),
        ),
        ButtonSegment(
          value: AppThemePreference.dark,
          icon: Icon(Icons.dark_mode_outlined),
          label: Text('Dark'),
        ),
      ],
      selected: {widget.settings.theme},
      onSelectionChanged: _saving
          ? null
          : (selection) => unawaited(
              _save(widget.settings.copyWith(theme: selection.single)),
            ),
    ),
  ];

  List<Widget> _playbackSection(BuildContext context, bool compact) => [
    Text(
      compact ? 'Audio quality' : 'Playback quality',
      key: const ValueKey('settings-playback-section'),
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: MusicSpacing.itemGap),
    Text(
      'This preference is used the next time a Track resolves a playable QQ Music source.',
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
    const SizedBox(height: MusicSpacing.contentGap),
    SegmentedButton<AppPlaybackQualityPreference>(
      key: const ValueKey('settings-quality-selector'),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: AppPlaybackQualityPreference.standard,
          icon: Icon(Icons.music_note_rounded),
          label: Text('Standard'),
        ),
        ButtonSegment(
          value: AppPlaybackQualityPreference.high,
          icon: Icon(Icons.high_quality_rounded),
          label: Text('High'),
        ),
      ],
      selected: {widget.settings.playbackQuality},
      onSelectionChanged: _saving
          ? null
          : (selection) => unawaited(
              _save(
                widget.settings.copyWith(playbackQuality: selection.single),
              ),
            ),
    ),
  ];
}

class _CompactSettingsMenu extends StatelessWidget {
  const _CompactSettingsMenu({
    required this.settings,
    required this.onSelected,
    super.key,
  });

  final AppSettings settings;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        key: const ValueKey('settings-compact-menu-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Choose a settings category',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          Material(
            color: colors.surfaceContainerLow,
            borderRadius: MusicRadii.content,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < SettingsSection.values.length;
                  index++
                ) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 68,
                      color: colors.outlineVariant,
                    ),
                  _CompactSettingsMenuTile(
                    key: ValueKey(
                      'settings-compact-${SettingsSection.values[index].name}',
                    ),
                    section: SettingsSection.values[index],
                    summary: SettingsSection.values[index].summary(settings),
                    onTap: () => onSelected(SettingsSection.values[index]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSettingsMenuTile extends StatelessWidget {
  const _CompactSettingsMenuTile({
    required this.section,
    required this.summary,
    required this.onTap,
    super.key,
  });

  final SettingsSection section;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '${section.label}. ${section.description}. $summary',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: MusicRadii.control,
                ),
                child: Icon(section.icon, color: colors.onSecondaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSearchDelegate extends SearchDelegate<SettingsSection?> {
  _SettingsSearchDelegate(this.settings)
    : super(searchFieldLabel: 'Search settings');

  final AppSettings settings;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        key: const ValueKey('settings-compact-search-clear'),
        tooltip: 'Clear search',
        onPressed: () => query = '',
        icon: const Icon(Icons.close_rounded),
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    key: const ValueKey('settings-compact-search-back'),
    tooltip: 'Back to settings',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _buildMatches(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildMatches(context);

  Widget _buildMatches(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final sections = SettingsSection.values
        .where((section) => section.matches(normalizedQuery))
        .toList(growable: false);
    if (sections.isEmpty) {
      return Center(
        key: const ValueKey('settings-compact-search-empty'),
        child: Padding(
          padding: const EdgeInsets.all(MusicSpacing.page),
          child: Text(
            'No settings match “${query.trim()}”.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      key: const ValueKey('settings-compact-search-results'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final section = sections[index];
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: MusicRadii.content,
          clipBehavior: Clip.antiAlias,
          child: _CompactSettingsMenuTile(
            key: ValueKey('settings-compact-search-result-${section.name}'),
            section: section,
            summary: section.summary(settings),
            onTap: () => close(context, section),
          ),
        );
      },
    );
  }
}
