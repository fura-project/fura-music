import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum NewSongStage { loading, content, empty, error }

class NewSongController extends ChangeNotifier {
  NewSongController(this._gateway);

  final NewSongGateway _gateway;

  NewSongCategory _category = NewSongCategory.latest;
  NewSongStage _stage = NewSongStage.loading;
  List<PlaylistTrackSummary> _tracks = const [];
  NewSongFailure? _failure;
  NewSongLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  NewSongCategory get category => _category;
  NewSongStage get stage => _stage;
  List<PlaylistTrackSummary> get tracks => _tracks;
  NewSongFailure? get failure => _failure;
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
    final operation = _gateway.beginLoad(category: expectedCategory);
    _operation = operation;
    _tracks = const [];
    _failure = null;
    _stage = NewSongStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation, expectedCategory)) return;

    if (result.failure == null && result.category == expectedCategory) {
      _tracks = List.unmodifiable(result.tracks);
      _stage = _tracks.isEmpty ? NewSongStage.empty : NewSongStage.content;
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
