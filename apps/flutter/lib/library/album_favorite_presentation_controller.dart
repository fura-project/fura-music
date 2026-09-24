import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/library/album_favorite_gateway.dart';
import 'package:flutterustmusic/library/favorite_album_controller.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/library/library_mutation_feedback.dart';

enum AuthoritativeAlbumFavoriteState {
  unavailable,
  unknown,
  loading,
  favorite,
  notFavorite,
}

/// Account-session favorite-Album membership owner.
class AlbumFavoritePresentationController extends ChangeNotifier {
  AlbumFavoritePresentationController({
    required this.providerId,
    required this.enabled,
    required FavoriteAlbumGateway gateway,
    required this.mutations,
  }) : _sourceGateway = gateway {
    sessionGateway = _AlbumMembershipGateway(this);
  }

  final String providerId;
  final bool enabled;
  final FavoriteAlbumGateway _sourceGateway;
  final LibraryMutationCoordinator mutations;
  late final FavoriteAlbumGateway sessionGateway;

  final Set<String> _favoriteAlbumIds = <String>{};
  final Map<String, bool> _confirmedOverrides = <String, bool>{};
  final Set<String> _requestedAlbumIds = <String>{};
  final Set<String> _needsReconciliation = <String>{};
  final Map<_AlbumPageKey, _SharedAlbumPage> _sharedPages = {};
  Future<void>? _scan;
  Future<void>? _refresh;
  FavoriteAlbumPageLoadOperation? _operation;
  int _nextOffset = 0;
  bool _complete = false;
  bool _loading = false;
  bool _scanReliable = true;
  bool _sessionAvailable = true;
  bool _refreshing = false;
  Set<String>? _refreshIds;
  int _refreshNextOffset = 0;
  bool _refreshReliable = true;
  int _generation = 0;
  bool _disposed = false;

  AuthoritativeAlbumFavoriteState stateFor(AlbumSummary album) {
    if (!enabled || !_sessionAvailable || album.providerId != providerId) {
      return AuthoritativeAlbumFavoriteState.unavailable;
    }
    if (_needsReconciliation.contains(album.opaqueId)) {
      return AuthoritativeAlbumFavoriteState.unknown;
    }
    final override = _confirmedOverrides[album.opaqueId];
    if (override != null) {
      return override
          ? AuthoritativeAlbumFavoriteState.favorite
          : AuthoritativeAlbumFavoriteState.notFavorite;
    }
    if (_favoriteAlbumIds.contains(album.opaqueId)) {
      return AuthoritativeAlbumFavoriteState.favorite;
    }
    if (_complete && _scanReliable) {
      return AuthoritativeAlbumFavoriteState.notFavorite;
    }
    if (_loading && _requestedAlbumIds.contains(album.opaqueId)) {
      return AuthoritativeAlbumFavoriteState.loading;
    }
    return AuthoritativeAlbumFavoriteState.unknown;
  }

  /// Seeds a positive state from an authoritative Favorite Albums page.
  void observeFavorite(AlbumSummary album) {
    if (!enabled || album.providerId != providerId) return;
    if (_favoriteAlbumIds.add(album.opaqueId)) _notify();
  }

  Future<void> preload() {
    if (!enabled || !_sessionAvailable || _complete || _disposed) {
      return Future.value();
    }
    final running = _scan;
    if (running != null) return running;
    final generation = _generation;
    _diagnostic('preload_started');
    late final Future<void> scan;
    scan = _scanContinuation(generation).whenComplete(() {
      if (identical(_scan, scan)) _scan = null;
    });
    _scan = scan;
    return scan;
  }

  Future<AuthoritativeAlbumFavoriteState> resolve(AlbumSummary album) async {
    final initial = stateFor(album);
    if (initial == AuthoritativeAlbumFavoriteState.unavailable ||
        initial == AuthoritativeAlbumFavoriteState.favorite ||
        initial == AuthoritativeAlbumFavoriteState.notFavorite) {
      return initial;
    }
    _requestedAlbumIds.add(album.opaqueId);
    if (!_loading && !_complete) {
      _loading = true;
      _notify();
    }
    await preload();
    return stateFor(album);
  }

  Future<LibraryMutationOutcome<AlbumFavoriteState>> setFavorite({
    required AlbumSummary album,
    required bool favorite,
    Future<void> Function()? refreshAdditionalState,
  }) async {
    _diagnostic(
      'action_requested',
      detail: 'knownState=${stateFor(album).name}',
    );
    final outcome = await mutations.setAlbumFavorite(
      album: album,
      favorite: favorite,
    );
    switch (outcome.status) {
      case LibraryMutationStatus.confirmed:
        _confirmedOverrides[album.opaqueId] =
            outcome.value == AlbumFavoriteState.favorite;
        _needsReconciliation.remove(album.opaqueId);
        _diagnostic('write_confirmed');
        _notify();
        _startBackgroundReconciliation(refreshAdditionalState);
      case LibraryMutationStatus.outcomeUnknown:
        _confirmedOverrides.remove(album.opaqueId);
        _needsReconciliation.add(album.opaqueId);
        _diagnostic('write_outcome_unknown');
        _notify();
        _startBackgroundReconciliation(refreshAdditionalState);
      case LibraryMutationStatus.definitiveFailure:
        _diagnostic('write_definitive_failure');
      case LibraryMutationStatus.unavailable:
        _diagnostic('write_unavailable');
      case LibraryMutationStatus.alreadyRunning:
        _diagnostic('write_already_running');
    }
    return outcome;
  }

