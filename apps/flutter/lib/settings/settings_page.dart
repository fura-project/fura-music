import 'dart:async';

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

  Future<void> _chooseSetting<T>({
    required String title,
    required T current,
    required List<_SettingsChoice<T>> choices,
    required ValueChanged<T> onSelected,
  }) async {
    if (_saving) return;
    Widget choiceList(BuildContext dialogContext) => RadioGroup<T>(
      groupValue: current,
      onChanged: (value) {
        if (value != null) Navigator.of(dialogContext).pop(value);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in choices)
            RadioListTile<T>(
              key: choice.key,
              value: choice.value,
              title: Text(choice.label),
              subtitle: choice.description == null
                  ? null
                  : Text(choice.description!),
            ),
        ],
      ),
    );
    final T? selected;
    if (MediaQuery.sizeOf(context).width < 600) {
      selected = await showModalBottomSheet<T>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        builder: (sheetContext) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 8),
              choiceList(sheetContext),
            ],
          ),
        ),
      );
    } else {
      selected = await showDialog<T>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: choiceList(dialogContext),
          ),
        ),
      );
    }
    if (!mounted || selected == null || selected == current) return;
    onSelected(selected);
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
        _SettingsValueTile(
          key: const ValueKey('settings-theme-selector'),
          icon: Icons.brightness_auto_rounded,
          title: context.l10n.settingsAppearanceCompactLabel,
          value: _themeSummary(widget.settings.theme, context.l10n),
          enabled: !_saving,
          onTap: () => unawaited(
            _chooseSetting<AppThemePreference>(
              title: context.l10n.settingsAppearanceCompactLabel,
              current: widget.settings.theme,
              choices: [
                _SettingsChoice(
                  value: AppThemePreference.system,
                  label: context.l10n.settingsThemeSystem,
                ),
                _SettingsChoice(
                  value: AppThemePreference.light,
                  label: context.l10n.settingsThemeLight,
                ),
                _SettingsChoice(
                  value: AppThemePreference.dark,
                  label: context.l10n.settingsThemeDark,
                ),
              ],
              onSelected: (theme) =>
                  unawaited(_save(widget.settings.copyWith(theme: theme))),
            ),
          ),
        ),
        _SettingsValueTile(
          key: const ValueKey('settings-color-source-selector'),
          icon: Icons.palette_outlined,
          title: context.l10n.settingsColorSourceLabel,
          value: _colorSourceSummary(widget.settings.colorSource, context.l10n),
          subtitle: context.l10n.settingsColorSourceBody,
          enabled: !_saving,
          onTap: () => unawaited(
            _chooseSetting<AppColorSourcePreference>(
              title: context.l10n.settingsColorSourceLabel,
              current: widget.settings.colorSource,
              choices: [
                _SettingsChoice(
                  key: const ValueKey('settings-color-source-system'),
                  value: AppColorSourcePreference.system,
                  label: context.l10n.settingsColorSourceSystem,
                  description:
                      context.l10n.settingsColorSourceSystemDescription,
                ),
                _SettingsChoice(
                  key: const ValueKey('settings-color-source-brand'),
                  value: AppColorSourcePreference.brand,
                  label: context.l10n.settingsColorSourceBrand,
                  description: context.l10n.settingsColorSourceBrandDescription(
                    _providerLabel(widget.settings.musicProvider, context.l10n),
                  ),
                ),
              ],
              onSelected: (source) => unawaited(
                _save(widget.settings.copyWith(colorSource: source)),
              ),
            ),
          ),
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
            return _SettingsValueTile(
              key: ValueKey(
                systemScheme == null
                    ? 'settings-system-colors-unavailable'
                    : 'settings-system-colors-available',
              ),
              leading: _ColorSourcePreview(
                icon: systemScheme == null
                    ? Icons.wallpaper_outlined
                    : Icons.wallpaper_rounded,
                background: preview.primaryContainer,
                foreground: preview.onPrimaryContainer,
              ),
              title: context.l10n.settingsColorSourceSystem,
              value: status,
              showChevron: false,
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
        _SettingsValueTile(
          key: const ValueKey('settings-provider-selector'),
          icon: Icons.library_music_outlined,
          title: context.l10n.settingsMusicServiceLabel,
          value: _providerLabel(widget.settings.musicProvider, context.l10n),
          enabled: !_saving,
          onTap: () => unawaited(
            _chooseSetting<AppMusicProvider>(
              title: context.l10n.settingsMusicServiceLabel,
              current: widget.settings.musicProvider,
              choices: [
                _SettingsChoice(
                  key: const ValueKey('settings-provider-qq-music'),
                  value: AppMusicProvider.qqMusic,
                  label: context.l10n.providerQqMusic,
                  description: context.l10n.providerQqMusicSettingsDescription,
                ),
                _SettingsChoice(
                  key: const ValueKey('settings-provider-netease'),
                  value: AppMusicProvider.netEaseCloudMusic,
                  label: context.l10n.providerNeteaseCloudMusic,
                  description: context.l10n.providerNeteaseSettingsDescription,
                ),
              ],
              onSelected: (provider) => unawaited(
                _save(widget.settings.copyWith(musicProvider: provider)),
              ),
            ),
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
        _SettingsValueTile(
          key: const ValueKey('settings-language-selector'),
          icon: Icons.language_rounded,
          title: context.l10n.settingsLanguageLabel,
          value: SettingsSection.language.summary(
            widget.settings,
            context.l10n,
          ),
          enabled: !_saving,
          onTap: () => unawaited(
            _chooseSetting<AppLocalePreference>(
              title: context.l10n.settingsLanguageLabel,
              current: widget.settings.localePreference,
              choices: [
                _SettingsChoice(
                  value: AppLocalePreference.system,
                  label: context.l10n.settingsLanguageFollowSystem,
                ),
                _SettingsChoice(
                  value: AppLocalePreference.english,
                  label: context.l10n.settingsLanguageEnglish,
                ),
                _SettingsChoice(
                  value: AppLocalePreference.simplifiedChinese,
                  label: context.l10n.settingsLanguageSimplifiedChinese,
                ),
              ],
              onSelected: (locale) => unawaited(
                _save(widget.settings.copyWith(localePreference: locale)),
              ),
            ),
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
        _SettingsValueTile(
          key: const ValueKey('settings-quality-selector'),
          icon: Icons.high_quality_rounded,
          title: context.l10n.settingsPlaybackSectionLabel,
          value: _qualitySummary(widget.settings.playbackQuality, context.l10n),
          enabled: !_saving,
          onTap: () => unawaited(
            _chooseSetting<AppPlaybackQualityPreference>(
              title: context.l10n.settingsPlaybackSectionLabel,
              current: widget.settings.playbackQuality,
              choices: [
                _SettingsChoice(
                  value: AppPlaybackQualityPreference.standard,
                  label: context.l10n.playbackQualityStandard,
                ),
                _SettingsChoice(
                  value: AppPlaybackQualityPreference.high,
                  label: context.l10n.playbackQualityHigh,
                ),
                _SettingsChoice(
                  value: AppPlaybackQualityPreference.lossless,
                  label: context.l10n.playbackQualityLossless,
                ),
              ],
              onSelected: (quality) => unawaited(
                _save(widget.settings.copyWith(playbackQuality: quality)),
              ),
            ),
          ),
        ),
        _SettingsValueTile(
          key: const ValueKey('settings-lyric-auxiliary-selector'),
          icon: Icons.lyrics_outlined,
          title: context.l10n.lyricsAuxiliaryMode,
          value: _lyricAuxiliarySummary(
            widget.settings.lyricAuxiliaryMode,
            context.l10n,
          ),
          enabled: !_saving,
          onTap: () => unawaited(
            _chooseSetting<LyricAuxiliaryMode>(
              title: context.l10n.lyricsAuxiliaryMode,
              current: widget.settings.lyricAuxiliaryMode,
              choices: [
                for (final mode in LyricAuxiliaryMode.values)
                  _SettingsChoice(
                    value: mode,
                    label: _lyricAuxiliarySummary(mode, context.l10n),
                  ),
              ],
              onSelected: (mode) => unawaited(
                _save(widget.settings.copyWith(lyricAuxiliaryMode: mode)),
              ),
            ),
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

class _SettingsValueTile extends StatelessWidget {
  const _SettingsValueTile({
    required this.title,
    required this.value,
    this.icon,
    this.leading,
    this.subtitle,
    this.onTap,
    this.enabled = true,
    this.showChevron = true,
    super.key,
  });

  final String title;
  final String value;
  final IconData? icon;
  final Widget? leading;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      enabled: enabled,
      leading:
          leading ??
          (icon == null
              ? null
              : Icon(icon, color: enabled ? colors.primary : null)),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: enabled
                  ? colors.onSurfaceVariant
                  : colors.onSurface.withValues(alpha: 0.38),
            ),
          ),
          if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!)],
        ],
      ),
      trailing: showChevron && onTap != null
          ? const Icon(Icons.chevron_right_rounded)
          : null,
      onTap: enabled ? onTap : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    );
  }
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
