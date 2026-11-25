import 'dart:typed_data';

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
  final List<PlaylistTrackSummary> _sourceTracks = [];
  final List<String?> _fingerprints = [];
  final Uint8List _prev2 = Uint8List(65);
  final Uint8List _prev1 = Uint8List(65);
  final Uint8List _curr = Uint8List(65);
  int? _collectionGeneration;
  int _version = 0;
  int _cachedVersion = -1;
  String? _cachedQuery;
  PlaylistTrackSearchResult _cachedResult = const PlaylistTrackSearchResult();

  void update(List<PlaylistTrackSummary> tracks, {int? collectionGeneration}) {
    final existingLength = _entries.length;
    var appendOnly = tracks.length >= existingLength;
    if (appendOnly && existingLength > 0) {
      if (collectionGeneration != null &&
          collectionGeneration == _collectionGeneration) {
        appendOnly =
            identical(tracks[0], _sourceTracks[0]) &&
            identical(
              tracks[existingLength - 1],
              _sourceTracks[existingLength - 1],
            );
      } else {
        for (var index = 0; index < existingLength; index += 1) {
          final incoming = tracks[index];
          final previous = _sourceTracks[index];
          if (identical(incoming, previous)) continue;
          final previousFingerprint = _fingerprints[index] ??= _fingerprint(
            previous,
          );
          if (_fingerprint(incoming) != previousFingerprint) {
            appendOnly = false;
            break;
          }
        }
      }
    }
    if (appendOnly && tracks.length == existingLength) {
      _collectionGeneration = collectionGeneration;
      return;
    }
    if (!appendOnly) {
      _entries.clear();
      _sourceTracks.clear();
      _fingerprints.clear();
    }
    for (var index = _entries.length; index < tracks.length; index += 1) {
      final track = tracks[index];
      _entries.add(_IndexedTrack(track, index));
      _sourceTracks.add(track);
      _fingerprints.add(null);
    }
    if (_entries.length != tracks.length) {
      _entries.removeRange(tracks.length, _entries.length);
      _sourceTracks.removeRange(tracks.length, _sourceTracks.length);
      _fingerprints.removeRange(tracks.length, _fingerprints.length);
    }
    _collectionGeneration = collectionGeneration;
    _version += 1;
  }

  PlaylistTrackSearchResult search(String rawQuery) {
    final query = normalizePlaylistSearchText(rawQuery);
    if (query.isEmpty) return const PlaylistTrackSearchResult();
    if (_cachedVersion == _version && _cachedQuery == query) {
      return _cachedResult;
    }

    final queryTokens = query.split(' ');
    final queryTokenCount = queryTokens.length;
    final tokenCanFuzzy = List<bool>.generate(
      queryTokenCount,
      (index) => _canFuzzyMatch(queryTokens[index]),
      growable: false,
    );
    final tokenMaxDistance = List<int>.generate(
      queryTokenCount,
      (index) => _maximumEditDistance(queryTokens[index]),
      growable: false,
    );
    final anyFuzzyEligible = tokenCanFuzzy.any((eligible) => eligible);

    final matches = <_ScoredTrack>[];
    for (var i = 0; i < _entries.length; i += 1) {
      final entry = _entries[i];
      final exactScore = entry.exactScore(query, queryTokens);
      if (exactScore != null) {
        matches.add(
          _ScoredTrack(entry.track, entry.position, exactScore, true),
        );
        continue;
      }
      if (!anyFuzzyEligible) continue;
      final fuzzyScore = _fuzzyScore(
        entry,
        queryTokens,
        tokenCanFuzzy,
        tokenMaxDistance,
      );
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
    var exactMatchCount = 0;
    for (var i = 0; i < matches.length; i += 1) {
      if (matches[i].exact) exactMatchCount += 1;
    }
    _cachedVersion = _version;
    _cachedQuery = query;
    _cachedResult = PlaylistTrackSearchResult(
      tracks: List.unmodifiable([for (final match in matches) match.track]),
      exactMatchCount: exactMatchCount,
    );
    return _cachedResult;
  }

  int? _fuzzyScore(
    _IndexedTrack entry,
    List<String> queryTokens,
    List<bool> tokenCanFuzzy,
    List<int> tokenMaxDistance,
  ) {
    final tokens = entry.tokens;
    var distance = 0;
    var usedApproximation = false;
    for (var q = 0; q < queryTokens.length; q += 1) {
      final queryToken = queryTokens[q];
      var contained = false;
      for (var t = 0; t < tokens.length; t += 1) {
        if (tokens[t].contains(queryToken)) {
          contained = true;
          break;
        }
      }
      if (contained) continue;
      if (!tokenCanFuzzy[q]) return null;
      final maximumDistance = tokenMaxDistance[q];
      int? best;
      for (var t = 0; t < tokens.length; t += 1) {
        final candidate = _boundedEditDistance(
          queryToken,
          tokens[t],
          maximumDistance,
        );
        if (candidate != null && (best == null || candidate < best)) {
          best = candidate;
          if (best == 1) break;
        }
      }
      if (best == null) return null;
      usedApproximation = true;
      distance += best;
    }
    return usedApproximation ? 10 + distance : null;
  }

  int? _boundedEditDistance(String left, String right, int maximum) {
    final leftLength = left.length;
    final rightLength = right.length;
    if ((leftLength - rightLength).abs() > maximum || rightLength > 64) {
      return null;
    }
    if (maximum == 1) {
      return _editDistanceAtMostOne(left, right);
    }
    return _editDistanceWithBuffers(left, right, maximum);
  }

  int? _editDistanceAtMostOne(String left, String right) {
    final leftLength = left.length;
    final rightLength = right.length;
    if (leftLength == rightLength) {
      var mismatch = -1;
      for (var i = 0; i < leftLength; i += 1) {
        if (left.codeUnitAt(i) != right.codeUnitAt(i)) {
          mismatch = i;
          break;
        }
      }
      if (mismatch == -1) return 0;
      // Single substitution check.
      var substitution = true;
      for (var i = mismatch + 1; i < leftLength; i += 1) {
        if (left.codeUnitAt(i) != right.codeUnitAt(i)) {
          substitution = false;
          break;
        }
      }
      if (substitution) return 1;
      // Adjacent transposition check.
      if (mismatch + 1 < leftLength &&
          left.codeUnitAt(mismatch) == right.codeUnitAt(mismatch + 1) &&
          left.codeUnitAt(mismatch + 1) == right.codeUnitAt(mismatch)) {
        for (var i = mismatch + 2; i < leftLength; i += 1) {
          if (left.codeUnitAt(i) != right.codeUnitAt(i)) return null;
        }
        return 1;
      }
      return null;
    }

    // Length difference is strictly 1 (insertion or deletion).
    final shorter = leftLength < rightLength ? left : right;
    final longer = leftLength < rightLength ? right : left;
    final shortLength = shorter.length;
    var mismatch = 0;
    while (mismatch < shortLength &&
        shorter.codeUnitAt(mismatch) == longer.codeUnitAt(mismatch)) {
      mismatch += 1;
    }
    for (var i = mismatch; i < shortLength; i += 1) {
      if (shorter.codeUnitAt(i) != longer.codeUnitAt(i + 1)) return null;
    }
    return 1;
  }

  int? _editDistanceWithBuffers(String left, String right, int maximum) {
    final leftLength = left.length;
    final rightLength = right.length;
    final prev2 = _prev2;
    final prev1 = _prev1;
    final curr = _curr;
    for (var column = 0; column <= rightLength; column += 1) {
      prev1[column] = column;
    }
    var prevRowMin = 0;
    for (var row = 1; row <= leftLength; row += 1) {
      final leftChar = left.codeUnitAt(row - 1);
      final leftPrevChar = row > 1 ? left.codeUnitAt(row - 2) : -1;
      curr[0] = row;
      var rowMin = row;
      for (var column = 1; column <= rightLength; column += 1) {
        final rightChar = right.codeUnitAt(column - 1);
        var distance = prev1[column - 1] + (leftChar == rightChar ? 0 : 1);
        final insertion = curr[column - 1] + 1;
        final deletion = prev1[column] + 1;
        if (insertion < distance) distance = insertion;
        if (deletion < distance) distance = deletion;
        if (row > 1 &&
            column > 1 &&
            leftChar == right.codeUnitAt(column - 2) &&
            leftPrevChar == rightChar) {
          final transposition = prev2[column - 2] + 1;
          if (transposition < distance) distance = transposition;
        }
        curr[column] = distance;
        if (distance < rowMin) rowMin = distance;
      }
      if (rowMin > maximum && prevRowMin > maximum) {
        return null;
      }
      prevRowMin = rowMin;
      for (var column = 0; column <= rightLength; column += 1) {
        prev2[column] = prev1[column];
        prev1[column] = curr[column];
      }
    }
    final distance = prev1[rightLength];
    return distance <= maximum ? distance : null;
  }
}

