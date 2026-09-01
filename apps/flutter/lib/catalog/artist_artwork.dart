import 'package:flutter/material.dart';

/// Provider-neutral Artist artwork with a truthful Material fallback.
class ArtistArtwork extends StatelessWidget {
  const ArtistArtwork({required this.uri, this.iconSize = 44, super.key});

  final String? uri;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: iconSize,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
    return ClipOval(
      child: uri == null
          ? fallback
          : Image.network(
              uri!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
