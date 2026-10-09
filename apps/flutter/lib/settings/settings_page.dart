import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

enum SettingsSection { appearance, musicService, language, playback }

extension SettingsSectionPresentation on SettingsSection {
  String label(AppLocalizations l10n) => switch (this) {
    SettingsSection.appearance => l10n.settingsAppearanceLabel,
    SettingsSection.musicService => l10n.settingsMusicServiceLabel,
    SettingsSection.language => l10n.settingsLanguageLabel,
    SettingsSection.playback => l10n.settingsPlaybackLabel,
  };

  IconData get icon => switch (this) {
    SettingsSection.appearance => Icons.palette_outlined,
    SettingsSection.musicService => Icons.library_music_outlined,
    SettingsSection.language => Icons.language_rounded,
    SettingsSection.playback => Icons.headphones_outlined,
  };

  String description(AppLocalizations l10n) => switch (this) {
    SettingsSection.appearance => l10n.settingsAppearanceDescription,
    SettingsSection.musicService => l10n.settingsMusicServiceDescription,
    SettingsSection.language => l10n.settingsLanguageDescription,
    SettingsSection.playback => l10n.settingsPlaybackDescription,
  };

  String summary(AppSettings settings, AppLocalizations l10n) => switch (this) {
    SettingsSection.appearance =>
      '${_themeSummary(settings.theme, l10n)} · '
          '${_colorSourceSummary(settings.colorSource, l10n)}',
    SettingsSection.musicService => _providerLabel(
      settings.musicProvider,
      l10n,
    ),
    SettingsSection.language => switch (settings.localePreference) {
      AppLocalePreference.system => l10n.settingsLanguageSummarySystem,
      AppLocalePreference.english => l10n.settingsLanguageSummaryEnglish,
      AppLocalePreference.simplifiedChinese =>
        l10n.settingsLanguageSummarySimplifiedChinese,
    },
    SettingsSection.playback => _qualitySummary(settings.playbackQuality, l10n),
  };

  bool matches(
    String normalizedQuery,
    AppSettings settings,
    AppLocalizations l10n,
  ) {
    if (normalizedQuery.isEmpty) return true;
    final keywords = switch (this) {
      SettingsSection.appearance => l10n.settingsAppearanceSearchKeywords,
      SettingsSection.musicService => l10n.settingsMusicServiceSearchKeywords,
      SettingsSection.language => l10n.settingsLanguageSearchKeywords,
      SettingsSection.playback => l10n.settingsPlaybackSearchKeywords,
    };
    final searchable = <String>[
      label(l10n),
      description(l10n),
      summary(settings, l10n),
      ...keywords.split('|'),
    ];
    return searchable.any(
      (term) => term.toLowerCase().contains(normalizedQuery),
    );
  }
}

String _themeSummary(AppThemePreference theme, AppLocalizations l10n) =>
    switch (theme) {
      AppThemePreference.system => l10n.settingsAppearanceSummarySystem,
      AppThemePreference.light => l10n.settingsAppearanceSummaryLight,
      AppThemePreference.dark => l10n.settingsAppearanceSummaryDark,
    };

String _colorSourceSummary(
  AppColorSourcePreference colorSource,
  AppLocalizations l10n,
) => switch (colorSource) {
  AppColorSourcePreference.system => l10n.settingsColorSourceSystemSummary,
  AppColorSourcePreference.brand => l10n.settingsColorSourceBrandSummary,
};

String _providerLabel(AppMusicProvider provider, AppLocalizations l10n) =>
    switch (provider) {
      AppMusicProvider.qqMusic => l10n.providerQqMusic,
      AppMusicProvider.netEaseCloudMusic => l10n.providerNeteaseCloudMusic,
    };

String _qualitySummary(
  AppPlaybackQualityPreference quality,
  AppLocalizations l10n,
) => switch (quality) {
  AppPlaybackQualityPreference.standard => l10n.playbackQualitySummaryStandard,
  AppPlaybackQualityPreference.high => l10n.playbackQualitySummaryHigh,
  AppPlaybackQualityPreference.lossless => l10n.playbackQualitySummaryLossless,
};

