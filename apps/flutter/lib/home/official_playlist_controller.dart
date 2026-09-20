import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/home/official_playlist_gateway.dart';

enum OfficialPlaylistStage { loading, refreshing, content, empty, error }

class OfficialPlaylistController extends ChangeNotifier {
  OfficialPlaylistController(this._gateway);

  static const pageSize = 8;

  final OfficialPlaylistGateway _gateway;

  OfficialPlaylistStage _stage = OfficialPlaylistStage.loading;
  List<OfficialPlaylistSummary> _playlists = const [];
  OfficialPlaylistFailure? _failure;
  int _omittedPlaylistCount = 0;
  OfficialPlaylistPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  OfficialPlaylistStage get stage => _stage;
  List<OfficialPlaylistSummary> get playlists => _playlists;
  OfficialPlaylistFailure? get failure => _failure;
  int get omittedPlaylistCount => _omittedPlaylistCount;
  bool get canRetry =>
      _stage == OfficialPlaylistStage.error && _isRetryable(_failure);

  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_generation;
    _operation?.cancel();
    OfficialPlaylistPageLoadOperation operation;
    try {
      operation = _gateway.beginLoad(page: 1, size: pageSize);
    } on Object {
      _playlists = const [];
      _failure = OfficialPlaylistFailure.coreUnavailable;
      _omittedPlaylistCount = 0;
      _stage = OfficialPlaylistStage.error;
      _notify();
      return;
    }
    _operation = operation;
    _failure = null;
    // Only the pending interval retains the last successful window. Final
    // empty/error results still follow the existing public-fallback policy.
    _stage = _playlists.isEmpty
        ? OfficialPlaylistStage.loading
        : OfficialPlaylistStage.refreshing;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    if (_validPage(result)) {
      _playlists = List.unmodifiable(result.playlists);
      _omittedPlaylistCount = result.omittedPlaylistCount;
      _stage = _playlists.isEmpty && _omittedPlaylistCount == 0
          ? OfficialPlaylistStage.empty
          : OfficialPlaylistStage.content;
    } else {
      _playlists = const [];
      _omittedPlaylistCount = 0;
      _failure = result.failure ?? OfficialPlaylistFailure.invalidResponse;
      _stage = OfficialPlaylistStage.error;
    }
    _notify();
  }

  void retry() {
    if (canRetry) unawaited(load());
  }

  bool _validPage(OfficialPlaylistPageResult result) =>
      result.failure == null &&
      result.page == 1 &&
      result.nextPage == 2 &&
      result.total >= 0 &&
      result.omittedPlaylistCount >= 0 &&
      (!result.hasMore ||
          result.playlists.isNotEmpty ||
          result.omittedPlaylistCount > 0);

  bool _isRetryable(OfficialPlaylistFailure? failure) =>
      failure == OfficialPlaylistFailure.coreUnavailable ||
      failure == OfficialPlaylistFailure.network ||
      failure == OfficialPlaylistFailure.serviceUnavailable ||
      failure == OfficialPlaylistFailure.invalidResponse ||
      failure == OfficialPlaylistFailure.alreadyRunning;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

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
