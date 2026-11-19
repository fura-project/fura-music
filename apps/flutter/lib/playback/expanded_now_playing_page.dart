import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/comments/track_comments_surface.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/lyrics/lyric_panel.dart';
import 'package:flutterustmusic/music_video/track_music_video_engine.dart';
import 'package:flutterustmusic/music_video/track_music_video_gateway.dart';
import 'package:flutterustmusic/music_video/track_music_video_surface.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

typedef ArtworkImageProviderBuilder = ImageProvider<Object> Function(
  String artworkUri,
);

typedef ArtworkColorSchemeLoader = Future<ColorScheme> Function({
  required ImageProvider<Object> provider,
  required Brightness brightness,
});

class ArtworkColorSchemeCache {
  ArtworkColorSchemeCache({
    this.maximumEntries = 8,
    this.artworkImageProviderBuilder = _networkArtworkProvider,
    this.artworkColorSchemeLoader = _materialArtworkColorScheme,
  }) : assert(maximumEntries > 0);

  final int maximumEntries;
  final ArtworkImageProviderBuilder artworkImageProviderBuilder;
  final ArtworkColorSchemeLoader artworkColorSchemeLoader;
  final LinkedHashMap<_ArtworkPaletteKey, ColorScheme> _resolved =
      LinkedHashMap<_ArtworkPaletteKey, ColorScheme>();
  final Map<_ArtworkPaletteKey, Future<ColorScheme?>> _pending =
      <_ArtworkPaletteKey, Future<ColorScheme?>>{};
  int _generation = 0;

  ColorScheme? lookup({
    required String artworkUri,
    required Brightness brightness,
  }) {
    final key = _ArtworkPaletteKey(artworkUri, brightness);
    final scheme = _resolved.remove(key);
    if (scheme != null) _resolved[key] = scheme;
    return scheme;
  }

  Future<ColorScheme?> resolve({
    required String artworkUri,
    required Brightness brightness,
  }) {
    final cached = lookup(artworkUri: artworkUri, brightness: brightness);
    if (cached != null) return Future<ColorScheme?>.value(cached);
    final key = _ArtworkPaletteKey(artworkUri, brightness);
    final existing = _pending[key];
    if (existing != null) return existing;
    late final Future<ColorScheme?> loadFuture;
    loadFuture = _load(key, _generation, () => _pending[key] == loadFuture);
    _pending[key] = loadFuture;
    return loadFuture;
  }

  void clear() {
    _generation += 1;
    _resolved.clear();
    _pending.clear();
  }

  Future<ColorScheme?> _load(
    _ArtworkPaletteKey key,
    int generation,
    bool Function() isCurrentPending,
  ) async {
    try {
      final provider = artworkImageProviderBuilder(key.artworkUri);
      final scheme = await artworkColorSchemeLoader(
        provider: provider,
        brightness: key.brightness,
      );
      if (generation == _generation) {
        _resolved[key] = scheme;
        while (_resolved.length > maximumEntries) {
          _resolved.remove(_resolved.keys.first);
        }
      }
      return scheme;
    } on Object {
      return null;
    } finally {
      if (isCurrentPending()) {
        _pending.remove(key);
      }
    }
  }
}

@immutable
class _ArtworkPaletteKey {
  const _ArtworkPaletteKey(this.artworkUri, this.brightness);

  final String artworkUri;
  final Brightness brightness;

  @override
  bool operator ==(Object other) =>
      other is _ArtworkPaletteKey &&
      other.artworkUri == artworkUri &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(artworkUri, brightness);
}

class ExpandedNowPlayingPage extends StatefulWidget {
  const ExpandedNowPlayingPage({
    required this.controller,
    required this.onBack,
    required this.onSignInAgain,
    this.qualityPreference,
    this.onQualityPreferenceChanged,
    this.lyricAuxiliaryMode = LyricAuxiliaryMode.auto,
    this.onLyricAuxiliaryModeChanged,
    this.commentsGateway = const RustTrackCommentGateway(),
    this.musicVideoGateway = const RustTrackMusicVideoGateway(),
    this.musicVideoEngine = const MediaKitTrackMusicVideoEngine(),
    this.artworkImageProviderBuilder = _networkArtworkProvider,
    this.artworkColorSchemeLoader = _materialArtworkColorScheme,
    this.artworkColorSchemeCache,
    super.key,
  });

  final QueuePlaybackController controller;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final AppPlaybackQualityPreference? qualityPreference;
  final PlaybackQualityPreferenceChanged? onQualityPreferenceChanged;
  final LyricAuxiliaryMode lyricAuxiliaryMode;
  final LyricAuxiliaryModeChanged? onLyricAuxiliaryModeChanged;
  final TrackCommentGateway commentsGateway;
  final TrackMusicVideoGateway musicVideoGateway;
  final TrackMusicVideoEngine musicVideoEngine;
  final ArtworkImageProviderBuilder artworkImageProviderBuilder;
  final ArtworkColorSchemeLoader artworkColorSchemeLoader;
  final ArtworkColorSchemeCache? artworkColorSchemeCache;

  @override
  State<ExpandedNowPlayingPage> createState() => _ExpandedNowPlayingPageState();
}

class _ExpandedNowPlayingPageState extends State<ExpandedNowPlayingPage> {
  String? _resolvedArtworkUri;
  Brightness? _resolvedBrightness;
  ColorScheme? _artworkColorScheme;
  late ArtworkColorSchemeCache _paletteCache;
  int _colorRequestGeneration = 0;
  bool _animateThemeChanges = false;

  @override
  void initState() {
    super.initState();
    _paletteCache = _cacheFor(widget);
    widget.controller.currentTrackListenable.addListener(
      _handleControllerChanged,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveArtworkColors(notify: false, animateTransition: false);
  }

  @override
  void reassemble() {
    super.reassemble();
    _paletteCache.clear();
    _resolvedArtworkUri = null;
    _resolvedBrightness = null;
    _artworkColorScheme = null;
    _animateThemeChanges = false;
    _resolveArtworkColors(notify: false, animateTransition: false);
  }

  @override
  void didUpdateWidget(ExpandedNowPlayingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.currentTrackListenable.removeListener(
        _handleControllerChanged,
      );
      widget.controller.currentTrackListenable.addListener(
        _handleControllerChanged,
      );
    }
    final paletteSourceChanged =
        oldWidget.artworkColorSchemeCache != widget.artworkColorSchemeCache ||
        oldWidget.artworkImageProviderBuilder !=
            widget.artworkImageProviderBuilder ||
        oldWidget.artworkColorSchemeLoader != widget.artworkColorSchemeLoader;
    if (paletteSourceChanged) _paletteCache = _cacheFor(widget);
    if (oldWidget.controller != widget.controller || paletteSourceChanged) {
      _resolvedArtworkUri = null;
      _resolvedBrightness = null;
      _animateThemeChanges = false;
      _resolveArtworkColors(notify: false, animateTransition: false);
    }
  }