String _lyricAuxiliarySummary(LyricAuxiliaryMode mode, AppLocalizations l10n) =>
    switch (mode) {
      LyricAuxiliaryMode.auto => l10n.lyricsAuxiliaryAuto,
      LyricAuxiliaryMode.translation => l10n.lyricsAuxiliaryTranslation,
      LyricAuxiliaryMode.romanization => l10n.lyricsAuxiliaryPronunciation,
      LyricAuxiliaryMode.off => l10n.lyricsAuxiliaryOff,
    };

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
    this.systemLightColorScheme,
    this.systemDarkColorScheme,
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
  final ColorScheme? systemLightColorScheme;
  final ColorScheme? systemDarkColorScheme;

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
          SnackBar(content: Text(context.l10n.settingsSaveFailure)),
        );
    }
  }

  Future<void> _showCompactSearch() async {
    final section = await showSearch<SettingsSection?>(
      context: context,
      delegate: _SettingsSearchDelegate(widget.settings, context.l10n),
    );
    if (!mounted || section == null) return;
    widget.onCompactSectionSelected(section);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final normalizedQuery = widget.searchQuery.trim().toLowerCase();
    final sections = normalizedQuery.isEmpty
        ? [widget.selectedSection]
        : SettingsSection.values
              .where(
                (section) =>
                    section.matches(normalizedQuery, widget.settings, l10n),
              )
              .toList(growable: false);
    final compactDetail = widget.compactHierarchy && widget.compactSectionOpen;
    final toolbar = AppBar(
      key: const ValueKey('settings-toolbar'),
      centerTitle: widget.compactHierarchy,
      leading: IconButton(
        key: const ValueKey('settings-back'),
        tooltip: l10n.settingsBackTooltip,
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : MusicMotion.stateChange,
        child: Text(
          compactDetail
              ? widget.selectedSection.label(l10n)
              : l10n.settingsTitle,
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
            tooltip: l10n.settingsSearchLabel,
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
    final settingsContent = _SettingsContentTransition(
      key: const ValueKey('settings-content-transition'),
      duration: disableAnimations ? Duration.zero : MusicMotion.stateChange,
      contentKey: ValueKey(contentKey),
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
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
                    l10n.settingsSearchResultsTitle,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: MusicSpacing.itemGap),
                  Text(
                    sections.isEmpty
                        ? l10n.settingsSearchNoMatch(widget.searchQuery.trim())
                        : l10n.settingsSearchMatchSummary(
                            sections.length,
                            widget.searchQuery.trim(),
                          ),
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
      return SafeArea(
        child: Column(
          key: const ValueKey('embedded-settings-page'),
          children: [
            if (widget.showToolbar)
              SizedBox(height: kToolbarHeight, child: toolbar),
            Expanded(child: body),
          ],
        ),
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
      SettingsSection.musicService => _musicServiceSection(context, compact),
      SettingsSection.language => _languageSection(context, compact),
      SettingsSection.playback => _playbackSection(context, compact),
    };
    return content;
  }

  List<Widget> _appearanceSection(BuildContext context, bool compact) {
    final l10n = context.l10n;
    final systemScheme = Theme.of(context).brightness == Brightness.dark
        ? widget.systemDarkColorScheme
        : widget.systemLightColorScheme;
    return [
      _SettingsSectionHeading(
        label: l10n.settingsAppearanceLabel,
        headingKey: const ValueKey('settings-appearance-section'),
      ),
      _SettingsGroup(
        children: [
          _SettingsThemeChoice(
            controlKey: const ValueKey('settings-theme-selector'),
            icon: Icons.brightness_auto_rounded,
            title: l10n.settingsAppearanceCompactLabel,
            current: widget.settings.theme,
            choices: [
              _SettingsChoice(
                key: const ValueKey('settings-theme-system'),
                value: AppThemePreference.system,
                label: l10n.settingsThemeSystem,
              ),
              _SettingsChoice(
                key: const ValueKey('settings-theme-light'),
                value: AppThemePreference.light,
                label: l10n.settingsThemeLight,
              ),
              _SettingsChoice(
                key: const ValueKey('settings-theme-dark'),
                value: AppThemePreference.dark,
                label: l10n.settingsThemeDark,
              ),
            ],
            enabled: !_saving,
            onSelected: (theme) =>
                _save(widget.settings.copyWith(theme: theme)),
          ),
          _SettingsColorDropdown(
            controlKey: const ValueKey('settings-color-source-selector'),
            icon: Icons.palette_outlined,
            title: l10n.settingsColorSourceLabel,
            current: widget.settings.colorSource,
            choices: [
              _SettingsChoice(
                key: const ValueKey('settings-color-source-system'),
                value: AppColorSourcePreference.system,
                label: l10n.settingsColorSourceSystem,
                description: l10n.settingsColorSourceSystemDescription,
              ),
              _SettingsChoice(
                key: const ValueKey('settings-color-source-brand'),
                value: AppColorSourcePreference.brand,
                label: l10n.settingsColorSourceBrand,
                description: l10n.settingsColorSourceBrandDescription(
                  _providerLabel(widget.settings.musicProvider, l10n),
                ),
              ),
            ],
            availability: systemScheme == null
                ? l10n.settingsColorSourceSystemUnavailable
                : l10n.settingsColorSourceSystemAvailable,
            availabilityKey: ValueKey(
              systemScheme == null
                  ? 'settings-system-colors-unavailable'
                  : 'settings-system-colors-available',
            ),
            enabled: !_saving,
            onSelected: (source) =>
                _save(widget.settings.copyWith(colorSource: source)),
          ),
        ],
      ),
    ];
  }

  List<Widget> _musicServiceSection(BuildContext context, bool compact) => [
    _SettingsSectionHeading(
      label: context.l10n.settingsMusicServiceLabel,
      headingKey: const ValueKey('settings-music-service-section'),
    ),
    _SettingsGroup(
      children: [
        _SettingsChoiceTile<AppMusicProvider>(
          controlKey: const ValueKey('settings-provider-selector'),
          icon: Icons.library_music_outlined,
          title: context.l10n.settingsMusicServiceLabel,
          current: widget.settings.musicProvider,
          choices: [
            _SettingsChoice(
              key: const ValueKey('settings-provider-qq-music'),
              value: AppMusicProvider.qqMusic,
              label: context.l10n.providerQqMusic,
            ),
            _SettingsChoice(
              key: const ValueKey('settings-provider-netease'),
              value: AppMusicProvider.netEaseCloudMusic,
              label: context.l10n.providerNeteaseCloudMusic,
            ),
          ],
          enabled: !_saving,
          onSelected: (provider) =>
              _save(widget.settings.copyWith(musicProvider: provider)),
        ),
      ],
    ),
  ];

  List<Widget> _languageSection(BuildContext context, bool compact) => [
    _SettingsSectionHeading(
      label: context.l10n.settingsLanguageLabel,
      headingKey: const ValueKey('settings-language-section'),
    ),
    _SettingsGroup(
      children: [
        _SettingsChoiceTile<AppLocalePreference>(
          controlKey: const ValueKey('settings-language-selector'),
          icon: Icons.language_rounded,
          title: context.l10n.settingsLanguageLabel,
          current: widget.settings.localePreference,
          choices: [
            _SettingsChoice(
              key: const ValueKey('settings-language-system'),
              value: AppLocalePreference.system,
              label: context.l10n.settingsLanguageFollowSystem,
            ),
            _SettingsChoice(
              key: const ValueKey('settings-language-english'),
              value: AppLocalePreference.english,
              label: context.l10n.settingsLanguageEnglish,
            ),
            _SettingsChoice(
              key: const ValueKey('settings-language-simplifiedChinese'),
              value: AppLocalePreference.simplifiedChinese,
              label: context.l10n.settingsLanguageSimplifiedChinese,
            ),
          ],
          enabled: !_saving,
          onSelected: (locale) =>
              _save(widget.settings.copyWith(localePreference: locale)),
        ),
      ],
    ),
  ];

  List<Widget> _playbackSection(BuildContext context, bool compact) => [
    _SettingsSectionHeading(
      label: context.l10n.settingsPlaybackSectionLabel,
      headingKey: const ValueKey('settings-playback-section'),
    ),
    _SettingsGroup(
      children: [
        _SettingsChoiceTile<AppPlaybackQualityPreference>(
          controlKey: const ValueKey('settings-quality-selector'),
          icon: Icons.high_quality_rounded,
          title: context.l10n.settingsPlaybackSectionLabel,
          current: widget.settings.playbackQuality,
          choices: [
            _SettingsChoice(
              key: const ValueKey('settings-quality-standard'),
              value: AppPlaybackQualityPreference.standard,
              label: context.l10n.playbackQualityStandard,
            ),
            _SettingsChoice(
              key: const ValueKey('settings-quality-high'),
              value: AppPlaybackQualityPreference.high,
              label: context.l10n.playbackQualityHigh,
            ),
            _SettingsChoice(
              key: const ValueKey('settings-quality-lossless'),
              value: AppPlaybackQualityPreference.lossless,
              label: context.l10n.playbackQualityLossless,
            ),
          ],
          enabled: !_saving,
          onSelected: (quality) =>
              _save(widget.settings.copyWith(playbackQuality: quality)),
        ),
        _SettingsChoiceTile<LyricAuxiliaryMode>(
          controlKey: const ValueKey('settings-lyric-auxiliary-selector'),
          icon: Icons.lyrics_outlined,
          title: context.l10n.lyricsAuxiliaryMode,
          current: widget.settings.lyricAuxiliaryMode,
          choices: [
            for (final mode in LyricAuxiliaryMode.values)
              _SettingsChoice(
                key: ValueKey('settings-lyric-auxiliary-${mode.name}'),
                value: mode,
                label: _lyricAuxiliarySummary(mode, context.l10n),
              ),
          ],
          enabled: !_saving,
          onSelected: (mode) =>
              _save(widget.settings.copyWith(lyricAuxiliaryMode: mode)),
        ),
      ],
    ),
  ];
}

/// A Material fade-through for peer Settings sections.
///
/// Only one section is mounted at any instant: the old section fades out,
/// then the new section fades and moves in. This avoids the translucent
/// incoming/outgoing page overlap produced by an [AnimatedSwitcher] stack.
class _SettingsContentTransition extends StatefulWidget {
  const _SettingsContentTransition({
    required this.contentKey,
    required this.duration,
    required this.child,
    super.key,
  });

  final Key contentKey;
  final Duration duration;
  final Widget child;

  @override
  State<_SettingsContentTransition> createState() =>
      _SettingsContentTransitionState();
}

class _SettingsContentTransitionState extends State<_SettingsContentTransition>
    with SingleTickerProviderStateMixin {
  static const double _swapPoint = 0.4;

  late final AnimationController _controller;
  late Key _contentKey;
  late Widget _outgoing;
  late Widget _incoming;

  @override
  void initState() {
    super.initState();
    _contentKey = widget.contentKey;
    _outgoing = widget.child;
    _incoming = widget.child;
    _controller = AnimationController(
      vsync: this,
      value: 1,
      duration: widget.duration,
    );
  }

  @override
  void didUpdateWidget(_SettingsContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (widget.contentKey == _contentKey) {
      _incoming = widget.child;
      if (_controller.isDismissed) _outgoing = widget.child;
      return;
    }

    _outgoing = _controller.value < _swapPoint ? _outgoing : _incoming;
    _incoming = widget.child;
    _contentKey = widget.contentKey;
    if (widget.duration == Duration.zero) {
      _controller.value = 1;
    } else {
      unawaited(_controller.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final progress = _controller.value;
      final showingIncoming = progress >= _swapPoint;
      final opacity = showingIncoming
          ? Easing.emphasizedDecelerate.transform(
              ((progress - _swapPoint) / (1 - _swapPoint)).clamp(0, 1),
            )
          : 1 -
                Easing.emphasizedAccelerate.transform(
                  (progress / _swapPoint).clamp(0, 1),
                );
      final slideProgress = showingIncoming
          ? ((progress - _swapPoint) / (1 - _swapPoint)).clamp(0, 1)
          : 1.0;
      return ClipRect(
        child: IgnorePointer(
          ignoring: _controller.isAnimating,
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset((1 - slideProgress) * 18, 0),
              child: KeyedSubtree(
                key: showingIncoming ? _contentKey : null,
                child: showingIncoming ? _incoming : _outgoing,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SettingsChoice<T> {
  const _SettingsChoice({
    required this.value,
    required this.label,
    this.description,
    this.key,
  });
  final T value;
  final String label;
  final String? description;
  final Key? key;
}

class _SettingsSectionHeading extends StatelessWidget {
  const _SettingsSectionHeading({
    required this.label,
    required this.headingKey,
  });
  final String label;
  final Key headingKey;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Semantics(
      header: true,
      child: Text(
        label,
        key: headingKey,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Theme(
    // One quiet surface per section; never one selected-color card per row.
    data: Theme.of(context).copyWith(listTileTheme: const ListTileThemeData()),
    child: Material(
      key: const ValueKey('settings-group'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: MusicRadii.content,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: 4),
            children[index],
          ],
        ],
      ),
    ),
  );
}

/// The Human-reviewed official modal sheet is scoped to Theme only.
class _SettingsThemeChoice extends StatefulWidget {
  const _SettingsThemeChoice({
    required this.controlKey,
    required this.icon,
    required this.title,
    required this.current,
    required this.choices,
    required this.enabled,
    required this.onSelected,
  });
  final Key controlKey;
  final IconData icon;
  final String title;
  final AppThemePreference current;
  final List<_SettingsChoice<AppThemePreference>> choices;
  final bool enabled;
  final Future<void> Function(AppThemePreference) onSelected;
  @override
  State<_SettingsThemeChoice> createState() => _SettingsThemeChoiceState();
}

class _SettingsThemeChoiceState extends State<_SettingsThemeChoice>
    with WidgetsBindingObserver {
  final _focusNode = FocusNode();
  ModalBottomSheetRoute<AppThemePreference>? _route;
  int _revision = 0;
  bool _opening = false;
  bool _focusReturnPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant _SettingsThemeChoice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current ||
        oldWidget.enabled != widget.enabled) {
      _revision++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _returnFocus();
  }

  void _returnFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.enabled || !_focusReturnPending) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      _focusReturnPending = false;
      _focusNode.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _choose(BuildContext sheetContext) async {
    if (!widget.enabled || _opening) return;
    _opening = true;
    final snapshot = widget.current;
    final revision = ++_revision;
    final selected = await showModalBottomSheet<AppThemePreference>(
      context: sheetContext,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) {
        _route =
            ModalRoute.of(context)!
                as ModalBottomSheetRoute<AppThemePreference>;
        void close(AppThemePreference? value) {
          if (!mounted ||
              revision != _revision ||
              widget.current != snapshot ||
              !widget.enabled ||
              !_route!.isCurrent) {
            return;
          }
          Navigator.of(context).pop(value);
        }

        return Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  Navigator.of(context).pop();
                  return null;
                },
              ),
            },
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      RadioGroup<AppThemePreference>(
                        groupValue: snapshot,
                        onChanged: close,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final choice in widget.choices)
                              RadioListTile<AppThemePreference>(
                                key: choice.key,
                                value: choice.value,
                                toggleable: true,
                                title: Text(choice.label),
                                autofocus: choice.value == snapshot,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    // Wait for the SDK route's exit motion before returning row focus.
    await _route?.completed;
    _route = null;
    _opening = false;
    if (!mounted) return;
    if (revision == _revision &&
        widget.enabled &&
        widget.current == snapshot &&
        selected != null &&
        selected != snapshot) {
      await widget.onSelected(selected);
    }
    if (!mounted) return;
    _focusReturnPending = true;
    _returnFocus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final route = _route;
    if (route != null && route.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    // Keep the existing ColorScheme, but use SDK M3 sheet defaults locally.
    data: Theme.of(context)
        .copyWith(bottomSheetTheme: const BottomSheetThemeData()),
    child: Builder(
      builder: (context) => _FuraSettingsRow(
        key: widget.controlKey,
        icon: widget.icon,
        title: widget.title,
        value: widget.choices
            .singleWhere((c) => c.value == widget.current)
            .label,
        valueKey: const ValueKey('settings-theme-selector-current'),
        focusNode: _focusNode,
        enabled: widget.enabled,
        onTap: () => unawaited(_choose(context)),
      ),
    ),
  );
}

/// Other settings retain their existing anchored presentation in this trial.
class _SettingsChoiceTile<T> extends StatefulWidget {
  const _SettingsChoiceTile({
    required this.controlKey,
    required this.icon,
    required this.title,
    required this.current,
    required this.choices,
    required this.onSelected,
    this.currentLabel,
    this.enabled = true,
  });
  final Key controlKey;
  final IconData icon;
  final String title;
  final T current;
  final String? currentLabel;
  final List<_SettingsChoice<T>> choices;
  final Future<void> Function(T) onSelected;
  final bool enabled;
  @override
  State<_SettingsChoiceTile<T>> createState() => _SettingsChoiceTileState<T>();
}

class _SettingsChoiceTileState<T> extends State<_SettingsChoiceTile<T>>
    with WidgetsBindingObserver {
  final _focusNode = FocusNode();
  final _menu = MenuController();
  final _anchorKey = GlobalKey();
  final _valueKey = GlobalKey();
  LocalHistoryEntry? _backEntry;
  bool _disposing = false;
  bool _selecting = false;
  int _revision = 0;
  bool _focusReturnPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _focusReturnPending) {
      _returnFocus();
    }
  }

  void _returnFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.enabled || !_focusReturnPending) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
        return;
      }
      _focusReturnPending = false;
      _focusNode.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didUpdateWidget(covariant _SettingsChoiceTile<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current || !widget.enabled) {
      _revision++;
      if (_menu.isOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _menu.isOpen) _menu.close();
        });
      }
    }
  }

  void _choose() {
    if (!widget.enabled || _selecting) return;
    if (_menu.isOpen) {
      _menu.close();
      return;
    }
    final anchor = _anchorKey.currentContext!.findRenderObject()! as RenderBox;
    final value = _valueKey.currentContext!.findRenderObject()! as RenderBox;
    // Anchor to the real current-value label, not the group's full width.
    // The SDK fits the naturally sized panel inside the available safe area.
    final origin = anchor.globalToLocal(value.localToGlobal(Offset.zero));
    // A fresh popup retires callbacks captured by an earlier popup, even
    // when the authoritative value has not changed (dismiss / reopen).
    setState(() => _revision++);
    _menu.open(position: origin + Offset(0, value.size.height + 4));
  }

  void _opened() {
    final route = ModalRoute.of(context);
    if (route == null) return;
    final entry = LocalHistoryEntry(
      onRemove: () {
        _backEntry = null;
        if (!_disposing && _menu.isOpen) _menu.close();
      },
    );
    _backEntry = entry;
    route.addLocalHistoryEntry(entry);
  }

  void _closed() {
    final entry = _backEntry;
    _backEntry = null;
    entry?.remove();
    if (_disposing) return;
    _focusReturnPending = true;
    _returnFocus();
  }

  Future<void> _select(T value, T snapshot, int revision) async {
    if (!mounted ||
        !widget.enabled ||
        _selecting ||
        revision != _revision ||
        widget.current != snapshot ||
        value == snapshot) {
      return;
    }
    _selecting = true;
    try {
      await widget.onSelected(value);
      if (!mounted) return;
      _focusReturnPending = true;
      _returnFocus();
    } finally {
      _selecting = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposing = true;
    _backEntry?.remove();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.choices.singleWhere(
      (choice) => choice.value == widget.current,
    );
    final snapshot = widget.current;
    final revision = _revision;
    return MenuAnchor(
      key: _anchorKey,
      controller: _menu,
      childFocusNode: _focusNode,
      // Constrain the SDK's intrinsic panel rather than clipping an
      // unconstrained natural-width menu at large text / compact widths.
      crossAxisUnconstrained: false,
      consumeOutsideTap: true,
      onOpen: _opened,
      onClose: _closed,
      style: MenuStyle(
        minimumSize: const WidgetStatePropertyAll(Size(160, 0)),
        maximumSize: WidgetStatePropertyAll(
          Size(
            (MediaQuery.sizeOf(context).width - 32).clamp(0, 320),
            double.infinity,
          ),
        ),
      ),
      menuChildren: [
        for (final choice in widget.choices)
          MenuItemButton(
            key: choice.key,
            autofocus: choice.value == snapshot,
            requestFocusOnHover: false,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 48)),
            ),
            leadingIcon: SizedBox(
              width: 24,
              child: choice.value == snapshot ? const Icon(Icons.check) : null,
            ),
            onPressed: widget.enabled
                ? () => unawaited(_select(choice.value, snapshot, revision))
                : null,
            // Put the selected flag inside the SDK's MergeSemantics owner.
            // An outer flag becomes a separate, unlabelled semantic node.
            child: Semantics(
              selected: choice.value == snapshot,
              child: Text(choice.label),
            ),
          ),
      ],
      child: _FuraSettingsRow(
        key: widget.controlKey,
        icon: widget.icon,
        title: widget.title,
        value: widget.currentLabel ?? selected.label,
        valueKey: ValueKey('${(widget.controlKey as ValueKey).value}-current'),
        valueAnchorKey: _valueKey,
        enabled: widget.enabled,
        focusNode: _focusNode,
        onTap: _choose,
      ),
    );
  }
}

