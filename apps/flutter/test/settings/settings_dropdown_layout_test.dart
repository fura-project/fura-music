import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/settings/settings_page.dart';

import 'settings_review_harness.dart';

void main() {
  for (final width in [320.0, 390.0, 640.0, 1440.0, 1600.0]) {
    for (final language in ['en', 'zh']) {
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          final name =
              '${width.toInt()}_${language}_${brightness.name}_${scale.toInt()}x';
          testWidgets('popup and inline details fit $name', (tester) async {
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
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              if (section == SettingsSection.appearance) {
                await _capture(tester, boundary, '$name-settings');
              }
              for (final (key, option) in selectors) {
                final row = find.byKey(ValueKey(key));
                await tester.ensureVisible(row);
                final detailed = key == 'settings-color-source-selector';
                final beforeSize = tester.getSize(
                  find.byKey(const ValueKey('settings-group')),
                );
                await tester.tap(row);
                await tester.pumpAndSettle();
                expect(find.byType(BottomSheet), findsNothing);
                expect(
                  find.byWidgetPredicate((w) => w is DropdownMenu),
                  findsNothing,
                );
                expect(find.byType(TextField), findsNothing);
                if (!detailed) {
                  expect(
                    tester.getSize(
                      find.byKey(const ValueKey('settings-group')),
                    ),
                    beforeSize,
                  );
                  for (final menu in tester.widgetList<MenuItemButton>(
                    find.byType(MenuItemButton),
                  )) {
                    final entry = find.byKey(menu.key!);
                    await tester.ensureVisible(entry);
                    await tester.pumpAndSettle();
                    expect(entry.hitTestable(), findsOneWidget);
                    final rect = tester.getRect(entry);
                    expect(rect.left, greaterThanOrEqualTo(0));
                    expect(rect.right, lessThanOrEqualTo(width));
                    expect(rect.top, greaterThanOrEqualTo(0));
                    expect(rect.bottom, lessThanOrEqualTo(900));
                    expect(rect.height, greaterThanOrEqualTo(48));
                  }
                }
                if (key == 'settings-theme-selector' || detailed) {
                  await _capture(
                    tester,
                    boundary,
                    '$name-${detailed ? 'color' : 'theme'}',
                  );
                }
                final target = find.byKey(ValueKey(option));
                await tester.ensureVisible(target);
                await tester.tap(target);
                await tester.pumpAndSettle();
                expect(find.byType(MenuItemButton), findsNothing);
                if (detailed) {
                  expect(
                    find.byKey(const ValueKey('settings-color-details')),
                    findsOneWidget,
                  );
                  final preview = find.byKey(
                    const ValueKey('settings-color-palette-preview'),
                  );
                  await tester.ensureVisible(preview);
                  await tester.pumpAndSettle();
                  // Decorative swatches have no input hit target.
                  expect(tester.getRect(preview).top, greaterThanOrEqualTo(0));
                  expect(
                    tester.getRect(preview).bottom,
                    lessThanOrEqualTo(900),
                  );
                  await tester.ensureVisible(row);
                  await tester.pumpAndSettle();
                  await tester.tap(row);
                  await tester.pumpAndSettle();
                  expect(
                    find.byKey(const ValueKey('settings-color-details')),
                    findsNothing,
                  );
                }
                expect(tester.takeException(), isNull);
              }
            }
          });
        }
      }
    }
  }
  testWidgets('inline expansion and collapse motion capture', (tester) async {
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
    final row = find.byKey(const ValueKey('settings-color-source-selector'));
    await tester.tap(row);
    await tester.pump();
    await _capture(tester, boundary, 'color-motion-open-000ms');
    await tester.pump(const Duration(milliseconds: 100));
    await _capture(tester, boundary, 'color-motion-open-100ms');
    await tester.pump(const Duration(milliseconds: 100));
    await _capture(tester, boundary, 'color-motion-open-200ms');
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();
    await _capture(tester, boundary, 'color-motion-close-000ms');
    await tester.pump(const Duration(milliseconds: 100));
    await _capture(tester, boundary, 'color-motion-close-100ms');
    await tester.pump(const Duration(milliseconds: 100));
    await _capture(tester, boundary, 'color-motion-close-200ms');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-color-details')), findsNothing);
  });
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