  @override
  void dispose() {
    _colorRequestGeneration += 1;
    widget.controller.currentTrackListenable.removeListener(
      _handleControllerChanged,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final rawArtworkColors = _artworkColorScheme;
    final colors = rawArtworkColors == null
        ? baseTheme.colorScheme
        : normalizeArtworkColorScheme(
            rawArtworkColors,
            fallback: baseTheme.colorScheme,
          );
    final atmosphere = ArtworkAtmosphere.resolve(colors);
    final pageTheme = baseTheme.copyWith(
      colorScheme: colors,
      extensions: <ThemeExtension>[
        ...baseTheme.extensions.values.cast<ThemeExtension>(),
        atmosphere,
      ],
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: colors.surfaceContainerLow,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: baseTheme.dividerTheme.copyWith(
        color: colors.outlineVariant,
      ),
      progressIndicatorTheme: baseTheme.progressIndicatorTheme.copyWith(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
        circularTrackColor: colors.surfaceContainerHighest,
      ),
    );
    final animateTheme =
        _animateThemeChanges && !MediaQuery.disableAnimationsOf(context);
    return AnimatedTheme(
      data: pageTheme,
      duration: animateTheme ? MusicMotion.stateChange : Duration.zero,
      curve: Curves.easeOutCubic,
      child: Builder(
        builder: (context) => PlaybackShortcuts(
          controller: widget.controller,
          child: Scaffold(
            key: const ValueKey('expanded-now-playing-page'),
            appBar: AppBar(
              flexibleSpace: const _ExpandedNowPlayingTopBarBackdrop(),
              leading: IconButton(
                key: const ValueKey('expanded-now-playing-back'),
                tooltip: context.l10n.nowPlayingBack,
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              title: Text(context.l10n.nowPlayingTitle),
            ),
            body: _ExpandedNowPlayingBackdrop(
              key: const ValueKey('expanded-now-playing-palette-ready'),
              child: _ExpandedNowPlayingBody(
                controller: widget.controller,
                onBack: widget.onBack,
                onSignInAgain: widget.onSignInAgain,
                commentsGateway: widget.commentsGateway,
                musicVideoGateway: widget.musicVideoGateway,
                musicVideoEngine: widget.musicVideoEngine,
                artworkImageProviderBuilder: widget.artworkImageProviderBuilder,
                lyricAuxiliaryMode: widget.lyricAuxiliaryMode,
              ),
            ),
            bottomNavigationBar: NowPlayingBar.expanded(
              controller: widget.controller,
              onSignInAgain: widget.onSignInAgain,
              qualityPreference: widget.qualityPreference,
              onQualityPreferenceChanged: widget.onQualityPreferenceChanged,
              lyricAuxiliaryMode: widget.lyricAuxiliaryMode,
              onLyricAuxiliaryModeChanged: widget.onLyricAuxiliaryModeChanged,
            ),
          ),
        ),
      ),
    );
  }

  void _handleControllerChanged() =>
      _resolveArtworkColors(animateTransition: true);

  ArtworkColorSchemeCache _cacheFor(ExpandedNowPlayingPage page) =>
      page.artworkColorSchemeCache ??
      ArtworkColorSchemeCache(
        artworkImageProviderBuilder: page.artworkImageProviderBuilder,
        artworkColorSchemeLoader: page.artworkColorSchemeLoader,
      );

  void _resolveArtworkColors({
    bool notify = true,
    required bool animateTransition,
  }) {
    if (!mounted) return;
    final brightness = Theme.of(context).brightness;
    final artworkUri = widget.controller.current?.artworkUri;
    if (_resolvedArtworkUri == artworkUri &&
        _resolvedBrightness == brightness) {
      return;
    }
    if (animateTransition) {
      _animateThemeChanges = true;
    }
    final generation = ++_colorRequestGeneration;
    _resolvedArtworkUri = artworkUri;
    _resolvedBrightness = brightness;
    _artworkColorScheme = artworkUri == null
        ? null
        : _paletteCache.lookup(artworkUri: artworkUri, brightness: brightness);
    if (notify) setState(() {});
    if (artworkUri == null || _artworkColorScheme != null) return;

    _paletteCache.resolve(artworkUri: artworkUri, brightness: brightness).then((
      scheme,
    ) {
      if (!mounted || generation != _colorRequestGeneration || scheme == null) {
        return;
      }
      setState(() => _artworkColorScheme = scheme);
    });
  }
}

ImageProvider<Object> _networkArtworkProvider(String artworkUri) =>
    musicArtworkImageProvider(artworkUri);

final Expando<ArtworkAtmosphere> _schemeAtmosphere = Expando<ArtworkAtmosphere>(
  'ArtworkAtmosphere',
);

/// Material 3 ambient lighting tokens extracted separately from interactive
/// accent controls so a cover's dominant canvas atmosphere (`primaryAmbient`,
/// `secondaryAmbient`) never fights with foreground control legibility.
@immutable
class ArtworkAtmosphere extends ThemeExtension<ArtworkAtmosphere> {
  const ArtworkAtmosphere({
    required this.primaryAmbient,
    required this.secondaryAmbient,
    required this.accentGlow,
  });

  final Color primaryAmbient;
  final Color secondaryAmbient;
  final Color accentGlow;

  static ArtworkAtmosphere resolve(ColorScheme scheme) =>
      _schemeAtmosphere[scheme] ?? ArtworkAtmosphere.fromColorScheme(scheme);

  factory ArtworkAtmosphere.fromColorScheme(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final pOk = _Oklab.fromColor(scheme.primaryContainer);
    final tOk = _Oklab.fromColor(scheme.tertiaryContainer);
    final aOk = _Oklab.fromColor(scheme.primary);

    final primaryAmbient = _pinAmbientOklab(pOk, dark: dark, secondary: false);
    var secondaryOk = tOk;
    if (_oklabDistance(pOk, tOk) < 0.035) {
      final shiftedHue = pOk.hueRadians + (math.pi * 0.72);
      final baseChroma = math.max(pOk.chroma, 0.018);
      secondaryOk = _Oklab(
        pOk.l,
        baseChroma * math.cos(shiftedHue),
        baseChroma * math.sin(shiftedHue),
      );
    }
    final secondaryAmbient = _pinAmbientOklab(
      secondaryOk,
      dark: dark,
      secondary: true,
    );
    final accentGlow = _Oklab.toGamutColor(
      dark ? 0.42 : 0.84,
      aOk.chroma.clamp(0.02, dark ? 0.13 : 0.085),
      aOk.hueRadians,
    );
    return ArtworkAtmosphere(
      primaryAmbient: primaryAmbient,
      secondaryAmbient: secondaryAmbient,
      accentGlow: accentGlow,
    );
  }

  @override
  ArtworkAtmosphere copyWith({
    Color? primaryAmbient,
    Color? secondaryAmbient,
    Color? accentGlow,
  }) => ArtworkAtmosphere(
    primaryAmbient: primaryAmbient ?? this.primaryAmbient,
    secondaryAmbient: secondaryAmbient ?? this.secondaryAmbient,
    accentGlow: accentGlow ?? this.accentGlow,
  );

  @override
  ArtworkAtmosphere lerp(ThemeExtension<ArtworkAtmosphere>? other, double t) {
    if (other is! ArtworkAtmosphere) return this;
    return ArtworkAtmosphere(
      primaryAmbient: Color.lerp(primaryAmbient, other.primaryAmbient, t)!,
      secondaryAmbient: Color.lerp(
        secondaryAmbient,
        other.secondaryAmbient,
        t,
      )!,
      accentGlow: Color.lerp(accentGlow, other.accentGlow, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ArtworkAtmosphere &&
      other.primaryAmbient == primaryAmbient &&
      other.secondaryAmbient == secondaryAmbient &&
      other.accentGlow == accentGlow;

  @override
  int get hashCode => Object.hash(primaryAmbient, secondaryAmbient, accentGlow);
}

@immutable
class _Oklab {
  const _Oklab(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;

  double get chroma => math.sqrt(a * a + b * b);
  double get hueRadians => math.atan2(b, a);

  static double _srgbToLinear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static double _linearToSrgb(double c) {
    final clamped = c.clamp(0.0, 1.0);
    return clamped <= 0.0031308
        ? 12.92 * clamped
        : 1.055 * math.pow(clamped, 1.0 / 2.4).toDouble() - 0.055;
  }

  static double _cbrt(double x) =>
      x <= 0.0 ? 0.0 : math.pow(x, 1.0 / 3.0).toDouble();

  factory _Oklab.fromLinearRgb(double lr, double lg, double lb) {
    final l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb;
    final m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb;
    final s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb;

    final lC = _cbrt(l);
    final mC = _cbrt(m);
    final sC = _cbrt(s);

    return _Oklab(
      0.2104542553 * lC + 0.7936177850 * mC - 0.0040720468 * sC,
      1.9779984951 * lC - 2.4285922050 * mC + 0.4505937099 * sC,
      0.0259040371 * lC + 0.7827717662 * mC - 0.8086757660 * sC,
    );
  }

  factory _Oklab.fromColor(Color color) => _Oklab.fromLinearRgb(
    _srgbToLinear(color.r),
    _srgbToLinear(color.g),
    _srgbToLinear(color.b),
  );

  static (double, double, double) _oklabToLinearRgb(
    double okL,
    double oka,
    double okb,
  ) {
    final lC = okL + 0.3963377774 * oka + 0.2158037573 * okb;
    final mC = okL - 0.1055613458 * oka - 0.0638541728 * okb;
    final sC = okL - 0.0894841775 * oka - 1.2914855480 * okb;

    final l = lC * lC * lC;
    final m = mC * mC * mC;
    final s = sC * sC * sC;

    final lr = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    final lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    final lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
    return (lr, lg, lb);
  }

  static bool _inSrgbGamut(double lr, double lg, double lb) =>
      lr >= -1e-4 &&
      lr <= 1.0001 &&
      lg >= -1e-4 &&
      lg <= 1.0001 &&
      lb >= -1e-4 &&
      lb <= 1.0001;

  /// Converts perceptual Oklch `(targetL, targetC, hueRadians)` to sRGB while
  /// preserving exact perceptual lightness and hue via binary-search gamut
  /// clamping on chroma.
  static Color toGamutColor(double targetL, double targetC, double hueRadians) {
    final clampedL = targetL.clamp(0.0, 1.0);
    final maxRequestedC = math.max(0.0, targetC);
    final cosH = math.cos(hueRadians);
    final sinH = math.sin(hueRadians);

    var (lr, lg, lb) = _oklabToLinearRgb(
      clampedL,
      maxRequestedC * cosH,
      maxRequestedC * sinH,
    );
    if (!_inSrgbGamut(lr, lg, lb)) {
      var low = 0.0;
      var high = maxRequestedC;
      for (var step = 0; step < 10; step += 1) {
        final mid = (low + high) * 0.5;
        final candidate = _oklabToLinearRgb(clampedL, mid * cosH, mid * sinH);
        if (_inSrgbGamut(candidate.$1, candidate.$2, candidate.$3)) {
          low = mid;
        } else {
          high = mid;
        }
      }
      (lr, lg, lb) = _oklabToLinearRgb(clampedL, low * cosH, low * sinH);
    }

    return Color.from(
      alpha: 1,
      red: _linearToSrgb(lr),
      green: _linearToSrgb(lg),
      blue: _linearToSrgb(lb),
    );
  }
}

double _oklabDistance(_Oklab x, _Oklab y) {
  final dl = x.l - y.l;
  final da = x.a - y.a;
  final db = x.b - y.b;
  return math.sqrt(dl * dl + da * da + db * db);
}

double _angularHueDiffRadians(double h1, double h2) {
  final diff = (h1 - h2).abs() % (2 * math.pi);
  return diff > math.pi ? (2 * math.pi) - diff : diff;
}

bool _isOliveYellowHue(double hueRadians) =>
    hueRadians >= 1.08 && hueRadians <= 2.08;

Color _pinAmbientOklab(
  _Oklab source, {
  required bool dark,
  required bool secondary,
}) {
  final rawC = source.chroma;
  final hue = rawC >= 0.008 ? source.hueRadians : (secondary ? 0.65 : -2.18);
  if (dark) {
    // Perceptual dark-mode ambient window: okL 0.40..0.48 (HCT Tone ~30..40)
    // with boosted chroma (up to 0.175) so the backdrop radiates vivid color
    // against the deep obsidian surface (okL 0.150).
    final baseL = secondary
        ? (0.34 + 0.07 * source.l.clamp(0.0, 1.0))
        : (0.40 + 0.08 * source.l.clamp(0.0, 1.0));
    final pinnedC = rawC < 0.022
        ? (secondary ? 0.028 : 0.032)
        : (rawC * (secondary ? 1.05 : 1.18)).clamp(0.048, 0.175);
    return _Oklab.toGamutColor(baseL, pinnedC.toDouble(), hue);
  } else {
    // Perceptual light-mode ambient window: okL 0.75..0.83 with rich chroma
    // (up to 0.155) so light-mode backdrops have vivid, dimensional contrast
    // against the crisp #FDFDFD lyric card and clean neutral surface.
    final baseL = secondary
        ? (0.78 + 0.05 * source.l.clamp(0.0, 1.0))
        : (0.75 + 0.06 * source.l.clamp(0.0, 1.0));
    final pinnedC = rawC < 0.022
        ? (secondary ? 0.015 : 0.018)
        : (rawC * (secondary ? 1.02 : 1.14)).clamp(0.044, 0.155);
    return _Oklab.toGamutColor(baseL, pinnedC.toDouble(), hue);
  }
}

ColorScheme _withCleanNeutralSurfaces(
  ColorScheme scheme, {
  required double tintHueRadians,
  required bool isMonochrome,
}) {
  final dark = scheme.brightness == Brightness.dark;
  final microChroma = isMonochrome ? 0.004 : 0.007;
  if (dark) {
    return scheme.copyWith(
      surface: _Oklab.toGamutColor(0.152, microChroma, tintHueRadians),
      surfaceContainerLowest: _Oklab.toGamutColor(
        0.168,
        microChroma * 0.5,
        tintHueRadians,
      ),
      surfaceContainerLow: _Oklab.toGamutColor(
        0.182,
        microChroma,
        tintHueRadians,
      ),
      surfaceContainer: _Oklab.toGamutColor(0.208, microChroma, tintHueRadians),
      surfaceContainerHigh: _Oklab.toGamutColor(
        0.242,
        microChroma,
        tintHueRadians,
      ),
      surfaceContainerHighest: _Oklab.toGamutColor(
        0.285,
        microChroma,
        tintHueRadians,
      ),
    );
  } else {
    return scheme.copyWith(
      surface: _Oklab.toGamutColor(0.982, microChroma * 0.4, tintHueRadians),
      surfaceContainerLowest: const Color(0xFFFDFDFD),
      surfaceContainerLow: _Oklab.toGamutColor(
        0.966,
        microChroma * 0.5,
        tintHueRadians,
      ),
      surfaceContainer: _Oklab.toGamutColor(0.948, microChroma, tintHueRadians),
      surfaceContainerHigh: _Oklab.toGamutColor(
        0.930,
        microChroma,
        tintHueRadians,
      ),
      surfaceContainerHighest: _Oklab.toGamutColor(
        0.910,
        microChroma,
        tintHueRadians,
      ),
    );
  }
}

class _MutableCluster {
  _MutableCluster(this.weight, this.lSum, this.aSum, this.bSum);

  double weight;
  double lSum;
  double aSum;
  double bSum;

  _Oklab get mean => _Oklab(lSum / weight, aSum / weight, bSum / weight);

  void absorb(_MutableCluster other) {
    weight += other.weight;
    lSum += other.lSum;
    aSum += other.aSum;
    bSum += other.bSum;
  }
}

Future<ColorScheme> _materialArtworkColorScheme({
  required ImageProvider<Object> provider,
  required Brightness brightness,
}) async {
  final dualRole = await _extractDualRoleArtworkScheme(
    provider: provider,
    brightness: brightness,
  );
  if (dualRole != null) {
    return dualRole;
  }
  final fallbackExtracted = await ColorScheme.fromImageProvider(
    provider: provider,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  return normalizeArtworkColorScheme(fallbackExtracted);
}

typedef _OklabTuple = (double l, double a, double b);

typedef _ExtractedOklabRoles = ({
  _OklabTuple? accent,
  _OklabTuple primaryAmbient,
  _OklabTuple? secondaryAmbient,
});

final Float64List _srgbByteToLinearLut = _buildSrgbByteToLinearLut();

Float64List _buildSrgbByteToLinearLut() {
  final lut = Float64List(256);
  for (var i = 0; i < 256; i += 1) {
    lut[i] = _Oklab._srgbToLinear(i / 255.0);
  }
  return lut;
}

Future<_ExtractedOklabRoles?> _isolateClusterArtworkOklabRoles(
  Uint8List bytes,
  int width,
  int height,
) => Isolate.run(() => _clusterArtworkOklabRoles(bytes, width, height));

Future<_ExtractedOklabRoles?> _runArtworkOklabClustering(
  Uint8List bytes,
  int width,
  int height,
) {
  // Completer.sync() is intentional: when called from a FakeAsync zone and
  // awaited inside WidgetTester.runAsync, an async Completer queues its
  // continuation on the paused FakeAsync microtask queue and deadlocks.
  final completer = Completer<_ExtractedOklabRoles?>.sync();
  Zone.root.run(() {
    _isolateClusterArtworkOklabRoles(
      bytes,
      width,
      height,
    ).then(completer.complete, onError: completer.completeError);
  });
  return completer.future;
}

@visibleForTesting
Future<
  ({
    (double, double, double)? accent,
    (double, double, double) primaryAmbient,
    (double, double, double)? secondaryAmbient,
  })?
>
clusterArtworkOklabRolesInIsolateForTest(
  Uint8List bytes,
  int width,
  int height,
) => _runArtworkOklabClustering(bytes, width, height);

_ExtractedOklabRoles? _clusterArtworkOklabRoles(Uint8List bytes, int w, int h) {
  final lut = _srgbByteToLinearLut;
  final buckets = <int, _MutableCluster>{};
  var totalWeight = 0.0;
  var chromaticWeight = 0.0;

  for (var y = 0; y < h; y += 1) {
    final ny = ((y + 0.5) / h) * 2.0 - 1.0;
    for (var x = 0; x < w; x += 1) {
      final offset = (y * w + x) * 4;
      if (offset + 3 >= bytes.length) break;
      final alpha = bytes[offset + 3];
      if (alpha < 32) continue;

      final nx = ((x + 0.5) / w) * 2.0 - 1.0;
      final dist2 = (nx * nx + ny * ny).clamp(0.0, 1.4);
      final pixelWeight = (alpha / 255.0) * (1.16 - 0.16 * dist2);

      final lr = lut[bytes[offset]];
      final lg = lut[bytes[offset + 1]];
      final lb = lut[bytes[offset + 2]];
      final ok = _Oklab.fromLinearRgb(lr, lg, lb);
      final c = ok.chroma;

      totalWeight += pixelWeight;
      if (c >= 0.032 && ok.l >= 0.12 && ok.l <= 0.96) {
        chromaticWeight += pixelWeight;
      }

      final int bucketKey;
      if (c < 0.022) {
        final lBin = (ok.l * 15.99).floor().clamp(0, 15);
        final tintBin = c < 0.007
            ? 0
            : (((ok.hueRadians + math.pi) / (2 * math.pi)) * 3.99)
                      .floor()
                      .clamp(0, 3) +
                  1;
        bucketKey = lBin * 8 + tintBin;
      } else {
        final lBin = (ok.l * 7.99).floor().clamp(0, 7);
        final cBin = ((c / 0.28) * 5.99).floor().clamp(0, 5);
        final hBin = (((ok.hueRadians + math.pi) / (2 * math.pi)) * 23.99)
            .floor()
            .clamp(0, 23);
        bucketKey = 1000 + (hBin * 64) + (cBin * 8) + lBin;
      }

      final existing = buckets[bucketKey];
      if (existing == null) {
        buckets[bucketKey] = _MutableCluster(
          pixelWeight,
          ok.l * pixelWeight,
          ok.a * pixelWeight,
          ok.b * pixelWeight,
        );
      } else {
        existing.weight += pixelWeight;
        existing.lSum += ok.l * pixelWeight;
        existing.aSum += ok.a * pixelWeight;
        existing.bSum += ok.b * pixelWeight;
      }
    }
  }

  if (totalWeight <= 0 || buckets.isEmpty) return null;

  final sorted = buckets.values.toList()
    ..sort((a, b) => b.weight.compareTo(a.weight));
  final merged = <_MutableCluster>[];
  for (final candidate in sorted.take(56)) {
    final candidateMean = candidate.mean;
    _MutableCluster? target;
    for (final m in merged) {
      final mMean = m.mean;
      if (_oklabDistance(mMean, candidateMean) >= 0.056) continue;
      if (mMean.chroma >= 0.025 &&
          candidateMean.chroma >= 0.025 &&
          _angularHueDiffRadians(mMean.hueRadians, candidateMean.hueRadians) >
              (22.0 * math.pi / 180.0)) {
        continue;
      }
      target = m;
      break;
    }
    if (target != null) {
      target.absorb(candidate);
    } else {
      merged.add(
        _MutableCluster(
          candidate.weight,
          candidate.lSum,
          candidate.aSum,
          candidate.bSum,
        ),
      );
    }
  }

  // Track A: Interactive Accent Selection (captures focal ink/horizon/glow
  // accents while penalizing muddy yellow/olive-brown hues when cooler or
  // richer colors exist on the cover, matching MD3's DislikeAnalyzer).
  _Oklab? accentOk;
  var bestAccentScore = 0.0;
  for (final cluster in merged) {
    final proportion = cluster.weight / totalWeight;
    if (proportion < 0.006) continue;
    final mean = cluster.mean;
    final c = mean.chroma;
    if (c < 0.032) continue;
    if (mean.l < 0.11 || mean.l > 0.965) continue;

    final toneSafety = mean.l < 0.22
        ? ((mean.l - 0.10) / 0.12).clamp(0.25, 1.0)
        : (mean.l > 0.88 ? ((0.97 - mean.l) / 0.09).clamp(0.30, 1.0) : 1.0);
    final dislikePenalty = _isOliveYellowHue(mean.hueRadians) ? 0.26 : 1.0;
    final chromaReward = math
        .pow((c / 0.14).clamp(0.22, 1.65), 0.78)
        .toDouble();
    final areaScore = math.pow(proportion, 0.36).toDouble();
    final score = areaScore * chromaReward * toneSafety * dislikePenalty;
    if (score > bestAccentScore) {
      bestAccentScore = score;
      accentOk = mean;
    }
  }

  // Track B: Primary & Secondary Ambient Canvas Selection (preserves true
  // area-weighted canvas tones—including silver B&W film, ivory white, or
  // deep midnight—without letting minor stamps dye the entire page).
  _Oklab? primaryAmbientRaw;
  var bestAmbientScore = -1.0;
  for (final cluster in merged) {
    final proportion = cluster.weight / totalWeight;
    final mean = cluster.mean;
    final visibilityPreference =
        0.88 + 0.16 * (1.0 - (mean.l - 0.48).abs() * 1.2).clamp(0.0, 1.0);
    final score = math.pow(proportion, 0.80).toDouble() * visibilityPreference;
    if (score > bestAmbientScore) {
      bestAmbientScore = score;
      primaryAmbientRaw = mean;
    }
  }
  primaryAmbientRaw ??= merged.first.mean;

  final chromaticCoverage = chromaticWeight / totalWeight;
  var primaryAmbientOk = primaryAmbientRaw;
  if (primaryAmbientOk.chroma < 0.024 && accentOk != null) {
    if (primaryAmbientOk.l < 0.20 && chromaticCoverage >= 0.12) {
      // Dark void cover with substantial glowing color (e.g. Stray - Feint):
      // infuse the ambient halo with the glowing subject's hue.
      primaryAmbientOk = _Oklab(
        primaryAmbientOk.l * 0.65 + accentOk.l * 0.35,
        accentOk.a * 0.68,
        accentOk.b * 0.68,
      );
    } else {
      // Predominantly B&W / ivory cover with a small colored accent (e.g.
      // 季候风 calligraphy): keep the canvas serene silver/ivory with only a
      // whisper of the accent's temperature.
      primaryAmbientOk = _Oklab(
        primaryAmbientOk.l,
        primaryAmbientOk.a * 0.85 + accentOk.a * 0.15,
        primaryAmbientOk.b * 0.85 + accentOk.b * 0.15,
      );
    }
  }

  // Secondary Ambient: require genuine hue separation (>= 38 deg) whenever
  // the primary ambient is chromatic so darker/lighter shades of the same hue
  // (e.g. dark brown buildings under a yellow sky) are never mistaken for a
  // second color.
  _Oklab? secondaryAmbientOk;
  var bestSecondaryScore = -1.0;
  for (final cluster in merged) {
    final proportion = cluster.weight / totalWeight;
    if (proportion < 0.015) continue;
    final mean = cluster.mean;
    final dist = _oklabDistance(mean, primaryAmbientOk);
    if (dist < 0.075) continue;

    var hueContrastFactor = 1.0;
    if (primaryAmbientOk.chroma >= 0.024) {
      if (mean.chroma < 0.028) continue;
      final hueDiff = _angularHueDiffRadians(
        primaryAmbientOk.hueRadians,
        mean.hueRadians,
      );
      if (hueDiff < (38.0 * math.pi / 180.0)) {
        continue;
      }
      hueContrastFactor = 0.35 + 0.65 * math.sin(hueDiff * 0.5);
    }
    final chromaBonus = 0.45 + mean.chroma.clamp(0.0, 0.18) * 4.2;
    final score =
        math.pow(proportion, 0.48).toDouble() * chromaBonus * hueContrastFactor;
    if (score > bestSecondaryScore) {
      bestSecondaryScore = score;
      secondaryAmbientOk = mean;
    }
  }

  return (
    accent: accentOk == null ? null : (accentOk.l, accentOk.a, accentOk.b),
    primaryAmbient: (
      primaryAmbientOk.l,
      primaryAmbientOk.a,
      primaryAmbientOk.b,
    ),
    secondaryAmbient: secondaryAmbientOk == null
        ? null
        : (secondaryAmbientOk.l, secondaryAmbientOk.a, secondaryAmbientOk.b),
  );
}

Future<ColorScheme?> _extractDualRoleArtworkScheme({
  required ImageProvider<Object> provider,
  required Brightness brightness,
}) async {
  const maxDimension = 64.0;
  final stream = provider.resolve(
    const ImageConfiguration(size: Size(maxDimension, maxDimension)),
  );
  final completer = Completer<ImageInfo>();
  late final ImageStreamListener listener;
  Timer? timeout;
  listener = ImageStreamListener(
    (info, _) {
      timeout?.cancel();
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete(info);
      } else {
        info.dispose();
      }
    },
    onError: (Object error, StackTrace? stackTrace) {
      timeout?.cancel();
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
  );
  stream.addListener(listener);
  if (!completer.isCompleted) {
    timeout = Timer(const Duration(seconds: 5), () {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Artwork load timed out'));
      }
    });
  }

  final imageInfo = await completer.future;
  final image = imageInfo.image;
  ui.Image? scaledImage;
  Uint8List? bytes;
  var w = 0;
  var h = 0;
  try {
    var targetImage = image;
    final srcWidth = image.width;
    final srcHeight = image.height;
    if (srcWidth <= 0 || srcHeight <= 0) return null;
    if (srcWidth > maxDimension || srcHeight > maxDimension) {
      final paintWidth = srcWidth > srcHeight
          ? maxDimension
          : (maxDimension / srcHeight) * srcWidth;
      final paintHeight = srcHeight > srcWidth
          ? maxDimension
          : (maxDimension / srcWidth) * srcHeight;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(0, 0, paintWidth, paintHeight),
        image: image,
        filterQuality: FilterQuality.low,
      );
      final picture = recorder.endRecording();
      try {
        scaledImage = await picture.toImage(
          math.max(1, paintWidth.toInt()),
          math.max(1, paintHeight.toInt()),
        );
      } finally {
        picture.dispose();
      }
      targetImage = scaledImage;
    }

    final byteData = await targetImage.toByteData();
    if (byteData == null) return null;
    bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    w = targetImage.width;
    h = targetImage.height;
  } finally {
    scaledImage?.dispose();
    imageInfo.dispose();
  }

  final extracted = await _runArtworkOklabClustering(bytes, w, h);
  if (extracted == null) return null;

  final accentOk = switch (extracted.accent) {
    final tuple? => _Oklab(tuple.$1, tuple.$2, tuple.$3),
    null => null,
  };
  final primaryAmbientOk = _Oklab(
    extracted.primaryAmbient.$1,
    extracted.primaryAmbient.$2,
    extracted.primaryAmbient.$3,
  );
  final secondaryAmbientOk = switch (extracted.secondaryAmbient) {
    final tuple? => _Oklab(tuple.$1, tuple.$2, tuple.$3),
    null => null,
  };

  final dark = brightness == Brightness.dark;
  final primaryAmbientColor = _pinAmbientOklab(
    primaryAmbientOk,
    dark: dark,
    secondary: false,
  );

  final Color secondaryAmbientColor;
  if (secondaryAmbientOk != null) {
    secondaryAmbientColor = _pinAmbientOklab(
      secondaryAmbientOk,
      dark: dark,
      secondary: true,
    );
  } else {
    // Single-hue or monochrome cover: guarantee a distinct warm/cool
    // counter-glow hue rather than repeating the primary hue.
    final shiftedHue = primaryAmbientOk.hueRadians + (math.pi * 0.72);
    final complementChroma = math
        .max(primaryAmbientOk.chroma * 0.75, 0.028)
        .clamp(0.024, 0.095);
    final complementOk = _Oklab(
      primaryAmbientOk.l,
      complementChroma * math.cos(shiftedHue),
      complementChroma * math.sin(shiftedHue),
    );
    secondaryAmbientColor = _pinAmbientOklab(
      complementOk,
      dark: dark,
      secondary: true,
    );
  }

  final ColorScheme interactiveScheme;
  final Color accentGlowColor;
  if (accentOk != null) {
    // If the only chromatic accent on the cover is in the olive/yellow-ochre
    // zone, shift its interactive control hue warmer toward amber-terracotta
    // so darkened light-mode buttons never turn muddy olive-brown.
    final effectiveAccentHue = _isOliveYellowHue(accentOk.hueRadians)
        ? 0.90
        : accentOk.hueRadians;
    final coneBoost = (0.46 / accentOk.l.clamp(0.20, 0.46)).clamp(1.0, 2.0);
    final boostedChroma = (accentOk.chroma * coneBoost).clamp(0.048, 0.22);
    final accentSeed = _Oklab.toGamutColor(
      accentOk.l.clamp(0.46, 0.66),
      boostedChroma,
      effectiveAccentHue,
    );
    final base = ColorScheme.fromSeed(
      seedColor: accentSeed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final pinnedPrimaryContainer = _Oklab.toGamutColor(
      dark ? 0.35 : 0.89,
      boostedChroma.clamp(0.038, dark ? 0.115 : 0.068),
      effectiveAccentHue,
    );
    final pinnedOnPrimaryContainer = _Oklab.toGamutColor(
      dark ? 0.93 : 0.24,
      boostedChroma.clamp(0.020, 0.065),
      effectiveAccentHue,
    );
    final pOk = _Oklab.fromColor(base.primary);
    final pinnedPrimary = dark
        ? (pOk.l < 0.74
              ? _Oklab.toGamutColor(
                  0.78,
                  boostedChroma.clamp(0.05, 0.15),
                  effectiveAccentHue,
                )
              : base.primary)
        : (pOk.l < 0.36 ||
                  pOk.l > 0.58 ||
                  _isOliveYellowHue(accentOk.hueRadians)
              ? _Oklab.toGamutColor(
                  0.48,
                  boostedChroma.clamp(0.06, 0.17),
                  effectiveAccentHue,
                )
              : base.primary);
    final withCleanSurfaces = _withCleanNeutralSurfaces(
      base,
      tintHueRadians: effectiveAccentHue,
      isMonochrome: false,
    );
    interactiveScheme = withCleanSurfaces.copyWith(
      primary: pinnedPrimary,
      onPrimary: dark ? const Color(0xFF101418) : Colors.white,
      primaryContainer: pinnedPrimaryContainer,
      onPrimaryContainer: pinnedOnPrimaryContainer,
      tertiaryContainer: secondaryAmbientColor,
    );
    accentGlowColor = _Oklab.toGamutColor(
      dark ? 0.44 : 0.80,
      boostedChroma.clamp(0.040, dark ? 0.135 : 0.105),
      effectiveAccentHue,
    );
  } else {
    // Pure monochrome cover (no chromatic focal accent): use a refined
    // cool steel-cyan accent + warm taupe counter-glow rather than flat
    // cement grey so UI elements and active lyric pills pop with crisp
    // metallic contrast.
    final neutralHue = primaryAmbientOk.chroma >= 0.008
        ? primaryAmbientOk.hueRadians
        : -2.18;
    final steelSeed = _Oklab.toGamutColor(0.54, 0.042, neutralHue);
    final base = ColorScheme.fromSeed(
      seedColor: steelSeed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final withCleanSurfaces = _withCleanNeutralSurfaces(
      base,
      tintHueRadians: neutralHue,
      isMonochrome: true,
    );
    interactiveScheme = withCleanSurfaces.copyWith(
      primary: _Oklab.toGamutColor(
        dark ? 0.80 : 0.44,
        dark ? 0.048 : 0.052,
        neutralHue,
      ),
      onPrimary: dark ? const Color(0xFF101418) : Colors.white,
      primaryContainer: _Oklab.toGamutColor(
        dark ? 0.36 : 0.89,
        dark ? 0.032 : 0.012,
        neutralHue,
      ),
      onPrimaryContainer: dark
          ? const Color(0xFFECEEF2)
          : const Color(0xFF1B1E24),
      secondaryContainer: _Oklab.toGamutColor(
        dark ? 0.30 : 0.90,
        dark ? 0.028 : 0.014,
        neutralHue,
      ),
      onSecondaryContainer: dark
          ? const Color(0xFFE4E8EE)
          : const Color(0xFF1E2229),
      tertiaryContainer: secondaryAmbientColor,
    );
    accentGlowColor = _Oklab.toGamutColor(
      dark ? 0.46 : 0.80,
      dark ? 0.052 : 0.032,
      neutralHue,
    );
  }

  _schemeAtmosphere[interactiveScheme] = ArtworkAtmosphere(
    primaryAmbient: primaryAmbientColor,
    secondaryAmbient: secondaryAmbientColor,
    accentGlow: accentGlowColor,
  );
  return interactiveScheme;
}

/// Normalizes externally supplied `ColorScheme`s (e.g. custom loaders or seed
/// tests) in perceptual Oklch space while returning dual-role extracted schemes
/// untouched in O(1).
@visibleForTesting
ColorScheme normalizeArtworkColorScheme(
  ColorScheme scheme, {
  ColorScheme? fallback,
}) {
  if (_schemeAtmosphere[scheme] != null) {
    return scheme;
  }

  final dark = scheme.brightness == Brightness.dark;
  final containerOk = _Oklab.fromColor(scheme.primaryContainer);
  final primaryOk = _Oklab.fromColor(scheme.primary);

  final containerTooDark = dark ? containerOk.l < 0.30 : containerOk.l < 0.38;
  final containerTooBright = dark
      ? containerOk.l > 0.78
      : (containerOk.l > 0.965 ||
            (containerOk.l > 0.91 && containerOk.chroma < 0.024));
  final primaryOutOfBounds = dark ? primaryOk.l < 0.62 : primaryOk.l < 0.26;

  if (!containerTooDark && !containerTooBright && !primaryOutOfBounds) {
    return scheme;
  }

  final refOk = containerOk.chroma >= primaryOk.chroma
      ? containerOk
      : primaryOk;
  final isMonochrome = refOk.chroma < 0.024;
  final rawHue = refOk.chroma >= 0.008 ? refOk.hueRadians : -2.15;
  final hue = (!isMonochrome && _isOliveYellowHue(rawHue)) ? 0.90 : rawHue;

  final ColorScheme normalized;
  if (isMonochrome) {
    final neutralSeed = _Oklab.toGamutColor(0.52, 0.022, hue);
    final base = ColorScheme.fromSeed(
      seedColor: neutralSeed,
      brightness: scheme.brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    );
    final withCleanSurfaces = _withCleanNeutralSurfaces(
      base,
      tintHueRadians: hue,
      isMonochrome: true,
    );
    final atmosphere = ArtworkAtmosphere.fromColorScheme(withCleanSurfaces);
    normalized = withCleanSurfaces.copyWith(
      primaryContainer: _Oklab.toGamutColor(
        dark ? 0.35 : 0.89,
        dark ? 0.020 : 0.011,
        hue,
      ),
      onPrimaryContainer: dark
          ? const Color(0xFFECEEF2)
          : const Color(0xFF1B1E24),
      tertiaryContainer: atmosphere.secondaryAmbient,
    );
    _schemeAtmosphere[normalized] = atmosphere;
  } else {
    final coneBoost = (0.46 / refOk.l.clamp(0.20, 0.46)).clamp(1.0, 2.0);
    final boostedChroma = (refOk.chroma * coneBoost).clamp(0.048, 0.22);
    final seed = _Oklab.toGamutColor(
      refOk.l.clamp(0.46, 0.66),
      boostedChroma,
      hue,
    );
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: scheme.brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final pinnedContainer = _Oklab.toGamutColor(
      dark ? 0.35 : 0.89,
      boostedChroma.clamp(0.038, dark ? 0.115 : 0.068),
      hue,
    );
    final pinnedOnContainer = _Oklab.toGamutColor(
      dark ? 0.93 : 0.24,
      boostedChroma.clamp(0.020, 0.065),
      hue,
    );
    final basePOk = _Oklab.fromColor(base.primary);
    final pinnedPrimary = dark
        ? (basePOk.l < 0.74
              ? _Oklab.toGamutColor(0.78, boostedChroma.clamp(0.05, 0.15), hue)
              : base.primary)
        : (basePOk.l < 0.36 || basePOk.l > 0.58 || _isOliveYellowHue(rawHue)
              ? _Oklab.toGamutColor(0.48, boostedChroma.clamp(0.06, 0.17), hue)
              : base.primary);
    final liftedAmbientOk = _Oklab(
      containerOk.l,
      containerOk.a * coneBoost,
      containerOk.b * coneBoost,
    );
    final ambientPrimary = _pinAmbientOklab(
      liftedAmbientOk,
      dark: dark,
      secondary: false,
    );
    final shiftedSecondaryHue = rawHue + (math.pi * 0.72);
    final ambientSecondary = _pinAmbientOklab(
      _Oklab(
        containerOk.l,
        boostedChroma * 0.75 * math.cos(shiftedSecondaryHue),
        boostedChroma * 0.75 * math.sin(shiftedSecondaryHue),
      ),
      dark: dark,
      secondary: true,
    );
    final withCleanSurfaces = _withCleanNeutralSurfaces(
      base,
      tintHueRadians: hue,
      isMonochrome: false,
    );
    normalized = withCleanSurfaces.copyWith(
      primary: pinnedPrimary,
      onPrimary: dark ? const Color(0xFF101418) : Colors.white,
      primaryContainer: pinnedContainer,
      onPrimaryContainer: pinnedOnContainer,
      tertiaryContainer: ambientSecondary,
    );
    _schemeAtmosphere[normalized] = ArtworkAtmosphere(
      primaryAmbient: ambientPrimary,
      secondaryAmbient: ambientSecondary,
      accentGlow: _Oklab.toGamutColor(
        dark ? 0.44 : 0.80,
        boostedChroma.clamp(0.040, dark ? 0.135 : 0.105),
        hue,
      ),
    );
  }
  return normalized;
}

class _ExpandedNowPlayingBackdrop extends StatelessWidget {
  const _ExpandedNowPlayingBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final atmosphere =
        theme.extension<ArtworkAtmosphere>() ??
        ArtworkAtmosphere.resolve(colors);
    final dark = colors.brightness == Brightness.dark;
    final surface = colors.surface;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: DecoratedBox(
              key: const ValueKey('expanded-now-playing-artwork-backdrop'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      atmosphere.primaryAmbient.withValues(
                        alpha: dark ? 0.50 : 0.54,
                      ),
                      surface,
                    ),
                    Color.alphaBlend(
                      atmosphere.secondaryAmbient.withValues(
                        alpha: dark ? 0.32 : 0.36,
                      ),
                      surface,
                    ),
                    surface,
                  ],
                  stops: const [0, 0.50, 1],
                ),
              ),
              child: CustomPaint(
                isComplex: true,
                painter: _ArtworkAmbientGlowPainter(
                  atmosphere: atmosphere,
                  dark: dark,
                ),
              ),
            ),
          ),
        ),
        RepaintBoundary(child: child),
      ],
    );
  }
}

