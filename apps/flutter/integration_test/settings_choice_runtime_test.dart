import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_controller.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/settings/settings_page.dart';
import 'package:flutterustmusic/theme/material_theme.dart';
import 'package:integration_test/integration_test.dart';

/// Real host/plugin presentation with a disposable preference key. Never
/// starts MusicApp, restores credentials, accesses Providers or changes Queue.
/// All platforms exercise the same SDK Flutter BottomSheet and DropdownMenu.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Settings choices use real platform presentation and storage', (
    tester,
  ) async {
    final storage = _CountingStorage(
      SharedPreferencesAppSettingsDocumentStorage(
        documentKey:
            'fura.integration.settings.choice.${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final store = AppSettingsStore(storage: storage);
    final owner = AppSettingsController(
      store,
      null,
      initialSettings: AppSettings.defaults,
    );
    var scale = 1.0;
    Widget fixture() => ListenableBuilder(
      listenable: owner,
      builder: (context, _) => DynamicColorBuilder(
        builder: (light, dark) => MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: MusicMaterialTheme.light(),
          darkTheme: MusicMaterialTheme.dark(),
          themeMode: owner.settings.theme == AppThemePreference.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: SettingsPage(
            settings: owner.settings,
            onSettingsChanged: owner.update,
            onBack: () {},
            onCompactSectionSelected: (_) {},
            compactHierarchy: true,
            compactSectionOpen: true,
            systemLightColorScheme: light,
            systemDarkColorScheme: dark,
          ),
        ),
      ),
    );
    Future<void> waitFor(bool Function() predicate) async {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!predicate() && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(
        predicate(),
        isTrue,
        reason: 'bounded runtime choice did not finish',
      );
      await tester.pumpAndSettle();
    }

    Future<void> choice(String phase, String rowKey, String optionKey) async {
      final row = find.byKey(ValueKey(rowKey));
      await tester.ensureVisible(row);
      final focus = tester
          .widget<InkWell>(
            find.descendant(of: row, matching: find.byType(InkWell)).first,
          )
          .focusNode!;
      await tester.tap(row);
      await tester.pumpAndSettle();
      debugPrint('FURA_SETTINGS_REVIEW phase=$phase ready');
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        tester.getSize(find.byType(BottomSheet)).width,
        MediaQuery.sizeOf(tester.element(row)).width,
      );
      if (optionKey == 'escape') {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else if (optionKey == 'scrim') {
        await tester.tapAt(const Offset(8, 8));
      } else {
        final option = find.byKey(ValueKey(optionKey));
        await tester.ensureVisible(option);
        await tester.tap(option);
      }
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      debugPrint('FURA_SETTINGS_REVIEW phase=$phase success');
    }

    try {
      expect(await storage.read(), isNull);
      await tester.pumpWidget(fixture());
      await tester.pumpAndSettle();
      await choice(
        'theme_light',
        'settings-theme-selector',
        'settings-theme-light',
      );
      expect(owner.settings.theme, AppThemePreference.light);
      await waitFor(() => storage.writes == 1);
      expect((await store.load()).settings.theme, AppThemePreference.light);
      await choice(
        'theme_current',
        'settings-theme-selector',
        'settings-theme-light',
      );
      expect(storage.writes, 1);
      await choice('theme_back', 'settings-theme-selector', 'escape');
      expect(storage.writes, 1);
      await choice('theme_scrim', 'settings-theme-selector', 'scrim');
      expect(storage.writes, 1);
      await choice(
        'theme_dark',
        'settings-theme-selector',
        'settings-theme-dark',
      );
      expect(owner.settings.theme, AppThemePreference.dark);
      await waitFor(() => storage.writes == 2);
      expect((await store.load()).settings.theme, AppThemePreference.dark);
      await choice(
        'theme_dark_current',
        'settings-theme-selector',
        'settings-theme-dark',
      );
      expect(storage.writes, 2);
      final colorRow = find.byKey(
        const ValueKey('settings-color-source-selector'),
      );
      await tester.ensureVisible(colorRow);
      await tester.tap(find.byType(DropdownMenu<AppColorSourcePreference>));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      final system = find
          .byKey(const ValueKey('settings-color-source-system'))
          .hitTestable();
      await tester.ensureVisible(system);
      await tester.tap(system);
      await tester.pumpAndSettle();
      expect(owner.settings.colorSource, AppColorSourcePreference.system);
      await waitFor(() => storage.writes == 3);
      expect(
        (await store.load()).settings.colorSource,
        AppColorSourcePreference.system,
      );
      await tester.tap(find.byType(DropdownMenu<AppColorSourcePreference>));
      await tester.pumpAndSettle();
      await tester.tap(system);
      await tester.pumpAndSettle();
      expect(storage.writes, 3);
      expect(
        find.byKey(const ValueKey('settings-color-palette-preview')),
        findsOneWidget,
      );
      await tester.tap(find.byType(DropdownMenu<AppColorSourcePreference>));
      await tester.pumpAndSettle();
      expect(system, findsOneWidget);
      await tester.ensureVisible(colorRow);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-color-palette-preview')),
        findsOneWidget,
      );
      scale = 2;
      await tester.pumpWidget(fixture());
      await tester.pumpAndSettle();
      await choice('theme_large_cancel', 'settings-theme-selector', 'escape');
      expect(storage.writes, 3);
      await tester.ensureVisible(colorRow);
      await tester.tap(find.byType(DropdownMenu<AppColorSourcePreference>));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-color-palette-preview')),
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
      debugPrint(
        'FURA_SETTINGS_REVIEW all_success writes=3 presentation=SDK_M3_FULL_WIDTH color=DROPDOWN_MENU',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      owner.dispose();
      await storage.delete();
      expect(await storage.read(), isNull);
    }
  });
}

class _CountingStorage implements AppSettingsDocumentStorage {
  _CountingStorage(this.inner);
  final AppSettingsDocumentStorage inner;
  int writes = 0;
  @override
  Future<String?> read() => inner.read();
  @override
  Future<void> write(String document) async {
    await inner.write(document);
    writes++;
  }

  @override
  Future<void> delete() => inner.delete();
}
