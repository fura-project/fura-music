import 'package:flutter/material.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

const String editorialSerifFontFamily = 'Georgia';

const List<String> editorialSerifFontFallback = <String>[
  'Noto Serif CJK SC',
  'Source Han Serif SC',
  'Songti SC',
  'STSong',
  'SimSun',
  'Noto Serif',
  'Liberation Serif',
  'DejaVu Serif',
  'Times New Roman',
  'serif',
];

@immutable
class MusicEditorialTheme extends ThemeExtension<MusicEditorialTheme> {
  const MusicEditorialTheme({
    required this.isEditorial,
    required this.paperCanvas,
    required this.sidebarSurface,
    required this.cardSurface,
    required this.hairline,
    required this.ruleStrong,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkMuted,
    required this.accentSeal,
    required this.cardRadius,
    required this.artworkRadius,
    required this.controlRadius,
    required this.galleryShadow,
  });

  static const standard = MusicEditorialTheme(
    isEditorial: false,
    paperCanvas: Color(0xFFFFFFFF),
    sidebarSurface: Color(0xFFF5F5F5),
    cardSurface: Color(0xFFF5F5F5),
    hairline: Color(0xFFE0E0E0),
    ruleStrong: Color(0xFFBDBDBD),
    inkPrimary: Color(0xFF1A1A1A),
    inkSecondary: Color(0xFF5F5F5F),
    inkMuted: Color(0xFF8C8C8C),
    accentSeal: MusicMaterialTheme.seedColor,
    cardRadius: MusicRadii.panel,
    artworkRadius: MusicRadii.artwork,
    controlRadius: MusicRadii.control,
    galleryShadow: <BoxShadow>[],
  );

