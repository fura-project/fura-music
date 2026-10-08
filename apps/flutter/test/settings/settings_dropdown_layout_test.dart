import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/settings_page.dart';
import 'package:flutterustmusic/settings/app_settings.dart';

import 'settings_review_harness.dart';

void main() {
  for (final width in [320.0, 390.0, 640.0, 1440.0, 1600.0]) {
    for (final language in ['en', 'zh']) {
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          final name =
              '${width.toInt()}_${language}_${brightness.name}_${scale.toInt()}x';
          testWidgets('choice rows and scrollable sheets fit $name', (
            tester,
          ) async {
            setSettingsViewport(tester, Size(width, 900));
            await _loadReviewFonts(tester);
            final boundary = GlobalKey();
            for (final (section, selectors) in settingsChoiceSelectors) {
              await tester.pumpWidget(
                RepaintBoundary(
                  key: boundary,
                  child: SettingsReviewHarness(
                    key: ValueKey(section),
                    section: section,
                    language: language,
                    brightness: brightness,
                    scale: scale,
                    compact: width < 600,
                  ),
                ),
              );
              await tester.pumpAndSettle();
              // Canonical resting captures must not retain the test pointer or
              // keyboard focus from an earlier interaction.
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              if (section == SettingsSection.appearance) {
                await _capture(tester, boundary, '$name-settings');
              }
              for (final (key, option) in selectors) {
                final row = find.byKey(ValueKey(key));
                await tester.ensureVisible(row);
                for (final text in tester.widgetList<Text>(
                  find.descendant(of: row, matching: find.byType(Text)),
                )) {
                  expect(text.maxLines, isNull);
                  expect(text.overflow, isNull);
                }
                expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
                final detailed = key == 'settings-color-source-selector';
                await tester.tap(
                  detailed
                      ? find.byType(DropdownMenu<AppColorSourcePreference>)
                      : row,
                );
                await tester.pumpAndSettle();
                expect(
                  find.byType(BottomSheet),
                  detailed ? findsNothing : findsOneWidget,
                );
                if (key == 'settings-theme-selector' ||
                    key == 'settings-color-source-selector') {
                  await _capture(
                    tester,
                    boundary,
                    '$name-${key == 'settings-theme-selector' ? 'theme' : 'color'}',
                  );
                }
                // Every option, not only the selected one, stays reachable at
                // large text. The standard scroll view supplies continuation.
                for (final optionTile in tester.widgetList<Widget>(
                  find.byWidgetPredicate((w) => w is RadioListTile<int>),
                )) {
                  final optionFinder = find.byKey(optionTile.key!);
                  await tester.ensureVisible(optionFinder);
                  await tester.pumpAndSettle();
                  expect(optionFinder.hitTestable(), findsOneWidget);
                  expect(
                    tester.getSize(optionFinder).height,
                    greaterThanOrEqualTo(48),
                  );
                }
                final selected = find.byKey(ValueKey(option)).hitTestable();
                await tester.ensureVisible(selected);
                await tester.tap(selected);
                await tester.pumpAndSettle();
                expect(find.byType(BottomSheet), findsNothing);
                expect(tester.takeException(), isNull);
                if (detailed) {
                  expect(
                    find.byKey(
                      const ValueKey('settings-color-palette-preview'),
                    ),
                    findsOneWidget,
                  );
                  await tester.tap(
                    find.byType(DropdownMenu<AppColorSourcePreference>),
                  );
                  await tester.pumpAndSettle();
                  expect(
                    find
                        .byKey(const ValueKey('settings-color-source-system'))
                        .hitTestable(),
                    findsOneWidget,
                  );
                  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                  await tester.pumpAndSettle();
                  expect(
                    find
                        .byKey(const ValueKey('settings-color-source-system'))
                        .hitTestable(),
                    findsNothing,
                  );
                }
              }
            }
          }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
        }
      }
    }
  }

  testWidgets('rendered sheet opening and closing time sequence', (
    tester,
  ) async {
    setSettingsViewport(tester, const Size(1440, 900));
    await _loadReviewFonts(tester);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: const SettingsReviewHarness(language: 'zh'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
    await tester.pump();
    await _capture(tester, boundary, 'motion-open-000ms');
    await tester.pump(const Duration(milliseconds: 125));
    await _capture(tester, boundary, 'motion-open-125ms');
    await tester.pump(const Duration(milliseconds: 125));
    await _capture(tester, boundary, 'motion-open-250ms');
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    await _capture(tester, boundary, 'motion-close-000ms');
    await tester.pump(const Duration(milliseconds: 100));
    await _capture(tester, boundary, 'motion-close-100ms');
    await tester.pump(const Duration(milliseconds: 100));
    await _capture(tester, boundary, 'motion-close-200ms');
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final color = find.byType(DropdownMenu<AppColorSourcePreference>);
    await tester.tap(color);
    await tester.pump();
    await _capture(tester, boundary, 'color-motion-open-000ms');
    await tester.pump(const Duration(milliseconds: 100));
    await _capture(tester, boundary, 'color-motion-open-100ms');
    await tester.pump(const Duration(milliseconds: 100));
    await _capture(tester, boundary, 'color-motion-open-200ms');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await _capture(tester, boundary, 'color-motion-close-000ms');
    await tester.pump(const Duration(milliseconds: 100));
    await _capture(tester, boundary, 'color-motion-close-100ms');
    await tester.pump(const Duration(milliseconds: 100));
    await _capture(tester, boundary, 'color-motion-close-200ms');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-color-palette-preview')),
      findsOneWidget,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
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

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (!const bool.fromEnvironment('SETTINGS_LAYOUT_REVIEW')) return;
  const directory = String.fromEnvironment(
    'SETTINGS_LAYOUT_REVIEW_DIR',
    defaultValue: '/tmp',
  );
  final previousShadows = debugDisableShadows;
  debugDisableShadows = false;
  // Test bindings replace elevations with solid outlines. Render the real
  // shadow only for evidence, restoring the binding invariant before return.
  void repaint(Element element) {
    if (element is RenderObjectElement) element.renderObject.markNeedsPaint();
    element.visitChildren(repaint);
  }

  try {
    tester.binding.rootElement!.visitChildren(repaint);
    await tester.pump();
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  } finally {
    debugDisableShadows = previousShadows;
  }
}
