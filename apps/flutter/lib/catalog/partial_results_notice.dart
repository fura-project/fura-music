import 'package:flutter/material.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

/// A single inline informational notice for a successfully loaded collection
/// that omitted unsafe rows. [resultRevision] lets assistive technology announce
/// the notice once for each newly accepted result, rather than on unrelated
/// rebuilds or repeated query replacements.
class PartialResultsNotice extends StatefulWidget {
  const PartialResultsNotice({
    required this.omittedCount,
    required this.resultRevision,
    this.message,
    this.announce = true,
    this.onAnnounced,
    super.key,
  });

  final int omittedCount;
  final int resultRevision;
  final String? message;
  final bool announce;
  final VoidCallback? onAnnounced;

  @override
  State<PartialResultsNotice> createState() => _PartialResultsNoticeState();
}

class _PartialResultsNoticeState extends State<PartialResultsNotice> {
  late bool _announce = widget.announce;

  @override
  void didUpdateWidget(PartialResultsNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.announce) {
      _announce = false;
    } else if (oldWidget.resultRevision != widget.resultRevision ||
        !oldWidget.announce) {
      _announce = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final message =
        widget.message ??
        context.l10n.partialResultsNotice(widget.omittedCount);
    if (_announce) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_announce) return;
        widget.onAnnounced?.call();
        setState(() => _announce = false);
      });
    }
    final colors = Theme.of(context).colorScheme;
    final editorial = context.editorialTheme;
    final background = editorial.isEditorial
        ? editorial.cardSurface
        : colors.surfaceContainerHigh;
    final foreground = editorial.isEditorial
        ? editorial.inkSecondary
        : colors.onSurfaceVariant;
    final borderRadius = editorial.isEditorial
        ? editorial.controlRadius
        : BorderRadius.circular(12);
    return Semantics(
      key: const ValueKey('partial-results-semantics'),
      container: true,
      liveRegion: _announce,
      label: message,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: borderRadius,
            border: editorial.isEditorial
                ? Border.all(color: editorial.hairline)
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
