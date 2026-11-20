import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

/// Semantic artwork domain used to select a cohesive placeholder icon and
/// surface framing across Material 3 and Magazine Editorial themes.
enum MusicArtworkKind {
  track,
  playingTrack,
  album,
  playlist,
  artist,
  ranking,
  spotlight,
  daily,
  radar,
  newRelease,
}

/// Unified, theme-aware artwork placeholder for loading, missing, and failed
/// artwork slots across the application.
///
/// Adapts icon scale and medallion framing to the rendered container bounds so
/// compact list thumbnails stay uncluttered while shelf cards, collection
/// headers, and Hero banners present intentional visual weight in both
/// Material 3 and Magazine Editorial themes (light & dark).
class MusicArtworkPlaceholder extends StatelessWidget {
  const MusicArtworkPlaceholder({
    this.kind = MusicArtworkKind.track,
    this.icon,
    this.iconSize,
    this.shape = BoxShape.rectangle,
    this.alignment,
    this.label,
    super.key,
  });

  /// Circular avatar placeholder displaying an uppercased initial glyph.
  const MusicArtworkPlaceholder.avatar({required String initial, super.key})
    : kind = MusicArtworkKind.artist,
      icon = null,
      iconSize = null,
      shape = BoxShape.circle,
      alignment = Alignment.center,
      label = initial;

  final MusicArtworkKind kind;
  final IconData? icon;
  final double? iconSize;
  final BoxShape shape;
  final AlignmentGeometry? alignment;
  final String? label;

  static IconData iconForKind(MusicArtworkKind kind) => switch (kind) {
    MusicArtworkKind.track => Icons.music_note_rounded,
    MusicArtworkKind.playingTrack => Icons.graphic_eq_rounded,
    MusicArtworkKind.album => Icons.album_rounded,
    MusicArtworkKind.playlist => Icons.queue_music_rounded,
    MusicArtworkKind.artist => Icons.person_rounded,
    MusicArtworkKind.ranking => Icons.equalizer_rounded,
    MusicArtworkKind.spotlight => Icons.auto_awesome_rounded,
    MusicArtworkKind.daily => Icons.wb_sunny_rounded,
    MusicArtworkKind.radar => Icons.podcasts_rounded,
    MusicArtworkKind.newRelease => Icons.library_music_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final editorial = context.editorialTheme;
    final dark = theme.brightness == Brightness.dark;

    final Color topColor;
    final Color bottomColor;
    final Color medallionFill;
    final Color medallionBorder;
    final Color outerRingBorder;
    final Color glyphColor;

    if (editorial.isEditorial) {
      topColor = editorial.cardSurface;
      bottomColor = Color.lerp(
        editorial.sidebarSurface,
        editorial.hairline,
        dark ? 0.24 : 0.30,
      )!;
      medallionFill = editorial.paperCanvas.withValues(
        alpha: dark ? 0.44 : 0.72,
      );
      medallionBorder = editorial.hairline;
      outerRingBorder = editorial.hairline.withValues(
        alpha: dark ? 0.65 : 0.75,
      );
      glyphColor = kind == MusicArtworkKind.playingTrack
          ? editorial.accentSeal
          : Color.lerp(editorial.inkSecondary, editorial.inkMuted, 0.35)!;
    } else {
      topColor = Color.lerp(
        colors.surfaceContainerHighest,
        colors.primaryContainer,
        dark ? 0.26 : 0.34,
      )!;
      bottomColor = Color.lerp(
        colors.surfaceContainerHigh,
        colors.secondaryContainer,
        dark ? 0.18 : 0.28,
      )!;
      medallionFill = colors.surface.withValues(alpha: dark ? 0.26 : 0.58);
      medallionBorder = colors.outlineVariant.withValues(
        alpha: dark ? 0.45 : 0.62,
      );
      outerRingBorder = colors.outlineVariant.withValues(
        alpha: dark ? 0.26 : 0.38,
      );
      glyphColor = kind == MusicArtworkKind.playingTrack
          ? colors.primary
          : Color.lerp(
              colors.onSurfaceVariant,
              colors.primary,
              dark ? 0.24 : 0.22,
            )!;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [topColor, bottomColor],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rawSide = constraints.biggest.shortestSide;
          final side = rawSide.isFinite && rawSide > 0 ? rawSide : 48.0;
          final resolvedAlignment =
              alignment ??
              (kind == MusicArtworkKind.spotlight && side >= 160
                  ? const Alignment(0, -0.18)
                  : Alignment.center);

          final trimmedLabel = label?.trim();
          if (trimmedLabel != null && trimmedLabel.isNotEmpty) {
            final text = trimmedLabel.toUpperCase();
            final fontSize = (side * 0.40).clamp(13.0, 28.0);
            final style = editorial.isEditorial
                ? editorial.serif(
                    theme.textTheme.titleMedium,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: glyphColor,
                    height: 1,
                  )
                : theme.textTheme.titleMedium?.copyWith(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: glyphColor,
                    height: 1,
                  );
            return Align(
              alignment: resolvedAlignment,
              child: Padding(
                padding: EdgeInsets.all(math.max(2.0, side * 0.14)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(text, maxLines: 1, softWrap: false, style: style),
                ),
              ),
            );
          }

          final resolvedIcon = icon ?? iconForKind(kind);

          if (side < 76) {
            final maxCompact = math.min(28.0, side * 0.62);
            final minCompact = math.min(16.0, maxCompact);
            final compactSize = (iconSize ?? side * 0.44).clamp(
              minCompact,
              maxCompact,
            );
            return Align(
              alignment: resolvedAlignment,
              child: Icon(resolvedIcon, size: compactSize, color: glyphColor),
            );
          }

          final isLarge = side >= 180;
          final computedIconSize = isLarge
              ? (side * 0.20).clamp(36.0, 52.0)
              : (side * 0.25).clamp(24.0, 38.0);
          final maxMedallion = side * 0.64;
          final minMedallion = math.min(44.0, maxMedallion);
          final maxIcon = math.max(16.0, maxMedallion * 0.56);
          final resolvedIconSize = (iconSize ?? computedIconSize).clamp(
            16.0,
            maxIcon,
          );
          final medallionDiameter = (resolvedIconSize * (isLarge ? 1.95 : 1.9))
              .clamp(minMedallion, maxMedallion);

          Widget emblem = Container(
            width: medallionDiameter,
            height: medallionDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: medallionFill,
              border: Border.all(color: medallionBorder),
            ),
            alignment: Alignment.center,
            child: Icon(
              resolvedIcon,
              size: resolvedIconSize,
              color: glyphColor,
            ),
          );

          if (isLarge) {
            final maxRing = side * 0.76;
            final minRing = math.min(medallionDiameter + 12, maxRing);
            final ringDiameter = (medallionDiameter * 1.38).clamp(
              minRing,
              maxRing,
            );
            emblem = Container(
              width: ringDiameter,
              height: ringDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: outerRingBorder),
              ),
              alignment: Alignment.center,
              child: emblem,
            );
          }

          return Align(alignment: resolvedAlignment, child: emblem);
        },
      ),
    );
  }
}
