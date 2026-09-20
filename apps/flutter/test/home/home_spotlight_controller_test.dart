import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/home_spotlight_controller.dart';
import 'package:flutterustmusic/home/official_playlist_controller.dart';
import 'package:flutterustmusic/home/official_playlist_gateway.dart';

void main() {
  test('newer official refresh wins and late cancelled results cannot restore old data', () async {
    final gateway = _PendingOfficialGateway();
    final official = OfficialPlaylistController(gateway);
    final public = RecommendedPlaylistController(
      _PublicGateway(const RecommendedPlaylistPageResult()),
    );
    final source = HomeSpotlightController(official, public);
    addTearDown(() {
      source.dispose();
      official.dispose();
      public.dispose();
    });
    final first = source.load();
    expect(official.stage, OfficialPlaylistStage.loading);
    expect(source.candidates, isEmpty);
    gateway.operations[0].completion.complete(_window('A'));
    await first;
    final old = source.load();
    expect(source.refreshing, isTrue);
    expect(source.candidates.single.opaqueId, 'catalog:A');
    final newer = source.load();
    expect(gateway.operations[1].cancellations, 1);
    expect(source.candidates.single.opaqueId, 'catalog:A');
    gateway.operations[2].completion.complete(_window('C'));
    await newer;
    expect(source.refreshing, isFalse);
    expect(source.candidates.single.opaqueId, 'catalog:C');
    gateway.operations[1].completion.complete(_window('B'));
    await old;
    expect(source.candidates.single.opaqueId, 'catalog:C');
    expect(official.stage, OfficialPlaylistStage.content);
  });

  test(
    'disposed source does not carry its pending snapshot into a new context',
    () async {
      final gateway = _PendingOfficialGateway();
      final oldOfficial = OfficialPlaylistController(gateway);
      final oldPublic = RecommendedPlaylistController(
        _PublicGateway(const RecommendedPlaylistPageResult()),
      );
      final oldSource = HomeSpotlightController(oldOfficial, oldPublic);
      final first = oldSource.load();
      gateway.operations[0].completion.complete(_window('old-account'));
      await first;
      final pending = oldSource.load();
      expect(oldSource.refreshing, isTrue);
      oldSource.dispose();
      oldOfficial.dispose();
      oldPublic.dispose();
      expect(gateway.operations[1].cancellations, 1);
      await oldSource.load();
      await oldOfficial.load();
      expect(gateway.operations, hasLength(2));
      final newOfficial = OfficialPlaylistController(_PendingOfficialGateway());
      final newPublic = RecommendedPlaylistController(
        _PublicGateway(const RecommendedPlaylistPageResult()),
      );
      final newSource = HomeSpotlightController(newOfficial, newPublic);
      addTearDown(() {
        newSource.dispose();
        newOfficial.dispose();
        newPublic.dispose();
      });
      expect(newSource.candidates, isEmpty);
      gateway.operations[1].completion.complete(_window('late-old-account'));
      await pending;
      expect(newSource.candidates, isEmpty);
      expect(newSource.refreshing, isFalse);
    },
  );

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

class _PendingOfficialGateway implements OfficialPlaylistGateway {
  final operations = <_PendingOfficialOperation>[];

  @override
  OfficialPlaylistPageLoadOperation beginLoad({
    required int page,
    required int size,
  }) {
    final operation = _PendingOfficialOperation();
    operations.add(operation);
    return operation;
  }
}

class _PendingOfficialOperation implements OfficialPlaylistPageLoadOperation {
  final completion = Completer<OfficialPlaylistPageResult>();
  int cancellations = 0;
  @override
  bool cancel() {
    cancellations++;
    return true;
  }

  @override
  Future<OfficialPlaylistPageResult> run() => completion.future;
}

OfficialPlaylistPageResult _window(String id) => OfficialPlaylistPageResult(
  page: 1,
  nextPage: 2,
  total: 1,
  playlists: [
    OfficialPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'catalog:$id',
      title: id,
    ),
  ],
);
