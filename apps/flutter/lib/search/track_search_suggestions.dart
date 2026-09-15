import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';

@immutable
class TrackSearchSuggestion {
  const TrackSearchSuggestion({required this.query, required this.detail});

  final String query;
  final String detail;
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
  bool _loading = false;
  bool _dismissed = false;
  int _generation = 0;
  bool _disposed = false;

  List<TrackSearchSuggestion> get suggestions => _suggestions;
  bool get loading => _loading;
  bool get enabled => _gateway != null;
  bool get visible => !_dismissed && (_loading || _suggestions.isNotEmpty);

  void updateQuery(String rawQuery) {
    final query = rawQuery.trim();
    final generation = ++_generation;
    _timer?.cancel();
    _timer = null;
    _operation?.cancel();
    _operation = null;
    _dismissed = false;
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

  void dismiss() {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _operation?.cancel();
    _operation = null;
    _loading = false;
    _dismissed = true;
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Column(
      key: ValueKey(
        popup ? 'top-search-suggestions' : 'track-search-suggestions',
      ),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.loading)
          const LinearProgressIndicator(
            key: ValueKey('search-suggestions-loading'),
            minHeight: 2,
          ),
        for (var index = 0; index < controller.suggestions.length; index++)
          ListTile(
            key: ValueKey(
              popup
                  ? 'top-search-suggestion-$index'
                  : 'track-search-suggestion-$index',
            ),
            dense: true,
            leading: const Icon(Icons.search_rounded),
            title: Text(
              controller.suggestions[index].query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: controller.suggestions[index].detail.isEmpty
                ? null
                : Text(
                    controller.suggestions[index].detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: () => onSelected(controller.suggestions[index].query),
          ),
      ],
    );
    if (!popup) {
      return Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: content,
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
        child: SingleChildScrollView(primary: false, child: content),
      ),
    );
  }
}
