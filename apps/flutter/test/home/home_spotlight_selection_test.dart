import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/home_page.dart';

void main() {
  const playlists = [
    RecommendedPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'catalog:3',
      title: 'Third',
    ),
    RecommendedPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'catalog:1',
      title: 'First',
    ),
    RecommendedPlaylistSummary(
      providerId: 'qq-music',
      opaqueId: 'catalog:2',
      title: 'Second',
    ),
  ];

  test('selects a stable daily spotlight independent of response order', () {
    final day = DateTime(2026, 9, 2, 23, 59);

    final selected = selectHomeSpotlightForDay(playlists, day);
    final reordered = selectHomeSpotlightForDay(
      playlists.reversed.toList(growable: false),
      day,
    );

    expect(selected?.opaqueId, reordered?.opaqueId);
  });

  test('advances the daily starting spotlight on the next date', () {
    final first = selectHomeSpotlightForDay(playlists, DateTime(2026, 9, 2));
    final next = selectHomeSpotlightForDay(playlists, DateTime(2026, 9, 3));

    expect(first, isNotNull);
    expect(next, isNotNull);
    expect(next?.opaqueId, isNot(first?.opaqueId));
  });

  test('returns no spotlight when the public recommendation set is empty', () {
    expect(selectHomeSpotlightForDay(const [], DateTime(2026, 9, 2)), isNull);
  });
}
