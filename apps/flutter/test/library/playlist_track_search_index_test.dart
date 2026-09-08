import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_track_search_index.dart';

void main() {
  test('normalizes case width punctuation and common Latin accents', () {
    expect(normalizePlaylistSearchText('  ＮÉＶＡＤＡ—Live  '), 'nevada live');
    expect(normalizePlaylistSearchText('周杰伦／晴天'), '周杰伦 晴天');
  });

  test('ranks exact fields before approximate spelling matches', () {
    final index = PlaylistTrackSearchIndex()
      ..update(const [
        PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:approximate',
          title: 'Nevada',
          artistNames: ['Vicetone'],
        ),
        PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:exact',
          title: 'Neveda Nights',
          artistNames: ['Synthetic Artist'],
        ),
      ]);

    final result = index.search('neveda');

    expect(result.tracks.map((track) => track.opaqueId), [
      'track:exact',
      'track:approximate',
    ]);
    expect(result.exactMatchCount, 1);
    expect(result.approximateMatchCount, 1);
    expect(result.approximateOnly, isFalse);
  });

  test('matches title Artist and Album terms across fields', () {
    final index = PlaylistTrackSearchIndex()
      ..update(const [
        PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:cross-fields',
          title: 'Take Me Hand',
          artistNames: ['Cécile Corbel'],
          albumTitle: 'SongBook Vol. 4',
        ),
      ]);

    expect(index.search('take cecile').tracks, hasLength(1));
    expect(index.search('songbook 4').tracks, hasLength(1));
    expect(index.search('take corbell').tracks, hasLength(1));
  });

  test('does not fuzz short or unrelated queries', () {
    final index = PlaylistTrackSearchIndex()
      ..update(const [
        PlaylistTrackSummary(
          providerId: 'qq-music',
          opaqueId: 'track:nevada',
          title: 'Nevada',
          artistNames: ['Vicetone'],
        ),
      ]);

    expect(index.search('nvd').tracks, isEmpty);
    expect(index.search('banana').tracks, isEmpty);
    expect(index.search('内华达').tracks, isEmpty);
  });

  test('extends append-only pages and rebuilds replaced snapshots', () {
    const first = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:first',
      title: 'First Track',
      artistNames: [],
    );
    const second = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:second',
      title: 'Nevada',
      artistNames: [],
    );
    const replacement = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:replacement',
      title: 'Replacement',
      artistNames: [],
    );
    final index = PlaylistTrackSearchIndex()..update(const [first]);
    expect(index.search('neveda').tracks, isEmpty);

    index.update(const [first, second]);
    expect(index.search('neveda').tracks.single.opaqueId, 'track:second');

    index.update(const [replacement]);
    expect(index.search('neveda').tracks, isEmpty);
    expect(
      index.search('replacement').tracks.single.opaqueId,
      'track:replacement',
    );
  });

  test('finds an approximate result appended beyond one thousand rows', () {
    final tracks = List.generate(
      1032,
      (index) => PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:$index',
        title: index == 1001 ? 'Nevada' : 'Synthetic Track $index',
        artistNames: const ['Synthetic Artist'],
      ),
      growable: false,
    );
    final index = PlaylistTrackSearchIndex();
    for (var end = 100; end < tracks.length; end += 100) {
      index.update(tracks.sublist(0, end));
    }
    index.update(tracks);

    final result = index.search('neveda');

    expect(result.tracks.single.opaqueId, 'track:1001');
    expect(result.approximateOnly, isTrue);
  });
}