class _ArtworkAmbientGlowPainter extends CustomPainter {
  const _ArtworkAmbientGlowPainter({
    required this.atmosphere,
    required this.dark,
  });

  final ArtworkAtmosphere atmosphere;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final wide = size.width >= 900;
    final shortest = size.shortestSide;

    // 1. Primary cover-anchored radial halo: focused directly behind the album
    // cover hero so it radiates outward while leaving the bottom-right surface
    // anchor clean and open.
    final coverCenter = wide
        ? Offset(size.width * 0.24, size.height * 0.42)
        : Offset(size.width * 0.26, size.height * 0.18);
    final primaryRadius = shortest * (wide ? 0.76 : 0.84);
    final coreGlowColor = Color.lerp(
      atmosphere.primaryAmbient,
      atmosphere.accentGlow,
      dark ? 0.32 : 0.26,
    )!;
    final primaryPeakAlpha = dark ? 0.52 : 0.56;
    final primaryPaint = Paint()
      ..shader = ui.Gradient.radial(
        coverCenter,
        primaryRadius,
        <Color>[
          coreGlowColor.withValues(alpha: primaryPeakAlpha),
          atmosphere.primaryAmbient.withValues(alpha: primaryPeakAlpha * 0.62),
          atmosphere.primaryAmbient.withValues(alpha: primaryPeakAlpha * 0.20),
          atmosphere.primaryAmbient.withValues(alpha: 0),
        ],
        const <double>[0.0, 0.34, 0.68, 1.0],
      );
    canvas.drawRect(rect, primaryPaint);

