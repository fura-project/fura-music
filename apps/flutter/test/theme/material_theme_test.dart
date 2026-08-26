import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

void main() {
  test('builds the same Material foundation for light and dark', () {
    final themes = [MusicMaterialTheme.light(), MusicMaterialTheme.dark()];

    expect(themes[0].colorScheme.brightness, Brightness.light);
    expect(themes[1].colorScheme.brightness, Brightness.dark);

    for (final theme in themes) {
      final colors = theme.colorScheme;
      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, colors.surface);
      expect(theme.appBarTheme.backgroundColor, colors.surface);
      expect(theme.appBarTheme.foregroundColor, colors.onSurface);
      expect(theme.cardTheme.color, colors.surfaceContainerLow);
      expect(theme.dialogTheme.backgroundColor, colors.surfaceContainerHigh);
      expect(
        theme.bottomSheetTheme.modalBackgroundColor,
        colors.surfaceContainerLow,
      );
      expect(theme.popupMenuTheme.color, colors.surfaceContainer);
      expect(theme.inputDecorationTheme.filled, isTrue);
      expect(
        theme.inputDecorationTheme.fillColor,
        colors.surfaceContainerHighest,
      );
      expect(theme.listTileTheme.selectedTileColor, colors.secondaryContainer);
      expect(theme.navigationBarTheme.backgroundColor, colors.surfaceContainer);
      expect(
        theme.navigationBarTheme.indicatorColor,
        colors.secondaryContainer,
      );
      expect(
        theme.navigationRailTheme.backgroundColor,
        colors.surfaceContainerLow,
      );
      expect(
        theme.navigationRailTheme.indicatorColor,
        colors.secondaryContainer,
      );
      expect(theme.dividerTheme.color, colors.outlineVariant);
      expect(theme.progressIndicatorTheme.color, colors.primary);
    }
  });

  test('keeps component geometry and interaction motion centralized', () {
    final theme = MusicMaterialTheme.light();
    final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
    final dialogShape = theme.dialogTheme.shape! as RoundedRectangleBorder;
    final menuShape = theme.popupMenuTheme.shape! as RoundedRectangleBorder;
    final listShape = theme.listTileTheme.shape! as RoundedRectangleBorder;
    final filledShape = theme.filledButtonTheme.style!.shape!.resolve({});

    expect(cardShape.borderRadius, MusicRadii.panel);
    expect(dialogShape.borderRadius, MusicRadii.panel);
    expect(menuShape.borderRadius, MusicRadii.content);
    expect(listShape.borderRadius, MusicRadii.control);
    expect(
      (filledShape! as RoundedRectangleBorder).borderRadius,
      MusicRadii.control,
    );
    expect(MusicMotion.stateChange, const Duration(milliseconds: 240));
  });
}
