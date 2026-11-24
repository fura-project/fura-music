import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/catalog/music_artwork_placeholder.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

/// Provider-neutral Artist artwork with a unified theme-aware fallback.
class ArtistArtwork extends StatelessWidget {
  const ArtistArtwork({
    required this.uri,
    this.iconSize,
    this.preservePreviousFrame = false,
    super.key,
  });

  final String? uri;
  final double? iconSize;
  final bool preservePreviousFrame;

  @override
  Widget build(BuildContext context) {
    final editorial = context.editorialTheme;
    final fallback = MusicArtworkPlaceholder(
      kind: MusicArtworkKind.artist,
      iconSize: iconSize,
      shape: BoxShape.circle,
    );
    final resolvedUri = uri?.trim();
    final hasUri = resolvedUri != null && resolvedUri.isNotEmpty;
    final clipped = ClipOval(
      child: !hasUri
          ? fallback
          : Image.network(
              resolvedUri,
              headers: musicArtworkRequestHeaders(resolvedUri),
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              gaplessPlayback: preservePreviousFrame,
              frameBuilder: musicArtworkFrameBuilder(
                fallback,
                preservePreviousFrame: preservePreviousFrame,
              ),
              errorBuilder: musicArtworkErrorBuilder(resolvedUri, fallback),
            ),
    );
    if (!editorial.isEditorial) return clipped;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: editorial.hairline),
      ),
      child: clipped,
    );
  }
}