    // 2. Secondary ambient counter-glow: positioned at the upper/mid-right to
    // create a true 3-zone spatial transition (Cover Halo -> Secondary Glow ->
    // Clean Neutral Surface at bottom-right).
    final secondaryCenter = wide
        ? Offset(size.width * 0.70, size.height * 0.24)
        : Offset(size.width * 0.76, size.height * 0.48);
    final secondaryRadius = shortest * (wide ? 0.70 : 0.76);
    final secondaryPeakAlpha = dark ? 0.36 : 0.40;
    final secondaryPaint = Paint()
      ..shader = ui.Gradient.radial(
        secondaryCenter,
        secondaryRadius,
        <Color>[
          atmosphere.secondaryAmbient.withValues(alpha: secondaryPeakAlpha),
          atmosphere.secondaryAmbient.withValues(
            alpha: secondaryPeakAlpha * 0.55,
          ),
          atmosphere.secondaryAmbient.withValues(
            alpha: secondaryPeakAlpha * 0.16,
          ),
          atmosphere.secondaryAmbient.withValues(alpha: 0),
        ],
        const <double>[0.0, 0.36, 0.70, 1.0],
      );
    canvas.drawRect(rect, secondaryPaint);
  }

  @override
  bool shouldRepaint(covariant _ArtworkAmbientGlowPainter oldDelegate) =>
      oldDelegate.atmosphere != atmosphere || oldDelegate.dark != dark;
}

