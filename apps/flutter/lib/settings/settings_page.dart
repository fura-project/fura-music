import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/settings_choice_presentation.dart';
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
          _SettingsChoiceTile<AppThemePreference>(
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
          _SettingsColorDisclosure(
            controlKey: const ValueKey('settings-color-source-selector'),
            icon: Icons.palette_outlined,
            title: l10n.settingsColorSourceLabel,
            current: widget.settings.colorSource,
            currentLabel: _colorSourceSummary(
              widget.settings.colorSource,
              l10n,
            ),
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

/// One interaction grammar on pointer and touch platforms. The standard modal
/// route owns dismissal/motion; the existing Settings owner owns persistence.
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
  bool _sheetOpen = false;
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

  SettingsChoicePresentation? _presentation;

  Future<void> _choose() async {
    if (!widget.enabled || _sheetOpen) return;
    _sheetOpen = true;
    _focusNode.unfocus();
    final current = widget.current;
    final values = [for (final choice in widget.choices) choice.value];
    try {
      final presentation = showSettingsSingleChoice(
        context: context,
        title: widget.title,
        selectedIndex: values.indexOf(current),
        options: [
          for (final choice in widget.choices)
            SettingsChoiceOption(
              label: choice.label,
              supportingText: choice.description,
              key: choice.key,
            ),
        ],
      );
      _presentation = presentation;
      final index = await presentation.result;
      if (!mounted || _presentation != presentation) return;
      // An external update while a dialog was open makes its snapshot stale.
      if (widget.enabled &&
          widget.current == current &&
          index != null &&
          index >= 0 &&
          index < values.length &&
          values[index] != current) {
        await widget.onSelected(values[index]);
      }
      if (!mounted) return;
      _focusReturnPending = true;
      // Saving disables the row and revokes its focus. Restore only after
      // the existing owner finishes and the enabled row has been rebuilt.
      _returnFocus();
    } finally {
      _sheetOpen = false;
      _presentation = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presentation?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.choices.singleWhere(
      (choice) => choice.value == widget.current,
    );
    final theme = Theme.of(context);
    final value = widget.currentLabel ?? selected.label;
    final titleStyle = theme.textTheme.bodyLarge!.copyWith(
      color: widget.enabled ? theme.colorScheme.onSurface : theme.disabledColor,
    );
    final valueStyle = theme.textTheme.bodyMedium!.copyWith(
      color: widget.enabled
          ? theme.colorScheme.onSurfaceVariant
          : theme.disabledColor,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline = _fitsInline(
          context,
          constraints.maxWidth,
          widget.title,
          titleStyle,
          value,
          valueStyle,
        );
        final valueText = Text(
          value,
          key: ValueKey('${(widget.controlKey as ValueKey).value}-current'),
          style: valueStyle,
        );
        return ListTile(
          key: widget.controlKey,
          focusNode: _focusNode,
          enabled: widget.enabled,
          leading: Icon(
            widget.icon,
            color: widget.enabled
                ? theme.colorScheme.onSurfaceVariant
                : theme.disabledColor,
          ),
          title: inline
              ? Row(
                  children: [
                    Expanded(child: Text(widget.title, style: titleStyle)),
                    const SizedBox(width: 16),
                    valueText,
                  ],
                )
              : Text(widget.title, style: titleStyle),
          subtitle: inline ? null : valueText,
          minVerticalPadding: 12,
          trailing: const ExcludeSemantics(
            child: Icon(Icons.chevron_right_rounded),
          ),
          onTap: widget.enabled ? () => unawaited(_choose()) : null,
        );
      },
    );
  }
}

/// Detailed choice: explanation, availability and preview stay together in
/// the existing group. This state owns disclosure only, never Settings truth.
class _SettingsColorDisclosure extends StatefulWidget {
  const _SettingsColorDisclosure({
    required this.controlKey,
    required this.icon,
    required this.title,
    required this.current,
    required this.currentLabel,
    required this.choices,
    required this.availability,
    required this.availabilityKey,
    required this.enabled,
    required this.onSelected,
  });
  final Key controlKey;
  final IconData icon;
  final String title;
  final AppColorSourcePreference current;
  final String currentLabel;
  final List<_SettingsChoice<AppColorSourcePreference>> choices;
  final String availability;
  final Key availabilityKey;
  final bool enabled;
  final Future<void> Function(AppColorSourcePreference) onSelected;
  @override
  State<_SettingsColorDisclosure> createState() =>
      _SettingsColorDisclosureState();
}

class _SettingsColorDisclosureState extends State<_SettingsColorDisclosure> {
  bool _expanded = false;
  final _focusNode = FocusNode();
  final _optionFocus = {
    for (final value in AppColorSourcePreference.values) value: FocusNode(),
  };

  void _toggle() {
    if (!widget.enabled) return;
    setState(() => _expanded = !_expanded);
    if (!_expanded) _focusNode.requestFocus();
  }

  Future<void> _select(AppColorSourcePreference? value) async {
    if (!widget.enabled || value == null || value == widget.current) return;
    await widget.onSelected(value);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled && _expanded) {
        _optionFocus[value]!.requestFocus();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    for (final focus in _optionFocus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final titleStyle = theme.textTheme.bodyLarge!.copyWith(
      color: widget.enabled ? theme.colorScheme.onSurface : theme.disabledColor,
    );
    final valueStyle = theme.textTheme.bodyMedium!.copyWith(
      color: widget.enabled
          ? theme.colorScheme.onSurfaceVariant
          : theme.disabledColor,
    );
    final value = Text(
      widget.currentLabel,
      key: const ValueKey('settings-color-source-selector-current'),
      style: valueStyle,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final inline = _fitsInline(
              context,
              constraints.maxWidth,
              widget.title,
              titleStyle,
              widget.currentLabel,
              valueStyle,
            );
            return Semantics(
              expanded: _expanded,
              child: ListTile(
                key: widget.controlKey,
                focusNode: _focusNode,
                enabled: widget.enabled,
                leading: Icon(
                  widget.icon,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                title: inline
                    ? Row(
                        children: [
                          Expanded(
                            child: Text(widget.title, style: titleStyle),
                          ),
                          const SizedBox(width: 16),
                          value,
                        ],
                      )
                    : Text(widget.title, style: titleStyle),
                subtitle: inline ? null : value,
                minVerticalPadding: 12,
                trailing: ExcludeSemantics(
                  child: AnimatedRotation(
                    key: const ValueKey('settings-color-chevron'),
                    turns: _expanded ? 0.5 : 0,
                    duration: duration,
                    curve: Curves.easeInOutCubic,
                    child: const Icon(Icons.expand_more_rounded),
                  ),
                ),
                onTap: widget.enabled ? _toggle : null,
              ),
            );
          },
        ),
        Builder(
          builder: (context) {
            final details = _expanded
                ? Padding(
                    key: const ValueKey('settings-color-details'),
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      24,
                      0,
                      16,
                      12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RadioGroup<AppColorSourcePreference>(
                          groupValue: widget.current,
                          onChanged: (value) => unawaited(_select(value)),
                          child: Column(
                            children: [
                              for (final choice in widget.choices)
                                RadioListTile<AppColorSourcePreference>(
                                  key: choice.key,
                                  value: choice.value,
                                  enabled: widget.enabled,
                                  focusNode: _optionFocus[choice.value],
                                  title: Text(choice.label),
                                  subtitle: Text(choice.description!),
                                  contentPadding: EdgeInsets.zero,
                                  minVerticalPadding: 8,
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            16,
                            8,
                            16,
                            4,
                          ),
                          child: Text(
                            widget.availability,
                            key: widget.availabilityKey,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        _SettingsPaletteRow(
                          title: context.l10n.settingsPalettePreviewLabel,
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0);
            // A zero-duration AnimatedSize starts synchronously during layout
            // on this SDK. Reduced motion renders directly, with no height tween.
            if (duration == Duration.zero) return details;
            return AnimatedSize(
              key: const ValueKey('settings-color-size'),
              duration: duration,
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: details,
            );
          },
        ),
      ],
    );
  }
}

/// Measure both actual effective styles, locale and scaler, including the
/// ListTile's icon/gaps/padding/chevron. Long/2x values stack without ellipsis.
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

class _SettingsPaletteRow extends StatelessWidget {
  const _SettingsPaletteRow({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final palette = _SettingsPalettePreview(scheme: theme.colorScheme);
      final inline =
          _fitsInline(
            context,
            constraints.maxWidth - 100,
            title,
            theme.textTheme.bodyLarge!,
            '',
            theme.textTheme.bodyMedium!,
          ) &&
          constraints.maxWidth >= 560;
      return ListTile(
        key: const ValueKey('settings-palette-row'),
        leading: Icon(
          Icons.color_lens_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(title),
        minVerticalPadding: 12,
        trailing: inline
            ? SizedBox(
                width: 124,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: palette,
                ),
              )
            : null,
        subtitle: inline
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: palette,
                ),
              ),
      );
    },
  );
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