/// Settings-specific spacing/state grammar, not default ListTile composition.
class _FuraSettingsRow extends StatelessWidget {
  const _FuraSettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.valueKey,
    required this.focusNode,
    required this.onTap,
    this.valueAnchorKey,
    this.enabled = true,
    super.key,
  });
  final IconData icon;
  final String title, value;
  final Key valueKey;
  final bool enabled;
  final FocusNode focusNode;
  final VoidCallback? onTap;
  final Key? valueAnchorKey;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.bodyLarge!.copyWith(
      color: enabled ? theme.colorScheme.onSurface : theme.disabledColor,
    );
    final valueStyle = theme.textTheme.bodyMedium!.copyWith(
      color: enabled ? theme.colorScheme.onSurfaceVariant : theme.disabledColor,
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: Focus(
        canRequestFocus: false,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            focusNode: focusNode,
            onTap: enabled ? onTap : null,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final inline = _fitsInline(
                  context,
                  constraints.maxWidth,
                  title,
                  titleStyle,
                  value,
                  valueStyle,
                );
                final valueText = KeyedSubtree(
                  key: valueAnchorKey,
                  child: Text(value, key: valueKey, style: valueStyle),
                );
                return ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      12,
                      16,
                      12,
                    ),
                    child: Row(
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            icon,
                            size: 24,
                            color: enabled
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.disabledColor,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: inline
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: Text(title, style: titleStyle),
                                    ),
                                    const SizedBox(width: 16),
                                    valueText,
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(title, style: titleStyle),
                                    const SizedBox(height: 4),
                                    valueText,
                                  ],
                                ),
                        ),
                        ...[
                          const SizedBox(width: 16),
                          ExcludeSemantics(
                            child: Icon(
                              Icons.expand_more_rounded,
                              size: 24,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Only Color Source uses the official select-only DropdownMenu.
class _SettingsColorDropdown extends StatefulWidget {
  const _SettingsColorDropdown({
    required this.controlKey,
    required this.icon,
    required this.title,
    required this.current,
    required this.choices,
    required this.availability,
    required this.availabilityKey,
    required this.enabled,
    required this.onSelected,
  });
  final Key controlKey;
  final IconData icon;
  final String title, availability;
  final AppColorSourcePreference current;
  final List<_SettingsChoice<AppColorSourcePreference>> choices;
  final Key availabilityKey;
  final bool enabled;
  final Future<void> Function(AppColorSourcePreference) onSelected;
  @override
  State<_SettingsColorDropdown> createState() => _SettingsColorDropdownState();
}

class _SettingsColorDropdownState extends State<_SettingsColorDropdown> {
  final _focusNode = FocusNode();
  int _revision = 0;
  bool _selecting = false;

  @override
  void didUpdateWidget(covariant _SettingsColorDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current ||
        oldWidget.enabled != widget.enabled) {
      _revision++;
    }
  }

  Future<void> _select(
    AppColorSourcePreference? value,
    AppColorSourcePreference snapshot,
    int revision,
  ) async {
    if (!mounted ||
        !widget.enabled ||
        _selecting ||
        value == null ||
        value == snapshot ||
        widget.current != snapshot ||
        revision != _revision) {
      return;
    }
    _selecting = true;
    _revision++;
    try {
      await widget.onSelected(value);
    } finally {
      _selecting = false;
      // Recreate SDK display state from the authoritative owner after rollback,
      // rather than retaining DropdownMenu's optimistic selected label.
      if (mounted) setState(() => _revision++);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = widget.current;
    final revision = _revision;
    double measure(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: theme.textTheme.bodyLarge),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.localeOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final preferredWidth =
        widget.choices
            .map((c) => measure(c.label))
            .reduce((a, b) => a > b ? a : b) +
        80;
    return Padding(
      key: widget.controlKey,
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = (constraints.maxWidth - 40).clamp(
            0.0,
            double.infinity,
          );
          final controlWidth = preferredWidth.clamp(0.0, available);
          final inline = measure(widget.title) + 16 + controlWidth <= available;
          final dropdown = Theme(
            // Reset only this representative selector's presentation overrides.
            // SDK M3 defaults + the real project ColorScheme match the reference.
            data: theme.copyWith(
              dropdownMenuTheme: const DropdownMenuThemeData(),
              menuTheme: const MenuThemeData(),
              inputDecorationTheme: const InputDecorationThemeData(),
            ),
            child: Semantics(
              label: widget.title,
              child: DropdownMenu<AppColorSourcePreference>(
                key: ValueKey('settings-color-dropdown-$revision'),
                width: controlWidth,
                focusNode: _focusNode,
                selectOnly: true,
                enableSearch: false,
                enableFilter: false,
                requestFocusOnTap: true,
                enabled: widget.enabled,
                initialSelection: snapshot,
                inputDecorationTheme: const InputDecorationThemeData(
                  filled: true,
                ),
                dropdownMenuEntries: [
                  for (final choice in widget.choices)
                    DropdownMenuEntry(
                      value: choice.value,
                      label: choice.label,
                      labelWidget: Text(choice.label, key: choice.key),
                    ),
                ],
                onSelected: (value) =>
                    unawaited(_select(value, snapshot, revision)),
              ),
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Icon(
                      widget.icon,
                      size: 24,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: inline
                        ? Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.title,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                              const SizedBox(width: 16),
                              dropdown,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: theme.textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 8),
                              dropdown,
                            ],
                          ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 40, top: 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      widget.availability,
                      key: widget.availabilityKey,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    _SettingsPalettePreview(scheme: theme.colorScheme),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Measure actual localized styles/scaler including our icon/padding/gaps.
bool _fitsInline(
  BuildContext context,
  double width,
  String title,
  TextStyle titleStyle,
  String value,
  TextStyle valueStyle,
) {
  double measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.localeOf(context),
    )..layout();
    final result = painter.width;
    painter.dispose();
    return result;
  }

  return width >= 560 &&
      measure(title, titleStyle) + measure(value, valueStyle) + 144 <= width;
}

class _SettingsPalettePreview extends StatelessWidget {
  const _SettingsPalettePreview({required this.scheme});
  final ColorScheme scheme;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Wrap(
      key: const ValueKey('settings-color-palette-preview'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final color in [
          scheme.primary,
          scheme.secondary,
          scheme.tertiary,
          scheme.primaryContainer,
          scheme.surfaceContainerHighest,
        ])
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
      ],
    ),
  );
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
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        key: const ValueKey('settings-compact-menu-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              l10n.settingsChooseCategory,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          Material(
            type: MaterialType.transparency,
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
                    summary: SettingsSection.values[index].summary(
                      settings,
                      l10n,
                    ),
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
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.settingsCategorySemantics(
        section.label(l10n),
        section.description(l10n),
        summary,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Icon(section.icon, color: colors.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.label(l10n),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
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
  _SettingsSearchDelegate(this.settings, this.l10n)
    : super(searchFieldLabel: l10n.settingsSearchLabel);

  final AppSettings settings;
  final AppLocalizations l10n;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        key: const ValueKey('settings-compact-search-clear'),
        tooltip: l10n.commonClearSearch,
        onPressed: () => query = '',
        icon: const Icon(Icons.close_rounded),
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    key: const ValueKey('settings-compact-search-back'),
    tooltip: l10n.settingsBackToSettingsTooltip,
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
        .where((section) => section.matches(normalizedQuery, settings, l10n))
        .toList(growable: false);
    if (sections.isEmpty) {
      return Center(
        key: const ValueKey('settings-compact-search-empty'),
        child: Padding(
          padding: const EdgeInsets.all(MusicSpacing.page),
          child: Text(
            l10n.settingsSearchNoMatch(query.trim()),
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
            summary: section.summary(settings, l10n),
            onTap: () => close(context, section),
          ),
        );
      },
    );
  }
}
