import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_controller.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/settings/settings_page.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

const settingsChoiceSelectors = <(SettingsSection, List<(String, String)>)>[
  (
    SettingsSection.appearance,
    [
      ('settings-theme-selector', 'settings-theme-light'),
      ('settings-color-source-selector', 'settings-color-source-system'),
    ],
  ),
  (
    SettingsSection.musicService,
    [('settings-provider-selector', 'settings-provider-netease')],
  ),
  (
    SettingsSection.language,
    [('settings-language-selector', 'settings-language-english')],
  ),
  (
    SettingsSection.playback,
    [
      ('settings-quality-selector', 'settings-quality-high'),
      ('settings-lyric-auxiliary-selector', 'settings-lyric-auxiliary-off'),
    ],
  ),
];

void setSettingsViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

InkWell settingsRowInk(WidgetTester tester, Finder row) =>
    tester.widget<InkWell>(
      find.descendant(of: row, matching: find.byType(InkWell)).first,
    );

class SettingsReviewHarness extends StatefulWidget {
  const SettingsReviewHarness({
    this.section = SettingsSection.appearance,
    this.owner,
    this.onChanged,
    this.language = 'en',
    this.brightness = Brightness.light,
    this.scale = 1,
    this.projectTheme = true,
    this.compact = false,
    this.systemColorsAvailable = true,
    this.showPage = true,
    super.key,
  });
  final SettingsSection section;
  final AppSettingsController? owner;
  final Future<AppSettingsWriteResult> Function(AppSettings)? onChanged;
  final String language;
  final Brightness brightness;
  final double scale;
  final bool projectTheme;
  final bool compact;
  final bool systemColorsAvailable;
  final bool showPage;
  @override
  State<SettingsReviewHarness> createState() => _SettingsReviewHarnessState();
}

class _SettingsReviewHarnessState extends State<SettingsReviewHarness> {
  AppSettings settings = AppSettings.defaults;
  @override
  Widget build(BuildContext context) {
    final schemeTheme = widget.brightness == Brightness.dark
        ? MusicMaterialTheme.dark()
        : MusicMaterialTheme.light();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(widget.language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: widget.projectTheme
          ? schemeTheme
          : ThemeData(useMaterial3: true, colorScheme: schemeTheme.colorScheme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(widget.scale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: widget.owner ?? const AlwaysStoppedAnimation(0),
          builder: (context, _) => widget.showPage
              ? SettingsPage(
                  settings: widget.owner?.settings ?? settings,
                  selectedSection: widget.section,
                  compactHierarchy: widget.compact,
                  compactSectionOpen: widget.compact,
                  embedded: true,
                  showToolbar: widget.compact,
                  systemLightColorScheme: widget.systemColorsAvailable
                      ? schemeTheme.colorScheme
                      : null,
                  systemDarkColorScheme: widget.systemColorsAvailable
                      ? schemeTheme.colorScheme
                      : null,
                  onBack: () {},
                  onCompactSectionSelected: (_) {},
                  onSettingsChanged: (next) async {
                    if (widget.owner != null) {
                      return widget.owner!.update(next);
                    }
                    if (widget.onChanged != null) {
                      return widget.onChanged!(next);
                    }
                    setState(() => settings = next);
                    return AppSettingsWriteResult.saved;
                  },
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
