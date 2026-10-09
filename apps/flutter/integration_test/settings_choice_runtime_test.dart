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

/// The real Linux runner, production SettingsPage and preference plugin.
/// No MusicApp, credentials, Provider calls or existing settings document.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('two official Settings representatives on real Linux', (
    tester,
  ) async {
    final storage = _Storage(
      SharedPreferencesAppSettingsDocumentStorage(
        documentKey:
            'fura.integration.settings.representatives.${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final store = AppSettingsStore(storage: storage);
    final owner = AppSettingsController(
      store,
      null,
      initialSettings: AppSettings.defaults,
    );
    try {
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: owner,
          builder: (context, _) => DynamicColorBuilder(
            builder: (light, dark) => MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: MusicMaterialTheme.light(),
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
        ),
      );
      await tester.pumpAndSettle();
      final theme = find.byKey(const ValueKey('settings-theme-selector'));
      for (final choice in [
        'escape',
        'settings-theme-system',
        'settings-theme-light',
      ]) {
        await tester.tap(theme);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        if (choice == 'escape') {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tap(find.byKey(ValueKey(choice)));
        }
        await tester.pumpAndSettle();
        await _wait(
          tester,
          () =>
              owner.settings.theme ==
              (choice == 'settings-theme-light'
                  ? AppThemePreference.light
                  : AppThemePreference.system),
        );
        expect(find.byType(BottomSheet), findsNothing);
      }
      expect(storage.writes, 1);
      final dropdown = find.byType(DropdownMenu<AppColorSourcePreference>);
      for (final choice in [
        'escape',
        'settings-color-source-brand',
        'settings-color-source-system',
      ]) {
        await tester.tap(
          find.descendant(of: dropdown, matching: find.byType(TextField)),
        );
        await tester.pumpAndSettle();
        if (choice == 'escape') {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tap(find.byKey(ValueKey(choice)).hitTestable());
        }
        await tester.pumpAndSettle();
        await _wait(
          tester,
          () =>
              owner.settings.colorSource ==
              (choice == 'settings-color-source-system'
                  ? AppColorSourcePreference.system
                  : AppColorSourcePreference.brand),
        );
      }
      expect(storage.writes, 2);
      final readback = await store.load();
      expect(readback.settings.theme, AppThemePreference.light);
      expect(readback.settings.colorSource, AppColorSourcePreference.system);
      expect(tester.takeException(), isNull);
      debugPrint(
        'FURA_SETTINGS_REVIEW representatives=THEME_MODAL_COLOR_DROPDOWN writes=2 readback=success',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      owner.dispose();
      await storage.delete();
    }
  });
}

Future<void> _wait(WidgetTester tester, bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  expect(predicate(), isTrue, reason: 'bounded representative Settings save');
  await tester.pumpAndSettle();
}

class _Storage implements AppSettingsDocumentStorage {
  _Storage(this.delegate);
  final AppSettingsDocumentStorage delegate;
  int writes = 0;
  @override
  Future<String?> read() => delegate.read();
  @override
  Future<void> write(String document) {
    writes++;
    return delegate.write(document);
  }

  @override
  Future<void> delete() => delegate.delete();
}
