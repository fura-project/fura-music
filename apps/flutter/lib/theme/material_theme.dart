import 'package:flutter/material.dart';

abstract final class MusicSpacing {
  static const double pageCompact = 20;
  static const double page = 24;
  static const double pageWide = 48;
  static const double panel = 28;
  static const double section = 28;
  static const double contentGap = 16;
  static const double itemGap = 8;
}

abstract final class MusicRadii {
  static const BorderRadius panel = BorderRadius.all(Radius.circular(28));
  static const BorderRadius artwork = BorderRadius.all(Radius.circular(20));
  static const BorderRadius content = BorderRadius.all(Radius.circular(16));
  static const BorderRadius control = BorderRadius.all(Radius.circular(14));
}

abstract final class MusicMotion {
  static const Duration stateChange = Duration(milliseconds: 240);
}

abstract final class MusicMaterialTheme {
  static const Color seedColor = Color(0xFF24B86A);

  static ThemeData light() => _create(Brightness.light);

  static ThemeData dark() => _create(Brightness.dark);

  static ThemeData _create(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final base = ThemeData(colorScheme: colors, useMaterial3: true);
    final textTheme = base.textTheme.copyWith(
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.05,
        letterSpacing: -1,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.12,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.16,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: MusicRadii.control,
    );

    return base.copyWith(
      scaffoldBackgroundColor: colors.surface,
      textTheme: textTheme,
      appBarTheme: AppBarThemeData(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: colors.surfaceTint,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: colors.onSurface),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainerLow,
        surfaceTintColor: colors.surfaceTint,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: MusicRadii.panel),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        surfaceTintColor: colors.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: MusicRadii.panel),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerLow,
        modalBackgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: colors.surfaceTint,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceContainer,
        surfaceTintColor: colors.surfaceTint,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: MusicRadii.content),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: MusicRadii.content,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: MusicRadii.content,
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: MusicRadii.content,
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: MusicRadii.control),
        iconColor: colors.onSurfaceVariant,
        selectedColor: colors.onSecondaryContainer,
        selectedTileColor: colors.secondaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.secondaryContainer,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.secondaryContainer,
        elevation: 0,
        useIndicator: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(controlShape)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(controlShape)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(controlShape)),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
        circularTrackColor: colors.surfaceContainerHighest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onInverseSurface,
        ),
        actionTextColor: colors.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: MusicRadii.control),
      ),
    );
  }
}
