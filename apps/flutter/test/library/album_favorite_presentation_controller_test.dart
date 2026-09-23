import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
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
    'positive favorite is authoritative without draining more pages',
    () async {
      final gateway = _FakeGateway([
        const FavoriteAlbumPageResult(
          continuationOffset: 1,
          total: 2,
          hasMore: true,
          albums: [favorite],
        ),
      ]);
      final controller = _controller(gateway);

      expect(
        await controller.resolve(favorite),
        AuthoritativeAlbumFavoriteState.favorite,
      );
      expect(gateway.requests, [(0, 20)]);
      controller.dispose();
    },
  );

  test('complete exact collection proves a negative state', () async {
    final gateway = _FakeGateway([
      const FavoriteAlbumPageResult(total: 1, albums: [favorite]),
    ]);
    final controller = _controller(gateway);

    expect(
      await controller.resolve(other),
      AuthoritativeAlbumFavoriteState.notFavorite,
    );
    controller.dispose();
  });

  test('omitted rows keep a negative state unknown', () async {
    final gateway = _FakeGateway([
      const FavoriteAlbumPageResult(total: 1, omittedAlbumCount: 1),
    ]);
    final controller = _controller(gateway);

    expect(
      await controller.resolve(other),
      AuthoritativeAlbumFavoriteState.unknown,
    );
    controller.dispose();
  });

  test('an authoritative collection row seeds a positive without a read', () {
    final gateway = _FakeGateway(const []);
    final controller = _controller(gateway);

    controller.observeFavorite(favorite);

    expect(
      controller.stateFor(favorite),
      AuthoritativeAlbumFavoriteState.favorite,
    );
    expect(gateway.requests, isEmpty);
    controller.dispose();
  });
}

AlbumFavoritePresentationController _controller(FavoriteAlbumGateway gateway) {
  final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
  addTearDown(mutations.dispose);
  return AlbumFavoritePresentationController(
    providerId: 'qq-music',
    enabled: true,
    gateway: gateway,
    mutations: mutations,
  );
}

class _FakeGateway implements FavoriteAlbumGateway {
  _FakeGateway(this.results);

  final List<FavoriteAlbumPageResult> results;
  final List<(int, int)> requests = [];
  int _index = 0;

  @override
  FavoriteAlbumPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return _Operation(results[_index++]);
  }
}

class _Operation implements FavoriteAlbumPageLoadOperation {
  const _Operation(this.result);

  final FavoriteAlbumPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<FavoriteAlbumPageResult> run() async => result;
}
