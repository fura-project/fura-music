import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterustmusic/fura_toast.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/catalog/music_artwork_placeholder.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/track_like_presentation_controller.dart';
import 'package:flutterustmusic/library/playlist_track_presentation_controller.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

export 'package:flutterustmusic/library/playlist_track_presentation_controller.dart'
    show showAddTrackToPlaylist;

typedef MusicTrackRowContentBuilder = Widget Function(
  BuildContext context,
  bool active,
  bool hovered,
);

const double musicTrackDesktopRowExtent = 56;
const double musicTrackCompactRowExtent = 64;
const double musicTrackRowSeparatorExtent = 1;

double musicTrackRowExtent({
  required bool desktop,
  bool includesSeparator = true,
}) =>
    (desktop ? musicTrackDesktopRowExtent : musicTrackCompactRowExtent) +
    (includesSeparator ? musicTrackRowSeparatorExtent : 0);

enum MusicTrackAction {
  play,
  addToQueue,
  addToPlaylist,
  openAlbum,
  openArtist,
  like,
  unlike,
}

bool canAddMusicTrackToPlaylist(BuildContext context) =>
    PlaylistTrackActionScope.maybeOf(context)?.ownedPlaylists.isNotEmpty ??
    false;

Future<MusicTrackAction?> resolveMusicTrackLikeAction(
  BuildContext context,
  PlaylistTrackSummary track,
) async {
  final controller = TrackLikeActionScope.maybeOf(context);
  if (controller == null) return null;
  final state = await controller.resolve(track);
  if (!context.mounted) return null;
  return switch (state) {
    AuthoritativeTrackLikeState.liked => MusicTrackAction.unlike,
    AuthoritativeTrackLikeState.notLiked => MusicTrackAction.like,
    AuthoritativeTrackLikeState.unavailable ||
    AuthoritativeTrackLikeState.unknown ||
    AuthoritativeTrackLikeState.loading => null,
  };
}

