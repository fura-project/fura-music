import 'package:flutter/material.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';

/// A single inline warning for a successfully loaded collection that omitted
/// unsafe rows. [resultRevision] lets assistive technology announce the notice
/// once for each newly accepted result, rather than on unrelated rebuilds.
class PartialResultsNotice extends StatefulWidget {
  const PartialResultsNotice({
    required this.omittedCount,
    required this.resultRevision,
    super.key,
  });

  final int omittedCount;
  final int resultRevision;

  @override
  State<PartialResultsNotice> createState() => _PartialResultsNoticeState();
}

class _PartialResultsNoticeState extends State<PartialResultsNotice> {
  bool _announce = true;

  @override
  void didUpdateWidget(PartialResultsNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resultRevision != widget.resultRevision) _announce = true;
  }

  @override
  Widget build(BuildContext context) {
    final message = context.l10n.partialResultsNotice(widget.omittedCount);
    if (_announce) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _announce) setState(() => _announce = false);
      });
    }
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('partial-results-semantics'),
      container: true,
      liveRegion: _announce,
      label: message,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.tertiaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: colors.onTertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colors.onTertiaryContainer),
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
