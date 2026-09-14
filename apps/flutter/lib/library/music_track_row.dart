import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';

typedef MusicTrackRowContentBuilder = Widget Function(
  BuildContext context,
  bool active,
  bool hovered,
);

enum MusicTrackAction { play, addToQueue, openAlbum, openArtist }

Future<void> openMusicTrackArtists({
  required BuildContext context,
  required List<ArtistSummary> artists,
  required ValueChanged<ArtistSummary>? onSelected,
  String? title,
  String? detail,
  String? cancelLabel,
  String itemKeyPrefix = 'music-track-artist',
}) async {
  if (onSelected == null || artists.isEmpty) return;
  final resolvedTitle = title ?? context.l10n.trackChooseArtistTitle;
  final resolvedDetail = detail ?? context.l10n.trackMultipleArtistsDetail;
  final resolvedCancelLabel = cancelLabel ?? context.l10n.commonCancel;
  if (artists.length == 1) {
    onSelected(artists.single);
    return;
  }
  final compact = MediaQuery.sizeOf(context).width < 600;
  final selected = compact
      ? await showModalBottomSheet<ArtistSummary>(
          context: context,
          showDragHandle: true,
          builder: (context) => _MusicTrackArtistSelection(
            artists: artists,
            compact: true,
            title: resolvedTitle,
            detail: resolvedDetail,
            itemKeyPrefix: itemKeyPrefix,
          ),
        )
      : await showDialog<ArtistSummary>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(resolvedTitle),
            content: _MusicTrackArtistSelection(
              artists: artists,
              compact: false,
              title: resolvedTitle,
              detail: resolvedDetail,
              itemKeyPrefix: itemKeyPrefix,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(resolvedCancelLabel),
              ),
            ],
          ),
        );
  if (selected != null) onSelected(selected);
}

class _MusicTrackArtistSelection extends StatelessWidget {
  const _MusicTrackArtistSelection({
    required this.artists,
    required this.compact,
    required this.title,
    required this.detail,
    required this.itemKeyPrefix,
  });

  final List<ArtistSummary> artists;
  final bool compact;
  final String title;
  final String detail;
  final String itemKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      shrinkWrap: compact,
      padding: EdgeInsets.fromLTRB(8, compact ? 0 : 4, 8, compact ? 16 : 4),
      children: [
        if (compact) ListTile(title: Text(title), subtitle: Text(detail)),
        for (var index = 0; index < artists.length; index++)
          ListTile(
            key: ValueKey('$itemKeyPrefix-$index'),
            leading: const Icon(Icons.person_rounded),
            title: Text(artists[index].name),
            onTap: () => Navigator.pop(context, artists[index]),
          ),
      ],
    );
    return SafeArea(
      top: !compact,
      child: compact
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
              child: list,
            )
          : SizedBox(
              width: 360,
              height: (artists.length * 56.0).clamp(56.0, 336.0),
              child: list,
            ),
    );
  }
}

/// Shared interaction and visual surface for a dense music Track row.
///
/// Pages keep ownership of their data, paging and action menus. This widget
/// owns the repeated row grammar: focus/hover state, current-Track treatment,
/// keyboard context-menu shortcuts, pointer gestures and 56/64 dp density.
class MusicTrackRowSurface extends StatefulWidget {
  const MusicTrackRowSurface({
    required this.itemKey,
    required this.desktop,
    required this.current,
    required this.semanticLabel,
    required this.onTap,
    required this.contentBuilder,
    this.onContextMenuRequested,
    this.hovered,
    this.onHoverChanged,
    super.key,
  }) : assert(
         (hovered == null && onHoverChanged == null) ||
             (hovered != null && onHoverChanged != null),
         'External hover state requires both hovered and onHoverChanged.',
       );

  final Key itemKey;
  final bool desktop;
  final bool current;
  final String semanticLabel;
  final VoidCallback onTap;
  final MusicTrackRowContentBuilder contentBuilder;
  final ValueChanged<Offset?>? onContextMenuRequested;

  /// Supply both fields when a list needs to clear hover on scroll.
  final bool? hovered;
  final ValueChanged<bool>? onHoverChanged;

  @override
  State<MusicTrackRowSurface> createState() => _MusicTrackRowSurfaceState();
}

class _MusicTrackRowSurfaceState extends State<MusicTrackRowSurface> {
  final FocusNode _focusNode = FocusNode();
  bool _internalHovered = false;

  bool get _hovered => widget.hovered ?? _internalHovered;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  void _handleHoverChanged(bool hovered) {
    final callback = widget.onHoverChanged;
    if (callback != null) {
      callback(hovered);
    } else if (_internalHovered != hovered) {
      setState(() => _internalHovered = hovered);
    }
  }

