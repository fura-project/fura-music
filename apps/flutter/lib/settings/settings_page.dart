import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/fura_toast.dart';
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
    SettingsSection.language => Icons.language_outlined,
    SettingsSection.playback => Icons.headphones_outlined,
  };

  IconData get selectedIcon => switch (this) {
    SettingsSection.appearance => Icons.palette_rounded,
    SettingsSection.musicService => Icons.library_music_rounded,
    SettingsSection.language => Icons.language_rounded,
    SettingsSection.playback => Icons.headphones_rounded,
  };

  String description(AppLocalizations l10n) => switch (this) {
    SettingsSection.appearance => l10n.settingsAppearanceDescription,
    SettingsSection.musicService => l10n.settingsMusicServiceDescription,
    SettingsSection.language => l10n.settingsLanguageDescription,
    SettingsSection.playback => l10n.settingsPlaybackDescription,
  };

  String body(AppLocalizations l10n) => switch (this) {
    SettingsSection.appearance => l10n.settingsAppearanceBody,
    SettingsSection.musicService => l10n.settingsMusicServiceBody,
    SettingsSection.language => l10n.settingsLanguageBody,
    SettingsSection.playback => l10n.settingsPlaybackBody,
  };

  String summary(AppSettings settings, AppLocalizations l10n) => switch (this) {
    SettingsSection.appearance =>
      settings.visualStyle == AppVisualStyle.editorial
          ? '${_themeSummary(settings.theme, l10n)} · '
                '${_visualStyleSummary(settings.visualStyle, l10n)}'
          : '${_themeSummary(settings.theme, l10n)} · '
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
      body(l10n),
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

String _visualStyleSummary(AppVisualStyle style, AppLocalizations l10n) =>
    switch (style) {
      AppVisualStyle.material => l10n.settingsVisualStyleMaterialSummary,
      AppVisualStyle.editorial => l10n.settingsVisualStyleEditorialSummary,
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
      showFuraToast(context, context.l10n.settingsSaveFailure);
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
              padding: EdgeInsets.fromLTRB(
                widget.compactHierarchy ? 16 : MusicSpacing.page,
                widget.compactHierarchy ? 8 : MusicSpacing.contentGap,
                widget.compactHierarchy ? 16 : MusicSpacing.page,
                MusicSpacing.page + MusicViewportClearance.bottomOf(context),
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
        section: SettingsSection.appearance,
        label: l10n.settingsAppearanceLabel,
        headingKey: const ValueKey('settings-appearance-section'),
        compact: compact,
      ),
      _SettingsGroup(
        children: [
          _SettingsChoiceTile<AppThemePreference>(
            controlKey: const ValueKey('settings-theme-selector'),
            icon: Icons.brightness_auto_rounded,
            title: l10n.settingsAppearanceCompactLabel,
            subtitle: _themeSummary(widget.settings.theme, l10n),
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
            subtitle: l10n.settingsColorSourceBody,
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
            availability:
                widget.settings.visualStyle == AppVisualStyle.editorial
                ? l10n.settingsVisualStyleEditorialPaletteNote
                : systemScheme == null
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
      const SizedBox(height: 12),
      _SettingsVisualStyleCard(
        current: widget.settings.visualStyle,
        enabled: !_saving,
        onSelected: (style) =>
            _save(widget.settings.copyWith(visualStyle: style)),
      ),
    ];
  }

  List<Widget> _musicServiceSection(BuildContext context, bool compact) => [
    _SettingsSectionHeading(
      section: SettingsSection.musicService,
      label: context.l10n.settingsMusicServiceLabel,
      headingKey: const ValueKey('settings-music-service-section'),
      compact: compact,
    ),
    _SettingsGroup(
      children: [
        _SettingsChoiceTile<AppMusicProvider>(
          controlKey: const ValueKey('settings-provider-selector'),
          icon: Icons.library_music_outlined,
          title: context.l10n.settingsMusicServiceLabel,
          subtitle: switch (widget.settings.musicProvider) {
            AppMusicProvider.qqMusic =>
              context.l10n.providerQqMusicSettingsDescription,
            AppMusicProvider.netEaseCloudMusic =>
              context.l10n.providerNeteaseSettingsDescription,
          },
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
      section: SettingsSection.language,
      label: context.l10n.settingsLanguageLabel,
      headingKey: const ValueKey('settings-language-section'),
      compact: compact,
    ),
    _SettingsGroup(
      children: [
        _SettingsChoiceTile<AppLocalePreference>(
          controlKey: const ValueKey('settings-language-selector'),
          icon: Icons.language_rounded,
          title: context.l10n.settingsLanguageLabel,
          subtitle: context.l10n.settingsLanguageDescription,
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
      section: SettingsSection.playback,
      label: context.l10n.settingsPlaybackLabel,
      headingKey: const ValueKey('settings-playback-section'),
      compact: compact,
    ),
    _SettingsGroup(
      children: [
        _SettingsChoiceTile<AppPlaybackQualityPreference>(
          controlKey: const ValueKey('settings-quality-selector'),
          icon: Icons.high_quality_rounded,
          title: context.l10n.settingsPlaybackCompactLabel,
          subtitle: context.l10n.settingsPlaybackDescription,
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
          subtitle:
              '${context.l10n.lyricsAuxiliaryTranslation} · '
              '${context.l10n.lyricsAuxiliaryPronunciation}',
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
    required this.section,
    required this.label,
    required this.headingKey,
    required this.compact,
  });
  final SettingsSection section;
  final String label;
  final Key headingKey;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final editorial = context.editorialTheme;
    final l10n = context.l10n;
    final editorialIndex = switch (section) {
      SettingsSection.appearance => '01',
      SettingsSection.musicService => '02',
      SettingsSection.language => '03',
      SettingsSection.playback => '04',
    };
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
        child: Semantics(
          header: true,
          child: Text(
            section.description(l10n),
            key: headingKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (editorial.isEditorial) ...[
            Text(
              editorialIndex,
              style: editorial.eyebrow(theme.textTheme.labelSmall),
            ),
            const SizedBox(height: 4),
          ],
          Semantics(
            header: true,
            child: Text(
              label,
              key: headingKey,
              style: editorial.isEditorial
                  ? editorial.serif(
                      theme.textTheme.headlineMedium,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    )
                  : theme.textTheme.titleLarge?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            section.body(l10n),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(listTileTheme: const ListTileThemeData()),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _SettingsCard(child: children[index]),
        ],
      ],
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final editorial = context.editorialTheme;
    if (editorial.isEditorial) {
      return Material(
        key: const ValueKey('settings-group'),
        color: editorial.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: editorial.cardRadius,
          side: BorderSide(color: editorial.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    return Material(
      key: const ValueKey('settings-group'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: MusicRadii.content,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

Widget _buildSettingsIconBadge(
  ThemeData theme,
  ColorScheme colors,
  IconData icon, {
  required bool enabled,
}) {
  final editorial =
      theme.extension<MusicEditorialTheme>() ?? MusicEditorialTheme.standard;
  return DecoratedBox(
    decoration: BoxDecoration(
      color: editorial.isEditorial
          ? (enabled
                ? editorial.paperCanvas
                : colors.onSurface.withValues(alpha: 0.06))
          : (enabled
                ? colors.secondaryContainer.withValues(alpha: 0.65)
                : colors.onSurface.withValues(alpha: 0.08)),
      border: editorial.isEditorial
          ? Border.all(color: editorial.hairline)
          : null,
      borderRadius: editorial.isEditorial
          ? editorial.controlRadius
          : const BorderRadius.all(Radius.circular(12)),
    ),
    child: SizedBox(
      width: 40,
      height: 40,
      child: Icon(
        icon,
        size: editorial.isEditorial ? 20 : 22,
        color: enabled ? colors.onSecondaryContainer : theme.disabledColor,
      ),
    ),
  );
}

/// Native Material ListTile + PopupMenuButton; Settings owner saves values.
class _SettingsChoiceTile<T> extends StatefulWidget {
  const _SettingsChoiceTile({
    required this.controlKey,
    required this.icon,
    required this.title,
    required this.current,
    required this.choices,
    required this.onSelected,
    this.subtitle,
    this.currentLabel,
    this.enabled = true,
  });
  final Key controlKey;
  final IconData icon;
  final String title;
  final String? subtitle;
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
  final _popupKey = GlobalKey<PopupMenuButtonState<T>>();
  ModalRoute<dynamic>? _route;
  bool _disposing = false;
  bool _selecting = false;
  bool _menuOpen = false;
  bool _initialFocusRequested = false;
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
      final route = _route;
      if (route != null && route.isActive) {
        _route = null;
        _menuOpen = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (route.isActive) route.navigator?.removeRoute(route);
        });
      }
    }
  }

  void _choose() {
    if (!widget.enabled || _selecting) return;
    final route = _route;
    if (route != null) {
      if (route.isCurrent) {
        route.navigator?.pop();
      }
      return;
    }
    _popupKey.currentState?.showButtonMenu();
  }

  void _opened() {
    if (mounted && !_disposing && !_menuOpen) {
      setState(() => _menuOpen = true);
    }
  }

  void _bindRoute(ModalRoute<dynamic>? route) {
    if (route == null || identical(_route, route)) return;
    _route = route;
    route.completed.whenComplete(() {
      if (!identical(_route, route)) return;
      _route = null;
      if (_disposing || !mounted) return;
      if (_menuOpen) {
        setState(() => _menuOpen = false);
      }
      if (!_selecting) {
        _focusReturnPending = true;
        _returnFocus();
      }
    });
  }

  void _canceled() {
    if (_disposing) return;
    if (mounted && _menuOpen) {
      setState(() => _menuOpen = false);
    }
    _focusReturnPending = true;
    _returnFocus();
  }

  Future<void> _select(T value, T snapshot, int revision) async {
    if (!mounted ||
        !widget.enabled ||
        _selecting ||
        revision != _revision ||
        widget.current != snapshot) {
      return;
    }
    if (_menuOpen) {
      setState(() => _menuOpen = false);
    }
    if (value == snapshot) {
      _focusReturnPending = true;
      _returnFocus();
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
    _revision++;
    final route = _route;
    _route = null;
    if (route != null && route.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final selected = widget.choices.singleWhere(
      (choice) => choice.value == widget.current,
    );
    final value = widget.currentLabel ?? selected.label;
    final valueKey = ValueKey(
      '${(widget.controlKey as ValueKey).value}-current',
    );
    final titleStyle = theme.textTheme.bodyLarge!.copyWith(
      color: widget.enabled ? colors.onSurface : theme.disabledColor,
      fontWeight: FontWeight.w600,
    );
    final subtitleStyle = theme.textTheme.bodySmall!.copyWith(
      color: widget.enabled ? colors.onSurfaceVariant : theme.disabledColor,
    );
    final valueStyle = theme.textTheme.bodyMedium!.copyWith(
      color: widget.enabled
          ? (_menuOpen ? colors.onSecondaryContainer : colors.onSurface)
          : theme.disabledColor,
      fontWeight: FontWeight.w500,
    );
    return Semantics(
      expanded: _menuOpen,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inline = _fitsInline(
            context,
            constraints.maxWidth,
            widget.title,
            titleStyle,
            value,
            valueStyle,
          );
          final valueText = Text(value, key: valueKey, style: valueStyle);
          final popupButton = ExcludeSemantics(
            child: IgnorePointer(
              child: PopupMenuButton<T>(
                key: _popupKey,
                enabled: widget.enabled,
                position: PopupMenuPosition.under,
                offset: const Offset(0, 4),
                popUpAnimationStyle: reduced
                    ? AnimationStyle.noAnimation
                    : null,
                constraints: BoxConstraints(
                  minWidth: 168,
                  maxWidth: (MediaQuery.sizeOf(context).width - 32).clamp(
                    168.0,
                    320.0,
                  ),
                ),
                onOpened: _opened,
                onCanceled: _canceled,
                itemBuilder: (context) {
                  // A fresh popup retires callbacks captured by an earlier
                  // popup, even when the authoritative value has not changed.
                  final snapshot = widget.current;
                  final revision = ++_revision;
                  _initialFocusRequested = false;
                  return [
                    for (final choice in widget.choices)
                      PopupMenuItem<T>(
                        key: choice.key,
                        value: choice.value,
                        enabled: widget.enabled,
                        onTap: widget.enabled
                            ? () => unawaited(
                                _select(choice.value, snapshot, revision),
                              )
                            : null,
                        child: Builder(
                          builder: (itemContext) {
                            _bindRoute(ModalRoute.of(itemContext));
                            final isSelected = choice.value == snapshot;
                            if (isSelected && !_initialFocusRequested) {
                              _initialFocusRequested = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (itemContext.mounted) {
                                  Focus.maybeOf(itemContext)?.requestFocus();
                                }
                              });
                            }
                            return Semantics(
                              selected: isSelected,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 22,
                                    child: isSelected
                                        ? Icon(
                                            Icons.check,
                                            size: 18,
                                            color: colors.primary,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      choice.label,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: isSelected
                                                ? colors.primary
                                                : colors.onSurface,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ];
                },
                child: const SizedBox.expand(),
              ),
            ),
          );
          final editorial = context.editorialTheme;
          final valuePill = Stack(
            children: [
              Positioned.fill(child: popupButton),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.enabled
                      ? (editorial.isEditorial
                            ? (_menuOpen
                                  ? editorial.inkPrimary.withValues(alpha: 0.08)
                                  : editorial.paperCanvas)
                            : (_menuOpen
                                  ? colors.secondaryContainer
                                  : colors.surfaceContainerHigh))
                      : colors.onSurface.withValues(alpha: 0.06),
                  border: editorial.isEditorial
                      ? Border.all(
                          color: _menuOpen
                              ? editorial.inkPrimary
                              : editorial.hairline,
                        )
                      : null,
                  borderRadius: editorial.isEditorial
                      ? editorial.controlRadius
                      : const BorderRadius.all(Radius.circular(12)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: valueText),
                      const SizedBox(width: 6),
                      ExcludeSemantics(
                        child: AnimatedRotation(
                          turns: _menuOpen ? .5 : 0,
                          duration: duration,
                          curve: Curves.easeInOutCubic,
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 20,
                            color: widget.enabled
                                ? (_menuOpen
                                      ? colors.onSecondaryContainer
                                      : colors.onSurfaceVariant)
                                : theme.disabledColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
          return ListTile(
            key: widget.controlKey,
            focusNode: _focusNode,
            enabled: widget.enabled,
            horizontalTitleGap: 12,
            contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 6),
            minVerticalPadding: 10,
            leading: _buildSettingsIconBadge(
              theme,
              colors,
              widget.icon,
              enabled: widget.enabled,
            ),
            title: Text(widget.title, style: titleStyle),
            subtitle: _buildSettingsSubtitle(
              inline: inline,
              subtitle: widget.subtitle,
              subtitleStyle: subtitleStyle,
              valuePill: valuePill,
            ),
            trailing: inline ? valuePill : null,
            onTap: widget.enabled ? _choose : null,
          );
        },
      ),
    );
  }
}

/// Detailed configuration stays inside its own setting card.
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
    this.subtitle,
  });
  final Key controlKey;
  final IconData icon;
  final String title, currentLabel, availability;
  final String? subtitle;
  final AppColorSourcePreference current;
  final List<_SettingsChoice<AppColorSourcePreference>> choices;
  final Key availabilityKey;
  final bool enabled;
  final Future<void> Function(AppColorSourcePreference) onSelected;
  @override
  State<_SettingsColorDisclosure> createState() =>
      _SettingsColorDisclosureState();
}

class _SettingsColorDisclosureState extends State<_SettingsColorDisclosure> {
  final _focusNode = FocusNode();
  final _optionFocus = {
    for (final value in AppColorSourcePreference.values) value: FocusNode(),
  };
  bool _expanded = false;
  bool _selecting = false;
  int _revision = 0;

  @override
  void didUpdateWidget(covariant _SettingsColorDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current || !widget.enabled) {
      _revision++;
    }
  }

  void _toggle() {
    if (!widget.enabled) return;
    setState(() {
      _revision++;
      _expanded = !_expanded;
    });
    if (!_expanded) _focusNode.requestFocus();
  }

  Future<void> _select(
    AppColorSourcePreference? value,
    AppColorSourcePreference snapshot,
    int revision,
  ) async {
    if (!mounted ||
        !widget.enabled ||
        _selecting ||
        !_expanded ||
        value == null ||
        value == snapshot ||
        widget.current != snapshot ||
        revision != _revision) {
      return;
    }
    _selecting = true;
    try {
      await widget.onSelected(value);
    } finally {
      _selecting = false;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.enabled && _expanded) {
            // Rollback focuses the authoritative selection, not an unsaved value.
            _optionFocus[widget.current]!.requestFocus();
          }
        });
        WidgetsBinding.instance.scheduleFrame();
      }
    }
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
    final colors = theme.colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final snapshot = widget.current;
    final revision = _revision;
    final titleStyle = theme.textTheme.bodyLarge!.copyWith(
      color: widget.enabled ? colors.onSurface : theme.disabledColor,
      fontWeight: FontWeight.w600,
    );
    final subtitleStyle = theme.textTheme.bodySmall!.copyWith(
      color: widget.enabled ? colors.onSurfaceVariant : theme.disabledColor,
    );
    final valueStyle = theme.textTheme.bodyMedium!.copyWith(
      color: widget.enabled
          ? (_expanded ? colors.onSecondaryContainer : colors.onSurface)
          : theme.disabledColor,
      fontWeight: FontWeight.w500,
    );
    final details = _expanded
        ? Padding(
            key: const ValueKey('settings-color-details'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RadioGroup<AppColorSourcePreference>(
                  groupValue: snapshot,
                  onChanged: (value) =>
                      unawaited(_select(value, snapshot, revision)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var index = 0;
                        index < widget.choices.length;
                        index++
                      ) ...[
                        if (index > 0) const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final choice = widget.choices[index];
                            final isSelected = choice.value == snapshot;
                            return MergeSemantics(
                              child: Material(
                                color: isSelected
                                    ? colors.secondaryContainer.withValues(
                                        alpha: 0.45,
                                      )
                                    : colors.surfaceContainer,
                                shape: RoundedRectangleBorder(
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                  side: BorderSide(
                                    color: isSelected
                                        ? colors.primary.withValues(alpha: 0.5)
                                        : colors.outlineVariant.withValues(
                                            alpha: 0.35,
                                          ),
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  key: choice.key,
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                  canRequestFocus: false,
                                  onTap: widget.enabled
                                      ? () => unawaited(
                                          _select(
                                            choice.value,
                                            snapshot,
                                            revision,
                                          ),
                                        )
                                      : null,
                                  child: Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                          12,
                                          10,
                                          14,
                                          10,
                                        ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Radio<AppColorSourcePreference>(
                                          value: choice.value,
                                          enabled: widget.enabled,
                                          focusNode: _optionFocus[choice.value],
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  choice.label,
                                                  style: theme
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.copyWith(
                                                        fontWeight: isSelected
                                                            ? FontWeight.w600
                                                            : FontWeight.w500,
                                                        color: widget.enabled
                                                            ? colors.onSurface
                                                            : theme
                                                                  .disabledColor,
                                                      ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  choice.description!,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: widget.enabled
                                                            ? colors
                                                                  .onSurfaceVariant
                                                            : theme
                                                                  .disabledColor,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          widget.availability,
                          key: widget.availabilityKey,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              context.l10n.settingsPalettePreviewLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            _SettingsPalettePreview(scheme: colors),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        : const SizedBox(width: double.infinity, height: 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: _expanded,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inline = _fitsInline(
                context,
                constraints.maxWidth,
                widget.title,
                titleStyle,
                widget.currentLabel,
                valueStyle,
              );
              final valueText = Text(
                widget.currentLabel,
                key: const ValueKey('settings-color-source-selector-current'),
                style: valueStyle,
              );
              final valuePill = DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.enabled
                      ? (_expanded
                            ? colors.secondaryContainer
                            : colors.surfaceContainerHigh)
                      : colors.onSurface.withValues(alpha: 0.06),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: valueText),
                      const SizedBox(width: 6),
                      ExcludeSemantics(
                        child: AnimatedRotation(
                          turns: _expanded ? .5 : 0,
                          duration: duration,
                          curve: Curves.easeInOutCubic,
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 20,
                            color: widget.enabled
                                ? (_expanded
                                      ? colors.onSecondaryContainer
                                      : colors.onSurfaceVariant)
                                : theme.disabledColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
              return ListTile(
                key: widget.controlKey,
                focusNode: _focusNode,
                enabled: widget.enabled,
                horizontalTitleGap: 12,
                contentPadding: const EdgeInsetsDirectional.fromSTEB(
                  16,
                  6,
                  16,
                  6,
                ),
                minVerticalPadding: 10,
                leading: _buildSettingsIconBadge(
                  theme,
                  colors,
                  widget.icon,
                  enabled: widget.enabled,
                ),
                title: Text(widget.title, style: titleStyle),
                subtitle: _buildSettingsSubtitle(
                  inline: inline,
                  subtitle: widget.subtitle,
                  subtitleStyle: subtitleStyle,
                  valuePill: valuePill,
                ),
                trailing: inline ? valuePill : null,
                onTap: widget.enabled ? _toggle : null,
              );
            },
          ),
        ),
        // A zero-duration AnimatedSize mutates during layout on the pinned SDK.
        // Reduced-motion renders the final layout directly instead.
        if (reduced)
          details
        else
          AnimatedSize(
            key: const ValueKey('settings-color-size'),
            duration: duration,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: details,
          ),
      ],
    );
  }
}

Widget? _buildSettingsSubtitle({
  required bool inline,
  required String? subtitle,
  required TextStyle subtitleStyle,
  required Widget valuePill,
}) {
  if (inline) {
    if (subtitle == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: subtitleStyle,
      ),
    );
  }
  final alignedPill = Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      child: valuePill,
    ),
  );
  if (subtitle == null) return alignedPill;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: subtitleStyle,
        ),
      ),
      alignedPill,
    ],
  );
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

  return width >= 280 &&
      measure(title, titleStyle) + measure(value, valueStyle) + 148 <= width;
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
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MusicViewportClearance.bottomOf(context),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              l10n.settingsChooseCategory,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          for (
            var index = 0;
            index < SettingsSection.values.length;
            index++
          ) ...[
            if (index > 0) const SizedBox(height: 10),
            Material(
              color: colors.surfaceContainerLow,
              borderRadius: MusicRadii.content,
              clipBehavior: Clip.antiAlias,
              child: _CompactSettingsMenuTile(
                key: ValueKey(
                  'settings-compact-${SettingsSection.values[index].name}',
                ),
                section: SettingsSection.values[index],
                summary: SettingsSection.values[index].summary(settings, l10n),
                onTap: () => onSelected(SettingsSection.values[index]),
              ),
            ),
          ],
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.secondaryContainer.withValues(alpha: 0.65),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    section.icon,
                    size: 22,
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.label(l10n),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
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

class _SettingsVisualStyleCard extends StatelessWidget {
  const _SettingsVisualStyleCard({
    required this.current,
    required this.enabled,
    required this.onSelected,
  });

  final AppVisualStyle current;
  final bool enabled;
  final Future<void> Function(AppVisualStyle style) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final editorial = context.editorialTheme;
    final l10n = context.l10n;
    final dark = theme.brightness == Brightness.dark;
    final card = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const ValueKey('settings-visual-style-selector'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsIconBadge(
                theme,
                colors,
                Icons.auto_stories_outlined,
                enabled: enabled,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsVisualStyleLabel,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: enabled ? colors.onSurface : theme.disabledColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.settingsVisualStyleBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: enabled
                            ? colors.onSurfaceVariant
                            : theme.disabledColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final sideBySide =
                  constraints.maxWidth >= 460 && textScale <= 1.35;
              final materialOption = _VisualStyleOptionCard(
                key: const ValueKey('settings-visual-style-material'),
                style: AppVisualStyle.material,
                title: l10n.settingsVisualStyleMaterial,
                description: l10n.settingsVisualStyleMaterialDescription,
                selected: current == AppVisualStyle.material,
                enabled: enabled,
                dark: dark,
                onTap: () => unawaited(onSelected(AppVisualStyle.material)),
              );
              final editorialOption = _VisualStyleOptionCard(
                key: const ValueKey('settings-visual-style-editorial'),
                style: AppVisualStyle.editorial,
                title: l10n.settingsVisualStyleEditorial,
                description: l10n.settingsVisualStyleEditorialDescription,
                selected: current == AppVisualStyle.editorial,
                enabled: enabled,
                dark: dark,
                onTap: () => unawaited(onSelected(AppVisualStyle.editorial)),
              );
              if (sideBySide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: materialOption),
                      const SizedBox(width: 12),
                      Expanded(child: editorialOption),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  materialOption,
                  const SizedBox(height: 10),
                  editorialOption,
                ],
              );
            },
          ),
        ],
      ),
    );
    if (editorial.isEditorial) {
      return Material(
        key: const ValueKey('settings-visual-style-card'),
        color: editorial.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: editorial.cardRadius,
          side: BorderSide(color: editorial.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: card,
      );
    }
    return Material(
      key: const ValueKey('settings-visual-style-card'),
      color: colors.surfaceContainerLow,
      borderRadius: MusicRadii.content,
      clipBehavior: Clip.antiAlias,
      child: card,
    );
  }
}

class _VisualStyleOptionCard extends StatelessWidget {
  const _VisualStyleOptionCard({
    required this.style,
    required this.title,
    required this.description,
    required this.selected,
    required this.enabled,
    required this.dark,
    required this.onTap,
    super.key,
  });

  final AppVisualStyle style;
  final String title;
  final String description;
  final bool selected;
  final bool enabled;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final editorial = context.editorialTheme;
    final radius = editorial.isEditorial
        ? editorial.controlRadius
        : const BorderRadius.all(Radius.circular(12));
    final borderColor = selected
        ? colors.primary
        : (editorial.isEditorial
              ? editorial.hairline
              : colors.outlineVariant.withValues(alpha: 0.45));
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '$title. $description',
      child: Material(
        color: selected
            ? (editorial.isEditorial
                  ? editorial.paperCanvas
                  : colors.secondaryContainer.withValues(alpha: 0.45))
            : (editorial.isEditorial
                  ? editorial.paperCanvas.withValues(alpha: 0.55)
                  : colors.surfaceContainer),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: borderColor, width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _VisualStyleMiniPreview(style: style, dark: dark),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: style == AppVisualStyle.editorial
                            ? MusicEditorialTheme.editorialLight.serif(
                                theme.textTheme.titleSmall,
                                fontWeight: FontWeight.w600,
                                color: enabled
                                    ? colors.onSurface
                                    : theme.disabledColor,
                              )
                            : theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: enabled
                                    ? colors.onSurface
                                    : theme.disabledColor,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ExcludeSemantics(
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: selected
                            ? colors.primary
                            : colors.onSurfaceVariant.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? colors.onSurfaceVariant
                        : theme.disabledColor,
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

class _VisualStyleMiniPreview extends StatelessWidget {
  const _VisualStyleMiniPreview({required this.style, required this.dark});

  final AppVisualStyle style;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final isEditorialOption = style == AppVisualStyle.editorial;
    final bg = isEditorialOption
        ? (dark ? const Color(0xFF141210) : const Color(0xFFFAF8F4))
        : (dark ? const Color(0xFF0D0F0E) : const Color(0xFFF6FBF6));
    final sidebar = isEditorialOption
        ? (dark ? const Color(0xFF1A1714) : const Color(0xFFF3EFE8))
        : (dark ? const Color(0xFF171918) : const Color(0xFFEAF3EC));
    final ink = isEditorialOption
        ? (dark ? const Color(0xFFF2EDE4) : const Color(0xFF171513))
        : (dark ? const Color(0xFFE3E4DF) : const Color(0xFF191C1A));
    final accent = isEditorialOption
        ? (dark ? const Color(0xFFF2EDE4) : const Color(0xFF171513))
        : MusicMaterialTheme.seedColor;
    final rule = isEditorialOption
        ? (dark ? const Color(0xFF312C26) : const Color(0xFFE3DDD1))
        : (dark ? const Color(0xFF343A35) : const Color(0xFFD2E2D6));

    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(isEditorialOption ? 3 : 10),
            border: Border.all(color: rule),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Container(
                width: 34,
                decoration: BoxDecoration(
                  color: sidebar,
                  border: Border(right: BorderSide(color: rule)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 4,
                      width: 18,
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (isEditorialOption)
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 3,
                              color: ink.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Container(width: 2, height: 10, color: ink),
                        ],
                      )
                    else
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Container(
                      height: 3,
                      width: 14,
                      color: ink.withValues(alpha: 0.25),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isEditorialOption ? '01  Aa' : 'Fura',
                            style: isEditorialOption
                                ? MusicEditorialTheme.editorialLight.serif(
                                    const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      height: 1.1,
                                    ),
                                    color: ink,
                                  )
                                : TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                    color: ink,
                                  ),
                          ),
                          const Spacer(),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (isEditorialOption) Container(height: 1, color: rule),
                      const Spacer(),
                      Row(
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            Expanded(
                              child: Container(
                                height: 22,
                                decoration: BoxDecoration(
                                  color: i == 0
                                      ? ink.withValues(alpha: 0.14)
                                      : ink.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(
                                    isEditorialOption ? 2 : 6,
                                  ),
                                  border: isEditorialOption
                                      ? Border.all(color: rule, width: 0.75)
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
