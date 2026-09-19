import 'package:flutter/material.dart';
import 'package:flutterustmusic/settings/app_settings.dart';

abstract final class MusicSpacing {
  static const double pageCompact = 20;
  static const double page = 24;
  static const double pageWide = 48;
  static const double panel = 28;
  static const double section = 28;
  static const double contentGap = 16;
  static const double itemGap = 8;
}

abstract final class MusicSizes {
  static const double desktopRail = 80;
  static const double desktopSidebar = 240;
  static const double contentMaxWidth = 1180;
}

abstract final class MusicRadii {
  static const BorderRadius hero = BorderRadius.all(Radius.circular(32));
  static const BorderRadius panel = BorderRadius.all(Radius.circular(28));
  static const BorderRadius artwork = BorderRadius.all(Radius.circular(20));
  static const BorderRadius content = BorderRadius.all(Radius.circular(16));
  static const BorderRadius control = BorderRadius.all(Radius.circular(14));
}

abstract final class MusicMotion {
  static const Duration stateChange = Duration(milliseconds: 240);
}

abstract final class MusicMaterialTheme {
  static const Color seedColor = Color(0xFF31C27C);
  static const Color netEaseSeedColor = Color(0xFFE60026);

  static Color brandSeedFor(AppMusicProvider provider) => switch (provider) {
    AppMusicProvider.qqMusic => seedColor,
    AppMusicProvider.netEaseCloudMusic => netEaseSeedColor,
  };

  static ThemeData light({Color? seed, ColorScheme? colorScheme}) =>
      _create(Brightness.light, seed: seed, colorScheme: colorScheme);

  static ThemeData dark({Color? seed, ColorScheme? colorScheme}) =>
      _create(Brightness.dark, seed: seed, colorScheme: colorScheme);

  static ThemeData _create(
    Brightness brightness, {
    Color? seed,
    ColorScheme? colorScheme,
  }) {
    assert(
      colorScheme == null || colorScheme.brightness == brightness,
      'The supplied ColorScheme must match the requested brightness.',
    );
    final suppliedSystemColors = colorScheme != null;
    final baseColors =
        colorScheme ??
        ColorScheme.fromSeed(
          seedColor: seed ?? seedColor,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        );
    final colors = brightness == Brightness.dark && !suppliedSystemColors
        ? baseColors.copyWith(
            surface: const Color(0xFF121412),
            surfaceDim: const Color(0xFF121412),
            surfaceBright: const Color(0xFF383B38),
            surfaceContainerLowest: const Color(0xFF0D0F0E),
            surfaceContainerLow: const Color(0xFF171918),
            surfaceContainer: const Color(0xFF1C1F1D),
            surfaceContainerHigh: const Color(0xFF252825),
            surfaceContainerHighest: const Color(0xFF303330),
            onSurface: const Color(0xFFE3E4DF),
            onSurfaceVariant: const Color(0xFFC1C8C1),
            outline: const Color(0xFF8B938C),
            outlineVariant: const Color(0xFF414843),
          )
        : baseColors;
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
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(colors.surfaceContainer),
      surfaceTintColor: WidgetStatePropertyAll(colors.surfaceTint),
      elevation: const WidgetStatePropertyAll(3),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: MusicRadii.content),
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: colors.surfaceContainerLowest,
      textTheme: textTheme,
      appBarTheme: AppBarThemeData(
        backgroundColor: colors.surfaceContainerLowest,
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
      menuTheme: MenuThemeData(style: menuStyle),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyLarge?.copyWith(
          color: colors.onSecondaryContainer,
        ),
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: colors.secondaryContainer,
          contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 0),
          constraints: const BoxConstraints(minHeight: 48),
          border: OutlineInputBorder(
            borderRadius: MusicRadii.control,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: MusicRadii.control,
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: MusicRadii.control,
            borderSide: BorderSide(color: colors.primary, width: 2),
          ),
          prefixIconColor: colors.onSecondaryContainer,
          suffixIconColor: colors.onSecondaryContainer,
        ),
        menuStyle: menuStyle,
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
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: colors.primary,
        collapsedIconColor: colors.onSurfaceVariant,
        textColor: colors.onSurface,
        collapsedTextColor: colors.onSurface,
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        childrenPadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.secondaryContainer,
        elevation: 0,
        height: 72,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.secondaryContainer,
        elevation: 0,
        useIndicator: true,
        minWidth: MusicSizes.desktopRail,
        minExtendedWidth: MusicSizes.desktopSidebar,
        groupAlignment: -1,
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
        backgroundColor: colors.surfaceContainerHighest,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: colors.primary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: MusicRadii.control,
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
    );
  }
}
