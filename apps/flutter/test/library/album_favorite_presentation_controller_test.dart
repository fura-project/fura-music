import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/library/album_favorite_gateway.dart';
import 'package:flutterustmusic/library/album_favorite_presentation_controller.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';

void main() {
  const favorite = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'favorite',
    title: 'Favorite',
  );
  const other = AlbumSummary(
    providerId: 'qq-music',
    opaqueId: 'other',
    title: 'Other',
  );

  test(
    'preload retains continuation and proves positive and negative',
    () async {
      final gateway = _FakeGateway.fromResults([
        const FavoriteAlbumPageResult(
          continuationOffset: 1,
          total: 2,
          hasMore: true,
          membershipAlbumOpaqueIds: ['favorite'],
          albums: [favorite],
        ),
        const FavoriteAlbumPageResult(
          offset: 1,
          continuationOffset: 2,
          total: 2,
        ),
      ]);
      final controller = _controller(gateway);

      await controller.preload();

      expect(
        controller.stateFor(favorite),
        AuthoritativeAlbumFavoriteState.favorite,
      );
      expect(
        controller.stateFor(other),
        AuthoritativeAlbumFavoriteState.notFavorite,
      );
      expect(gateway.requests, [(0, 20), (1, 20)]);
      await controller.resolve(other);
      expect(gateway.requests.length, 2);
      controller.dispose();
    },
  );

  test('omitted presentation Album does not poison membership', () async {
    final gateway = _FakeGateway.fromResults([
      const FavoriteAlbumPageResult(
        continuationOffset: 1,
        total: 1,
        omittedAlbumCount: 1,
        membershipAlbumOpaqueIds: ['favorite'],
      ),
    ]);
    final controller = _controller(gateway);

    await controller.preload();

    expect(
      controller.stateFor(favorite),
      AuthoritativeAlbumFavoriteState.favorite,
    );
    expect(
      controller.stateFor(other),
      AuthoritativeAlbumFavoriteState.notFavorite,
    );
    controller.dispose();
  });

  test(
    'identity-incomplete Album collection never fabricates a negative',
    () async {
      final gateway = _FakeGateway.fromResults([
        const FavoriteAlbumPageResult(
          continuationOffset: 1,
          total: 1,
          membershipIsExact: false,
          omittedAlbumCount: 1,
        ),
      ]);
      final controller = _controller(gateway);

      await controller.preload();

      expect(
        controller.stateFor(other),
        AuthoritativeAlbumFavoriteState.unknown,
      );
      controller.dispose();
    },
  );

  test('Favorite Albums page joins the membership page future', () async {
    final pending = Completer<FavoriteAlbumPageResult>();
    final gateway = _FakeGateway([_PendingAlbumOperation(pending)]);
    final controller = _controller(gateway);

    final page = controller.sessionGateway.beginLoad(offset: 0, size: 20).run();
    expect(gateway.requests, [(0, 20)]);
    pending.complete(
      const FavoriteAlbumPageResult(
        continuationOffset: 1,
        total: 1,
        membershipAlbumOpaqueIds: ['favorite'],
        albums: [favorite],
      ),
    );
    await page;
    await controller.preload();

    expect(gateway.requests, [(0, 20)]);
    expect(
      controller.stateFor(favorite),
      AuthoritativeAlbumFavoriteState.favorite,
    );
    controller.dispose();
  });

  test('confirmed favorite applies local delta while reconciling', () async {
    final refresh = Completer<FavoriteAlbumPageResult>();
    final gateway = _FakeGateway([
      const _ImmediateAlbumOperation(FavoriteAlbumPageResult()),
      _PendingAlbumOperation(refresh),
    ]);
    final controller = _controller(
      gateway,
      mutationGateway: _AlbumMutationGateway(
        const AlbumFavoriteMutationResult(
          confirmedState: AlbumFavoriteState.favorite,
        ),
      ),
    );
    await controller.preload();

    final outcome = await controller.setFavorite(album: other, favorite: true);

    expect(outcome.status, LibraryMutationStatus.confirmed);
    expect(
      controller.stateFor(other),
      AuthoritativeAlbumFavoriteState.favorite,
    );
    expect(gateway.requests, [(0, 20), (0, 20)]);
    controller.dispose();
  });

  test('unknown Album outcome targets only the mutated identity', () async {
    final refresh = Completer<FavoriteAlbumPageResult>();
    final gateway = _FakeGateway([
      const _ImmediateAlbumOperation(
        FavoriteAlbumPageResult(
          continuationOffset: 1,
          total: 1,
          membershipAlbumOpaqueIds: ['favorite'],
        ),
      ),
      _PendingAlbumOperation(refresh),
    ]);
    final controller = _controller(
      gateway,
      mutationGateway: _AlbumMutationGateway(
        const AlbumFavoriteMutationResult(
          failure: AlbumFavoriteMutationFailure.networkOutcomeUnknown,
        ),
      ),
    );
    await controller.preload();

    final outcome = await controller.setFavorite(album: other, favorite: true);

    expect(outcome.status, LibraryMutationStatus.outcomeUnknown);
    expect(controller.stateFor(other), AuthoritativeAlbumFavoriteState.unknown);
    expect(
      controller.stateFor(favorite),
      AuthoritativeAlbumFavoriteState.favorite,
    );
    controller.dispose();
  });

  test('confirmed unfavorite applies an immediate negative delta', () async {
    final refresh = Completer<FavoriteAlbumPageResult>();
    final gateway = _FakeGateway([
      const _ImmediateAlbumOperation(
        FavoriteAlbumPageResult(
          continuationOffset: 1,
          total: 1,
          membershipAlbumOpaqueIds: ['favorite'],
        ),
      ),
      _PendingAlbumOperation(refresh),
    ]);
    final controller = _controller(
      gateway,
      mutationGateway: _AlbumMutationGateway(
        const AlbumFavoriteMutationResult(
          confirmedState: AlbumFavoriteState.notFavorite,
        ),
      ),
    );
    await controller.preload();

    final outcome = await controller.setFavorite(
      album: favorite,
      favorite: false,
    );

    expect(outcome.status, LibraryMutationStatus.confirmed);
    expect(
      controller.stateFor(favorite),
      AuthoritativeAlbumFavoriteState.notFavorite,
    );
    controller.dispose();
  });

  test('definitive failure preserves authoritative Album state', () async {
    final gateway = _FakeGateway.fromResults([
      const FavoriteAlbumPageResult(
        continuationOffset: 1,
        total: 1,
        membershipAlbumOpaqueIds: ['favorite'],
      ),
    ]);
    final controller = _controller(
      gateway,
      mutationGateway: _AlbumMutationGateway(
        const AlbumFavoriteMutationResult(
          failure: AlbumFavoriteMutationFailure.invalidRequest,
        ),
      ),
    );
    await controller.preload();

    final outcome = await controller.setFavorite(
      album: favorite,
      favorite: false,
    );

    expect(outcome.status, LibraryMutationStatus.definitiveFailure);
    expect(
      controller.stateFor(favorite),
      AuthoritativeAlbumFavoriteState.favorite,
    );
    expect(gateway.requests, [(0, 20)]);
    controller.dispose();
  });

  test('credential rejection invalidates the Album account session', () async {
    final gateway = _FakeGateway.fromResults([
      const FavoriteAlbumPageResult(
        failure: FavoriteAlbumFailure.credentialRejected,
      ),
    ]);
    final controller = _controller(gateway);

    await controller.preload();

    expect(
      controller.stateFor(favorite),
      AuthoritativeAlbumFavoriteState.unavailable,
    );
    controller.dispose();
  });
}

