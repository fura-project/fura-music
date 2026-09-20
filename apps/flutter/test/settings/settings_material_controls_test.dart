import 'dart:async';
import 'dart:io';

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
  const materialReviewDirectory = String.fromEnvironment(
    'MATERIAL_FIRST_VISUAL_REVIEW_DIR',
    defaultValue: '/tmp',
  );
  for (final width in [320.0, 360.0, 390.0, 1180.0]) {
    testWidgets('settings use Material controls at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      if (captureMaterialReview && width == 360) {
        await _loadReviewFonts(tester);
      }

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
            Uri.file('$materialReviewDirectory/dropdown-360-open.png'),
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
    if (captureMaterialReview) await _loadReviewFonts(tester);

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
          Uri.file('$materialReviewDirectory/color-expansion-360-open.png'),
        ),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('every short enum setting is a Material DropdownMenu', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (captureMaterialReview) await _loadReviewFonts(tester);

    for (final width
        in captureMaterialReview ? const [390.0, 1180.0] : const [1180.0]) {
      tester.view.physicalSize = Size(width, 844);
      for (final (section, keys) in _shortEnumSelectors) {
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
        if (captureMaterialReview) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              Uri.file(
                '$materialReviewDirectory/settings-${section.name}-${width.toInt()}-closed.png',
              ),
            ),
          );
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('all short enum selectors isolate the full input theme chain', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final (section, keys) in _shortEnumSelectors) {
      await tester.pumpWidget(_SettingsHarness(section: section));
      await tester.pumpAndSettle();

      for (final key in keys) {
        final selector = find.byKey(key);
        final selectorContext = tester.element(selector);
        expect(
          DropdownMenuTheme.of(selectorContext).inputDecorationTheme,
          isNull,
        );
        expect(DropdownMenuTheme.of(selectorContext).menuStyle, isNull);
        expect(MenuTheme.of(selectorContext).style, isNull);
        expect(InputDecorationTheme.of(selectorContext).enabledBorder, isNull);
        expect(InputDecorationTheme.of(selectorContext).focusedBorder, isNull);
        expect(InputDecorationTheme.of(selectorContext).disabledBorder, isNull);

        _expectSdkInputState(tester, selector, enabled: true, focused: false);

        await tester.tap(selector);
        await tester.pump();
        expect(find.byType(MenuItemButton).hitTestable(), findsWidgets);
        _expectSdkInputState(
          tester,
          selector,
          enabled: true,
          focused: true,
          menuOpen: true,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('short enum selector disabled state keeps the SDK outline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pendingSave = Completer<AppSettingsWriteResult>();
    addTearDown(() {
      if (!pendingSave.isCompleted) {
        pendingSave.complete(AppSettingsWriteResult.saved);
      }
    });

    await tester.pumpWidget(
      _SettingsHarness(
        section: SettingsSection.playback,
        onSettingsChanged: (_) => pendingSave.future,
      ),
    );
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('settings-quality-selector'));
    await tester.tap(selector);
    await tester.pump();
    await tester.tap(
      find
          .ancestor(
            of: find.byKey(const ValueKey('settings-quality-high')),
            matching: find.byType(MenuItemButton),
          )
          .hitTestable(),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('settings-save-progress')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DropdownMenu<AppPlaybackQualityPreference>>(selector)
          .enabled,
      isFalse,
    );
    // DropdownMenu keeps its field focus while the asynchronous save disables
    // the control; InputDecorator must still resolve the disabled outline.
    _expectSdkInputState(tester, selector, enabled: false, focused: true);
    expect(tester.takeException(), isNull);

    pendingSave.complete(AppSettingsWriteResult.saved);
    await tester.pumpAndSettle();
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

const _shortEnumSelectors = <(SettingsSection, List<ValueKey<String>>)>[
  (SettingsSection.appearance, [ValueKey('settings-theme-selector')]),
  (SettingsSection.musicService, [ValueKey('settings-provider-selector')]),
  (SettingsSection.language, [ValueKey('settings-language-selector')]),
  (
    SettingsSection.playback,
    [
      ValueKey('settings-quality-selector'),
      ValueKey('settings-lyric-auxiliary-selector'),
    ],
  ),
];

void _expectSdkInputState(
  WidgetTester tester,
  Finder selector, {
  required bool enabled,
  required bool focused,
  bool menuOpen = false,
}) {
  final decorator = tester.widget<InputDecorator>(
    find.descendant(of: selector, matching: find.byType(InputDecorator)),
  );
  final decoration = decorator.decoration;
  expect(decoration.enabled, enabled);
  expect(decorator.isFocused, focused);
  expect(decoration.filled, isFalse);

  final effectiveBorder = !enabled
      ? decoration.disabledBorder ?? decoration.border
      : focused
      ? decoration.focusedBorder ?? decoration.border
      : decoration.enabledBorder ?? decoration.border;
  expect(effectiveBorder, isA<OutlineInputBorder>());
  expect(
    (effectiveBorder! as OutlineInputBorder).borderRadius,
    const BorderRadius.all(Radius.circular(4)),
  );
  expect(decoration.enabledBorder, isNull);
  expect(decoration.focusedBorder, isNull);
  expect(decoration.disabledBorder, isNull);

  final theme = Theme.of(tester.element(selector));
  final editable = tester.widget<EditableText>(
    find.descendant(of: selector, matching: find.byType(EditableText)),
  );
  expect(
    editable.style.color,
    enabled
        ? theme.textTheme.bodyLarge?.color
        : theme.colorScheme.onSurface.withAlpha((255 * 0.38).round()),
  );
  final suffixButton = tester.widget<IconButton>(
    find.descendant(
      of: find.descendant(of: selector, matching: find.byType(InputDecorator)),
      matching: find.byType(IconButton),
    ),
  );
  expect(suffixButton.onPressed, enabled ? isNotNull : isNull);
  expect(suffixButton.isSelected, menuOpen);
}

class _SettingsHarness extends StatefulWidget {
  const _SettingsHarness({
    this.section = SettingsSection.appearance,
    this.onSettingsChanged,
  });

  final SettingsSection section;
  final Future<AppSettingsWriteResult> Function(AppSettings settings)?
  onSettingsChanged;

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
    debugShowCheckedModeBanner: false,
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
          final callback = widget.onSettingsChanged;
          if (callback != null) return callback(next);
          setState(() => settings = next);
          return AppSettingsWriteResult.saved;
        },
      ),
    ),
  );
}

Future<void> _loadReviewFonts(WidgetTester tester) async {
  const font = String.fromEnvironment('HOME_REVIEW_CJK_FONT');
  if (font.isEmpty) return;
  await tester.runAsync(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(File(font).readAsBytes().then(ByteData.sublistView))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
}