  Future<void> refreshSnapshot() {
    final running = _refresh;
    if (running != null) return running;
    if (!enabled || !_sessionAvailable || _disposed) return Future.value();
    _operation?.cancel();
    _operation = null;
    _scan = null;
    _cancelSharedPages();
    _refreshing = true;
    _refreshIds = <String>{};
    _refreshNextOffset = 0;
    _refreshReliable = true;
    final generation = _generation;
    _diagnostic('reconcile_started');
    late final Future<void> refresh;
    refresh = _scanRefresh(generation).whenComplete(() {
      if (identical(_refresh, refresh)) _refresh = null;
    });
    _refresh = refresh;
    return refresh;
  }

  void _startBackgroundReconciliation(
    Future<void> Function()? refreshAdditionalState,
  ) {
    final membership = refreshSnapshot();
    if (refreshAdditionalState != null) {
      unawaited(Future.wait<void>([membership, refreshAdditionalState()]));
    } else {
      unawaited(membership);
    }
  }

  Future<void> _scanContinuation(int generation) async {
    _loading = _requestedAlbumIds.isNotEmpty;
    _notify();
    while (_isCurrent(generation) && !_complete && !_refreshing) {
      final expectedOffset = _nextOffset;
      late final FavoriteAlbumPageLoadOperation operation;
      try {
        operation = sessionGateway.beginLoad(
          offset: expectedOffset,
          size: FavoriteAlbumController.pageSize,
        );
      } on Object {
        break;
      }
      _operation = operation;
      final result = await operation.run();
      if (identical(_operation, operation)) _operation = null;
      if (!_isCurrent(generation) || _refreshing) return;
      if (_isSessionFailure(result.failure)) {
        _invalidateSession();
        return;
      }
      if (!_validPage(result, expectedOffset)) break;
      _acceptCurrentPage(result);
    }
    if (!_isCurrent(generation)) return;
    _loading = false;
    _diagnostic(
      _complete && _scanReliable ? 'preload_complete' : 'preload_paused',
    );
    _notify();
  }

  Future<void> _scanRefresh(int generation) async {
    while (_isCurrent(generation) && _refreshing) {
      final expectedOffset = _refreshNextOffset;
      late final FavoriteAlbumPageLoadOperation operation;
      try {
        operation = sessionGateway.beginLoad(
          offset: expectedOffset,
          size: FavoriteAlbumController.pageSize,
        );
      } on Object {
        break;
      }
      _operation = operation;
      final result = await operation.run();
      if (identical(_operation, operation)) _operation = null;
      if (!_isCurrent(generation) || !_refreshing) return;
      if (_isSessionFailure(result.failure)) {
        _invalidateSession();
        return;
      }
      if (!_validPage(result, expectedOffset)) break;
      _acceptRefreshPage(result);
      if (!result.hasMore) {
        if (_refreshReliable) _commitRefresh();
        break;
      }
    }
    if (!_isCurrent(generation)) return;
    _refreshing = false;
    _refreshIds = null;
    _diagnostic('reconcile_finished');
    _notify();
  }

  FavoriteAlbumPageLoadOperation _beginSharedLoad({
    required int offset,
    required int size,
  }) {
    final key = _AlbumPageKey(offset, size);
    var page = _sharedPages[key];
    if (page == null) {
      final source = _sourceGateway.beginLoad(offset: offset, size: size);
      final generation = _generation;
      late final Future<FavoriteAlbumPageResult> future;
      future = source.run().then((result) {
        if (_isCurrent(generation)) {
          if (_isSessionFailure(result.failure)) {
            _invalidateSession();
          } else if (result.failure == null) {
            if (_refreshing) {
              _acceptRefreshPage(result);
            } else {
              _acceptCurrentPage(result);
            }
          } else if (identical(_sharedPages[key]?.future, future)) {
            _sharedPages.remove(key);
          }
        }
        return result;
      });
      page = _SharedAlbumPage(source, future);
      _sharedPages[key] = page;
    }
    return _JoinedAlbumPageLoadOperation(page.future);
  }

  void _acceptCurrentPage(FavoriteAlbumPageResult result) {
    if (result.failure != null || result.offset != _nextOffset) return;
    _favoriteAlbumIds.addAll(result.membershipAlbumOpaqueIds);
    for (final album in result.albums) {
      if (album.providerId == providerId) _favoriteAlbumIds.add(album.opaqueId);
    }
    _scanReliable = _scanReliable && result.membershipIsExact;
    if (result.continuationOffset > _nextOffset) {
      _nextOffset = result.continuationOffset;
    }
    if (!result.hasMore) _complete = true;
    _notify();
  }