  void _showKeyboardMenu() {
    final callback = widget.onContextMenuRequested;
    if (callback == null) return;
    if (!widget.desktop) {
      callback(null);
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    callback(box.localToGlobal(box.size.center(Offset.zero)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = _hovered || _focusNode.hasFocus;
    final background = widget.current
        ? colors.surfaceContainerHigh
        : active
        ? colors.surfaceContainerLow
        : Colors.transparent;
    return CallbackShortcuts(
      bindings: widget.onContextMenuRequested == null
          ? const <ShortcutActivator, VoidCallback>{}
          : <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.contextMenu):
                  _showKeyboardMenu,
              const SingleActivator(LogicalKeyboardKey.f10, shift: true):
                  _showKeyboardMenu,
            },
      child: Semantics(
        label: widget.semanticLabel,
        container: true,
        button: true,
        selected: widget.current,
        excludeSemantics: true,
        onTap: widget.onTap,
        onLongPress: !widget.desktop && widget.onContextMenuRequested != null
            ? () => widget.onContextMenuRequested!(null)
            : null,
        child: MouseRegion(
          onEnter: (_) => _handleHoverChanged(true),
          onExit: (_) => _handleHoverChanged(false),
          child: InkWell(
            key: widget.itemKey,
            focusNode: _focusNode,
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              _focusNode.requestFocus();
              widget.onTap();
            },
            onLongPress:
                !widget.desktop && widget.onContextMenuRequested != null
                ? () => widget.onContextMenuRequested!(null)
                : null,
            onSecondaryTapDown:
                widget.desktop && widget.onContextMenuRequested != null
                ? (details) {
                    _focusNode.requestFocus();
                    widget.onContextMenuRequested!(details.globalPosition);
                  }
                : null,
            child: Ink(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: widget.desktop ? 56 : 64,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.desktop ? 12 : 8,
                    vertical: widget.desktop ? 7 : 6,
                  ),
                  child: widget.contentBuilder(context, active, _hovered),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    required this.onPlay,
    required this.onAddToQueue,
    required this.onMore,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.showInlineQueueAction,
    this.addToQueueTooltip,
    this.moreTooltip,
    this.playTooltip,
    this.albumTooltip,
    this.artistTooltip,
    this.title,
    this.queueKey,
    this.moreKey,
    super.key,
  });

  final int index;
  final PlaylistTrackSummary track;
  final bool desktop;
  final bool current;
  final bool active;
  final String artistNames;
  final VoidCallback onPlay;
  final VoidCallback onAddToQueue;
  final VoidCallback onMore;
  final VoidCallback? onOpenAlbum;
  final VoidCallback? onOpenArtist;
  final bool? showInlineQueueAction;
  final String? addToQueueTooltip;
  final String? moreTooltip;
  final String? playTooltip;
  final String? albumTooltip;
  final String? artistTooltip;
  final String? title;
  final Key? queueKey;
  final Key? moreKey;

  @override
  Widget build(BuildContext context) =>
      desktop ? _desktopContent(context) : _compactContent(context);

  Widget _desktopContent(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final resolvedPlayTooltip = playTooltip ?? context.l10n.commonPlayFromHere;
    final resolvedQueueTooltip =
        addToQueueTooltip ?? context.l10n.commonAddToQueue;
    final resolvedArtistTooltip =
        artistTooltip ?? context.l10n.commonOpenArtist;
    final resolvedAlbumTooltip = albumTooltip ?? context.l10n.commonOpenAlbum;
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Center(
            child: current
                ? Icon(Icons.equalizer_rounded, size: 18, color: colors.primary)
                : active
                ? ExcludeFocus(
                    child: IconButton(
                      tooltip: resolvedPlayTooltip,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        foregroundColor: colors.primary,
                        hoverColor: colors.primary.withValues(alpha: 0.12),
                        focusColor: colors.primary.withValues(alpha: 0.12),
                      ),
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded, size: 19),
                    ),
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
                ExcludeFocus(
                  child: IconButton(
                    key: queueKey,
                    tooltip: resolvedQueueTooltip,
                    visualDensity: VisualDensity.compact,
                    onPressed: onAddToQueue,
                    icon: const Icon(Icons.playlist_add_rounded, size: 19),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: MusicTrackMetadataAction(
            value: artistNames,
            tooltip: resolvedArtistTooltip,
            onPressed: onOpenArtist,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: MusicTrackMetadataAction(
            value: track.albumTitle ?? '—',
            tooltip: resolvedAlbumTooltip,
            onPressed: onOpenAlbum,
          ),
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
            Row(
              children: [
                Flexible(child: MusicTrackMetadataText(artistNames)),
                if (track.albumTitle != null) ...[
                  Text(
                    ' · ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Flexible(child: MusicTrackMetadataText(track.albumTitle!)),
                ],
              ],
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      if (showInlineQueueAction ?? false)
        ExcludeFocus(
          child: IconButton(
            key: queueKey,
            tooltip: addToQueueTooltip ?? context.l10n.commonAddToQueue,
            onPressed: onAddToQueue,
            icon: const Icon(Icons.playlist_add_rounded, size: 20),
          ),
        ),
      Text(
        formatTrackDuration(track.durationSeconds),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      ExcludeFocus(
        child: IconButton(
          key: moreKey,
          tooltip: moreTooltip ?? context.l10n.commonMoreActions,
          onPressed: onMore,
          icon: const Icon(Icons.more_horiz_rounded),
        ),
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

class MusicTrackMetadataAction extends StatelessWidget {
  const MusicTrackMetadataAction({
    required this.value,
    required this.tooltip,
    this.onPressed,
    this.compact = false,
    super.key,
  });

  final String value;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) return MusicTrackMetadataText(value);
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: ExcludeFocus(
            child: Tooltip(
              message: tooltip,
              child: Semantics(
                button: true,
                label: context.l10n.metadataActionSemantics(tooltip, value),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onPressed,
                    hoverColor: colors.primary.withValues(alpha: 0.10),
                    focusColor: colors.primary.withValues(alpha: 0.12),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 3 : 6,
                        vertical: compact ? 1 : 6,
                      ),
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
              headers: musicArtworkRequestHeaders(uri!),
              fit: BoxFit.cover,
              errorBuilder: musicArtworkErrorBuilder(uri!, placeholder),
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