AlbumFavoritePresentationController _controller(
  FavoriteAlbumGateway gateway, {
  AlbumFavoriteGateway? mutationGateway,
}) {
  final mutations = LibraryMutationCoordinator(
    providerId: 'qq-music',
    albumFavoriteGateway: mutationGateway,
  );
  addTearDown(mutations.dispose);
  return AlbumFavoritePresentationController(
    providerId: 'qq-music',
    enabled: true,
    gateway: gateway,
    mutations: mutations,
  );
}

class _FakeGateway implements FavoriteAlbumGateway {
  _FakeGateway(this.operations);

  _FakeGateway.fromResults(List<FavoriteAlbumPageResult> results)
    : operations = results
          .map<FavoriteAlbumPageLoadOperation>(_ImmediateAlbumOperation.new)
          .toList();

  final List<FavoriteAlbumPageLoadOperation> operations;
  final List<(int, int)> requests = [];
  int _index = 0;

  @override
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return operations[_index++];
  }
}

class _ImmediateAlbumOperation implements FavoriteAlbumPageLoadOperation {
  const _ImmediateAlbumOperation(this.result);

  final FavoriteAlbumPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<FavoriteAlbumPageResult> run() async => result;
}

class _PendingAlbumOperation implements FavoriteAlbumPageLoadOperation {
  _PendingAlbumOperation(this.completer);

  final Completer<FavoriteAlbumPageResult> completer;

  @override
  bool cancel() => true;

  @override
  Future<FavoriteAlbumPageResult> run() => completer.future;
}

class _AlbumMutationGateway implements AlbumFavoriteGateway {
  const _AlbumMutationGateway(this.result);

  final AlbumFavoriteMutationResult result;

  @override
  AlbumFavoriteMutationOperation beginMutation({
    required String providerId,
    required String opaqueAlbumId,
    required AlbumFavoriteState desiredState,
  }) => _AlbumMutationOperation(result);
}

class _AlbumMutationOperation implements AlbumFavoriteMutationOperation {
  const _AlbumMutationOperation(this.result);

  final AlbumFavoriteMutationResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumFavoriteMutationResult> run() async => result;
}