  void _acceptRefreshPage(FavoriteAlbumPageResult result) {
    final ids = _refreshIds;
    if (!_refreshing ||
        ids == null ||
        result.failure != null ||
        result.offset != _refreshNextOffset) {
      return;
    }
    ids.addAll(result.membershipAlbumOpaqueIds);
    for (final album in result.albums) {
      if (album.providerId == providerId) ids.add(album.opaqueId);
    }
    _refreshReliable = _refreshReliable && result.membershipIsExact;
    _needsReconciliation.removeAll(ids);
    if (result.continuationOffset > _refreshNextOffset) {
      _refreshNextOffset = result.continuationOffset;
    }
    _notify();
  }

  void _commitRefresh() {
    final ids = _refreshIds;
    if (ids == null) return;
    _favoriteAlbumIds
      ..clear()
      ..addAll(ids);
    _nextOffset = _refreshNextOffset;
    _complete = true;
    _scanReliable = true;
    _confirmedOverrides.clear();
    _needsReconciliation.clear();
  }

  bool _validPage(FavoriteAlbumPageResult result, int expectedOffset) =>
      result.failure == null &&
      result.offset == expectedOffset &&
      result.continuationOffset >= expectedOffset &&
      (!result.hasMore || result.continuationOffset > expectedOffset);

  bool _isSessionFailure(FavoriteAlbumFailure? failure) =>
      failure == FavoriteAlbumFailure.authenticationRequired ||
      failure == FavoriteAlbumFailure.credentialRejected ||
      failure == FavoriteAlbumFailure.credentialRejectedStorageCleanupFailed ||
      failure == FavoriteAlbumFailure.replaced;

  void _invalidateSession() {
    _generation += 1;
    _operation?.cancel();
    _operation = null;
    _scan = null;
    _refresh = null;
    _cancelSharedPages();
    _favoriteAlbumIds.clear();
    _sessionAvailable = false;
    _confirmedOverrides.clear();
    _requestedAlbumIds.clear();
    _needsReconciliation.clear();
    _nextOffset = 0;
    _complete = false;
    _loading = false;
    _scanReliable = true;
    _refreshing = false;
    _refreshIds = null;
    _notify();
  }

  void _cancelSharedPages() {
    for (final page in _sharedPages.values) {
      page.source.cancel();
    }
    _sharedPages.clear();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _diagnostic(String phase, {String? detail}) {
    debugPrint(
      'FURA_DIAGNOSTIC library_mutation provider=$providerId '
      'kind=album_favorite phase=$phase${detail == null ? '' : ' $detail'}',
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _operation?.cancel();
    _operation = null;
    _cancelSharedPages();
    super.dispose();
  }
}

class _AlbumMembershipGateway implements FavoriteAlbumGateway {
  const _AlbumMembershipGateway(this.owner);

  final AlbumFavoritePresentationController owner;

  @override
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) => owner._beginSharedLoad(offset: offset, size: size);
}

@immutable
class _AlbumPageKey {
  const _AlbumPageKey(this.offset, this.size);

  final int offset;
  final int size;

  @override
  bool operator ==(Object other) =>
      other is _AlbumPageKey && other.offset == offset && other.size == size;

  @override
  int get hashCode => Object.hash(offset, size);
}

class _SharedAlbumPage {
  const _SharedAlbumPage(this.source, this.future);

  final FavoriteAlbumPageLoadOperation source;
  final Future<FavoriteAlbumPageResult> future;
}

class _JoinedAlbumPageLoadOperation implements FavoriteAlbumPageLoadOperation {
  _JoinedAlbumPageLoadOperation(this._future);

  final Future<FavoriteAlbumPageResult> _future;
  bool _active = true;

  @override
  bool cancel() {
    final wasActive = _active;
    _active = false;
    return wasActive;
  }

  @override
  Future<FavoriteAlbumPageResult> run() async {
    if (!_active) {
      return const FavoriteAlbumPageResult(
        failure: FavoriteAlbumFailure.cancelled,
      );
    }
    final result = await _future;
    return _active
        ? result
        : const FavoriteAlbumPageResult(
            failure: FavoriteAlbumFailure.cancelled,
          );
  }
}

class AlbumFavoriteActionScope
    extends InheritedNotifier<AlbumFavoritePresentationController> {
  const AlbumFavoriteActionScope({
    required AlbumFavoritePresentationController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AlbumFavoritePresentationController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AlbumFavoriteActionScope>()
          ?.notifier;
}

Future<void> performAlbumFavoriteAction({
  required BuildContext context,
  required AlbumSummary album,
  required bool favorite,
  Future<void> Function()? refreshAdditionalState,
}) async {
  final controller = AlbumFavoriteActionScope.maybeOf(context);
  if (controller == null) return;
  final outcome = await controller.setFavorite(
    album: album,
    favorite: favorite,
    refreshAdditionalState: refreshAdditionalState,
  );
  if (!context.mounted) return;
  showLibraryMutationFeedback(context, outcome.status);
}
