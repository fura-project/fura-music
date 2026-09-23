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

class AlbumFavoritePresentationController extends ChangeNotifier {
  AlbumFavoritePresentationController({
    required this.providerId,
    required this.enabled,
    required this.gateway,
    required this.mutations,
  });

  final String providerId;
  final bool enabled;
  final FavoriteAlbumGateway gateway;
  final LibraryMutationCoordinator mutations;

  final Set<String> _favoriteAlbumIds = <String>{};
  final Set<String> _requestedAlbumIds = <String>{};
  Future<void>? _scan;
  FavoriteAlbumPageLoadOperation? _operation;
  bool _complete = false;
  bool _loading = false;
  bool _scanReliable = true;
  int _generation = 0;
  bool _disposed = false;

  AuthoritativeAlbumFavoriteState stateFor(AlbumSummary album) {
    if (!enabled || album.providerId != providerId) {
      return AuthoritativeAlbumFavoriteState.unavailable;
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

  /// Seeds a positive state from the provider's Favorite Albums collection.
  /// A visible row in that authoritative collection proves membership without
  /// issuing a second identical read when the user opens its detail page.
  void observeFavorite(AlbumSummary album) {
    if (!enabled || album.providerId != providerId) return;
    if (_favoriteAlbumIds.add(album.opaqueId)) _notify();
  }

  Future<AuthoritativeAlbumFavoriteState> resolve(AlbumSummary album) async {
    final initial = stateFor(album);
    if (initial == AuthoritativeAlbumFavoriteState.unavailable ||
        initial == AuthoritativeAlbumFavoriteState.favorite ||
        initial == AuthoritativeAlbumFavoriteState.notFavorite) {
      return initial;
    }
    _requestedAlbumIds.add(album.opaqueId);
    if (!_loading) {
      _loading = true;
      _notify();
    }
    final scan = _scan ??= _scanFavorites(_generation);
    await scan;
    if (identical(_scan, scan)) _scan = null;
    return stateFor(album);
  }

  Future<LibraryMutationOutcome<AlbumFavoriteState>> setFavorite({
    required AlbumSummary album,
    required bool favorite,
    Future<void> Function()? refreshAdditionalState,
  }) => mutations.setAlbumFavorite(
    album: album,
    favorite: favorite,
    refreshAuthoritativeState: () async {
      _invalidate();
      if (refreshAdditionalState != null) await refreshAdditionalState();
      await resolve(album);
    },
  );

  Future<void> _scanFavorites(int generation) async {
    var offset = 0;
    var reliable = true;
    while (_isCurrent(generation)) {
      late final FavoriteAlbumPageLoadOperation operation;
      try {
        operation = gateway.beginLoad(
          offset: offset,
          size: FavoriteAlbumController.pageSize,
        );
      } on Object {
        reliable = false;
        break;
      }
      _operation = operation;
      final result = await operation.run();
      if (identical(_operation, operation)) _operation = null;
      if (!_isCurrent(generation)) return;
      if (result.failure != null || result.offset != offset) {
        reliable = false;
        break;
      }
      reliable = reliable && result.omittedAlbumCount == 0;
      for (final album in result.albums) {
        if (album.providerId == providerId) {
          _favoriteAlbumIds.add(album.opaqueId);
        }
      }
      _notify();
      if (_requestedAlbumIds.isNotEmpty &&
          _requestedAlbumIds.every(_favoriteAlbumIds.contains)) {
        break;
      }
      if (!result.hasMore) {
        _complete = true;
        break;
      }
      if (result.continuationOffset <= offset) {
        reliable = false;
        break;
      }
      offset = result.continuationOffset;
    }
    _finishScan(generation, reliable: reliable && _complete);
  }

  void _finishScan(int generation, {required bool reliable}) {
    if (!_isCurrent(generation)) return;
    _scanReliable = reliable;
    _loading = false;
    _notify();
  }

  void _invalidate() {
    _generation += 1;
    _operation?.cancel();
    _operation = null;
    _scan = null;
    _favoriteAlbumIds.clear();
    _requestedAlbumIds.clear();
    _complete = false;
    _loading = false;
    _scanReliable = true;
    _notify();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _operation?.cancel();
    _operation = null;
    super.dispose();
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
