import 'package:flutter/material.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

class MusicTrackTile extends StatelessWidget {
  const MusicTrackTile({
    required this.track,
    required this.position,
    required this.desktop,
    required this.onPlay,
    required this.onQueue,
    required this.itemKey,
    required this.queueKey,
    this.contextKey,
    this.onOpenAlbum,
    this.onOpenArtist,
    super.key,
  });

  final PlaylistTrackSummary track;
  final int position;
  final bool desktop;
  final VoidCallback onPlay;
  final VoidCallback onQueue;
  final Key itemKey;
  final Key queueKey;
  final Key? contextKey;
  final ValueChanged<AlbumSummary>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = formatTrackDuration(track.durationSeconds);
    final artistCopy = track.artistNames.isEmpty
        ? 'Unknown artist'
        : track.artistNames.join(' · ');
    final metadata = [
      artistCopy,
      ?track.albumTitle,
      if (!desktop) duration,
    ].join(' · ');
    final title = track.subtitle == null
        ? track.title
        : '${track.title} · ${track.subtitle}';
    final album = onOpenAlbum == null ? null : track.album;
    final contextArtists = onOpenArtist == null
        ? const <ArtistSummary>[]
        : track.artists;
    final hasContext = album != null || contextArtists.isNotEmpty;

    return ListTile(
      key: itemKey,
      minTileHeight: desktop ? 64 : 72,
      contentPadding: EdgeInsets.symmetric(horizontal: desktop ? 12 : 8),
      leading: SizedBox(
        width: desktop ? 88 : 84,
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$position',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox.square(
              dimension: desktop ? 44 : 48,
              child: _TrackArtwork(track: track),
            ),
          ],
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        metadata,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onPlay,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (desktop) ...[
            SizedBox(
              width: 48,
              child: Text(
                duration,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (hasContext)
            PopupMenuButton<_TrackContextDestination>(
              key: contextKey,
              tooltip: 'Browse context for ${track.title}',
              onSelected: _openContext,
              itemBuilder: (context) => [
                if (album != null)
                  PopupMenuItem(
                    key: const ValueKey('track-context-album'),
                    value: _TrackContextDestination(album: album),
                    child: ListTile(
                      leading: const Icon(Icons.album_rounded),
                      title: const Text('Open album'),
                      subtitle: Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                for (var index = 0; index < contextArtists.length; index++)
                  PopupMenuItem(
                    key: ValueKey('track-context-artist-$index'),
                    value: _TrackContextDestination(
                      artist: contextArtists[index],
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.person_rounded),
                      title: const Text('Open artist'),
                      subtitle: Text(
                        contextArtists[index].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
              icon: const Icon(Icons.more_vert_rounded),
            ),
          IconButton(
            key: queueKey,
            tooltip: 'Add ${track.title} to queue',
            onPressed: onQueue,
            icon: const Icon(Icons.playlist_add_rounded),
          ),
        ],
      ),
    );
  }

  void _openContext(_TrackContextDestination destination) {
    final album = destination.album;
    if (album != null) {
      onOpenAlbum?.call(album);
      return;
    }
    final artist = destination.artist;
    if (artist != null) onOpenArtist?.call(artist);
  }
}

class _TrackContextDestination {
  const _TrackContextDestination({this.album, this.artist})
    : assert((album == null) != (artist == null));

  final AlbumSummary? album;
  final ArtistSummary? artist;
}

class _TrackArtwork extends StatelessWidget {
  const _TrackArtwork({required this.track});

  final PlaylistTrackSummary track;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.secondaryContainer,
      child: Icon(Icons.music_note_rounded, color: colors.onSecondaryContainer),
    );
    final artworkUri = track.artworkUri;
    return Semantics(
      label: 'Artwork for ${track.title}',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: artworkUri == null
            ? placeholder
            : Image.network(
                artworkUri,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

String formatTrackDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '—';
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}
