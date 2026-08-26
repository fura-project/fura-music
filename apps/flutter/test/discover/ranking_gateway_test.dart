import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/rankings.dart' as bridge;

void main() {
  const expected = RankingSummary(
    providerId: 'qq-music',
    opaqueId: 'ranking:62001',
    title: 'Synthetic ranking',
  );

  test('maps immutable ranking groups and optional current metadata', () {
    final result = mapBridgeRankingGroups(
      const bridge.QqMusicRankingGroupLoad(
        groups: [
          bridge.CatalogRankingGroup(
            title: 'Synthetic group',
            rankings: [
              bridge.CatalogRankingSummary(
                providerId: 'qq-music',
                opaqueId: 'ranking:62001',
                title: 'Synthetic ranking',
                period: 'fixture-period',
                trackCount: 100,
              ),
            ],
          ),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.groups.single.title, 'Synthetic group');
    expect(result.groups.single.rankings.single.period, 'fixture-period');
    expect(result.groups.single.rankings.single.trackCount, 100);
    expect(
      () => result.groups.add(result.groups.single),
      throwsUnsupportedError,
    );
  });

  test('rejects malformed or contradictory group results', () {
    final malformed = mapBridgeRankingGroups(
      const bridge.QqMusicRankingGroupLoad(
        groups: [bridge.CatalogRankingGroup(title: ' ', rankings: [])],
      ),
    );
    expect(malformed.failure, RankingFailure.invalidResponse);

    final contradictory = mapBridgeRankingGroups(
      const bridge.QqMusicRankingGroupLoad(
        groups: [
          bridge.CatalogRankingGroup(
            title: 'Synthetic group',
            rankings: [
              bridge.CatalogRankingSummary(
                providerId: 'qq-music',
                opaqueId: 'ranking:62001',
                title: 'Synthetic ranking',
              ),
            ],
          ),
        ],
        failure: bridge.QqMusicRankingLoadFailure.network,
      ),
    );
    expect(contradictory.failure, RankingFailure.invalidResponse);
  });

  test('maps ranking Track page and rejects route mismatch', () {
    const bridgeResult = bridge.QqMusicRankingTrackPageLoad(
      ranking: bridge.CatalogRankingSummary(
        providerId: 'qq-music',
        opaqueId: 'ranking:62001',
        title: 'Updated ranking',
        period: 'fixture-period',
      ),
      offset: 0,
      total: 31,
      hasMore: true,
      tracks: [
        bridge_library.LibraryTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:41001:0:fixtureMid:-',
          title: 'Synthetic Track',
          artistNames: ['Artist'],
        ),
      ],
    );
    final mapped = mapBridgeRankingTrackPage(bridgeResult, expected);

    expect(mapped.failure, isNull);
    expect(mapped.ranking!.title, 'Updated ranking');
    expect(mapped.total, 31);
    expect(mapped.hasMore, isTrue);
    expect(mapped.tracks.single.title, 'Synthetic Track');
    expect(
      () => mapped.tracks.add(mapped.tracks.single),
      throwsUnsupportedError,
    );

    const wrongRoute = RankingSummary(
      providerId: 'qq-music',
      opaqueId: 'ranking:62002',
      title: 'Wrong route',
    );
    expect(
      mapBridgeRankingTrackPage(bridgeResult, wrongRoute).failure,
      RankingFailure.invalidResponse,
    );
  });

  test('maps every Bridge failure without inferring account state', () {
    expect(
      mapBridgeRankingFailure(bridge.QqMusicRankingLoadFailure.network),
      RankingFailure.network,
    );
    expect(
      mapBridgeRankingFailure(
        bridge.QqMusicRankingLoadFailure.serviceUnavailable,
      ),
      RankingFailure.serviceUnavailable,
    );
    expect(
      mapBridgeRankingFailure(bridge.QqMusicRankingLoadFailure.cancelled),
      RankingFailure.cancelled,
    );
  });
}
