import 'package:flutter/material.dart';

class MusicCatalogHeader extends StatelessWidget {
  const MusicCatalogHeader({
    required this.artwork,
    required this.eyebrow,
    required this.title,
    required this.titleKey,
    required this.desktop,
    this.children = const [],
    super.key,
  });

  final Widget artwork;
  final String eyebrow;
  final String title;
  final Key titleKey;
  final bool desktop;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final alignment = desktop
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    final textAlignment = desktop ? TextAlign.start : TextAlign.center;
    final copy = Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          eyebrow,
          textAlign: textAlignment,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          header: true,
          child: Text(
            title,
            key: titleKey,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlignment,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        ...children,
      ],
    );
    final sizedArtwork = SizedBox.square(
      dimension: desktop ? 132 : 92,
      child: artwork,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 48 : 20,
        desktop ? 20 : 12,
        desktop ? 48 : 20,
        20,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: desktop
              ? Row(
                  children: [
                    sizedArtwork,
                    const SizedBox(width: 24),
                    Expanded(child: copy),
                  ],
                )
              : Column(
                  children: [sizedArtwork, const SizedBox(height: 14), copy],
                ),
        ),
      ),
    );
  }
}