Future<void> runMusicTrackLikeAction(
  BuildContext context,
  PlaylistTrackSummary track,
  MusicTrackAction action,
) => performTrackLikeAction(
  context: context,
  track: track,
  liked: action == MusicTrackAction.like,
);

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
          animationStyle: furaDialogAnimationStyle(context),
          builder: (context) => FuraDialogTransition(
            child: AlertDialog(
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
    final editorial = context.editorialTheme;
    final active = _hovered || _focusNode.hasFocus;
    final background = editorial.isEditorial
        ? (widget.current
              ? editorial.inkPrimary.withValues(alpha: 0.05)
              : active
              ? editorial.inkPrimary.withValues(alpha: 0.03)
              : Colors.transparent)
        : (widget.current
              ? colors.surfaceContainerHigh
              : active
              ? colors.surfaceContainerLow
              : Colors.transparent);
    final radius = editorial.isEditorial
        ? const BorderRadius.all(Radius.circular(2))
        : BorderRadius.circular(10);
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
        key: widget.itemKey,
        label: widget.semanticLabel,
        container: true,
        explicitChildNodes: true,
        button: true,
        selected: widget.current,
        onTap: widget.onTap,
        onLongPress: widget.onContextMenuRequested != null
            ? _showKeyboardMenu
            : null,
        child: MouseRegion(
          onEnter: (_) => _handleHoverChanged(true),
          onExit: (_) => _handleHoverChanged(false),
          child: InkWell(
            excludeFromSemantics: true,
            focusNode: _focusNode,
            borderRadius: radius,
            onTap: () {
              _focusNode.requestFocus();
              widget.onTap();
            },
            onLongPress: widget.onContextMenuRequested != null
                ? () {
                    _focusNode.requestFocus();
                    _showKeyboardMenu();
                  }
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
                borderRadius: editorial.isEditorial ? null : radius,
                border: editorial.isEditorial
                    ? Border(
                        bottom: BorderSide(
                          color: editorial.hairline.withValues(alpha: 0.72),
                        ),
                      )
                    : null,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: widget.desktop
                      ? musicTrackDesktopRowExtent
                      : musicTrackCompactRowExtent,
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

class MusicTrackMenuEntry<T> {
  const MusicTrackMenuEntry({
    required this.value,
    required this.icon,
    required this.label,
    this.key,
  });

  final T value;
  final IconData icon;
  final String label;
  final Key? key;
}

Offset? musicTrackAnchorOffset(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset(box.size.width / 2, box.size.height));
}

Future<T?> showAdaptiveMusicContextMenu<T>({
  required BuildContext context,
  required bool desktop,
  required List<MusicTrackMenuEntry<T>> entries,
  Offset? anchorPosition,
  String? headerTitle,
}) {
  if (entries.isEmpty) return Future<T?>.value();
  if (!desktop) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (headerTitle != null && headerTitle.isNotEmpty)
                ListTile(
                  title: Text(
                    headerTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              for (final entry in entries)
                ListTile(
                  key: entry.key,
                  leading: Icon(entry.icon),
                  title: Text(entry.label),
                  onTap: () => Navigator.pop(context, entry.value),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
  final overlay = Overlay.of(context).context.findRenderObject();
  if (overlay is! RenderBox) return Future<T?>.value();
  final resolvedPosition =
      anchorPosition ??
      musicTrackAnchorOffset(context) ??
      overlay.size.center(Offset.zero);
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(
      resolvedPosition.dx,
      resolvedPosition.dy,
      overlay.size.width - resolvedPosition.dx,
      overlay.size.height - resolvedPosition.dy,
    ),
    items: [
      for (final entry in entries)
        PopupMenuItem<T>(
          key: entry.key,
          value: entry.value,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.icon, size: 20, color: colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
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
    final editorial = context.editorialTheme;
    final style = editorial.isEditorial
        ? editorial.eyebrow(
            Theme.of(context).textTheme.labelSmall,
            color: editorial.inkMuted,
          )
        : Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          );
    String formatHeader(String text) =>
        editorial.isEditorial ? text.toUpperCase() : text;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: editorial.isEditorial
                ? editorial.hairline
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '#',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              formatHeader(titleLabel),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text(
              formatHeader(artistLabel),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text(
              formatHeader(albumLabel),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 52,
            child: editorial.isEditorial
                ? Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Tooltip(
                      message: durationLabel,
                      child: Semantics(
                        label: durationLabel,
                        child: Icon(
                          Icons.schedule_rounded,
                          size: 15,
                          color: editorial.inkMuted,
                        ),
                      ),
                    ),
                  )
                : Text(
                    durationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: style,
                  ),
          ),
          const SizedBox(width: 36),
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
    this.onMoreAt,
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
  final ValueChanged<Offset?>? onMoreAt;
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
    final resolvedMoreTooltip = moreTooltip ?? context.l10n.commonMoreActions;
    final resolvedArtistTooltip =
        artistTooltip ?? context.l10n.commonOpenArtist;
    final resolvedAlbumTooltip = albumTooltip ?? context.l10n.commonOpenAlbum;
    final showMoreAction = active || current;
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Center(
            child: ExcludeSemantics(
              child: current
                  ? Icon(
                      Icons.equalizer_rounded,
                      size: 18,
                      color: colors.primary,
                    )
                  : active
                  ? ExcludeSemantics(
                      child: ExcludeFocus(
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
                      ),
                    )
                  : Text(
                      '$index',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              SizedBox.square(
                dimension: 40,
                child: ExcludeSemantics(
                  child: MusicTrackArtwork(uri: track.artworkUri),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ExcludeSemantics(
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
        const SizedBox(width: 4),
        SizedBox(
          width: 32,
          height: 32,
          child: showMoreAction
              ? ExcludeFocus(
                  child: Builder(
                    builder: (buttonContext) => IconButton(
                      key: moreKey,
                      tooltip: resolvedMoreTooltip,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        if (onMoreAt != null) {
                          onMoreAt!(musicTrackAnchorOffset(buttonContext));
                          return;
                        }
                        onMore();
                      },
                      icon: const Icon(Icons.more_horiz_rounded, size: 19),
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _compactContent(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 26,
        child: ExcludeSemantics(
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
      ),
      const SizedBox(width: 8),
      SizedBox.square(
        dimension: 48,
        child: ExcludeSemantics(
          child: MusicTrackArtwork(uri: track.artworkUri),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Text(
                title ?? track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: current ? Theme.of(context).colorScheme.primary : null,
                  fontWeight: FontWeight.w600,
                ),
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
      ExcludeSemantics(
        child: Text(
          formatTrackDuration(track.durationSeconds),
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
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
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignment,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
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
    final editorial = context.editorialTheme;
    final radius = editorial.isEditorial
        ? const BorderRadius.all(Radius.circular(3))
        : BorderRadius.circular(6);
    const placeholder = MusicArtworkPlaceholder(kind: MusicArtworkKind.track);
    final clipped = ClipRRect(
      borderRadius: radius,
      child: uri == null
          ? placeholder
          : Image.network(
              uri!,
              headers: musicArtworkRequestHeaders(uri!),
              fit: BoxFit.cover,
              gaplessPlayback: false,
              frameBuilder: musicArtworkFrameBuilder(placeholder),
              errorBuilder: musicArtworkErrorBuilder(uri!, placeholder),
            ),
    );
    if (!editorial.isEditorial) return clipped;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: editorial.hairline),
      ),
      child: clipped,
    );
  }
}

/// Overlays a locate-current-Track action only while the current row is
/// outside the visible portion of a fixed-density music list.
class MusicTrackLocatorOverlay extends StatefulWidget {
  const MusicTrackLocatorOverlay({
    required this.controller,
    required this.currentIndex,
    required this.desktop,
    required this.child,
    this.leadingExtent = 0,
    this.itemExtent,
    this.bottomInset,
    this.buttonKey = const ValueKey('locate-current-track'),
    super.key,
  });

  final ScrollController controller;
  final int? currentIndex;
  final bool desktop;
  final Widget child;
  final double leadingExtent;
  final double? itemExtent;
  final double? bottomInset;
  final Key buttonKey;

  @override
  State<MusicTrackLocatorOverlay> createState() =>
      _MusicTrackLocatorOverlayState();
}

class _MusicTrackLocatorOverlayState extends State<MusicTrackLocatorOverlay> {
  bool _visible = false;
  bool _visibilityUpdateScheduled = false;

  double get _itemExtent =>
      widget.itemExtent ?? musicTrackRowExtent(desktop: widget.desktop);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_requestVisibilityUpdate);
    _requestVisibilityUpdate();
  }

  @override
  void didUpdateWidget(MusicTrackLocatorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_requestVisibilityUpdate);
      widget.controller.addListener(_requestVisibilityUpdate);
    }
    _requestVisibilityUpdate();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_requestVisibilityUpdate);
    super.dispose();
  }

  void _requestVisibilityUpdate() {
    if (_visibilityUpdateScheduled) return;
    _visibilityUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityUpdateScheduled = false;
      if (mounted) _updateVisibilityAfterLayout();
    });
  }

  void _updateVisibilityAfterLayout() {
    final index = widget.currentIndex;
    final controller = widget.controller;
    var visible = false;
    if (index != null && controller.positions.length == 1) {
      final position = controller.position;
      if (position.hasContentDimensions) {
        final rowStart = widget.leadingExtent + (index * _itemExtent);
        final rowEnd = rowStart + _itemExtent;
        final viewportStart = position.pixels;
        final viewportEnd = viewportStart + position.viewportDimension;
        visible = rowEnd <= viewportStart || rowStart >= viewportEnd;
      }
    }
    if (_visible != visible) setState(() => _visible = visible);
  }

  void _locate() {
    final index = widget.currentIndex;
    final controller = widget.controller;
    if (index == null || controller.positions.length != 1) return;
    final position = controller.position;
    if (!position.hasContentDimensions) return;
    final target =
        widget.leadingExtent +
        (index * _itemExtent) -
        (position.viewportDimension * 0.28);
    final offset = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      controller.jumpTo(offset);
      return;
    }
    controller.animateTo(
      offset,
      duration: const Duration(milliseconds: 360),
      curve: Easing.emphasizedDecelerate,
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _requestVisibilityUpdate();
          return false;
        },
        child: widget.child,
      ),
      PositionedDirectional(
        end: 16,
        bottom:
            widget.bottomInset ??
            (16 +
                MusicViewportClearance.bottomOf(
                  context,
                  fallbackPlayerPresent:
                      !widget.desktop && widget.currentIndex != null,
                )),
        child: IgnorePointer(
          ignoring: !_visible,
          child: ExcludeSemantics(
            excluding: !_visible,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: AnimatedScale(
                scale: _visible ? 1 : 0.82,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Easing.standard,
                child: IconButton.filledTonal(
                  key: widget.buttonKey,
                  tooltip: _visible
                      ? context.l10n.commonLocateCurrentTrack
                      : null,
                  onPressed: _visible ? _locate : null,
                  constraints: const BoxConstraints.tightFor(
                    width: 52,
                    height: 52,
                  ),
                  icon: const Icon(Icons.my_location_rounded),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

int? musicTrackIndexOf(
  List<PlaylistTrackSummary> tracks,
  PlaylistTrackSummary? current,
) {
  if (current == null) return null;
  final index = tracks.indexWhere(
    (track) =>
        track.providerId == current.providerId &&
        track.opaqueId == current.opaqueId,
  );
  return index < 0 ? null : index;
}

String formatTrackDuration(int? seconds) {
  if (seconds == null || seconds < 0) return '--:--';
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '$minutes:${remaining.toString().padLeft(2, '0')}';
}
