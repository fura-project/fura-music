import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_controller.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/settings/settings_page.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

void main() {
  for (final width in [390.0, 640.0, 1180.0]) {
    for (final language in ['en', 'zh']) {
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          for (final project in [false, true]) {
            final name =
                '${width}_${language}_${brightness.name}_${scale}_${project ? 'project' : 'default'}';
            testWidgets('settings dropdown fit $name', (tester) async {
              final oldDisableShadows = debugDisableShadows;
              debugDisableShadows = false;
              try {
                tester.view.physicalSize = Size(width, 1100);
                tester.view.devicePixelRatio = 1;
                addTearDown(tester.view.resetPhysicalSize);
                addTearDown(tester.view.resetDevicePixelRatio);
                await _loadReviewFonts(tester);
                final schemeTheme = brightness == Brightness.dark
                    ? MusicMaterialTheme.dark()
                    : MusicMaterialTheme.light();
                // Hold color palette and fonts constant; isolate component theme overrides.
                final theme = project
                    ? schemeTheme
                    : ThemeData(
                        useMaterial3: true,
                        colorScheme: schemeTheme.colorScheme,
                      );
                final boundary = GlobalKey();
                await tester.pumpWidget(
                  RepaintBoundary(
                    key: boundary,
                    child: MaterialApp(
                      debugShowCheckedModeBanner: false,
                      locale: Locale(language),
                      localizationsDelegates:
                          AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      theme: theme,
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: child!,
                      ),
                      home: Scaffold(
                        body: SettingsPage(
                          settings: const AppSettings(
                            theme: AppThemePreference.system,
                          ),
                          selectedSection: SettingsSection.appearance,
                          embedded: true,
                          showToolbar: false,
                          systemLightColorScheme: schemeTheme.colorScheme,
                          systemDarkColorScheme: schemeTheme.colorScheme,
                          onBack: () {},
                          onCompactSectionSelected: (_) {},
                          onSettingsChanged: (_) async =>
                              AppSettingsWriteResult.saved,
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                final selector = find.byKey(
                  const ValueKey('settings-theme-selector'),
                );
                Future<void> capture(String state, {bool settle = true}) async {
                  if (settle) await tester.pumpAndSettle();
                  final errors = <String>[];
                  Object? error;
                  while ((error = tester.takeException()) != null) {
                    errors.add(error.toString());
                  }
                  debugPrint(
                    'settings dropdown fit $name/$state trigger=${tester.getRect(selector)} errors=$errors',
                  );
                  if (const bool.fromEnvironment('SETTINGS_LAYOUT_REVIEW')) {
                    const reviewDirectory = String.fromEnvironment(
                      'SETTINGS_LAYOUT_REVIEW_DIR',
                      defaultValue: '/tmp/fura-targeted-fix-20260920',
                    );
                    await tester.runAsync(() async {
                      final image =
                          await (boundary.currentContext!.findRenderObject()
                                  as RenderRepaintBoundary)
                              .toImage();
                      final bytes = await image.toByteData(
                        format: ui.ImageByteFormat.png,
                      );
                      await File('$reviewDirectory/$name-$state.png')
                          .writeAsBytes(bytes!.buffer.asUint8List());
                      image.dispose();
                      if (errors.isNotEmpty) {
                        await File('$reviewDirectory/$name-$state.errors')
                            .writeAsString(errors.join('\n'));
                      }
                    });
                  }
                  expect(errors, isEmpty);
                }

                await capture('closed');
                {
                  final editable = tester
                      .state<EditableTextState>(
                        find.descendant(
                          of: selector,
                          matching: find.byType(EditableText),
                        ),
                      )
                      .renderEditable;
                  debugPrint(
                    'AUDIT text fit $name visibleWidth=${editable.size.width} maxScrollExtent=${editable.maxScrollExtent} text=${editable.text?.toPlainText()}',
                  );
                  expect(
                    editable.maxScrollExtent,
                    0,
                    reason: 'Selected value should be completely visible without horizontal scrolling',
                  );
                }
                final field = tester.widget<EditableText>(
                  find
                      .descendant(
                        of: selector,
                        matching: find.byType(EditableText),
                      )
                      .first,
                );
                field.focusNode.requestFocus();
                await capture('focus');
                await tester.tap(selector);
                const reviewEnabled = bool.fromEnvironment(
                  'SETTINGS_LAYOUT_REVIEW',
                );
                final captureMenuTimeline =
                    reviewEnabled && name == '1180.0_en_light_1.0_project';
                if (captureMenuTimeline) {
                  await tester.pump();
                  await capture('open-000ms', settle: false);
                  await tester.pump(const Duration(milliseconds: 250));
                  await capture('open-250ms', settle: false);
                  await tester.pump(const Duration(milliseconds: 250));
                  await capture('open-500ms', settle: false);
                }
                await capture('open');
                for (final value in ['system', 'light', 'dark']) {
                  expect(
                    find.byKey(ValueKey('settings-theme-$value')).hitTestable(),
                    findsOneWidget,
                  );
                }
                final light = find
                    .byKey(const ValueKey('settings-theme-light'))
                    .hitTestable();
                final mouse = await tester.createGesture(
                  kind: ui.PointerDeviceKind.mouse,
                );
                await mouse.addPointer(location: const Offset(389, 1099));
                await mouse.moveTo(tester.getCenter(light));
                await capture('hover');
                await mouse.moveTo(const Offset(389, 1099));
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
                await capture('keyboard');
                await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                if (captureMenuTimeline) {
                  await tester.pump();
                  await capture('close-000ms', settle: false);
                  await tester.pump(const Duration(milliseconds: 75));
                  await capture('close-075ms', settle: false);
                  await tester.pump(const Duration(milliseconds: 75));
                  await capture('close-150ms', settle: false);
                } else {
                  await tester.pumpAndSettle();
                }
                // Explicit outside tap closes menu before expansion capture.
                if (light.evaluate().isNotEmpty) {
                  await tester.tapAt(const Offset(10, 1090));
                  await tester.pumpAndSettle();
                  expect(light, findsNothing);
                }
                FocusManager.instance.primaryFocus?.unfocus();
                await mouse.removePointer();
                final colorSelector = find.byKey(
                  const ValueKey('settings-color-source-selector'),
                );
                await tester.ensureVisible(colorSelector);
                Future<void> tapColorHeader() => tester.tapAt(
                  tester.getTopLeft(colorSelector) + const Offset(48, 32),
                );
                await tapColorHeader();
                if (captureMenuTimeline) {
                  await tester.pump();
                  await capture('expand-000ms', settle: false);
                  await tester.pump(const Duration(milliseconds: 100));
                  await capture('expand-100ms', settle: false);
                  await tester.pump(const Duration(milliseconds: 100));
                  await capture('expand-200ms', settle: false);
                  await tapColorHeader();
                  await tester.pump();
                  await capture('collapse-000ms', settle: false);
                  await tester.pump(const Duration(milliseconds: 100));
                  await capture('collapse-100ms', settle: false);
                  await tester.pump(const Duration(milliseconds: 100));
                  await capture('collapse-200ms', settle: false);

                  tester.platformDispatcher.accessibilityFeaturesTestValue =
                      const FakeAccessibilityFeatures(disableAnimations: true);
                  addTearDown(
                    tester
                        .platformDispatcher
                        .clearAccessibilityFeaturesTestValue,
                  );
                  await tapColorHeader();
                  await tester.pump();
                  await capture('reduced-expand-000ms', settle: false);
                  await tester.pump(const Duration(milliseconds: 5));
                  await capture('reduced-expand-005ms', settle: false);
                  await tester.pump(const Duration(milliseconds: 5));
                  await capture('reduced-expand-010ms', settle: false);
                } else {
                  await tester.pumpAndSettle();
                }
                expect(
                  find.byKey(
                    const ValueKey('settings-system-colors-available'),
                  ),
                  findsOneWidget,
                );
                await capture('expanded');
                await tester.pumpWidget(const SizedBox.shrink());
              } finally {
                debugDisableShadows = oldDisableShadows;
              }
            });
          }
        }
      }
    }
  }
  for (final language in ['en', 'zh']) {
    for (final succeeds in [true, false]) {
      testWidgets(
        'settings keyboard selection reconciles $language save $succeeds',
        (tester) async {
          await _loadReviewFonts(tester);
          tester.view.physicalSize = const Size(1180, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final storage = _PendingSettingsStorage();
          final owner = AppSettingsController(
            AppSettingsStore(storage: storage),
            null,
            initialSettings: AppSettings.defaults,
          );
          addTearDown(owner.dispose);
          final semantics = tester.ensureSemantics();

          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: MusicMaterialTheme.light(),
              home: Scaffold(
                body: ListenableBuilder(
                  listenable: owner,
                  builder: (context, _) => SettingsPage(
                    settings: owner.settings,
                    selectedSection: SettingsSection.appearance,
                    embedded: true,
                    showToolbar: false,
                    onBack: () {},
                    onCompactSectionSelected: (_) {},
                    onSettingsChanged: owner.update,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final selector = find.byKey(
            const ValueKey('settings-theme-selector'),
          );
          String current() => tester
              .widget<EditableText>(
                find.descendant(
                  of: selector,
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text;
          final l10n = AppLocalizations.of(tester.element(selector));
          expect(current(), l10n.settingsThemeSystem);
          await tester.tap(selector);
          await tester.pumpAndSettle();
          final field = tester.widget<EditableText>(
            find.descendant(of: selector, matching: find.byType(EditableText)),
          );
          expect(field.focusNode.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(owner.settings.theme, AppThemePreference.light);
          expect(current(), l10n.settingsThemeLight);
          expect(storage.writes, 1);
          expect(
            tester.getSemantics(selector).label,
            contains(l10n.settingsThemeLight),
          );
          if (succeeds) {
            storage.completion.complete();
          } else {
            storage.completion.completeError(
              StateError('fixture write failure'),
            );
          }
          await tester.pumpAndSettle();
          expect(
            owner.settings.theme,
            succeeds ? AppThemePreference.light : AppThemePreference.system,
          );
          expect(
            current(),
            succeeds ? l10n.settingsThemeLight : l10n.settingsThemeSystem,
          );
          expect(tester.getSemantics(selector).label, contains(current()));
          expect(
            tester.widget<DropdownMenu<AppThemePreference>>(selector).enabled,
            isTrue,
          );
          if (!succeeds) {
            expect(find.text(l10n.settingsSaveFailure), findsOneWidget);
          }
          semantics.dispose();
        },
      );
    }
  }
  testWidgets(
    'settings dropdown stacks when scaled row cannot fit above 520 dp',
    (tester) async {
      await _loadReviewFonts(tester);
      // Ahem's block glyphs need more width than the real CJK review font.
      // Both viewports leave the tile wider than 520 dp; at each measured
      // boundary the same row fits at 1x and must stack at 2x.
      const reviewFont = String.fromEnvironment('HOME_REVIEW_CJK_FONT');
      tester.view.physicalSize = Size(reviewFont.isEmpty ? 644 : 620, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> show(double scale) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: MusicMaterialTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SettingsPage(
                settings: AppSettings.defaults,
                selectedSection: SettingsSection.playback,
                embedded: true,
                showToolbar: false,
                onBack: () {},
                onCompactSectionSelected: (_) {},
                onSettingsChanged: (_) async => AppSettingsWriteResult.saved,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      final selector = find.byKey(const ValueKey('settings-quality-selector'));
      await show(1);
      expect(
        find.ancestor(of: selector, matching: find.byType(ListTile)),
        findsOneWidget,
      );
      await show(2);
      expect(
        find.ancestor(of: selector, matching: find.byType(ListTile)),
        findsNothing,
      );
      final editable = tester
          .state<EditableTextState>(
            find.descendant(of: selector, matching: find.byType(EditableText)),
          )
          .renderEditable;
      expect(editable.maxScrollExtent, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

class _PendingSettingsStorage implements AppSettingsDocumentStorage {
  final completion = Completer<void>();
  int writes = 0;
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String document) {
    writes++;
    return completion.future;
  }

  @override
  Future<void> delete() async {}
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
