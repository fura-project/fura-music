import 'package:flutter/material.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

class MusicTrackTableHeader extends StatelessWidget {
  const MusicTrackTableHeader({
    required this.titleLabel,
    required this.artistLabel,
    required this.albumLabel,
    required this.durationLabel,
    super.key,
  });

  final String titleLabel;
  final String artistLabel;
  final String albumLabel;
  final String durationLabel;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text('#', style: style)),
          Expanded(flex: 3, child: Text(titleLabel, style: style)),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: Text(artistLabel, style: style)),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: Text(albumLabel, style: style)),
          const SizedBox(width: 16),
          SizedBox(
            width: 52,
            child: Text(durationLabel, textAlign: TextAlign.end, style: style),
          ),
        ],
      ),
    );
  }
}

class MusicTrackRowContent extends StatelessWidget {
  const MusicTrackRowContent({
    required this.index,
    required this.track,
    required this.desktop,
    required this.current,
    required this.active,
    required this.artistNames,
    required this.onAddToQueue,
    required this.onMore,
    this.showInlineQueueAction,
    this.addToQueueTooltip = 'Add to queue',
    this.moreTooltip = 'More actions',
    this.title,
    super.key,
  });

  final int index;
  final PlaylistTrackSummary track;
  final bool desktop;
  final bool current;
  final bool active;
  final String artistNames;
  final VoidCallback onAddToQueue;
  final VoidCallback onMore;
  final bool? showInlineQueueAction;
  final String addToQueueTooltip;
  final String moreTooltip;
  final String? title;

  @override
  Widget build(BuildContext context) =>
      desktop ? _desktopContent(context) : _compactContent(context);

  Widget _desktopContent(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Center(
            child: current
                ? Icon(Icons.equalizer_rounded, size: 18, color: colors.primary)
                : active
                ? Icon(
                    Icons.play_arrow_rounded,
                    size: 19,
                    color: colors.primary,
                  )
                : Text(
                    '$index',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              SizedBox.square(
                dimension: 40,
                child: MusicTrackArtwork(uri: track.artworkUri),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title ?? track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: current ? colors.primary : colors.onSurface,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (showInlineQueueAction ?? active)
                IconButton(
                  tooltip: addToQueueTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: onAddToQueue,
                  icon: const Icon(Icons.playlist_add_rounded, size: 19),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(flex: 2, child: MusicTrackMetadataText(artistNames)),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: MusicTrackMetadataText(track.albumTitle ?? '—'),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 52,
          child: MusicTrackMetadataText(
            formatTrackDuration(track.durationSeconds),
            alignment: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _compactContent(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 26,
        child: current
            ? Icon(
                Icons.equalizer_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              )
            : Text(
                '$index',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
      ),
      const SizedBox(width: 8),
      SizedBox.square(
        dimension: 48,
        child: MusicTrackArtwork(uri: track.artworkUri),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title ?? track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: current ? Theme.of(context).colorScheme.primary : null,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              track.albumTitle == null
                  ? artistNames
                  : '$artistNames · ${track.albumTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Text(
        formatTrackDuration(track.durationSeconds),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      IconButton(
        tooltip: moreTooltip,
        onPressed: onMore,
        icon: const Icon(Icons.more_horiz_rounded),
      ),
    ],
  );
}

class MusicTrackMetadataText extends StatelessWidget {
  const MusicTrackMetadataText(this.value, {this.alignment, super.key});

  final String value;
  final TextAlign? alignment;

  @override
  Widget build(BuildContext context) => Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: alignment,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

class MusicTrackArtwork extends StatelessWidget {
  const MusicTrackArtwork({this.uri, super.key});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(Icons.music_note_rounded, color: colors.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: uri == null
          ? placeholder
          : Image.network(
              uri!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

String formatTrackDuration(int? seconds) {
  if (seconds == null || seconds < 0) return '--:--';
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '$minutes:${remaining.toString().padLeft(2, '0')}';
}
