import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/settings/settings_page.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

void main() {
  const captureMaterialReview = bool.fromEnvironment(
    'MATERIAL_FIRST_VISUAL_REVIEW',
  );
  for (final width in [320.0, 360.0, 390.0, 1180.0]) {
    testWidgets('settings use Material controls at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(const _SettingsHarness());
      await tester.pumpAndSettle();

      final selector = find.byKey(const ValueKey('settings-theme-selector'));
      expect(find.byType(DropdownMenu<AppThemePreference>), findsOneWidget);
      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(tester.getSize(selector).width, lessThanOrEqualTo(width - 48));
      final selectorSemantics = tester.getSemantics(selector);
      expect(selectorSemantics.label, contains('Theme'));
      expect(selectorSemantics.label, contains('System'));
      expect(tester.takeException(), isNull);

      await tester.tap(selector);
      await tester.pumpAndSettle();
      final lightOption = find
          .byKey(const ValueKey('settings-theme-light'))
          .hitTestable();
      expect(lightOption, findsOneWidget);
      final triggerRect = tester.getRect(selector);
      final optionRect = tester.getRect(
        find
            .ancestor(of: lightOption, matching: find.byType(MenuItemButton))
            .hitTestable(),
      );
      expect(optionRect.left, closeTo(triggerRect.left, 1));
      if (captureMaterialReview && width == 360) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            Uri.file('/tmp/fura-settings-material-dropdown-360.png'),
          ),
        );
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_SettingsHarness.settingsOf(tester), AppThemePreference.light);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('ExpansionTile owns reduced-motion color source expansion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _SettingsHarness());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-system-colors-available')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-color-source-selector')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-system-colors-available')),
      findsOneWidget,
    );
    expect(find.byType(ExpansionTile), findsOneWidget);
    if (captureMaterialReview) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          Uri.file('/tmp/fura-settings-material-expansion-360.png'),
        ),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('every short enum setting is a Material DropdownMenu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final (section, keys) in [
      (SettingsSection.appearance, const [ValueKey('settings-theme-selector')]),
      (
        SettingsSection.musicService,
        const [ValueKey('settings-provider-selector')],
      ),
      (
        SettingsSection.language,
        const [ValueKey('settings-language-selector')],
      ),
      (
        SettingsSection.playback,
        const [
          ValueKey('settings-quality-selector'),
          ValueKey('settings-lyric-auxiliary-selector'),
        ],
      ),
    ]) {
      await tester.pumpWidget(_SettingsHarness(section: section));
      await tester.pumpAndSettle();
      for (final key in keys) {
        final selector = find.byKey(key);
        expect(selector, findsOneWidget);
        expect(
          tester.widget(selector).runtimeType.toString(),
          startsWith('DropdownMenu<'),
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('only the theme selector restores the SDK component defaults', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _SettingsHarness());
    await tester.pumpAndSettle();
    final themeSelector = find.byKey(const ValueKey('settings-theme-selector'));
    final themeSelectorContext = tester.element(themeSelector);
    expect(
      DropdownMenuTheme.of(themeSelectorContext).inputDecorationTheme,
      isNull,
    );
    expect(DropdownMenuTheme.of(themeSelectorContext).menuStyle, isNull);
    expect(MenuTheme.of(themeSelectorContext).style, isNull);
    final decoration = tester
        .widget<InputDecorator>(
          find.descendant(
            of: themeSelector,
            matching: find.byType(InputDecorator),
          ),
        )
        .decoration;
    expect(decoration.filled, isFalse);
    expect(
      (decoration.border! as OutlineInputBorder).borderRadius,
      const BorderRadius.all(Radius.circular(4)),
    );

    await tester.pumpWidget(
      const _SettingsHarness(section: SettingsSection.playback),
    );
    await tester.pumpAndSettle();
    final qualitySelector = find.byKey(
      const ValueKey('settings-quality-selector'),
    );
    final inheritedProjectTheme = DropdownMenuTheme.of(
      tester.element(qualitySelector),
    );
    expect(inheritedProjectTheme.inputDecorationTheme?.filled, isTrue);
    expect(inheritedProjectTheme.menuStyle, isNotNull);
    expect(tester.takeException(), isNull);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'theme selector keeps the SDK menu motion at reducedMotion=$reducedMotion',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reducedMotion);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        tester.view.physicalSize = const Size(1180, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const _SettingsHarness());
        await tester.pumpAndSettle();
        final selector = find.byKey(const ValueKey('settings-theme-selector'));
        final menuAnchor = tester.widget<MenuAnchor>(
          find.descendant(of: selector, matching: find.byType(MenuAnchor)),
        );

        // Flutter 3.47.1's DropdownMenu does not opt MenuAnchor into its
        // optional animation. Opening and closing therefore complete in the
        // same frame in both normal and reduced-motion modes; Fura must not
        // add a second transition and call it the platform default.
        expect(menuAnchor.animated, isFalse);
        await tester.tap(selector);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('settings-theme-light')).hitTestable(),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('settings-theme-light')).hitTestable(),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('only the color source expansion restores SDK list defaults', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _SettingsHarness());
    await tester.pumpAndSettle();
    final selector = find.byKey(
      const ValueKey('settings-color-source-selector'),
    );
    final selectorContext = tester.element(selector);
    final expansionTheme = ExpansionTileTheme.of(selectorContext);
    final listTheme = ListTileTheme.of(selectorContext);
    expect(expansionTheme.tilePadding, isNull);
    expect(expansionTheme.childrenPadding, isNull);
    expect(expansionTheme.iconColor, isNull);
    expect(expansionTheme.collapsedIconColor, isNull);
    expect(expansionTheme.expansionAnimationStyle, isNull);
    expect(listTheme.shape, isNull);
    expect(listTheme.selectedColor, isNull);
    expect(listTheme.selectedTileColor, isNull);

    final expansion = tester.widget<ExpansionTile>(selector);
    expect(expansion.shape, const Border());
    expect(expansion.collapsedShape, const Border());
    expect(expansion.expansionAnimationStyle, isNull);

    await tester.tap(selector);
    await tester.pumpAndSettle();
    final systemOption = find.byKey(
      const ValueKey('settings-color-source-system'),
    );
    expect(systemOption, findsOneWidget);
    expect(ListTileTheme.of(tester.element(systemOption)).shape, isNull);
    expect(
      tester
          .widget<RadioListTile<AppColorSourcePreference>>(systemOption)
          .enabled,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'color source keeps SDK expansion motion at reducedMotion=$reducedMotion',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reducedMotion);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        tester.view.physicalSize = const Size(1180, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const _SettingsHarness());
        await tester.pumpAndSettle();
        final selector = find.byKey(
          const ValueKey('settings-color-source-selector'),
        );
        final expansion = tester.widget<ExpansionTile>(selector);
        expect(expansion.expansionAnimationStyle, isNull);
        final closedHeight = tester.getSize(selector).height;
        Future<void> tapHeader() =>
            tester.tapAt(tester.getTopLeft(selector) + const Offset(48, 32));

        await tapHeader();
        await tester.pump();
        expect(tester.getSize(selector).height, closeTo(closedHeight, 0.01));
        final halfDuration = reducedMotion
            ? const Duration(milliseconds: 5)
            : const Duration(milliseconds: 100);
        await tester.pump(halfDuration);
        final openingHeight = tester.getSize(selector).height;
        expect(openingHeight, greaterThan(closedHeight));
        await tester.pump(halfDuration);
        final expandedHeight = tester.getSize(selector).height;
        expect(expandedHeight, greaterThan(openingHeight));

        await tapHeader();
        await tester.pump();
        expect(tester.getSize(selector).height, closeTo(expandedHeight, 0.01));
        await tester.pump(halfDuration);
        final closingHeight = tester.getSize(selector).height;
        expect(closingHeight, lessThan(expandedHeight));
        await tester.pump(halfDuration);
        expect(tester.getSize(selector).height, closeTo(closedHeight, 0.01));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _SettingsHarness extends StatefulWidget {
  const _SettingsHarness({this.section = SettingsSection.appearance});

  final SettingsSection section;

  static AppThemePreference settingsOf(WidgetTester tester) => tester
      .state<_SettingsHarnessState>(find.byType(_SettingsHarness))
      .settings
      .theme;

  @override
  State<_SettingsHarness> createState() => _SettingsHarnessState();
}

class _SettingsHarnessState extends State<_SettingsHarness> {
  AppSettings settings = const AppSettings(theme: AppThemePreference.system);

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: MusicMaterialTheme.light(),
    home: Scaffold(
      body: SettingsPage(
        settings: settings,
        selectedSection: widget.section,
        embedded: true,
        showToolbar: false,
        systemLightColorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
        ),
        onBack: () {},
        onCompactSectionSelected: (_) {},
        onSettingsChanged: (next) async {
          setState(() => settings = next);
          return AppSettingsWriteResult.saved;
        },
      ),
    ),
  );
}
