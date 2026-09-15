import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';

@immutable
class TrackSearchSuggestion {
  const TrackSearchSuggestion({
    required this.query,
    required this.detail,
    this.raw = false,
  });

  final String query;
  final String detail;
  final bool raw;
}

/// Builds provider-backed query suggestions from the first bounded Track
/// search page. The existing Track search boundary remains the only source of
/// catalog truth; this controller only debounces, cancels and de-duplicates
/// the display candidates.
class TrackSearchSuggestionController extends ChangeNotifier {
  TrackSearchSuggestionController(
    this._gateway, {
    this.debounce = const Duration(milliseconds: 320),
  });

  static const int pageSize = 8;

  final TrackSearchGateway? _gateway;
  final Duration debounce;

  Timer? _timer;
  TrackSearchPageLoadOperation? _operation;
  List<TrackSearchSuggestion> _suggestions = const [];
  String _query = '';
  int? _highlightedIndex;
  bool _loading = false;
  bool _dismissed = false;
  int _generation = 0;
  bool _disposed = false;

  List<TrackSearchSuggestion> get suggestions => _suggestions;
  List<TrackSearchSuggestion> get entries => _query.isEmpty
      ? const []
      : [
          TrackSearchSuggestion(query: _query, detail: '', raw: true),
          ..._suggestions,
        ];
  int? get highlightedIndex => _highlightedIndex;
  String? get highlightedQuery {
    final index = _highlightedIndex;
    final currentEntries = entries;
    return index == null || index < 0 || index >= currentEntries.length
        ? null
        : currentEntries[index].query;
  }

  bool get loading => _loading;
  bool get enabled => _gateway != null;
  bool get visible => !_dismissed && _query.isNotEmpty;

  void updateQuery(String rawQuery) {
    final query = rawQuery.trim();
    final generation = ++_generation;
    _timer?.cancel();
    _timer = null;
    _operation?.cancel();
    _operation = null;
    _dismissed = false;
    _query = query;
    _highlightedIndex = null;
    _suggestions = const [];
    _loading = false;
    _notify();
    final gateway = _gateway;
    if (gateway == null || query.isEmpty) return;
    _timer = Timer(
      debounce,
      () => unawaited(_load(gateway, query, generation)),
    );
  }

  Future<void> _load(
    TrackSearchGateway gateway,
    String query,
    int generation,
  ) async {
    if (!_isCurrent(generation)) return;
    _timer = null;
    late final TrackSearchPageLoadOperation operation;
    try {
      operation = gateway.beginLoad(query: query, page: 1, size: pageSize);
    } on Object {
      if (_isCurrent(generation)) {
        _loading = false;
        _suggestions = const [];
        _notify();
      }
      return;
    }
    _operation = operation;
    _loading = true;
    _notify();
    late final TrackSearchPageResult result;
    try {
      result = await operation.run();
    } on Object {
      if (identical(_operation, operation)) _operation = null;
      if (_isCurrent(generation)) {
        _loading = false;
        _suggestions = const [];
        _notify();
      }
      return;
    }
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;
    _loading = false;
    if (result.failure != null || result.page != 1) {
      _suggestions = const [];
      _notify();
      return;
    }
    final normalizedQuery = query.toLowerCase();
    final seen = <String>{};
    final suggestions = <TrackSearchSuggestion>[];
    for (final item in result.items) {
      final title = item.track.title.trim();
      if (title.isEmpty ||
          title.toLowerCase() == normalizedQuery ||
          !seen.add(title.toLowerCase())) {
        continue;
      }
      final detail = item.track.artistNames
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .join(' · ');
      suggestions.add(TrackSearchSuggestion(query: title, detail: detail));
      if (suggestions.length == 6) break;
    }
    _suggestions = List.unmodifiable(suggestions);
    _notify();
  }

  bool moveHighlight(int delta) {
    final currentEntries = entries;
    if (!visible || currentEntries.isEmpty || delta == 0) return false;
    final current = _highlightedIndex;
    final next = current == null
        ? (delta > 0 ? 0 : currentEntries.length - 1)
        : (current + delta) % currentEntries.length;
    _highlightedIndex = next < 0 ? next + currentEntries.length : next;
    _notify();
    return true;
  }

  void highlight(int? index) {
    final next = index != null && index >= 0 && index < entries.length
        ? index
        : null;
    if (_highlightedIndex == next) return;
    _highlightedIndex = next;
    _notify();
  }

  void dismiss() {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _operation?.cancel();
    _operation = null;
    _loading = false;
    _dismissed = true;
    _highlightedIndex = null;
    _suggestions = const [];
    _notify();
  }

  void clear() {
    updateQuery('');
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _operation?.cancel();
    super.dispose();
  }
}

class TrackSearchSuggestionsPanel extends StatelessWidget {
  const TrackSearchSuggestionsPanel({
    required this.controller,
    required this.onSelected,
    this.popup = false,
    super.key,
  });

  final TrackSearchSuggestionController controller;
  final ValueChanged<String> onSelected;
  final bool popup;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _buildPanel(context),
  );

  Widget _buildPanel(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = controller.entries;
    final content = Column(
      key: ValueKey(
        popup ? 'top-search-suggestions' : 'track-search-suggestions',
      ),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          _TrackSearchSuggestionRow(
            key: ValueKey(
              entries[index].raw
                  ? (popup
                        ? 'top-search-suggestion-raw'
                        : 'track-search-suggestion-raw')
                  : (popup
                        ? 'top-search-suggestion-${index - 1}'
                        : 'track-search-suggestion-${index - 1}'),
            ),
            suggestion: entries[index],
            highlighted: controller.highlightedIndex == index,
            onHover: () => controller.highlight(index),
            onSelected: () => onSelected(entries[index].query),
          ),
          if (index == 0 && controller.loading)
            const LinearProgressIndicator(
              key: ValueKey('search-suggestions-loading'),
              minHeight: 2,
            ),
        ],
      ],
    );
    if (!popup) {
      return Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(width: double.infinity, child: content),
      );
    }
    return Material(
      elevation: 3,
      shadowColor: colors.shadow.withValues(alpha: 0.22),
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: SingleChildScrollView(
          primary: false,
          child: SizedBox(width: double.infinity, child: content),
        ),
      ),
    );
  }
}

class _TrackSearchSuggestionRow extends StatelessWidget {
  const _TrackSearchSuggestionRow({
    required this.suggestion,
    required this.highlighted,
    required this.onHover,
    required this.onSelected,
    super.key,
  });

  final TrackSearchSuggestion suggestion;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = suggestion.raw
        ? context.l10n.searchSuggestionSubmit(suggestion.query)
        : suggestion.detail.isEmpty
        ? suggestion.query
        : '${suggestion.query}, ${suggestion.detail}';
    return Semantics(
      button: true,
      selected: highlighted,
      label: label,
      onTap: onSelected,
      excludeSemantics: true,
      child: Material(
        color: highlighted
            ? colors.surfaceContainerHighest
            : Colors.transparent,
        child: InkWell(
          onTap: onSelected,
          onHover: (hovered) {
            if (hovered) onHover();
          },
          excludeFromSemantics: true,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    suggestion.raw
                        ? Icons.arrow_forward_rounded
                        : Icons.search_rounded,
                    size: 20,
                    color: highlighted
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: suggestion.raw
                        ? Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge,
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                suggestion.query,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (suggestion.detail.isNotEmpty)
                                Text(
                                  suggestion.detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
