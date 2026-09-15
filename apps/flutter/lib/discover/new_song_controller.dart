import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum NewSongStage { loading, content, empty, error }

class NewSongController extends ChangeNotifier {
  NewSongController(
    this._gateway, {
    NewSongCategory initialCategory = NewSongCategory.latest,
  }) : _category = initialCategory;

  final NewSongGateway _gateway;

  NewSongCategory _category;
  NewSongStage _stage = NewSongStage.loading;
  List<PlaylistTrackSummary> _tracks = const [];
  NewSongFailure? _failure;
  int _omittedTrackCount = 0;
  int _partialResultRevision = 0;
  NewSongLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  NewSongCategory get category => _category;
  NewSongStage get stage => _stage;
  List<PlaylistTrackSummary> get tracks => _tracks;
  NewSongFailure? get failure => _failure;
  int get omittedTrackCount => _omittedTrackCount;
  int get partialResultRevision => _partialResultRevision;
  bool get canRetry => _stage == NewSongStage.error && _isRetryable(_failure);

  Future<void> load() => _load(_category);

  void selectCategory(NewSongCategory category) {
    if (_category == category) return;
    _category = category;
    unawaited(_load(category));
  }

  void retry() {
    if (canRetry) unawaited(_load(_category));
  }

  Future<void> _load(NewSongCategory expectedCategory) async {
    final generation = ++_generation;
    _operation?.cancel();
    late final NewSongLoadOperation operation;
    try {
      operation = _gateway.beginLoad(category: expectedCategory);
    } on Object {
      if (!_isCurrent(generation, expectedCategory)) return;
      _operation = null;
      _tracks = const [];
      _omittedTrackCount = 0;
      _failure = NewSongFailure.coreUnavailable;
      _stage = NewSongStage.error;
      _notify();
      return;
    }
    _operation = operation;
    _tracks = const [];
    _omittedTrackCount = 0;
    _failure = null;
    _stage = NewSongStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation, expectedCategory)) return;

    if (result.failure == null && result.category == expectedCategory) {
      _tracks = List.unmodifiable(result.tracks);
      _omittedTrackCount = result.omittedTrackCount;
      if (result.omittedTrackCount > 0) _partialResultRevision += 1;
      _stage = _tracks.isEmpty && _omittedTrackCount == 0
          ? NewSongStage.empty
          : NewSongStage.content;
    } else {
      _failure = result.failure ?? NewSongFailure.invalidResponse;
      _stage = NewSongStage.error;
    }
    _notify();
  }

  bool _isRetryable(NewSongFailure? failure) =>
      failure == NewSongFailure.coreUnavailable ||
      failure == NewSongFailure.network ||
      failure == NewSongFailure.serviceUnavailable ||
      failure == NewSongFailure.invalidResponse ||
      failure == NewSongFailure.alreadyRunning;

  bool _isCurrent(int generation, NewSongCategory expectedCategory) =>
      !_disposed && generation == _generation && expectedCategory == _category;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _operation?.cancel();
    _operation = null;
    super.dispose();
  }
}
