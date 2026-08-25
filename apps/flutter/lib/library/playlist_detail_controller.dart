import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum PlaylistDetailStage {
  loading,
  content,
  empty,
  error,
  authenticationRequired,
  credentialRejected,
}

class PlaylistDetailController extends ChangeNotifier {
  PlaylistDetailController(this.playlist, this._gateway);

  static const pageSize = 100;

  final UserPlaylistSummary playlist;
  final PlaylistDetailGateway _gateway;

  PlaylistDetailStage _stage = PlaylistDetailStage.loading;
  List<PlaylistTrackSummary> _tracks = const [];
  UserLibraryFailure? _failure;
  int _total = 0;
  bool _hasMore = false;
  PlaylistTrackPageLoadOperation? _operation;
  int _generation = 0;
  bool _disposed = false;

  PlaylistDetailStage get stage => _stage;
  List<PlaylistTrackSummary> get tracks => _tracks;
  UserLibraryFailure? get failure => _failure;
  int get total => _total;
  bool get hasMore => _hasMore;

  bool get canRetry =>
      _stage == PlaylistDetailStage.error &&
      (_failure == UserLibraryFailure.network ||
          _failure == UserLibraryFailure.serviceUnavailable ||
          _failure == UserLibraryFailure.invalidResponse ||
          _failure == UserLibraryFailure.coreUnavailable);

  Future<void> load() async {
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(
      playlist: playlist,
      offset: 0,
      size: pageSize,
    );
    _operation = operation;
    _tracks = const [];
    _failure = null;
    _total = 0;
    _hasMore = false;
    _stage = PlaylistDetailStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    _failure = result.failure;
    if (result.failure == null && result.offset == 0) {
      _tracks = List.unmodifiable(result.tracks);
      _total = result.total;
      _hasMore = result.hasMore;
      _stage = _tracks.isEmpty
          ? PlaylistDetailStage.empty
          : PlaylistDetailStage.content;
    } else {
      _tracks = const [];
      _total = 0;
      _hasMore = false;
      _failure ??= UserLibraryFailure.invalidResponse;
      _stage = switch (_failure!) {
        UserLibraryFailure.authenticationRequired ||
        UserLibraryFailure.replaced ||
        UserLibraryFailure.cancelled =>
          PlaylistDetailStage.authenticationRequired,
        UserLibraryFailure.credentialRejected ||
        UserLibraryFailure.credentialRejectedStorageCleanupFailed =>
          PlaylistDetailStage.credentialRejected,
        UserLibraryFailure.coreUnavailable ||
        UserLibraryFailure.network ||
        UserLibraryFailure.serviceUnavailable ||
        UserLibraryFailure.invalidResponse ||
        UserLibraryFailure.alreadyRunning => PlaylistDetailStage.error,
      };
    }
    _notify();
  }

  void retry() {
    if (canRetry) unawaited(load());
  }

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
