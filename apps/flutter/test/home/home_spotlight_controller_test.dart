import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/home_spotlight_controller.dart';
import 'package:flutterustmusic/home/official_playlist_controller.dart';
import 'package:flutterustmusic/home/official_playlist_gateway.dart';

void main() {
  test(
    'official source wins without conflating the public recommendation feed',
    () async {
      final officialGateway = _OfficialGateway(
        OfficialPlaylistPageResult(
          page: 1,
          nextPage: 2,
          total: 12,
          hasMore: true,
          playlists: List.generate(
            10,
            (index) => OfficialPlaylistSummary(
              providerId: 'qq-music',
              opaqueId: 'catalog:official-$index',
              title: 'Official $index',
            ),
          ),
        ),
      );
      final publicGateway = _PublicGateway(
        const RecommendedPlaylistPageResult(
          continuationOffset: 1,
          playlists: [
            RecommendedPlaylistSummary(
              providerId: 'qq-music',
              opaqueId: 'catalog:public-1',
              title: 'Public one',
            ),
          ],
        ),
      );
      final official = OfficialPlaylistController(officialGateway);
      final public = RecommendedPlaylistController(publicGateway);
      final source = HomeSpotlightController(official, public);
      addTearDown(() {
        source.dispose();
        official.dispose();
        public.dispose();
      });

      await source.load();

      expect(source.stage, HomeSpotlightStage.content);
      expect(source.kind, HomeSpotlightKind.official);
      expect(
        source.candidates,
        hasLength(HomeSpotlightController.candidateLimit),
      );
      expect(source.candidates.first.opaqueId, 'catalog:official-0');
      expect(source.candidates.last.opaqueId, 'catalog:official-7');
      expect(officialGateway.requests, [(1, 8)]);
      expect(publicGateway.requests, [(0, 20)]);

      // Rotation and presentation reads operate on the bounded local candidate
      // window; only an explicit refresh may request another window.
      for (var index = 0; index < 20; index += 1) {
        expect(
          source.candidates[index % source.candidates.length].title,
          isNotEmpty,
        );
      }
      expect(officialGateway.requests, hasLength(1));
      expect(publicGateway.requests, hasLength(1));

      await source.load();
      expect(officialGateway.requests, hasLength(2));
      expect(publicGateway.requests, hasLength(2));
    },
  );

  test(
    'official failure falls back to a truthfully typed public spotlight',
    () async {
      final official = OfficialPlaylistController(
        _OfficialGateway(
          const OfficialPlaylistPageResult(
            failure: OfficialPlaylistFailure.serviceUnavailable,
          ),
        ),
      );
      final public = RecommendedPlaylistController(
        _PublicGateway(
          const RecommendedPlaylistPageResult(
            continuationOffset: 1,
            playlists: [
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'catalog:public-1',
                title: 'Public fallback',
              ),
            ],
          ),
        ),
      );
      final source = HomeSpotlightController(official, public);
      addTearDown(() {
        source.dispose();
        official.dispose();
        public.dispose();
      });

      await source.load();

      expect(source.stage, HomeSpotlightStage.content);
      expect(source.kind, HomeSpotlightKind.publicFallback);
      expect(source.candidates.single.title, 'Public fallback');
    },
  );

  test('candidate window changes only after an explicit refresh', () async {
    final officialGateway = _OfficialGateway(
      const OfficialPlaylistPageResult(
        page: 1,
        nextPage: 2,
        total: 1,
        playlists: [
          OfficialPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'catalog:first-window',
            title: 'First window',
          ),
        ],
      ),
    );
    final official = OfficialPlaylistController(officialGateway);
    final public = RecommendedPlaylistController(
      _PublicGateway(const RecommendedPlaylistPageResult()),
    );
    final source = HomeSpotlightController(official, public);
    addTearDown(() {
      source.dispose();
      official.dispose();
      public.dispose();
    });

    await source.load();
    expect(source.candidates.single.opaqueId, 'catalog:first-window');

    officialGateway.result = const OfficialPlaylistPageResult(
      page: 1,
      nextPage: 2,
      total: 1,
      playlists: [
        OfficialPlaylistSummary(
          providerId: 'qq-music',
          opaqueId: 'catalog:refreshed-window',
          title: 'Refreshed window',
        ),
      ],
    );
    expect(source.candidates.single.opaqueId, 'catalog:first-window');

    await source.load();
    expect(source.candidates.single.opaqueId, 'catalog:refreshed-window');
    expect(officialGateway.requests, [(1, 8), (1, 8)]);
  });
}

class _OfficialGateway implements OfficialPlaylistGateway {
  _OfficialGateway(this.result);

  OfficialPlaylistPageResult result;
  final List<(int, int)> requests = [];

  @override
  OfficialPlaylistPageLoadOperation beginLoad({
    required int page,
    required int size,
  }) {
    requests.add((page, size));
    return _OfficialOperation(result);
  }
}

class _OfficialOperation implements OfficialPlaylistPageLoadOperation {
  const _OfficialOperation(this.result);

  final OfficialPlaylistPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<OfficialPlaylistPageResult> run() async => result;
}

class _PublicGateway implements RecommendedPlaylistGateway {
  _PublicGateway(this.result);

  final RecommendedPlaylistPageResult result;
  final List<(int, int)> requests = [];

  @override
  RecommendedPlaylistPageLoadOperation beginLoad({
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return _PublicOperation(result);
  }
}

class _PublicOperation implements RecommendedPlaylistPageLoadOperation {
  const _PublicOperation(this.result);

  final RecommendedPlaylistPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<RecommendedPlaylistPageResult> run() async => result;
}
