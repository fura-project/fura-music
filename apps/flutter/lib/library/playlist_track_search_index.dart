import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

class PlaylistTrackSearchResult {
  const PlaylistTrackSearchResult({
    this.tracks = const [],
    this.exactMatchCount = 0,
  });

  final List<PlaylistTrackSummary> tracks;
  final int exactMatchCount;

  int get approximateMatchCount => tracks.length - exactMatchCount;
  bool get approximateOnly => tracks.isNotEmpty && exactMatchCount == 0;
}

/// A page-local index for incrementally loaded playlist Tracks.
///
/// Provider and user content remains untouched. Only normalized presentation
/// copies are retained for matching, and a refreshed/replaced prefix rebuilds
/// the index instead of mixing snapshots.
class PlaylistTrackSearchIndex {
  final List<_IndexedTrack> _entries = [];
  final List<String> _fingerprints = [];
  int _version = 0;
  int _cachedVersion = -1;
  String? _cachedQuery;
  PlaylistTrackSearchResult _cachedResult = const PlaylistTrackSearchResult();

  void update(List<PlaylistTrackSummary> tracks) {
    var appendOnly = tracks.length >= _entries.length;
    if (appendOnly) {
      for (var index = 0; index < _entries.length; index += 1) {
        if (_fingerprint(tracks[index]) != _fingerprints[index]) {
          appendOnly = false;
          break;
        }
      }
    }
    if (appendOnly && tracks.length == _entries.length) return;
    if (!appendOnly) {
      _entries.clear();
      _fingerprints.clear();
    }
    for (var index = _entries.length; index < tracks.length; index += 1) {
      final track = tracks[index];
      _entries.add(_IndexedTrack(track, index));
      _fingerprints.add(_fingerprint(track));
    }
    if (_entries.length != tracks.length) {
      _entries.removeRange(tracks.length, _entries.length);
      _fingerprints.removeRange(tracks.length, _fingerprints.length);
    }
    _version += 1;
  }

  PlaylistTrackSearchResult search(String rawQuery) {
    final query = normalizePlaylistSearchText(rawQuery);
    if (query.isEmpty) return const PlaylistTrackSearchResult();
    if (_cachedVersion == _version && _cachedQuery == query) {
      return _cachedResult;
    }

    final queryTokens = query.split(' ');
    final matches = <_ScoredTrack>[];
    for (final entry in _entries) {
      final exactScore = entry.exactScore(query, queryTokens);
      if (exactScore != null) {
        matches.add(
          _ScoredTrack(entry.track, entry.position, exactScore, true),
        );
        continue;
      }
      final fuzzyScore = entry.fuzzyScore(queryTokens);
      if (fuzzyScore != null) {
        matches.add(
          _ScoredTrack(entry.track, entry.position, fuzzyScore, false),
        );
      }
    }
    matches.sort((left, right) {
      final byScore = left.score.compareTo(right.score);
      return byScore != 0 ? byScore : left.position.compareTo(right.position);
    });
    final exactMatchCount = matches.where((match) => match.exact).length;
    _cachedVersion = _version;
    _cachedQuery = query;
    _cachedResult = PlaylistTrackSearchResult(
      tracks: List.unmodifiable(matches.map((match) => match.track)),
      exactMatchCount: exactMatchCount,
    );
    return _cachedResult;
  }
}

class _IndexedTrack {
  _IndexedTrack(this.track, this.position)
    : fields = List.unmodifiable(
        [
          track.title,
          ?track.subtitle,
          ...track.artistNames,
          ?track.albumTitle,
        ].map(normalizePlaylistSearchText).where((value) => value.isNotEmpty),
      ),
      tokens = List.unmodifiable(
        [track.title, ?track.subtitle, ...track.artistNames, ?track.albumTitle]
            .map(normalizePlaylistSearchText)
            .where((value) => value.isNotEmpty)
            .expand((value) => value.split(' '))
            .where((value) => value.isNotEmpty)
            .toSet(),
      );

  final PlaylistTrackSummary track;
  final int position;
  final List<String> fields;
  final List<String> tokens;

  int? exactScore(String query, List<String> queryTokens) {
    if (fields.any((field) => field == query)) return 0;
    if (fields.any((field) => field.startsWith(query))) return 1;
    if (fields.any((field) => field.contains(query))) return 2;
    if (queryTokens.length > 1 &&
        queryTokens.every(
          (queryToken) => fields.any((field) => field.contains(queryToken)),
        )) {
      return 3;
    }
    return null;
  }

