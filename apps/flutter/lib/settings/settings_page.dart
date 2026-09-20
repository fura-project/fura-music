import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
      compact
          ? context.l10n.settingsAppearanceCompactLabel
          : context.l10n.settingsAppearanceLabel,
      key: const ValueKey('settings-appearance-section'),
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: MusicSpacing.itemGap),
    Text(
      context.l10n.settingsAppearanceBody,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
    const SizedBox(height: MusicSpacing.contentGap),
    _SettingsGroup(
      children: [
        _SettingsDropdownTile<AppThemePreference>(
          controlKey: const ValueKey('settings-theme-selector'),
          icon: Icons.brightness_auto_rounded,
          title: context.l10n.settingsAppearanceCompactLabel,
          materialDefaults: true,
          current: widget.settings.theme,
          choices: [
            _SettingsChoice(
              key: const ValueKey('settings-theme-system'),
              value: AppThemePreference.system,
              label: context.l10n.settingsThemeSystem,
            ),
            _SettingsChoice(
              key: const ValueKey('settings-theme-light'),
              value: AppThemePreference.light,
              label: context.l10n.settingsThemeLight,
            ),
            _SettingsChoice(
              key: const ValueKey('settings-theme-dark'),
              value: AppThemePreference.dark,
              label: context.l10n.settingsThemeDark,
            ),
          ],
          enabled: !_saving,
          onSelected: (theme) =>
              unawaited(_save(widget.settings.copyWith(theme: theme))),
        ),
        Builder(
          builder: (context) {
            final brightness = Theme.of(context).brightness;
            final systemScheme = brightness == Brightness.dark
                ? widget.systemDarkColorScheme
                : widget.systemLightColorScheme;
            final fallback = ColorScheme.fromSeed(
              seedColor: MusicMaterialTheme.brandSeedFor(
                widget.settings.musicProvider,
              ),
              brightness: brightness,
              dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
            );
            final preview = systemScheme ?? fallback;
            final status = systemScheme == null
                ? context.l10n.settingsColorSourceSystemUnavailable
                : context.l10n.settingsColorSourceSystemAvailable;
            return Theme(
              data: Theme.of(context).copyWith(
                expansionTileTheme: const ExpansionTileThemeData(),
                listTileTheme: const ListTileThemeData(),
              ),
              child: ExpansionTile(
                key: const ValueKey('settings-color-source-selector'),
                leading: const Icon(Icons.palette_outlined),
                title: Text(context.l10n.settingsColorSourceLabel),
                subtitle: Text(
                  _colorSourceSummary(
                    widget.settings.colorSource,
                    context.l10n,
                  ),
                ),
                enabled: !_saving,
                // The surrounding SettingsGroup owns the separator. Keep the
                // SDK component motion, spacing and states without drawing a
                // second expanded border over that page-level divider.
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        context.l10n.settingsColorSourceBody,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  RadioGroup<AppColorSourcePreference>(
                    groupValue: widget.settings.colorSource,
                    onChanged: (source) {
                      if (!_saving && source != null) {
                        unawaited(
                          _save(widget.settings.copyWith(colorSource: source)),
                        );
                      }
                    },
                    child: Column(
                      children: [
                        RadioListTile<AppColorSourcePreference>(
                          key: const ValueKey('settings-color-source-system'),
                          value: AppColorSourcePreference.system,
                          enabled: !_saving,
                          title: Text(context.l10n.settingsColorSourceSystem),
                          subtitle: Text(
                            context.l10n.settingsColorSourceSystemDescription,
                          ),
                        ),
                        RadioListTile<AppColorSourcePreference>(
                          key: const ValueKey('settings-color-source-brand'),
                          value: AppColorSourcePreference.brand,
                          enabled: !_saving,
                          title: Text(context.l10n.settingsColorSourceBrand),
                          subtitle: Text(
                            context.l10n.settingsColorSourceBrandDescription(
                              _providerLabel(
                                widget.settings.musicProvider,
                                context.l10n,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                    child: Row(
                      key: ValueKey(
                        systemScheme == null
                            ? 'settings-system-colors-unavailable'
                            : 'settings-system-colors-available',
                      ),
                      children: [
                        _ColorSourcePreview(
                          icon: systemScheme == null
                              ? Icons.wallpaper_outlined
                              : Icons.wallpaper_rounded,
                          background: preview.primaryContainer,
                          foreground: preview.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(status)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: _SettingsPalettePreview(scheme: preview),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    ),
  ];

  List<Widget> _musicServiceSection(BuildContext context, bool compact) => [
    Text(
      context.l10n.settingsMusicServiceLabel,
      key: const ValueKey('settings-music-service-section'),
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: MusicSpacing.itemGap),
    Text(
      context.l10n.settingsMusicServiceBody,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
    const SizedBox(height: MusicSpacing.contentGap),
    _SettingsGroup(
      children: [
        _SettingsDropdownTile<AppMusicProvider>(
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
          onSelected: (provider) => unawaited(
            _save(widget.settings.copyWith(musicProvider: provider)),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _languageSection(BuildContext context, bool compact) => [
    Text(
      context.l10n.settingsLanguageLabel,
      key: const ValueKey('settings-language-section'),
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: MusicSpacing.itemGap),
    Text(
      context.l10n.settingsLanguageBody,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
    const SizedBox(height: MusicSpacing.contentGap),
    _SettingsGroup(
      children: [
        _SettingsDropdownTile<AppLocalePreference>(
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
          onSelected: (locale) => unawaited(
            _save(widget.settings.copyWith(localePreference: locale)),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _playbackSection(BuildContext context, bool compact) => [
    Text(
      compact
          ? context.l10n.settingsPlaybackCompactLabel
          : context.l10n.settingsPlaybackSectionLabel,
      key: const ValueKey('settings-playback-section'),
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: MusicSpacing.itemGap),
    Text(
      context.l10n.settingsPlaybackBody,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
    const SizedBox(height: MusicSpacing.contentGap),
    _SettingsGroup(
      children: [
        _SettingsDropdownTile<AppPlaybackQualityPreference>(
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
          onSelected: (quality) => unawaited(
            _save(widget.settings.copyWith(playbackQuality: quality)),
          ),
        ),
        _SettingsDropdownTile<LyricAuxiliaryMode>(
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
          onSelected: (mode) => unawaited(
            _save(widget.settings.copyWith(lyricAuxiliaryMode: mode)),
          ),
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
  const _SettingsChoice({required this.value, required this.label, this.key});

  final T value;
  final String label;
  final Key? key;
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('settings-group'),
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: MusicRadii.content,
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0)
            Divider(
              height: 1,
              indent: 72,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          children[index],
        ],
      ],
    ),
  );
}

class _SettingsDropdownTile<T> extends StatelessWidget {
  const _SettingsDropdownTile({
    required this.controlKey,
    required this.icon,
    required this.title,
    required this.current,
    required this.choices,
    required this.onSelected,
    this.enabled = true,
    this.materialDefaults = false,
    super.key,
  });

  final Key controlKey;
  final IconData icon;
  final String title;
  final T current;
  final List<_SettingsChoice<T>> choices;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final bool materialDefaults;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final selected = choices.singleWhere((choice) => choice.value == current);
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final dropdownTheme = materialDefaults
          ? const DropdownMenuThemeData()
          : DropdownMenuTheme.of(context);
      // Theme overrides may contain only colors/font family. TextField merges
      // those with the localized body style; measure the same effective style.
      final textStyle = theme.textTheme.bodyLarge!.merge(
        dropdownTheme.textStyle,
      );
      final direction = Directionality.of(context);
      double textWidth(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: direction,
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.localeOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      final labelWidth = choices.fold<double>(
        0,
        (width, choice) => math.max(width, textWidth(choice.label, textStyle)),
      );
      final decorationPadding =
          dropdownTheme.inputDecorationTheme?.contentPadding
              ?.resolve(direction)
              .horizontal ??
          24;
      // Reserve the standard 48 dp arrow target, its 4 dp inset on each side,
      // decoration padding and editable caret margin, without shrinking text.
      final preferredWidth = math.max(
        180.0,
        (labelWidth + decorationPadding + kMinInteractiveDimension + 8 + 8)
            .ceilToDouble(),
      );
      final titleWidth = textWidth(
        title,
        ListTileTheme.of(context).titleTextStyle ?? theme.textTheme.bodyLarge!,
      );
      // ListTile has 18 dp side padding, a 40 dp leading slot and two gaps.
      final rowWidth = 36 + 40 + 16 + titleWidth + 16 + preferredWidth;
      final stacked =
          constraints.maxWidth < 520 || rowWidth > constraints.maxWidth;
      final controlWidth = stacked ? constraints.maxWidth - 36 : preferredWidth;
      final dropdown = Semantics(
        label: context.l10n.commonSelectedValue(title, selected.label),
        child: DropdownMenu<T>(
          key: controlKey,
          width: controlWidth,
          maxLines: stacked ? null : 1,
          enabled: enabled,
          initialSelection: current,
          selectOnly: true,
          requestFocusOnTap: true,
          enableSearch: false,
          dropdownMenuEntries: [
            for (final choice in choices)
              DropdownMenuEntry<T>(
                value: choice.value,
                label: choice.label,
                labelWidget: Text(choice.label, key: choice.key),
              ),
          ],
          onSelected: (value) {
            if (value != null && value != current) onSelected(value);
          },
        ),
      );
      final effectiveDropdown = materialDefaults
          ? Theme(
              data: theme.copyWith(
                dropdownMenuTheme: const DropdownMenuThemeData(),
                menuTheme: const MenuThemeData(),
              ),
              child: dropdown,
            )
          : dropdown;
      final tile = ListTile(
        enabled: enabled,
        leading: Icon(icon, color: enabled ? colors.primary : null),
        title: Text(title),
        trailing: stacked ? null : effectiveDropdown,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      );
      if (!stacked) return tile;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile,
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: effectiveDropdown,
          ),
        ],
      );
    },
  );
}

class _ColorSourcePreview extends StatelessWidget {
  const _ColorSourcePreview({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: SizedBox.square(
        dimension: 40,
        child: Icon(icon, color: foreground, size: 22),
      ),
    ),
  );
}

class _SettingsPalettePreview extends StatelessWidget {
  const _SettingsPalettePreview({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final colors = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.primaryContainer,
      scheme.surfaceContainerHighest,
    ];
    return Semantics(
      label: context.l10n.settingsColorSourceLabel,
      child: Row(
        key: const ValueKey('settings-color-palette-preview'),
        children: [
          for (var index = 0; index < colors.length; index++)
            Expanded(
              child: Container(
                height: 28,
                decoration: BoxDecoration(
                  color: colors[index],
                  borderRadius: BorderRadius.horizontal(
                    left: index == 0 ? const Radius.circular(14) : Radius.zero,
                    right: index == colors.length - 1
                        ? const Radius.circular(14)
                        : Radius.zero,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
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
                      section.label(l10n),
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