class _IndexedTrack {
  factory _IndexedTrack(PlaylistTrackSummary track, int position) {
    final fields = <String>[];
    final tokenSet = <String>{};
    void addRaw(String? raw) {
      if (raw == null || raw.isEmpty) return;
      final normalized = normalizePlaylistSearchText(raw);
      if (normalized.isEmpty) return;
      fields.add(normalized);
      for (final token in normalized.split(' ')) {
        if (token.isNotEmpty) tokenSet.add(token);
      }
    }

    addRaw(track.title);
    addRaw(track.subtitle);
    for (var i = 0; i < track.artistNames.length; i += 1) {
      addRaw(track.artistNames[i]);
    }
    addRaw(track.albumTitle);
    return _IndexedTrack._(
      track,
      position,
      List.unmodifiable(fields),
      List.unmodifiable(tokenSet),
    );
  }

  const _IndexedTrack._(this.track, this.position, this.fields, this.tokens);

  final PlaylistTrackSummary track;
  final int position;
  final List<String> fields;
  final List<String> tokens;

  int? exactScore(String query, List<String> queryTokens) {
    var best = 4;
    for (var i = 0; i < fields.length; i += 1) {
      final field = fields[i];
      if (field == query) return 0;
      if (best > 1 && field.startsWith(query)) {
        best = 1;
      } else if (best > 2 && field.contains(query)) {
        best = 2;
      }
    }
    if (best < 4) return best;
    if (queryTokens.length > 1) {
      for (var q = 0; q < queryTokens.length; q += 1) {
        final queryToken = queryTokens[q];
        var matched = false;
        for (var i = 0; i < fields.length; i += 1) {
          if (fields[i].contains(queryToken)) {
            matched = true;
            break;
          }
        }
        if (!matched) return null;
      }
      return 3;
    }
    return null;
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
