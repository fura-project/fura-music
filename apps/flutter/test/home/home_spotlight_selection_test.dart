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

  test('preserves the first playlist in provider editorial order', () {
    final day = DateTime(2026, 9, 2, 23, 59);

    final selected = selectHomeSpotlightForDay(playlists, day);

    expect(selected?.opaqueId, 'catalog:3');
  });

  test('date changes do not reorder the provider-owned candidate window', () {
    final first = selectHomeSpotlightForDay(playlists, DateTime(2026, 9, 2));
    final next = selectHomeSpotlightForDay(playlists, DateTime(2026, 9, 3));

    expect(first, isNotNull);
    expect(next, isNotNull);
    expect(next?.opaqueId, first?.opaqueId);
  });

  test('returns no spotlight when the candidate window is empty', () {
    expect(selectHomeSpotlightForDay(const [], DateTime(2026, 9, 2)), isNull);
  });
}