  int? fuzzyScore(List<String> queryTokens) {
    var distance = 0;
    var usedApproximation = false;
    for (final queryToken in queryTokens) {
      if (tokens.any((token) => token.contains(queryToken))) continue;
      if (!_canFuzzyMatch(queryToken)) return null;
      int? best;
      for (final token in tokens) {
        final maximumDistance = _maximumEditDistance(queryToken);
        final candidate = _boundedEditDistance(
          queryToken,
          token,
          maximumDistance,
        );
        if (candidate != null && (best == null || candidate < best)) {
          best = candidate;
        }
      }
      if (best == null) return null;
      usedApproximation = true;
      distance += best;
    }
    return usedApproximation ? 10 + distance : null;
  }
}

class _ScoredTrack {
  const _ScoredTrack(this.track, this.position, this.score, this.exact);

  final PlaylistTrackSummary track;
  final int position;
  final int score;
  final bool exact;
}

String normalizePlaylistSearchText(String value) {
  final buffer = StringBuffer();
  var pendingSeparator = false;
  for (final rawRune in value.trim().toLowerCase().runes) {
    final rune = rawRune >= 0xff01 && rawRune <= 0xff5e
        ? rawRune - 0xfee0
        : rawRune;
    final folded = _foldedLatin[rune];
    if (folded != null) {
      if (pendingSeparator && buffer.isNotEmpty) buffer.write(' ');
      buffer.write(folded);
      pendingSeparator = false;
    } else if (_isSearchRune(rune)) {
      if (pendingSeparator && buffer.isNotEmpty) buffer.write(' ');
      buffer.writeCharCode(rune);
      pendingSeparator = false;
    } else {
      pendingSeparator = true;
    }
  }
  return buffer.toString();
}

bool _isSearchRune(int rune) =>
    rune >= 0x30 && rune <= 0x39 ||
    rune >= 0x61 && rune <= 0x7a ||
    rune >= 0x3400 && rune <= 0x9fff ||
    rune >= 0x3040 && rune <= 0x30ff ||
    rune >= 0xac00 && rune <= 0xd7af;

bool _canFuzzyMatch(String token) =>
    token.length >= 4 &&
    token.length <= 64 &&
    token.codeUnits.every(
      (unit) => unit >= 0x61 && unit <= 0x7a || unit >= 0x30 && unit <= 0x39,
    );

int _maximumEditDistance(String token) => token.length >= 8 ? 2 : 1;

int? _boundedEditDistance(String left, String right, int maximum) {
  if ((left.length - right.length).abs() > maximum || right.length > 64) {
    return null;
  }
  final rows = List.generate(
    left.length + 1,
    (row) => List<int>.filled(right.length + 1, 0),
  );
  for (var row = 0; row <= left.length; row += 1) {
    rows[row][0] = row;
  }
  for (var column = 0; column <= right.length; column += 1) {
    rows[0][column] = column;
  }
  for (var row = 1; row <= left.length; row += 1) {
    for (var column = 1; column <= right.length; column += 1) {
      final substitution =
          rows[row - 1][column - 1] +
          (left.codeUnitAt(row - 1) == right.codeUnitAt(column - 1) ? 0 : 1);
      var distance = substitution;
      final insertion = rows[row][column - 1] + 1;
      final deletion = rows[row - 1][column] + 1;
      if (insertion < distance) distance = insertion;
      if (deletion < distance) distance = deletion;
      if (row > 1 &&
          column > 1 &&
          left.codeUnitAt(row - 1) == right.codeUnitAt(column - 2) &&
          left.codeUnitAt(row - 2) == right.codeUnitAt(column - 1)) {
        final transposition = rows[row - 2][column - 2] + 1;
        if (transposition < distance) distance = transposition;
      }
      rows[row][column] = distance;
    }
  }
  final distance = rows[left.length][right.length];
  return distance <= maximum ? distance : null;
}

String _fingerprint(PlaylistTrackSummary track) => [
  track.providerId,
  track.opaqueId,
  track.title,
  track.subtitle ?? '',
  ...track.artistNames,
  track.albumTitle ?? '',
].join('\u0000');

const _foldedLatin = <int, String>{
  0x00e0: 'a',
  0x00e1: 'a',
  0x00e2: 'a',
  0x00e3: 'a',
  0x00e4: 'a',
  0x00e5: 'a',
  0x00e7: 'c',
  0x00e8: 'e',
  0x00e9: 'e',
  0x00ea: 'e',
  0x00eb: 'e',
  0x00ec: 'i',
  0x00ed: 'i',
  0x00ee: 'i',
  0x00ef: 'i',
  0x00f1: 'n',
  0x00f2: 'o',
  0x00f3: 'o',
  0x00f4: 'o',
  0x00f5: 'o',
  0x00f6: 'o',
  0x00f9: 'u',
  0x00fa: 'u',
  0x00fb: 'u',
  0x00fc: 'u',
  0x00fd: 'y',
  0x00ff: 'y',
};