class _ExpandedNowPlayingTopBarBackdrop extends StatelessWidget {
  const _ExpandedNowPlayingTopBarBackdrop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final atmosphere =
        theme.extension<ArtworkAtmosphere>() ??
        ArtworkAtmosphere.resolve(colors);
    final dark = colors.brightness == Brightness.dark;
    return DecoratedBox(
      key: const ValueKey('expanded-now-playing-top-bar-backdrop'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [
            Color.alphaBlend(
              atmosphere.primaryAmbient.withValues(alpha: dark ? 0.26 : 0.34),
              colors.surfaceContainerLow,
            ),
            Color.alphaBlend(
              atmosphere.secondaryAmbient.withValues(alpha: dark ? 0.12 : 0.18),
              colors.surfaceContainerLow,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandedNowPlayingBody extends StatefulWidget {
  const _ExpandedNowPlayingBody({
    required this.controller,
    required this.onBack,
    required this.onSignInAgain,
    required this.commentsGateway,
    required this.musicVideoGateway,
    required this.musicVideoEngine,
    required this.artworkImageProviderBuilder,
    required this.lyricAuxiliaryMode,
  });

  final QueuePlaybackController controller;
  final VoidCallback onBack;
  final VoidCallback onSignInAgain;
  final TrackCommentGateway commentsGateway;
  final TrackMusicVideoGateway musicVideoGateway;
  final TrackMusicVideoEngine musicVideoEngine;
  final ArtworkImageProviderBuilder artworkImageProviderBuilder;
  final LyricAuxiliaryMode lyricAuxiliaryMode;

  @override
  State<_ExpandedNowPlayingBody> createState() =>
      _ExpandedNowPlayingBodyState();
}

class _ExpandedNowPlayingBodyState extends State<_ExpandedNowPlayingBody> {
  PlaylistTrackSummary? _track;
  int? _currentIndex;

  @override
  void initState() {
    super.initState();
    _readCurrent();
    widget.controller.stateListenable.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(_ExpandedNowPlayingBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.stateListenable.removeListener(
      _handleControllerChanged,
    );
    _readCurrent();
    widget.controller.stateListenable.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.stateListenable.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    if (track == null) {
      return _ExpandedNowPlayingEmpty(onBack: widget.onBack);
    }
    final catalogLabel = nowPlayingCatalogContextLabel(context, track);
    final onOpenCatalog = catalogLabel == null
        ? null
        : () => unawaited(
            openNowPlayingCatalogContext(
              context: context,
              controller: widget.controller,
              expectedTrack: track,
              expectedIndex: _currentIndex,
            ),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final lyrics = _lyrics();
        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: Row(
                  key: const ValueKey('expanded-now-playing-wide-layout'),
                  children: [
                    Expanded(
                      flex: 5,
                      child: _ExpandedTrackHero(
                        track: track,
                        artworkImageProviderBuilder:
                            widget.artworkImageProviderBuilder,
                        catalogLabel: catalogLabel,
                        onOpenCatalog: onOpenCatalog,
                        onOpenComments: () => _openComments(context, track),
                        onOpenMusicVideo: () => _openMusicVideo(context, track),
                      ),
                    ),
                    const SizedBox(width: 40),
                    Expanded(
                      flex: 6,
                      child: _ExpandedLyricsSurface(child: lyrics),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final heroHeight = math
            .min(constraints.maxWidth * 0.52, constraints.maxHeight * 0.38)
            .clamp(176.0, 240.0)
            .toDouble();
        return Column(
          key: const ValueKey('expanded-now-playing-compact-layout'),
          children: [
            SizedBox(
              width: double.infinity,
              height: heroHeight,
              child: _ExpandedTrackHero(
                track: track,
                compact: true,
                artworkImageProviderBuilder: widget.artworkImageProviderBuilder,
                catalogLabel: catalogLabel,
                onOpenCatalog: onOpenCatalog,
                onOpenComments: () => _openComments(context, track),
                onOpenMusicVideo: () => _openMusicVideo(context, track),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _ExpandedLyricsSurface(child: lyrics),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _lyrics() {
    final lyrics = widget.controller.lyrics;
    if (lyrics == null) {
      return const _ExpandedLyricsUnavailable();
    }
    return LyricPanel(
      key: const ValueKey('expanded-now-playing-lyrics'),
      controller: lyrics,
      onClose: widget.onBack,
      onSignInAgain: widget.onSignInAgain,
      playbackState: widget.controller.playback.stateListenable,
      canSeek: () => widget.controller.playback.canSeek,
      onSeek: widget.controller.playback.seekToMs,
      showCloseButton: false,
      immersive: true,
      auxiliaryMode: widget.lyricAuxiliaryMode,
    );
  }

  void _openComments(BuildContext context, PlaylistTrackSummary track) {
    unawaited(
      showTrackCommentsSurface(
        context: context,
        gateway: widget.commentsGateway,
        track: track,
        playbackController: widget.controller,
      ),
    );
  }

  void _openMusicVideo(BuildContext context, PlaylistTrackSummary track) {
    unawaited(
      showTrackMusicVideoSurface(
        context: context,
        gateway: widget.musicVideoGateway,
        engine: widget.musicVideoEngine,
        track: track,
        playbackController: widget.controller,
      ),
    );
  }

  void _readCurrent() {
    _track = widget.controller.current;
    _currentIndex = widget.controller.currentIndex;
  }

  void _handleControllerChanged() {
    final nextTrack = widget.controller.current;
    final nextIndex = widget.controller.currentIndex;
    if (identical(nextTrack, _track) && nextIndex == _currentIndex) return;
    setState(() {
      _track = nextTrack;
      _currentIndex = nextIndex;
    });
  }
}

class _ExpandedLyricsSurface extends StatelessWidget {
  const _ExpandedLyricsSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('expanded-now-playing-lyrics-surface'),
      color: colors.surfaceContainerLowest.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: MusicRadii.panel,
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _ExpandedTrackHero extends StatelessWidget {
  const _ExpandedTrackHero({
    required this.track,
    required this.artworkImageProviderBuilder,
    required this.catalogLabel,
    required this.onOpenCatalog,
    required this.onOpenComments,
    required this.onOpenMusicVideo,
    this.compact = false,
  });

  final PlaylistTrackSummary track;
  final ArtworkImageProviderBuilder artworkImageProviderBuilder;
  final String? catalogLabel;
  final VoidCallback? onOpenCatalog;
  final VoidCallback onOpenComments;
  final VoidCallback onOpenMusicVideo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final artists = track.artistNames.isEmpty
        ? context.l10n.trackUnknownArtist
        : track.artistNames.join(' · ');
    return LayoutBuilder(
      builder: (context, constraints) {
        if (compact || constraints.maxHeight < 360) {
          final artworkDimension = math
              .min(136.0, constraints.maxHeight - 32)
              .clamp(96.0, 136.0)
              .toDouble();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                _ExpandedArtwork(
                  track: track,
                  dimension: artworkDimension,
                  imageProviderBuilder: artworkImageProviderBuilder,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        key: const ValueKey('expanded-now-playing-title'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _artistLink(context, artists, compact: true),
                      if (track.albumTitle case final albumTitle?)
                        Text(
                          albumTitle,
                          key: const ValueKey('expanded-now-playing-album'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton.filledTonal(
                            key: const ValueKey('expanded-now-playing-mv'),
                            tooltip: context.l10n.nowPlayingOpenMusicVideo,
                            onPressed: onOpenMusicVideo,
                            icon: const Icon(Icons.music_video_outlined),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            key: const ValueKey(
                              'expanded-now-playing-comments',
                            ),
                            tooltip: context.l10n.nowPlayingOpenComments,
                            onPressed: onOpenComments,
                            icon: const Icon(Icons.mode_comment_outlined),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final dense = constraints.maxHeight < 640;
        final horizontalPadding = dense ? 20.0 : 32.0;
        final verticalPadding = dense ? 12.0 : 24.0;
        final reservedInformationHeight = dense ? 172.0 : 196.0;
        final availableArtworkHeight = math.max(
          112.0,
          constraints.maxHeight -
              (verticalPadding * 2) -
              reservedInformationHeight,
        );
        final artworkDimension = math
            .min(
              math.min(
                constraints.maxWidth - (horizontalPadding * 2),
                availableArtworkHeight,
              ),
              420.0,
            )
            .toDouble();
        final contentWidth = math
            .min(
              constraints.maxWidth - (horizontalPadding * 2),
              math.max(artworkDimension, 320.0),
            )
            .toDouble();
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: FittedBox(
            key: const ValueKey('expanded-now-playing-adaptive-hero'),
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              width: contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ExpandedArtwork(
                    track: track,
                    dimension: artworkDimension,
                    imageProviderBuilder: artworkImageProviderBuilder,
                  ),
                  SizedBox(height: dense ? 12 : 24),
                  Text(
                    track.title,
                    key: const ValueKey('expanded-now-playing-title'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style:
                        (dense
                                ? theme.textTheme.headlineSmall
                                : theme.textTheme.headlineMedium)
                            ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  _artistLink(context, artists, compact: false),
                  if (track.albumTitle case final albumTitle?)
                    Text(
                      albumTitle,
                      key: const ValueKey('expanded-now-playing-album'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  SizedBox(height: dense ? 10 : 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        key: const ValueKey('expanded-now-playing-mv'),
                        onPressed: onOpenMusicVideo,
                        icon: const Icon(Icons.music_video_outlined),
                        label: const Text('MV'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('expanded-now-playing-comments'),
                        onPressed: onOpenComments,
                        icon: const Icon(Icons.mode_comment_outlined),
                        label: Text(context.l10n.nowPlayingComments),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _artistLink(
    BuildContext context,
    String artists, {
    required bool compact,
  }) {
    final colors = Theme.of(context).colorScheme;
    final style = (compact
        ? Theme.of(context).textTheme.bodyMedium
        : Theme.of(context).textTheme.bodyLarge);
    final activateCatalog = onOpenCatalog;
    final label = Text(
      artists,
      key: const ValueKey('expanded-now-playing-artists'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: compact ? TextAlign.start : TextAlign.center,
      style: style?.copyWith(
        color: activateCatalog == null
            ? colors.onSurfaceVariant
            : colors.primary,
      ),
    );
    if (activateCatalog == null) return label;
    return Tooltip(
      message: catalogLabel!,
      child: TextButton(
        key: const ValueKey('expanded-now-playing-open-catalog'),
        onPressed: activateCatalog,
        style: TextButton.styleFrom(
          alignment: compact ? Alignment.centerLeft : Alignment.center,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: label),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ExpandedArtwork extends StatelessWidget {
  const _ExpandedArtwork({
    required this.track,
    required this.dimension,
    required this.imageProviderBuilder,
  });

  final PlaylistTrackSummary track;
  final double dimension;
  final ArtworkImageProviderBuilder imageProviderBuilder;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.tertiaryContainer,
          ],
        ),
      ),
      child: Icon(
        Icons.album_rounded,
        size: dimension * 0.28,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
    final artworkUri = track.artworkUri;
    ImageProvider<Object>? provider;
    if (artworkUri != null) {
      try {
        provider = imageProviderBuilder(artworkUri);
      } on Object {
        provider = null;
      }
    }
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_compactRadius(dimension) + 2),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow
                  .withValues(alpha: 0.22),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Semantics(
          image: true,
          label: context.l10n.playbackArtworkSemantics(track.title),
          child: SizedBox.square(
            key: const ValueKey('expanded-now-playing-artwork'),
            dimension: dimension,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_compactRadius(dimension)),
              child: provider == null
                  ? placeholder
                  : Image(
                      image: provider,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      gaplessPlayback: true,
                      frameBuilder: musicArtworkFrameBuilder(placeholder),
                      errorBuilder: musicArtworkErrorBuilder(
                        artworkUri!,
                        placeholder,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

double _compactRadius(double dimension) => math.min(32, dimension * 0.1);

class _ExpandedNowPlayingEmpty extends StatelessWidget {
  const _ExpandedNowPlayingEmpty({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    key: const ValueKey('expanded-now-playing-empty'),
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.queue_music_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.nowPlayingEmptyTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(context.l10n.nowPlayingEmptyDetail, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.tonal(
            key: const ValueKey('expanded-now-playing-empty-back'),
            onPressed: onBack,
            child: Text(context.l10n.nowPlayingBackToMusic),
          ),
        ],
      ),
    ),
  );
}

class _ExpandedLyricsUnavailable extends StatelessWidget {
  const _ExpandedLyricsUnavailable();

  @override
  Widget build(BuildContext context) => Center(
    key: const ValueKey('expanded-now-playing-lyrics-unavailable'),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.nowPlayingLyricsUnavailable,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