  static const editorialLight = MusicEditorialTheme(
    isEditorial: true,
    paperCanvas: Color(0xFFFAF8F4),
    sidebarSurface: Color(0xFFF3EFE8),
    cardSurface: Color(0xFFF6F3EC),
    hairline: Color(0xFFE3DDD1),
    ruleStrong: Color(0xFFC1B8A9),
    inkPrimary: Color(0xFF171513),
    inkSecondary: Color(0xFF5D574F),
    inkMuted: Color(0xFF8C8479),
    accentSeal: Color(0xFF8E3B2E),
    cardRadius: BorderRadius.all(Radius.circular(4)),
    artworkRadius: BorderRadius.all(Radius.circular(4)),
    controlRadius: BorderRadius.all(Radius.circular(4)),
    galleryShadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x1E171513),
        blurRadius: 34,
        spreadRadius: -4,
        offset: Offset(0, 18),
      ),
      BoxShadow(color: Color(0x12171513), blurRadius: 10, offset: Offset(0, 4)),
    ],
  );

  static const editorialDark = MusicEditorialTheme(
    isEditorial: true,
    paperCanvas: Color(0xFF141210),
    sidebarSurface: Color(0xFF1A1714),
    cardSurface: Color(0xFF1D1A17),
    hairline: Color(0xFF312C26),
    ruleStrong: Color(0xFF5A5249),
    inkPrimary: Color(0xFFF2EDE4),
    inkSecondary: Color(0xFFB4ABA0),
    inkMuted: Color(0xFF7B7369),
    accentSeal: Color(0xFFD88A72),
    cardRadius: BorderRadius.all(Radius.circular(4)),
    artworkRadius: BorderRadius.all(Radius.circular(4)),
    controlRadius: BorderRadius.all(Radius.circular(4)),
    galleryShadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 40,
        spreadRadius: -4,
        offset: Offset(0, 20),
      ),
      BoxShadow(color: Color(0x3D000000), blurRadius: 12, offset: Offset(0, 5)),
    ],
  );

  final bool isEditorial;
  final Color paperCanvas;
  final Color sidebarSurface;
  final Color cardSurface;
  final Color hairline;
  final Color ruleStrong;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkMuted;
  final Color accentSeal;
  final BorderRadius cardRadius;
  final BorderRadius artworkRadius;
  final BorderRadius controlRadius;
  final List<BoxShadow> galleryShadow;

  static MusicEditorialTheme of(BuildContext context) =>
      Theme.of(context).extension<MusicEditorialTheme>() ?? standard;

  TextStyle serif(
    TextStyle? base, {
    FontWeight? fontWeight,
    double? fontSize,
    double? height,
    double? letterSpacing,
    Color? color,
    FontStyle? fontStyle,
  }) => (base ?? const TextStyle()).copyWith(
    fontFamily: editorialSerifFontFamily,
    fontFamilyFallback: editorialSerifFontFallback,
    fontWeight: fontWeight,
    fontSize: fontSize,
    height: height,
    letterSpacing: letterSpacing,
    color: color,
    fontStyle: fontStyle,
  );

  TextStyle eyebrow(TextStyle? base, {Color? color}) =>
      (base ?? const TextStyle(fontSize: 11)).copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        height: 1.2,
        color: color ?? inkSecondary,
      );

  @override
  MusicEditorialTheme copyWith({
    bool? isEditorial,
    Color? paperCanvas,
    Color? sidebarSurface,
    Color? cardSurface,
    Color? hairline,
    Color? ruleStrong,
    Color? inkPrimary,
    Color? inkSecondary,
    Color? inkMuted,
    Color? accentSeal,
    BorderRadius? cardRadius,
    BorderRadius? artworkRadius,
    BorderRadius? controlRadius,
    List<BoxShadow>? galleryShadow,
  }) => MusicEditorialTheme(
    isEditorial: isEditorial ?? this.isEditorial,
    paperCanvas: paperCanvas ?? this.paperCanvas,
    sidebarSurface: sidebarSurface ?? this.sidebarSurface,
    cardSurface: cardSurface ?? this.cardSurface,
    hairline: hairline ?? this.hairline,
    ruleStrong: ruleStrong ?? this.ruleStrong,
    inkPrimary: inkPrimary ?? this.inkPrimary,
    inkSecondary: inkSecondary ?? this.inkSecondary,
    inkMuted: inkMuted ?? this.inkMuted,
    accentSeal: accentSeal ?? this.accentSeal,
    cardRadius: cardRadius ?? this.cardRadius,
    artworkRadius: artworkRadius ?? this.artworkRadius,
    controlRadius: controlRadius ?? this.controlRadius,
    galleryShadow: galleryShadow ?? this.galleryShadow,
  );

  @override
  MusicEditorialTheme lerp(
    covariant ThemeExtension<MusicEditorialTheme>? other,
    double t,
  ) {
    if (other is! MusicEditorialTheme) return this;
    return MusicEditorialTheme(
      isEditorial: t < 0.5 ? isEditorial : other.isEditorial,
      paperCanvas: Color.lerp(paperCanvas, other.paperCanvas, t)!,
      sidebarSurface: Color.lerp(sidebarSurface, other.sidebarSurface, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      ruleStrong: Color.lerp(ruleStrong, other.ruleStrong, t)!,
      inkPrimary: Color.lerp(inkPrimary, other.inkPrimary, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      accentSeal: Color.lerp(accentSeal, other.accentSeal, t)!,
      cardRadius: BorderRadius.lerp(cardRadius, other.cardRadius, t)!,
      artworkRadius: BorderRadius.lerp(artworkRadius, other.artworkRadius, t)!,
      controlRadius: BorderRadius.lerp(controlRadius, other.controlRadius, t)!,
      galleryShadow:
          BoxShadow.lerpList(galleryShadow, other.galleryShadow, t) ??
          const <BoxShadow>[],
    );
  }
}

extension MusicEditorialContext on BuildContext {
  MusicEditorialTheme get editorialTheme => MusicEditorialTheme.of(this);
  bool get isEditorialTheme => editorialTheme.isEditorial;
}

ThemeData buildEditorialTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final tokens = dark
      ? MusicEditorialTheme.editorialDark
      : MusicEditorialTheme.editorialLight;

  final ColorScheme colors = dark
      ? const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFFF2EDE4),
          onPrimary: Color(0xFF151311),
          primaryContainer: Color(0xFF2E2923),
          onPrimaryContainer: Color(0xFFF2EDE4),
          secondary: Color(0xFFC9BFB2),
          onSecondary: Color(0xFF1A1714),
          secondaryContainer: Color(0xFF2B2722),
          onSecondaryContainer: Color(0xFFF2EDE4),
          tertiary: Color(0xFFD88A72),
          onTertiary: Color(0xFF2B120B),
          tertiaryContainer: Color(0xFF47251C),
          onTertiaryContainer: Color(0xFFF8DDD4),
          error: Color(0xFFE58A80),
          onError: Color(0xFF2E0F0C),
          errorContainer: Color(0xFF561D17),
          onErrorContainer: Color(0xFFFADBD7),
          surface: Color(0xFF141210),
          onSurface: Color(0xFFF2EDE4),
          surfaceDim: Color(0xFF100E0C),
          surfaceBright: Color(0xFF332E28),
          surfaceContainerLowest: Color(0xFF141210),
          surfaceContainerLow: Color(0xFF1A1714),
          surfaceContainer: Color(0xFF211E1A),
          surfaceContainerHigh: Color(0xFF2A2621),
          surfaceContainerHighest: Color(0xFF35302A),
          onSurfaceVariant: Color(0xFFB4ABA0),
          outline: Color(0xFF5A5249),
          outlineVariant: Color(0xFF312C26),
          shadow: Color(0xFF000000),
          scrim: Color(0xFF000000),
          inverseSurface: Color(0xFFF2EDE4),
          onInverseSurface: Color(0xFF171513),
          inversePrimary: Color(0xFF8E3B2E),
          surfaceTint: Colors.transparent,
        )
      : const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF171513),
          onPrimary: Color(0xFFFAF8F4),
          primaryContainer: Color(0xFFE9E2D6),
          onPrimaryContainer: Color(0xFF171513),
          secondary: Color(0xFF564F47),
          onSecondary: Color(0xFFFAF8F4),
          secondaryContainer: Color(0xFFEAE4D9),
          onSecondaryContainer: Color(0xFF171513),
          tertiary: Color(0xFF8E3B2E),
          onTertiary: Color(0xFFFAF8F4),
          tertiaryContainer: Color(0xFFF2DDD7),
          onTertiaryContainer: Color(0xFF3B150E),
          error: Color(0xFF9E2A2B),
          onError: Color(0xFFFAF8F4),
          errorContainer: Color(0xFFF7DADA),
          onErrorContainer: Color(0xFF410E0E),
          surface: Color(0xFFFAF8F4),
          onSurface: Color(0xFF171513),
          surfaceDim: Color(0xFFEAE5DC),
          surfaceBright: Color(0xFFFFFDF9),
          surfaceContainerLowest: Color(0xFFFAF8F4),
          surfaceContainerLow: Color(0xFFF3EFE8),
          surfaceContainer: Color(0xFFEDE8DF),
          surfaceContainerHigh: Color(0xFFE6E0D5),
          surfaceContainerHighest: Color(0xFFDDD6C9),
          onSurfaceVariant: Color(0xFF5D574F),
          outline: Color(0xFFC1B8A9),
          outlineVariant: Color(0xFFE3DDD1),
          shadow: Color(0xFF171513),
          scrim: Color(0xFF12100E),
          inverseSurface: Color(0xFF1B1916),
          onInverseSurface: Color(0xFFFAF8F4),
          inversePrimary: Color(0xFFD88A72),
          surfaceTint: Colors.transparent,
        );

  final base = ThemeData(colorScheme: colors, useMaterial3: true);
  final textTheme = base.textTheme.copyWith(
    displayLarge: tokens.serif(
      base.textTheme.displayLarge,
      fontWeight: FontWeight.w500,
      height: 1.06,
      letterSpacing: -0.8,
      color: colors.onSurface,
    ),
    displayMedium: tokens.serif(
      base.textTheme.displayMedium,
      fontWeight: FontWeight.w500,
      height: 1.08,
      letterSpacing: -0.6,
      color: colors.onSurface,
    ),
    displaySmall: tokens.serif(
      base.textTheme.displaySmall,
      fontWeight: FontWeight.w500,
      height: 1.1,
      letterSpacing: -0.4,
      color: colors.onSurface,
    ),
    headlineLarge: tokens.serif(
      base.textTheme.headlineLarge,
      fontWeight: FontWeight.w600,
      height: 1.14,
      letterSpacing: -0.4,
      color: colors.onSurface,
    ),
    headlineMedium: tokens.serif(
      base.textTheme.headlineMedium,
      fontWeight: FontWeight.w600,
      height: 1.18,
      letterSpacing: -0.25,
      color: colors.onSurface,
    ),
    headlineSmall: tokens.serif(
      base.textTheme.headlineSmall,
      fontWeight: FontWeight.w600,
      height: 1.22,
      letterSpacing: -0.15,
      color: colors.onSurface,
    ),
    titleLarge: tokens.serif(
      base.textTheme.titleLarge,
      fontWeight: FontWeight.w600,
      height: 1.25,
      color: colors.onSurface,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.05,
      color: colors.onSurface,
    ),
    titleSmall: base.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: colors.onSurface,
    ),
    labelMedium: base.textTheme.labelMedium?.copyWith(
      letterSpacing: 0.6,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: base.textTheme.labelSmall?.copyWith(
      letterSpacing: 0.7,
      fontWeight: FontWeight.w600,
    ),
  );

  final controlShape = RoundedRectangleBorder(
    borderRadius: tokens.controlRadius,
  );
  final cardShape = RoundedRectangleBorder(
    borderRadius: tokens.cardRadius,
    side: BorderSide(color: tokens.hairline),
  );
  final menuStyle = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(tokens.paperCanvas),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(2),
    side: WidgetStatePropertyAll(BorderSide(color: tokens.hairline)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: tokens.cardRadius),
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: tokens.paperCanvas,
    textTheme: textTheme,
    extensions: <ThemeExtension<dynamic>>[tokens],
    appBarTheme: AppBarThemeData(
      backgroundColor: tokens.paperCanvas,
      foregroundColor: colors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: colors.onSurface),
    ),
    cardTheme: CardThemeData(
      color: tokens.cardSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.paperCanvas,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: tokens.hairline),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.paperCanvas,
      modalBackgroundColor: tokens.paperCanvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        side: BorderSide(color: tokens.hairline),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.paperCanvas,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: tokens.cardRadius,
        side: BorderSide(color: tokens.hairline),
      ),
    ),
    menuTheme: MenuThemeData(style: menuStyle),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: textTheme.bodyLarge?.copyWith(color: colors.onSurface),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: tokens.cardSurface,
        contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 0),
        constraints: const BoxConstraints(minHeight: 48),
        border: OutlineInputBorder(
          borderRadius: tokens.controlRadius,
          borderSide: BorderSide(color: tokens.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: tokens.controlRadius,
          borderSide: BorderSide(color: tokens.hairline),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: tokens.controlRadius,
          borderSide: BorderSide(color: tokens.hairline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: tokens.controlRadius,
          borderSide: BorderSide(color: tokens.inkPrimary, width: 1.5),
        ),
        prefixIconColor: colors.onSurface,
        suffixIconColor: colors.onSurface,
      ),
      menuStyle: menuStyle,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: tokens.cardSurface,
      border: OutlineInputBorder(
        borderRadius: tokens.controlRadius,
        borderSide: BorderSide(color: tokens.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: tokens.controlRadius,
        borderSide: BorderSide(color: tokens.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: tokens.controlRadius,
        borderSide: BorderSide(color: tokens.inkPrimary, width: 1.4),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: tokens.controlRadius),
      iconColor: colors.onSurfaceVariant,
      selectedColor: colors.onSurface,
      selectedTileColor: colors.secondaryContainer.withValues(alpha: 0.55),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: colors.onSurface,
      collapsedIconColor: colors.onSurfaceVariant,
      textColor: colors.onSurface,
      collapsedTextColor: colors.onSurface,
      tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.paperCanvas,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: tokens.controlRadius,
      ),
      elevation: 0,
      height: 72,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: tokens.sidebarSurface,
      indicatorColor: colors.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: tokens.controlRadius,
      ),
      elevation: 0,
      useIndicator: true,
      minWidth: MusicSizes.desktopRail,
      minExtendedWidth: MusicSizes.desktopSidebar,
      groupAlignment: -1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(controlShape),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(controlShape),
        side: WidgetStatePropertyAll(BorderSide(color: tokens.ruleStrong)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(controlShape)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(controlShape),
        side: WidgetStatePropertyAll(BorderSide(color: tokens.hairline)),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.inkPrimary;
          }
          return tokens.cardSurface;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.paperCanvas;
          }
          return tokens.inkSecondary;
        }),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: tokens.inkPrimary,
      unselectedLabelColor: tokens.inkSecondary,
      indicatorColor: tokens.inkPrimary,
      dividerColor: tokens.hairline,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.cardSurface,
      selectedColor: tokens.inkPrimary,
      labelStyle: textTheme.labelMedium?.copyWith(color: tokens.inkPrimary),
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(
        color: tokens.paperCanvas,
      ),
      side: BorderSide(color: tokens.hairline),
      shape: controlShape,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tokens.inkPrimary,
        borderRadius: tokens.controlRadius,
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: tokens.paperCanvas),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.hairline,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: tokens.hairline,
      circularTrackColor: tokens.hairline,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 2,
      activeTrackColor: tokens.inkPrimary,
      inactiveTrackColor: tokens.hairline,
      thumbColor: tokens.inkPrimary,
      overlayColor: tokens.inkPrimary.withValues(alpha: 0.1),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tokens.inkPrimary,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: tokens.paperCanvas,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: colors.inversePrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: tokens.controlRadius),
    ),
  );
}
